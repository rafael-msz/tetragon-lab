# Protótipo 2 — Contenção

**Status:** 🚧 em andamento — políticas carregadas em `monitor_only`; detecção validada em laboratório.

> Este arquivo concentra o que **muda** nesta etapa (cenário, testes, caveats). O README raiz fica estável.

## Ideia
A mesma `TracingPolicy` que observa (`Post`) passa a conter trocando a ação para **`Override`**
(nega a chamada, processo segue vivo) ou **`Sigkill`** (encerra o processo).

## Metodologia (nunca ligar bloqueio às cegas)
1. **Observar** (`Post`) → entender o normal.
2. **Calibrar** seletores até só o malicioso casar.
3. **Monitoring** → ação avaliada e contada (`NMONITOR`), sem executar.
4. **Enforcement** → liga o bloqueio.

## Cenário da demonstração — escape via `docker.sock`
Contêiner `lab-sock` com `/var/run/docker.sock` montado. Cadeia em 4 etapas (MITRE):

| Etapa | Técnica | Ação |
|---|---|---|
| 1 | T1105 | roda a ferramenta (curl/apk) no contêiner |
| 2 | T1613 | descobre o soquete, lista contêineres |
| 3 | T1610 | cria contêiner com o disco do host |
| 4 | T1611 | escreve no sistema de arquivos do host |

**Onde contemos:** na **etapa 1**, com **`Sigkill` no `execve`** da ferramenta — hook que dispara de
forma confiável. Prova do bloqueio: processo morto → **código de saída 137**.

## Validação da detecção
```bash
sudo bash scripts/03-lab.sh reset        # lab limpo + log zerado
# Terminal A: observar
sudo tail -n0 -f /var/log/tetragon/tetragon.log | jq -rc -f scripts/filtro.jq
# Terminal B: disparar
sudo bash scripts/04-simular-ataques.sh
```

## Caveats / planos B (atualizar conforme testar)
- **`escape-docker-sock`** — `security_file_open` **não** captura acesso ao socket via `--unix-socket`
  (é `connect()`, não `open()`). ➜ contenção no `execve` (acima) ou hook na conexão ao socket.
- **`escape-mount`** — `matchNamespaceChanges: Mnt` pode não disparar num `mount` simples.
  ➜ plano B: `matchNamespaces` com `Mnt NotIn host_ns` (estado, não mudança).
- **`remocao-indicadores`** — `unlinkat` pode receber caminho **relativo**; o `Postfix` por nome é
  robusto, o `Prefix /var/log` é frágil.

## Evitar falso positivo
Seletores precisos (linhagem, namespace, caminho exato) · testar em `monitoring` e medir `NMONITOR` ·
preferir `Override` a `Sigkill` quando possível.

> _Observado no lab: só a subida dos contêineres já disparou `container-discovery` 8× e
> `leitura-credenciais` 2× — ruído de inicialização que a calibragem precisa separar do ataque real._

## Requisitos de kernel
- `Sigkill`: funciona em qualquer kernel com BPF (sem opção especial).
- `Override`: exige `CONFIG_BPF_KPROBE_OVERRIDE` (conferir com `tetra probe config`).
- `keep-sensors-on-exit: true`: mantém o bloqueio ativo mesmo se o agente cair.
