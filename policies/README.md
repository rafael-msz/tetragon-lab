# policies/

`TracingPolicy` do Tetragon, organizadas **por tática do MITRE ATT&CK for Containers**
(uma pasta por tática). A pasta `tetragon.tp.d` é lida recursivamente, então as subpastas
funcionam direto.

## Catálogo

> ⚙️ **Tabela gerada automaticamente** por [`scripts/gerar-catalogo.sh`](../scripts/gerar-catalogo.sh).
> **Não edite à mão.** Adicionou ou mudou uma política? Rode o script e commite.

<!-- CATALOGO:START -->

| Tática | Técnica | Política | Hook | Descrição |
|---|---|---|---|---|
| Command & Control | T1071 | `conexao-saida` | `tcp_connect` | — |
| Credential Access | T1552 | `leitura-credenciais` | `security_file_open` | — |
| Defense Evasion | T1070 | `remocao-indicadores` | `sys_unlinkat` | — |
| Discovery | T1613 | `container-discovery` | `security_file_open` | — |
| Execution | T1105 | `exec-ferramentas-transferencia` | `sys_execve` | — |
| Impact | T1496 | `mineracao-pool` | `tcp_connect` | — |
| Persistence | T1098 | `persistencia-arquivos` | `security_file_open` | — |
| Privilege Escalation | T1611 | `escape-docker-sock` | `security_file_open` | — |
| Privilege Escalation | T1611 | `escape-mount` | `sys_mount` | — |

<!-- CATALOGO:END -->

## Como adicionar uma política

1. Crie o arquivo em `policies/<tatica>/T<ID>-<slug>.yaml`
   (ex.: `privilege-escalation/T1611-escape-pivot-root.yaml`).
2. Siga as [convenções](#convenções) abaixo.
3. Rode `bash scripts/gerar-catalogo.sh` para atualizar a tabela.
4. Carregue com o pré-check: `sudo bash scripts/02-sincronizar-policies.sh`.

## Convenções

- **`kind: TracingPolicy`** — nunca `TracingPolicyNamespaced` (não funciona em Docker puro).
- **Nome do arquivo:** `T<ID>-<slug>.yaml`; a **pasta** define a tática, o **prefixo** define a técnica.
- **`metadata.name`** único em todo o repositório.
- **(Opcional, recomendado)** `metadata.annotations.description` com uma frase — ela entra na
  coluna *Descrição* do catálogo automaticamente:
  ```yaml
  metadata:
    name: "escape-mount"
    annotations:
      description: "Montagem a partir de um contêiner (possível escape)"
  ```
- Começar com a ação **`Post`** (observação); a contenção troca para `Override`/`Sigkill`.
- **Lógica dos seletores:** dentro de um seletor, vários `matchArgs` são **E (AND)**;
  seletores **separados** são **OU (OR)**.

## Sincronizar com o Tetragon

Use [`scripts/02-sincronizar-policies.sh`](../scripts/02-sincronizar-policies.sh): ele roda um
**pré-check** (sem arquivo vazio, `kind` correto, nada de `TracingPolicyNamespaced`) **antes** de
recarregar — porque um único YAML inválido derruba o agente inteiro no restart.

## Limitações e planos B

Observações de validação (atualize conforme testar) ficam em
[`docs/prototipo-2-contencao.md`](../docs/prototipo-2-contencao.md).
