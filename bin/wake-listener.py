#!/data/data/com.termux/files/usr/bin/python3
"""Always-on wake word listener.

Mic -> PulseAudio (OpenSL ES source, works with the screen locked) -> ffmpeg (16 kHz mono)
-> openWakeWord. On detection it keeps recording from the same stream, so "Hey Jarvis, count to 50" works in one
breath (the chime only confirms; pausing after "Hey Jarvis" works too). The recording ends after a short silence
and is handed to bin/ask; listening for the wake word resumes when ask is done.
Env: WAKE_MODEL (default hey_jarvis), WAKE_THRESHOLD (default 0.6), HEAR_START_TIMEOUT (6), HEAR_MAX (20),
     HEAR_END_SILENCE (0.8).
Pause without stopping: touch ~/phone-assistant/state/wake-paused
"""
import collections, os, sys, time, subprocess, wave, warnings
warnings.filterwarnings("ignore")
P = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(P, "lib"))  # sklearn stub (openwakeword imports it, we don't use it)
import numpy as np
from openwakeword.model import Model

MODEL = os.environ.get("WAKE_MODEL", "hey_jarvis")
THRESH = float(os.environ.get("WAKE_THRESHOLD", "0.6"))
STATE = os.path.join(P, "state"); os.makedirs(STATE, exist_ok=True)
LOG = os.path.join(P, "logs", "wake.log")
CHUNK = 1280  # 80 ms at 16 kHz
RATE, FRAME = 16000, 480                       # VAD works on 30 ms frames
START_TIMEOUT = float(os.environ.get("HEAR_START_TIMEOUT", "6"))
MAX_LEN = float(os.environ.get("HEAR_MAX", "20"))
END_SIL = float(os.environ.get("HEAR_END_SILENCE", "0.8"))
PREROLL = 0.4                                  # audio kept from before detection, in case you didn't pause at all
TAIL = 0.3                                     # speech in the first 0.3 s after detection is the end of "Jarvis"
CMD_WAV = os.path.join(STATE, "wake-command.wav")

def log(msg):
    with open(LOG, "a") as f:
        f.write(time.strftime("%F %T ") + msg + "\n")

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout

def ensure_pulse():
    if subprocess.run("pulseaudio --check", shell=True).returncode != 0:
        sh("pulseaudio --start --exit-idle-time=-1"); time.sleep(1)
    if "OpenSL_ES_source" not in sh("pactl list short sources"):
        sh("pactl load-module module-sles-source")

