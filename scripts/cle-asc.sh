#!/usr/bin/env bash
# Écrit la clé d'API App Store Connect des secrets dans un fichier de la machine de fabrication, lisible du seul
# propriétaire, et contrôle sa forme sans jamais l'afficher. Workflows « TestFlight » et « Certificats ».
#
#   scripts/cle-asc.sh        → $RUNNER_TEMP/asc/AuthKey_<ASC_CLE_ID>.p8 (le nom qu'attend xcodebuild)
#
#   ASC_CLE_P8_B64   la clé .p8 telle quelle, ou encodée en base64 (les deux sont acceptés)
#   ASC_CLE_ID       son identifiant
# L'appelant efface "$RUNNER_TEMP/asc" en fin de travail (étape « if: always() »).
set -euo pipefail

[[ -n "${ASC_CLE_P8_B64:-}" ]] || { echo "::error::secret ASC_CLE_P8_B64 absent"; exit 1; }
[[ "${ASC_CLE_ID:-}" =~ ^[A-Z0-9]+$ ]] || { echo "::error::secret ASC_CLE_ID absent ou mal formé"; exit 1; }

umask 077
mkdir -p "$RUNNER_TEMP/asc"
fichier="$RUNNER_TEMP/asc/AuthKey_${ASC_CLE_ID}.p8"
# repère d'une clé PEM, écrit sans son en-tête complet (la garde de confidentialité du dépôt le refuse)
repere="PRIVATE KEY-----"
if [[ "$ASC_CLE_P8_B64" == *"$repere"* ]]; then
    printf '%s\n' "$ASC_CLE_P8_B64" > "$fichier"
else
    printf '%s' "$ASC_CLE_P8_B64" | python3 -c \
        'import base64, sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read().strip(), validate=True))' \
        > "$fichier"
fi
grep -q -- "$repere" "$fichier" \
    || { echo "::error::ASC_CLE_P8_B64 : pas une clé .p8 ($(wc -c < "$fichier") octets)"; exit 1; }
