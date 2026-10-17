#!/usr/bin/env bash
# Prépare le projet Xcode : configuration de la maison (facultative), puis génération par XcodeGen.
#
#   scripts/generer.sh
#
# La configuration de la maison n'est JAMAIS versionnée (dépôt public). Elle arrive par l'environnement :
#   ALFRED_RELAIS            nom d'hôte du relais (https), par exemple relais.maison.example
#   ALFRED_AUTORITE_PEM_B64  certificat de l'autorité de la maison (PEM, encodé en base64), épinglé par l'app ; le
#                            relais devient alors une exception d'ATS (seul moyen d'accepter une autorité inconnue
#                            de l'appareil), en https seulement
#   ALFRED_HA_HOTE           nom d'hôte de Home Assistant s'il sert sa page de connexion en http (exception ATS
#                            limitée à ce seul hôte ; jamais NSAllowsArbitraryLoads)
# Sans ALFRED_RELAIS, l'app demande l'adresse du relais au premier lancement (et se fie aux autorités du système).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=App/Ressources/Configuration.plist
rm -f "$CONFIG"

if [[ -n "${ALFRED_RELAIS:-}" ]]; then
    [[ "$ALFRED_RELAIS" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "ALFRED_RELAIS : un nom d'hôte seul est attendu" >&2; exit 1; }
    plutil -create xml1 "$CONFIG"
    plutil -insert Relais -string "$ALFRED_RELAIS" "$CONFIG"
    if [[ -n "${ALFRED_AUTORITE_PEM_B64:-}" ]]; then
        tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
        # décodage strict par Python (présent sur les Mac de GitHub) ; en cas d'échec, la longueur et le début de
        # l'empreinte de la valeur, pour la comparer à celle attendue, jamais son contenu
        if ! printf '%s' "$ALFRED_AUTORITE_PEM_B64" | python3 -c \
            'import base64, sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read().strip(), validate=True))' \
            > "$tmp/ca.pem" || [[ ! -s "$tmp/ca.pem" ]]; then
            echo "ALFRED_AUTORITE_PEM_B64 : base64 invalide (${#ALFRED_AUTORITE_PEM_B64} caractères, sha256" \
                "$(printf '%s' "$ALFRED_AUTORITE_PEM_B64" | shasum -a 256 | cut -c1-12))" >&2
            exit 1
        fi
        grep -q -- "-----BEGIN CERTIFICATE-----" "$tmp/ca.pem" \
            || { echo "ALFRED_AUTORITE_PEM_B64 : pas un certificat PEM ($(wc -c < "$tmp/ca.pem") octets)" >&2; exit 1; }
        # une AUTORITÉ, pas un certificat de serveur : l'app ne fait confiance qu'à elle pour ce relais.
        # « -text » est compris par OpenSSL comme par LibreSSL (l'openssl de macOS, sans « -ext ») ; lu dans une
        # variable, pas par un tube : « grep -q » couperait openssl, et pipefail ferait échouer le test
        details=$(openssl x509 -in "$tmp/ca.pem" -noout -text)
        [[ "$details" == *"CA:TRUE"* ]] \
            || { echo "ALFRED_AUTORITE_PEM_B64 : ce n'est pas un certificat d'autorité" >&2; exit 1; }
        openssl x509 -in "$tmp/ca.pem" -outform der -out "$tmp/ca.der"
        plutil -insert Autorite -data "$(base64 < "$tmp/ca.der" | tr -d '\n')" "$CONFIG"
    fi
    echo "configuration de la maison : relais configuré$( [[ -n "${ALFRED_AUTORITE_PEM_B64:-}" ]] && echo ", autorité épinglée")"
else
    echo "configuration de la maison : aucune (l'app demandera l'adresse du relais)"
fi

xcodegen generate --quiet

# Exceptions d'App Transport Security, chacune pour un seul hôte, sans ses sous-domaines (jamais NSAllowsArbitraryLoads).
# NSExceptionAllowsInsecureHTTPLoads est LA clé d'Apple pour les deux besoins : charger un hôte en http, ou « assouplir
# l'évaluation de la confiance » d'un hôte en https (documentation de la clé). Sans elle, ATS refuse une autorité que
# l'appareil ne connaît pas, même acceptée par l'app (-1202) : « You cannot loosen server trust requirements for an
# ATS-protected domain » (Apple, « Performing Manual Server Trust Authentication »).
plist=App/Info.plist
exception_ats() {
    local hote
    hote=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')    # ATS : noms de domaine en minuscules
    /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity:NSExceptionDomains:$hote" "$plist" > /dev/null 2>&1 \
        && return 0
    /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity:NSExceptionDomains" "$plist" > /dev/null 2>&1 \
        || /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains dict" "$plist"
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:$hote dict" "$plist"
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:$hote:NSExceptionAllowsInsecureHTTPLoads bool true" "$plist"
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:$hote:NSIncludesSubdomains bool false" "$plist"
}

# Le relais, quand son autorité est épinglée : l'app n'y accepte que cette autorité (ConfianceTLS) et n'y va qu'en
# https (Relais n'admet que https et wss, la page de connexion refuse http vers lui).
if [[ -n "${ALFRED_RELAIS:-}" && -n "${ALFRED_AUTORITE_PEM_B64:-}" ]]; then
    exception_ats "$ALFRED_RELAIS"
    echo "exception ATS : le relais (autorité de la maison épinglée)"
fi

# Home Assistant, s'il sert sa page de connexion en http.
if [[ -n "${ALFRED_HA_HOTE:-}" ]]; then
    [[ "$ALFRED_HA_HOTE" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "ALFRED_HA_HOTE : un nom d'hôte seul est attendu" >&2; exit 1; }
    exception_ats "$ALFRED_HA_HOTE"
    echo "exception ATS : la page de connexion de Home Assistant"
fi