def open_stream():
    ensure_pulse()
    # Capture at the source's native format (asking parec for 16k mono returned silence), resample in ffmpeg.
    parec = subprocess.Popen(["parec", "-d", "OpenSL_ES_source", "--raw",
                              "--format=s16le", "--rate=44100", "--channels=2"],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    ff = subprocess.Popen(["ffmpeg", "-v", "error", "-f", "s16le", "-ar", "44100", "-ac", "2", "-i", "-",
                           "-ar", "16000", "-ac", "1", "-f", "s16le", "-"],
                          stdin=parec.stdout, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    parec.stdout.close()
    return parec, ff

def close_stream(parec, ff):
    for p in (parec, ff):
        try: p.kill(); p.wait(timeout=2)
        except Exception: pass

def chime():
    """Confirm we heard the wake word, without waiting for it to finish."""
    ack = os.environ.get("ASSISTANT_ACK", "chime")
    if ack == "off":
        return
    subprocess.Popen(["termux-vibrate", "-d", "50", "-f"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if ack in ("chime", "voice"):              # "voice" would talk over you, so it's a chime here too
        subprocess.Popen(["paplay", os.path.join(P, "assets", "listening.wav")],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def record_command(ff, vad, preroll):
    """Keep reading the open stream until you've finished talking. Returns the wav path, or None if you didn't
    say anything after the wake word."""
    frames = []                                # 30 ms frames after detection
    pending = b""
    started = None; last_voice = None; run = 0; peak = 0.0
    vad.reset_states()
    while True:
        buf = ff.stdout.read(FRAME * 2)
        if len(buf) < FRAME * 2:
            break
        frames.append(buf); now = len(frames) * FRAME / RATE
        prob = float(vad.predict(np.frombuffer(buf, np.int16)))
        peak = max(peak, prob)
        if prob >= 0.5:
            run += 1; last_voice = now
            if started is None and run >= 3 and now > TAIL:
                started = now - run * FRAME / RATE
        elif prob < 0.3:
            run = 0
        if started is None and now > START_TIMEOUT:
            break
        if started is not None and now - last_voice > END_SIL:
            break
        if now > MAX_LEN:
            break
    log(f"command: recorded {len(frames) * FRAME / RATE:.1f}s after wake, peak speech {peak:.2f}, "
        + (f"speech from {started:.2f}s" if started is not None else "no speech"))
    if started is None:
        return None
    if started < 0.6:                          # you didn't pause: the request may have begun during detection
        audio = b"".join(preroll) + b"".join(frames)    # (bin/hear --strip-wake removes the "Jarvis" this keeps)
    else:
        audio = b"".join(frames[int((started - 0.25) * RATE / FRAME):])
    with wave.open(CMD_WAV, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(audio)
    return CMD_WAV


def busy():
    """True while bin/ask is running (it holds state/ask.lock). A leftover 'busy' file from a crash doesn't count."""
    import fcntl
    try:
        with open(os.path.join(STATE, "ask.lock"), "a") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(f, fcntl.LOCK_UN)
            return False
    except OSError:
        return True


SPEAKING = os.path.join(STATE, "speaking-wake")      # bin/speak: "a reply is playing, wake word = interrupt"
INTERRUPT = os.path.join(STATE, "wake-interrupt")    # we write this when the wake word is heard during a reply


def want_mic():
    """Listen when idle, and while a reply is playing on a locked phone. Release the mic while bin/ask is recording
    or transcribing your request (or when paused)."""
    if os.path.exists(os.path.join(STATE, "wake-paused")):
        return False
    return (not busy()) or os.path.exists(SPEAKING)


def main():
    model = Model(wakeword_models=[MODEL], inference_framework="onnx")
    from openwakeword.vad import VAD
    vad = VAD()
    log(f"started model={MODEL} threshold={THRESH}")
    ask = None
    recent = collections.deque(maxlen=int(PREROLL * RATE / CHUNK) + 1)   # last ~0.4 s of audio
    while True:
        if not want_mic():
            time.sleep(0.2); continue
        parec, ff = open_stream()
        model.reset()
        warmup = 0
        triggered = False; cmd = None
        recent.clear()
        try:
            while True:
                buf = ff.stdout.read(CHUNK * 2)
                if len(buf) < CHUNK * 2:
                    log("stream ended, restarting"); time.sleep(2); break
                if not want_mic():
                    break
                recent.append(buf)
                score = float(model.predict(np.frombuffer(buf, np.int16))[MODEL])
                warmup += 1
                if warmup > 20 and score >= THRESH:
                    if busy():                      # a reply is playing: interrupt it, keep listening
                        log(f"wake detected during reply score={score:.2f} -> interrupt")
                        open(INTERRUPT, "w").close()
                        model.reset(); warmup = 0
                        continue
                    log(f"wake detected score={score:.2f}")
                    chime()
                    triggered = True
                    try:
                        cmd = record_command(ff, vad, list(recent))
                    except Exception as e:
                        log(f"command recording failed: {e!r}")
                    break
        finally:
            close_stream(parec, ff)
        if triggered and cmd is None:          # wake word, then nothing: back to waiting
            subprocess.Popen(["termux-vibrate", "-d", "40"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            continue
        if triggered:
            ask = subprocess.Popen([os.path.join(P, "bin", "ask"), "--audio", cmd])
            for _ in range(50):                    # wait until ask holds its lock, so we don't grab the mic back
                if busy() or ask.poll() is not None:
                    break
                time.sleep(0.1)

if __name__ == "__main__":
    main()
