// ============================================================
// Sonora - Backend alternativo (Google Cloud Run)
//
// Faz o mesmo que backend/AcessoWebApp.gs (Apps Script) faz hoje:
//   GET /validar?id=XXX   -> checa/registra liberação do App_ID na planilha
//   GET /cache             -> devolve o JSON do cache da biblioteca
//
// POR QUE ISSO EXISTE: contas Google normais têm limite de 30 execuções
// simultâneas no Apps Script. Com muita gente abrindo o app ao mesmo
// tempo, isso pode virar gargalo (ver sonora_deploy.md nas notas do
// projeto). Rodando em Cloud Run em vez de Apps Script, esse limite deixa
// de existir.
//
// STATUS (28/08/2026): pronto e testável de forma independente, mas o
// app Flutter AINDA aponta pro Apps Script (AppConstants.backendBaseUrl
// não foi alterado). Só troca quando o Barclay decidir migrar de vez —
// ver README.md nesta pasta pro passo a passo de deploy e de como (e
// quando) apontar o app pra cá.
//
// GET /midia/:fileId       -> proxy de mídia com cache no Cloud Storage
//   (evita bater direto no Drive a cada play — ver comentário na rota,
//   mais detalhes em sonora_deploy.md nas notas do projeto, 30/08/2026)
//
// GET /gerar-cache?chave=XXX -> gera o cache da biblioteca inteira e
//   SOBRESCREVE o mesmo arquivo que backend/CacheBiblioteca.gs (Apps
//   Script) já gera hoje — o app não precisa saber quem escreveu. Existe
//   porque o Apps Script tem limite de 6 min por execução, o que não vai
//   dar conta de uma biblioteca de ~200 mil faixas (testado em
//   28/08/2026 com ~2.900 faixas, biblioteca ainda crescendo aos poucos).
//   Acionado manualmente pelo Barclay (não é chamado pelo app).
//
// PAINEL ADMINISTRATIVO (29/08/2026, ampliado 30/08/2026):
//   POST /registrar-play              -> app registra cada play no Firestore
//   GET  /api/resumo?chave=XXX        -> biblioteca + dispositivos + cache de mídia
//   GET  /api/usuarios?chave=XXX      -> lista de dispositivos/usuários
//   GET  /api/usuario-plays?chave=XXX&appId=X -> últimas faixas de um usuário
//   POST /api/liberar?chave=XXX       -> libera um App_ID (Status -> Liberado)
//   GET  /api/engajamento?chave=XXX   -> agrega plays do Firestore (14 dias) + top álbuns
//   GET  /api/alertas?chave=XXX       -> últimos erros registrados (Drive, cache, etc.)
//   GET  /painel?chave=XXX            -> a página do painel em si
//   Protegido por PAINEL_CHAVE (mesma ideia do GERAR_CACHE_CHAVE, senha
//   simples via query param — não é auth de verdade). /registrar-play não
//   tem trava, é chamado o tempo todo pelo app.
// ============================================================

const stream = require('stream');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const compression = require('compression');
const { Firestore } = require('@google-cloud/firestore');
const { Storage } = require('@google-cloud/storage');

const app = express();
const PORT = process.env.PORT || 8080;

// Cloud Run entrega as requisicoes atraves de um proxy (Google Front
// End) -- sem isso, o IP que o express/express-rate-limit enxerga e
// sempre o do proxy, nao o do cliente de verdade, e todo mundo cairia
// no mesmo "balde" de rate limit.
app.set('trust proxy', 1);

// Configuração via variáveis de ambiente (definidas no deploy do Cloud
// Run — ver README.md). Valores default abaixo são os mesmos já usados
// no Apps Script hoje, só pra documentar o formato esperado.
const PLANILHA_ID = process.env.PLANILHA_ID || '1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE';
const ABA_NOME = process.env.ABA_NOME || 'Página1'; // conferir o nome real da aba na planilha
const CACHE_FILE_ID = process.env.CACHE_FILE_ID || '1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP';
// (10/10/2026) A DRIVE_API_KEY foi REMOVIDA: o servidor agora le tudo do
// Drive pela conta de servico (ver baixarDoDrive), entao nenhuma chave de
// API precisa existir -- nem no codigo, nem no APK, nem nas env vars.

// Tamanhos maximos (bytes). O proxy carrega o arquivo inteiro na memoria
// (instancia de 1Gi, ate 80 requisicoes simultaneas), entao um fileId
// errado/malicioso apontando pra um arquivo gigante nao pode passar.
const MAX_BYTES_AUDIO = 100 * 1024 * 1024;
const MAX_BYTES_CAPA = 10 * 1024 * 1024;
// Validade das URLs assinadas do bucket. Cada seek/Range volta pelo
// /midia e ganha uma URL nova, entao nao precisa ser longa.
const URL_ASSINADA_TTL_MS = 30 * 60 * 1000;
// Formato aceito de App_ID: codigo curto atual (6 caracteres) e os UUIDs
// antigos. Barra lixo antes de virar linha nova na planilha.
const APP_ID_FORMATO = /^[A-Za-z0-9-]{4,64}$/;

// Bucket do Cloud Storage usado como cache de mídia (ver rota /midia
// abaixo) — precisa existir e a conta de serviço do Cloud Run precisa
// ter permissão de escrita nele (roles/storage.objectAdmin). Sem essa
// variável configurada, /midia responde erro 500 em vez de travar
// silenciosamente.
const MIDIA_BUCKET = process.env.MIDIA_BUCKET || '';

// Pasta raiz da biblioteca ("Sonora") que /gerar-cache percorre.
const PASTA_BIBLIOTECA_ID = process.env.PASTA_BIBLIOTECA_ID || '14D3JK1VVyL3nyDNroK0s2vSLMC0H16I6';
// Trava de segurança contra pastas aninhadas demais por engano.
const PROFUNDIDADE_MAX = 8;
// Quantas subpastas processar em paralelo por nível — equilibra
// velocidade (mais rápido que o Apps Script, que é sempre sequencial)
// com não estourar a cota do Drive de uma vez só.
const CONCORRENCIA_GERAR_CACHE = 6;
// Senha simples pra evitar que qualquer um na internet aperte
// /gerar-cache e gaste cota/reescreva o arquivo — não é pra ser um
// sistema de auth de verdade, só uma trava básica.
const GERAR_CACHE_CHAVE = process.env.GERAR_CACHE_CHAVE || '';

// Senha simples pro painel administrativo (/painel e as rotas /api/*) —
// mesma ideia do GERAR_CACHE_CHAVE, não é auth de verdade.
const PAINEL_CHAVE = process.env.PAINEL_CHAVE || '';

app.use(express.json());
app.use(helmet({ contentSecurityPolicy: false })); // CSP desligado: painel.html tem <script> inline
app.use(compression()); // gzip/brotli nas respostas -- corta bastante o tamanho do JSON do /cache

// ---- Protecao basica contra abuso (reforco de seguranca) ----
// Quatro limitadores separados, calibrados pro uso real de cada rota --
// nao e auth de verdade (isso continua sendo a CHAVE / o appId liberado),
// so trava enxurrada.
const limiteValidar = rateLimit({
  windowMs: 5 * 60 * 1000,
  max: 30, // um app real chama /validar rarissimas vezes; 30/5min sobra
  standardHeaders: true,
  legacyHeaders: false,
  message: { erro: 'Muitas tentativas. Aguarde alguns minutos.' },
});
const limitePainel = rateLimit({
  windowMs: 5 * 60 * 1000,
  max: 200, // a página /criar faz várias chamadas seguidas (curadoria) sem travar o Barclay
  standardHeaders: true,
  legacyHeaders: false,
  message: { erro: 'Muitas tentativas. Aguarde alguns minutos.' },
});
const limiteGerarCache = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 3,
  standardHeaders: true,
  legacyHeaders: false,
  message: { erro: 'Muitas tentativas de gerar o cache. Aguarde alguns minutos.' },
});
const limiteMidia = rateLimit({
  windowMs: 5 * 60 * 1000,
  max: 300, // generoso -- e a rota de streaming/cache usada o tempo todo pelo app
  standardHeaders: true,
  legacyHeaders: false,
  message: { erro: 'Muitas requisicoes. Aguarde um pouco.' },
});

const limiteCapa = rateLimit({
  windowMs: 5 * 60 * 1000,
  max: 2000, // listas e curadoria carregam dezenas de capas de uma vez
  standardHeaders: true,
  legacyHeaders: false,
  message: { erro: 'Muitas requisicoes. Aguarde um pouco.' },
});

let sheetsClientPromise = null;
let driveClientPromise = null;
let firestoreClientPromise = null;
let storageClient = null;

/**
 * Cliente do Firestore, usando a mesma conta de serviço anexada ao
 * serviço do Cloud Run (Application Default Credentials — sem chave
 * baixada). A conta de serviço precisa do papel "Cloud Datastore User"
 * (ou "Editor") no projeto — ver README.md.
 */
function getFirestore() {
  if (!firestoreClientPromise) {
    firestoreClientPromise = new Firestore();
  }
  return firestoreClientPromise;
}

/**
 * Cliente do Cloud Storage, mesma identidade da conta de serviço
 * anexada ao Cloud Run (Application Default Credentials).
 */
function getStorage() {
  if (!storageClient) {
    storageClient = new Storage();
  }
  return storageClient;
}

/**
 * Compara a chave enviada com a esperada em tempo constante. FALHA
 * FECHADA: se a variavel de ambiente da chave nao estiver configurada
 * (ex.: um deploy com --set-env-vars que sobrescreveu as outras), o
 * acesso e NEGADO -- antes, chave vazia significava painel aberto.
 */
function chavesIguais(enviada, esperada) {
  if (!esperada || typeof enviada !== 'string' || !enviada) return false;
  const a = crypto.createHash('sha256').update(enviada).digest();
  const b = crypto.createHash('sha256').update(esperada).digest();
  return crypto.timingSafeEqual(a, b);
}

