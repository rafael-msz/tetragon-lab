# Tetragon em Docker — Comandos Complementares

Continuação de `tetragon-comandos.md`. Pressupõe que os passos 1 a 6 daquele arquivo já foram executados e que o contêiner `tetragon` está "Up".

| Parte | Conteúdo | Quando usar |
|---|---|---|
| A | Verificações e gerenciamento de políticas | Agora |
| B | Opções desligadas por padrão | Quando precisar |
| C | Extras | Etapa posterior |

---

# Parte A — Verificações e gerenciamento de políticas

## A1. Requisitos do kernel

Rode antes de instalar numa máquina nova (a VPS, por exemplo).

```bash
uname -r                          # deve ser 5.4 ou superior
ls -l /sys/kernel/btf/vmlinux     # o arquivo precisa existir (BTF)
stat -fc %T /sys/fs/cgroup        # esperado: cgroup2fs
cat /sys/kernel/security/lsm      # "bpf" na lista = lsmhooks disponíveis
```

Com o Tetragon rodando, veja os recursos que ele detectou:

```bash
sudo docker exec tetragon tetra probe
sudo docker exec tetragon tetra probe config | grep -E 'BTF|KPROBE_OVERRIDE|BPF_LSM'
```

- `CONFIG_BPF_KPROBE_OVERRIDE=y`: a ação `Override` funciona
- `bpf` ausente em `/sys/kernel/security/lsm`: `lsmhooks` não funcionam. Para ativar, adicione `bpf` ao parâmetro `lsm=` em `/etc/default/grub`, rode `sudo update-grub` e reinicie.

## A2. Verificar a assinatura da imagem

Confirma que a imagem é oficial e não foi adulterada. Recomendado sobretudo na VPS.

```bash
sudo apt install -y cosign

cosign verify \
  --certificate-identity-regexp "https://github.com/cilium/tetragon/.*" \
  --certificate-github-workflow-repository cilium/tetragon \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  quay.io/cilium/tetragon:v1.7.0 | jq
```

Na saída, o `Issuer` deve ser `https://token.actions.githubusercontent.com`. Se o comando falhar, não use a imagem antes de investigar.

## A3. Testar uma política sem reiniciar o Tetragon

Útil para testar rapidamente. A política fica ativa só até o próximo `docker restart`.

A pasta `/etc/tetragon` já está montada no contêiner, então use uma subpasta de testes, **fora** de `tetragon.tp.d`:

```bash
sudo mkdir -p /etc/tetragon/teste
sudo cp politica.yaml /etc/tetragon/teste/

# carregar
sudo docker exec tetragon tetra tracingpolicy add /etc/tetragon/teste/politica.yaml

# conferir
sudo docker exec tetragon tetra --timeout 60s tracingpolicy list

# descarregar (use o metadata.name da política, não o nome do arquivo)
sudo docker exec tetragon tetra tracingpolicy delete <nome-da-politica>
```

Quando a política estiver pronta, torne-a permanente:

```bash
sudo mv /etc/tetragon/teste/politica.yaml /etc/tetragon/tetragon.tp.d/
sudo docker restart tetragon
```

## A4. Modo monitor e enforce

Uma política com `Sigkill` ou `Override` pode rodar em `monitor`: ela registra o que faria, mas não bloqueia. Use isso para validar antes de bloquear de verdade.

**Fixo no arquivo da política** (vale sempre):

```yaml
spec:
  options:
  - name: "policy-mode"
    value: "monitor"      # ou "enforce"
```

**Ao carregar** (sobrepõe o arquivo):

```bash
sudo docker exec tetragon tetra tracingpolicy add --mode monitor /etc/tetragon/teste/politica.yaml
```

**Com a política já carregada** (vale até o próximo restart):

```bash
sudo docker exec tetragon tetra tracingpolicy set-mode <nome-da-politica> enforce
sudo docker exec tetragon tetra tracingpolicy set-mode <nome-da-politica> monitor
```

Na coluna `MODE` do `tracingpolicy list`, o valor `monitor_only` indica que a política não tem nenhuma ação de bloqueio.

---

# Parte B — Opções desligadas por padrão

## B1. Métricas (Prometheus)

As métricas precisam da porta publicada, o que exige recriar o contêiner:

```bash
echo ":2112" | sudo tee /etc/tetragon/tetragon.conf.d/metrics-server
echo "binary" | sudo tee /etc/tetragon/tetragon.conf.d/metrics-label-filter

sudo docker rm -f tetragon
sudo docker run -d --name tetragon --restart unless-stopped \
  --hostname "$(hostname)" \
  --pid=host --cgroupns=host --privileged \
  -p 2112:2112 \
  -v /etc/tetragon:/etc/tetragon \
  -v /sys/kernel:/sys/kernel \
  -v /var/log/tetragon:/var/log/tetragon \
  quay.io/cilium/tetragon:v1.7.0

curl -s http://localhost:2112/metrics | head -20
```

