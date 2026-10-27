# Cenário 1 — Escape via `docker.sock`

Cadeia de ataque para o laboratório de defesa com Tetragon. Contêiner-alvo: `lab-sock` (com `/var/run/docker.sock` montado). Objetivo: reconhecer as etapas, correlacioná-las e conter.

> Reproduza apenas na VM do Proxmox, nunca na VPS. Remova o `lab-sock` ao terminar.
> Confirme os IDs das técnicas em attack.mitre.org/matrices/enterprise/containers (a MITRE reorganiza as colunas periodicamente).

---

## Visão geral da cadeia

| # | Etapa | Técnica MITRE | Coluna da matriz |
|---|---|---|---|
| 1 | Reconhecimento: achar o soquete e listar contêineres | T1613 – Container and Resource Discovery | Discovery |
| 2 | Criar um contêiner novo com o disco do host montado | T1610 – Deploy Container | Execution |
| 3 | Acessar/escrever no sistema de arquivos do host | T1611 – Escape to Host | Privilege Escalation |

A ideia da correlação: as três etapas, vindas do **mesmo contêiner**, numa **janela curta de tempo**, formam o padrão de um escape. Uma etapa isolada pode ser ruído; a sequência não.

---

## Tabela detalhada

### Etapa 1 — Discovery (T1613)

| Campo | Valor |
|---|---|
| Comando (dentro do `lab-sock`) | `ls -l /var/run/docker.sock` e depois `curl --unix-socket /var/run/docker.sock http://localhost/containers/json` |
| O que o atacante faz | Confirma que o soquete existe e usa a API do Docker para listar contêineres |
| Evento esperado no Tetragon | `process_exec` de `/usr/bin/curl` (ou `ls`) com `process.docker` = ID do `lab-sock`; e a abertura do arquivo `/var/run/docker.sock` |
| Hook de detecção | `process_exec` (nativo) + kprobe em `security_file_open` filtrando o caminho do soquete |

### Etapa 2 — Deploy Container (T1610)

| Campo | Valor |
|---|---|
| Comando (dentro do `lab-sock`) | Via API, cria e inicia um contêiner com `/` do host montado em `/host`. Ex.: `POST /containers/create` com `Binds: ["/:/host"]`, depois `POST /containers/{id}/start` |
| O que o atacante faz | Pede ao Docker do **host** para subir um contêiner que enxerga o disco da VM |
| Evento esperado no Tetragon | No **host**: `process_exec` de `runc` / `containerd-shim` criando o novo contêiner, logo após a atividade do `lab-sock` |
| Hook de detecção | `process_exec` (nativo); correlacionar com a Etapa 1 pelo tempo e pela proximidade |

### Etapa 3 — Escape to Host (T1611)

| Campo | Valor |
|---|---|
| Comando (no contêiner novo) | `chroot /host sh -c 'id > /tmp/prova_escape'` ou escrever num arquivo do host, como `/host/etc/cron.d/...` |
| O que o atacante faz | Lê ou escreve no sistema de arquivos do host a partir do contêiner recém-criado |
| Evento esperado no Tetragon | `process_exec` de `chroot`; escrita em caminho do host; possivelmente `sys_mount` |
| Hook de detecção | kprobe em `security_file_open` / `sys_write` nos caminhos sensíveis; `matchNamespaceChanges` se houver troca de namespace |

---

## Ponto de contenção

O elo mais frágil da cadeia é a **Etapa 1**: o acesso ao `docker.sock` de dentro de um contêiner. Bloqueando ali, as etapas 2 e 3 nem começam.

Estratégia híbrida (como combinamos):

- **Tetragon**: `Override` no acesso ao `/var/run/docker.sock` quando vem de um processo dentro de contêiner (namespace diferente do host). A operação falha, o processo continua vivo.
- **Correlação (Wazuh, fase futura)**: se as três etapas aparecerem em sequência, derrubar o contêiner (`docker stop`) e alertar.

Testar sempre em modo `monitor` antes de `enforce`.

---

## Política de detecção (esqueleto para validar na Parte A3)

> Ilustrativa. Teste com `tetra tracingpolicy add` e ajuste os caminhos/hook conforme o que aparecer nos eventos do seu kernel.

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: "acesso-docker-sock"
spec:
  kprobes:
  - call: "security_file_open"
    syscall: false
    args:
    - index: 0
      type: "file"
    selectors:
    - matchArgs:
      - index: 0
        operator: "Equal"
        values:
        - "/run/docker.sock"
      # Só processos DENTRO de contêiner (fora do namespace de montagem do host)
      matchNamespaceChanges:
      - operator: "In"
        values:
        - "Mnt"
      matchActions:
      - action: Post        # troque para Override (argError: -1) na fase de contenção
```

Pontos a confirmar no laboratório:
- O caminho real do soquete nos eventos pode ser `/run/docker.sock` (o `/var/run` costuma ser link para `/run`).
- Qual hook captura melhor o acesso: `security_file_open`, `fd_install` ou a conexão ao soquete unix. Decida pelo que aparecer no `tetra getevents`.
- Como distinguir "dentro do contêiner" x "host": teste `matchNamespaceChanges` e, se não bastar, filtre pelo `process.docker` na exportação.

---

## Roteiro de execução no laboratório

1. Subir o alvo: `lab-sock` (ver `tetragon-comandos-complementares.md`, Parte C3).
2. Carregar a política em modo monitor (Parte A3/A4).
3. Abrir os eventos filtrando pelo contêiner (Parte C2).
4. Executar as três etapas dentro do `lab-sock` e registrar os eventos de cada uma.
5. Montar a correlação (anotar exec_id, process.docker e horários).
6. Trocar a Etapa 1 para `Override` e repetir: a cadeia deve parar.
7. Remover o `lab-sock`.
