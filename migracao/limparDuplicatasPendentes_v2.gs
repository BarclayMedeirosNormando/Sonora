// Versão resumível: processa em lotes com tempo de segurança (a operação
// toda — 526 remoções de linha + 526 pastas pra lixeira — passa do limite
// de 6 min do Apps Script numa chamada só). Rodar "Executar" quantas vezes
// forem necessárias: é seguro rodar de novo, ela pula o que já foi feito.
function limparDuplicatasPendentes() {
  const inicio = new Date().getTime();
  const LIMITE_MS = 4.5 * 60 * 1000; // 4.5 min de margem

  const props = PropertiesService.getScriptProperties();
  const planilhaId = props.getProperty('PLANILHA_ID');
  if (!planilhaId) { Logger.log('PLANILHA_ID não encontrado — rode isso no mesmo projeto do iniciarCopia().'); return; }

  const fila = SpreadsheetApp.openById(planilhaId).getSheetByName('Fila');
  const destinosParaTrashar = new Set(PARES_PARA_LIMPAR.map(function (p) { return p.trashar; }));

  // 1) Remove as linhas que ainda existem na fila (rodar de novo é seguro:
  // linhas já removidas simplesmente não aparecem mais nessa busca)
  const dados = fila.getDataRange().getValues();
  const linhasParaRemover = [];
  for (let i = 1; i < dados.length; i++) {
    if (destinosParaTrashar.has(dados[i][1])) {
      linhasParaRemover.push(i + 1); // linha real na planilha
    }
  }
  linhasParaRemover.sort(function (a, b) { return b - a; }); // de baixo pra cima

  let linhasRemovidas = 0;
  for (let i = 0; i < linhasParaRemover.length; i++) {
    fila.deleteRow(linhasParaRemover[i]);
    linhasRemovidas++;
    if (new Date().getTime() - inicio > LIMITE_MS) {
      Logger.log('⏸️ Tempo esgotado removendo linhas da fila (' + linhasRemovidas + '/' + linhasParaRemover.length + ' nessa passada). Clique em Executar de novo pra continuar.');
      return;
    }
  }
  if (linhasParaRemover.length > 0) {
    Logger.log('✅ Linhas removidas da fila nessa passada: ' + linhasRemovidas + '/' + linhasParaRemover.length);
  } else {
    Logger.log('✅ Nenhuma linha duplicada restante na fila (já foi limpo antes).');
  }

  // 2) Move as pastas duplicadas pra lixeira (pula as que já estão trashed)
  const listaDestinos = Array.from(destinosParaTrashar);
  let trashadasAgora = 0, jaEstavam = 0, erros = 0;
  for (let i = 0; i < listaDestinos.length; i++) {
    try {
      const pasta = DriveApp.getFolderById(listaDestinos[i]);
      if (pasta.isTrashed()) {
        jaEstavam++;
      } else {
        pasta.setTrashed(true);
        trashadasAgora++;
      }
    } catch (e) {
      erros++;
    }

    if (new Date().getTime() - inicio > LIMITE_MS) {
      Logger.log('⏸️ Tempo esgotado movendo pastas pra lixeira (processadas ' + (i + 1) + '/' + listaDestinos.length + ' nessa passada, ' + trashadasAgora + ' novas, ' + jaEstavam + ' já estavam). Clique em Executar de novo pra continuar.');
      return;
    }
  }

  Logger.log('🎉 CONCLUÍDO! Pastas movidas pra lixeira nessa passada: ' + trashadasAgora +
             '. Já estavam na lixeira: ' + jaEstavam + '. Erros: ' + erros + '.');
}
