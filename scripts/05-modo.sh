#!/usr/bin/env bash
# 05-modo.sh — troca o modo de uma política SEM editar o YAML (recurso nativo do Tetragon).
#   monitor  -> as ações de contenção são elididas (só conta NMONITOR) = observação
#   enforce  -> as ações (Override/Sigkill) são executadas = contenção
# Só funciona em políticas que têm ação de contenção; uma política só-Post é "monitor_only".
#
# Uso:
#   sudo bash scripts/05-modo.sh list                      # lista políticas e seus modos
#   sudo bash scripts/05-modo.sh <politica> <monitor|enforce>
#   sudo bash scripts/05-modo.sh escape-docker-sock enforce
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode com sudo."; exit 1; }

case "${1:-list}" in
  list)
    docker exec tetragon tetra tracingpolicy list
    ;;
  *)
    pol="$1"; modo="${2:-}"
    case "$modo" in
      monitor|enforce) ;;
      *) echo "modo inválido: use 'monitor' ou 'enforce'"; exit 1 ;;
    esac
    docker exec tetragon tetra tracingpolicy set-mode "$pol" "$modo"
    echo "-> '$pol' agora em modo: $modo"
    docker exec tetragon tetra tracingpolicy list | awk 'NR==1 || /'"$pol"'/'
    ;;
esac