Na VPS, não exponha a porta 2112 à internet: use `-p 127.0.0.1:2112:2112`.

Para desligar: `sudo rm /etc/tetragon/tetragon.conf.d/metrics-server` e recrie o contêiner **sem** o `-p 2112:2112`.

## B2. Limite de memória

Aplica-se sem reiniciar:

```bash
sudo docker update --memory 512m --memory-swap 512m tetragon
sudo docker stats --no-stream tetragon     # acompanhar o consumo
```

Se o Tetragon começar a reiniciar sozinho (`docker ps` mostra "Restarting"), o limite está baixo. Para remover o limite, recrie o contêiner sem a opção.

## B3. Bloqueio persistente (recomendado na VPS)

Mantém as políticas ativas no kernel mesmo se o agente cair, para que um invasor não consiga desligar a proteção derrubando o contêiner.

```bash
echo "true" | sudo tee /etc/tetragon/tetragon.conf.d/keep-sensors-on-exit
sudo docker restart tetragon
```

**Atenção:** com essa opção, `docker stop` **não** desliga mais os bloqueios. Teste primeiro na VM e confira o procedimento completo (inclusive como desfazer) em https://tetragon.io/docs/concepts/enforcement/persistent-enforcement/, porque o comportamento em contêiner pode exigir ajustes.

Para desligar: `sudo rm /etc/tetragon/tetragon.conf.d/keep-sensors-on-exit` e `sudo docker restart tetragon`.

---

# Parte C — Extras (etapa posterior)

> Nada desta parte é necessário agora. Use quando chegar à fase de simulação e contenção.

## C1. Organizar as políticas em subpastas

O Tetragon lê subpastas de `tetragon.tp.d` automaticamente.

```bash
sudo mkdir -p /etc/tetragon/tetragon.tp.d/{rede,arquivos,exec,escape}
```

## C2. Filtrar eventos

**Por tipo de evento** (`process_exec`, `process_exit`, `process_kprobe`, `process_tracepoint`, `process_lsm`):

```bash
sudo tail -f /var/log/tetragon/tetragon.log | jq -c 'select(has("process_kprobe"))'
```

**Por contêiner:**

```bash
ID=$(sudo docker inspect -f '{{.Id}}' <nome-do-conteiner> | cut -c1-12)
sudo tail -f /var/log/tetragon/tetragon.log \
  | jq -c --arg id "$ID" 'select([.[]? | objects | .process.docker? // empty] | any(startswith($id)))'
```

**Por política:**

```bash
sudo tail -f /var/log/tetragon/tetragon.log | jq -c 'select(.process_kprobe.policy_name == "<nome-da-politica>")'
```

## C3. Contêineres-alvo para simulação

> **Inseguros de propósito.** Crie apenas durante os testes e remova em seguida. Nunca deixe na VPS.

```bash
sudo docker network create lab-net

# referência, sem privilégios extras
sudo docker run -d --name lab-normal --label tetragon-lab=1 --network lab-net \
  alpine:3.20 sleep infinity

# soquete do Docker exposto (cenário clássico de escape)
sudo docker run -d --name lab-sock --label tetragon-lab=1 --network lab-net \
  -v /var/run/docker.sock:/var/run/docker.sock alpine:3.20 sleep infinity

# contêiner privilegiado
sudo docker run -d --name lab-priv --label tetragon-lab=1 --network lab-net \
  --privileged alpine:3.20 sleep infinity

# capability perigosa
sudo docker run -d --name lab-caps --label tetragon-lab=1 --network lab-net \
  --cap-add SYS_ADMIN alpine:3.20 sleep infinity
```

Acessar e listar:

```bash
sudo docker exec -it lab-sock sh
sudo docker ps --filter label=tetragon-lab=1
```

Remover tudo:

```bash
sudo docker rm -f $(sudo docker ps -aq --filter label=tetragon-lab=1)
sudo docker network rm lab-net
```

## C4. Backup e restauração

Salva configuração e políticas para versionar no GitHub e replicar na VPS.

```bash
# gerar
sudo tar -czf tetragon-backup-$(date +%Y%m%d-%H%M).tar.gz -C / etc/tetragon

# restaurar (em outra máquina, após os passos 1 a 5 do arquivo principal)
sudo tar -xzf tetragon-backup-AAAAMMDD-HHMM.tar.gz -C /
sudo docker restart tetragon
```

## C5. Sincronização de horário

A correlação de eventos (Wazuh, mais adiante) depende de horário correto nas máquinas.

```bash
timedatectl                       # procure "System clock synchronized: yes"
sudo timedatectl set-ntp true     # ativa, se estiver "no"
```

## C6. Fases futuras (ainda sem comandos)

- **Simulações:** scripts em `simulacoes/`, um por técnica MITRE ATT&CK for Containers
- **Wazuh:** leitura de `/var/log/tetragon/tetragon.log` e regras de correlação
- **Hardening da VPS:** firewall e SSH
