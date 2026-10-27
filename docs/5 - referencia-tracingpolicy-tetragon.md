# Referência — Parâmetros de uma TracingPolicy do Tetragon

Todos os campos que um arquivo `.yaml` de política aceita. Baseado na documentação oficial (tetragon.io). Fonte da verdade sempre que houver dúvida: o CRD em `pkg/k8s/apis/cilium.io/client/crds/v1alpha1/cilium.io_tracingpolicies.yaml`.

> Em Docker puro, use sempre `kind: TracingPolicy` (nunca `TracingPolicyNamespaced`, que é do Kubernetes).

---

## 1. Estrutura geral

```yaml
apiVersion: cilium.io/v1alpha1     # fixo
kind: TracingPolicy                # fixo (Docker puro)
metadata:
  name: "nome-da-politica"         # identifica a política no 'tracingpolicy list' e nos eventos
spec:
  # blocos abaixo
```

Dentro de `spec`, os blocos possíveis:

| Bloco | O que faz |
|---|---|
| `kprobes` | Hook em função do kernel ou syscall |
| `fentries` | Igual ao kprobe, mais rápido (kernel ≥ 6.1 + BTF; não suporta Override/Signal) |
| `tracepoints` | Hook em tracepoint estático do kernel |
| `uprobes` | Hook em função de binário de usuário |
| `usdts` | Hook em probe USDT de binário |
| `lsmhooks` | Hook em hook de LSM (exige BPF LSM ativo) |
| `lists` | Listas de funções reutilizáveis via `call: "list:nome"` |
| `enforcers` | Programa auxiliar para a ação `NotifyEnforcer` |
| `selectorsMacros` | Blocos de seletor reutilizáveis |
| `options` | Ajustes da política (ver seção 7) |

---

## 2. Campos dos hooks

### kprobes / fentries
```yaml
  kprobes:
  - call: "sys_openat"       # função/syscall a interceptar (sem prefixo de arquitetura)
    syscall: true            # true = é syscall; false = função de kernel comum
    return: true             # true = também captura o retorno (precisa de returnArg)
    message: "texto"         # (opcional) mensagem anexada ao evento
    tags: ["observability.filesystem"]  # (opcional) rótulos
    args: [...]              # argumentos a capturar (seção 3)
    returnArg: {...}         # tipo do valor de retorno (seção 4)
    returnArgAction: "TrackSock"  # ação sobre o retorno (TrackSock/UntrackSock)
    selectors: [...]         # filtros e ações (seções 5 e 6)
    ignore:                  # (opcional) tolerância a falha de carregamento
      callNotFound: true     # ignora se a função não existir neste kernel
```

### tracepoints
```yaml
  tracepoints:
  - subsystem: "raw_syscalls"   # subsistema (ver /sys/kernel/tracing/events)
    event: "sys_enter"          # evento dentro do subsistema
    raw: true                   # (opcional) raw tracepoint, acesso aos args crus
    args: [...]
    selectors: [...]
```

### uprobes
```yaml
  uprobes:
  - path: "/bin/bash"           # binário alvo
    symbols: ["readline"]       # símbolos (funções) a interceptar
    return: true
    returnArg: {...}
    binaryDigests: ["sha256:..."]  # (opcional) só aplica a este build do binário
    ignore:
      digestVerificationFailure: true
    selectors: [...]
```

### usdts
```yaml
  usdts:
  - path: "/caminho/binario"
    provider: "test"            # provedor da probe USDT
    name: "usdt0"               # nome da probe
    args: [...]
    selectors: [...]
```

### lsmhooks
```yaml
  lsmhooks:
  - hook: "file_open"           # nome do hook LSM (ver security/security.c)
    args: [...]
    selectors: [...]
```

### lists
```yaml
  lists:
  - name: "dups"                # nome arbitrário, referenciado em call: "list:dups"
    type: "syscalls"            # syscalls | generated_syscalls | generated_ftrace
    pattern: "^ksys_"           # (só generated_ftrace) regex de funções
    values:                     # funções da lista
    - "sys_dup"
    - "sys_dup2"
```

