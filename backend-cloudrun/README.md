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

## Painel administrativo (29/08/2026)

Além de `/validar`, `/cache` e `/gerar-cache`, agora tem um painel web em
`/painel` — biblioteca, dispositivos pendentes de liberação (com botão
"Liberar" direto ali), lista de usuários, e engajamento (faixas mais
tocadas, plays por dia), alimentado por eventos que o app Flutter passou
a registrar a cada play (`POST /registrar-play`).

Passos extras (além dos 1-8 acima) pra colocar isso no ar:

9. **Criar um banco Firestore** no projeto (Native mode), se ainda não
   existir:
   ```
   gcloud firestore databases create --location=us-central1
   ```
   (`us-central1` combina com a região do Cloud Run já usada — não muda o
   custo, mas evita latência entre serviços.)

10. **Dar permissão de Firestore pra conta de serviço** `sonora-backend`
    (o papel "Cloud Datastore User" cobre leitura e escrita no Firestore):
    ```
    gcloud projects add-iam-policy-binding sonora-506315 `
      --member="serviceAccount:sonora-backend@sonora-506315.iam.gserviceaccount.com" `
      --role="roles/datastore.user"
    ```

11. **Escolher uma senha pra `PAINEL_CHAVE`** (mesma ideia da
    `GERAR_CACHE_CHAVE` — protege `/painel` e as rotas `/api/*` de
    qualquer um achar a URL à toa; `/registrar-play` fica sem trava de
    propósito, é chamado o tempo todo pelo app).

12. **Redeploy** incluindo a `PAINEL_CHAVE` nas env vars (repare que a
    lista inteira de `--set-env-vars` precisa estar entre **aspas
    duplas** no PowerShell — sem isso as vírgulas se perdem e as
    variáveis vêm todas erradas, ver nota de 28/08/2026 no
    `sonora_deploy.md`):
    ```
    gcloud run deploy sonora-backend `
      --source . `
      --region us-central1 `
      --allow-unauthenticated `
      --timeout 3600 `
      --memory 1Gi `
      --service-account sonora-backend@sonora-506315.iam.gserviceaccount.com `
      --set-env-vars "PLANILHA_ID=1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE,ABA_NOME=Untitled,CACHE_FILE_ID=1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP,DRIVE_API_KEY=AIzaSyA8gpiXcOLxKjGSVXuO_iF5NQRnKHwLwno,PASTA_BIBLIOTECA_ID=14D3JK1VVyL3nyDNroK0s2vSLMC0H16I6,GERAR_CACHE_CHAVE=sonora2026xyz,PAINEL_CHAVE=escolha-outra-senha-aqui"
    ```

13. **Abrir o painel**: `<URL>/painel?chave=SUA_PAINEL_CHAVE`. Na primeira
    vez, "Biblioteca" e "Crescimento" ficam vazios até rodar
    `/gerar-cache` de novo pelo menos uma vez (é o que grava o resumo no
    Firestore) — e "Engajamento" fica vazio até o app novo (1.7.0+12 ou
    mais recente, com o registro de play) rodar de verdade em algum
    aparelho.

## Quando quiser migrar o app pra usar `/validar` e `/cache` deste backend

Só troca o valor de `AppConstants.backendBaseUrl` em
`lib/core/constants.dart` pela URL do Cloud Run (sem `/validar` nem
`/cache` no final — só a URL base), gera um novo build, e testa. Isso é
uma decisão separada de quando ativar `/gerar-cache` — não tem pressa, os
dois podem ser testados/ativados em momentos diferentes.

## Proxy de mídia (30/08/2026) — evita bloqueio por abuso do Drive

Hoje o app baixa os MP3s direto do Google Drive (`files/{id}?alt=media&key=...`).
Isso funciona, mas o Drive tem um mecanismo de anti-abuso **separado** da
cota normal — não documentado, disparado por padrão de acesso — que pode
bloquear quando muita gente diferente toca a MESMA faixa popular numa
janela curta de tempo. Risco real com a meta de ~500 clientes até o fim
do ano.

A rota nova `GET /midia/:fileId` resolve isso agindo como cache: na
primeira vez que qualquer usuário pede uma faixa, o Cloud Run baixa do
Drive e guarda uma cópia num bucket do Cloud Storage (ao mesmo tempo que
já manda os bytes pro usuário, sem esperar). Da segunda vez em diante —
qualquer usuário, qualquer aparelho — ele nem chega a bater no Drive:
redireciona direto pra URL pública do arquivo já cacheado. Resultado: o
Drive passa a receber no máximo 1 request por faixa, pra sempre, em vez
de 1 por play.

### O que fazer, uma vez só, pra colocar isso no ar

1. **Criar o bucket** (nome sugerido, mas pode ser outro — só ajustar a
   variável `MIDIA_BUCKET` no deploy de acordo):
   ```
   gcloud storage buckets create gs://sonora-midia-cache --location=us-central1
   ```

2. **Deixar os objetos do bucket públicos pra leitura** (mesmo modelo de
   segurança que os arquivos já têm no Drive hoje — "qualquer pessoa com
   o link" — os IDs de arquivo continuam sendo a única "trava"):
   ```
   gcloud storage buckets add-iam-policy-binding gs://sonora-midia-cache `
     --member=allUsers --role=roles/storage.objectViewer
   ```

3. **Dar permissão de escrita pra conta de serviço** `sonora-backend`
   (precisa gravar os arquivos cacheados):
   ```
   gcloud storage buckets add-iam-policy-binding gs://sonora-midia-cache `
     --member="serviceAccount:sonora-backend@sonora-506315.iam.gserviceaccount.com" `
     --role=roles/storage.objectAdmin
   ```

