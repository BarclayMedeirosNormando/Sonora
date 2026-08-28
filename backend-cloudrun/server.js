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
// GET /gerar-cache?chave=XXX -> gera o cache da biblioteca inteira e
//   SOBRESCREVE o mesmo arquivo que backend/CacheBiblioteca.gs (Apps
//   Script) já gera hoje — o app não precisa saber quem escreveu. Existe
//   porque o Apps Script tem limite de 6 min por execução, o que não vai
//   dar conta de uma biblioteca de ~200 mil faixas (testado em
//   28/08/2026 com ~2.900 faixas, biblioteca ainda crescendo aos poucos).
//   Acionado manualmente pelo Barclay (não é chamado pelo app).
//
// PAINEL ADMINISTRATIVO (29/08/2026):
//   POST /registrar-play           -> app registra cada play no Firestore
//   GET  /api/resumo?chave=XXX     -> biblioteca + contagem de dispositivos
//   GET  /api/usuarios?chave=XXX   -> lista de dispositivos/usuários
//   POST /api/liberar?chave=XXX    -> libera um App_ID (Status -> Liberado)
//   GET  /api/engajamento?chave=XXX-> agrega plays do Firestore (14 dias)
//   GET  /painel?chave=XXX         -> a página do painel em si
//   Protegido por PAINEL_CHAVE (mesma ideia do GERAR_CACHE_CHAVE, senha
//   simples via query param — não é auth de verdade). /registrar-play não
//   tem trava, é chamado o tempo todo pelo app.
// ============================================================

const stream = require('stream');
const path = require('path');
const express = require('express');
const { Firestore } = require('@google-cloud/firestore');

const app = express();
const PORT = process.env.PORT || 8080;

// Configuração via variáveis de ambiente (definidas no deploy do Cloud
// Run — ver README.md). Valores default abaixo são os mesmos já usados
// no Apps Script hoje, só pra documentar o formato esperado.
const PLANILHA_ID = process.env.PLANILHA_ID || '1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE';
const ABA_NOME = process.env.ABA_NOME || 'Página1'; // conferir o nome real da aba na planilha
const CACHE_FILE_ID = process.env.CACHE_FILE_ID || '1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP';
const DRIVE_API_KEY = process.env.DRIVE_API_KEY || '';

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

let sheetsClientPromise = null;
let driveClientPromise = null;
let firestoreClientPromise = null;

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

function chavePainelValida(req) {
  return !PAINEL_CHAVE || req.query.chave === PAINEL_CHAVE;
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

/**
 * Checa se o App_ID está com Status "Liberado" na planilha de controle.
 * Se o ID ainda não existir, cadastra automaticamente como "Bloqueado"
 * (mesma lógica de validarId() em backend/AcessoWebApp.gs).
 */
app.get('/validar', async (req, res) => {
  const appId = req.query.id;
  if (!appId) {
    return res.json({ erro: 'Parâmetro id ausente.' });
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
app.get('/cache', async (req, res) => {
  try {
    const url =
      `https://www.googleapis.com/drive/v3/files/${CACHE_FILE_ID}` +
      `?alt=media&key=${DRIVE_API_KEY}`;
    const respostaDrive = await fetch(url);
    if (!respostaDrive.ok) {
      throw new Error(`Drive respondeu HTTP ${respostaDrive.status}`);
    }
    const texto = await respostaDrive.text();
    res.set('Content-Type', 'application/json; charset=utf-8');
    res.set('Access-Control-Allow-Origin', '*'); // libera CORS pro Flutter Web
    return res.send(texto);
  } catch (erro) {
    console.error('Erro em /cache:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar o cache da biblioteca.' });
  }
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
app.get('/gerar-cache', async (req, res) => {
  if (GERAR_CACHE_CHAVE && req.query.chave !== GERAR_CACHE_CHAVE) {
    return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  }

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
    return res.status(500).json({
      erro: 'Falha ao gerar o cache.',
      detalhe: String((erro && erro.message) || erro),
      duracaoMs: Date.now() - inicio,
    });
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
app.get('/api/resumo', async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    const db = getFirestore();
    const doc = await db.collection('estado').doc('biblioteca').get();
    const biblioteca = doc.exists ? doc.data() : null;

    const historicoSnap = await db
      .collection('historicoBiblioteca')
      .orderBy('geradoEm', 'desc')
      .limit(30)
      .get();
    const historico = historicoSnap.docs
      .map((d) => d.data())
      .reverse(); // mais antigo primeiro, pro gráfico

    const sheets = await getSheetsClient();
    const leitura = await sheets.spreadsheets.values.get({
      spreadsheetId: PLANILHA_ID,
      range: `${ABA_NOME}!A:D`,
    });
    const linhas = (leitura.data.values || []).slice(1);
    const liberados = linhas.filter(
      (l) => String(l[1] || '').trim().toLowerCase() === 'liberado'
    ).length;

    return res.json({
      biblioteca,
      historico,
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
 * Lista completa de dispositivos/usuários da planilha, com o engajamento
 * de cada um (últimos 14 dias) quando disponível — pro painel.
 */
app.get('/api/usuarios', async (req, res) => {
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
 * Libera um App_ID (muda Status pra "Liberado" na planilha) — ação do
 * botão "Liberar" no painel.
 */
app.post('/api/liberar', async (req, res) => {
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
app.get('/api/engajamento', async (req, res) => {
  if (!chavePainelValida(req)) return res.status(403).json({ erro: 'Chave ausente ou incorreta.' });
  try {
    const plays = await buscarPlaysRecentes(14);

    const porDia = {};
    const porFaixa = {};
    const usuariosHoje = new Set();
    const hojeStr = new Date().toISOString().slice(0, 10);

    plays.forEach((p) => {
      const diaStr = p.data.toISOString().slice(0, 10);
      porDia[diaStr] = (porDia[diaStr] || 0) + 1;
      if (diaStr === hojeStr) usuariosHoje.add(p.appId);

      porFaixa[p.faixaId] = porFaixa[p.faixaId] || { faixaNome: p.faixaNome, count: 0 };
      porFaixa[p.faixaId].count += 1;
    });

    const playsPorDia = Object.entries(porDia)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([dia, total]) => ({ dia, total }));

    const topFaixas = Object.values(porFaixa)
      .sort((a, b) => b.count - a.count)
      .slice(0, 8);

    return res.json({
      playsPorDia,
      topFaixas,
      usuariosAtivosHoje: usuariosHoje.size,
      totalPlays14d: plays.length,
    });
  } catch (erro) {
    console.error('Erro em /api/engajamento:', erro);
    return res.status(500).json({ erro: 'Falha ao carregar engajamento.' });
  }
});

/**
 * A página do painel em si (arquivo estático em public/painel.html). A
 * página faz as chamadas de API do lado do navegador, repassando a
 * chave que veio na própria URL.
 */
app.get('/painel', (req, res) => {
  if (!chavePainelValida(req)) {
    return res.status(403).send('Acesso negado — chave ausente ou incorreta. Use /painel?chave=SUACHAVE');
  }
  res.sendFile(path.join(__dirname, 'public', 'painel.html'));
});

app.get('/', (_req, res) => {
  res.send(
    'Sonora backend (Cloud Run) no ar. Endpoints: /validar?id=XXX, /cache e /gerar-cache?chave=XXX'
  );
});

app.listen(PORT, () => {
  console.log(`Sonora backend (Cloud Run) rodando na porta ${PORT}`);
});
