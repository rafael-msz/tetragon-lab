# Protótipo 1 — Observabilidade

**Status:** ✅ concluído

## Objetivo
Tornar visíveis, a partir do host, os sinais de um *container escape*: execução de processos,
acesso a arquivos sensíveis e conexões de rede de todos os contêineres.

## O que foi entregue
- Instalação e configuração do Tetragon em Docker (ver [`scripts/01-instalar.sh`](../scripts/01-instalar.sh)).
- Exportação de eventos em JSON (`/var/log/tetragon/tetragon.log`) com identidade de contêiner,
  credenciais (`enable-process-cred`) e namespaces (`enable-process-ns`).
- Leitura dos eventos de forma legível com [`scripts/filtro.jq`](../scripts/filtro.jq).

## Como demonstrar
```bash
sudo bash scripts/01-instalar.sh
sudo bash scripts/03-lab.sh create
sudo tail -n0 -f /var/log/tetragon/tetragon.log | jq -rc -f scripts/filtro.jq
```

## Frameworks relacionados
NIST SP 800-137 (monitoramento contínuo) · NIST SP 800-94 (IDS/IPS) · MITRE ATT&CK (Containers).

> _Preencha com as medições e prints usados na apresentação do protótipo 1._
