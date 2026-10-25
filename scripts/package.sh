#!/bin/bash
# Empaquette KalisMusic.app (compilé sans signature, en arm64 + arm64e) en :
#   out/KalisMusic-unsigned.ipa                      -> Sideloadly / AltStore / TrollStore / AppSync
#   out/<bundle-id>_<version>_iphoneos-arm64.deb     -> jailbreak rootless (/var/jb), binaire arm64 + arm64e
#
# Le .deb rootless s'appelle « iphoneos-arm64 » pour tous les iPhone (A11 compris) : le binaire qu'il contient
# est « fat » (arm64 + arm64e), et iOS choisit la tranche qui convient à la puce de l'appareil.
# Le .ipa ne garde que arm64 : un arm64e « tiers » n'est accepté que par un système jailbreaké, et un .ipa
# re-signé par Sideloadly / AltStore doit pouvoir démarrer sur un iPhone non jailbreaké.
#
# Variables facultatives :
#   APP=chemin/vers/KalisMusic.app   (défaut : build/Build/Products/Release-iphoneos/KalisMusic.app)
#   REQUIRE_ARM64E=0                 accepter un binaire sans tranche arm64e (défaut : 1 = refuser)
#   IPA_FAT=1                        garder arm64 + arm64e dans le .ipa (défaut : 0 = arm64 seul)
#   ENTITLEMENTS=chemin.entitlements droits donnés par ldid (défaut : Resources/KalisMusic.entitlements)
set -euo pipefail

cd "$(dirname "$0")/.."   # racine du dépôt, d'où que le script soit lancé

APP="${APP:-build/Build/Products/Release-iphoneos/KalisMusic.app}"
ENTITLEMENTS="${ENTITLEMENTS:-Resources/KalisMusic.entitlements}"
REQUIRE_ARM64E="${REQUIRE_ARM64E:-1}"
IPA_FAT="${IPA_FAT:-0}"
PLISTBUDDY="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"

# Pas de fichiers « ._* » (AppleDouble) dans les archives créées sous macOS
export COPYFILE_DISABLE=1

die() { echo "ERREUR : $*" >&2; exit 1; }

for tool in lipo ldid dpkg-deb zip "$PLISTBUDDY"; do
  command -v "$tool" >/dev/null 2>&1 || [ -x "$tool" ] || die "outil introuvable : $tool (brew install ldid dpkg)"
done
[ -d "$APP" ] || die "KalisMusic.app introuvable : $APP (lancez d'abord la compilation)"
[ -f "$ENTITLEMENTS" ] || die "fichier de droits introuvable : $ENTITLEMENTS"

plist() { "$PLISTBUDDY" -c "Print :$1" "$APP/Info.plist"; }

EXEC_NAME="$(plist CFBundleExecutable)"
BUNDLE_ID="$(plist CFBundleIdentifier)"
VERSION="$(plist CFBundleShortVersionString)"
DISPLAY_NAME="$(plist CFBundleDisplayName 2>/dev/null || plist CFBundleName)"
MIN_OS="$(plist MinimumOSVersion 2>/dev/null || echo 16.0)"
BIN="$APP/$EXEC_NAME"
[ -f "$BIN" ] || die "exécutable introuvable : $BIN"

has_arch() { case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }

# --- 0. architectures présentes dans le binaire compilé
ARCHS="$(lipo -archs "$BIN")"
echo "==> $DISPLAY_NAME $VERSION ($BUNDLE_ID), iOS >= $MIN_OS"
echo "==> architectures compilées : $ARCHS"
has_arch "$ARCHS" arm64 || die "il manque la tranche arm64"
if ! has_arch "$ARCHS" arm64e; then
  if [ "$REQUIRE_ARM64E" = "1" ]; then
    die "il manque la tranche arm64e : compilez avec ARCHS=\"arm64 arm64e\" ONLY_ACTIVE_ARCH=NO (ou REQUIRE_ARM64E=0 pour continuer sans)"
  fi
  echo "ATTENTION : pas de tranche arm64e, le .deb ne contiendra que arm64"
fi

clean_bundle() {
  find "$1" -name '.DS_Store' -delete
  find "$1" -name '._*' -delete
  xattr -cr "$1" 2>/dev/null || true
}

rm -rf out stage
mkdir -p out stage

