// ============================================================
// Gera um cache da biblioteca inteira como um arquivo JSON no Drive, fora
// da pasta "Sonora" (assim ele nunca aparece na navegação do app). Tem
// duas partes dentro do mesmo arquivo:
//
//   - albuns: pastas com mp3 direto (usado pela Home e pela Busca)
//   - arvore: TODA pasta e TODO arquivo mp3 da biblioteca, cada um sabendo
//     quem é a pasta-pai (paiId). É usado pela navegação de pastas do app
//     (FolderScreen), no lugar do endpoint action=navegar do Apps Script —
//     assim a navegação normal não passa mais pelo Web App e não esbarra
//     no limite de 30 execuções simultâneas do script com muita gente
//     usando o app ao mesmo tempo. Só a validação de acesso continua
//     passando pelo Apps Script.
//
// O app Flutter lê esse arquivo direto via Drive API (mesma URL usada pra
// tocar faixa/mostrar capa), sem passar pelo backend.
//
// Script novo e independente — não redeclara nada de nível de arquivo que
// já exista em outro .gs deste mesmo projeto.
//
// Como usar:
//   1. Cole este arquivo no projeto Apps Script "Sonora", substituindo a
//      versão anterior do CacheBiblioteca.gs.
//   2. Rode a função atualizarCacheBiblioteca().
//   3. Veja o log (Ver > Registros / Executar > Registros de execução):
//      mostra quantos álbuns e quantos nós de árvore achou, e o ID do
//      arquivo de cache gerado.
//   4. Se essa for a primeira vez rodando esse script, manda esse ID —
//      é usado pra configurar o app. Se já tinha rodado antes, o ID é
//      sempre o mesmo (reaproveita o mesmo arquivo, sobrescrevendo o
//      conteúdo) — não precisa mandar de novo nem gerar novo APK.
//   5. Rode de novo sempre que quiser atualizar (depois de baixar mais
//      música, por exemplo).
// ============================================================

function atualizarCacheBiblioteca() {
  var idPastaBiblioteca = '14D3JK1VVyL3nyDNroK0s2vSLMC0H16I6'; // pasta "Sonora"
  var idPastaOndeSalvarCache = '1G8Muuustel-YTW3kvACoV9YuXb6xL0A-'; // pasta "Musicas" (pai de Sonora)
  var nomeArquivoCache = 'sonora_cache_biblioteca.json';
  var tempoLimiteMs = 5 * 60 * 1000; // margem de segurança abaixo do limite de 6 min do Apps Script
  var inicio = new Date().getTime();

  var albuns = [];
  var arvore = [];
  var estourouTempo = false;

  function dentroDoTempo() {
    return (new Date().getTime() - inicio) < tempoLimiteMs;
  }

  // Percorre uma pasta: registra na árvore ela mesma (com o ID da
  // pasta-pai, exceto a raiz da biblioteca, que o app já conhece pelo ID
  // fixo em constants.dart e por isso não precisa aparecer como "filha"
  // de ninguém) e todo mp3 direto nela. Também decide se ela é um
  // "álbum" (tem mp3 direto), pra continuar alimentando a lista usada
  // pela Home/Busca do jeito que já funcionava.
  function percorrer(pastaObj, paiId, profundidade) {
    if (!dentroDoTempo()) { estourouTempo = true; return; }
    if (profundidade > 6) return; // trava de segurança

    var pastaId = pastaObj.getId();
    var arquivos = pastaObj.getFiles();
    var temMp3 = false;
    var capaId = null;

    while (arquivos.hasNext()) {
      var arquivo = arquivos.next();
      var nome = arquivo.getName();
      var mime = arquivo.getMimeType();
      var ehMp3 = nome.toLowerCase().indexOf('.mp3', nome.length - 4) !== -1 || mime === 'audio/mpeg';

      if (ehMp3) {
        temMp3 = true;
        arvore.push({
          tipo: 'faixa',
          id: arquivo.getId(),
          name: nome,
          paiId: pastaId,
          size: arquivo.getSize()
        });
      } else if (capaId === null && mime.indexOf('image/') === 0) {
        capaId = arquivo.getId();
      }
    }

    if (paiId !== null) {
      arvore.push({
        tipo: 'pasta',
        id: pastaId,
        name: pastaObj.getName(),
        paiId: paiId,
        capaId: capaId,
        criadoEm: pastaObj.getDateCreated().toISOString()
      });
    }

    if (temMp3) {
      albuns.push({
        id: pastaId,
        name: pastaObj.getName(),
        capaId: capaId,
        criadoEm: pastaObj.getDateCreated().toISOString()
      });
    }

    var subpastas = pastaObj.getFolders();
    while (subpastas.hasNext()) {
      if (!dentroDoTempo()) { estourouTempo = true; return; }
      percorrer(subpastas.next(), pastaId, profundidade + 1);
    }
  }

  percorrer(DriveApp.getFolderById(idPastaBiblioteca), null, 0);

  albuns.sort(function (a, b) {
    return new Date(b.criadoEm).getTime() - new Date(a.criadoEm).getTime();
  });

  var conteudo = JSON.stringify({
    geradoEm: new Date().toISOString(),
    estourouTempo: estourouTempo,
    totalAlbuns: albuns.length,
    albuns: albuns,
    arvore: arvore
  });

  var pastaDestino = DriveApp.getFolderById(idPastaOndeSalvarCache);
  var existentes = pastaDestino.getFilesByName(nomeArquivoCache);
  var arquivoCache;
  if (existentes.hasNext()) {
    arquivoCache = existentes.next();
    arquivoCache.setContent(conteudo);
  } else {
    arquivoCache = pastaDestino.createFile(nomeArquivoCache, conteudo, MimeType.PLAIN_TEXT);
  }
  // Sempre garante o compartilhamento público de leitura, mesmo se o
  // arquivo já existia (idempotente, custa pouco rodar de novo).
  arquivoCache.setSharing(DriveApp.Access.ANYONE, DriveApp.Permission.VIEW);

  Logger.log(
    'Cache atualizado: ' + albuns.length + ' álbuns, ' + arvore.length + ' nós na árvore de pastas' +
    (estourouTempo ? ' — PAROU por tempo (6 min), rode de novo se a lista parecer incompleta' : '')
  );
  Logger.log('ID do arquivo de cache: ' + arquivoCache.getId());
}
