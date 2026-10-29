#!/usr/bin/env bash
# 01-instalar.sh — instalação limpa de Docker + Cilium Tetragon (Ubuntu Server)
# Uso:
#   sudo bash scripts/01-instalar.sh          # instala (pergunta antes de limpar)
#   sudo bash scripts/01-instalar.sh --clean  # força a limpeza prévia sem perguntar
set -euo pipefail

TETRAGON_VERSION="v1.7.0"
[[ $EUID -eq 0 ]] || { echo "Rode com sudo."; exit 1; }

CLEAN="ask"; [[ "${1:-}" == "--clean" ]] && CLEAN="yes"

echo "==> 1/5  Limpeza (instalação do zero)"
if [[ "$CLEAN" == "ask" ]]; then
  read -rp "Remover Docker/Tetragon existentes e seus dados? [s/N] " r
  [[ "${r,,}" == "s" ]] && CLEAN="yes" || CLEAN="no"
fi
if [[ "$CLEAN" == "yes" ]]; then
  docker rm -f "$(docker ps -aq)" 2>/dev/null || true
  apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
    docker-compose-plugin docker-ce-rootless-extras docker.io containerd runc 2>/dev/null || true
  apt autoremove -y || true
  rm -rf /var/lib/docker /var/lib/containerd /etc/tetragon /var/log/tetragon \
    /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
  echo "    limpeza concluída."
fi

echo "==> 2/5  Instalando o Docker"
apt update
apt install -y ca-certificates curl jq rsync
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt update
apt install -y docker-ce docker-ce-cli containerd.io
systemctl enable --now docker
docker --version

echo "==> 3/5  Pastas e configuração do Tetragon"
mkdir -p /etc/tetragon/tetragon.conf.d /etc/tetragon/tetragon.tp.d /var/log/tetragon
echo "/var/log/tetragon/tetragon.log" > /etc/tetragon/tetragon.conf.d/export-filename
echo "true" > /etc/tetragon/tetragon.conf.d/enable-process-cred
echo "true" > /etc/tetragon/tetragon.conf.d/enable-process-ns
# robustez: mantém os sensores ativos se o agente cair (ver README)
echo "true" > /etc/tetragon/tetragon.conf.d/keep-sensors-on-exit

echo "==> 4/5  Baixando e iniciando o Tetragon ${TETRAGON_VERSION}"
docker pull "quay.io/cilium/tetragon:${TETRAGON_VERSION}"
docker rm -f tetragon 2>/dev/null || true
docker run -d --name tetragon --restart unless-stopped \
  --hostname "$(hostname)" \
  --pid=host --cgroupns=host --privileged \
  -v /etc/tetragon:/etc/tetragon \
  -v /sys/kernel:/sys/kernel \
  -v /var/log/tetragon:/var/log/tetragon \
  "quay.io/cilium/tetragon:${TETRAGON_VERSION}"

echo "==> 5/5  Verificação"
sleep 8
docker ps --filter name=tetragon
docker logs tetragon 2>&1 | tail -5 || true
echo
echo "OK. Próximo passo: sudo bash scripts/02-sincronizar-policies.sh"
