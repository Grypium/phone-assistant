# phone-assistant

Turns an Android phone running Termux into:

1. **A voice assistant with Claude as the brain.** Say a wake word (or tap a button), speak, and Claude answers out loud.
   It can actually operate the phone: Termux:API (flashlight, texts, location, camera…) plus ADB to the phone itself
   (tap/swipe/type in any app, screenshots).
2. **Termux sessions that survive.** Android's process killers are switched off, and if Termux dies anyway
   (reboot, force-stop, add-on install) your sessions come back, including running Claude Code conversations,
   reopened with the same flags they were started with.

## Getting started

Two manual steps get Termux and Claude Code onto the phone. After that, Claude sets up the rest from this repo.

Requirements: a 64-bit Android phone (8 or newer; 11+ recommended for wireless ADB), Wi-Fi for the setup, and a
Claude subscription (Pro/Max) or an Anthropic Console account.

### Step 1: install Termux and its add-ons from F-Droid

Install these four apps, **all from F-Droid**. Add-ons only work when they're signed by the same source as Termux,
and the Google Play build of Termux is a different, incompatible build.

| App | F-Droid page | What it's for |
|---|---|---|
| Termux | https://f-droid.org/packages/com.termux/ | the terminal |
| Termux:API | https://f-droid.org/packages/com.termux.api/ | mic, speech, notifications, vibration, Wi-Fi info |
| Termux:Boot | https://f-droid.org/packages/com.termux.boot/ | starts everything after a reboot |
| Termux:Widget | https://f-droid.org/packages/com.termux.widget/ | home-screen shortcuts ("Talk to Claude") |

1. Install the F-Droid client from https://f-droid.org (or download each APK straight from the pages above).
   Allow "install unknown apps" for your browser / F-Droid when Android asks.
2. If you already have Termux from Google Play, uninstall it first (this deletes its files).
3. Install all four now, before you start working in Termux. Installing an add-on later closes every open Termux
   session.
4. Open Termux once and let it finish "Installing bootstrap packages", then run:
   ```bash
   pkg update -y && pkg upgrade -y
   uname -m            # must print aarch64
   ```
5. Open **Termux:Boot** once (that's what enables it to run at boot).

Already have Termux from GitHub instead? That works too, as long as all add-ons also come from GitHub. The
installer checks the signatures and fetches matching add-ons.

### Step 2: install Claude Code in Termux

Anthropic's Claude Code binary doesn't run on Android out of the box. The community project
[claude-code-android](https://github.com/ferrumclaudepilgrim/claude-code-android) installs the official linux-arm64
build and patches it to run under Termux (glibc-runner). It updates itself once a day. It's a third-party
script: read it first if you like.

In a fresh Termux session (not inside another Claude session):
```bash
curl -fsSL https://raw.githubusercontent.com/ferrumclaudepilgrim/claude-code-android/main/install.sh -o install.sh
bash install.sh
```
It asks two yes/no questions, then downloads ~230 MB (5–10 min). If it reports that the current binary crashes on
your Android version, accept its offer to install the pinned fallback release. Then:
```bash
claude          # sign in when it asks (it prints a URL to open in the browser)
```

### Step 3: let Claude set up the rest
```bash
pkg install -y git
git clone <this repo's URL> ~/phone-assistant
cd ~ && claude
```
Then tell Claude: **"read ~/phone-assistant/CLAUDE.md and set it up"**. It runs `./install.sh`, walks you through ADB
pairing (you read it the pairing code from Settings), starts the assistant, and tests it with you.

Start `claude` from your home directory (`cd ~`). The claude-code-android launcher currently fails anywhere else with
`preload not found "./.local/share/claude/setdns.js"`.

Manual alternative: `cd ~/phone-assistant && ./install.sh`. It's interactive and safe to re-run; it skips whatever's
done. Options: `--pair IP:PORT CODE`, `--yes`, `--no-addons`.

Afterwards: add the **Termux:Widget** shortcuts to your home screen (long-press home → Widgets → Termux:Widget).

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
CLAUDE.md             setup instructions for Claude ("read ~/phone-assistant/CLAUDE.md and set it up")
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
