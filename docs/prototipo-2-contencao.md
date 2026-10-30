# Protótipo 2 — Contenção

**Status:** 🚧 em andamento — políticas de detecção validadas; contenção via **modo nativo** do Tetragon.

> Este arquivo concentra o que **muda** nesta etapa (modos, cenário, correções, testes). O README raiz fica estável.

## Ideia

A **mesma** `TracingPolicy` que observa passa a conter. Em vez de manter cópias por modo ou editar o
YAML na hora, usamos o recurso **nativo** de modo do Tetragon:

- a política declara sua ação de contenção (`Override` ou `Sigkill`) **uma vez**, no YAML;
- carrega em **`monitor`** por padrão (ação elidida, só conta `NMONITOR`) — seguro;
- na apresentação, troca-se para **`enforce`** com **um comando**, sem tocar no arquivo.

### Modos (nativo do Tetragon v1.7.0)

| Modo | Comportamento |
|------|---------------|
| `monitor` | ações de contenção elididas (contadas em `NMONITOR`) = observação |
| `enforce` | ações executadas (`Override` nega a chamada / `Sigkill` mata o processo) = contenção |
| `monitor_only` | política sem ação de contenção (só `Post`); **não** pode ir para `enforce` |

Como a política entra em `monitor`: no próprio YAML,
```yaml
spec:
  options:
    - name: "policy-mode"
      value: "monitor"
```
Como alternar na hora (sem editar o YAML):
```bash
sudo bash scripts/05-modo.sh escape-docker-sock enforce   # liga a contenção
sudo bash scripts/05-modo.sh escape-docker-sock monitor   # volta a observar
sudo bash scripts/05-modo.sh list                         # vê o modo de cada política
```
> Internamente: `tetra tracingpolicy set-mode <nome> <monitor|enforce>` — confirme os tokens no seu
> ambiente com `tetra tracingpolicy set-mode --help` / `tetra tracingpolicy add --help`.

## Metodologia (nunca ligar bloqueio às cegas)

1. **Observar** (`Post` / `monitor`) → entender o normal.
2. **Calibrar** seletores até só o malicioso casar.
3. **Monitoring** → ação avaliada e contada (`NMONITOR`), sem executar.
4. **Enforcement** → `05-modo.sh <politica> enforce`.

## Cenário da demonstração — escape via `docker.sock`

Contêiner `lab-sock` com `/var/run/docker.sock` montado. Cadeia em 4 etapas (MITRE):

| Etapa | Técnica | Ação |
|---|---|---|
| 1 | T1105 | roda a ferramenta (curl/apk) no contêiner |
| 2 | T1613 | descobre o soquete, lista contêineres |
| 3 | T1610 | cria contêiner com o disco do host |
| 4 | T1611 | escreve no sistema de arquivos do host |

**Onde contemos:** na **etapa 2**, negando a conexão ao soquete com **`Override` em
`security_socket_connect`** (ver correção da política 9 abaixo). Alternativa igualmente válida:
`Sigkill` no `execve` da ferramenta na etapa 1 (promova a `exec-ferramentas-transferencia`).

## Correções aplicadas (políticas 9 e 10)

### Política 9 — `escape-docker-sock`

- **O que estava errado:** usava `security_file_open` em `/run/docker.sock`. O acesso ao soquete é
  uma **`connect()` em soquete UNIX**, não um `open()` de arquivo — então o hook nunca disparava.
- **Correção:** hook **`security_socket_connect`** com o argumento **`sockaddr_un`** (tipo nativo que
  expõe o caminho do soquete), casando `/run/docker.sock` e `/var/run/docker.sock` com `Equal`.
- **Contenção:** `Override` (`argError: -1`) nega a `connect()` — o `security_socket_connect` aceita
  `Override` (confirmado no exemplo oficial `security-socket-connect-block-others.yaml`).
- **Teste:**
  ```bash
  sudo bash scripts/05-modo.sh escape-docker-sock enforce
  docker exec lab-sock sh -c 'apk add -q --no-cache curl; curl -s --unix-socket /var/run/docker.sock http://localhost/version; echo exit=$?'
  # esperado: evento da política + connect negado (exit != 0)
  ```

### Política 10 — `escape-mount`

- **O que estava errado:** `matchNamespaceChanges: Mnt` detecta **mudança** de namespace
  (`unshare`/`setns`), não um `mount` comum — um processo de contêiner já nasce no seu namespace, não
  há mudança, então não disparava.
- **Correção:** filtrar pelo **estado** com `matchNamespaces` — `namespace: Mnt`, `operator: NotIn`,
  `values: ["host_ns"]` → processo cujo namespace de montagem **não é o do host** = dentro de contêiner.
  (Sintaxe confirmada no exemplo oficial `fd_install_ns_host.yaml`.)
- **Contenção:** `Override` (`argError: -1`) faz o `mount` falhar.
- **Teste:**
  ```bash
  sudo bash scripts/05-modo.sh escape-mount enforce
  docker exec lab-priv sh -c 'mkdir -p /mnt/h && mount /dev/vda1 /mnt/h; echo exit=$?'
  # o evento dispara no sys_mount mesmo que o disco não exista; em enforce, o mount é negado
  ```

> **Nota sobre `remocao-indicadores` (política 4):** `unlinkat` pode receber caminho **relativo**; o
> `Postfix` por nome (`.bash_history`) é robusto, o `Prefix /var/log` é frágil. Mantido como está;
> _a validar_ no homelab.

## Validação da detecção (todas)

```bash
sudo bash scripts/03-lab.sh reset        # lab limpo + log zerado
# Terminal A: observar
sudo tail -n0 -f /var/log/tetragon/tetragon.log | jq -rc -f scripts/filtro.jq
# Terminal B: disparar
sudo bash scripts/04-simular-ataques.sh
```

## Evitar falso positivo

Seletores precisos (linhagem, namespace, caminho exato) · testar em `monitor` e medir `NMONITOR`
antes de `enforce` · preferir `Override` a `Sigkill` quando possível.

> _Observado no lab: só a subida dos contêineres já disparou `container-discovery` 8× e
> `leitura-credenciais` 2× — ruído de inicialização que a calibragem precisa separar do ataque real._

## Requisitos de kernel

- `Sigkill`: funciona em qualquer kernel com BPF (sem opção especial).
- `Override`: exige `CONFIG_BPF_KPROBE_OVERRIDE` (conferir com `tetra probe config`).
- `keep-sensors-on-exit: true` (já ligado pelo `01-instalar.sh`): mantém o bloqueio ativo mesmo se o
  agente cair.
