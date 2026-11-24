#!/usr/bin/env bash
# Builds every package in packages/ into a legacy-compatible .deb, copies any
# prebuilt .debs from debs/, and generates a flat Cydia repo in _site/.
#
# Needs: dpkg-dev (dpkg-deb, dpkg-scanpackages), apt-utils (apt-ftparchive), bzip2, gzip.
# Runs on Linux / WSL (GNU sed). The GitHub Actions workflow runs it for you.
set -euo pipefail
shopt -s nullglob

cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source <(sed 's/\r$//' repo.conf)

OUT="${OUT:-_site}"

# ---- Work out the public URL of the repo -----------------------------------
if [ -n "${REPO_URL_OVERRIDE:-}" ]; then
  REPO_URL="$REPO_URL_OVERRIDE"
elif [ -f CNAME ]; then
  # Custom domain: use plain http so very old iOS (no modern TLS) can connect.
  REPO_URL="http://$(tr -d ' \r\n' < CNAME)"
else
  REPO_URL="${REPO_URL:-}"   # set by the workflow from GitHub Pages
fi
REPO_URL="${REPO_URL%/}"
if [ -z "$REPO_URL" ]; then
  echo "error: could not determine repo URL; set REPO_URL_OVERRIDE in repo.conf or REPO_URL env" >&2
  exit 1
fi
echo "Repo URL: $REPO_URL"

rm -rf "$OUT"
mkdir -p "$OUT/debs"

# ---- 1. Build packages/<id>/ into .debs ------------------------------------
for dir in packages/*/; do
  dir="${dir%/}"
  [ -f "$dir/DEBIAN/control" ] || { echo "skip $dir (no DEBIAN/control)"; continue; }

  stage="$(mktemp -d)"
  cp -R "$dir/." "$stage/"
  find "$stage" -name '.gitkeep' -delete

  # Files edited on Windows get CRLF; dpkg on iOS chokes on that.
  find "$stage/DEBIAN" -type f -exec sed -i 's/\r$//' {} +
  sed -i "s|@REPO_URL@|$REPO_URL|g" "$stage/DEBIAN/control"
  # Guarantee the control file ends with a newline.
  [ -n "$(tail -c1 "$stage/DEBIAN/control")" ] && echo >> "$stage/DEBIAN/control"

  # Git on Windows loses the executable bit, so set permissions explicitly.
  find "$stage" -type d -exec chmod 0755 {} +
  find "$stage" -type f -exec chmod 0644 {} +
  for s in preinst postinst prerm postrm extrainst_; do
    [ -f "$stage/DEBIAN/$s" ] && chmod 0755 "$stage/DEBIAN/$s"
  done
  find "$stage" -type f \( -path '*/bin/*' -o -path '*/sbin/*' -o -path '*/libexec/*' -o -name '*.sh' \) \
    -not -path "$stage/DEBIAN/*" -exec chmod 0755 {} +

  field() { awk -v k="$1" -F': *' '$1==k {print $2; exit}' "$stage/DEBIAN/control"; }
  pkg="$(field Package)"; ver="$(field Version)"; arch="$(field Architecture)"
  deb="$OUT/debs/${pkg}_${ver}_${arch}.deb"

  # -Zgzip: legacy dpkg on iOS 3-6 cannot read xz/zstd-compressed debs.
  dpkg-deb --root-owner-group -Zgzip -b "$stage" "$deb" >/dev/null
  echo "built $deb"
  rm -rf "$stage"
done

# ---- 2. Prebuilt .debs dropped into debs/ ----------------------------------
for f in debs/*.deb; do
  cp "$f" "$OUT/debs/"
  echo "added $f"
done

# ---- 3. Package index -------------------------------------------------------
(
  cd "$OUT"
  dpkg-scanpackages -m debs /dev/null > Packages 2>/dev/null
  bzip2 -9 -k -f Packages   # what old Cydia asks for first
  gzip  -9 -k -f -n Packages
)

# ---- 4. Release file --------------------------------------------------------
{
  echo "Origin: $ORIGIN"
  echo "Label: $LABEL"
  echo "Suite: stable"
  echo "Version: 1.0"
  echo "Codename: ios"
  echo "Architectures: iphoneos-arm"
  echo "Components: main"
  echo "Description: $DESCRIPTION"
  (cd "$OUT" && apt-ftparchive release .)
} > "$OUT/Release.tmp"
mv "$OUT/Release.tmp" "$OUT/Release"

# ---- 5. Static site (landing page, icon, depictions) ------------------------
cp -R site/. "$OUT/"
[ -f CNAME ] && cp CNAME "$OUT/CNAME"
find "$OUT" -name '*.html' -exec sed -i \
  -e "s|@REPO_URL@|$REPO_URL|g" \
  -e "s|@REPO_LABEL@|$LABEL|g" \
  -e "s|@REPO_DESCRIPTION@|$DESCRIPTION|g" {} +

echo
echo "Done. $(grep -c '^Package:' "$OUT/Packages") package(s) in $OUT/"
echo "Add this source in Cydia: $REPO_URL/"
