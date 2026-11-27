#!/bin/bash
# Builds Overreach on a Mac with Xcode and installs it on a cable-connected iPhone, signed with your own
# (free) Apple ID, so Apple Health works. Sideloading tools drop the HealthKit entitlement (ADR-0021).
#
# Run it either way (nothing else to install; it only needs Xcode):
#   curl -fsSL https://raw.githubusercontent.com/droidsam1/overreach/main/scripts/install-from-mac.command | bash
#   or double-click this file in Finder.
#
# Everything it downloads (the source and XcodeGen) goes to a temporary folder that is deleted at the end.
# Run it again within 7 days to renew the app: same Apple ID, same app, data kept.
#
# Options (environment variables): OVERREACH_REF=<branch or tag> (default main), KEEP_CACHE=1 (keep the
# build folder for a faster next run).

set -euo pipefail

# Everything runs inside main(), so `curl … | bash` reads the whole script before any command can read stdin.
main() {
REPO="droidsam1/overreach"
REF="${OVERREACH_REF:-main}"
XCODEGEN_VERSION="2.42.0"
WORK="${TMPDIR:-/tmp}/overreach-installer"
LOG="$WORK/build.log"

say() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
fail() {
    printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2
    osascript -e "display alert \"Overreach\" message \"$*\" as critical" >/dev/null 2>&1 || true
    exit 1
}
dialog() { osascript -e "display dialog \"$1\" buttons {\"Cancelar\", \"$2\"} default button 2 with title \"Overreach\"" >/dev/null 2>&1; }
cleanup() { [ "${KEEP_CACHE:-0}" = "1" ] || rm -rf "$WORK"; }
trap cleanup EXIT

# --- 1. Xcode ------------------------------------------------------------------------------------------
say "Buscando Xcode"
XCODE_APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -n 1 || true)"
[ -n "$XCODE_APP" ] || XCODE_APP="/Applications/Xcode.app"
if [ ! -d "$XCODE_APP" ]; then
    open "macappstore://apps.apple.com/app/xcode/id497799835" 2>/dev/null || true
    fail "Falta Xcode. Instálalo desde la App Store (se acaba de abrir), ábrelo una vez y vuelve a ejecutar esto."
fi
export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
echo "  $XCODE_APP ($(xcodebuild -version | head -n 1))"
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    open "$XCODE_APP"
    fail "Abre Xcode una vez, acepta lo que pida (licencia y componentes) y vuelve a ejecutar esto."
fi

# --- 2. Apple ID (personal team) --------------------------------------------------------------------------
say "Buscando tu Apple ID en Xcode"
mkdir -p "$WORK"
defaults export com.apple.dt.Xcode "$WORK/xcode.plist" 2>/dev/null || true
TEAMS="$(osascript -l JavaScript - "$WORK/xcode.plist" <<'JS' 2>/dev/null || true
function run(argv) {
    ObjC.import('Foundation');
    const prefs = ObjC.deepUnwrap($.NSDictionary.dictionaryWithContentsOfFile(argv[0])) || {};
    const groups = prefs.IDEProvisioningTeamByIdentifier || prefs.IDEProvisioningTeams || {};
    const lines = [];
    for (const key in groups) {
        for (const team of groups[key] || []) {
            if (!team.teamID) continue;
            const free = team.isFreeProvisioningTeam ? 'free' : 'paid';
            const line = team.teamID + '\t' + (team.teamName || team.teamID) + '\t' + free;
            if (lines.indexOf(line) < 0) lines.push(line);
        }
    }
    return lines.join('\n');
}
JS
)"
PERSONAL="$(printf '%s\n' "$TEAMS" | awk -F'\t' '$3 == "free"' || true)"
if [ -z "$TEAMS" ]; then
    open "$XCODE_APP"
    fail "Añade tu Apple ID en Xcode: menú Xcode > Settings > Accounts > + > Apple ID. Después vuelve a ejecutar esto."
fi
if [ "$(printf '%s\n' "$PERSONAL" | grep -c . || true)" = "1" ]; then
    TEAM_LINE="$PERSONAL"
else
    # Several teams: never pick one silently.
    CHOICES="$(printf '%s\n' "$TEAMS" | awk -F'\t' '{ printf "%s\"%s (%s)%s\"", sep, $2, $1, ($3 == "free" ? " · personal" : ""); sep = ", " }')"
    PICKED="$(osascript -e "choose from list {$CHOICES} with title \"Overreach\" with prompt \"¿Con qué cuenta firmo la app?\"" 2>/dev/null || true)"
    [ -n "$PICKED" ] && [ "$PICKED" != "false" ] || fail "Cancelado."
    TEAM_ID="$(printf '%s' "$PICKED" | sed -E 's/.*\(([A-Z0-9]+)\).*/\1/')"
    TEAM_LINE="$(printf '%s\n' "$TEAMS" | awk -F'\t' -v id="$TEAM_ID" '$1 == id')"
fi
TEAM_ID="$(printf '%s' "$TEAM_LINE" | cut -f1)"
echo "  Equipo: $(printf '%s' "$TEAM_LINE" | cut -f2) ($TEAM_ID)"
# A free team cannot reuse a bundle id registered by someone else; tie it to the team so renewals keep data.
BUNDLE_PREFIX="io.github.overreach.$(printf '%s' "$TEAM_ID" | tr '[:upper:]' '[:lower:]')"

