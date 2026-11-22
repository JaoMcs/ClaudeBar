---
name: wire
description: Protocolo compacto para TODA mensagem entre agentes (prompt de subagente, retorno, SendMessage). Usar sempre que escrever para outro agente ou devolver resultado a um. Não usar para texto que vai ao usuário ou ao GitHub.
---
# wire

Máquina lê, gente não. Menor número de tokens que preserva o sentido.

## Regras
- Linhas `CHAVE:valor`. Listas com `,`. Sem artigos, cortesia, explicação ou repetição do óbvio.
- Caminho, número ou id em vez de conteúdo. Nunca colar arquivo, diff ou log que o outro pode ler.
- Só o que o destinatário precisa para ESTA task. Nada de histórico.
- Retorno = JSON minificado no schema pedido. Campo vazio fica de fora. Booleano como `1`/`0`.
- Texto livre só onde o schema pede, ≤ 140 caracteres, estilo telegrama.
- Português ou inglês, o que for mais curto; identificadores no original.

## Chaves
`ROLE` impl|fix|rev|merge · `T` id da task · `SRC` caminho da task · `B` branch · `PR` número · `M` modelo · `DO` passos (`;`) · `F` arquivos · `A` achados · `CI` 1|0 · `NV` não verificado · `RET` schema esperado · `X` proibições extras.

Severidade: `BL` bloqueante · `SG` sugestão · `NIT`.

## Exemplos
Brief:
```
ROLE:impl T:T19 B:feat/ir-para-sessao
SRC:/abs/.planning/06-tasks/T19-ir-para-sessao.md
RET:{"ok":1,"pr":0,"nv":""}
```
Retorno: `{"ok":1,"pr":21,"nv":"tmux;iterm2;foco real"}`
Achados: `{"ci":1,"a":[{"s":"SG","f":"SessionNavigator.swift:111","d":"tmux sem timeout trava Task; timeout:2"}]}`

## Exceção
Commit, PR, comentário no GitHub e mensagem ao usuário: português completo e legível.
