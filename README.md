# tetragon-lab
Laboratório de testes do framework tetragon.

## Especificação de Ambiente da Máquina Virtual
Abaixo estão detalhados os recursos da infraestrutura de hardware, sistema operacional e ferramentas de runtime configuradas para hospedar o Tetragon de forma adequada.

### Proxmox VE e Máquina Virtual
- Hipervisor: Proxmox VE 9.2.0 (pve-manager: 9.2.3)
- Kernel do Host: Linux 7.0.12-1-pve
- Hardware Físico: Intel Core i3-6006U (2.00 GHz, 1 Socket, 4 Cores)
- Tipo de Instância (Guest): VM QEMU/KVM (ID 101)
- Recursos da VM: 2 vCPUs | 2.0 GiB RAM | 32.0 GiB Disco (Boot)

### Sistema Operacional e Containers
- Sistema Operacional (VM): Ubuntu 26.04 LTS (Resolute Raccoon)
- Kernel do Guest: Linux 7.0.0-27-generic
- Docker Engine: 29.7.2 (API v1.55) | Containerd: v2.3.4 | Runc: 1.4.3
- Recomendação Tetragon: 256 MiB a 512 MiB de limite de memória.

## Instalação do Tetragon
Neste laboratório, o Tetragon é instalado como um serviço do Systemd. Systemd é um gerenciador de serviços para sistemas operacionais Linux modernos. É responsável por inicializar o sistema, gerenciar serviços e controlar recursos durante a inicialização do sistema operacional.

1. Use o CURL para baixar o arquivo .tar.gz contendo a última versão do executável.
   ```
   curl -LO https://github.com/cilium/tetragon/releases/download/v1.7.0/tetragon-v1.7.0-amd64.tar.gz
   ```
3. Extraia o arquivo, e rode o script para instalar o Tetragon.
  ```
  tar -xvf tetragon-v1.7.0-amd64.tar.gz
  cd tetragon-v1.7.0-amd64/
  sudo ./install.sh
  ```
4. Por fim, verifique se o Tetragon está ativado:
   ```
   sudo systemctl status tetragon
   ```
5. Para ver o Tetragon em ação basta executar o comando:
   ```
   sudo tetra getevents -o compact
   ```
## Configuração do Tetragon
Para reescrever as configurações do tetragon, há o diretório `/etc/tetragon.conf.d/`, onde as configurações ficam guardadas.

Se o diretório não foi criado durante a instalação: `sudo mkdir /etc/tetragon/tetragon.conf.d/`

### Ordem de Precedência
As configurações de controle do Tetragon podem ser carregadas de um arquivo YAML de acordo com a seguinte ordem de precedência:

1. Diretório `/etc/tetragon/tetragon.conf.d/*`.
2. Arquivo `/etc/tetragon/tetragon.yaml`.
3. Diretórios:
- `/usr/local/lib/tetragon/tetragon.conf.d/*`
- `/usr/lib/tetragon/tetragon.conf.d/*`

### Exportação de logs
O arquivo `export-file-name` dentro do diretório de configurações, define o caminho do arquivo onde o Tetragon escreverá os logs.

Verifique se o arquivo `export-file-name` existe dentro do diretório `/etc/tetragon/tetragon.conf.d/`, e se o caminho especificado no texto do arquivo é _/var/log/tetragon/tetragon.log_. Se o arquivo não existe, utilize os comandos:
```
echo "/var/log/tetragon/tetragon.log" | sudo tee -a /etc/tetragon/tetragon.conf.d/export-file-name
systemctl restart tetragon
```

A configuração `--config-dir` pode ser utilizada para mudar o diretório de onde o Tetragon irá carregar suas configurações.