function chavePainelValida(req) {
  // Aceita a chave tanto por query string (?chave=X -- necessario pra
  // navegacao normal do /painel, que e um link clicavel) quanto por
  // header X-Painel-Chave (usado pelas chamadas de API feitas pelo
  // proprio painel.html via JS, pra nao deixar a chave espalhada nos
  // logs de acesso do Cloud Run, que registram a URL completa mas nao
  // headers customizados).
  return chavesIguais(req.get('X-Painel-Chave') || req.query.chave, PAINEL_CHAVE);
}

/**
 * Registra um alerta de erro no Firestore pro painel administrativo
 * mostrar sem precisar ir no Cloud Logging manualmente (30/08/2026).
 * Fire-and-forget: nunca lança erro, só loga se falhar em gravar — não
 * pode derrubar a rota que chamou.
 */
function registrarAlerta(origem, detalhe) {
  try {
    getFirestore()
      .collection('alertas')
      .add({
        origem: String(origem),
        detalhe: String((detalhe && detalhe.message) || detalhe || ''),
        timestamp: Firestore.FieldValue.serverTimestamp(),
      })
      .catch((erroFirestore) => {
        console.error('Aviso: falha ao registrar alerta no Firestore (não bloqueia):', erroFirestore);
      });
  } catch (erroSincrono) {
    console.error('Aviso: falha ao registrar alerta (não bloqueia):', erroSincrono);
  }
}

/**
 * Cliente autenticado do Google Drive API, mesma identidade da conta de
 * serviço usada pro Sheets. A conta de serviço precisa ter acesso de
 * Editor à pasta "Musicas" (pai de "Sonora", onde fica o arquivo de
 * cache) — ver README.md.
 */
async function getDriveClient() {
  if (!driveClientPromise) {
    driveClientPromise = (async () => {
      const { google } = require('googleapis');
      const auth = new google.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/drive'],
      });
      const authClient = await auth.getClient();
      return google.drive({ version: 'v3', auth: authClient });
    })();
  }
  return driveClientPromise;
}

/**
 * Cliente autenticado do Google Sheets API, usando a identidade da conta
 * de serviço anexada ao serviço do Cloud Run (sem precisar de chave JSON
 * baixada nem guardada em lugar nenhum — mais seguro). A conta de serviço
 * precisa ter sido adicionada como Editor na planilha (ver README.md).
 */
async function getSheetsClient() {
  if (!sheetsClientPromise) {
    sheetsClientPromise = (async () => {
      const { google } = require('googleapis');
      const auth = new google.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/spreadsheets'],
      });
      const authClient = await auth.getClient();
      return google.sheets({ version: 'v4', auth: authClient });
    })();
  }
  return sheetsClientPromise;
}

// ---- Cache em memoria de App_IDs liberados (reforco de seguranca) ----
// /cache e /midia/:fileId, antes desse reforco, respondiam pra qualquer
// um que soubesse a URL -- o gate de "liberado" so existia dentro do
// app (tela de validacao), nunca no backend. Agora as duas rotas tambem
// exigem ?appId=X liberado. Consultar a planilha a cada play seria
// lento (e caro em cota) -- por isso um cache simples em memoria,
// renovado no maximo a cada 30s.
let liberadosCache = { set: null, expiraEm: 0 };
const LIBERADOS_CACHE_TTL_MS = 30 * 1000;

async function obterLiberados() {
  const agora = Date.now();
  if (liberadosCache.set && agora < liberadosCache.expiraEm) {
    return liberadosCache.set;
  }
  const sheets = await getSheetsClient();
  const leitura = await sheets.spreadsheets.values.get({
    spreadsheetId: PLANILHA_ID,
    range: `${ABA_NOME}!A:D`,
  });
  const linhas = (leitura.data.values || []).slice(1);
  const set = new Set(
    linhas
      .filter((l) => String(l[1] || '').trim().toLowerCase() === 'liberado')
      .map((l) => l[0])
  );
  liberadosCache = { set, expiraEm: agora + LIBERADOS_CACHE_TTL_MS };
  return set;
}

/**
 * Middleware: exige ?appId=X liberado na planilha antes de servir a
 * rota. Usado em /cache e /midia/:fileId -- as duas rotas que entregam
 * conteudo de verdade (catalogo e audio), diferente de /validar (que E
 * a propria checagem) e das rotas /api/* (protegidas por PAINEL_CHAVE,
 * nao por App_ID).
 */
async function exigirAppIdLiberado(req, res, next) {
  const appId = req.query.appId;
  if (!appId) {
    return res.status(401).json({ erro: 'Parametro appId ausente.' });
  }
  try {
    const liberados = await obterLiberados();
    if (!liberados.has(appId)) {
      return res.status(403).json({ erro: 'App_ID nao liberado.' });
    }
    next();
  } catch (erro) {
    console.error('Erro ao checar liberacao do appId:', erro);
    return res.status(503).json({ erro: 'Falha ao checar liberacao. Tente novamente.' });
  }
}

/**
 * Checa se o App_ID está com Status "Liberado" na planilha de controle.
 * Se o ID ainda não existir, cadastra automaticamente como "Bloqueado"
 * (mesma lógica de validarId() em backend/AcessoWebApp.gs).
 */
app.get('/validar', limiteValidar, async (req, res) => {
  const appId = req.query.id;
  if (!appId) {
    return res.json({ erro: 'Parâmetro id ausente.' });
  }
  if (typeof appId !== 'string' || !APP_ID_FORMATO.test(appId)) {
    return res.json({ erro: 'Formato de id inválido.' });
  }

  try {
    const sheets = await getSheetsClient();
    const range = `${ABA_NOME}!A:D`;

    const leitura = await sheets.spreadsheets.values.get({
      spreadsheetId: PLANILHA_ID,
      range,
    });
    const linhas = leitura.data.values || [];

    for (let i = 1; i < linhas.length; i++) { // linha 0 = cabeçalho
      if (linhas[i][0] === appId) {
        const status = String(linhas[i][1] || '').trim().toLowerCase();
        return res.json({ liberado: status === 'liberado' });
      }
    }

    // ID novo: registra como Bloqueado para liberação manual (igual hoje).
    await sheets.spreadsheets.values.append({
      spreadsheetId: PLANILHA_ID,
      range,
      valueInputOption: 'RAW',
      requestBody: {
        values: [[appId, 'Bloqueado', '', new Date().toISOString()]],
      },
    });
    return res.json({ liberado: false });
  } catch (erro) {
    console.error('Erro em /validar:', erro);
    return res.status(500).json({ erro: 'Falha ao validar o ID.' });
  }
});

/**
 * Devolve o JSON do cache da biblioteca (gerado por
 * backend/CacheBiblioteca.gs, que continua rodando do jeito que está —
 * isso aqui só passa o conteúdo adiante). Existe principalmente pro
 * Flutter Web, que precisa de um endpoint com CORS liberado; fora da Web,
 * o app já busca esse arquivo direto do Drive (ver ApiService no Flutter).
 */
app.get('/cache', limiteMidia, exigirAppIdLiberado, async (req, res) => {
  try {
    const { bytes } = await baixarDoDrive(CACHE_FILE_ID);
    const texto = bytes.toString('utf8');
    res.set('Content-Type', 'application/json; charset=utf-8');
    res.set('Access-Control-Allow-Origin', '*'); // libera CORS pro Flutter Web
    // Cache HTTP curto (5 min): o app ja tem seu proprio TTL de 1h no
    // cliente (LibraryCacheService), isso aqui e so pra evitar bater no
    // Drive de novo a cada revalidacao que cair na mesma janela de 5 min
    // (ex: varios usuarios abrindo o app quase ao mesmo tempo).
    res.set('Cache-Control', 'public, max-age=300');
    return res.send(texto);
  } catch (erro) {
    console.error('Erro em /cache:', erro);
    registrarAlerta('/cache', erro);
    return res.status(500).json({ erro: 'Falha ao carregar o cache da biblioteca.' });
  }
});

/**
 * Proxy de mídia com cache "preguiçoso" no Cloud Storage — resolve o
 * risco de o Google Drive bloquear por abuso quando muita gente toca a
 * mesma faixa popular ao mesmo tempo (mecanismo de anti-abuso do Drive,
 * separado da cota normal, disparado por padrão de acesso e não
 * documentado — ver sonora_deploy.md nas notas do projeto, 30/08/2026).
 *
 * Primeira vez que uma faixa é pedida (qualquer usuário, a partir daí):
 * baixa do Drive INTEIRA pra memória (faixas de MP3 são pequenas, poucos
 * MB — cabe tranquilo), manda pro cliente, e SÓ DEPOIS de responder
 * grava uma cópia no bucket em segundo plano (sem o cliente esperar por
 * isso). Da segunda vez em diante (qualquer usuário, qualquer aparelho),
 * é um cache hit: redireciona (302) direto pra URL pública do objeto no
 * Cloud Storage, que já suporta "Range" nativamente (arrastar a barra de
 * progresso sem baixar a faixa inteira de novo) sem gastar rede do Cloud
 * Run. Resultado: o Drive passa a receber no máximo 1 request por faixa,
 * pra sempre — não 1 por play.
 *
 * NOTA (30/08/2026): a primeira versão desse endpoint tentava mandar pro
 * cliente e gravar no bucket ao mesmo tempo, "correndo" as duas coisas a
 * partir do mesmo stream de leitura do Drive (stream.pipe() pros dois
 * lados). Na prática isso travava a entrega pro cliente esperando a
 * gravação no Storage também progredir (backpressure de um lado
 * contaminando o outro) — confirmado pelo Barclay: abrir a URL direto
 * ficava travado em 0:00, mas abrir de novo (depois que a gravação
 * enfim tinha terminado por trás) funcionava normal. Baixar tudo pra um
 * Buffer primeiro elimina essa dependência entre as duas coisas.
 */
