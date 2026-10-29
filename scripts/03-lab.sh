#!/usr/bin/env bash
# 03-lab.sh — gerencia os contêineres-alvo do laboratório (inseguros DE PROPÓSITO).
# Uso:
#   sudo bash scripts/03-lab.sh create   # cria lab-sock e lab-priv
#   sudo bash scripts/03-lab.sh reset    # recria limpos + zera o log do Tetragon
#   sudo bash scripts/03-lab.sh status   # mostra os contêineres do lab
#   sudo bash scripts/03-lab.sh destroy  # remove os contêineres
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode com sudo."; exit 1; }

create() {
  docker run -d --name lab-sock \
    -v /var/run/docker.sock:/var/run/docker.sock \
    alpine sleep infinity
  docker run -d --name lab-priv --privileged \
    alpine sleep infinity
  docker ps --filter name=lab-
}
destroy() { docker rm -f lab-sock lab-priv 2>/dev/null || true; }

case "${1:-}" in
  create)  destroy; create ;;
  reset)   destroy; create; : > /var/log/tetragon/tetragon.log 2>/dev/null || truncate -s 0 /var/log/tetragon/tetragon.log; echo "lab resetado + log zerado" ;;
  status)  docker ps --filter name=lab- ;;
  destroy) destroy; echo "contêineres do lab removidos" ;;
  *) echo "uso: $0 {create|reset|status|destroy}"; exit 1 ;;
esac
