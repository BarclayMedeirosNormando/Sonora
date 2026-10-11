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
     --set-env-vars PLANILHA_ID=1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE,ABA_NOME=Página1,CACHE_FILE_ID=1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP,PASTA_BIBLIOTECA_ID=14D3JK1VVyL3nyDNroK0s2vSLMC0H16I6,GERAR_CACHE_CHAVE=escolha-uma-senha-aqui
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
      --set-env-vars "PLANILHA_ID=1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE,ABA_NOME=Untitled,CACHE_FILE_ID=1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP,PASTA_BIBLIOTECA_ID=14D3JK1VVyL3nyDNroK0s2vSLMC0H16I6,GERAR_CACHE_CHAVE=<SUA_SENHA_LONGA>,PAINEL_CHAVE=escolha-outra-senha-aqui"
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
     --set-env-vars "PLANILHA_ID=1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE,ABA_NOME=Untitled,CACHE_FILE_ID=1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP,PASTA_BIBLIOTECA_ID=14D3JK1VVyL3nyDNroK0s2vSLMC0H16I6,GERAR_CACHE_CHAVE=<SUA_SENHA_LONGA>,PAINEL_CHAVE=escolha-outra-senha-aqui,MIDIA_BUCKET=sonora-midia-cache"
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

**RESOLVIDO (31/08/2026)** — checado e reforçado. A auditoria original
suspeitou que o bucket `sonora-midia-cache` tivesse `roles/storage.objectViewer`
pra `allUsers` no nível do BUCKET (o que incluiria permissão de LISTAR
todos os objetos, não só ler um já conhecido). Checagem real via
`gcloud storage buckets get-iam-policy` e `gcloud storage buckets describe
--format="default(acl)"` mostrou que **não existia** nenhum vínculo pra
`allUsers`/`allAuthenticatedUsers` — nem na política de IAM, nem na ACL
de bucket. Ou seja, o bucket nunca esteve listável publicamente — o
acesso de leitura sempre foi via ACL por objeto (cada arquivo com sua
própria entrada pública), que não concede list. Alarme falso, mas
reforçado mesmo assim:

- `uniform bucket-level access` desligado (`--no-uniform-bucket-level-access`),
  necessário pra ACL por objeto funcionar de forma confiável.
- `gsutil defacl set public-read` — todo objeto NOVO gravado pelo proxy
  já nasce público de leitura (sem list) automaticamente.
- `gsutil -m acl set -R public-read gs://sonora-midia-cache/midia/` —
  aplicado retroativamente nos 69 objetos já existentes no bucket
  (precisou de uma permissão temporária extra pro Barclay, já revogada
  depois — os objetos foram criados pela conta de serviço, que detinha
  a ACL original).
- Testado: música tocando normal pela URL pública depois do ajuste.

**`driveApiKey` restrita (31/08/2026)** — a chave hardcoded em
`lib/core/constants.dart` (também usada como
`DRIVE_API_KEY` no Cloud Run — REMOVIDA em 10/10/2026, ver a última seção) foi restrita no Console/`gcloud` só à
Drive API (`gcloud services api-keys update KEY --api-target=service=drive.googleapis.com`,
confirmado via `--format="yaml(restrictions)"`). Não dava pra restringir
por app Android nem por IP/referrer — a mesma chave é usada tanto pelo
Cloud Run (`/cache`) quanto direto por todo celular (capa de álbum), sem
IP fixo nem cabeçalho de app nativo confiável. Mas restringir por API já
garante que, se vazar, não serve pra mais nada no projeto.

**Status final da auditoria (31/08/2026)**: os 6 itens levantados —
gate de appId em `/cache`/`/midia`, rate limiting, chave do painel por
header, confirmação em `/api/zerar-plays`, listagem pública do bucket
(alarme falso, reforçado do mesmo jeito) e restrição da `driveApiKey`
— estão todos implementados e validados em produção.

## Acesso às músicas só com App_ID liberado (10/10/2026)

**Por que mudou.** Até aqui o gate de App_ID protegia só o `/midia` e o
`/cache`. Por fora dele, a pasta do Drive estava como "qualquer pessoa com
o link" e a chave de API (no código e no APK) deixava listar/baixar tudo
direto do Google, e os objetos do bucket eram públicos por ACL. Agora:

- O servidor lê o Drive **pela conta de serviço** (`baixarDoDrive`). Nenhuma
  chave de API existe mais — nem no código, nem no APK, nem em env var.
- `GET /capa/:fileId?appId=X` (App_ID liberado) e
  `GET /api/admin/capa/:fileId?chave=X` (curadoria) entregam as capas. Só
  servem arquivos de imagem (até 10 MB) e guardam cópia privada em
  `capas/<fileId>` no bucket. O app e as páginas `/minhaplaylist` e
  `/criar` deixaram de buscar capa direto no Drive/`drive.google.com`.