function erroHttp(status, mensagem) {
  const erro = new Error(mensagem);
  erro.httpStatus = status;
  return erro;
}

/** Status HTTP pra devolver ao cliente a partir de um erro (Drive/Storage/validacao). */
function statusDoErro(erro) {
  if (erro && erro.httpStatus) return erro.httpStatus;
  const codigo = erro && (erro.code || (erro.response && erro.response.status));
  // Drive responde 403 pra arquivo que a conta de servico nao enxerga: pro
  // cliente isso e simplesmente "nao existe".
  if (codigo === 404 || codigo === 403) return 404;
  return 502;
}

/**
 * Baixa um arquivo do Drive INTEIRO pra memoria usando a CONTA DE SERVICO
 * do Cloud Run -- sem chave de API e sem exigir que o arquivo esteja
 * compartilhado como "qualquer pessoa com o link". E isso que permite
 * deixar a pasta do Drive restrita.
 * [validar] recebe os metadados ({ name, mimeType, size }) e decide se o
 * tipo e aceito; [maxBytes] barra arquivos grandes demais.
 */
async function baixarDoDrive(fileId, { maxBytes = 0, validar = null } = {}) {
  const drive = await getDriveClient();
  const meta = await drive.files.get({ fileId, fields: 'id,name,mimeType,size' });
  const dados = meta.data;
  if (validar && !validar(dados)) {
    throw erroHttp(415, 'Tipo de arquivo não permitido.');
  }
  if (maxBytes && Number(dados.size || 0) > maxBytes) {
    throw erroHttp(413, 'Arquivo grande demais.');
  }
  const resposta = await drive.files.get({ fileId, alt: 'media' }, { responseType: 'arraybuffer' });
  return { bytes: Buffer.from(resposta.data), mimeType: dados.mimeType, nome: dados.name };
}

const ehAudio = (m) =>
  String(m.mimeType || '').startsWith('audio/') || /\.mp3$/i.test(String(m.name || ''));
const ehImagem = (m) => String(m.mimeType || '').startsWith('image/');

/** Descobre o tipo de uma imagem pelos primeiros bytes (evita ler metadados do bucket). */
function tipoDaImagem(bytes) {
  if (bytes.length > 3 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e) return 'image/png';
  if (bytes.length > 3 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) return 'image/gif';
  if (bytes.length > 12 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') {
    return 'image/webp';
  }
  return 'image/jpeg';
}

/** Responde com os bytes, com suporte a Range (seek no player). */
function enviarBuffer(req, res, bytes, contentType) {
  res.set('Content-Type', contentType);
  res.set('Accept-Ranges', 'bytes');
  const total = bytes.length;
  const combinacao = req.headers.range && /^bytes=(\d*)-(\d*)$/.exec(req.headers.range);
  if (combinacao && (combinacao[1] || combinacao[2])) {
    let inicio;
    let fim;
    if (combinacao[1]) {
      inicio = parseInt(combinacao[1], 10);
      fim = combinacao[2] ? Math.min(parseInt(combinacao[2], 10), total - 1) : total - 1;
    } else {
      inicio = Math.max(0, total - parseInt(combinacao[2], 10)); // "bytes=-N": ultimos N bytes
      fim = total - 1;
    }
    if (inicio > fim || inicio >= total) {
      res.set('Content-Range', `bytes */${total}`);
      return res.status(416).end();
    }
    res.status(206);
    res.set('Content-Range', `bytes ${inicio}-${fim}/${total}`);
    res.set('Content-Length', String(fim - inicio + 1));
    return res.send(bytes.subarray(inicio, fim + 1));
  }
  res.set('Content-Length', String(total));
  return res.send(bytes);
}

let avisouFalhaAssinatura = false;

/**
 * Faixa ja em cache: o objeto do bucket e PRIVADO, entao o cliente e
 * mandado (302) pra uma URL ASSINADA que vale 30 minutos -- so quem
 * passou pelo gate de App_ID do /midia chega nela, e ela expira. O
 * download continua saindo direto do Storage (suporta Range nativo).
 * Se a assinatura falhar (falta o papel Service Account Token Creator
 * da propria conta de servico -- ver README), cai pro proxy: o servidor
 * le o objeto e entrega os bytes, mais lento/caro mas sem quebrar a
 * reproducao.
 */
async function redirecionarParaBucket(req, res, objeto, contentType) {
  try {
    const [url] = await objeto.getSignedUrl({
      version: 'v4',
      action: 'read',
      expires: Date.now() + URL_ASSINADA_TTL_MS,
    });
    res.set('Cache-Control', 'private, no-store');
    return res.redirect(302, url);
  } catch (erroAssinatura) {
    if (!avisouFalhaAssinatura) {
      avisouFalhaAssinatura = true;
      console.error('Aviso: falha ao assinar URL do bucket, usando o proxy:', erroAssinatura);
      registrarAlerta(
        '/midia',
        'Falha ao assinar URL do bucket (confira o papel Service Account Token Creator): ' +
          ((erroAssinatura && erroAssinatura.message) || erroAssinatura)
      );
    }
    const [bytes] = await objeto.download();
    return enviarBuffer(req, res, bytes, contentType);
  }
}

/**
 * Envia os bytes de uma faixa (cache "preguiçoso" no Cloud Storage) —
 * lógica compartilhada entre /midia/:fileId (app, exige appId liberado)
 * e /api/admin/midia/:fileId (curadoria, exige só PAINEL_CHAVE, usado
 * pro preview antes de adicionar a uma playlist).
 */
async function enviarMidia(req, res, fileId) {
  if (!/^[a-zA-Z0-9_-]+$/.test(fileId || '')) {
    return res.status(400).json({ erro: 'fileId inválido.' });
  }
  if (!MIDIA_BUCKET) {
    console.error('mídia chamada sem MIDIA_BUCKET configurado.');
    return res.status(500).json({ erro: 'Cache de mídia não configurado.' });
  }

  const nomeObjeto = `midia/${fileId}.mp3`;

  try {
    const bucket = getStorage().bucket(MIDIA_BUCKET);
    const objeto = bucket.file(nomeObjeto);
    const [existe] = await objeto.exists();

    if (existe) {
      return await redirecionarParaBucket(req, res, objeto, 'audio/mpeg');
    }

    // Primeira vez: baixa do Drive (so audio, ate MAX_BYTES_AUDIO), entrega,
    // e SO DEPOIS grava no bucket em segundo plano (ver nota do pipe duplo).
    const arquivo = await baixarDoDrive(fileId, { maxBytes: MAX_BYTES_AUDIO, validar: ehAudio });
    enviarBuffer(req, res, arquivo.bytes, 'audio/mpeg');

    objeto
      .save(arquivo.bytes, { contentType: 'audio/mpeg', resumable: false })
      .catch((erroGravacao) => {
        console.error(`Erro ao gravar cache de mídia (${fileId}):`, erroGravacao);
      });
  } catch (erro) {
    const status = statusDoErro(erro);
    console.error(`Erro ao enviar mídia ${fileId}:`, erro);
    if (status === 502) registrarAlerta('/midia', `${fileId}: ${(erro && erro.message) || erro}`);
    if (!res.headersSent) {
      const mensagem = erro && erro.httpStatus ? erro.message : status === 404 ? 'Faixa não encontrada.' : 'Falha ao carregar a faixa.';
      res.status(status).json({ erro: mensagem });
    }
  }
}

/**
 * Capa (imagem) servida pelo backend -- o app e as paginas deixam de
 * buscar direto no Drive, o que permite deixar a pasta restrita. So
 * entrega arquivos de IMAGEM (ate MAX_BYTES_CAPA); guarda uma copia
 * privada no bucket (capas/<fileId>) pra nao reler do Drive toda vez.
 */
async function enviarCapa(req, res, fileId) {
  if (!/^[a-zA-Z0-9_-]+$/.test(fileId || '')) {
    return res.status(400).json({ erro: 'fileId inválido.' });
  }
  // Libera o uso por <img>/Flutter Web de outra origem (helmet poe
  // Cross-Origin-Resource-Policy: same-origin por padrao).
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Cross-Origin-Resource-Policy', 'cross-origin');
  res.set('Cache-Control', 'private, max-age=86400');

  const objeto = MIDIA_BUCKET ? getStorage().bucket(MIDIA_BUCKET).file(`capas/${fileId}`) : null;
  try {
    if (objeto) {
      try {
        const [guardada] = await objeto.download(); // 1 operacao: hit devolve os bytes, miss da 404
        return enviarBuffer(req, res, guardada, tipoDaImagem(guardada));
      } catch (erroBucket) {
        if (!erroBucket || erroBucket.code !== 404) throw erroBucket;
      }
    }
    const arquivo = await baixarDoDrive(fileId, { maxBytes: MAX_BYTES_CAPA, validar: ehImagem });
    enviarBuffer(req, res, arquivo.bytes, arquivo.mimeType);
    if (objeto) {
      objeto
        .save(arquivo.bytes, { contentType: arquivo.mimeType, resumable: false })
        .catch((erroGravacao) => {
          console.error(`Erro ao gravar cache de capa (${fileId}):`, erroGravacao);
        });
    }
  } catch (erro) {
    const status = statusDoErro(erro);
    console.error(`Erro ao enviar capa ${fileId}:`, erro);
    if (status === 502) registrarAlerta('/capa', `${fileId}: ${(erro && erro.message) || erro}`);
    if (!res.headersSent) {
      res.status(status).json({ erro: erro && erro.httpStatus ? erro.message : 'Capa indisponível.' });
    }
  }
}

