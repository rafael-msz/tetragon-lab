# Campos essenciais para monitorar atividade maliciosa em contêineres (Tetragon)

Referência ampla, para expandir as técnicas de monitoramento. Organizado por **o que o campo revela**. Todos os caminhos são relativos ao JSON de um evento (`process_exec`, `process_kprobe`, etc.).

---

## 1. Identificação e contexto (responde "ONDE e QUEM")

| Campo | Revela | Por que importa |
|---|---|---|
| chave do evento (`process_exec`, `process_exit`, `process_kprobe`, `process_tracepoint`, `process_lsm`, `process_loader`) | o tipo de atividade | define o que você está vendo |
| `process.docker` | ID do contêiner | separa contêiner de host; é a chave de correlação por contêiner |
| `process.pod` (K8s) | namespace/pod | vazio em Docker puro |
| `node_name` / `time` | máquina e horário | base da correlação temporal |
| `process.binary` | o programa executado | o "o quê" |
| `process.arguments` | a linha de comando | o detalhe do "o quê" (alvo, flags) |
| `process.cwd` | diretório de trabalho | contexto; `cwd` estranho pode indicar algo |

---

## 2. Execução e linhagem (responde "QUEM CHAMOU QUEM")

| Campo | Revela | Detecta |
|---|---|---|
| `process.exec_id` | identidade única da execução | base para remontar a árvore |
| `process.parent_exec_id` | identidade do pai | liga filho ao pai |
| `parent.binary` / `parent.arguments` | quem executou o processo | shell vindo de servidor web, processos filhos anômalos |
| `process.pid` / `tid` | PID/TID (host) | referência; não use como chave única |
| `process.flags` | como o processo surgiu (`execve`, `clone`, `rootcwd`...) | execução sem execve, truques de fork |
| **`process.in_init_tree`** | se descende do init do contêiner | **`false` = injetado** (docker exec/kubectl exec) — alguém "entrou" no contêiner |

---

## 3. Privilégio e credenciais (responde "COM QUANTO PODER")

| Campo | Revela | Detecta |
|---|---|---|
| `process.process_credentials.uid`/`euid`/`suid` | identidade do usuário | execução como root, mudança de UID |
| `process.process_credentials.gid`/`egid` | grupo | escalada de grupo |
| `process.cap.effective` | capabilities em uso | contêiner com poder além do necessário (`CAP_SYS_ADMIN`, `CAP_SYS_PTRACE`, `CAP_NET_ADMIN`, `CAP_DAC_READ_SEARCH`) |
| `process.cap.permitted` | capabilities disponíveis | superfície de ataque do contêiner |
| `process.binary_properties.setuid`/`setgid` | binário SUID/SGID executado | escalada via SUID (T1548) |
| `process.binary_properties.privileges_changed` | privilégio subiu na execução | momento exato da escalada |

> Compare o `cap.effective` do processo com o do host: um contêiner "normal" tem conjunto reduzido; um privilegiado tem quase tudo. Capability a mais = alerta.

---

## 4. Isolamento e namespaces (responde "AINDA ESTÁ PRESO?") — núcleo do escape

| Campo | Revela | Detecta |
|---|---|---|
| `process.ns.mnt.is_host` | namespace de montagem é o do host | **escape**: contêiner vendo o FS do host |
| `process.ns.pid.is_host` | namespace de PID é o do host | escape / `--pid=host` |
| `process.ns.net.is_host` | rede é a do host | `--net=host`, rede do host |
| `process.ns.user.is_host` | user namespace | criação de user namespace por não-privilegiado (T1611) |
| `process.ns.cgroup` / `.uts` / `.ipc` | demais namespaces | mudanças de isolamento |

> Regra de ouro: um processo cujo `process.docker` existe **mas** tem algum `ns.*.is_host == true` (fora de `user`) é forte indício de escape.

---

## 5. Sistema de arquivos (responde "TOCOU O QUÊ")
Capturado por kprobes/LSM (`security_file_open`, `security_file_permission`, `fd_install`, `sys_write`...).

