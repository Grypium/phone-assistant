# phone-assistant

Turns an Android phone running Termux into:

1. **A voice assistant with Claude as the brain.** Say a wake word (or tap a button), speak, and Claude answers out loud.
   It can actually operate the phone: Termux:API (flashlight, texts, location, camera…) plus ADB to the phone itself
   (tap/swipe/type in any app, screenshots).
2. **Termux sessions that survive.** Android's process killers are switched off, and if Termux dies anyway
   (reboot, force-stop, add-on install) your sessions come back, including running Claude Code conversations,
   reopened with the same flags they were started with.

## Getting started

You need: a 64-bit Android 11+ phone, Wi-Fi during setup, and a Claude subscription (Pro/Max) or an Anthropic
Console account. About 15 minutes.

**1. Install Termux from F-Droid.** Get it at https://f-droid.org/packages/com.termux/ (either install the F-Droid
app store first from https://f-droid.org, or tap "Download APK" on that page). Allow "install unknown apps" when
Android asks. Don't use the Google Play version: Termux's add-ons, which setup installs for you, only work with a
matching build. Open Termux once and wait for it to finish installing.

**2. Paste this into Termux:**
```bash
curl -fsSLo setup.sh https://raw.githubusercontent.com/Grypium/phone-assistant/main/setup.sh && bash setup.sh
```
It updates Termux, downloads this repo to `~/phone-assistant`, and installs Claude Code. Claude Code doesn't run on
Android out of the box, so this uses the community installer
[claude-code-android](https://github.com/ferrumclaudepilgrim/claude-code-android): it installs Anthropic's official
binary, patched to run in Termux, and keeps it updated. It asks two yes/no questions. Then it starts Claude.

**3. Sign in, and Claude does the rest.** Following [CLAUDE.md](CLAUDE.md), Claude:
- builds the offline speech-to-text and wake word engines
- walks you through turning on **Wireless debugging** and reading it a pairing code (the one thing you do in Settings)
- switches off Android's background killers for Termux
- installs Termux:API, Termux:Boot and Termux:Widget itself. Termux closes and comes back during this, and Claude
  picks up where it left off.
- starts the voice assistant and tests it

Afterwards, optionally add the Termux:Widget shortcuts to your home screen ("Talk to Claude", "Start assistant").

Start `claude` from your home directory (`cd ~`). The claude-code-android launcher currently fails anywhere else with
`preload not found "./.local/share/claude/setdns.js"`.

### Doing it by hand
```bash
pkg install -y git && git clone https://github.com/Grypium/phone-assistant ~/phone-assistant
cd ~/phone-assistant && ./install.sh     # interactive; safe to re-run, skips what's done
```
Options: `--pair IP:PORT CODE` (ADB pairing without prompts), `--no-addons`, `--yes`. Installing the add-ons
closes all Termux sessions once (tmux sessions come back by themselves).

Settings live in `config.sh` (created from `config.example.sh`).

## Voice assistant
- `bin/assistant start|stop|status|wake on|off` — notification with 🎤 Talk / wake toggle / Stop.
- `bin/ask` — one exchange (listen → Claude → speak). `bin/ask "text"` skips the mic; `bin/ask --audio WAV` takes a
  recording made by the wake listener. If Claude's reply ends with a question, it listens again. Conversation context
  carries over for 30 minutes.
- **One breath:** "Hey Jarvis, count to 50" works without waiting for the chime. The wake listener keeps recording
  from the stream it already has open, and the chime + buzz play in the background (`ASSISTANT_ACK` = chime |
  vibrate | off). Pausing after "Hey Jarvis" works too (up to 6 s). `bin/hear --strip-wake` drops the "Jarvis" that
  the recording starts with.
- **Streaming:** `bin/claude-stream` runs Claude with `--output-format stream-json` and passes each sentence to
  `bin/speak -` as soon as it's written, so the first sentence plays while Claude is still writing (about 2 s after
  the request). An interrupt closes the pipe and Claude is killed, even mid-tool-call.
- `bin/hear` — records your request and transcribes it **offline with whisper.cpp** (`vendor/whisper.cpp`, model
  base.en). Works with the phone locked; Android's recognizer (`termux-speech-to-text`) hangs on the lock screen,
  so it's only used if `STT_ENGINE=android`. Ends 0.8 s after you stop talking (`HEAR_END_SILENCE`); gives up if you
  don't start within 6 s. Whisper pads to 30 s of audio unless told otherwise: `-ac` sized to the recording cut a
  short command from 1.1 s to 0.4 s with the same text.
