# scripts/

Runbooks executáveis do laboratório. Rode sempre a partir da raiz do repositório.

| Script | O que faz |
|--------|-----------|
| `01-instalar.sh` | Instalação limpa de Docker + Tetragon v1.7.0. `--clean` força a limpeza prévia. |
| `02-sincronizar-policies.sh` | Copia `policies/` → `/etc/tetragon/tetragon.tp.d/` e recarrega. **Roda um pré-check** que impede subir um YAML inválido (que derrubaria o agente). |
| `03-lab.sh` | `create` / `reset` / `status` / `destroy` dos contêineres-alvo (`lab-sock`, `lab-priv`). |
| `04-simular-ataques.sh` | Dispara as técnicas para validar a detecção. Aceita números de técnica (ex.: `... 3 5`). |
| `gerar-catalogo.sh` | Lê `policies/**/*.yaml` e **regenera a tabela** em `policies/README.md`. Rode após adicionar/editar uma política. |
| `filtro.jq` | Filtro `jq` que torna os eventos legíveis (uma linha por evento, só de contêiner). |

## Manter o catálogo das políticas

A tabela em `policies/README.md` **não é editada à mão** — é gerada:

```bash
bash scripts/gerar-catalogo.sh
```

Opcional: o workflow em `.github/workflows/catalogo.yml` roda isso sozinho a cada push que mexe em
`policies/`, mantendo a tabela sempre em dia sem você precisar lembrar.

## Fluxo típico

```bash
sudo bash scripts/01-instalar.sh
sudo bash scripts/02-sincronizar-policies.sh
sudo bash scripts/03-lab.sh create

# Terminal A — observar
sudo tail -n0 -f /var/log/tetragon/tetragon.log | jq -rc -f scripts/filtro.jq
# Terminal B — atacar
sudo bash scripts/04-simular-ataques.sh
```

> ⚠️ `lab-sock`/`lab-priv` são inseguros de propósito. Só em VM/VPS isolada. Veja o README raiz.
