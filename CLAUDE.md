# Setting up phone-assistant (instructions for Claude)

You're running in Termux on the user's phone, most likely started by `setup.sh`. The user has done only two things:
installed Termux (normally from F-Droid) and run setup.sh. Everything else is your job. Make it easy for them: do
everything you can yourself, and when you need them, give one short, concrete instruction at a time.

The only things the user has to do:
1. Turn on Developer options and Wireless debugging, and read you a pairing code (step B).
2. Reopen Termux if it doesn't come back by itself after the add-ons install (step D).
3. Optionally, add home-screen widgets and try the voice assistant.

## Rules
- Run `claude` only from `~`: the launcher fails in other directories (`preload not found ./.local/share/claude/setdns.js`).
  When you call `claude -p` yourself, `cd ~` first.
- `install.sh` is idempotent: re-run it after fixing anything. Run it with stdin from /dev/null; it never prompts then.
- Until the Termux:API app is installed (step D), `termux-*` commands hang. Don't call them before that.
- Never use `pkill -f` / `killall` with broad patterns: they can kill your own shell. Kill by PID.
- Installing Termux add-ons closes every Termux session, this one included. Only do it as described in step D.
- Don't change Android settings beyond what install.sh does without asking. Don't commit or push unless asked.

## A. Start (tell the user the plan in 3–4 lines first)
Say it takes ~15 minutes and you'll need them once, for a pairing code in Settings. Then:
```bash
uname -m; echo "$TERMUX_VERSION"            # aarch64, a version
pkg install -y android-tools >/dev/null      # adb, needed for pairing
cd ~/phone-assistant && nohup ./install.sh --no-addons </dev/null > logs/install-1.log 2>&1 &
```
The installer's step 1 (packages, wake word models, building whisper.cpp) takes ~10 minutes. Let it run in the
background while you do the pairing with the user. Check `logs/install-1.log` now and then.

## B. ADB pairing (the user does this on screen)
ADB to the phone itself lets setup switch off Android's process killers, install the Termux add-ons, read the lock
state, and operate apps. One step at a time:
1. Settings → About phone → Software information → tap **Build number** 7 times (on Pixels: About phone → Build
   number). Enter the PIN if asked. "You are now a developer."
2. Settings → Developer options (on Samsung: at the bottom of Settings) → **Wireless debugging** ON. It needs Wi-Fi.
   If it says "no IP available", turn Wi-Fi or Wireless debugging off and on.
3. Tap the words **Wireless debugging** to open it → **Pair device with pairing code**.
   Tip: open Termux and Settings side by side in split screen, otherwise the code disappears when they switch apps.
4. Ask them to tell you the **IP address & port** and the **6-digit code** from that dialog. (The pairing port differs
   from the one on the main Wireless debugging screen.)
```bash
adb pair IP:PORT CODE && ~/phone-assistant/bin/adb-self IP
adb -s localhost:5555 shell echo ok
```
`adb-self` finds the connect port by scanning and arms `localhost:5555`, so ADB keeps working without Wi-Fi until the
next reboot. If pairing fails: the code expires after a minute or two, so ask for a fresh one.

## C. Finish the base install
Wait for the background installer to finish (`tail logs/install-1.log` shows `6/6`, or no install.sh process is
left). Fix any `!` lines. Then run it again, now with ADB available. This applies the Android settings (steps 3–5)
and stops before the add-ons:
```bash
cd ~/phone-assistant && ./install.sh --no-addons </dev/null
```
After this, every new Termux session runs inside tmux, and tmux sessions survive Termux being killed.

## D. Termux add-ons (Termux:API, Termux:Boot, Termux:Widget)
`install.sh` downloads them from the same source as the user's Termux (checking the signatures) and installs them over
ADB. Installing them closes every Termux session, **including this conversation**. This conversation isn't in tmux,
so register it to be reopened first:
```bash
cd ~/phone-assistant
bin/keepalive adopt "Termux restarted after installing the add-ons. Continue the phone-assistant setup at step E of ~/phone-assistant/CLAUDE.md."
```
Tell the user: "I'm installing the Termux add-ons now. Termux will close and come back by itself in about 30 seconds,
and I'll continue. If it doesn't reopen, just open Termux." Then:
```bash
./install.sh --yes </dev/null
```
The install runs on the phone's side, so it finishes after Termux is killed. It opens Termux:Boot once (that enables
it), then reopens Termux. The new session restores this conversation with the prompt above.
If you're still running after it finishes (Termux wasn't killed), run `bin/keepalive adopt --cancel` and go on.

## E. Verify and start the assistant
```bash
cd ~/phone-assistant
adb -s localhost:5555 shell pm list packages | grep termux    # termux, .api, .boot, .widget
timeout 15 termux-wifi-connectioninfo | head -3             # Termux:API works (JSON)
./install.sh </dev/null | tail -8                           # everything ✓
bin/assistant start; sleep 10; tail -3 logs/wake.log         # "started model=hey_jarvis"
bin/ask "say hello in one short sentence"                    # speaks out loud (no mic)
```
Self-test the whole voice path without the user talking. The phone's own speaker can trigger the wake word:
```bash
termux-tts-speak -s MUSIC "Hey Jarvis, what is two plus two?"; sleep 15
tail -3 logs/wake.log; tail -1 logs/hear.log; tail -2 logs/conversation.log
```
Expect "wake detected", a transcript like 'What is 2+2?', and a CLAUDE: line. If termux-* commands hang, run
`bin/heal-api` and retry.

## F. Hand over
Tell the user, briefly:
- Say **"Hey Jarvis, …"** in one breath, even with the screen locked. To interrupt a reply, say "stop" (unlocked),
  or "Hey Jarvis" (locked), or tap ⏹ in the notification.
- Optional: home screen → long-press → Widgets → Termux:Widget → "Talk to Claude" / "Start assistant".
- Their Termux sessions and Claude conversations now survive Android killing Termux and reboots.
- Settings: `~/phone-assistant/config.sh` (model, wake word, chime, autostart). Their own extra voice instructions
  (e.g. folders it must not touch) go in `~/phone-assistant/ASSISTANT.local.md`, which isn't in git.
- After a reboot, ADB needs Wireless debugging + Wi-Fi once: run `adb-self` (or the assistant does it at boot when
  Wi-Fi is on).

## Troubleshooting
| Symptom | Fix |
|---|---|
| termux-* commands hang | Termux:API missing or stuck: `bin/heal-api` (needs ADB), or force-stop Termux:API in Settings |
| Wake listener hears nothing | `pactl list short sources` should list `OpenSL_ES_source`; mic: `adb -s localhost:5555 shell pm grant com.termux android.permission.RECORD_AUDIO` |
| `adb-self` "not found" | Wireless debugging off, or a different Wi-Fi network: toggle it and re-run; re-pair if the pairing was reset |
| add-on "signature doesn't match" | their Termux isn't from F-Droid or GitHub (e.g. Google Play): add-ons must come from the same source |
| Claude errors in `logs/claude-errors.log` | `cd ~ && claude -p hi` to check Claude itself works / is signed in |
| Sessions killed in the background | re-run `./install.sh </dev/null` (re-applies the Android settings) |

Logs: `logs/` (install, wake, hear, speak, conversation, claude-errors, keepalive). Architecture: README.md.
