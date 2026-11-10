#!/usr/bin/env bash
# Extract CrealityPrint AppImages for Solus (and similar hosts that lack
# libdeflate / need Mesa libgbm instead of minigbm).
#
# Usage:
#   ./extract-crealityprint.sh FILE.AppImage [FILE2.AppImage ...]
#   ./extract-crealityprint.sh --all
#   ./extract-crealityprint.sh --download latest
#   ./extract-crealityprint.sh --download v7.3.1
#   ./extract-crealityprint.sh --all --set-default V7.3.1.6378
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == *"Programs/CrealityPrint"* ]]; then
  DEFAULT_BASE="$SCRIPT_DIR"
else
  DEFAULT_BASE="$HOME/Programs/CrealityPrint"
fi
BASE="${CREALITY_BASE:-$DEFAULT_BASE}"
mkdir -p "$BASE"
LIBDIR="${CREALITY_LIBDIR:-$HOME/.local/lib/crealityprint}"
BINDIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APPDIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
GBM_LIB="${GBM_LIB:-/usr/lib64/libgbm.so.1.0.0}"
GBM_DRI="${GBM_DRI:-/usr/lib64/gbm/dri_gbm.so}"
LIBDEFLATE_TAG="${LIBDEFLATE_TAG:-v1.22}"
GH_REPO="${CREALITY_GH_REPO:-CrealityOfficial/CrealityPrint}"

SET_DEFAULT=""
DO_ALL=0
DOWNLOAD_SPEC=""
APPIMAGES=()

usage() {
  cat << EOF
Extract CrealityPrint AppImages (Solus patches: libdeflate + Mesa libgbm).

Usage:
  $(basename "$0") FILE.AppImage [FILE2.AppImage ...]
  $(basename "$0") --all
  $(basename "$0") --download latest
  $(basename "$0") --download v7.3.1
  $(basename "$0") --download 7.2.1 --set-default V7.2.1.5476
  $(basename "$0") ~/Downloads/CrealityPrint-V7.*.AppImage

Options:
  --download SPEC       wget AppImage from GitHub (latest | v7.3.1 | 7.3.1)
  --all                 Extract every *.AppImage in $BASE
  --set-default VER     Point 'crealityprint' launcher at VER (e.g. V7.3.1.6378)
  -h, --help            Show this help
EOF
}

