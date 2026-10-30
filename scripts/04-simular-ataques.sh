#!/usr/bin/env bash
# 04-simular-ataques.sh — dispara as técnicas para validar a DETECÇÃO.
# Deixe o observador rodando em outro terminal:
#   sudo tail -n0 -f /var/log/tetragon/tetragon.log | jq -rc -f scripts/filtro.jq
#
# Para ver a CONTENÇÃO (políticas 9/10), ligue o enforcement ANTES de disparar:
#   sudo bash scripts/05-modo.sh escape-docker-sock enforce
#   sudo bash scripts/05-modo.sh escape-mount enforce
#
# Uso:
#   sudo bash scripts/04-simular-ataques.sh         # roda todas, com pausa entre elas
#   sudo bash scripts/04-simular-ataques.sh 3 5     # roda só as técnicas 3 e 5
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode com sudo."; exit 1; }

run() { echo; echo ">>> [$1] $2"; shift 2; "$@" || true; sleep 2; }

t6(){ docker exec lab-sock apk add --no-cache curl; }                                   # T1105
t3(){ docker exec lab-sock cat /etc/shadow; }                                            # T1552
t5(){ docker exec lab-sock sh -c 'cat /.dockerenv; cat /proc/self/cgroup'; }            # T1613
t7(){ docker exec lab-sock sh -c 'mkdir -p /root/.ssh; echo teste >> /root/.ssh/authorized_keys'; } # T1098
t2(){ docker exec lab-sock sh -c 'curl -s https://ebpf.io -o /dev/null'; }              # T1071
t8(){ docker exec lab-sock sh -c 'nc -w1 1.1.1.1 3333 || true'; }                       # T1496
t4(){ docker exec lab-sock sh -c 'touch /root/.bash_history && rm -f /root/.bash_history'; } # T1070
t9(){ docker exec lab-sock sh -c 'command -v curl >/dev/null || apk add -q --no-cache curl; curl -s --unix-socket /var/run/docker.sock http://localhost/version >/dev/null; echo "connect docker.sock: exit=$?"'; } # T1611
t10(){ docker exec lab-priv sh -c 'mkdir -p /mnt/h && mount /dev/vda1 /mnt/h 2>&1 | head -1'; }     # T1611 (dispara no sys_mount; ajuste o disco se quiser que o mount conclua)

declare -A NAME=( [6]="T1105 exec-ferramentas" [3]="T1552 leitura-credenciais" \
  [5]="T1613 container-discovery" [7]="T1098 persistencia-arquivos" [2]="T1071 conexao-saida" \
  [8]="T1496 mineracao-pool" [4]="T1070 remocao-indicadores" \
  [9]="T1611 escape-docker-sock" [10]="T1611 escape-mount" )

SEL=("$@"); [[ ${#SEL[@]} -eq 0 ]] && SEL=(6 3 5 7 2 8 4 9 10)
for n in "${SEL[@]}"; do run "$n" "${NAME[$n]:-?}" "t$n"; done
echo; echo "Pronto. Confira as linhas no terminal do observador."
