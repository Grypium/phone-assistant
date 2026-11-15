# Copied to config.sh by install.sh (config.sh is not committed). Edit config.sh, not this file.

# Voice assistant
export ASSISTANT_AUTOSTART=1       # start the wake word listener at boot
export ASSISTANT_MODEL=sonnet      # model for voice replies
export ASSISTANT_ACK=chime         # how it shows it's listening: chime | voice | vibrate | off
export ASSISTANT_ACK_TEXT="Yes?"   # what it says when ASSISTANT_ACK=voice
export STT_ENGINE=whisper          # whisper (offline, works locked) | android (Google, unlocked only)
export WHISPER_MODEL=base.en       # base.en (accurate, ~1.5 s) | tiny.en (~0.8 s)
export WAKE_MODEL=hey_jarvis       # openWakeWord model: hey_jarvis, alexa, hey_mycroft (custom "hey claude" later)
export WAKE_THRESHOLD=0.6          # higher = fewer false wakes, more misses

# Session keepalive
export RESTORE_SESSIONS=1          # recreate tmux sessions after Termux is killed / phone reboots
export AUTO_CONTINUE_AGENTS=0      # 1 = restored Claude sessions are told to keep working, not just reopened
