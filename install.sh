#!/data/data/com.termux/files/usr/bin/bash
# phone-assistant installer for Termux. Safe to re-run; every step skips what's already done.
#
#   ./install.sh                          interactive
#   ./install.sh --yes                    don't ask before the step that restarts Termux
#   ./install.sh --pair IP:PORT CODE      pair ADB without prompting (from Wireless debugging > Pair with code)
#   ./install.sh --no-addons              skip step 6 (installing add-ons closes every Termux session)
# Non-interactive runs (e.g. Claude running it) never prompt: without --pair the ADB steps are skipped with a hint.
#
# What it sets up:
#   1. packages + Python wake word engine
#   2. ADB to the phone itself (Wireless debugging pairing, then localhost:5555 so it works off Wi-Fi)
#   3. Android settings so Termux isn't killed: no phantom-process limit, Doze allowlist, exempt standby bucket
#   4. session keepalive: shells run in tmux; after a kill or reboot sessions and Claude conversations come back
#   5. voice assistant: notification, home-screen shortcuts, start at boot
#   6. Termux add-ons (API, Widget, Boot) from the same source as your Termux. LAST, because installing one
#      makes Android kill every Termux session (they share one app ID). Sessions come back thanks to step 4.
set -u
P="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
YES=0; ADDONS=1; PAIR_HP=; PAIR_CODE=
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --no-addons) ADDONS=0 ;;
    --pair) PAIR_HP="${2:-}"; PAIR_CODE="${3:-}"; shift 2 ;;
    *) echo "unknown option: $1"; sed -n 4,9p "$0"; exit 2 ;;
  esac; shift
