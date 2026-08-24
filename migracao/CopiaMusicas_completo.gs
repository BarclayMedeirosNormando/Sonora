// ===== CONFIGURAÇÃO =====
const ID_PASTA_ORIGEM = "1htduKAvqSeyBs-mldsdqOBZ6QKrEykf8";
const ID_PASTA_DESTINO = "1p4U1_MANHrzEpoZu5iUAQn_Ng_phJuV7"; // sua pasta já existente
// Margem de segurança por execução. Ficava em 5 min (empatado com o
// intervalo do gatilho), e como cada execução sempre gasta um pouco mais de
// tempo escrevendo na planilha/listando subpastas depois de copiar, ela
// estourava pra ~5,5-6 min — isso fazia o PRÓXIMO gatilho (5 em 5 min)
// disparar em cima da execução anterior ainda rodando, e a trava fazia essa
// segunda execução desistir sem copiar nada (metade dos ciclos jogados
// fora). Baixando pra 4 min sobra margem suficiente pra sempre terminar
// antes do próximo gatilho, então nenhum ciclo é mais desperdiçado.
const TEMPO_LIMITE_MS = 4 * 60 * 1000;

// Palavras-chave que indicam erro de cota (não erro de arquivo específico)
const PALAVRAS_COTA = ["rate limit", "quota", "userratelimitexceeded", "dailylimitexceeded", "limit exceeded"];

// ===== PASSO 1: rodar UMA VEZ para iniciar =====
function iniciarCopia() {
  const props = PropertiesService.getScriptProperties();
  if (props.getProperty("PLANILHA_ID")) {
    Logger.log("Já iniciado. Rode 'processarLote' ou aguarde o gatilho.");
    return;
  }

  const planilha = SpreadsheetApp.create("Log_Copia_Musicas");
  const fila = planilha.getActiveSheet();
  fila.setName("Fila");
  fila.appendRow(["OrigemID", "DestinoID", "Status", "PageToken", "ArquivosCopiados"]);
  fila.appendRow([ID_PASTA_ORIGEM, ID_PASTA_DESTINO, "Pendente", "", 0]);

  // move a planilha para dentro da pasta destino
  const arquivoPlanilha = DriveApp.getFileById(planilha.getId());
  const pastaDestino = DriveApp.getFolderById(ID_PASTA_DESTINO);
  pastaDestino.addFile(arquivoPlanilha);
  DriveApp.getRootFolder().removeFile(arquivoPlanilha);

  props.setProperty("PLANILHA_ID", planilha.getId());
  props.deleteProperty("COTA_ESTOURADA"); // garante estado limpo

  ScriptApp.newTrigger("processarLote")
    .timeBased()
    .everyMinutes(5)
    .create();

  Logger.log("✅ Iniciado! Planilha de controle: " + planilha.getUrl());
  processarLote();
}

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
      let totalCopiado = valoresLinha[4] || 0;

      fila.getRange(linha, 3).setValue("Em Progresso");

      // Idempotência: se essa linha já tinha progresso salvo (retomando de
      // uma execução anterior que foi interrompida no meio), monta a lista
      // do que já existe no destino pra não copiar de novo. Isso cobre tanto
      // o caso de ter parado no meio de uma página de até 100 arquivos,
      // quanto o caso de ter terminado todos os arquivos mas sido
      // interrompida antes de marcar a linha como "Concluído" (nesse caso o
      // PageToken salvo fica vazio, igual uma linha nova — sem essa checagem
      // ela recopiaria a pasta inteira de novo).
      const precisaChecarExistentes = !!pageTokenSalvo || totalCopiado > 0;
      let nomesExistentesDestino = null;
      if (precisaChecarExistentes) {
        nomesExistentesDestino = new Set();
        const existentes = DriveApp.getFolderById(destinoId).getFiles();
        while (existentes.hasNext()) {
          nomesExistentesDestino.add(existentes.next().getName());
        }
      }

      let pageToken = pageTokenSalvo || null;

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

          if (nomesExistentesDestino && nomesExistentesDestino.has(item.name)) {
            continue; // já copiado numa passada anterior, pula
          }

          try {
            Drive.Files.copy({ name: item.name, parents: [destinoId] }, item.id);
            if (nomesExistentesDestino) nomesExistentesDestino.add(item.name);
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

// Detecta se o erro é de cota. Se for, loga aviso claro e marca estado de pausa.
// Retorna true se era erro de cota (chamador deve parar), false caso contrário.
function registrarSeErroDeCota(e, props) {
  const msg = (e.message || "").toLowerCase();
  const eCota = PALAVRAS_COTA.some(function (palavra) { return msg.indexOf(palavra) !== -1; });

  if (eCota) {
    const agora = new Date().toString();
    props.setProperty("COTA_ESTOURADA", agora);
    Logger.log("🛑 COTA DA API DO DRIVE EXCEDIDA às " + agora + ". " +
               "Detalhe do erro: " + e.message + ". " +
               "O script vai pausar aqui com o progresso salvo e tentar de novo automaticamente " +
               "no próximo ciclo do gatilho (5 min). A cota reseta por volta da meia-noite (Pacífico).");
    return true;
  }
  return false;
}

function encontrarProximaPendente(fila) {
  const dados = fila.getDataRange().getValues();
  for (let i = 1; i < dados.length; i++) {
    if (dados[i][2] === "Pendente" || dados[i][2] === "Em Progresso") return i + 1;
  }
  return -1;
}

function finalizarTudo() {
  const triggers = ScriptApp.getProjectTriggers();
  triggers.forEach(function (t) {
    if (t.getHandlerFunction() === "processarLote") ScriptApp.deleteTrigger(t);
  });
  PropertiesService.getScriptProperties().deleteProperty("COTA_ESTOURADA");
  Logger.log("🎉 CÓPIA CONCLUÍDA — todos os arquivos processados.");
}