---

## 3. Campo `args` (argumentos a capturar)

```yaml
    args:
    - index: 0                  # posição do argumento na função (base 0)
      type: "file"              # tipo (ver tabela abaixo)
      label: "arquivo"          # (opcional) rótulo no evento
      returnCopy: true          # (char_buf) lê o valor no retorno, não na entrada
      sizeArgIndex: 3           # (char_buf) índice do arg que diz o tamanho (conta a partir de 1!)
      maxData: true             # (char_buf) lê até ~327 KB em vez de 4 KB
      resolve: "mm.owner.comm"  # (opcional) extrai campo interno de struct
      btfType: "sockaddr_in"    # (opcional) "casta" o arg para outra struct antes do resolve
      btfTypeModule: "af_alg"   # (opcional) struct definida por módulo do kernel
```

**Tipos de argumento mais usados:** `int`, `uint32`, `int64`, `uint64`, `size_t`, `string`, `char_buf`, `char_iovec`, `fd`, `file`, `path`, `dentry`, `sock`, `skb`, `sockaddr`, `cred`, `linux_binprm`, `capability`, `kernel_cap_t`, `syscall64`, `bpf_attr`, `user_namespace`, `bpf_map`.

---

## 4. Retorno

```yaml
    return: true
    returnArg:
      index: 0
      type: "int"              # tipo do valor de retorno
    returnArgAction: "TrackSock"   # TrackSock | UntrackSock (rastreio de socket)
```

---

## 5. Seletores (`selectors`) — filtros

Regra: dentro de um seletor, os filtros se combinam com **E**. Vários valores num filtro = **OU**. Entre seletores = **OU**, e só a ação do primeiro que casar é aplicada. Máximo **5 seletores** por hook.

| Filtro | Filtra por | Campos/operadores |
|---|---|---|
| `matchArgs` | valor de argumento | `index`/`args`, `operator`, `values`. Operadores: `Equal`, `NotEqual`, `Prefix`, `Postfix`, `Mask`, `GreaterThan`/`GT`, `LessThan`/`LT`, `InRange`, `NotInRange`, `InMap`, `NotInMap`, `FileType`, `NotFileType`, `SubString`, e de rede: `SAddr`, `DAddr`, `SPort`, `DPort`, `Protocol`, `Family`, `State` (+ variações `Not...`/`...Priv`) |
| `matchReturnArgs` | valor de retorno | `operator`: `Equal`, `NotEqual`, `Prefix`, `Postfix` |
| `matchData` | campo do `current_task`/`pt_regs` | precisa de bloco `data:` (`source`, `resolve`, `type`); mesmos operadores de `matchArgs` |
| `matchCmdArgs` | argv do processo | `index` (0–31), `operator`: `Equal`, `NotEqual`, `Prefix`, `NotPrefix`, `Postfix`, `NotPostfix` |
| `matchPIDs` | PID | `operator`: `In`, `NotIn`; `followForks`, `isNamespacePID` |
| `matchBinaries` | caminho do binário | `operator`: `In`, `NotIn`, `Prefix`, `NotPrefix`, `Postfix`, `NotPostfix`; `followChildren` |
| `matchParentBinaries` | binário do pai | iguais ao `matchBinaries`; exige `--parents-map-enabled` |
| `matchNamespaces` | namespace | `namespace` (`Mnt`,`Pid`,`Net`,`User`,`Cgroup`,`Uts`,`Ipc`,`Time`), `operator` `In`/`NotIn`, `values` (número ou `host_ns`) |
| `matchNamespaceChanges` | troca de namespace | `operator` `In`/`NotIn` + tipo de namespace |
| `matchCapabilities` | capabilities atuais | `type` (`Effective`,`Permitted`,`Inheritable`), `operator` `In`/`NotIn`, `values` (ex.: `CAP_SYS_ADMIN`) |
| `matchCapabilityChanges` | ganho de capability | idem + `isNamespaceCapability` |
| `matchCEL` | expressão CEL | `expr` avaliada no kernel |
| `matchUserCallers` | pilha de chamadas (só uprobe) | `depth`, `symbol` ou `startRange`/`endRange` |
| `matchWorkloads` | pods/contêineres K8s | **não funciona fora do Kubernetes** |