/**
 * Aquecimento do cache de midia: quando faixas entram numa playlist, o
 * servidor copia o MP3 do Drive pro bucket em segundo plano, ANTES de
 * alguem pedir. Assim o download offline do cliente (que baixa a playlist
 * inteira de uma vez) nao espera o Drive faixa por faixa. Limites de
 * proposito: 2 copias ao mesmo tempo, fila de no maximo 300 faixas
 * (o excedente simplesmente continua sendo copiado na primeira vez que
 * alguem tocar, como sempre foi) e nada de arquivo que ja esta no bucket.
 * Desliga com AQUECER_CACHE=0. Observacao: o Cloud Run so garante CPU
 * fora de uma requisicao com "CPU sempre alocada" (--no-cpu-throttling);
 * sem isso o aquecimento anda mais devagar, mas nunca atrapalha nada.
 */
const AQUECER_ATIVO = process.env.AQUECER_CACHE !== '0';
const AQUECER_CONCORRENCIA = 2;
const AQUECER_FILA_MAX = 300;
const filaAquecer = [];
const pendentesAquecer = new Set();
let trabalhadoresAquecer = 0;

async function trabalhadorAquecer() {
  trabalhadoresAquecer++;
  try {
    while (filaAquecer.length) {
      const fileId = filaAquecer.shift();
      try {
        const objeto = getStorage().bucket(MIDIA_BUCKET).file(`midia/${fileId}.mp3`);
        const [existe] = await objeto.exists();
        if (!existe) {
          const arquivo = await baixarDoDrive(fileId, { maxBytes: MAX_BYTES_AUDIO, validar: ehAudio });
          await objeto.save(arquivo.bytes, { contentType: 'audio/mpeg', resumable: false });
        }
      } catch (erro) {
        console.error(`Aviso: não consegui aquecer o cache de ${fileId}:`, (erro && erro.message) || erro);
      } finally {
        pendentesAquecer.delete(fileId);
      }
    }
  } finally {
    trabalhadoresAquecer--;
  }
}

function aquecerCache(fileIds) {
  if (!AQUECER_ATIVO || !MIDIA_BUCKET || !Array.isArray(fileIds)) return;
  for (const fileId of fileIds) {
    if (filaAquecer.length >= AQUECER_FILA_MAX) break;
    if (!/^[a-zA-Z0-9_-]+$/.test(fileId || '') || pendentesAquecer.has(fileId)) continue;
    pendentesAquecer.add(fileId);
    filaAquecer.push(fileId);
  }
  for (let i = trabalhadoresAquecer; i < AQUECER_CONCORRENCIA && i < filaAquecer.length; i++) {
    trabalhadorAquecer().catch(() => {});
  }
}

app.get('/midia/:fileId', limiteMidia, exigirAppIdLiberado, async (req, res) => {
  await enviarMidia(req, res, req.params.fileId);
});

/** Capa de álbum/playlist pro app e pra /minhaplaylist (exige App_ID liberado). */
app.get('/capa/:fileId', limiteCapa, exigirAppIdLiberado, async (req, res) => {
  await enviarCapa(req, res, req.params.fileId);
});

/**
 * Lista subpastas e arquivos de uma pasta do Drive (paginando se precisar
 * — mais de 1000 itens numa pasta só).
 */
async function listarFilhos(drive, pastaId) {
  const subpastas = [];
  const arquivos = [];
  let pageToken;
  do {
    const resposta = await drive.files.list({
      q: `'${pastaId}' in parents and trashed = false`,
      fields: 'nextPageToken, files(id, name, mimeType, size, createdTime)',
      pageSize: 1000,
      pageToken,
    });
    for (const item of resposta.data.files || []) {
      if (item.mimeType === 'application/vnd.google-apps.folder') {
        subpastas.push(item);
      } else {
        arquivos.push(item);
      }
    }
    pageToken = resposta.data.nextPageToken || undefined;
  } while (pageToken);
  return { subpastas, arquivos };
}

/**
 * Gera o cache da biblioteca inteira, no MESMO formato que
 * backend/CacheBiblioteca.gs já produz ({ geradoEm, totalAlbuns, albuns,
 * arvore }), e sobrescreve o mesmo arquivo do Drive — pra que o app
 * Flutter (que já lê esse arquivo) não precise de nenhuma mudança pra
 * testar essa geração alternativa.
 */
let gerandoCache = false;

app.get('/gerar-cache', limiteGerarCache, async (req, res) => {
  if (!chavesIguais(req.query.chave, GERAR_CACHE_CHAVE)) {
    return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  }
  if (gerandoCache) {
    return res.status(429).json({ erro: 'Ja existe uma geracao de cache em andamento -- aguarde ela terminar.' });
  }

  gerandoCache = true;
  const inicio = Date.now();
  try {
    const drive = await getDriveClient();
    const albuns = [];
    const arvore = [];

    async function percorrer(pastaId, paiId, nomePasta, criadoEmPasta, profundidade) {
      if (profundidade > PROFUNDIDADE_MAX) return;

      const { subpastas, arquivos } = await listarFilhos(drive, pastaId);

      let temMp3 = false;
      let capaId = null;
      for (const arquivo of arquivos) {
        const nome = arquivo.name || '';
        const ehMp3 =
          nome.toLowerCase().endsWith('.mp3') || arquivo.mimeType === 'audio/mpeg';
        if (ehMp3) {
          temMp3 = true;
          arvore.push({
            tipo: 'faixa',
            id: arquivo.id,
            name: nome,
            paiId: pastaId,
            size: Number(arquivo.size || 0),
          });
        } else if (capaId === null && (arquivo.mimeType || '').startsWith('image/')) {
          capaId = arquivo.id;
        }
      }

      if (paiId !== null) {
        arvore.push({
          tipo: 'pasta',
          id: pastaId,
          name: nomePasta,
          paiId,
          capaId,
          criadoEm: criadoEmPasta,
        });
      }

      if (temMp3) {
        albuns.push({ id: pastaId, name: nomePasta, capaId, criadoEm: criadoEmPasta });
      }

      // Processa subpastas em lotes paralelos — bem mais rápido que o
      // Apps Script (que é sempre sequencial), sem abrir concorrência
      // demais de uma vez.
      for (let i = 0; i < subpastas.length; i += CONCORRENCIA_GERAR_CACHE) {
        const lote = subpastas.slice(i, i + CONCORRENCIA_GERAR_CACHE);
        await Promise.all(
          lote.map((sub) =>
            percorrer(sub.id, pastaId, sub.name, sub.createdTime, profundidade + 1)
          )
        );
      }
    }

    await percorrer(PASTA_BIBLIOTECA_ID, null, null, null, 0);

    albuns.sort((a, b) => new Date(b.criadoEm).getTime() - new Date(a.criadoEm).getTime());

    const conteudo = JSON.stringify({
      geradoEm: new Date().toISOString(),
      geradoPor: 'cloud-run',
      totalAlbuns: albuns.length,
      albuns,
      arvore,
    });

    // Sobrescreve o mesmo arquivo que o Apps Script gera.
    await drive.files.update({
      fileId: CACHE_FILE_ID,
      media: {
        mimeType: 'application/json',
        body: stream.Readable.from([conteudo]),
      },
    });
    // Garante que continua público de leitura (idempotente, igual o
    // CacheBiblioteca.gs faz).
    await drive.permissions.create({
      fileId: CACHE_FILE_ID,
      requestBody: { role: 'reader', type: 'anyone' },
    });

    const totalFaixas = arvore.filter((n) => n.tipo === 'faixa').length;
    const resumoGeracao = {
      geradoEm: new Date().toISOString(),
      totalAlbuns: albuns.length,
      totalFaixas,
      totalNos: arvore.length,
      duracaoMs: Date.now() - inicio,
    };

    // Guarda o resultado no Firestore pro painel mostrar sem precisar
    // rodar /gerar-cache de novo — falha aqui não deve derrubar a
    // resposta principal (o cache já foi gravado com sucesso).
    try {
      const db = getFirestore();
      await db.collection('estado').doc('biblioteca').set(resumoGeracao);
      await db.collection('historicoBiblioteca').add(resumoGeracao);
    } catch (erroFirestore) {
      console.error('Aviso: falha ao salvar estado no Firestore (não bloqueia):', erroFirestore);
    }

    return res.json({ ok: true, ...resumoGeracao });
  } catch (erro) {
    console.error('Erro em /gerar-cache:', erro);
    registrarAlerta('/gerar-cache', erro);

    // Grava a falha no histórico também (antes só sucesso ficava
    // registrado) — pra tabela de últimas gerações do painel mostrar
    // quando uma rodada quebrou, não só as que deram certo (30/08/2026).
    try {
      await getFirestore().collection('historicoBiblioteca').add({
        geradoEm: new Date().toISOString(),
        erro: String((erro && erro.message) || erro),
        duracaoMs: Date.now() - inicio,
      });
    } catch (erroFirestore) {
      console.error('Aviso: falha ao salvar falha no Firestore (não bloqueia):', erroFirestore);
    }

    return res.status(500).json({
      erro: 'Falha ao gerar o cache.',
      detalhe: String((erro && erro.message) || erro),
      duracaoMs: Date.now() - inicio,
    });
  } finally {
    gerandoCache = false;
  }
});

/**
 * Registrado pelo app a cada faixa que começa a tocar de verdade (ver
 * PlayerService no Flutter). Sem trava de senha — é chamado o tempo todo
 * durante o uso normal do app, não é uma ação administrativa. O app
 * ignora o resultado (não afeta a reprodução se isso aqui falhar).
 */
app.post('/registrar-play', async (req, res) => {
  const { appId, faixaId, faixaNome, albumNome } = req.body || {};
  if (!appId || !faixaId) {
    return res.status(400).json({ erro: 'appId e faixaId são obrigatórios.' });
  }
  try {
    await getFirestore().collection('plays').add({
      appId: String(appId),
      faixaId: String(faixaId),
      faixaNome: String(faixaNome || ''),
      albumNome: String(albumNome || ''),
      timestamp: Firestore.FieldValue.serverTimestamp(),
    });
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em /registrar-play:', erro);
    return res.status(500).json({ erro: 'Falha ao registrar o play.' });
  }
});

