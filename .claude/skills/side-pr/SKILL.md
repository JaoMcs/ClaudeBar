---
name: side-pr
description: Abrir um PR de arquivos editados no checkout principal sem trocar a branch dele (worktree temporário + pii-check). Usar quando agentes/trilhas estiverem usando o checkout para merge.
---
1. Corpo do PR em português num arquivo temporário (o que muda, por quê, "Não verificado").
2. `scripts/dev/side-pr.sh <branch> "<título>" <corpo.md> <arquivos...>` → número do PR. Ele recusa enviar se `pii-check.sh` achar caminho da máquina ou e-mail.
3. Revisão: skill `review-pr`. Merge: `scripts/dev/merge.sh <pr>`. Depois `git checkout -- <arquivos>` e `git pull --ff-only` no checkout principal.