Campos de `matchArgs`:
```yaml
    - matchArgs:
      - index: 1            # posição do arg na função
        operator: "Prefix"
        values:
        - "/etc"
```

---

## 6. Ações (`matchActions` / `matchReturnActions`)

```yaml
      matchActions:
      - action: Post
```

| Ação | Onde roda | Parâmetros |
|---|---|---|
| `Post` | kernel | `rateLimit` (ex.: `5m`), `rateLimitScope` (`thread`/`process`/`global`), `kernelStackTrace`, `userStackTrace`, `imaHash` |
| `NoPost` | kernel | executa as outras ações sem gerar evento |
| `Sigkill` | kernel | mata o processo |
| `Signal` | kernel | `argSig` (número do sinal) |
| `Override` | kernel | `argError` (valor de retorno forçado); kprobe/lsm/uprobe |
| `NotifyEnforcer` | kernel | `argError`, `argSig` (+ bloco `enforcers`) |
| `TrackSock` / `UntrackSock` | kernel | `argSock` (índice do socket) |
| `GetUrl` | userspace | `argUrl` |
| `DnsLookup` | userspace | `argFqdn` |
| `Set` | uprobe/USDT | `argIndex`, `argValue` |

`matchReturnActions` aceita as mesmas ações, mas disparadas no retorno da função.

---

## 7. `spec.options`

```yaml
  options:
  - name: "policy-mode"
    value: "monitor"        # monitor | enforce
```

| Opção | Valores | Efeito |
|---|---|---|
| `policy-mode` | `monitor`, `enforce` | ignora ou executa as ações de bloqueio |
| `disable-kprobe-multi` | `0`/`1` | desativa o kprobe multi link |
| `disable-uprobe-multi` | `0`/`1` | desativa o uprobe multi link |
| `uprobe-heap-size` | inteiro | tamanho dos heaps de uprobe/usdt |

---

## 8. Limites (porque o BPF precisa ser limitado)

- Máximo **5 seletores** por hook.
- Máximo **5 `matchArgs`** por seletor (um por índice).
- Máximo **4 valores** por `matchArgs` (operadores como `Equal`, `GT`, `LT`).
- Máximo **4 PIDs** por `matchPIDs`.
- Máximo **4 valores** por `matchNamespaces` (10 em kernel ≥ 5.3).
- Arquivos (`fd`/`file`): **8 valores** em kernel ≥ 5.3, 2 em < 5.3.
- Prefixo de string: até **256** caracteres. Postfix: até **127** (87 em < 5.3).
- `followChildren`: no máximo **64** blocos `matchBinaries`/`matchParentBinaries` com ele.
- Para conjuntos grandes de valores, use `InMap`/`NotInMap` (limitado só pela memória).

---

## 9. Exigências de kernel por recurso

| Recurso | Exige |
|---|---|
| `Override` | `CONFIG_BPF_KPROBE_OVERRIDE=y` (e `security_*` a partir do 5.7) |
| `lsmhooks` | BPF LSM ativo (`bpf` em `/sys/kernel/security/lsm`) |
| `fentries` | kernel ≥ 6.1 com BTF |
| `resolve` | kprobe ≥ 5.4; LSM ≥ 5.7; não há em uprobe |
| `matchParentBinaries` | `--parents-map-enabled` |
| rastreio de socket (`TrackSock`) | kernel ≥ 5.3 |
| `rateLimit` | kernel ≥ 5.3 |
| `imaHash` | kernel ≥ 5.11 (recomendado 6.1+) |