/**
 * Resumo pro topo do painel — junta o último resultado de /gerar-cache
 * (guardado no Firestore) com a contagem de dispositivos da planilha.
 */
/**
 * Estatísticas do cache de mídia (bucket do Cloud Storage usado pelo
 * proxy /midia) — quantos arquivos já estão em cache e quanto espaço
 * ocupam, pro painel mostrar sem precisar abrir o Console (30/08/2026).
 * Retorna null se MIDIA_BUCKET não estiver configurado — não deve
 * quebrar o resto do /api/resumo se isso falhar.
 */
async function estatisticasCacheMidia() {
  if (!MIDIA_BUCKET) return null;
  try {
    const [arquivos] = await getStorage().bucket(MIDIA_BUCKET).getFiles({ prefix: 'midia/' });
    const totalBytes = arquivos.reduce((soma, a) => soma + Number(a.metadata.size || 0), 0);
    return { totalArquivos: arquivos.length, totalBytes };
  } catch (erro) {
    console.error('Aviso: falha ao ler estatísticas do cache de mídia (não bloqueia):', erro);
    return null;
  }
}

app.get('/api/resumo', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    const db = getFirestore();

    const [doc, historicoSnap, leitura, cacheMidia] = await Promise.all([
      db.collection('estado').doc('biblioteca').get(),
      db.collection('historicoBiblioteca').orderBy('geradoEm', 'desc').limit(30).get(),
      getSheetsClient().then((sheets) =>
        sheets.spreadsheets.values.get({ spreadsheetId: PLANILHA_ID, range: `${ABA_NOME}!A:D` })
      ),
      estatisticasCacheMidia(),
    ]);

    const biblioteca = doc.exists ? doc.data() : null;
    const historico = historicoSnap.docs
      .map((d) => d.data())
      .reverse(); // mais antigo primeiro, pro gráfico

    const linhas = (leitura.data.values || []).slice(1);
    const liberados = linhas.filter(
      (l) => String(l[1] || '').trim().toLowerCase() === 'liberado'
    ).length;

    return res.json({
      biblioteca,
      historico,
      cacheMidia,
      dispositivos: {
        liberados,
        bloqueados: linhas.length - liberados,
        total: linhas.length,
      },
    });
  } catch (erro) {
    console.error('Erro em /api/resumo:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar o resumo.' });
  }
});

/**
 * Últimos alertas de erro registrados (ver registrarAlerta acima) — pro
 * painel avisar se algo deu errado recentemente (Drive bloqueando,
 * /gerar-cache falhando, etc.) sem precisar checar o Cloud Logging
 * manualmente (30/08/2026).
 */
app.get('/api/alertas', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    const snap = await getFirestore()
      .collection('alertas')
      .orderBy('timestamp', 'desc')
      .limit(10)
      .get();
    const alertas = snap.docs.map((d) => {
      const dados = d.data();
      return {
        origem: dados.origem,
        detalhe: dados.detalhe,
        timestamp: dados.timestamp && dados.timestamp.toDate ? dados.timestamp.toDate().toISOString() : null,
      };
    });
    return res.json({ alertas });
  } catch (erro) {
    console.error('Erro em /api/alertas:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar alertas.' });
  }
});

/**
 * Lista completa de dispositivos/usuários da planilha, com o engajamento
 * de cada um (últimos 14 dias) quando disponível — pro painel.
 */
app.get('/api/usuarios', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    const sheets = await getSheetsClient();
    const leitura = await sheets.spreadsheets.values.get({
      spreadsheetId: PLANILHA_ID,
      range: `${ABA_NOME}!A:D`,
    });
    const linhas = (leitura.data.values || []).slice(1);
    const usuarios = linhas
      .filter((l) => l[0])
      .map((l) => ({
        appId: l[0],
        status: String(l[1] || '').trim(),
        nome: l[2] || '',
        dataLiberacao: l[3] || '',
      }));

    let porUsuario = {};
    try {
      porUsuario = await agregarEngajamentoPorUsuario();
    } catch (erroEngajamento) {
      console.error('Aviso: falha ao juntar engajamento em /api/usuarios (não bloqueia):', erroEngajamento);
    }

    usuarios.forEach((u) => {
      const info = porUsuario[u.appId];
      u.totalPlays14d = info ? info.totalPlays : 0;
      u.faixaFavorita = info ? info.faixaFavorita : null;
    });

    return res.json({ usuarios });
  } catch (erro) {
    console.error('Erro em /api/usuarios:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar usuários.' });
  }
});

/**
 * Últimas faixas que um App_ID específico tocou — pro painel mostrar
 * "o que esse cliente andou ouvindo" ao expandir a linha dele
 * (30/08/2026). Sem filtro de data no Firestore (só igualdade de
 * appId, sem orderBy) pra não precisar de índice composto — ordena e
 * corta em memória, tranquilo no volume de uso atual.
 */
app.get('/api/usuario-plays', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  const appId = req.query.appId;
  if (!appId) return res.status(400).json({ erro: 'appId é obrigatório.' });
  try {
    const snap = await getFirestore()
      .collection('plays')
      .where('appId', '==', String(appId))
      .get();
    const plays = [];
    snap.forEach((doc) => {
      const d = doc.data();
      if (!d.timestamp || !d.timestamp.toDate) return;
      plays.push({
        faixaNome: d.faixaNome || d.faixaId,
        albumNome: d.albumNome || '',
        data: d.timestamp.toDate().toISOString(),
      });
    });
    plays.sort((a, b) => b.data.localeCompare(a.data));
    return res.json({ plays: plays.slice(0, 50) });
  } catch (erro) {
    console.error('Erro em /api/usuario-plays:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar as faixas do usuário.' });
  }
});

/**
 * Apaga TODOS os documentos da coleção "plays" — zera o histórico de
 * reprodução usado pelo painel (Faixas mais tocadas, Plays por dia,
 * Álbuns mais tocados e o histórico por usuário). Ação manual, disparada
 * uma vez visitando a URL com a chave (mesmo padrão do /gerar-cache) —
 * não é usada pelo app nem chamada automaticamente por nada.
 * IRREVERSÍVEL: não existe backup dos plays apagados.
 */
app.get('/api/zerar-plays', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  // Acao irreversivel (apaga TODO o historico de plays) -- exige uma
  // segunda confirmacao explicita na propria URL, alem da chave, pra
  // nao disparar sozinha por acidente (ex: um crawler/preview de link
  // seguindo a URL, ou um clique errado num link salvo).
  if (req.query.confirmar !== 'sim') {
    return res.status(400).json({
      erro: 'Acao irreversivel. Confirme adicionando &confirmar=sim na URL.',
    });
  }
  try {
    const db = getFirestore();
    let totalApagado = 0;
    // Apaga em lotes de até 500 (limite de um batch do Firestore),
    // repetindo até a coleção esvaziar.
    while (true) {
      const snap = await db.collection('plays').limit(500).get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      totalApagado += snap.size;
    }
    console.log(`/api/zerar-plays: ${totalApagado} plays apagados.`);
    registrarAlerta('/api/zerar-plays', `${totalApagado} plays apagados (IP ${req.ip}).`);
    return res.json({ ok: true, totalApagado });
  } catch (erro) {
    console.error('Erro em /api/zerar-plays:', erro);
    return res.status(500).json({ erro: 'Falha ao zerar os plays.' });
  }
});

/**
 * Libera um App_ID (muda Status pra "Liberado" na planilha) — ação do
 * botão "Liberar" no painel.
 */
app.post('/api/liberar', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  const { appId } = req.body || {};
  if (!appId) return res.status(400).json({ erro: 'appId é obrigatório.' });
  try {
    const sheets = await getSheetsClient();
    const range = `${ABA_NOME}!A:D`;
    const leitura = await sheets.spreadsheets.values.get({ spreadsheetId: PLANILHA_ID, range });
    const linhas = leitura.data.values || [];

    let linhaEncontrada = -1;
    for (let i = 1; i < linhas.length; i++) {
      if (linhas[i][0] === appId) {
        linhaEncontrada = i;
        break;
      }
    }
    if (linhaEncontrada === -1) {
      return res.status(404).json({ erro: 'appId não encontrado.' });
    }

    const numeroLinha = linhaEncontrada + 1; // planilha é 1-indexed
    await sheets.spreadsheets.values.update({
      spreadsheetId: PLANILHA_ID,
      range: `${ABA_NOME}!B${numeroLinha}`,
      valueInputOption: 'RAW',
      requestBody: { values: [['Liberado']] },
    });
    registrarAlerta('/api/liberar', `appId ${appId} liberado (IP ${req.ip}).`);
    // Invalida o cache de liberados na hora -- sem isso, esse mesmo
    // App_ID so passaria a tocar/ver o catalogo depois de ate 30s (TTL
    // do cache usado por /cache e /midia, ver obterLiberados acima).
    liberadosCache = { set: null, expiraEm: 0 };
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em /api/liberar:', erro);
    return res.status(500).json({ erro: 'Falha ao liberar o dispositivo.' });
  }
});

/**
 * Busca os plays dos últimos `dias` no Firestore. Volume esperado é
 * baixo (uso pessoal/família), então agrega tudo em memória — sem
 * precisar de contadores pré-computados nesse tamanho de uso.
 */
async function buscarPlaysRecentes(dias) {
  const desde = new Date(Date.now() - dias * 24 * 60 * 60 * 1000);
  const snap = await getFirestore()
    .collection('plays')
    .where('timestamp', '>=', desde)
    .get();
  const plays = [];
  snap.forEach((doc) => {
    const d = doc.data();
    if (!d.timestamp || !d.timestamp.toDate) return;
    plays.push({
      appId: d.appId,
      faixaId: d.faixaId,
      faixaNome: d.faixaNome || d.faixaId,
      albumNome: d.albumNome || '',
      data: d.timestamp.toDate(),
    });
  });
  return plays;
}