# --- 1. .ipa non signé (le signataire - Sideloadly, AltStore… - le signera lui-même)
IPA_PAYLOAD="stage/ipa/Payload"
mkdir -p "$IPA_PAYLOAD"
cp -R "$APP" "$IPA_PAYLOAD/"
IPA_APP="$IPA_PAYLOAD/$(basename "$APP")"
if [ "$IPA_FAT" != "1" ] && [ "$(echo "$ARCHS" | wc -w | tr -d ' ')" -gt 1 ]; then
  lipo "$IPA_APP/$EXEC_NAME" -thin arm64 -output "$IPA_APP/$EXEC_NAME.arm64"
  mv "$IPA_APP/$EXEC_NAME.arm64" "$IPA_APP/$EXEC_NAME"
  chmod 755 "$IPA_APP/$EXEC_NAME"
fi
clean_bundle "$IPA_APP"
(cd stage/ipa && zip -qryX ../../out/KalisMusic-unsigned.ipa Payload)
echo "==> .ipa : architectures $(lipo -archs "$IPA_APP/$EXEC_NAME")"

# --- 2. .deb rootless : signature « factice » ldid avec les droits jailbreak (toutes les tranches)
DEB="stage/deb"
DEB_APP_DIR="$DEB/var/jb/Applications"
mkdir -p "$DEB_APP_DIR" "$DEB/DEBIAN"
cp -R "$APP" "$DEB_APP_DIR/"
DEB_APP="$DEB_APP_DIR/$(basename "$APP")"
rm -rf "$DEB_APP/_CodeSignature"
clean_bundle "$DEB_APP"

ldid -S"$ENTITLEMENTS" "$DEB_APP/$EXEC_NAME"

DEB_ARCHS="$(lipo -archs "$DEB_APP/$EXEC_NAME")"
[ "$DEB_ARCHS" = "$ARCHS" ] || die "ldid a changé les architectures ($ARCHS -> $DEB_ARCHS)"
ldid -e "$DEB_APP/$EXEC_NAME" | grep -q "platform-application" \
  || die "les droits jailbreak ne sont pas dans le binaire signé"
echo "==> .deb : architectures $DEB_ARCHS, signé avec $ENTITLEMENTS"

INSTALLED_SIZE="$(du -sk "$DEB/var" | cut -f1)"

cat > "$DEB/DEBIAN/control" <<EOF
Package: $BUNDLE_ID
Name: $DISPLAY_NAME
Version: $VERSION
Architecture: iphoneos-arm64
Description: Lecteur de musique inspiré de Musique iOS 7-9 (port iOS de KalisMusic for Android)
Maintainer: KalisMusic
Author: KalisMusic
Section: Multimedia
Depends: firmware (>= $MIN_OS)
Installed-Size: $INSTALLED_SIZE
EOF

APP_NAME="$(basename "$APP")"

cat > "$DEB/DEBIAN/postinst" <<EOF
#!/bin/sh
if [ -x /var/jb/usr/bin/uicache ]; then
  /var/jb/usr/bin/uicache -p /var/jb/Applications/$APP_NAME
elif command -v uicache >/dev/null 2>&1; then
  uicache -p /var/jb/Applications/$APP_NAME
fi
exit 0
EOF

cat > "$DEB/DEBIAN/postrm" <<EOF
#!/bin/sh
if [ -x /var/jb/usr/bin/uicache ]; then
  /var/jb/usr/bin/uicache -u /var/jb/Applications/$APP_NAME >/dev/null 2>&1
elif command -v uicache >/dev/null 2>&1; then
  uicache -u /var/jb/Applications/$APP_NAME >/dev/null 2>&1
fi
exit 0
EOF

# droits des fichiers : dossiers 755, fichiers 644, exécutable et scripts 755
find "$DEB" -type d -exec chmod 755 {} +
find "$DEB" -type f -exec chmod 644 {} +
chmod 755 "$DEB_APP/$EXEC_NAME" "$DEB/DEBIAN/postinst" "$DEB/DEBIAN/postrm"

DEB_FILE="out/${BUNDLE_ID}_${VERSION}_iphoneos-arm64.deb"
dpkg-deb --root-owner-group -Zgzip -b "$DEB" "$DEB_FILE"

echo
dpkg-deb -I "$DEB_FILE" | sed -n '1,20p'
echo
ls -la out