| O que vigiar | Exemplos de caminho | Detecta |
|---|---|---|
| Soquetes de runtime | `/run/docker.sock`, `containerd.sock` | controle do host |
| Mecanismos de escape | `/proc/sys/kernel/core_pattern`, `/sys/kernel/uevent_helper`, `release_agent` | escape pelo kernel |
| Dispositivos brutos | `/dev/mem`, `/dev/sda`, `/dev/kmsg` | acesso direto a disco/memória |
| Credenciais | `/etc/shadow`, `~/.ssh/`, `~/.docker/config.json`, tokens | roubo de credenciais (T1552) |
| Metadados do contêiner | `/.dockerenv`, `/proc/self/cgroup` | reconhecimento (T1613) |
| Montagem do host | `/host`, `/mnt/host`, `/proc/1/root` | escape por montagem |

Campo útil: `args[].file.path` (ou o tipo `string` do arg) traz o caminho; `returnMatchArgs` detecta **tentativa falha** de acesso.

---

## 6. Rede (responde "FALOU COM QUEM")
Capturado por kprobes como `tcp_connect`, `tcp_close`, `sk_alloc`, ou `security_socket_connect`.

| Campo (via `args[].sock_arg`) | Revela | Detecta |
|---|---|---|
| `daddr` / `dport` | destino da conexão | C2, reverse shell, exfiltração |
| `saddr` / `sport` | origem | — |
| `family` / `protocol` | IPv4/IPv6, TCP/UDP | — |
| `state` | estado do socket | conexões estabelecidas |

Padrões a vigiar: conexão **de saída** de um contêiner que não deveria iniciar conexões; porta/destino incomum; shell com socket (reverse shell).

---

## 7. Mapa: categoria de ataque → o que monitorar

| Categoria (MITRE) | Evento/hook | Campos-chave |
|---|---|---|
| Execução / injeção em contêiner (T1059, Deploy/exec) | `process_exec` | `binary`, `arguments`, `in_init_tree=false`, `parent.binary` |
| Transferência de ferramentas (T1105) | `process_exec` | `binary` = apk/apt/curl/wget dentro de contêiner |
| Reconhecimento (T1613) | `process_exec` / file open | leitura de `/proc/self/cgroup`, `/.dockerenv` |
| Escalada de privilégio (T1548) | `process_exec` | `binary_properties.setuid`, `privileges_changed`, `capset` |
| Escape para o host (T1611) | kprobe/LSM + `process_exec` | `ns.*.is_host`, `matchNamespaceChanges`, `sys_mount`, `setns`, `docker.sock` |
| Acesso a credenciais (T1552) | file open (LSM) | caminho `/etc/shadow`, `~/.ssh`, tokens |
| Persistência | file write | `/etc/cron*`, `/host/...`, `authorized_keys` |
| Defesa/evasão | file / exec | execução de binário deletado (`binary_properties.file` com `links:0`), exec fileless (`/proc/self/fd/*`) |
| Impacto / C2 / exfiltração | network kprobe | `daddr`/`dport`, conexões de saída |
| Módulos de kernel | kprobe | `security_kernel_module_request` |
| Abuso de eBPF | kprobe | `bpf_check`, `security_bpf_*` |

---

## 8. Os 8 campos que, se você só pudesse olhar alguns

Para começar a expandir, estes dão o maior retorno:

1. `process.binary` + `process.arguments` — o quê
2. `parent.binary` — quem chamou
3. `process.docker` — qual contêiner
4. `process.in_init_tree` — foi injetado?
5. `process.ns.mnt.is_host` — escapou?
6. `process.cap.effective` — com quanto poder
7. `process_credentials.euid` — é root?
8. caminho do arquivo acessado — tocou algo sensível?

---

## 9. Pré-requisitos de configuração

Para alguns campos aparecerem, ligue no `tetragon.conf.d`:

| Campo | Exige |
|---|---|
| `cap.*`, `process_credentials.*`, `binary_properties.*` | `enable-process-cred: true` |
| `ns.*` | `enable-process-ns: true` |
| lista de ancestrais | `enable-ancestors` |
| `parent` em todos os eventos / `matchParentBinaries` | `parents-map-enabled: true` |

> `enable-process-cred` e `enable-process-ns` você já ativou na instalação.
