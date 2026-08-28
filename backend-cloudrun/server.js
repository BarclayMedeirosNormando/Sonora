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
// ============================================================

const express = require('express');

const app = express();
const PORT = process.env.PORT || 8080;

// Configuração via variáveis de ambiente (definidas no deploy do Cloud
// Run — ver README.md). Valores default abaixo são os mesmos já usados
// no Apps Script hoje, só pra documentar o formato esperado.
const PLANILHA_ID = process.env.PLANILHA_ID || '1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE';
const ABA_NOME = process.env.ABA_NOME || 'Página1'; // conferir o nome real da aba na planilha
const CACHE_FILE_ID = process.env.CACHE_FILE_ID || '1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP';
const DRIVE_API_KEY = process.env.DRIVE_API_KEY || '';

let sheetsClientPromise = null;

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

app.get('/', (_req, res) => {
  res.send('Sonora backend (Cloud Run) no ar. Endpoints: /validar?id=XXX e /cache');
});

app.listen(PORT, () => {
  console.log(`Sonora backend (Cloud Run) rodando na porta ${PORT}`);
});