- `bin/speak` — speaks a reply and lets you interrupt:
  - **unlocked**: say "stop" (cancel, quiet, enough, never mind, that's enough…; only short stop phrases). Android's
    recognizer ignores the phone's own speaker, so it hears you over the reply.
  - **locked**: say the wake word ("Hey Jarvis"). The always-on wake listener keeps listening during the reply and
    flags the interrupt; the assistant then listens for your new request.
  - the notification's **⏹ Stop talking** button.
  - One `termux-tts-speak` process is started at once and fed one line per sentence. A process per sentence cost
    ~1 s of silence before each one.
  - On interrupt `bin/heal-api` kills the Termux:API process (via ADB): the speech engine drops its queue and goes
    quiet instantly. Without ADB it mutes the media volume until the queue ends, then restores it.
  - If the engine hangs, it gives up after an estimate of the speaking time and restarts Termux:API.
  - Never force-stop the TTS engine (TTS hangs afterwards) and never run two `termux-tts-speak` at once (both hang).
  - "Is it talking?": `adb shell dumpsys audio | grep 'state:started.*CONTENT_TYPE_SPEECH'`.
- `bin/is-locked` — lock state via ADB (0 locked, 1 unlocked, 2 unknown).
- `bin/wake-listener.py` — always-on wake word, then records the request (releases the mic while `ask` runs, except
  during a reply on a locked phone): PulseAudio OpenSL ES mic → ffmpeg 16 kHz → openWakeWord + Silero VAD
  (about 3% of one core). Default wake word "Hey Jarvis" (pretrained); custom "Hey Claude" is a TODO.
- `ASSISTANT.md` — Claude's instructions for voice replies: what tools exist and what needs a spoken confirmation
  (texts, calls, purchases, deletes…).

## Session keepalive
- Watchdog: the keepalive saver restarts the voice assistant within 15 s if it dies, unless you stopped it.
- `shell/termux-init.sh` (sourced from `~/.bashrc`): every Termux session runs in tmux; `claude` is wrapped so
  each session gets a known conversation id, and its flags are recorded (`bin/claude-args` reads which options take
  values from `claude --help`, so new options work automatically; the prompt itself isn't replayed).
- `bin/keepalive`: snapshots tmux windows every 15 s + on open/close. For panes running Claude it reads the live
  conversation id from Claude Code's own `~/.claude/sessions/<pid>.json` (which records the tmux pane) and the flags
  from `/proc/<pid>/cmdline`, so it stays right after `/resume`, `/clear`, the `--resume` picker, or a `claude`
  started without the wrapper. The wrapper's tags are only a fallback. Then it on the next Termux start (or boot)
  recreates them in the same folders and runs `claude <same flags> --resume <id>`.
  Sessions you close normally (or Claude you exit) are not brought back.
  `AUTO_CONTINUE_AGENTS=1` in config.sh also tells restored agents to keep going.
- **Tabs come back too**: after restoring, each session gets its own Termux tab again, in the original order
  (`keepalive open-tabs`, via Termux's internal `service_execute` intent). Termux only starts a tab's program once
  the tab is shown, so the tmux sessions (and Claude) run in the background right away and each tab attaches when you
  first look at it. Sessions waiting for their tab are marked `@pa_tab_pending` so a new tab doesn't grab them.
  Requires `allow-external-apps = true` in `~/.termux/termux.properties` and "Appear on top" for Termux.
- Escape hatch: `PA_NO_TMUX=1` before opening a session; `bin/keepalive clear` forgets the snapshot.
- `bin/keepalive adopt [PROMPT]`, run from inside Claude Code: reopens *that* conversation (with its flags, plus PROMPT)
  the next time Termux starts, even though it is not in tmux. Setup uses it before installing the add-ons, which
  kills Termux. It is valid for 1 hour; `adopt --cancel` drops it.
- Android side (via ADB, persists across reboots): phantom process killer off, Doze allowlist, exempt standby bucket.

## ADB to the phone itself
- Pair once via Wireless debugging. `bin/adb-self` connects (prefers `localhost:5555`, which keeps working
  **without Wi-Fi**; `adb tcpip 5555` resets on reboot, so after a reboot turn Wireless debugging on once,
  on any Wi-Fi, and run `adb-self` — the boot script tries automatically and notifies you if it can't).
- `adb tcpip` leaves port 5555 open on the current network; connections still need the phone's ADB key approval.

## Things learned the hard way
- **Installing/updating any Termux add-on kills all Termux processes** (shared UID → "permissions revoked").
- Add-ons must be signed like Termux (F-Droid vs GitHub builds). `install.sh` checks the signature.
- Mic: Android pins Termux's RECORD_AUDIO to "while in use" (`appops` override gets reverted), yet recording keeps
  working with the screen off and can even be started while locked (tested Android 17 / One UI, Galaxy S25 Ultra).
  Re-test after OS updates: `tests/lock-listen-test`, or the self-test: play `termux-tts-speak -s MUSIC` while
  recording and compare RMS levels with `ffmpeg -af astats`.
- `termux-speech-to-text` ignores the phone's own speaker (echo cancellation), so it can't be self-tested that way.
- PulseAudio's `module-sles-source` returns silence if you ask `parec` for 16 kHz mono; capture native 44.1k stereo
  and resample with ffmpeg.
- Re-arming ADB after a reboot can't be automated without root: Wireless debugging needs Wi-Fi, and Termux can't
  toggle it itself (even with WRITE_SECURE_SETTINGS granted, `settings`/`content` refuse app UIDs). If Wireless
  debugging says "no IP available", toggle it off and on.
- The phone can't be operated through the UI while it's locked with a PIN. Use Samsung Extend Unlock (trusted
  Bluetooth device / place) rather than storing a PIN.

## Layout
```
install.sh            setup (idempotent)
setup.sh              one-command bootstrap for a fresh Termux (repo + Claude Code, then hands off to Claude)
CLAUDE.md             setup instructions Claude follows
config.example.sh     settings template → config.sh
ASSISTANT.md          Claude's voice-assistant instructions (+ your own ASSISTANT.local.md, not in git)
bin/                  ask, assistant, wake-listener.py, hear, speak, claude-stream, keepalive, claude-args,
                      adb-self, wifi-ip, is-locked, heal-api, shush, wait-wake
assets/               chimes
vendor/               whisper.cpp (cloned and built by install.sh, not in git)
shell/                termux-init.sh (bashrc hook), tmux.conf
boot/                 Termux:Boot script
lib/sklearn           import stub (openWakeWord imports scikit-learn for a feature we don't use)
tests/                hardware tests (mic while locked, ADB without Wi-Fi)
```
