#!/data/data/com.termux/files/usr/bin/bash
# One-command setup for a fresh Termux (from F-Droid). In Termux:
#
#   curl -fsSLo setup.sh https://raw.githubusercontent.com/Grypium/phone-assistant/main/setup.sh && bash setup.sh
#
# Updates Termux, clones this repo to ~/phone-assistant, installs Claude Code (claude-code-android), then starts
# Claude with instructions to finish the setup (CLAUDE.md). Safe to re-run.
set -u
REPO="${PA_REPO:-https://github.com/Grypium/phone-assistant}"
DIR="${PA_DIR:-$HOME/phone-assistant}"
CC_INSTALLER="https://raw.githubusercontent.com/ferrumclaudepilgrim/claude-code-android/main/install.sh"
say(){ printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
die(){ printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[ -n "${TERMUX_VERSION:-}" ] || die "Run this inside the Termux app."
[ "$(uname -m)" = aarch64 ] || die "Needs a 64-bit phone (uname -m says $(uname -m))."
[ -z "${CLAUDECODE:-}" ] || die "Run this in a plain Termux session, not inside Claude Code."

say "1/3 Updating Termux packages"
export DEBIAN_FRONTEND=noninteractive
pkg update -y || die "pkg update failed. Check your connection (or run termux-change-repo) and try again."
apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confnew full-upgrade
pkg install -y git curl jq >/dev/null || die "couldn't install git"

say "2/3 Getting phone-assistant"
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull -q --ff-only || echo "   (couldn't update $DIR, using it as is)"
else git clone -q "$REPO" "$DIR" || die "clone failed"; fi
chmod +x "$DIR"/install.sh "$DIR"/bin/* 2>/dev/null
echo "   $DIR"

say "3/3 Claude Code"
if command -v claude >/dev/null && claude --version >/dev/null 2>&1; then
  echo "   already installed: $(claude --version)"
else
  echo "   Using the community installer claude-code-android (official Claude Code binary, patched for Termux):"
  echo "   https://github.com/ferrumclaudepilgrim/claude-code-android"
  f="$PREFIX/tmp/claude-code-android-install.sh"
  curl -fsSL "$CC_INSTALLER" -o "$f" || die "download failed"
  bash "$f" || die "Claude Code install failed. See the messages above, then re-run: bash setup.sh"
  hash -r
  command -v claude >/dev/null || die "claude isn't on PATH. Open a new Termux session and re-run: bash setup.sh"
fi

cat <<EOF

Starting Claude. Sign in if it asks (it shows a link to open), then it sets up the rest
and tells you when it needs you (one pairing code from Settings).

EOF
cd "$HOME"   # the claude-code-android launcher only works when started from ~
exec claude "Set up phone-assistant on this phone: read $DIR/CLAUDE.md and follow it."
