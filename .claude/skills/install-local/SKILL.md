---
name: install-local
description: Instalar a build da main no Mac do dono para ele testar (fecha o app aberto, manda o anterior para o Lixo, abre o novo). Usar quando pedirem para "rodar", "instalar" ou "abrir" o app para teste.
---
1. Confirme que a main local está atualizada (`git pull --ff-only`) e sem mudanças.
2. `scripts/dev/install-local.sh` → `instalado=<nome> versao=<v> build=<n>`.
3. Diga ao dono a versão/build e que a anterior está no Lixo. Não mexa no `settings.json`: se os hooks estiverem velhos, o próprio app oferece migrar com diff.
