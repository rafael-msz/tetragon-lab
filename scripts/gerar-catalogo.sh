#!/usr/bin/env bash
# gerar-catalogo.sh — gera a tabela do catálogo a partir das próprias políticas.
# Lê policies/**/*.yaml e reescreve a tabela em policies/README.md, entre os marcadores:
#   <!-- CATALOGO:START -->  ...  <!-- CATALOGO:END -->
# Assim você NUNCA edita a tabela à mão: muda a política, roda este script.
#
# Como cada campo é obtido:
#   Tática   = nome da pasta (ex.: privilege-escalation)
#   Técnica  = prefixo do arquivo (ex.: T1611-...) ou annotation mitre.technique
#   Política = metadata.name
#   Hook     = primeiro 'call:' do spec
#   Descrição= metadata.annotations.description (opcional)
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POL="$REPO/policies"
OUT="$POL/README.md"
[[ -d "$POL" ]] || { echo "pasta não encontrada: $POL"; exit 1; }
[[ -f "$OUT" ]] || { echo "arquivo não encontrado: $OUT"; exit 1; }

declare -A TAT=(
 [command-and-control]="Command & Control" [credential-access]="Credential Access"
 [defense-evasion]="Defense Evasion" [discovery]="Discovery" [execution]="Execution"
 [impact]="Impact" [initial-access]="Initial Access" [lateral-movement]="Lateral Movement"
 [persistence]="Persistence" [privilege-escalation]="Privilege Escalation"
 [exfiltration]="Exfiltration" [collection]="Collection" [reconnaissance]="Reconnaissance"
)

field(){ grep -m1 -E "$1" "$2" 2>/dev/null | sed -E "$3" || true; }

tmp="$(mktemp)"; count=0
{
  echo "| Tática | Técnica | Política | Hook | Modo | Descrição |"
  echo "|---|---|---|---|---|---|"
  while IFS= read -r f; do
    folder="$(basename "$(dirname "$f")")"
    tat="${TAT[$folder]:-$folder}"
    tech="$(basename "$f" | grep -oE '^T[0-9]+(\.[0-9]+)?' || true)"
    [[ -z "$tech" ]] && tech="$(field '\s*mitre\.technique:' "$f" 's/.*:\s*"?([^"]+)"?.*/\1/')"
    [[ -z "$tech" ]] && tech="-"
    name="$(field '^\s*name:' "$f" 's/.*name:\s*"?([^"]+)"?.*/\1/')"
    hook="$(field '^\s*-?\s*call:' "$f" 's/.*call:\s*"?([^"]+)"?.*/\1/')"
    desc="$(field '\s*description:' "$f" 's/.*description:\s*"?([^"]*)"?.*/\1/')"
    modo="$(field '\s*modo-suportado:' "$f" 's/.*modo-suportado:\s*"?([^"]*)"?.*/\1/')"
    if [[ -z "$modo" ]]; then
      if grep -qE '\b(Override|Sigkill)\b' "$f"; then modo="observação/contenção"; else modo="observação"; fi
    fi
    echo "| $tat | $tech | \`${name:-?}\` | \`${hook:-?}\` | ${modo} | ${desc:-—} |"
    count=$((count+1))
  done < <(find "$POL" -type f \( -name '*.yaml' -o -name '*.yml' \) -not -name '_*' | sort)
} > "$tmp"

awk -v tblfile="$tmp" '
  BEGIN{ while((getline l < tblfile)>0) tbl=tbl l "\n" }
  /<!-- CATALOGO:START -->/ { print; print ""; printf "%s", tbl; skip=1; next }
  /<!-- CATALOGO:END -->/   { skip=0; print ""; print; next }
  !skip { print }
' "$OUT" > "$OUT.new" && mv "$OUT.new" "$OUT"
rm -f "$tmp"
echo "Catálogo atualizado: $count políticas -> policies/README.md"
