# Setting up phone-assistant (instructions for Claude)

The user has done the manual steps in README.md: Termux (plus, ideally, Termux:API / Boot / Widget) installed from
the same source, and Claude Code installed with claude-code-android. You're running inside Termux on their phone. Your
job: get everything else working, talking the user through the few things only they can do on screen.

Before starting, tell the user briefly what will happen (see the steps below) and that it takes ~10–20 minutes, mostly
building whisper.cpp.

## Rules
- Run `claude` only from `~`: the launcher fails in other directories (`preload not found ./.local/share/claude/setdns.js`).
  When you call `claude -p` yourself, `cd ~` first.
- `install.sh` is idempotent: re-run it after fixing anything. Run it with stdin from /dev/null; it never prompts then.
- Never use `pkill -f` / `killall` with broad patterns: they can kill your own shell. Kill by PID.
- **Installing a Termux add-on closes every Termux session, including this one.** Never install one without warning
  the user first, and only after step C below.
- Don't change Android settings beyond what install.sh does without asking.
- Don't commit, push or delete anything in the repo unless asked.

## Steps

### A. Check prerequisites
```bash
uname -m                                   # aarch64
echo $TERMUX_VERSION
pm list packages 2>/dev/null | grep termux # may be empty without ADB; see below
termux-wifi-connectioninfo                 # hangs/fails if the Termux:API *app* isn't installed
```
If `termux-wifi-connectioninfo` doesn't return JSON within ~10 s, the Termux:API app is missing (the `termux-api`
package alone isn't enough). Ask the user to install Termux:API (and Boot, Widget) from the same place they got
Termux (README step 1) *before* continuing. It's much easier now than later, when installing them kills sessions.

### B. Packages, models, whisper.cpp (no user action)
```bash
cd ~/phone-assistant && ./install.sh --no-addons </dev/null
```
Step 1 takes the longest (pkg installs, openWakeWord models, whisper.cpp build + base.en/tiny.en models). Run it in
the background if your tool times out, and watch for `✓`/`!` lines. Fix any `!` and re-run.
Step 2 will say "not paired" the first time: that's expected.

### C. ADB pairing (the user does this on screen)
ADB to the phone itself lets the assistant switch off Android's process killers, read the lock state, and operate apps.
Walk the user through it:
1. Settings → About phone → Software information → tap **Build number** 7 times (enables Developer options).
2. Settings → Developer options → **Wireless debugging** ON (needs Wi-Fi; if it says "no IP available", toggle Wi-Fi
   or Wireless debugging off and on).
3. Tap **Pair device with pairing code**. Tip: use split screen (Termux + Settings), or the code disappears when they
   switch apps.
4. Ask them for the **IP address & port** shown in that dialog and the **6-digit code**. The pairing port is NOT the
   port shown on the main Wireless debugging screen.
Then:
```bash
./install.sh --no-addons --pair IP:PORT CODE </dev/null
```
This pairs, finds the connect port by scanning, and arms `localhost:5555`, so ADB keeps working without Wi-Fi until
the next reboot. Steps 3–5 then run with ADB. Verify: `adb -s localhost:5555 shell echo ok`.

### D. Add-ons (only if any are missing)
If step 6 of install.sh lists add-ons to install, warn the user: **Android will close every Termux session, including
this conversation.** Sessions started after step 4 run in tmux and come back automatically when Termux is reopened,
but this conversation started before that. Ask them to:
1. open a **new Termux session** (swipe from the left edge → New session); it starts inside tmux now,
2. run `claude --continue` there, and continue the setup from that session,
3. then run `./install.sh --yes </dev/null`.
After it's done: they open **Termux:Boot** once.

### E. Start and test the assistant
```bash
bin/assistant start          # wake word listener + notification
bin/assistant status
tail -5 logs/wake.log        # "started model=hey_jarvis"
bin/ask "say hello in one short sentence"   # should speak out loud (text in, no mic)
```
Self-test without the user talking. The phone's own speaker can trigger the wake word:
```bash
termux-tts-speak -s MUSIC "Hey Jarvis, what is two plus two?"; sleep 15
tail -3 logs/wake.log; tail -1 logs/hear.log; tail -2 logs/conversation.log
```
Expect "wake detected", a transcript like 'What is 2+2?', and a CLAUDE: line. Then ask the user to try with their own
voice: "Hey Jarvis, …" in one breath, with the screen locked too, and "stop" while it's talking (unlocked), or
"Hey Jarvis" while it's talking (locked).

### F. Finish
- Have the user add the Termux:Widget shortcuts to the home screen ("Talk to Claude", "Start assistant").
- Mention `config.sh` (model, wake word, chime, autostart) and `ASSISTANT.local.md` (their own additions to the voice
  instructions, not in git: e.g. folders or projects the voice assistant must not touch).
- Optional: a reboot test. After the reboot, Termux and the assistant should come back on their own (Termux:Boot).
  ADB over localhost needs Wireless debugging and Wi-Fi once after each reboot: `~/phone-assistant/bin/adb-self` (also linked as `~/bin/adb-self`).

## Troubleshooting
| Symptom | Fix |
|---|---|
| termux-* commands hang | Termux:API app missing or stuck: `bin/heal-api` (needs ADB) or force-stop Termux:API in Settings |
| No speech heard by the wake listener | `pactl list short sources` should show `OpenSL_ES_source`; mic permission: `adb -s localhost:5555 shell pm grant com.termux android.permission.RECORD_AUDIO` |
| `adb-self` "not found" | Wireless debugging off, or the phone changed Wi-Fi network: toggle it, re-run; re-pair if the pairing was reset |
| Claude errors in `logs/claude-errors.log` | run `cd ~ && claude -p hi` to see if Claude itself works / is logged in |
| Sessions killed in the background | re-run `./install.sh </dev/null` (re-applies the Android settings) |

Logs: `logs/` (wake, hear, speak, conversation, claude-errors). State: `state/`. Architecture: README.md.