log()  { printf '==> %s\n' "$*" >&2; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) DO_ALL=1; shift ;;
    --download)
      [[ $# -ge 2 ]] || die "--download needs latest or a tag like v7.3.1"
      DOWNLOAD_SPEC="$2"; shift 2
      ;;
    --set-default)
      [[ $# -ge 2 ]] || die "--set-default needs a version like V7.3.1.6378"
      SET_DEFAULT="$2"; shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; APPIMAGES+=("$@"); break ;;
    -*) die "unknown option: $1" ;;
    *) APPIMAGES+=("$1"); shift ;;
  esac
done

if [[ "$DO_ALL" -eq 1 ]]; then
  shopt -s nullglob
  APPIMAGES+=("$BASE"/*.AppImage)
  shopt -u nullglob
fi

[[ ${#APPIMAGES[@]} -gt 0 || -n "$SET_DEFAULT" || -n "$DOWNLOAD_SPEC" ]] || {
  usage
  exit 1
}

version_from_name() {
  local name="$1"
  # Prefer full build id: V7.3.1.6378
  if [[ "$name" =~ (V[0-9]+(\.[0-9]+)+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

normalize_release_tag() {
  local spec="$1"
  if [[ "$spec" == "latest" ]]; then
    printf 'latest\n'
    return 0
  fi
  # Accept 7.3.1, v7.3.1, V7.3.1
  spec="${spec#v}"
  spec="${spec#V}"
  printf 'v%s\n' "$spec"
}

# Pick the best x86_64 Release AppImage from a GitHub release JSON file.
# Prints: name<TAB>browser_download_url
pick_appimage_asset() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json, re, sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assets = data.get("assets") or []
cands = []
for a in assets:
    name = a.get("name") or ""
    url = a.get("browser_download_url") or ""
    if not name.endswith(".AppImage"):
        continue
    if "x86_64" not in name:
        continue
    if "aarch64" in name or "arm64" in name:
        continue
    # Prefer generic Release builds over ubuntu*/Beta/wayland variants.
    score = 0
    low = name.lower()
    if re.search(r"crealityprint-v\d", low):
        score += 100
    if "release" in low:
        score += 20
    if "beta" in low or "wayland" in low:
        score -= 50
    if "ubuntu" in low:
        score -= 30
    m = re.search(r"V(\d+(?:\.\d+)+)", name)
    ver = m.group(1) if m else "0"
    cands.append((score, ver, name, url))

if not cands:
    sys.exit(2)

def ver_key(v):
    return [int(x) if x.isdigit() else 0 for x in v.split(".")]

cands.sort(key=lambda t: (t[0], ver_key(t[1]), t[2]))
name, url = cands[-1][2], cands[-1][3]
print(f"{name}\t{url}")
PY
}

download_appimage() {
  local spec="$1"
  command -v wget >/dev/null || die "wget is required for --download"
  command -v python3 >/dev/null || die "python3 is required for --download"

  local tag api_url json picked name url out
  tag="$(normalize_release_tag "$spec")"
  if [[ "$tag" == "latest" ]]; then
    api_url="https://api.github.com/repos/${GH_REPO}/releases/latest"
  else
    api_url="https://api.github.com/repos/${GH_REPO}/releases/tags/${tag}"
  fi

  log "Fetching release metadata ($tag) from $GH_REPO"
  json="$(mktemp /tmp/creality-release-XXXXXX.json)"
  if ! wget -qO "$json" --header='Accept: application/vnd.github+json' "$api_url"; then
    rm -f "$json"
    die "failed to fetch release metadata: $api_url"
  fi

  if ! picked="$(pick_appimage_asset "$json")"; then
    rm -f "$json"
    die "no x86_64 AppImage found in release $tag"
  fi
  rm -f "$json"

  name="${picked%%$'\t'*}"
  url="${picked#*$'\t'}"
  out="$BASE/$name"

  if [[ -f "$out" ]]; then
    log "Already downloaded: $out"
  else
    log "Downloading $name"
    wget --show-progress -O "$out.partial" "$url"
    mv -f "$out.partial" "$out"
  fi
  chmod +x "$out"
  printf '%s\n' "$out"
}

ensure_libdeflate() {
  if [[ -f "$LIBDIR/libdeflate.so.0" ]]; then
    return 0
  fi
  log "Building libdeflate ($LIBDEFLATE_TAG) into $LIBDIR"
  command -v cmake >/dev/null && command -v gcc >/dev/null && command -v make >/dev/null \
    || die "cmake/gcc/make required to build libdeflate"
  command -v git >/dev/null || die "git required to fetch libdeflate"

  mkdir -p "$LIBDIR"
  local tmp
  tmp="$(mktemp -d /tmp/libdeflate-build-XXXXXX)"
  trap 'rm -rf "'"$tmp"'"' RETURN
  git clone --depth 1 --branch "$LIBDEFLATE_TAG" \
    https://github.com/ebiggers/libdeflate.git "$tmp/src" >/dev/null
  cmake -S "$tmp/src" -B "$tmp/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLIBDEFLATE_BUILD_STATIC_LIB=OFF \
    -DLIBDEFLATE_BUILD_GZIP=OFF >/dev/null
  cmake --build "$tmp/build" -j"$(nproc)" >/dev/null
  cp -a "$tmp/build/libdeflate.so.0" "$LIBDIR/"
  ln -sfn libdeflate.so.0 "$LIBDIR/libdeflate.so"
  rm -rf "$tmp"
  trap - RETURN
}

ensure_gbm() {
  [[ -f "$GBM_LIB" ]] || die "Mesa libgbm not found at $GBM_LIB (set GBM_LIB=...)"
  [[ -f "$GBM_DRI" ]] || warn "dri_gbm.so not found at $GBM_DRI (WebKit may fail)"
}

patch_extracted() {
  local dest="$1"
  mkdir -p "$dest/usr/lib/gbm"

  cp -a "$LIBDIR/libdeflate.so.0" "$dest/usr/lib/"
  ln -sfn libdeflate.so.0 "$dest/usr/lib/libdeflate.so"

  # Prefer Mesa GBM over host minigbm (missing gbm_bo_create_with_modifiers2).
  cp -a "$GBM_LIB" "$dest/usr/lib/libgbm.so.1.0.0"
  ln -sfn libgbm.so.1.0.0 "$dest/usr/lib/libgbm.so.1"
  if [[ -f "$GBM_DRI" ]]; then
    cp -a "$GBM_DRI" "$dest/usr/lib/gbm/"
  fi

  chmod +x "$dest/AppRun" 2>/dev/null || true
  chmod +x "$dest/bin/CrealityPrint" 2>/dev/null || true
}

check_libs() {
  local dest="$1"
  local missing
  missing="$(
    LD_LIBRARY_PATH="$dest/bin:$dest/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
      ldd "$dest/bin/CrealityPrint" 2>/dev/null | grep 'not found' || true
  )"
  if [[ -n "$missing" ]]; then
    warn "missing shared libs in $(basename "$dest"):"
    printf '%s\n' "$missing" >&2
    if printf '%s\n' "$missing" | grep -q 'libwebkit2gtk-4\.0'; then
      warn "This build wants WebKitGTK 4.0 (Ubuntu 20.04). Solus only ships 4.1 — use Distrobox or skip this version."
    fi
    return 1
  fi
  return 0
}