/**
 * Agrega, por App_ID, total de plays e faixa favorita nos últimos 14
 * dias — usado por /api/usuarios pra enriquecer a lista.
 */
async function agregarEngajamentoPorUsuario() {
  const plays = await buscarPlaysRecentes(14);
  const porUsuario = {};
  plays.forEach((p) => {
    if (!porUsuario[p.appId]) porUsuario[p.appId] = { totalPlays: 0, faixas: {} };
    porUsuario[p.appId].totalPlays += 1;
    const faixas = porUsuario[p.appId].faixas;
    faixas[p.faixaId] = faixas[p.faixaId] || { nome: p.faixaNome, count: 0 };
    faixas[p.faixaId].count += 1;
  });

  const resultado = {};
  Object.entries(porUsuario).forEach(([appId, info]) => {
    let favorita = null;
    Object.values(info.faixas).forEach((f) => {
      if (!favorita || f.count > favorita.count) favorita = f;
    });
    resultado[appId] = {
      totalPlays: info.totalPlays,
      faixaFavorita: favorita ? favorita.nome : null,
    };
  });
  return resultado;
}

/**
 * Engajamento agregado pro painel: plays por dia (14 dias), faixas mais
 * tocadas (14 dias) e usuários ativos hoje.
 */
app.get('/api/engajamento', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    const plays = await buscarPlaysRecentes(14);

    const porDia = {};
    const porFaixa = {};
    const porAlbum = {};
    const usuariosHoje = new Set();
    const hojeStr = new Date().toISOString().slice(0, 10);

    plays.forEach((p) => {
      const diaStr = p.data.toISOString().slice(0, 10);
      porDia[diaStr] = (porDia[diaStr] || 0) + 1;
      if (diaStr === hojeStr) usuariosHoje.add(p.appId);

      porFaixa[p.faixaId] = porFaixa[p.faixaId] || { faixaNome: p.faixaNome, count: 0 };
      porFaixa[p.faixaId].count += 1;

      if (p.albumNome) {
        porAlbum[p.albumNome] = porAlbum[p.albumNome] || { albumNome: p.albumNome, count: 0 };
        porAlbum[p.albumNome].count += 1;
      }
    });

    const playsPorDia = Object.entries(porDia)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([dia, total]) => ({ dia, total }));

    const topFaixas = Object.values(porFaixa)
      .sort((a, b) => b.count - a.count)
      .slice(0, 8);

    const topAlbuns = Object.values(porAlbum)
      .sort((a, b) => b.count - a.count)
      .slice(0, 8);

    return res.json({
      playsPorDia,
      topFaixas,
      topAlbuns,
      usuariosAtivosHoje: usuariosHoje.size,
      totalPlays14d: plays.length,
    });
  } catch (erro) {
    console.error('Erro em /api/engajamento:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar engajamento.' });
  }
});

// ============================================================
// PLAYLISTS CURADAS (10/09/2026) — em vez do usuário navegar pastas
// cruas do Drive, o Barclay cura faixas em playlists numa página de
// curadoria própria; o app só lista o que está curado, e só as
// playlists direcionadas ao appId de quem está pedindo (não existe
// playlist pública/compartilhada — toda playlist tem 1+ App_ID alvo,
// ver appIds abaixo). Duas coleções novas no Firestore:
//   playlists/{id}              -> { nome, capaId, faixas: [...], appIds: [...], criadoEm, atualizadoEm }
//   curadoria_vistos/{albumId}  -> { albumId, status, vistoEm } — álbuns já
//     revisados na curadoria (incluídos numa playlist ou ignorados), pra
//     alimentar o contador "Novidades" sem repetir álbum já visto.
// Rotas /api/admin/playlists* e /api/admin/novidades|vistos (protegidas
// por PAINEL_CHAVE) são usadas só pela página de curadoria. Rotas
// /api/playlists* (protegidas por appId liberado, mesmo padrão de /cache
// e /midia) são as que o app consome — e filtram por appIds.
// ============================================================

/** Playlist inteira, sem checagem de dono (uso pessoal). */
async function obterPlaylistDoc(id) {
  const doc = await getFirestore().collection('playlists').doc(id).get();
  return doc.exists ? { id: doc.id, ...doc.data() } : null;
}

// ---- Admin: CRUD de playlists (curadoria) ----

app.get('/api/admin/playlists', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    const snap = await getFirestore().collection('playlists').orderBy('criadoEm', 'desc').get();
    const playlists = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    return res.json({ playlists });
  } catch (erro) {
    console.error('Erro em GET /api/admin/playlists:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar playlists.' });
  }
});

app.post('/api/admin/playlists', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  const nome = String((req.body && req.body.nome) || '').trim();
  const appIds = Array.isArray(req.body && req.body.appIds)
    ? [...new Set(req.body.appIds.map(String).filter(Boolean))]
    : [];
  if (!nome) return res.status(400).json({ erro: 'nome é obrigatório.' });
  if (!appIds.length) return res.status(400).json({ erro: 'Informe pelo menos um App_ID pra essa playlist.' });
  try {
    const liberados = await obterLiberados();
    const invalidos = appIds.filter((id) => !liberados.has(id));
    if (invalidos.length) {
      return res.status(400).json({ erro: `App_ID(s) não liberado(s): ${invalidos.join(', ')}` });
    }
    const agora = new Date().toISOString();
    const ref = await getFirestore().collection('playlists').add({
      nome,
      capaId: null,
      faixas: [],
      appIds,
      criadoEm: agora,
      atualizadoEm: agora,
    });
    return res.json({ id: ref.id });
  } catch (erro) {
    console.error('Erro em POST /api/admin/playlists:', erro);
    return res.status(500).json({ erro: 'Falha ao criar playlist.' });
  }
});

app.put('/api/admin/playlists/:id', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  const { id } = req.params;
  const nome = req.body && req.body.nome != null ? String(req.body.nome).trim() : null;
  if (!nome) return res.status(400).json({ erro: 'nome é obrigatório.' });
  try {
    const ref = getFirestore().collection('playlists').doc(id);
    const doc = await ref.get();
    if (!doc.exists) return res.status(404).json({ erro: 'Playlist não encontrada.' });
    await ref.update({ nome, atualizadoEm: new Date().toISOString() });
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em PUT /api/admin/playlists/:id:', erro);
    return res.status(500).json({ erro: 'Falha ao renomear playlist.' });
  }
});

app.delete('/api/admin/playlists/:id', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    await getFirestore().collection('playlists').doc(req.params.id).delete();
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em DELETE /api/admin/playlists/:id:', erro);
    return res.status(500).json({ erro: 'Falha ao apagar playlist.' });
  }
});

/**
 * Adiciona uma faixa à playlist (ignora se o fileId já estiver nela —
 * clicar duas vezes no "+" da curadoria não duplica).
 */
app.post('/api/admin/playlists/:id/faixas', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  const { fileId, nome, albumId, albumNome, capaId } = req.body || {};
  if (!fileId || !nome) return res.status(400).json({ erro: 'fileId e nome são obrigatórios.' });
  try {
    const ref = getFirestore().collection('playlists').doc(req.params.id);
    const doc = await ref.get();
    if (!doc.exists) return res.status(404).json({ erro: 'Playlist não encontrada.' });
    const faixas = doc.data().faixas || [];
    if (faixas.some((f) => f.fileId === fileId)) {
      return res.json({ ok: true, jaExistia: true });
    }
    faixas.push({
      fileId: String(fileId),
      nome: String(nome),
      albumId: albumId ? String(albumId) : null,
      albumNome: albumNome ? String(albumNome) : '',
      capaId: capaId ? String(capaId) : null,
    });
    const atualizacao = { faixas, atualizadoEm: new Date().toISOString() };
    // Primeira faixa adicionada define a capa da playlist, se ainda não tiver uma.
    if (!doc.data().capaId && capaId) atualizacao.capaId = String(capaId);
    await ref.update(atualizacao);
    aquecerCache([String(fileId)]);
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em POST /api/admin/playlists/:id/faixas:', erro);
    return res.status(500).json({ erro: 'Falha ao adicionar faixa.' });
  }
});

/**
 * Adiciona várias faixas de uma vez (ex.: "álbum inteiro") — body
 * { faixas: [{ fileId, nome, albumId, albumNome, capaId }, ...] } (até 500).
 * Só entram as que ainda não estão na playlist. Uma única chamada em vez
 * de N, pra não estourar o limite de requisições da página de curadoria.
 */
app.post('/api/admin/playlists/:id/faixas-lote', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  const entrada = Array.isArray(req.body && req.body.faixas) ? req.body.faixas : [];
  if (!entrada.length) return res.status(400).json({ erro: 'Nenhuma faixa informada.' });
  if (entrada.length > 500) return res.status(400).json({ erro: 'Máximo de 500 faixas por vez.' });
  try {
    const ref = getFirestore().collection('playlists').doc(req.params.id);
    const doc = await ref.get();
    if (!doc.exists) return res.status(404).json({ erro: 'Playlist não encontrada.' });
    const dados = doc.data();
    const faixas = dados.faixas || [];
    const existentes = new Set(faixas.map((f) => f.fileId));
    let adicionadas = 0;
    let jaExistiam = 0;
    let primeiraCapa = null;
    const novas = [];
    for (const f of entrada) {
      if (!f || !f.fileId || !f.nome) continue;
      const fileId = String(f.fileId);
      if (existentes.has(fileId)) { jaExistiam++; continue; }
      existentes.add(fileId);
      faixas.push({
        fileId,
        nome: String(f.nome),
        albumId: f.albumId ? String(f.albumId) : null,
        albumNome: f.albumNome ? String(f.albumNome) : '',
        capaId: f.capaId ? String(f.capaId) : null,
      });
      if (!primeiraCapa && f.capaId) primeiraCapa = String(f.capaId);
      novas.push(fileId);
      adicionadas++;
    }
    const atualizacao = { faixas, atualizadoEm: new Date().toISOString() };
    if (!dados.capaId && primeiraCapa) atualizacao.capaId = primeiraCapa;
    if (adicionadas > 0) await ref.update(atualizacao);
    aquecerCache(novas);
    return res.json({ ok: true, adicionadas, jaExistiam, playlist: { id: doc.id, ...dados, ...atualizacao } });
  } catch (erro) {
    console.error('Erro em POST /api/admin/playlists/:id/faixas-lote:', erro);
    return res.status(500).json({ erro: 'Falha ao adicionar faixas.' });
  }
});

