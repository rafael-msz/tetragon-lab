# tetragon-lab
Laboratório de testes do framework tetragon.

## Especificação de Ambiente
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
