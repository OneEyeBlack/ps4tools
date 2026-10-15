# PS4 Save Agent

Payload ELF para rodar no PS4 com GoldHEN e expor uma API HTTP local para o
PS4PKGDownloader sincronizar saves descriptografados sem abrir o Apollo
manualmente.

Este diretorio contem a base do protocolo que o programa Delphi ja chama.
O binario final esperado pelo programa e:

```text
payloads/ps4-save-agent.elf
```

No PS4, o arquivo e instalado/validado em:

```text
/data/payloads/ps4-save-agent.elf
```

Esse e o diretorio que o GoldHEN mostra em Utilities > Payloader.

## API esperada pelo Delphi

```text
GET  /api/ping
POST /api/sync_decrypted?source_user=<uid>&dest_user=<uid>&title=<CUSA>&save=<SaveName>
GET  /api/export_decrypted?user=<uid>&title=<CUSA>&save=<SaveName>
POST /api/import_decrypted?user=<uid>&title=<CUSA>&save=<SaveName>
```

`/api/sync_decrypted` deve:

1. Montar/descriptografar o save do usuario origem.
2. Criar ou montar o save equivalente para o usuario destino.
3. Copiar o conteudo descriptografado do mount origem para o mount destino.
4. Ajustar `sce_sys/param.sfo` para o usuario destino.
5. Desmontar destino e origem para o Orbis recriptografar o PFS.

`/api/export_decrypted` deve:

1. Localizar `/user/home/<uid>/savedata/<CUSA>/sdimg_<SaveName>`.
2. Localizar `/user/home/<uid>/savedata/<CUSA>/<SaveName>.bin`.
3. Montar o save com as funcoes Orbis/pfsmgr.
4. Compactar o conteudo montado descriptografado.
5. Responder um ZIP para o PC.

`/api/import_decrypted` deve:

1. Receber o ZIP enviado pelo PC.
2. Criar ou abrir um save para o usuario destino.
3. Copiar os arquivos descriptografados para dentro do mount.
4. Ajustar `sce_sys/param.sfo` para o account/user local.
5. Desmontar para o PS4 recriptografar o PFS.

## Observacao importante

Este payload precisa ser completado/compilado com um SDK de PS4 compativel com
GoldHEN. O PC/Delphi nao consegue substituir `pfsmgr`, `sbl_srv` e as funcoes
de montagem do Orbis.
