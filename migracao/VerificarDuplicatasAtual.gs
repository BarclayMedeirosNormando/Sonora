// ============================================================
// Script novo e independente dos outros — não redeclara nenhuma
// const/var de nível de arquivo que já exista no projeto (todo mundo
// aqui é variável local, dentro da função, pra não repetir o erro do
// "Identifier has already been declared").
//
// Duas funções, rode uma de cada vez pelo editor do Apps Script:
//
// 1) verificarLimpezaAntiga()
//    Percorre a aba "VerificacaoDuplicatas" (os 114 pares já analisados
//    antes) e confere, pasta por pasta, se o lado que a Recomendacao
//    mandou trashar já está de fato na lixeira do Drive. Escreve o
//    resultado numa coluna nova "StatusLimpeza" na mesma aba.
//
// 2) verificarDuplicatasNovas()
//    Lê a aba "Fila" inteira (direto na planilha, sem o limite de leitura
//    que uma ferramenta externa teria) e procura OrigemID que aparecem em
//    mais de uma linha — isso indicaria que o bug de corrida (duas
//    execuções pegando a mesma linha ao mesmo tempo) voltou a acontecer
//    depois da correção do LockService. Também lista as subpastas de 1º
//    nível da pasta destino e agrupa por nome, pra achar pastas
//    duplicadas por nome mesmo que a Fila não acuse nada. Escreve os dois
//    relatórios em abas novas: "DuplicatasFilaAtual" e
//    "PastasDestinoNomeRepetido".
//
// Como usar:
//   1. Cole este arquivo no MESMO projeto Apps Script "Sonora" (o que já
//      tem processarLote e a propriedade PLANILHA_ID salva).
//   2. Rode verificarLimpezaAntiga() primeiro (mais rápida, ~114 linhas).
//   3. Rode verificarDuplicatasNovas() depois.
//   4. Os resultados ficam na planilha Log_Copia_Musicas.
// ============================================================

function verificarLimpezaAntiga() {
  const props = PropertiesService.getScriptProperties();
  const planilhaId = props.getProperty('PLANILHA_ID');
  if (!planilhaId) {
    Logger.log('PLANILHA_ID não encontrado — rode isso no mesmo projeto do iniciarCopia().');
    return;
  }
  const planilha = SpreadsheetApp.openById(planilhaId);

  const aba = planilha.getSheetByName('VerificacaoDuplicatas');
  if (!aba) {
    Logger.log('Aba "VerificacaoDuplicatas" não encontrada.');
    return;
  }

  const dados = aba.getDataRange().getValues();
  const cabecalho = dados[0]; // OrigemID, DestinoA, ContagemA, DestinoB, ContagemB, Recomendacao
  const idxDestinoA = cabecalho.indexOf('DestinoA');
  const idxDestinoB = cabecalho.indexOf('DestinoB');
  const idxRecomendacao = cabecalho.indexOf('Recomendacao');

  let idxStatus = cabecalho.indexOf('StatusLimpeza');
  if (idxStatus === -1) {
    idxStatus = cabecalho.length;
    aba.getRange(1, idxStatus + 1).setValue('StatusLimpeza');
  }

  const resultados = [];
  for (let i = 1; i < dados.length; i++) {
    const linha = dados[i];
    const destinoA = linha[idxDestinoA];
    const destinoB = linha[idxDestinoB];
    const recomendacao = String(linha[idxRecomendacao] || '');

    if (!destinoA && !destinoB) {
      resultados.push(['']);
      continue;
    }

    let idParaTrashar = null;
    if (recomendacao.indexOf('trashar A') !== -1) {
      idParaTrashar = destinoA;
    } else if (recomendacao.indexOf('trashar B') !== -1) {
      idParaTrashar = destinoB;
    } else {
      resultados.push(['SEM RECOMENDACAO AUTOMATICA']);
      continue;
    }

    let status;
    try {
      const pasta = DriveApp.getFolderById(idParaTrashar);
      status = pasta.isTrashed() ? 'OK - trashado' : 'PENDENTE - ainda ativo';
    } catch (e) {
      status = 'ERRO - pasta não encontrada (' + e.message + ')';
    }
    resultados.push([status]);

    if (i % 50 === 0) Utilities.sleep(200);
  }

  aba.getRange(2, idxStatus + 1, resultados.length, 1).setValues(resultados);
  Logger.log('verificarLimpezaAntiga concluído: ' + resultados.length + ' linhas.');
}