# --- 3. iPhone -----------------------------------------------------------------------------------------
say "Buscando el iPhone"
find_iphone() {
    xcrun devicectl list devices --json-output "$WORK/devices.json" >/dev/null 2>&1 || return 0
    osascript -l JavaScript - "$WORK/devices.json" <<'JS' 2>/dev/null || true
function run(argv) {
    ObjC.import('Foundation');
    const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js;
    const devices = ((JSON.parse(text).result || {}).devices) || [];
    return devices.filter(d => {
        const hw = d.hardwareProperties || {}, conn = d.connectionProperties || {};
        return hw.platform === 'iOS' && hw.deviceType === 'iPhone' && conn.pairingState === 'paired'
            && (conn.transportType === 'wired' || conn.tunnelState === 'connected');
    }).map(d => [d.hardwareProperties.udid, (d.deviceProperties || {}).name || 'iPhone',
                 (d.deviceProperties || {}).osVersionNumber || '?'].join('\t')).join('\n');
}
JS
}
IPHONE=""
for _ in 1 2 3 4 5; do
    IPHONE="$(find_iphone | head -n 1)"
    [ -n "$IPHONE" ] && break
    dialog "Conecta el iPhone por cable, desbloquéalo y, si pregunta, pulsa «Confiar» en este ordenador. Debe tener activado el Modo desarrollador (Ajustes > Privacidad y seguridad)." "Ya está" \
        || fail "Cancelado."
done
[ -n "$IPHONE" ] || fail "No encuentro ningún iPhone conectado y de confianza."
UDID="$(printf '%s' "$IPHONE" | cut -f1)"
echo "  $(printf '%s' "$IPHONE" | cut -f2) (iOS $(printf '%s' "$IPHONE" | cut -f3))"

# --- 4. Source and XcodeGen (temporary) -------------------------------------------------------------------
say "Descargando Overreach ($REF) y XcodeGen $XCODEGEN_VERSION"
rm -rf "$WORK/src" "$WORK/xcodegen"
mkdir -p "$WORK/src"
curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xz -C "$WORK/src" --strip-components 1 \
    || fail "No pude descargar el código. ¿Hay conexión a internet?"
curl -fsSL -o "$WORK/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip" \
    || fail "No pude descargar XcodeGen."
ditto -x -k "$WORK/xcodegen.zip" "$WORK"
XCODEGEN="$WORK/xcodegen/bin/xcodegen"
codesign --force --sign - "$XCODEGEN" >/dev/null 2>&1 || true
(cd "$WORK/src/App" && "$XCODEGEN" generate --quiet) || fail "No pude generar el proyecto de Xcode."

# --- 5. Build, signed with the personal team ---------------------------------------------------------------
say "Compilando y firmando (tarda unos minutos la primera vez)"
if ! xcodebuild build \
    -project "$WORK/src/App/Overreach.xcodeproj" \
    -scheme Overreach \
    -configuration Release \
    -destination "id=$UDID" \
    -derivedDataPath "$WORK/DerivedData" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    BUNDLE_ID_PREFIX="$BUNDLE_PREFIX" \
    CODE_SIGN_STYLE=Automatic \
    >"$LOG" 2>&1; then
    tail -n 30 "$LOG"
    if grep -qi "healthkit" "$LOG"; then
        KEEP_CACHE=1
        fail "Apple no permitió HealthKit con esta cuenta. Detalles en $LOG"
    fi
    KEEP_CACHE=1
    fail "La compilación falló. Detalles en $LOG (si el iPhone tiene un iOS más nuevo que este Xcode, actualiza Xcode)."
fi
APP="$WORK/DerivedData/Build/Products/Release-iphoneos/Overreach.app"
[ -d "$APP" ] || fail "No encuentro la app compilada."

if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "com.apple.developer.healthkit"; then
    echo "  Firma con permiso de Apple Salud: sí"
else
    echo "  Firma con permiso de Apple Salud: NO (la app se instala, pero Salud no funcionará)"
fi

# --- 6. Install ------------------------------------------------------------------------------------------
say "Instalando en el iPhone"
xcrun devicectl device install app --device "$UDID" "$APP" >>"$LOG" 2>&1 \
    || { tail -n 20 "$LOG"; KEEP_CACHE=1; fail "No pude instalar la app. Detalles en $LOG"; }

say "¡Listo!"
cat <<EOF
  En el iPhone, la primera vez: Ajustes > General > VPN y gestión de dispositivos > confía en tu Apple ID.
  Después abre Overreach y pulsa «Conectar Apple Salud».
  Esta copia caduca en 7 días: vuelve a ejecutar esto para renovarla (conserva tus datos).
  Si ya tenías Overreach instalado con Sideloadly, es otra app: en la vieja haz una copia de seguridad
  (Axustes), restáurala al configurar la nueva y después borra la vieja.
EOF
osascript -e 'display notification "Overreach instalado en el iPhone" with title "Overreach"' >/dev/null 2>&1 || true
}

main "$@"
