# Tetragon em Docker — Comandos

Ambiente: Ubuntu Server (VM Proxmox / VPS) · Tetragon `v1.7.0` · sem Kubernetes.

Cada bloco pode ser colado inteiro no terminal. Se algum der erro, guarde a mensagem exata.

**Onde fica cada coisa**

| O quê | Caminho |
|---|---|
| Configuração (1 arquivo por opção) | `/etc/tetragon/tetragon.conf.d/` |
| Políticas (TracingPolicy) | `/etc/tetragon/tetragon.tp.d/` |
| Eventos em JSON | `/var/log/tetragon/tetragon.log` |

---

## 1. Remover tudo (instalação limpa)

> Pule se a máquina nunca teve Docker ou Tetragon. **Apaga todos os contêineres e imagens.**

```bash
sudo docker rm -f $(sudo docker ps -aq) 2>/dev/null
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
  docker-compose-plugin docker-ce-rootless-extras docker.io containerd runc
sudo apt autoremove -y
sudo rm -rf /var/lib/docker /var/lib/containerd \
  /etc/tetragon /var/log/tetragon \
  /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
```

## 2. Atualizar o sistema

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

Depois do reboot, reconecte por SSH.

## 3. Instalar o Docker

```bash
sudo apt install -y ca-certificates curl jq
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker
sudo docker --version
```

## 4. Preparar pastas e configuração do Tetragon

```bash
sudo mkdir -p /etc/tetragon/tetragon.conf.d /etc/tetragon/tetragon.tp.d /var/log/tetragon
echo "/var/log/tetragon/tetragon.log" | sudo tee /etc/tetragon/tetragon.conf.d/export-filename
echo "true" | sudo tee /etc/tetragon/tetragon.conf.d/enable-process-cred
echo "true" | sudo tee /etc/tetragon/tetragon.conf.d/enable-process-ns
```

- `export-filename`: grava os eventos em JSON
- `enable-process-cred`: inclui usuário, grupo e capabilities nos eventos
- `enable-process-ns`: inclui os namespaces (essencial para detectar container escape)

## 5. Baixar e iniciar o Tetragon

```bash
sudo docker pull quay.io/cilium/tetragon:v1.7.0

sudo docker run -d --name tetragon --restart unless-stopped \
  --hostname "$(hostname)" \
  --pid=host --cgroupns=host --privileged \
  -v /etc/tetragon:/etc/tetragon \
  -v /sys/kernel:/sys/kernel \
  -v /var/log/tetragon:/var/log/tetragon \
  quay.io/cilium/tetragon:v1.7.0
```

`--restart unless-stopped` faz o Tetragon voltar sozinho após reiniciar a máquina.

## 6. Verificar

```bash
sudo docker ps --filter name=tetragon          # deve aparecer "Up"
sudo docker logs tetragon | tail -5            # deve terminar em "Listening for events..."
sudo docker exec tetragon tetra --timeout 60s tracingpolicy list
```

Eventos ao vivo (Terminal 1):

```bash
sudo docker exec -it tetragon tetra getevents -o compact
```

No Terminal 2, rode qualquer comando (`ls`) e veja aparecer no Terminal 1. Saia com `Ctrl+C`.

---

## 7. Uso no dia a dia

**Políticas**

```bash
# adicionar ou alterar
sudo cp politica.yaml /etc/tetragon/tetragon.tp.d/
sudo docker restart tetragon

# remover
sudo rm /etc/tetragon/tetragon.tp.d/politica.yaml
sudo docker restart tetragon

# ver as carregadas
sudo docker exec tetragon tetra --timeout 60s tracingpolicy list
```

> Em Docker, use sempre `kind: TracingPolicy` (nunca `TracingPolicyNamespaced`), senão o agente não sobe.

**Configuração**

```bash
# definir uma opção
echo "valor" | sudo tee /etc/tetragon/tetragon.conf.d/<opção>
sudo docker restart tetragon

# remover uma opção (volta ao padrão)
sudo rm /etc/tetragon/tetragon.conf.d/<opção>
sudo docker restart tetragon

# ver as opções atuais
sudo grep -r . /etc/tetragon/tetragon.conf.d/
```

**Eventos e logs**

```bash
sudo docker exec -it tetragon tetra getevents -o compact   # ao vivo
sudo tail -f /var/log/tetragon/tetragon.log | jq -c .      # gravados em JSON
sudo docker logs tetragon | tail -20                       # erros do próprio agente
```

**Ligar, parar e checar o kernel**

```bash
sudo docker stop tetragon
sudo docker start tetragon
sudo docker exec tetragon tetra probe
sudo docker exec tetragon tetra probe config | grep -E 'BTF|KPROBE_OVERRIDE|BPF_LSM'
cat /sys/kernel/security/lsm     # "bpf" na lista = lsmhooks disponíveis
```

**Atualizar a versão do Tetragon**

```bash
sudo docker pull quay.io/cilium/tetragon:<nova-versão>
sudo docker rm -f tetragon
# repita o passo 5 trocando a versão
```

---

## Se o Tetragon não ficar "Up"

```bash
sudo docker logs tetragon
```

Causas mais comuns:

- **`metadata.namespace: Required value`**: há uma política `TracingPolicyNamespaced` na pasta. Troque para `TracingPolicy`.
- **Erro de YAML**: arquivo vazio ou com erro de digitação em `/etc/tetragon/tetragon.tp.d/`. Remova-o e rode `sudo docker restart tetragon`.
- **BTF ausente**: confira com `ls /sys/kernel/btf/vmlinux`.
