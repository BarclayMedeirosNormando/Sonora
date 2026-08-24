// ============================================================
// Sonora - Backend (Web App do Apps Script)
// Endpoints:
//   ?action=validar&id=XXX     -> checa liberação do App_ID
//   ?action=navegar&pasta=XXX  -> lista subpastas e faixas de uma pasta do Drive
// ============================================================

var PLANILHA_ACESSO_ID = '1UyH7VLTSU3pIRXH1DOiPSBB1vavy_qyRo65y07DEyiE'; // Log_Acesso_Sonora

// Quantos níveis abaixo de cada subpasta a busca de capa desce: 0 = só a
// própria subpasta, 1 = subpasta + subpastas dela, 2 = + a "sub da sub".
// Voltou pra 0 — com 2 a navegação ficou muito lenta (buscar recursivo em
// tempo real pra cada subpasta mostrada não escala bem com esse volume de
// pastas). Ver comentário mais abaixo sobre a alternativa com cache.
var PROFUNDIDADE_MAX_CAPA = 0;

function doGet(e) {
  var action = e.parameter.action;

  if (action === 'validar') {
    return validarId(e.parameter.id);
  }
  if (action === 'navegar') {
    return navegarPasta(e.parameter.pasta);
  }

  return jsonResponse({ erro: 'Ação inválida. Use action=validar ou action=navegar.' });
}

/**
 * Checa se o App_ID está com Status "Liberado" na planilha Log_Acesso_Sonora.
 * Se o ID ainda não existir na planilha, cadastra automaticamente como
 * "Bloqueado" (fica visível pro Barclay liberar manualmente depois).
 */
function validarId(appId) {
  if (!appId) {
    return jsonResponse({ erro: 'Parâmetro id ausente.' });
  }

  var planilha = SpreadsheetApp.openById(PLANILHA_ACESSO_ID);
  var aba = planilha.getSheets()[0];
  var dados = aba.getDataRange().getValues();

  for (var i = 1; i < dados.length; i++) { // linha 0 = cabeçalho
    if (dados[i][0] === appId) {
      var status = String(dados[i][1] || '').trim().toLowerCase();
      return jsonResponse({ liberado: status === 'liberado' });
    }
  }

  // ID novo: registra como Bloqueado para liberação manual.
  aba.appendRow([appId, 'Bloqueado', '', new Date()]);
  return jsonResponse({ liberado: false });
}

/**
 * Lista o conteúdo direto de uma pasta do Drive: subpastas e arquivos MP3
 * (só um nível — o app chama de novo pra cada subpasta que o usuário abrir,
 * já que a profundidade real varia de pasta pra pasta).
 */
function navegarPasta(pastaId) {
  if (!pastaId) {
    return jsonResponse({ erro: 'Parâmetro pasta ausente.' });
  }

  var pasta = DriveApp.getFolderById(pastaId);

  var subpastas = pasta.getFolders();
  var pastasResultado = [];
  while (subpastas.hasNext()) {
    var sub = subpastas.next();
    pastasResultado.push({
      id: sub.getId(),
      name: sub.getName(),
      capaId: encontrarCapa(sub, PROFUNDIDADE_MAX_CAPA)
    });
  }
  pastasResultado.sort(function (a, b) {
    return a.name.localeCompare(b.name, 'pt-BR', { numeric: true });
  });

  var arquivos = pasta.getFiles();
  var faixasResultado = [];
  while (arquivos.hasNext()) {
    var arquivo = arquivos.next();
    var nome = arquivo.getName();
    if (nome.toLowerCase().endsWith('.mp3') || arquivo.getMimeType() === 'audio/mpeg') {
      faixasResultado.push({ id: arquivo.getId(), name: nome, size: arquivo.getSize() });
    }
  }
  faixasResultado.sort(function (a, b) {
    return a.name.localeCompare(b.name, 'pt-BR', { numeric: true });
  });

  return jsonResponse({ pastas: pastasResultado, faixas: faixasResultado });
}

/**
 * Procura uma imagem (capa) dentro da pasta, descendo até
 * PROFUNDIDADE_MAX_CAPA níveis em subpastas (pasta > subpasta > sub da
 * sub...). Para assim que acha a primeira imagem, sem vasculhar o resto —
 * isso limita o custo mesmo quando não acha nada (o pior caso é limitado
 * pela profundidade máxima, não pela árvore inteira, que foi o problema de
 * lentidão do filtro que tentamos antes no navegarPasta).
 */
function encontrarCapa(pastaObj, profundidadeRestante) {
  var arquivos = pastaObj.getFiles();
  while (arquivos.hasNext()) {
    var arquivo = arquivos.next();
    if (arquivo.getMimeType().indexOf('image/') === 0) {
      return arquivo.getId();
    }
  }

  if (profundidadeRestante <= 0) return null;

  var subpastas = pastaObj.getFolders();
  while (subpastas.hasNext()) {
    var achada = encontrarCapa(subpastas.next(), profundidadeRestante - 1);
    if (achada) return achada;
  }

  return null;
}

function jsonResponse(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
