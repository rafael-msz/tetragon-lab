# Protótipo 3 — Honeypot + correlação temporal

**Status:** 🔜 planejado

## Objetivo
Levar o lab para uma **VPS isolada** funcionando como **honeypot** (servidor isca) para estudar
invasões reais, e acrescentar **correlação temporal** — detectar uma **sequência** de etapas no tempo,
não só eventos isolados.

## Por que precisa de uma camada externa
O Tetragon (síncrono, no kernel) decide por evento, sem memória nem relógio — ver
[`sincrono.png`](sincrono.png). Ligar `T1105 → T1613 → T1611` dentro de uma janela de tempo exige
**estado + janela**, que fica numa camada assíncrona (ex.: **Wazuh**: `if_matched_sid` + `timeframe`,
com *Active Response* para conter a sequência).

## A planejar
- [ ] Endurecer a VPS (sem expor 2112/9090/3000; acesso por túnel SSH).
- [ ] Encaminhar os eventos do Tetragon para o Wazuh.
- [ ] Regras de correlação da cadeia de escape.
- [ ] *Active Response* (contenção assíncrona da sequência).
- [ ] Coleta e análise das invasões (evidências ficam fora do git — ver `.gitignore`).

## Frameworks relacionados
MITRE Engage (deception) · MITRE ATT&CK · NIST SP 800-61 (resposta a incidentes).