4. **Redeploy** incluindo a variável `MIDIA_BUCKET` (repare que a lista
   inteira de `--set-env-vars` precisa estar entre **aspas duplas** no
   PowerShell — ver lição de 28/08/2026 no `sonora_deploy.md`):
   ```
   gcloud run deploy sonora-backend `
     --source . `
     --region us-central1 `
     --allow-unauthenticated `
     --timeout 3600 `
     --memory 1Gi `
     --service-account sonora-backend@sonora-506315.iam.gserviceaccount.com `
     --set-env-vars "PLANILHA_ID=1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE,ABA_NOME=Untitled,CACHE_FILE_ID=1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP,DRIVE_API_KEY=AIzaSyA8gpiXcOLxKjGSVXuO_iF5NQRnKHwLwno,PASTA_BIBLIOTECA_ID=14D3JK1VVyL3nyDNroK0s2vSLMC0H16I6,GERAR_CACHE_CHAVE=sonora2026xyz,PAINEL_CHAVE=escolha-outra-senha-aqui,MIDIA_BUCKET=sonora-midia-cache"
   ```

### Como testar

- **`<URL>/midia/ID_DE_ALGUMA_FAIXA`** — abra direto no navegador (pega
  qualquer ID de arquivo MP3 do Drive). Na primeira vez deve tocar/baixar
  normalmente (vindo do Drive, um pouco mais lento) e aparecer um objeto
  novo em `gs://sonora-midia-cache/midia/`. Na segunda vez que abrir a
  MESMA URL, deve ser bem mais rápido — é o redirecionamento pro cache.
- Depois disso, testar no app de verdade: tocar uma música qualquer,
  conferir que toca normal, e no Console do Cloud Storage ver o arquivo
  aparecendo no bucket.

### Rollback

Se algo der errado, é só voltar `Track.streamUrl()` (lib/models/track.dart)
pra montar a URL direto do Drive como antes — não precisa desfazer nada
no bucket nem no Cloud Run, o endpoint `/midia` simplesmente fica sem uso.

### Sobre as capas dos álbuns

Por enquanto essa mudança cobre só o ÁUDIO (`Track.streamUrl`). As capas
(`Album.capaUrl`) continuam vindo direto do Drive — são bem menores que os
MP3s e menos prováveis de disparar o mesmo gatilho de abuso, mas se um dia
virar problema, o mesmo padrão de proxy+cache dá pra estender pra elas.

## Reforço de segurança (31/08/2026)

Auditoria encontrou que `/cache` e `/midia/:fileId` respondiam pra
qualquer um que soubesse a URL, sem checar liberação nenhuma — o gate
de "App_ID liberado" só existia dentro do app (tela de validação),
nunca no backend. Corrigido:

- `/cache` e `/midia/:fileId` agora exigem `?appId=X` liberado na
  planilha (checado com um cache em memória de 30s, pra não bater na
  planilha a cada play). Resposta `401` sem `appId`, `403` se não
  liberado.
- Rate limiting (`express-rate-limit`) em todas as rotas: `/validar`
  (30/5min por IP), `/gerar-cache` (3/15min) + trava contra execução
  simultânea, `/cache`+`/midia` (300/5min), `/painel`+`/api/*`
  (60/5min).
- `PAINEL_CHAVE` agora também aceita o header `X-Painel-Chave` (usado
  pelas chamadas de API do `painel.html`) — reduz a chave aparecendo
  nos logs de acesso do Cloud Run, que registram a URL completa.
- `/api/zerar-plays` (apaga TODO o histórico de plays, irreversível)
  agora exige `&confirmar=sim` na URL, além da chave — evita disparo
  acidental (crawler seguindo um link salvo, etc.).
- `/api/liberar` grava um alerta de auditoria (`registrarAlerta`) toda
  vez que libera um App_ID, com o IP de quem chamou.
- `helmet` adicionado como camada básica de headers HTTP de segurança
  (CSP desligado, porque `painel.html` usa `<script>` inline).

**IMPORTANTE — ordem de deploy**: depois de publicar essa versão do
backend, qualquer APK instalado ANTES dela (ex: `2.5.0+20` ou
anteriores) vai parar de tocar música e carregar a Biblioteca — porque
esses builds antigos chamam `/midia` e `/cache` sem `?appId=`, e a
nova checagem responde `401`. Isso não é bug, é o gate funcionando.
Rebuildar e reinstalar o app (versão `2.5.1+21`, já com o `appId`
sendo enviado) logo em seguida ao `gcloud run deploy` evita esse
período sem música.

**Pendente, fora do escopo do código** (é mudança de IAM no bucket, não
de app): o bucket `sonora-midia-cache` está com `roles/storage.objectViewer`
pra `allUsers` no nível do BUCKET — isso inclui permissão de LISTAR os
objetos, não só ler um que você já sabe o nome. Quem listar o bucket
descobre todos os `fileId` já cacheados sem precisar nunca passar pelo
`/midia` (e portanto sem nunca passar pelo gate de `appId` acima). Pra
fechar isso, trocar a permissão de nível de bucket por ACL por objeto
(sem list, só o objeto individual fica público):

```
gcloud storage buckets remove-iam-policy-binding gs://sonora-midia-cache \
  --member=allUsers --role=roles/storage.objectViewer

gsutil defacl set public-read gs://sonora-midia-cache
```

A segunda linha faz com que todo objeto NOVO gravado pelo proxy já
suba público de leitura (sem list) automaticamente — os objetos que já
estão no bucket hoje precisam do ACL aplicado retroativamente:

```
gsutil -m acl set -R public-read gs://sonora-midia-cache/midia/
```