[Tabela de configurações do Tetragon daemon](https://tetragon.io/docs/reference/daemon-configuration/#configure-tracing-policies-location)

### Habilitar credênciais de processos
Em linux, cada processo é associado a um usuário, grupo e capabilidades conhecidads como _process credentials_. Para habilitar o Tetragon para ver essas credenciais:
1. Crie o arquivo: `enable-process-cred` no diretório `/etc/tetragon/tetragon.conf.d/`
2. Escreva "true" no arquivo.
```
echo "true" | sudo tee -a /etc/tetragon/tetragon.conf.d/enable-process-cred
systemctl restart tetragon
```

### Tracing Policies
Tetragon automaticamente carrega suas políticas de rastreamento (tracing policies) do diretório padrão `/etc/tetragon/tetragon.tp.d/`.

Tracing policies podem ser organizadas em diretórios como `/etc/tetragon/tetragon.tp.d/file-access`, `/etc/tetragon/tetragon.tp.d/network-access`, etc.

A configuração `--tracing-policy-dir` pode ser usada para mudar o diretório padrão de onde as tracing policies são carregadas.

A configuraão `--tracing-policy` pode ser usada para especificar o caminho de uma tracing policy a ser carregada.

## Testes iniciais
Esses testes iniciais demonstram as funcionalidades básicas do Tetragon, ainda sem definir uma Tracing Policy. Para realizar os testes abra dois terminais, em um será executado o Tetragon, no outro um container de teste.

### 1. Obervação de processos
1. No primeiro terminal, faça o Tetragon observar os processos dos programs `bash`, `whoami` e `uname`, para isso execute o comando:
```
sudo tetra getevents -o compact --processes bash,whoami,uname
```

2. No segundo terminal, crie um container de teste que chamaremos de `target`. Após criar container, execute no terminal bash do container os comandos:
- `whoami`: exibe que usuário está logado;
- `uname -r`: exibe a versão do kernel.

```
docker run -d --name target --rm buildpack-deps:26.04-curl sleep infinity
docker exec target bash -c "whoami"
docker exec target bash -c "uname -r"
docker stop target
```

3. Observe os alertas gerados pelo Tetragon no primeiro terminal.

### 2. Filtragem de dados de um processo
1. No primeiro terminal, execute o comando:
```
sudo tetra getevents --processes cat | jq '.process_exec.process // empty | {binary, arguments, docker}'
```
Este comando faz o Tetragon observar eventos relacionados ao program `cat`, e escrever a saída em um objeto JSON. Em seguida ele faz um `pipe` para a utilidade `jq`, que filtra o objeto e cria um novo objeto, mais limpo, contendo apenas com os campos:
- `binary`: nome do arquivo ELF;
- `arguments`: parâmetros fornecidos ao programa;
- `docker`: o ID do container.

2. No segundo terminal, execute os comandos:
````
docker run -d --name target --rm buildpack-deps:26.04-curl sleep infinity
docker exec target cat /etc/hostname
docker inspect -f '{{.Id}}' target | cut -c1-31
docker stop target
````
Essa sequência de comandos cria um docker executa o programa cat em `/etc/hostname` (o padrão são os 12 primeiros caracteres do ID do container), depois lê os primeiros 31 dos 64 caracteres do ID do container.

3. Observe os alertas gerados pelo Tetragon no primeiro terminal.

### 3. Observação de I/O em arquivos
1. No primeiro terminal faça o Tetragon observar os programas `cat` e `bash`. Execute:
```
sudo tetra getevents -o compact --process cat,bash
```

2. No segundo terminal:
a. Crie um diretório chamado `dummy` e arquivos de teste no diretório /tmp do host. Execute:
```
sudo mkdir /tmp/dummy
sudo touch /tmp/dummy/file0.txt
sudo touch /tmp/dummy/file1.txt
```
b. Crie um container com o diretório `/tmp/dummy` do host montado no diretório seu diretório `/tmp`. Dessa forma, o container consegue ler escrever nesse diretório. Execute:
```
docker run \
  -d \
  --name target \
  -v /tmp/dummy:/tmp \
  --rm \
  buildpack-deps:26.04-curl \
  sleep infinity
```

Faça o container `target` listar os arquivos de `/tmp`:
```
docker exec target ls -l tmp
```

Faça o container `target` criar e escrever em arquivos em `/tmp`. Exemplo:
```
ts=$(date +"%Y-%m-%d %H:%M:%S")
docker exec target bash -c "echo Ubuntu was here at $ts >> /tmp/secret.txt"
```

3. Liste o diretório `/tmp/dummy` do host e leia os arquivos para confirmar que o container de fato leu e escreveu neles. Observe os alertas gerados pelo Tetragon no primeiro terminal.

### 4. Observação de requisições feitas por um container
1. No primeiro terminal, faça o Tetragon observar eventos do programa `curl`:
```
sudo tetra getevents -o compact --processes curl
```
2. No segundo termianal, crie um container e baixe arquivos usando o `curl`. Exemplo:
```
docker run -d --name target --rm buildpack-deps:26.04-curl sleep infinity
docker exec target curl -sI https://ebpf.io
docker exec target curl -s http://127.0.0.1
docker stop target
```
3. Observe os alertas gerados pelo Tetragon no primeiro terminal.

## Teste de Bloqueio de Acesso
```
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: "monitorar-segredo"
spec:
  kprobes:
    - call: "security_file_permission"
      syscall: false
      args:
        - index: 0
          type: "file"
        - index: 1
          type: "int"
      selectors:
        - matchArgs:
            - index: 0
              operator: "Equal"
              values:
                - "/tmp/dummy/secret.txt"
            - index: 1
              operator: "Equal"
              values:
                - "4"
          matchActions:
            - action: Sigkill
```
