// ===== PASSO 2: roda sozinho via gatilho, processando aos poucos =====
function processarLote() {
  // Trava de concorrência: o gatilho de 5 em 5 min pode disparar uma nova
  // execução antes da anterior terminar (Apps Script não impede isso
  // sozinho). Sem essa trava, duas execuções pegam a mesma linha "Pendente"
  // ou "Em Progresso" ao mesmo tempo e cada uma cria sua própria cópia da
  // pasta — foi isso que causou as pastas duplicadas.
  const lock = LockService.getScriptLock();
  const conseguiuLock = lock.tryLock(5000); // espera até 5s por um lock livre
  if (!conseguiuLock) {
    Logger.log("⏭️ Já existe uma execução de processarLote em andamento — pulando esta chamada pra não duplicar. O próximo gatilho tenta de novo.");
    return;
  }

  try {
    const props = PropertiesService.getScriptProperties();

    // Se a última execução detectou cota estourada, avisa e não tenta de novo agora
    const cotaEstourada = props.getProperty("COTA_ESTOURADA");
    if (cotaEstourada) {
      const agora = new Date();
      Logger.log("⏸️ PAUSADO por cota excedida desde " + cotaEstourada + ". " +
                 "A cota do Drive reseta por volta da meia-noite (horário do Pacífico / ~4-5h da manhã em Brasília). " +
                 "O script vai tentar de novo automaticamente no próximo ciclo do gatilho, e remove essa pausa sozinho se der certo.");
      // tenta mesmo assim a cada execução — se der certo, a pausa é removida logo abaixo
    }

    const inicio = new Date().getTime();
    const planilhaId = props.getProperty("PLANILHA_ID");
    if (!planilhaId) { Logger.log("Rode iniciarCopia() primeiro."); return; }

    const fila = SpreadsheetApp.openById(planilhaId).getSheetByName("Fila");

    while (new Date().getTime() - inicio < TEMPO_LIMITE_MS) {
      const linha = encontrarProximaPendente(fila);
      if (linha === -1) {
        finalizarTudo();
        return;
      }

      const valoresLinha = fila.getRange(linha, 1, 1, 5).getValues()[0];
      const origemId = valoresLinha[0];
      const destinoId = valoresLinha[1];
      const pageTokenSalvo = valoresLinha[3];

      fila.getRange(linha, 3).setValue("Em Progresso");

      let pageToken = pageTokenSalvo || null;
      let totalCopiado = fila.getRange(linha, 5).getValue() || 0;

      do {
        let resposta;
        try {
          resposta = Drive.Files.list({
            q: `'${origemId}' in parents and trashed = false`,
            fields: "nextPageToken, files(id, name, mimeType)",
            pageSize: 100,
            pageToken: pageToken
          });
        } catch (e) {
          if (registrarSeErroDeCota(e, props)) return; // pausa tudo, progresso já está salvo
          Logger.log("Erro ao listar pasta " + origemId + ": " + e.message);
          return; // erro não-cota na listagem: pausa esta execução, tenta de novo no próximo gatilho
        }

        const arquivos = resposta.files || [];
        for (let i = 0; i < arquivos.length; i++) {
          const item = arquivos[i];
          if (item.mimeType === "application/vnd.google-apps.folder") continue;
          try {
            Drive.Files.copy({ name: item.name, parents: [destinoId] }, item.id);
            totalCopiado++;
          } catch (e) {
            if (registrarSeErroDeCota(e, props)) {
              fila.getRange(linha, 5).setValue(totalCopiado); // salva progresso antes de sair
              return;
            }
            Logger.log("  ⚠️ Erro ao copiar '" + item.name + "': " + e.message);
          }
        }

        // Se chegou até aqui sem erro de cota, garante que a pausa está removida
        if (props.getProperty("COTA_ESTOURADA")) {
          props.deleteProperty("COTA_ESTOURADA");
          Logger.log("✅ Cota normalizada, retomando cópia normalmente.");
        }

        pageToken = resposta.nextPageToken || null;
        fila.getRange(linha, 4).setValue(pageToken || "");
        fila.getRange(linha, 5).setValue(totalCopiado);

        if (new Date().getTime() - inicio >= TEMPO_LIMITE_MS) return;

      } while (pageToken);

      // Terminou os arquivos desta pasta — enfileira as subpastas
      let subResposta;
      try {
        subResposta = Drive.Files.list({
          q: `'${origemId}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
          fields: "files(id, name)"
        });
      } catch (e) {
        if (registrarSeErroDeCota(e, props)) return;
        Logger.log("Erro ao listar subpastas de " + origemId + ": " + e.message);
        return;
      }

      (subResposta.files || []).forEach(function (sub) {
        const novaPastaDestino = DriveApp.getFolderById(destinoId).createFolder(sub.name);
        fila.appendRow([sub.id, novaPastaDestino.getId(), "Pendente", "", 0]);
      });

      fila.getRange(linha, 3).setValue("Concluído");
    }
  } finally {
    lock.releaseLock();
  }
}
