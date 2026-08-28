# Sonora — Backend alternativo (Google Cloud Run)

Faz o mesmo que `backend/AcessoWebApp.gs` (Apps Script) faz hoje — `validar`
e `cache` — mas rodando no Google Cloud Run, que **não tem** o limite de
30 execuções simultâneas que contas Google normais têm no Apps Script.

Também tem um endpoint novo, `/gerar-cache`, pensado especificamente pra
biblioteca de ~200 mil músicas que está sendo montada aos poucos: o
`atualizarCacheBiblioteca()` do Apps Script tem um limite duro de 6
minutos por execução, o que não vai dar conta desse volume. `/gerar-cache`
faz a mesma varredura, mas sem esse limite de tempo e mais rápido (processa
várias pastas em paralelo em vez de uma por vez).

**Status: estruturado e pronto pra testar, mas o app Flutter ainda NÃO usa
nada disso pra ler capas/áudio/validação.** `AppConstants.backendBaseUrl`
continua apontando pro Apps Script. O único uso pretendido, por enquanto,
é rodar `/gerar-cache` manualmente pra testar se ele gera o arquivo de
cache corretamente — e como ele escreve no MESMO arquivo do Drive que o
Apps Script já usa, o app continua funcionando normalmente lendo esse
arquivo, sem nenhuma mudança de código nele. Se o teste não der certo, é
só voltar a rodar `atualizarCacheBiblioteca()` no Apps Script como antes —
nada precisa ser desfeito.

## O que precisa fazer, uma vez só, pra colocar isso no ar

1. **Habilitar as APIs necessárias** no projeto `sonora-506315`:
   - Cloud Run API
   - Cloud Build API
   - Google Sheets API
   - Google Drive API (já deve estar habilitada, já é usada pelo app)

2. **Criar uma conta de serviço** (IAM e administrador → Contas de
   serviço → Criar conta de serviço), por exemplo `sonora-backend`. Não
   precisa baixar chave JSON — o Cloud Run usa a identidade da conta
   direto, mais seguro.

3. **Compartilhar a planilha "Log_Acesso_Sonora"** com o e-mail dessa
   conta de serviço (algo tipo
   `sonora-backend@sonora-506315.iam.gserviceaccount.com`), permissão de
   **Editor** — necessário pro `/validar`.

4. **Compartilhar a pasta "Musicas"** (a pasta-pai de "Sonora" no seu
   Drive, onde fica o arquivo `sonora_cache_biblioteca.json`) com o mesmo
   e-mail da conta de serviço, também como **Editor** — necessário pro
   `/gerar-cache` conseguir ler a árvore de pastas inteira (dentro de
   "Musicas" > "Sonora") e sobrescrever o arquivo de cache. Sem esse
   compartilhamento, `/gerar-cache` vai dar erro de permissão.

5. **Conferir o nome da aba** da planilha (a "Página1" no código é só um
   palpite) e ajustar a variável `ABA_NOME` no comando de deploy abaixo se
   for diferente.

6. **Escolher uma senha simples** pra variável `GERAR_CACHE_CHAVE` (só
   pra evitar que alguém aleatoriamente ache a URL e fique gerando o cache
   à toa — não é segurança de verdade, só uma trava básica).

7. **Deploy**, rodando isso dentro desta pasta (`backend-cloudrun/`), no
   seu terminal, com o `gcloud` CLI instalado e logado na sua conta:

   ```
   gcloud run deploy sonora-backend `
     --source . `
     --region us-central1 `
     --allow-unauthenticated `
     --timeout 3600 `
     --memory 1Gi `
     --service-account sonora-backend@sonora-506315.iam.gserviceaccount.com `
     --set-env-vars PLANILHA_ID=1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE,ABA_NOME=Página1,CACHE_FILE_ID=1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP,DRIVE_API_KEY=AIzaSyA8gpiXcOLxKjGSVXuO_iF5NQRnKHwLwno,PASTA_BIBLIOTECA_ID=14D3JK1VVyL3nyDNroK0s2vSLMC0H16I6,GERAR_CACHE_CHAVE=escolha-uma-senha-aqui
   ```

   (No PowerShell/Windows, o `` ` `` no fim da linha continua o comando na
   linha de baixo — se copiar tudo numa linha só, é só tirar os `` ` ``.
   `--timeout 3600` = 1 hora, o máximo que o Cloud Run permite — margem
   folgada pro `/gerar-cache` mesmo com a biblioteca bem maior no futuro.
   `--memory 1Gi` dá mais fôlego pra segurar a árvore inteira em memória
   antes de escrever o arquivo; se um dia a biblioteca ficar bem maior que
   200 mil faixas e der erro de memória, pode subir pra `2Gi`.)

   O `gcloud` vai perguntar se pode criar um repositório no Artifact
   Registry pra guardar a imagem — pode aceitar (sim/y).

8. Ao final, ele mostra uma **URL** tipo
   `https://sonora-backend-xxxxxxxxxx-uc.a.run.app` — anote essa URL.

## Como testar

Com a URL do passo 8:

- **`<URL>/validar?id=teste123`** — deve responder algo tipo
  `{"liberado":false}` (e criar uma linha nova "teste123 / Bloqueado" na
  planilha — pode apagar depois).
- **`<URL>/cache`** — deve responder o JSON da biblioteca, do mesmo jeito
  que `action=cache` no Apps Script responde hoje.
- **`<URL>/gerar-cache?chave=SUA_SENHA`** — o principal pra testar agora.
  Abra direto no navegador (ou peça pra mim rodar via `curl` daqui). Pode
  demorar de alguns segundos a alguns minutos, dependendo do tamanho da
  biblioteca no momento — quando terminar, responde um JSON tipo
  `{"ok":true,"totalAlbuns":N,"totalNos":N,"duracaoMs":N}`. Depois disso,
  abra o app Sonora (ou puxe pra atualizar a Biblioteca) — ele deve
  mostrar a biblioteca atualizada, vinda desse arquivo que o Cloud Run
  acabou de escrever, sem nenhuma mudança no app.

## Se o teste não der certo (rollback)

Não precisa desfazer nada no app nem no Drive. É só voltar a rodar
`atualizarCacheBiblioteca()` no editor do Apps Script, do jeito que já
fazia antes — ele sobrescreve o mesmo arquivo de novo, e o app volta a
funcionar com a versão gerada por ele. `/gerar-cache` só fica sem uso, sem
custo (Cloud Run só cobra pelo que é efetivamente chamado).

## Quando quiser migrar o app pra usar `/validar` e `/cache` deste backend

Só troca o valor de `AppConstants.backendBaseUrl` em
`lib/core/constants.dart` pela URL do Cloud Run (sem `/validar` nem
`/cache` no final — só a URL base), gera um novo build, e testa. Isso é
uma decisão separada de quando ativar `/gerar-cache` — não tem pressa, os
dois podem ser testados/ativados em momentos diferentes.
