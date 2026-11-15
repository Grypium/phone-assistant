# Changelog

All notable changes to this project. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [0.3.0] - 2026-11-14

### Added
- **Unlock flow.** When Claude needs the screen and the phone is locked, it says "please unlock your phone…", then
  `bin/need-unlock` wakes the screen, shows the unlock prompt, buzzes, and waits 30 s. If the phone stays locked,
  Claude says to ping it again once unlocked, and the conversation (kept 30 min) picks the task back up.
- **Silent replies.** When there's nothing worth saying ("thanks, that's it"), Claude replies `<silent>`: nothing is
  spoken and the phone gives a short buzz. No more "You're welcome!" or "Anything else?".
- Speech watchdog: if the TTS engine hasn't started talking ~5 s after the first sentence, `bin/speak` restarts
  Termux:API and the engine and replays the reply (checked via `dumpsys audio`; needs ADB).
- `hear.log` records transcription time, thread count and CPU group.
- This changelog.

### Fixed
- **Very slow transcription (25–57 s) while the phone was locked or another app was in front.** Android moves Termux
  to its background CPU group (4 slower cores) and whisper's 6 spin-waiting threads stalled each other (18.8 s vs
  0.9 s with 4 threads). whisper now uses at most 4 threads, never more than the allowed cores.
- A successful but empty reply (e.g. Claude only ran a command) was spoken as "Sorry, I couldn't reach Claude" and
  reset the conversation.
- Background jobs (notification updates, vibration) inherited `ask`'s lock, so a request right after the previous
  one could be refused ("Already listening") and hang on the toast. Those calls now also have timeouts.
- The listening chime no longer waits on the vibration (a stuck Termux:API could block listening).

## [0.2.0] - 2026-11-14

### Added
- **One-command setup.** Install Termux from F-Droid, paste one line (`setup.sh`): it updates Termux, clones the repo,
  installs Claude Code (claude-code-android), and starts Claude with `CLAUDE.md` to finish the setup.
- `CLAUDE.md`: the setup playbook Claude follows. It pairs ADB with the user, runs the installer, installs the
  Termux add-ons itself, starts and self-tests the assistant.
- `keepalive adopt [PROMPT]`: reopen the current (non-tmux) Claude conversation, with its flags and a prompt, the
  next time Termux starts. Setup uses it to survive the add-on install, which kills Termux.
- `install.sh --pair IP:PORT CODE` / `--no-addons`; non-interactive runs never prompt.
- `install.sh` opens Termux:Boot after installing it (it must be opened once to work).

### Changed
- README: new getting-started guide.
- `adb-self [IP]` can use the IP from the pairing address (works before Termux:API is installed).
- Personal voice-assistant rules go in `ASSISTANT.local.md` (not in git).

## [0.1.0] - 2026-11-14

### Added
- **Voice assistant.** "Hey Jarvis" wake word (openWakeWord) or a notification button; offline speech-to-text
  (whisper.cpp, works with the screen locked); Claude answers out loud. It can operate the phone through Termux:API
  and ADB.
  - Say it in one breath ("Hey Jarvis, count to 50"): the wake listener keeps recording into your request.
  - Replies are streamed: the first sentence plays while Claude is still writing. One persistent TTS process, so no
    gap between sentences.
  - Interrupt with "stop" (unlocked), "Hey Jarvis" (locked) or the notification's Stop button; Claude stops too,
    even mid-tool-call.
  - Follow-up questions keep listening; conversation context is kept for 30 minutes.
- **Session keepalive.** Termux shells run in tmux; after Android kills Termux or the phone reboots, sessions and their
  tabs come back, and Claude Code conversations resume with their original flags.
- **ADB to the phone itself** (`adb-self`), kept working without Wi-Fi via `localhost:5555`.
- Android settings so Termux isn't killed (phantom process killer off, battery exemptions), Termux:Boot start-up,
  Termux:Widget shortcuts.
- Idempotent `install.sh`.
