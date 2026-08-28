# Sonora — Backend alternativo (Google Cloud Run)

Faz o mesmo que `backend/AcessoWebApp.gs` (Apps Script) faz hoje — `validar`
e `cache` — mas rodando no Google Cloud Run, que **não tem** o limite de
30 execuções simultâneas que contas Google normais têm no Apps Script.

**Status: estruturado e pronto pra testar, mas ainda NÃO conectado ao
app.** O Flutter continua apontando pro Apps Script
(`AppConstants.backendBaseUrl`, em `lib/core/constants.dart`) até você
decidir migrar de vez. Isso é proposital — dá pra testar esse backend novo
com calma, sem nenhum risco pro app que já está no ar.

## O que precisa fazer, uma vez só, pra colocar isso no ar (testável, sem
afetar o app ainda)

1. **Habilitar as APIs necessárias** no projeto `sonora-506315` (o mesmo
   projeto que já existe, com a API do Drive habilitada):
   - Cloud Run API
   - Cloud Build API
   - Google Sheets API

2. **Criar uma conta de serviço** (IAM e administrador → Contas de
   serviço → Criar conta de serviço), por exemplo `sonora-backend`. Não
   precisa baixar chave JSON — o Cloud Run usa a identidade da conta
   direto, mais seguro.

3. **Compartilhar a planilha "Log_Acesso_Sonora"** com o e-mail dessa
   conta de serviço (algo tipo
   `sonora-backend@sonora-506315.iam.gserviceaccount.com`), dando
   permissão de **Editor** — é assim que o backend consegue ler/escrever
   nela, do mesmo jeito que o Apps Script já faz hoje (rodando como sua
   conta pessoal).

4. **Conferir o nome da aba** da planilha (a "Página1" no código é só um
   palpite) e ajustar a variável `ABA_NOME` no comando de deploy abaixo se
   for diferente.

5. **Deploy**, rodando isso dentro desta pasta (`backend-cloudrun/`), no
   seu terminal, com o `gcloud` CLI instalado e logado na sua conta:

   ```
   gcloud run deploy sonora-backend `
     --source . `
     --region us-central1 `
     --allow-unauthenticated `
     --service-account sonora-backend@sonora-506315.iam.gserviceaccount.com `
     --set-env-vars PLANILHA_ID=1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE,ABA_NOME=Página1,CACHE_FILE_ID=1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP,DRIVE_API_KEY=AIzaSyA8gpiXcOLxKjGSVXuO_iF5NQRnKHwLwno
   ```

   (No PowerShell/Windows, o `` ` `` no fim da linha continua o comando na
   linha de baixo — se copiar tudo numa linha só, é só tirar os `` ` ``.)

   O `gcloud` vai perguntar se pode criar um repositório no Artifact
   Registry pra guardar a imagem — pode aceitar (sim/y).

6. Ao final, ele mostra uma **URL** tipo
   `https://sonora-backend-xxxxxxxxxx-uc.a.run.app` — anote essa URL.

## Como testar (sem mexer no app)

Com a URL do passo 6, abra direto no navegador:

- `<URL>/validar?id=teste123` — deve responder algo tipo `{"liberado":false}`
  (e criar uma linha nova "teste123 / Bloqueado" na planilha — pode
  apagar depois).
- `<URL>/cache` — deve responder o JSON grande da biblioteca, do mesmo
  jeito que `action=cache` no Apps Script responde hoje.

Se os dois funcionarem, o backend novo está pronto.

## Quando quiser migrar o app pra usar esse backend

Só troca o valor de `AppConstants.backendBaseUrl` em
`lib/core/constants.dart` pela URL do Cloud Run (sem `/validar` nem
`/cache` no final — só a URL base, igual é hoje com a URL do Apps
Script), gera um novo build, e testa. Nesse momento também dá pra decidir
se quer desligar o Web App do Apps Script ou deixar como um backup — não
tem pressa, os dois podem coexistir enquanto quiser.