- `/midia` passou a redirecionar (302) pra uma **URL assinada de 30 min** do
  bucket, em vez da URL pública. Se a assinatura falhar, cai pro proxy
  (entrega os bytes pelo servidor) e grava um alerta no painel — a música
  não para, só fica mais cara/lenta até o papel abaixo ser concedido.
- `/midia` só baixa do Drive arquivos de áudio (até 100 MB); `/validar` só
  aceita App_ID com formato válido (4–64 letras/números/hífen).
- `PAINEL_CHAVE` e `GERAR_CACHE_CHAVE` agora **falham fechadas**: se a
  variável não estiver configurada, o acesso é NEGADO (antes, vazia = aberto).
  A comparação é em tempo constante.

### Passo a passo (nesta ordem — cada passo tem teste e dá pra parar ali)

Nomes usados: projeto `sonora-506315`, serviço `sonora-backend`, região
`us-central1`, bucket `sonora-midia-cache`. **No PowerShell, valor de flag
com vírgula sempre entre aspas duplas.** Confirme a conta de serviço do
Cloud Run (aqui chamada `SA`) com:
`gcloud run services describe sonora-backend --region us-central1 --format="value(spec.template.spec.serviceAccountName)"`

0. **Troque a senha do `/gerar-cache` agora** (a antiga estava neste README
   público). Use `--update-env-vars`, **nunca `--set-env-vars`** (esse
   apaga todas as outras variáveis — foi assim que o painel já ficou sem
   chave): `gcloud run services update sonora-backend --region us-central1 --update-env-vars "GERAR_CACHE_CHAVE=<NOVA_SENHA_LONGA>"`
1. **Deploy do backend novo**, dentro de `backend-cloudrun/`:
   `gcloud run deploy sonora-backend --source . --region us-central1`
   (sem `--set-env-vars`). Teste: o app toca música e carrega capas; o
   `/painel` e o `/criar` abrem com a chave.
2. **Permitir assinar URLs**: `gcloud services enable iamcredentials.googleapis.com`
   e `gcloud iam service-accounts add-iam-policy-binding SA --member="serviceAccount:SA" --role="roles/iam.serviceAccountTokenCreator"`.
   Teste: `/midia/ID?appId=SEU_ID` de uma faixa já em cache responde 302 pra
   uma URL com `X-Goog-Signature`. Se o painel mostrar o alerta "Falha ao
   assinar URL", o papel ainda não propagou (espere alguns minutos).
3. **Fechar o bucket** (só depois do passo 2 funcionar):
   `gcloud storage buckets update gs://sonora-midia-cache --predefined-default-object-acl=private`
   `gcloud storage objects update "gs://sonora-midia-cache/**" --predefined-acl=private`
   `gcloud storage buckets update gs://sonora-midia-cache --public-access-prevention`
   (como da outra vez, o segundo comando pode exigir `roles/storage.admin`
   temporário pra você, porque os objetos pertencem à conta de serviço.)
   Teste: a URL pública antiga de um objeto agora dá 403 e a música continua
   tocando pelo app.
4. **Publicar o app novo** (versão com as capas pelo `/capa`) e instalar
   nos clientes. Aparelhos com o app antigo continuam tocando, mas as
   **capas somem** depois do passo 5.
5. **Fechar o Drive**: na pasta `Sonora` (e na pasta-mãe `Musicas`), em
   Compartilhar > Acesso geral, trocar para **Restrito**; confirmar que a
   conta de serviço continua como Editora. Teste: o app, `/minhaplaylist` e
   `/criar` continuam mostrando capas e tocando; uma listagem anônima do
   Drive com a chave antiga passa a falhar.
6. **Revogar a chave antiga** no Console (APIs e serviços > Credenciais) e
   remover a variável: `gcloud run services update sonora-backend --region us-central1 --remove-env-vars DRIVE_API_KEY`.
   O histórico do Git ainda tem a chave: por isso ela precisa ser revogada,
   não só apagada do código.

### O que continua em aberto (de propósito, ficou pra depois)

- O App_ID tem 6 caracteres (~1 bilhão de combinações) e vai na URL
  (`?appId=`). Dá pra adivinhar por força bruta lentamente e ele aparece
  nos logs. A correção é um segredo longo por aparelho, emitido pelo
  servidor quando o ID for liberado.
- O App_ID não é preso ao aparelho: quem copiar um ID liberado usa o acesso.
- O `/criar` (curadoria) é a página do **administrador**: quem entra com a
  `PAINEL_CHAVE` pode liberar IDs, zerar plays e editar qualquer playlist.
  Cliente deve usar só o `/minhaplaylist` (é o que o botão do app abre).