app.delete('/api/admin/playlists/:id/faixas/:fileId', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    const ref = getFirestore().collection('playlists').doc(req.params.id);
    const doc = await ref.get();
    if (!doc.exists) return res.status(404).json({ erro: 'Playlist não encontrada.' });
    const faixas = (doc.data().faixas || []).filter((f) => f.fileId !== req.params.fileId);
    await ref.update({ faixas, atualizadoEm: new Date().toISOString() });
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em DELETE /api/admin/playlists/:id/faixas/:fileId:', erro);
    return res.status(500).json({ erro: 'Falha ao remover faixa.' });
  }
});

/** Reordena as faixas — body { ordem: [fileId, fileId, ...] }. */
app.put('/api/admin/playlists/:id/reordenar', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  const ordem = (req.body && req.body.ordem) || [];
  if (!Array.isArray(ordem) || !ordem.length) return res.status(400).json({ erro: 'ordem é obrigatória.' });
  try {
    const ref = getFirestore().collection('playlists').doc(req.params.id);
    const doc = await ref.get();
    if (!doc.exists) return res.status(404).json({ erro: 'Playlist não encontrada.' });
    const porId = new Map((doc.data().faixas || []).map((f) => [f.fileId, f]));
    const faixasOrdenadas = ordem.map((fid) => porId.get(fid)).filter(Boolean);
    await ref.update({ faixas: faixasOrdenadas, atualizadoEm: new Date().toISOString() });
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em PUT /api/admin/playlists/:id/reordenar:', erro);
    return res.status(500).json({ erro: 'Falha ao reordenar.' });
  }
});

/**
 * Muda quem vê a playlist — body { appIds: [appId, appId, ...] }. Toda
 * playlist precisa de pelo menos um App_ID alvo (não existe playlist
 * "pública" pra todo mundo); o app só lista/abre playlists onde o seu
 * appId está nessa lista (ver GET /api/playlists e /api/playlists/:id).
 * Cada App_ID é validado contra a planilha de liberados — não aceita ID
 * inventado/errado nem de gente não liberada.
 */
app.put('/api/admin/playlists/:id/usuarios', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  const appIds = Array.isArray(req.body && req.body.appIds)
    ? [...new Set(req.body.appIds.map(String).filter(Boolean))]
    : [];
  if (!appIds.length) return res.status(400).json({ erro: 'Informe pelo menos um App_ID pra essa playlist.' });
  try {
    const liberados = await obterLiberados();
    const invalidos = appIds.filter((id) => !liberados.has(id));
    if (invalidos.length) {
      return res.status(400).json({ erro: `App_ID(s) não liberado(s): ${invalidos.join(', ')}` });
    }
    const ref = getFirestore().collection('playlists').doc(req.params.id);
    const doc = await ref.get();
    if (!doc.exists) return res.status(404).json({ erro: 'Playlist não encontrada.' });
    await ref.update({ appIds, atualizadoEm: new Date().toISOString() });
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em PUT /api/admin/playlists/:id/usuarios:', erro);
    return res.status(500).json({ erro: 'Falha ao atualizar os usuários da playlist.' });
  }
});

// ---- Admin: "Novidades" (álbuns ainda não revisados na curadoria) ----

/**
 * Busca o cache da biblioteca inteiro (álbuns + árvore de faixas) direto
 * do Drive (mesmo arquivo que /cache serve) — reaproveitado tanto por
 * /api/admin/cache (curadoria navega a biblioteca) quanto por
 * /api/admin/novidades (só precisa da lista de álbuns).
 */
async function obterCacheCompleto() {
  const { bytes } = await baixarDoDrive(CACHE_FILE_ID);
  return JSON.parse(bytes.toString('utf8'));
}

/**
 * Catálogo completo (álbuns + árvore de pastas/faixas) pra página de
 * curadoria navegar/buscar a biblioteca e montar playlists. Diferente de
 * /cache, não exige appId — protegido só por PAINEL_CHAVE, como o resto
 * de /api/admin/*.
 */
app.get('/api/admin/cache', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    const cache = await obterCacheCompleto();
    return res.json(cache);
  } catch (erro) {
    console.error('Erro em /api/admin/cache:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar o catálogo.' });
  }
});

/**
 * Preview de uma faixa direto na curadoria, antes de adicionar a uma
 * playlist — mesma lógica de cache do /midia/:fileId, só que protegida
 * por PAINEL_CHAVE (aceita ?chave=X, já que a tag <audio> não manda
 * headers customizados) em vez de appId liberado.
 */
app.get('/api/admin/midia/:fileId', limiteMidia, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  await enviarMidia(req, res, req.params.fileId);
});

/** Capa pra página de curadoria (a tag <img> não manda headers, então aceita ?chave=X como o preview de áudio). */
app.get('/api/admin/capa/:fileId', limiteCapa, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  await enviarCapa(req, res, req.params.fileId);
});

app.get('/api/admin/novidades', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    const [cache, vistosSnap] = await Promise.all([
      obterCacheCompleto(),
      getFirestore().collection('curadoria_vistos').get(),
    ]);
    const vistos = new Set(vistosSnap.docs.map((d) => d.id));
    const novidades = (cache.albuns || []).filter((a) => !vistos.has(a.id));
    return res.json({ novidades, total: novidades.length });
  } catch (erro) {
    console.error('Erro em /api/admin/novidades:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar novidades.' });
  }
});