function verificarDuplicatasNovas() {
  const props = PropertiesService.getScriptProperties();
  const planilhaId = props.getProperty('PLANILHA_ID');
  if (!planilhaId) {
    Logger.log('PLANILHA_ID não encontrado — rode isso no mesmo projeto do iniciarCopia().');
    return;
  }
  const planilha = SpreadsheetApp.openById(planilhaId);

  const abaFila = planilha.getSheetByName('Fila');
  if (!abaFila) {
    Logger.log('Aba "Fila" não encontrada.');
    return;
  }

  const dados = abaFila.getDataRange().getValues();
  const cabecalho = dados[0];
  const idxOrigem = cabecalho.indexOf('OrigemID');
  const idxDestino = cabecalho.indexOf('DestinoID');

  const contagemOrigem = {}; // OrigemID -> [{linha, destino}]
  for (let i = 1; i < dados.length; i++) {
    const origem = dados[i][idxOrigem];
    if (!origem) continue;
    if (!contagemOrigem[origem]) contagemOrigem[origem] = [];
    contagemOrigem[origem].push({ linha: i + 1, destino: dados[i][idxDestino] });
  }

  const origensComDuplicata = Object.keys(contagemOrigem).filter(
    function (k) { return contagemOrigem[k].length > 1; }
  );

  let abaRelatorio1 = planilha.getSheetByName('DuplicatasFilaAtual');
  if (!abaRelatorio1) abaRelatorio1 = planilha.insertSheet('DuplicatasFilaAtual');
  abaRelatorio1.clear();
  abaRelatorio1.appendRow(['OrigemID', 'LinhaNaFila', 'DestinoID']);
  origensComDuplicata.forEach(function (origem) {
    contagemOrigem[origem].forEach(function (ocorrencia) {
      abaRelatorio1.appendRow([origem, ocorrencia.linha, ocorrencia.destino]);
    });
  });
  Logger.log(
    'Linhas lidas na Fila: ' + (dados.length - 1) +
    ' | OrigemID duplicados: ' + origensComDuplicata.length
  );

  const idPastaDestino = '1p4U1_MANHrzEpoZu5iUAQn_Ng_phJuV7';
  const pastasPorNome = {};
  const iterador = DriveApp.getFolderById(idPastaDestino).getFolders();
  let total = 0;
  while (iterador.hasNext()) {
    const pasta = iterador.next();
    if (pasta.isTrashed()) continue;
    const nome = pasta.getName();
    if (!pastasPorNome[nome]) pastasPorNome[nome] = [];
    pastasPorNome[nome].push(pasta.getId());
    total++;
  }

  const nomesComDuplicata = Object.keys(pastasPorNome).filter(
    function (n) { return pastasPorNome[n].length > 1; }
  );

  let abaRelatorio2 = planilha.getSheetByName('PastasDestinoNomeRepetido');
  if (!abaRelatorio2) abaRelatorio2 = planilha.insertSheet('PastasDestinoNomeRepetido');
  abaRelatorio2.clear();
  abaRelatorio2.appendRow(['NomeDaPasta', 'PastaID']);
  nomesComDuplicata.forEach(function (nome) {
    pastasPorNome[nome].forEach(function (id) {
      abaRelatorio2.appendRow([nome, id]);
    });
  });

  Logger.log(
    'Pastas de 1o nivel no destino (ativas): ' + total +
    ' | nomes repetidos: ' + nomesComDuplicata.length
  );
}
