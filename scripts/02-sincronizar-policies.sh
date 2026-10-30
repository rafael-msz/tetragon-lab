#!/usr/bin/env bash
# 02-sincronizar-policies.sh — copia policies/ -> /etc/tetragon/tetragon.tp.d/ e recarrega o agente.
# Roda um PRÉ-CHECK antes de tocar no Tetragon: um único YAML inválido derruba o agente inteiro.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Rode com sudo."; exit 1; }
# raiz do repo (este script está em scripts/)
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/policies"
DST="/etc/tetragon/tetragon.tp.d"

[[ -d "$SRC" ]] || { echo "Pasta não encontrada: $SRC"; exit 1; }

echo "==> PRÉ-CHECK em $SRC"
fail=0
empty="$(find "$SRC" -type f \( -name '*.yaml' -o -name '*.yml' \) -not -name '_*' -empty || true)"
if [[ -n "$empty" ]]; then echo "  [ERRO] arquivos vazios:"; echo "$empty"; fail=1; fi
nokind="$(grep -rL 'kind: TracingPolicy' "$SRC" --include='*.yaml' --include='*.yml' --exclude='_*' || true)"
if [[ -n "$nokind" ]]; then echo "  [ERRO] sem 'kind: TracingPolicy':"; echo "$nokind"; fail=1; fi
badkind="$(grep -rl 'TracingPolicyNamespaced' "$SRC" --include='*.yaml' --include='*.yml' --exclude='_*' || true)"
if [[ -n "$badkind" ]]; then echo "  [ERRO] usa TracingPolicyNamespaced (não funciona em Docker):"; echo "$badkind"; fail=1; fi
if [[ $fail -ne 0 ]]; then
  echo "==> PRÉ-CHECK FALHOU. Corrija no repositório antes de sincronizar (o Tetragon NÃO foi tocado)."
  exit 1
fi
echo "  OK — nenhum arquivo vazio, kind correto."

echo "==> Sincronizando para $DST"
rm -rf "${DST:?}/"*
rsync -a --include='*/' --exclude='_*' --include='*.yaml' --include='*.yml' --exclude='*' "$SRC"/ "$DST"/

echo "==> Recarregando o Tetragon"
docker restart tetragon >/dev/null
sleep 15
docker ps --filter name=tetragon
echo "==> Políticas carregadas:"
docker exec tetragon tetra tracingpolicy list || {
  echo "  [AVISO] 'tracingpolicy list' falhou — veja: docker logs tetragon | tail -30"; exit 1; }