done
TTY=0; [ -t 0 ] && TTY=1
ADB="adb -s localhost:5555"
say(){ printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok(){ printf '   \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '   \033[33m!\033[0m %s\n' "$*"; }
have_pkg(){ $ADB shell pm list packages --user 0 2>/dev/null | grep -qx "package:$1"; }

[ -n "${TERMUX_VERSION:-}" ] || { echo "Run this inside Termux."; exit 1; }
mkdir -p "$P/logs" "$P/state"
chmod +x "$P"/bin/* "$P"/boot/* "$P"/tests/* 2>/dev/null

# ---------------------------------------------------------------- 1
say "1/6 Packages"
pkg install -y termux-api android-tools apksigner ffmpeg pulseaudio tmux git curl \
  python python-numpy python-onnxruntime >/dev/null 2>&1 && ok "pkg packages" || warn "pkg install had errors"
python3 -c "import openwakeword" 2>/dev/null || PYTHONPATH="$P/lib" python3 -c "import openwakeword" 2>/dev/null \
  || { pip install -q --no-deps openwakeword==0.6.0 tqdm && pip install -q requests; }
PYTHONPATH="$P/lib" python3 -W ignore -c "
from openwakeword.utils import download_models; download_models(['hey_jarvis','alexa','hey_mycroft','hey_rhasspy'])" >/dev/null 2>&1 \
  && ok "openWakeWord + models" || warn "openWakeWord setup failed"
if [ ! -x "$P/vendor/whisper.cpp/build/bin/whisper-cli" ]; then   # offline speech-to-text (works when locked)
  pkg install -y cmake clang >/dev/null 2>&1
  mkdir -p "$P/vendor"; [ -d "$P/vendor/whisper.cpp" ] || git clone -q --depth 1 https://github.com/ggml-org/whisper.cpp "$P/vendor/whisper.cpp"
  ( cd "$P/vendor/whisper.cpp" && cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_OPENMP=OFF >/dev/null 2>&1 \
      && cmake --build build -j8 --target whisper-cli >/dev/null 2>&1 )
fi
for m in base.en tiny.en; do [ -f "$P/vendor/whisper.cpp/models/ggml-$m.bin" ] || \
  ( cd "$P/vendor/whisper.cpp" && sh models/download-ggml-model.sh $m >/dev/null 2>&1 ); done
[ -x "$P/vendor/whisper.cpp/build/bin/whisper-cli" ] && ok "whisper.cpp + models" || warn "whisper.cpp build failed"
[ -f "$P/config.sh" ] || { cp "$P/config.example.sh" "$P/config.sh"; ok "created config.sh"; }

# ---------------------------------------------------------------- 2
say "2/6 ADB to this phone"
mkdir -p "$HOME/bin"; ln -sf "$P/bin/adb-self" "$HOME/bin/adb-self"
if "$P/bin/adb-self" >/dev/null 2>&1; then ok "connected (localhost:5555)"
else
  echo "   Settings > About phone > Software information > tap Build number 7x (enables Developer options)"
  echo "   Settings > Developer options > Wireless debugging: ON (needs Wi-Fi) > Pair device with pairing code"
  echo "   Tip: split screen Termux + Settings, or the code disappears."
  hp=$PAIR_HP; code=$PAIR_CODE
  if [ -z "$hp" ] && [ $TTY = 1 ]; then read -rp "   Pairing IP:port: " hp; read -rp "   6-digit code: " code; fi
  if [ -n "$hp" ]; then
    adb pair "$hp" "$code" && "$P/bin/adb-self" "${hp%:*}" && ok "paired and connected" || warn "ADB not connected; re-run later"
  else warn "not paired: re-run with --pair IP:PORT CODE"; fi
fi
ADB_OK=0; $ADB get-state >/dev/null 2>&1 && ADB_OK=1

# ---------------------------------------------------------------- 3
say "3/6 Stop Android from killing Termux"
if [ $ADB_OK = 1 ]; then
  $ADB shell settings put global settings_enable_monitor_phantom_procs false
  $ADB shell device_config set_sync_disabled_for_tests persistent
  $ADB shell device_config put activity_manager max_phantom_processes 2147483647
  ok "phantom process killer off"
  for pk in com.termux com.termux.api com.termux.boot com.termux.widget; do
    have_pkg $pk || continue
    $ADB shell dumpsys deviceidle whitelist +$pk >/dev/null; $ADB shell am set-standby-bucket $pk active; $ADB shell cmd appops set $pk RUN_ANY_IN_BACKGROUND allow
  done
  ok "battery optimization off for Termux"
  $ADB shell pm grant com.termux android.permission.RECORD_AUDIO 2>/dev/null && ok "mic permission for Termux (wake word)"
  $ADB shell appops set com.termux SYSTEM_ALERT_WINDOW allow && ok "\"Appear on top\" for Termux (needed to reopen tabs at boot)"
else warn "skipped (no ADB). Manually: Developer options > Disable child process restrictions; Battery > Unrestricted;"
     warn "Apps > Termux > Appear on top: on"; fi

# ---------------------------------------------------------------- 4
say "4/6 Session keepalive"
MARK="# phone-assistant"
grep -q "$MARK" "$HOME/.bashrc" 2>/dev/null || \
  printf '\n%s\n[ -f "%s/shell/termux-init.sh" ] && PA_HOME="%s" . "%s/shell/termux-init.sh"\n' "$MARK" "$P" "$P" "$P" >> "$HOME/.bashrc"
ok "~/.bashrc: new sessions run inside tmux (set PA_NO_TMUX=1 to skip)"
grep -q "$MARK" "$HOME/.tmux.conf" 2>/dev/null || cat >> "$HOME/.tmux.conf" <<EOF

$MARK
source-file "$P/shell/tmux.conf"
set-hook -g session-closed "run-shell -b '$P/bin/keepalive save'"
set-hook -g session-created "run-shell -b '$P/bin/keepalive save'"
EOF
ok "~/.tmux.conf"
grep -q '^allow-external-apps *= *true' "$HOME/.termux/termux.properties" 2>/dev/null || \
  { mkdir -p "$HOME/.termux"; echo "allow-external-apps = true" >> "$HOME/.termux/termux.properties"; }

# ---------------------------------------------------------------- 5
say "5/6 Voice assistant"
mkdir -p "$HOME/.shortcuts/tasks" "$HOME/.termux/boot"; chmod 700 "$HOME/.shortcuts"
printf '#!/data/data/com.termux/files/usr/bin/bash\nexec "%s/bin/ask"\n' "$P" > "$HOME/.shortcuts/tasks/Talk to Claude"
printf '#!/data/data/com.termux/files/usr/bin/bash\n"%s/bin/assistant" start\n' "$P" > "$HOME/.shortcuts/tasks/Start assistant"
printf '#!/data/data/com.termux/files/usr/bin/bash\n"%s/bin/assistant" config\n' "$P" > "$HOME/.shortcuts/tasks/Assistant settings"
sed "s|^P=\"\$HOME/phone-assistant\"|P=\"$P\"|" "$P/boot/phone-assistant" > "$HOME/.termux/boot/phone-assistant"
chmod +x "$HOME/.shortcuts/tasks/"* "$HOME/.termux/boot/phone-assistant"
ok "home-screen shortcuts + boot script"

# ---------------------------------------------------------------- 6
say "6/6 Termux add-ons"
[ $ADDONS = 1 ] || { warn "skipped (--no-addons)"; exit 0; }
[ $ADB_OK = 1 ] || { warn "needs ADB; re-run after pairing"; exit 0; }
# Add-ons must be signed with the same key as Termux itself (F-Droid build vs GitHub build).
tmp="$PREFIX/tmp/pa-install"; rm -rf "$tmp"; mkdir -p "$tmp"
$ADB pull "$($ADB shell pm path --user 0 com.termux | head -1 | cut -d: -f2 | tr -d '\r')" "$tmp/termux.apk" >/dev/null 2>&1
CERT=$(apksigner verify --print-certs "$tmp/termux.apk" 2>/dev/null | grep -m1 'SHA-256' | awk '{print $NF}')
SRC=github; apksigner verify --print-certs "$tmp/termux.apk" | grep -q 'O=fdroid.org' && SRC=fdroid
ok "your Termux is the $SRC build"
fetch(){ # $1 package  $2 github repo
  if [ $SRC = fdroid ]; then
    local vc; vc=$(curl -s "https://f-droid.org/api/v1/packages/$1" | python3 -c "import sys,json;print(json.load(sys.stdin)['suggestedVersionCode'])")
    curl -sfL -o "$tmp/$1.apk" "https://f-droid.org/repo/${1}_${vc}.apk"
  else
    local url; url=$(curl -s "https://api.github.com/repos/termux/$2/releases/latest" | python3 -c \
      "import sys,json;print([a['browser_download_url'] for a in json.load(sys.stdin)['assets'] if a['name'].endswith('.apk') and 'github' in a['name']][0])")
    curl -sfL -o "$tmp/$1.apk" "$url"
  fi
  [ "$(apksigner verify --print-certs "$tmp/$1.apk" 2>/dev/null | grep -m1 SHA-256 | awk '{print $NF}')" = "$CERT" ] \
    || { warn "$1: signature doesn't match your Termux, skipping"; rm -f "$tmp/$1.apk"; return 1; }
}
todo=()
for pair in com.termux.api:termux-api com.termux.widget:termux-widget com.termux.boot:termux-boot; do
  pk=${pair%%:*}; have_pkg "$pk" && { ok "$pk already installed"; continue; }
  fetch "$pk" "${pair#*:}" && todo+=("$pk")
done
API_PERMS="CAMERA ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION RECORD_AUDIO READ_CONTACTS READ_SMS SEND_SMS READ_CALL_LOG READ_PHONE_STATE CALL_PHONE POST_NOTIFICATIONS BODY_SENSORS NEARBY_WIFI_DEVICES"
grants="for p in $API_PERMS; do pm grant com.termux.api android.permission.\$p; done; for k in com.termux.api com.termux.boot com.termux.widget; do dumpsys deviceidle whitelist +\$k; am set-standby-bucket \$k active; cmd appops set \$k RUN_ANY_IN_BACKGROUND allow; done"
if [ ${#todo[@]} -eq 0 ]; then
  have_pkg com.termux.api && $ADB shell "$grants" >/dev/null 2>&1; ok "Termux:API permissions granted"
  say "Done."; exit 0
fi
echo; warn "Installing: ${todo[*]}"
warn "Android may close ALL Termux sessions when this happens (Termux:Widget did; Termux:Boot didn't)."
warn "Sessions in tmux are restored when you reopen Termux, Claude conversations too. Sessions opened"
warn "before this setup weren't in tmux; reopen those with: claude --resume"
if [ $YES = 0 ] && [ $TTY = 0 ]; then echo "   Not installing without --yes (non-interactive run)."; exit 0; fi
if [ $YES = 0 ]; then read -rp "   Continue? [y/N] " a; [ "$a" = y ] || [ "$a" = Y ] || { echo "   Skipped. Re-run when ready."; exit 0; }; fi
# Run the install on the phone's side (adb shell) so it finishes even though Termux gets killed.
dev=""; for pk in "${todo[@]}"; do $ADB push "$tmp/$pk.apk" "/data/local/tmp/pa-$pk.apk" >/dev/null; dev="$dev pm install --user 0 /data/local/tmp/pa-$pk.apk; rm /data/local/tmp/pa-$pk.apk;"; done
# Termux:Boot only runs at boot after its app has been opened once; then bring Termux back to the front.
$ADB shell "setsid nohup sh -c 'sleep 2; $dev $grants; am start -n com.termux.boot/.BootActivity; sleep 2; am start -n com.termux/.app.TermuxActivity' > /data/local/tmp/pa-install.log 2>&1 &"
echo "   Installing… (if Termux closes, just reopen it)"
for _ in $(seq 1 60); do $ADB shell cat /data/local/tmp/pa-install.log 2>/dev/null | grep -q TermuxActivity && break; sleep 2; done
$ADB shell cat /data/local/tmp/pa-install.log 2>/dev/null | grep -E 'Success|Failure' | sed 's/^/   /'
$ADB shell rm -f /data/local/tmp/pa-install.log
ok "Optional: add the Termux:Widget shortcuts to your home screen (Talk to Claude, Start assistant)."