/** Marca vários álbuns como revisados de uma vez — body { albumIds: [...], status }. */
app.post('/api/admin/vistos-lote', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  const ids = Array.isArray(req.body && req.body.albumIds)
    ? [...new Set(req.body.albumIds.map(String).filter(Boolean))]
    : [];
  const status = req.body && req.body.status ? String(req.body.status) : 'ignorado';
  if (!ids.length) return res.status(400).json({ erro: 'albumIds é obrigatório.' });
  try {
    const db = getFirestore();
    for (let i = 0; i < ids.length; i += 400) {
      const batch = db.batch();
      for (const albumId of ids.slice(i, i + 400)) {
        batch.set(db.collection('curadoria_vistos').doc(albumId), {
          albumId,
          status,
          vistoEm: Firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    return res.json({ ok: true, total: ids.length });
  } catch (erro) {
    console.error('Erro em /api/admin/vistos-lote:', erro);
    return res.status(500).json({ erro: 'Falha ao marcar como revisados.' });
  }
});

/** Marca um álbum como revisado (incluído numa playlist ou ignorado). */
app.post('/api/admin/vistos', limitePainel, async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  const { albumId, status } = req.body || {};
  if (!albumId) return res.status(400).json({ erro: 'albumId é obrigatório.' });
  try {
    await getFirestore().collection('curadoria_vistos').doc(String(albumId)).set({
      albumId: String(albumId),
      status: status ? String(status) : 'ignorado',
      vistoEm: Firestore.FieldValue.serverTimestamp(),
    });
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em /api/admin/vistos:', erro);
    return res.status(500).json({ erro: 'Falha ao marcar como visto.' });
  }
});

// ---- App: playlists visíveis pro usuário final ----

/**
 * Só devolve as playlists cujo appIds inclui quem está pedindo — cada
 * playlist é direcionada a um ou mais Apps/usuários específicos, não
 * existe playlist pública/compartilhada por todos.
 */
app.get('/api/playlists', limiteMidia, exigirAppIdLiberado, async (req, res) => {
  try {
    const appId = req.query.appId;
    const snap = await getFirestore().collection('playlists').orderBy('atualizadoEm', 'desc').get();
    const playlists = snap.docs
      .filter((d) => (d.data().appIds || []).includes(appId))
      .map((d) => {
        const dados = d.data();
        return {
          id: d.id,
          nome: dados.nome,
          capaId: dados.capaId || null,
          totalFaixas: (dados.faixas || []).length,
        };
      });
    return res.json({ playlists });
  } catch (erro) {
    console.error('Erro em GET /api/playlists:', erro);
    registrarAlerta('/api/playlists', erro);
    return res.status(500).json({ erro: 'Falha ao carregar playlists.' });
  }
});

app.get('/api/playlists/:id', limiteMidia, exigirAppIdLiberado, async (req, res) => {
  try {
    const playlist = await obterPlaylistDoc(req.params.id);
    if (!playlist) return res.status(404).json({ erro: 'Playlist não encontrada.' });
    if (!(playlist.appIds || []).includes(req.query.appId)) {
      return res.status(403).json({ erro: 'Você não tem acesso a essa playlist.' });
    }
    return res.json(playlist);
  } catch (erro) {
    console.error('Erro em GET /api/playlists/:id:', erro);
    registrarAlerta('/api/playlists/:id', erro);
    return res.status(500).json({ erro: 'Falha ao carregar playlist.' });
  }
});

// ---- Cliente: cada pessoa monta as PRÓPRIAS playlists (página /minhaplaylist) ----
//
// As playlists do cliente ficam na mesma coleção `playlists`, com
// appIds = [dono] e donoAppId = dono. Assim o app (GET /api/playlists) já
// as mostra sem nenhuma mudança, e o painel /criar as enxerga também.
// Autenticação: header X-App-Id liberado na planilha (mesma regra do
// /cache e /midia). O cliente só mexe em playlists onde donoAppId == ele —
// as curadas por você (sem donoAppId) são intocáveis por aqui.

const MAX_PLAYLISTS_CLIENTE = 30;
const MAX_FAIXAS_CLIENTE = 1000;
const limiteCliente = rateLimit({
  windowMs: 5 * 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: { erro: 'Muitas requisições. Aguarde um pouco.' },
});

async function exigirCliente(req, res, next) {
  const appId = String(req.get('X-App-Id') || '').trim();
  if (!appId) return res.status(401).json({ erro: 'App_ID ausente.' });
  try {
    const liberados = await obterLiberados();
    if (!liberados.has(appId)) return res.status(403).json({ erro: 'App_ID não liberado.' });
    req.appIdCliente = appId;
    next();
  } catch (erro) {
    console.error('Erro ao checar liberação do cliente:', erro);
    return res.status(503).json({ erro: 'Falha ao checar liberação. Tente novamente.' });
  }
}

/** Carrega a playlist e garante que é do cliente; responde o erro e devolve null se não for. */
async function playlistDoCliente(req, res) {
  const ref = getFirestore().collection('playlists').doc(req.params.id);
  const doc = await ref.get();
  if (!doc.exists) { res.status(404).json({ erro: 'Playlist não encontrada.' }); return null; }
  if (doc.data().donoAppId !== req.appIdCliente) {
    res.status(403).json({ erro: 'Essa playlist não é sua.' });
    return null;
  }
  return { ref, doc, dados: doc.data() };
}

/** Confirma o App_ID (usado no login da página). */
app.get('/api/cliente/eu', limiteCliente, exigirCliente, (req, res) => res.json({ ok: true }));

app.get('/api/cliente/playlists', limiteCliente, exigirCliente, async (req, res) => {
  try {
    const snap = await getFirestore().collection('playlists').where('donoAppId', '==', req.appIdCliente).get();
    const playlists = snap.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .sort((a, b) => String(b.criadoEm || '').localeCompare(String(a.criadoEm || '')));
    return res.json({ playlists });
  } catch (erro) {
    console.error('Erro em GET /api/cliente/playlists:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar suas playlists.' });
  }
});

app.post('/api/cliente/playlists', limiteCliente, exigirCliente, async (req, res) => {
  const nome = String((req.body && req.body.nome) || '').trim().slice(0, 60);
  if (!nome) return res.status(400).json({ erro: 'Dê um nome para a playlist.' });
  try {
    const col = getFirestore().collection('playlists');
    const existentes = await col.where('donoAppId', '==', req.appIdCliente).get();
    if (existentes.size >= MAX_PLAYLISTS_CLIENTE) {
      return res.status(400).json({ erro: `Limite de ${MAX_PLAYLISTS_CLIENTE} playlists atingido.` });
    }
    const agora = new Date().toISOString();
    const ref = await col.add({
      nome,
      capaId: null,
      faixas: [],
      appIds: [req.appIdCliente],
      donoAppId: req.appIdCliente,
      criadoEm: agora,
      atualizadoEm: agora,
    });
    return res.json({ id: ref.id });
  } catch (erro) {
    console.error('Erro em POST /api/cliente/playlists:', erro);
    return res.status(500).json({ erro: 'Falha ao criar a playlist.' });
  }
});

app.put('/api/cliente/playlists/:id', limiteCliente, exigirCliente, async (req, res) => {
  const nome = String((req.body && req.body.nome) || '').trim().slice(0, 60);
  if (!nome) return res.status(400).json({ erro: 'Dê um nome para a playlist.' });
  try {
    const p = await playlistDoCliente(req, res);
    if (!p) return;
    await p.ref.update({ nome, atualizadoEm: new Date().toISOString() });
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em PUT /api/cliente/playlists/:id:', erro);
    return res.status(500).json({ erro: 'Falha ao renomear.' });
  }
});

app.delete('/api/cliente/playlists/:id', limiteCliente, exigirCliente, async (req, res) => {
  try {
    const p = await playlistDoCliente(req, res);
    if (!p) return;
    await p.ref.delete();
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em DELETE /api/cliente/playlists/:id:', erro);
    return res.status(500).json({ erro: 'Falha ao apagar.' });
  }
});

app.post('/api/cliente/playlists/:id/faixas-lote', limiteCliente, exigirCliente, async (req, res) => {
  const entrada = Array.isArray(req.body && req.body.faixas) ? req.body.faixas : [];
  if (!entrada.length) return res.status(400).json({ erro: 'Nenhuma faixa informada.' });
  if (entrada.length > 500) return res.status(400).json({ erro: 'Máximo de 500 faixas por vez.' });
  try {
    const p = await playlistDoCliente(req, res);
    if (!p) return;
    const faixas = p.dados.faixas || [];
    const existentes = new Set(faixas.map((f) => f.fileId));
    let adicionadas = 0;
    let jaExistiam = 0;
    let cheia = false;
    let primeiraCapa = null;
    const novas = [];
    for (const f of entrada) {
      if (!f || !f.fileId || !f.nome) continue;
      const fileId = String(f.fileId);
      if (existentes.has(fileId)) { jaExistiam++; continue; }
      if (faixas.length >= MAX_FAIXAS_CLIENTE) { cheia = true; break; }
      existentes.add(fileId);
      faixas.push({
        fileId,
        nome: String(f.nome).slice(0, 300),
        albumId: f.albumId ? String(f.albumId) : null,
        albumNome: f.albumNome ? String(f.albumNome).slice(0, 300) : '',
        capaId: f.capaId ? String(f.capaId) : null,
      });
      if (!primeiraCapa && f.capaId) primeiraCapa = String(f.capaId);
      novas.push(fileId);
      adicionadas++;
    }
    const atualizacao = { faixas, atualizadoEm: new Date().toISOString() };
    if (!p.dados.capaId && primeiraCapa) atualizacao.capaId = primeiraCapa;
    if (adicionadas > 0) await p.ref.update(atualizacao);
    aquecerCache(novas);
    return res.json({
      ok: true, adicionadas, jaExistiam, cheia,
      playlist: { id: p.doc.id, ...p.dados, ...atualizacao },
    });
  } catch (erro) {
    console.error('Erro em POST /api/cliente/playlists/:id/faixas-lote:', erro);
    return res.status(500).json({ erro: 'Falha ao adicionar faixas.' });
  }
});

app.delete('/api/cliente/playlists/:id/faixas/:fileId', limiteCliente, exigirCliente, async (req, res) => {
  try {
    const p = await playlistDoCliente(req, res);
    if (!p) return;
    const faixas = (p.dados.faixas || []).filter((f) => f.fileId !== req.params.fileId);
    await p.ref.update({ faixas, atualizadoEm: new Date().toISOString() });
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em DELETE /api/cliente/playlists/:id/faixas/:fileId:', erro);
    return res.status(500).json({ erro: 'Falha ao remover faixa.' });
  }
});

app.put('/api/cliente/playlists/:id/reordenar', limiteCliente, exigirCliente, async (req, res) => {
  const ordem = (req.body && req.body.ordem) || [];
  if (!Array.isArray(ordem) || !ordem.length) return res.status(400).json({ erro: 'ordem é obrigatória.' });
  try {
    const p = await playlistDoCliente(req, res);
    if (!p) return;
    const porId = new Map((p.dados.faixas || []).map((f) => [f.fileId, f]));
    const ordenadas = ordem.map((fid) => porId.get(fid)).filter(Boolean);
    // Faixas que não vieram na ordem (adicionadas em outra aba) vão pro fim, sem sumir.
    const citadas = new Set(ordenadas.map((f) => f.fileId));
    porId.forEach((f, fid) => { if (!citadas.has(fid)) ordenadas.push(f); });
    await p.ref.update({ faixas: ordenadas, atualizadoEm: new Date().toISOString() });
    return res.json({ ok: true });
  } catch (erro) {
    console.error('Erro em PUT /api/cliente/playlists/:id/reordenar:', erro);
    return res.status(500).json({ erro: 'Falha ao reordenar.' });
  }
});

/** Página pública onde o cliente monta as próprias playlists; entra com o App_ID. */
app.get(['/minhaplaylist', '/minha'], limiteCliente, (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'minhaplaylist.html'));
});

/**
 * Link curto e público da página de criar playlists (/criar). A página
 * em si não expõe nada: ela pede a chave no login e só então chama as
 * rotas /api/admin/*, que continuam protegidas por PAINEL_CHAVE.
 */
app.get(['/criar', '/criarplaylist'], limitePainel, (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'curadoria.html'));
});

/**
 * A página de curadoria (arquivo estático em public/curadoria.html) —
 * onde o Barclay monta as playlists. Mesma trava de chave do /painel.
 */
app.get('/curadoria', limitePainel, (req, res) => {
  if (!chavePainelValida(req)) {
    return res.status(403).send('Acesso negado — chave ausente ou incorreta. Use /curadoria?chave=SUACHAVE');
  }
  res.sendFile(path.join(__dirname, 'public', 'curadoria.html'));
});

/**
 * A página do painel em si (arquivo estático em public/painel.html). A
 * página faz as chamadas de API do lado do navegador, repassando a
 * chave que veio na própria URL.
 */
app.get('/painel', limitePainel, (req, res) => {
  if (!chavePainelValida(req)) {
    return res.status(403).send('Acesso negado — chave ausente ou incorreta. Use /painel?chave=SUACHAVE');
  }
  res.sendFile(path.join(__dirname, 'public', 'painel.html'));
});

app.get('/', (_req, res) => {
  res.send(
    'Sonora backend (Cloud Run) no ar. Endpoints: /validar?id=XXX, /cache, /midia/:fileId e /gerar-cache?chave=XXX'
  );
});

app.listen(PORT, () => {
  console.log(`Sonora backend (Cloud Run) rodando na porta ${PORT}`);
});
