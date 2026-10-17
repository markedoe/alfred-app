#!/usr/bin/env bash
# Prépare le projet Xcode : configuration de la maison (facultative), puis génération par XcodeGen.
#
#   scripts/generer.sh
#
# La configuration de la maison n'est JAMAIS versionnée (dépôt public). Elle arrive par l'environnement :
#   ALFRED_RELAIS            nom d'hôte du relais (https), par exemple relais.maison.example
#   ALFRED_AUTORITE_PEM_B64  certificat de l'autorité de la maison (PEM, encodé en base64), épinglé par l'app
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

if [[ -n "${ALFRED_HA_HOTE:-}" ]]; then
    [[ "$ALFRED_HA_HOTE" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "ALFRED_HA_HOTE : un nom d'hôte seul est attendu" >&2; exit 1; }
    plist=App/Info.plist
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains dict" "$plist"
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:$ALFRED_HA_HOTE dict" "$plist"
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:$ALFRED_HA_HOTE:NSExceptionAllowsInsecureHTTPLoads bool true" "$plist"
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:$ALFRED_HA_HOTE:NSIncludesSubdomains bool false" "$plist"
    echo "exception ATS : un seul hôte (page de connexion de Home Assistant)"
fi
