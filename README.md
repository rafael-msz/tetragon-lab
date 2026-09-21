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
## Configuração do Tetragon
Para reescrever as configurações do tetragon, crie o diretório `/etc/tetragon.conf.d/`, onde as configurações ficarão guardadas.

### Exportação de logs
Como um usuário com privilégios, crie um arquivo de configuração `export-file` dentro do diretório `/etc/tetragon/tetragon.conf.d/export-file`
```
echo "/var/log/tetragon/tetragon.log" | sudo tee -a /etc/tetragon/tetragon.conf.d/export-file
systemctl restart tetragon
```

### Habilitar credênciais de processos
Em linux, cada processo é associado a um usuário, grupo e capabilidades conhecidads como _process credentials_. Para habilitar o Tetragon para ver essas credenciais:
1. Crie o arquivo: `enable-process-cred` no diretório `/etc/tetragon/tetragon.conf.d/`
2. Escreva "true" no arquivo.
```
echo "true" | sudo tee -a /etc/tetragon/tetragon.conf.d/enable-process-cred
systemctl restart tetragon
```