install_launcher() {
  local ver="$1"
  local dest="$2"
  mkdir -p "$BINDIR" "$APPDIR"

  local launcher="$BINDIR/crealityprint-${ver}"
  cat > "$launcher" << EOF
#!/usr/bin/env bash
APP="$dest/AppRun"
DETACH=0
ARGS=()
for arg in "\$@"; do
  case "\$arg" in
    -d|--detach) DETACH=1 ;;
    *) ARGS+=("\$arg") ;;
  esac
done
if [[ "\$DETACH" -eq 1 ]]; then
  setsid -f "\$APP" "\${ARGS[@]}" >/dev/null 2>&1
  exit 0
fi
exec "\$APP" "\${ARGS[@]}"
EOF
  chmod +x "$launcher"

  local icon
  icon="$(find "$dest" -path '*/icons/hicolor/192x192/apps/*.png' 2>/dev/null | head -1 || true)"
  [[ -n "$icon" ]] || icon="$(find "$dest" -name 'CrealityPrint.png' 2>/dev/null | head -1 || true)"

  cat > "$APPDIR/crealityprint-${ver}.desktop" << EOF
[Desktop Entry]
Name=Creality Print ${ver}
Comment=CrealityPrint slicer ${ver}
Exec=${dest}/AppRun %F
Icon=${icon:-crealityprint}
Type=Application
Categories=Graphics;3DGraphics;Engineering;
Terminal=false
MimeType=model/stl;application/sla;
EOF

  log "launcher: crealityprint-${ver}"
}

set_default_launcher() {
  local ver="$1"
  local dest="$BASE/$ver"
  [[ -x "$dest/AppRun" ]] || die "default target missing: $dest/AppRun"

  mkdir -p "$BINDIR" "$APPDIR"
  cat > "$BINDIR/crealityprint" << EOF
#!/usr/bin/env bash
APP="$dest/AppRun"
DETACH=0
ARGS=()
for arg in "\$@"; do
  case "\$arg" in
    -d|--detach) DETACH=1 ;;
    *) ARGS+=("\$arg") ;;
  esac
done
if [[ "\$DETACH" -eq 1 ]]; then
  setsid -f "\$APP" "\${ARGS[@]}" >/dev/null 2>&1
  exit 0
fi
exec "\$APP" "\${ARGS[@]}"
EOF
  chmod +x "$BINDIR/crealityprint"

  local icon
  icon="$(find "$dest" -path '*/icons/hicolor/192x192/apps/*.png' 2>/dev/null | head -1 || true)"

  cat > "$APPDIR/crealityprint.desktop" << EOF
[Desktop Entry]
Name=Creality Print
Comment=CrealityPrint slicer (${ver})
Exec=${dest}/AppRun %F
Icon=${icon:-crealityprint}
Type=Application
Categories=Graphics;3DGraphics;Engineering;
Terminal=false
MimeType=model/stl;application/sla;
EOF
  log "default 'crealityprint' -> $ver"
}

extract_one() {
  local appimage="$1"
  [[ -f "$appimage" ]] || die "not a file: $appimage"
  appimage="$(readlink -f "$appimage")"

  local base name ver dest tmp
  name="$(basename "$appimage")"
  ver="$(version_from_name "$name")" || die "could not parse version from: $name"
  dest="$BASE/$ver"

  log "Extracting $ver from $name"
  chmod +x "$appimage"

  tmp="$(mktemp -d /tmp/creality-extract-XXXXXX)"
  (
    cd "$tmp"
    "$appimage" --appimage-extract >/dev/null
    [[ -d squashfs-root ]] || die "extract failed for $name"
  )

  rm -rf "$dest"
  mkdir -p "$dest"
  # Move extracted tree (including hidden files)
  shopt -s dotglob nullglob
  mv "$tmp"/squashfs-root/* "$dest/"
  shopt -u dotglob nullglob
  rm -rf "$tmp"

  patch_extracted "$dest"
  if check_libs "$dest"; then
    log "OK libs for $ver"
  fi
  install_launcher "$ver" "$dest"
  printf '%s\n' "$ver"
}

if [[ -n "$DOWNLOAD_SPEC" ]]; then
  APPIMAGES+=("$(download_appimage "$DOWNLOAD_SPEC")")
fi

# Only need host patches when actually extracting
if [[ ${#APPIMAGES[@]} -gt 0 ]]; then
  ensure_libdeflate
  ensure_gbm
fi

EXTRACTED=()
for ai in "${APPIMAGES[@]+"${APPIMAGES[@]}"}"; do
  [[ -n "$ai" ]] || continue
  EXTRACTED+=("$(extract_one "$ai")")
done

if [[ -n "$SET_DEFAULT" ]]; then
  set_default_launcher "$SET_DEFAULT"
elif [[ ${#EXTRACTED[@]} -eq 1 ]]; then
  # Single extract: make it the default automatically
  set_default_launcher "${EXTRACTED[0]}"
fi

log "Done. Versions in $BASE:"
for d in "$BASE"/V*; do
  [[ -d "$d" ]] || continue
  if [[ -x "$d/AppRun" ]]; then
    printf '  %s\n' "$(basename "$d")"
  fi
done
