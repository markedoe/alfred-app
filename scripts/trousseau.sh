#!/usr/bin/env bash
# Installe l'identité de signature de la CI dans un trousseau temporaire de la machine de fabrication : le certificat
# « Apple Development » unique de l'équipe et sa clé, gardés dans les secrets du dépôt (workflow « Certificats »).
# Sans elle, Xcode créerait un certificat à chaque fabrication (une machine neuve n'en a aucun), jusqu'à la limite
# d'Apple. Méthode de la documentation de GitHub, « Installing an Apple certificate on macOS runners ».
#
#   scripts/trousseau.sh      → $RUNNER_TEMP/signature.keychain-db, en tête de la liste de recherche
#
#   SIGNATURE_P12_B64            l'identité (.p12 encodé en base64 : certificat, intermédiaire d'Apple, clé)
#   SIGNATURE_P12_MOT_DE_PASSE   son mot de passe
# L'appelant efface le trousseau en fin de travail (étape « if: always() »).
set -euo pipefail

[[ -n "${SIGNATURE_P12_B64:-}" && -n "${SIGNATURE_P12_MOT_DE_PASSE:-}" ]] \
    || { echo "::error::secrets SIGNATURE_P12_B64 et SIGNATURE_P12_MOT_DE_PASSE attendus (workflow Certificats)"; exit 1; }

umask 077
trousseau="$RUNNER_TEMP/signature.keychain-db"
p12="$RUNNER_TEMP/signature.p12"
# le trousseau disparaît avec la machine : son mot de passe est tiré au hasard et n'est gardé nulle part
mot_de_passe=$(openssl rand -base64 24)

printf '%s' "$SIGNATURE_P12_B64" | base64 --decode > "$p12"
# un mois avant la fin du certificat (un an de validité), la fabrication le signale sans échouer
if ! openssl pkcs12 -in "$p12" -passin env:SIGNATURE_P12_MOT_DE_PASSE -nokeys -clcerts 2>/dev/null \
    | openssl x509 -noout -checkend 2592000 > /dev/null; then
    echo "::warning::le certificat de la CI expire dans moins de 30 jours : en créer un autre (workflow Certificats)"
fi

security create-keychain -p "$mot_de_passe" "$trousseau"
security set-keychain-settings -lut 21600 "$trousseau"
security unlock-keychain -p "$mot_de_passe" "$trousseau"
security import "$p12" -P "$SIGNATURE_P12_MOT_DE_PASSE" -A -t cert -f pkcs12 -k "$trousseau" > /dev/null
rm -f "$p12"
security set-key-partition-list -S apple-tool:,apple: -k "$mot_de_passe" "$trousseau" > /dev/null
# en tête de la liste de recherche, sans retirer les trousseaux de la machine
read -ra autres <<< "$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')"
security list-keychains -d user -s "$trousseau" "${autres[@]}"

# une identité valide, chaîne vérifiée jusqu'à Apple ; son nom (celui du titulaire) n'est pas affiché
valides=$(security find-identity -v -p codesigning "$trousseau" | grep -cE '^ +[0-9]+\) ' || true)
[[ "$valides" == 1 ]] || { echo "::error::trousseau : $valides identité(s) de signature valide(s), 1 attendue"; exit 1; }
echo "identité de signature de la CI installée"
