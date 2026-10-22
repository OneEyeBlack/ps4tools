unit UnitTropheus;

interface

uses
  System.Classes, System.SysUtils, System.Types;

type
  TPS4TrophyUser = record
    UserID: string;
    HasTrophyDb: Boolean;
  end;

  TPS4TrophyTitle = record
    UserID: string;
    TrophyTitleID: string;
    Title: string;
    TrophyNum: Integer;
    UnlockedNum: Integer;
  end;

  TPS4TrophyLogEvent = procedure(const AMsg: string) of object;
  TPS4TrophyProgressEvent = procedure(const AMsg: string;
    APosition, AMax: Int64) of object;
  TPS4TrophyExistingMode = (temMerge, temReplace);

function ListPS4TrophyUsers(const AHost: string; APort: Word): TArray<TPS4TrophyUser>;
function ListPS4Trophies(const AHost: string; APort: Word): TArray<TPS4TrophyTitle>;
function ListPS4TrophiesForUser(const AHost: string; APort: Word;
  const AUserID: string): TArray<TPS4TrophyTitle>;
function ListPS4TrophiesFromBackup(const ABackupDir, AUserID: string): TArray<TPS4TrophyTitle>;
procedure SyncPS4Trophies(const ALeftHost, ADestHost: string; APort: Word;
  const ATrophies: TArray<TPS4TrophyTitle>; AExistingMode: TPS4TrophyExistingMode;
  ALog: TPS4TrophyLogEvent);
procedure SyncPS4TrophiesForUsers(const ALeftHost, ADestHost: string; APort: Word;
  const ALeftUserID, ADestUserID: string;
  const ATrophies: TArray<TPS4TrophyTitle>; AExistingMode: TPS4TrophyExistingMode;
  ALog: TPS4TrophyLogEvent);
procedure DeletePS4Trophies(const AHost: string; APort: Word;
  const ATrophies: TArray<TPS4TrophyTitle>; ALog: TPS4TrophyLogEvent);
procedure DeletePS4TrophiesForUser(const AHost: string; APort: Word;
  const AUserID: string; const ATrophies: TArray<TPS4TrophyTitle>;
  ALog: TPS4TrophyLogEvent);
procedure SortPS4TrophiesAlphabetically(const AHost: string; APort: Word;
  const AUserID: string; ALog: TPS4TrophyLogEvent);
procedure BackupPS4TrophyState(const AHost: string; APort: Word;
  const AUserID, ADestDir: string; ALog: TPS4TrophyLogEvent);
procedure RestorePS4TrophyState(const AHost: string; APort: Word;
  const AUserID, ALeftDir: string; ALog: TPS4TrophyLogEvent);
procedure RestorePS4TrophyTitles(const AHost: string; APort: Word;
  const AUserID, ABackupDir: string;
  const ATrophies: TArray<TPS4TrophyTitle>; AExistingMode: TPS4TrophyExistingMode;
  ALog: TPS4TrophyLogEvent; AProgress: TPS4TrophyProgressEvent);

implementation

uses
  System.IOUtils, System.Generics.Collections, System.Sqlite,
  Winapi.Windows,
  IdFTP, IdFTPCommon, IdFTPList;

const
  PS4_FTP_USER = 'anonymous';
  PS4_FTP_PASS = 'anonymous@';
  MAX_SQLITE_CELLS = MaxInt div SizeOf(MarshaledAString) - 1;

type
  TSQLiteCellArray = array[0..MAX_SQLITE_CELLS] of MarshaledAString;
  PSQLiteCellArray = ^TSQLiteCellArray;
  TSQLiteExecUtf8 = function(DbConnection: sqlite3; sql: MarshaledAString;
    Callback: TSqlite3ExecCallback; CallbackArg: Pointer;
    ErrMsg: PMarshaledAString): Integer; cdecl;

var
  GSQLiteExecUtf8: TSQLiteExecUtf8;

function SQLiteExecUtf8(DbConnection: sqlite3; sql: MarshaledAString;
  Callback: TSqlite3ExecCallback; CallbackArg: Pointer;
  ErrMsg: PMarshaledAString): Integer;
var
  ModuleHandle: HMODULE;
begin
  if not Assigned(GSQLiteExecUtf8) then
  begin
    ModuleHandle := GetModuleHandle(sqlite3dll);
    if ModuleHandle = 0 then
      raise Exception.Create('sqlite3.dll nao esta carregada.');
    GSQLiteExecUtf8 := TSQLiteExecUtf8(GetProcAddress(ModuleHandle, 'sqlite3_exec'));
    if not Assigned(GSQLiteExecUtf8) then
      raise Exception.Create('Funcao sqlite3_exec nao encontrada em sqlite3.dll.');
  end;
  Result := GSQLiteExecUtf8(DbConnection, sql, Callback, CallbackArg, ErrMsg);
end;

procedure EnsureSQLiteLoaded; forward;

function UTF8PtrToString(P: MarshaledAString): string;
begin
  if P = nil then
    Result := ''
  else
    Result := string(UTF8String(P));
end;

function SQLQuote(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
end;

function TryLoadSQLiteFrom(const AFileName: string): Boolean;
begin
  Result := FileExists(AFileName) and (LoadLibrary(PChar(AFileName)) <> 0);
end;

procedure EnsureSQLiteLoaded;
var
  BDS: string;
  ExeDir: string;
begin
  if GetModuleHandle('sqlite3.dll') <> 0 then Exit;

  ExeDir := ExtractFileDir(ParamStr(0));
  if TryLoadSQLiteFrom(TPath.Combine(ExeDir, 'sqlite3.dll')) then Exit;

  BDS := GetEnvironmentVariable('BDS');
  if (BDS <> '') and TryLoadSQLiteFrom(TPath.Combine(BDS, 'bin\sqlite3.dll')) then Exit;

  if TryLoadSQLiteFrom('C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\sqlite3.dll') then Exit;
  if TryLoadSQLiteFrom('C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\sqlite3.dll') then Exit;

  raise Exception.Create('sqlite3.dll nao encontrada. Copie sqlite3.dll para a mesma pasta do PS4PKGDownloader.exe.');
end;

procedure EnsureSQLiteFile(const AFileName: string);
const
  SQLITE_HEADER: AnsiString = 'SQLite format 3';
var
  FS: TFileStream;
  Header: TBytes;
  S: AnsiString;
begin
  if not FileExists(AFileName) then
    raise Exception.Create('trophy_local.db nao foi baixado do PS4.');

  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    if FS.Size < 100 then
      raise Exception.Create('trophy_local.db baixado esta vazio ou incompleto.');
    SetLength(Header, Length(SQLITE_HEADER));
    FS.ReadBuffer(Header[0], Length(Header));
    SetString(S, PAnsiChar(@Header[0]), Length(Header));
    if S <> SQLITE_HEADER then
      raise Exception.Create('trophy_local.db baixado nao tem cabecalho SQLite valido.');
  finally
    FS.Free;
  end;
end;

type
  TPS4TrophyDb = class
  private
    FDb: sqlite3;
    procedure CheckSQLite(ACode: Integer; const AContext: string);
    procedure Query(const ASQL: string; ARows: TStrings);
    function ScalarInt(const ASQL: string): Integer;
    procedure Exec(const ASQL: string);
    procedure InsertTitleFromLeft(const ATrophyTitleID: string);
    procedure MergeUnlockedFromLeft(const ATrophyTitleID: string);
    procedure RecountTitle(const ATrophyTitleID: string);
    procedure RecountUser;
    procedure SortAlphabetically;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    function ReadTitles(const AUserID: string): TArray<TPS4TrophyTitle>;
    function HasTitle(const ATrophyTitleID: string): Boolean;
    procedure DeleteTitle(const ATrophyTitleID: string);
    procedure SortTitlesAlphabetically;
    procedure MergeFromLeft(const ALeftDb: string; const ATrophyTitleID: string;
      AExistingMode: TPS4TrophyExistingMode);
  end;

function ListPS4TrophiesFromBackup(const ABackupDir, AUserID: string): TArray<TPS4TrophyTitle>;
var
  Db: TPS4TrophyDb;
  DbFile: string;
  DbFiles: TArray<string>;
begin
  DbFiles := TDirectory.GetFiles(ABackupDir, 'trophy_local.db', TSearchOption.soAllDirectories);
  if Length(DbFiles) = 0 then
    raise Exception.Create('Backup invalido: trophy_local.db nao encontrado.');
  DbFile := DbFiles[0];
  EnsureSQLiteLoaded;
  Db := TPS4TrophyDb.Create(DbFile);
  try
    Result := Db.ReadTitles(AUserID);
  finally
    Db.Free;
  end;
end;

constructor TPS4TrophyDb.Create(const AFileName: string);
var
  Code: Integer;
  Utf8Name: UTF8String;
begin
  inherited Create;
  FDb := nil;
  Utf8Name := UTF8String(AFileName);
  Code := sqlite3_open_v2(PAnsiChar(Utf8Name), FDb,
    SQLITE_OPEN_READWRITE or SQLITE_OPEN_FULLMUTEX, nil);
  CheckSQLite(Code, 'abrir trophy_local.db');
  sqlite3_busy_timeout(FDb, 5000);
end;

destructor TPS4TrophyDb.Destroy;
begin
  if FDb <> nil then sqlite3_close(FDb);
  inherited;
end;

procedure TPS4TrophyDb.CheckSQLite(ACode: Integer; const AContext: string);
var
  Msg: string;
begin
  if ACode = SQLITE_OK then Exit;
  if FDb <> nil then
    Msg := UTF8PtrToString(sqlite3_errmsg(FDb))
  else
    Msg := 'erro SQLite ' + IntToStr(ACode);
  raise Exception.Create('Falha ao ' + AContext + ': ' + Msg);
end;

procedure TPS4TrophyDb.Query(const ASQL: string; ARows: TStrings);
var
  Code, RowCount, ColCount, I, J, Idx: Integer;
  ErrMsg: MarshaledAString;
  Table: PMarshaledAString;
  Cells: PSQLiteCellArray;
  Utf8SQL: UTF8String;
  Line: string;
begin
  ARows.Clear;
  RowCount := 0;
  ColCount := 0;
  ErrMsg := nil;
  Table := nil;
  Utf8SQL := UTF8String(ASQL);
  Code := sqlite3_get_table(FDb, PAnsiChar(Utf8SQL), @Table, RowCount,
    ColCount, @ErrMsg);
  if Code <> SQLITE_OK then
  begin
    try
      if ErrMsg <> nil then
        raise Exception.Create(UTF8PtrToString(ErrMsg))
      else
        CheckSQLite(Code, 'consultar trophy_local.db');
    finally
      if ErrMsg <> nil then sqlite3_free(ErrMsg);
    end;
  end;

  try
    Cells := PSQLiteCellArray(Table);
    for I := 1 to RowCount do
    begin
      Line := '';
      for J := 0 to ColCount - 1 do
      begin
        Idx := I * ColCount + J;
        if J > 0 then Line := Line + #9;
        Line := Line + UTF8PtrToString(Cells^[Idx]);
      end;
      ARows.Add(Line);
    end;
  finally
    if Table <> nil then sqlite3_free_table(Table);
  end;
end;

function TPS4TrophyDb.ScalarInt(const ASQL: string): Integer;
var
  Rows: TStringList;
begin
  Result := 0;
  Rows := TStringList.Create;
  try
    Query(ASQL, Rows);
    if Rows.Count > 0 then
      Result := StrToIntDef(Rows[0], 0);
  finally
    Rows.Free;
  end;
end;

procedure TPS4TrophyDb.Exec(const ASQL: string);
var
  Code: Integer;
  ErrMsg: MarshaledAString;
  Utf8SQL: UTF8String;
begin
  ErrMsg := nil;
  Utf8SQL := UTF8String(ASQL);
  Code := SQLiteExecUtf8(FDb, PAnsiChar(Utf8SQL), nil, nil, @ErrMsg);
  if Code <> SQLITE_OK then
  begin
    try
      if ErrMsg <> nil then
        raise Exception.Create(UTF8PtrToString(ErrMsg))
      else
        CheckSQLite(Code, 'alterar trophy_local.db');
    finally
      if ErrMsg <> nil then sqlite3_free(ErrMsg);
    end;
  end;
end;

function TPS4TrophyDb.ReadTitles(const AUserID: string): TArray<TPS4TrophyTitle>;
var
  Rows: TStringList;
  I: Integer;
  Parts: TArray<string>;
  Item: TPS4TrophyTitle;
begin
  SetLength(Result, 0);
  Rows := TStringList.Create;
  try
    Query('SELECT trophy_title_id, title, trophy_num, unlocked_trophy_num ' +
      'FROM tbl_trophy_title ORDER BY title COLLATE NOCASE', Rows);
    for I := 0 to Rows.Count - 1 do
    begin
      Parts := Rows[I].Split([#9]);
      if Length(Parts) < 4 then Continue;
      Item.UserID := AUserID;
      Item.TrophyTitleID := Parts[0];
      Item.Title := Parts[1];
      Item.TrophyNum := StrToIntDef(Parts[2], 0);
      Item.UnlockedNum := StrToIntDef(Parts[3], 0);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Item;
    end;
  finally
    Rows.Free;
  end;
end;

function TPS4TrophyDb.HasTitle(const ATrophyTitleID: string): Boolean;
begin
  Result := ScalarInt('SELECT COUNT(*) FROM tbl_trophy_title WHERE trophy_title_id = ' +
    SQLQuote(ATrophyTitleID)) > 0;
end;

procedure TPS4TrophyDb.InsertTitleFromLeft(const ATrophyTitleID: string);
var
  Q: string;
begin
  Q := SQLQuote(ATrophyTitleID);

  Exec('DELETE FROM tbl_trophy_flag_entry WHERE trophy_title_id = ' + Q);
  Exec('DELETE FROM tbl_trophy_title_entry WHERE trophy_title_id = ' + Q);
  Exec('DELETE FROM tbl_trophy_flag WHERE trophy_title_id = ' + Q);
  Exec('DELETE FROM tbl_trophy_group WHERE trophy_title_id = ' + Q);
  Exec('DELETE FROM tbl_trophy_title WHERE trophy_title_id = ' + Q);

  Exec('CREATE TEMP TABLE tmp_trophy_ids AS ' +
    'SELECT COALESCE((SELECT MAX(id) FROM tbl_trophy_title),0)+1 AS title_id, ' +
    'COALESCE((SELECT MAX(id) FROM tbl_trophy_title_entry),0) AS title_entry_base, ' +
    'COALESCE((SELECT MAX(id) FROM tbl_trophy_group),0) AS group_base, ' +
    'COALESCE((SELECT MAX(id) FROM tbl_trophy_flag),0) AS flag_base, ' +
    'COALESCE((SELECT MAX(id) FROM tbl_trophy_flag_entry),0) AS flag_entry_base');

  Exec('INSERT INTO tbl_trophy_title ' +
    '(id,user_id,revision,trophy_title_id,status,conf_file_revision,data_file_revision,trop_info_revision,net_trans_file_revision,' +
    'trophies_conf_file_revision,trophies_data_file_revision,trophies_trop_info_revision,trophies_net_trans_file_revision,' +
    'progress,unlocked_trophy_num,unlocked_platinum_num,unlocked_gold_num,unlocked_silver_num,unlocked_bronze_num,' +
    'sync_req_num,sync_pending_num,time_last_synced,time_last_unlocked,time_last_update,time_last_update_uc,' +
    'instsrc_type,instsrc_attr,instsrc_digest,icon_location,platform,trophy_set_version,trophy_num,platinum_num,gold_num,' +
    'silver_num,bronze_num,platinum_set,gold_set,silver_set,bronze_set,group_num,group_set,title,description) ' +
    'SELECT (SELECT title_id FROM tmp_trophy_ids),(SELECT id FROM tbl_trophy_user LIMIT 1),' +
    'revision,trophy_title_id,status,conf_file_revision,data_file_revision,trop_info_revision,net_trans_file_revision,' +
    'trophies_conf_file_revision,trophies_data_file_revision,trophies_trop_info_revision,trophies_net_trans_file_revision,' +
    'progress,unlocked_trophy_num,unlocked_platinum_num,unlocked_gold_num,unlocked_silver_num,unlocked_bronze_num,' +
    'sync_req_num,sync_pending_num,time_last_synced,time_last_unlocked,time_last_update,time_last_update_uc,' +
    'instsrc_type,instsrc_attr,instsrc_digest,icon_location,platform,trophy_set_version,trophy_num,platinum_num,gold_num,' +
    'silver_num,bronze_num,platinum_set,gold_set,silver_set,bronze_set,group_num,group_set,title,description ' +
    'FROM src.tbl_trophy_title WHERE trophy_title_id = ' + Q);

  Exec('INSERT INTO tbl_trophy_group ' +
    'SELECT id + (SELECT group_base FROM tmp_trophy_ids), ' +
    '(SELECT title_id FROM tmp_trophy_ids), trophy_title_id, progress, unlocked_trophy_num, unlocked_platinum_num, ' +
    'unlocked_gold_num, unlocked_silver_num, unlocked_bronze_num, time_last_unlocked, time_last_update, ' +
    'time_last_update_uc, groupid, trophy_num, platinum_num, gold_num, silver_num, bronze_num, platinum_set, ' +
    'gold_set, silver_set, bronze_set, title, description FROM src.tbl_trophy_group WHERE trophy_title_id = ' + Q);

  Exec('INSERT INTO tbl_trophy_flag ' +
    'SELECT id + (SELECT flag_base FROM tmp_trophy_ids), ' +
    '(SELECT title_id FROM tmp_trophy_ids), revision, trophy_title_id, trophyid, groupid, visible, unlocked, ' +
    'unlock_attribute, time_unlocked, time_unlocked_uc, grade, hidden, title, description ' +
    'FROM src.tbl_trophy_flag WHERE trophy_title_id = ' + Q);

  Exec('INSERT INTO tbl_trophy_title_entry ' +
    '(id,user_entry_id,revision,trophy_title_id,status,instsrc_type,instsrc_attr,instsrc_digest,data_file_revision,' +
    'trop_info_revision,conf_file_revision,net_trans_file_revision,time_last_update,time_last_update_uc) ' +
    'SELECT id + (SELECT title_entry_base FROM tmp_trophy_ids),(SELECT id FROM tbl_trophy_user_entry LIMIT 1),' +
    'revision,trophy_title_id,status,instsrc_type,instsrc_attr,instsrc_digest,data_file_revision,trop_info_revision,' +
    'conf_file_revision,net_trans_file_revision,time_last_update,time_last_update_uc ' +
    'FROM src.tbl_trophy_title_entry WHERE trophy_title_id = ' + Q);

  Exec('INSERT INTO tbl_trophy_flag_entry ' +
    'SELECT id + (SELECT flag_entry_base FROM tmp_trophy_ids), ' +
    'title_entry_id + (SELECT title_entry_base FROM tmp_trophy_ids), revision, trophy_title_id, trophyid ' +
    'FROM src.tbl_trophy_flag_entry WHERE trophy_title_id = ' + Q);

  Exec('DROP TABLE tmp_trophy_ids');
end;

procedure TPS4TrophyDb.MergeUnlockedFromLeft(const ATrophyTitleID: string);
var
  Q: string;
begin
  Q := SQLQuote(ATrophyTitleID);

  Exec('UPDATE tbl_trophy_flag SET ' +
    'unlocked = 1, ' +
    'unlock_attribute = (SELECT src.unlock_attribute FROM src.tbl_trophy_flag src ' +
      'WHERE src.trophy_title_id = tbl_trophy_flag.trophy_title_id AND src.trophyid = tbl_trophy_flag.trophyid), ' +
    'time_unlocked = (SELECT src.time_unlocked FROM src.tbl_trophy_flag src ' +
      'WHERE src.trophy_title_id = tbl_trophy_flag.trophy_title_id AND src.trophyid = tbl_trophy_flag.trophyid), ' +
    'time_unlocked_uc = (SELECT src.time_unlocked_uc FROM src.tbl_trophy_flag src ' +
      'WHERE src.trophy_title_id = tbl_trophy_flag.trophy_title_id AND src.trophyid = tbl_trophy_flag.trophyid) ' +
    'WHERE tbl_trophy_flag.trophy_title_id = ' + Q + ' AND COALESCE(tbl_trophy_flag.unlocked,0) = 0 ' +
    'AND EXISTS (SELECT 1 FROM src.tbl_trophy_flag src ' +
      'WHERE src.trophy_title_id = tbl_trophy_flag.trophy_title_id AND src.trophyid = tbl_trophy_flag.trophyid ' +
      'AND COALESCE(src.unlocked,0) <> 0)');
end;

procedure TPS4TrophyDb.RecountTitle(const ATrophyTitleID: string);
var
  Q: string;
begin
  Q := SQLQuote(ATrophyTitleID);

  Exec('UPDATE tbl_trophy_title SET ' +
    'unlocked_trophy_num = (SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND COALESCE(f.unlocked,0) <> 0), ' +
    'unlocked_platinum_num = (SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND COALESCE(f.unlocked,0) <> 0 AND f.grade = 1), ' +
    'unlocked_gold_num = (SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND COALESCE(f.unlocked,0) <> 0 AND f.grade = 2), ' +
    'unlocked_silver_num = (SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND COALESCE(f.unlocked,0) <> 0 AND f.grade = 3), ' +
    'unlocked_bronze_num = (SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND COALESCE(f.unlocked,0) <> 0 AND f.grade = 4), ' +
    'progress = CASE WHEN COALESCE(trophy_num,0) > 0 THEN CAST(((SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND COALESCE(f.unlocked,0) <> 0) * 100) / trophy_num AS INTEGER) ELSE 0 END, ' +
    'time_last_unlocked = COALESCE((SELECT MAX(NULLIF(time_unlocked,''0001-01-01T00:00:00.00Z'')) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND COALESCE(f.unlocked,0) <> 0), time_last_unlocked), ' +
    'time_last_update = COALESCE((SELECT MAX(NULLIF(time_unlocked,''0001-01-01T00:00:00.00Z'')) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND COALESCE(f.unlocked,0) <> 0), time_last_update) ' +
    'WHERE trophy_title_id = ' + Q);

  Exec('UPDATE tbl_trophy_group SET ' +
    'unlocked_trophy_num = (SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND f.groupid = tbl_trophy_group.groupid AND COALESCE(f.unlocked,0) <> 0), ' +
    'unlocked_platinum_num = (SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND f.groupid = tbl_trophy_group.groupid AND COALESCE(f.unlocked,0) <> 0 AND f.grade = 1), ' +
    'unlocked_gold_num = (SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND f.groupid = tbl_trophy_group.groupid AND COALESCE(f.unlocked,0) <> 0 AND f.grade = 2), ' +
    'unlocked_silver_num = (SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND f.groupid = tbl_trophy_group.groupid AND COALESCE(f.unlocked,0) <> 0 AND f.grade = 3), ' +
    'unlocked_bronze_num = (SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND f.groupid = tbl_trophy_group.groupid AND COALESCE(f.unlocked,0) <> 0 AND f.grade = 4), ' +
    'progress = CASE WHEN COALESCE(trophy_num,0) > 0 THEN CAST(((SELECT COUNT(*) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND f.groupid = tbl_trophy_group.groupid AND COALESCE(f.unlocked,0) <> 0) * 100) / trophy_num AS INTEGER) ELSE 0 END, ' +
    'time_last_unlocked = COALESCE((SELECT MAX(NULLIF(time_unlocked,''0001-01-01T00:00:00.00Z'')) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND f.groupid = tbl_trophy_group.groupid AND COALESCE(f.unlocked,0) <> 0), time_last_unlocked), ' +
    'time_last_update = COALESCE((SELECT MAX(NULLIF(time_unlocked,''0001-01-01T00:00:00.00Z'')) FROM tbl_trophy_flag f WHERE f.trophy_title_id = ' + Q + ' AND f.groupid = tbl_trophy_group.groupid AND COALESCE(f.unlocked,0) <> 0), time_last_update) ' +
    'WHERE trophy_title_id = ' + Q);

  Exec('UPDATE tbl_trophy_user SET ' +
    'title_num = (SELECT COUNT(*) FROM tbl_trophy_title), ' +
    'icon_title_num = (SELECT COUNT(*) FROM tbl_trophy_title)');
end;

procedure TPS4TrophyDb.RecountUser;
begin
  Exec('UPDATE tbl_trophy_user SET ' +
    'title_num = (SELECT COUNT(*) FROM tbl_trophy_title), ' +
    'icon_title_num = (SELECT COUNT(*) FROM tbl_trophy_title)');
end;

procedure TPS4TrophyDb.DeleteTitle(const ATrophyTitleID: string);
var
  Q: string;
begin
  Q := SQLQuote(ATrophyTitleID);

  Exec('BEGIN IMMEDIATE');
  try
    Exec('DELETE FROM tbl_trophy_flag_entry WHERE trophy_title_id = ' + Q);
    Exec('DELETE FROM tbl_trophy_title_entry WHERE trophy_title_id = ' + Q);
    Exec('DELETE FROM tbl_trophy_flag WHERE trophy_title_id = ' + Q);
    Exec('DELETE FROM tbl_trophy_group WHERE trophy_title_id = ' + Q);
    Exec('DELETE FROM tbl_trophy_title WHERE trophy_title_id = ' + Q);
    RecountUser;
    Exec('COMMIT');
  except
    Exec('ROLLBACK');
    raise;
  end;
end;

procedure TPS4TrophyDb.SortAlphabetically;
begin
  Exec('DROP TABLE IF EXISTS tmp_title_sort');
  Exec('CREATE TEMP TABLE tmp_title_sort AS ' +
    'SELECT a.trophy_title_id, ' +
    '(SELECT COUNT(*) FROM tbl_trophy_title b WHERE ' +
      'b.title COLLATE NOCASE < a.title COLLATE NOCASE OR ' +
      '(b.title COLLATE NOCASE = a.title COLLATE NOCASE AND b.trophy_title_id COLLATE NOCASE <= a.trophy_title_id COLLATE NOCASE)) AS alpha_rank, ' +
    'strftime(''%Y-%m-%dT%H:%M:%S.00Z'', ''now'', ''-'' || ((SELECT COUNT(*) FROM tbl_trophy_title b WHERE ' +
      'b.title COLLATE NOCASE < a.title COLLATE NOCASE OR ' +
      '(b.title COLLATE NOCASE = a.title COLLATE NOCASE AND b.trophy_title_id COLLATE NOCASE <= a.trophy_title_id COLLATE NOCASE)) - 1) || '' seconds'') AS sort_time, ' +
    'strftime(''%Y-%m-%dT%H:%M:%fZ'', ''now'', ''-'' || ((SELECT COUNT(*) FROM tbl_trophy_title b WHERE ' +
      'b.title COLLATE NOCASE < a.title COLLATE NOCASE OR ' +
      '(b.title COLLATE NOCASE = a.title COLLATE NOCASE AND b.trophy_title_id COLLATE NOCASE <= a.trophy_title_id COLLATE NOCASE)) - 1) || '' seconds'') AS sort_time_uc ' +
    'FROM tbl_trophy_title a');

  Exec('UPDATE tbl_trophy_title SET ' +
    'time_last_update = (SELECT sort_time FROM tmp_title_sort s WHERE s.trophy_title_id = tbl_trophy_title.trophy_title_id), ' +
    'time_last_update_uc = (SELECT sort_time_uc FROM tmp_title_sort s WHERE s.trophy_title_id = tbl_trophy_title.trophy_title_id)');
  Exec('UPDATE tbl_trophy_title_entry SET ' +
    'time_last_update = (SELECT sort_time FROM tmp_title_sort s WHERE s.trophy_title_id = tbl_trophy_title_entry.trophy_title_id), ' +
    'time_last_update_uc = (SELECT sort_time_uc FROM tmp_title_sort s WHERE s.trophy_title_id = tbl_trophy_title_entry.trophy_title_id)');
  Exec('UPDATE tbl_trophy_group SET ' +
    'time_last_update = (SELECT sort_time FROM tmp_title_sort s WHERE s.trophy_title_id = tbl_trophy_group.trophy_title_id), ' +
    'time_last_update_uc = (SELECT sort_time_uc FROM tmp_title_sort s WHERE s.trophy_title_id = tbl_trophy_group.trophy_title_id)');

  Exec('DROP TABLE tmp_title_sort');
end;

procedure TPS4TrophyDb.SortTitlesAlphabetically;
begin
  Exec('BEGIN IMMEDIATE');
  try
    SortAlphabetically;
    RecountUser;
    Exec('COMMIT');
  except
    Exec('ROLLBACK');
    raise;
  end;
end;

procedure TPS4TrophyDb.MergeFromLeft(const ALeftDb: string; const ATrophyTitleID: string;
  AExistingMode: TPS4TrophyExistingMode);
var
  Q, SrcFile: string;
  TitleExists: Boolean;
begin
  Q := SQLQuote(ATrophyTitleID);
  SrcFile := SQLQuote(ALeftDb);

  Exec('ATTACH DATABASE ' + SrcFile + ' AS src');
  try
    TitleExists := ScalarInt('SELECT COUNT(*) FROM tbl_trophy_title WHERE trophy_title_id = ' + Q) > 0;
    Exec('BEGIN IMMEDIATE');
    try
      if TitleExists and (AExistingMode = temMerge) then
        MergeUnlockedFromLeft(ATrophyTitleID)
      else
        InsertTitleFromLeft(ATrophyTitleID);
      RecountTitle(ATrophyTitleID);
      Exec('COMMIT');
    except
      Exec('ROLLBACK');
      raise;
    end;
  finally
    Exec('DETACH DATABASE src');
  end;
end;

function ConnectFTP(const AHost: string; APort: Word): TIdFTP;
begin
  Result := TIdFTP.Create(nil);
  try
    Result.Host := Trim(AHost);
    Result.Port := APort;
    Result.Username := PS4_FTP_USER;
    Result.Password := PS4_FTP_PASS;
    Result.Passive := True;
    Result.TransferType := ftBinary;
    Result.ConnectTimeout := 10000;
    Result.ReadTimeout := 30000;
    Result.Connect;
  except
    Result.Free;
    raise;
  end;
end;

function TryListDir(AFTP: TIdFTP; const ARemoteDir: string): Boolean;
begin
  try
    AFTP.DirectoryListing.Clear;
    AFTP.ChangeDir(ARemoteDir);
    AFTP.List('', True);
    Result := True;
  except
    Result := False;
  end;
end;

procedure DownloadDir(AFTP: TIdFTP; const ARemoteDir, ALocalDir: string;
  ALog: TPS4TrophyLogEvent);
var
  Names: TStringList;
  IsDir: TList<Boolean>;
  I: Integer;
  RemoteName, RemotePath, LocalPath: string;
begin
  ForceDirectories(ALocalDir);
  Names := TStringList.Create;
  IsDir := TList<Boolean>.Create;
  try
    if not TryListDir(AFTP, ARemoteDir) then Exit;
    for I := 0 to AFTP.DirectoryListing.Count - 1 do
    begin
      RemoteName := AFTP.DirectoryListing[I].FileName;
      if (RemoteName = '.') or (RemoteName = '..') then Continue;
      Names.Add(RemoteName);
      IsDir.Add(AFTP.DirectoryListing[I].ItemType = ditDirectory);
    end;

    for I := 0 to Names.Count - 1 do
    begin
      RemotePath := ARemoteDir + '/' + Names[I];
      LocalPath := TPath.Combine(ALocalDir, Names[I]);
      if IsDir[I] then
        DownloadDir(AFTP, RemotePath, LocalPath, ALog)
      else
      begin
        if Assigned(ALog) then ALog('Baixando ' + RemotePath);
        AFTP.Get(RemotePath, LocalPath, True);
      end;
    end;
  finally
    IsDir.Free;
    Names.Free;
  end;
end;

procedure EnsureRemoteDir(AFTP: TIdFTP; const APath: string);
var
  Part, CurrentPath: string;
begin
  CurrentPath := '';
  for Part in StringReplace(APath, '\', '/', [rfReplaceAll]).Split(['/']) do
  begin
    if Part = '' then Continue;
    CurrentPath := CurrentPath + '/' + Part;
    try
      AFTP.ChangeDir(CurrentPath);
    except
      try
        AFTP.MakeDir(CurrentPath);
      except
      end;
      AFTP.ChangeDir(CurrentPath);
    end;
  end;
end;

procedure UploadDir(AFTP: TIdFTP; const ALocalDir, ARemoteDir: string;
  ALog: TPS4TrophyLogEvent);
var
  Files, Dirs: TStringDynArray;
  F, D: string;
begin
  EnsureRemoteDir(AFTP, ARemoteDir);
  Files := TDirectory.GetFiles(ALocalDir);
  for F in Files do
  begin
    if Assigned(ALog) then ALog('Enviando ' + ExtractFileName(F) + ' para ' + ARemoteDir);
    AFTP.ChangeDir(ARemoteDir);
    AFTP.Put(F, ExtractFileName(F));
  end;

  Dirs := TDirectory.GetDirectories(ALocalDir);
  for D in Dirs do
    UploadDir(AFTP, D, ARemoteDir + '/' + ExtractFileName(D), ALog);
end;

procedure ClearRemoteDir(AFTP: TIdFTP; const ARemoteDir: string;
  ALog: TPS4TrophyLogEvent);
var
  Names: TStringList;
  IsDir: TList<Boolean>;
  I: Integer;
  RemoteName, RemotePath: string;
begin
  Names := TStringList.Create;
  IsDir := TList<Boolean>.Create;
  try
    if not TryListDir(AFTP, ARemoteDir) then
    begin
      EnsureRemoteDir(AFTP, ARemoteDir);
      Exit;
    end;

    for I := 0 to AFTP.DirectoryListing.Count - 1 do
    begin
      RemoteName := AFTP.DirectoryListing[I].FileName;
      if (RemoteName = '.') or (RemoteName = '..') then Continue;
      Names.Add(RemoteName);
      IsDir.Add(AFTP.DirectoryListing[I].ItemType = ditDirectory);
    end;

    for I := 0 to Names.Count - 1 do
    begin
      RemotePath := ARemoteDir + '/' + Names[I];
      if IsDir[I] then
      begin
        ClearRemoteDir(AFTP, RemotePath, ALog);
        try
          AFTP.RemoveDir(RemotePath);
        except
        end;
      end
      else
      begin
        if Assigned(ALog) then
          ALog('Removendo cache ' + RemotePath);
        try
          AFTP.Delete(RemotePath);
        except
        end;
      end;
    end;
  finally
    IsDir.Free;
    Names.Free;
  end;
end;

procedure DeleteRemoteDir(AFTP: TIdFTP; const ARemoteDir: string;
  ALog: TPS4TrophyLogEvent);
begin
  if not TryListDir(AFTP, ARemoteDir) then Exit;
  ClearRemoteDir(AFTP, ARemoteDir, ALog);
  if Assigned(ALog) then
    ALog('Removendo pasta ' + ARemoteDir);
  try
    AFTP.RemoveDir(ARemoteDir);
  except
  end;
end;

procedure DeleteRemoteFileIfExists(AFTP: TIdFTP; const ARemoteFile: string;
  ALog: TPS4TrophyLogEvent);
begin
  try
    if Assigned(ALog) then
      ALog('Removendo arquivo auxiliar ' + ARemoteFile);
    AFTP.Delete(ARemoteFile);
  except
  end;
end;

procedure RenameRemoteDirIfExists(AFTP: TIdFTP; const AOldDir, ANewDir: string;
  ALog: TPS4TrophyLogEvent);
begin
  if not TryListDir(AFTP, AOldDir) then Exit;
  try
    if Assigned(ALog) then
      ALog('Renomeando ' + AOldDir + ' para ' + ANewDir);
    AFTP.Rename(AOldDir, ANewDir);
  except
  end;
end;

procedure ReorderRemoteTrophyDirs(AFTP: TIdFTP; const ABaseDir: string;
  const ATrophies: TArray<TPS4TrophyTitle>; ALog: TPS4TrophyLogEvent);
var
  I: Integer;
  TmpName, OldDir, TmpDir: string;
begin
  for I := 0 to High(ATrophies) do
  begin
    TmpName := '__az_tmp_' + ATrophies[I].TrophyTitleID;
    OldDir := ABaseDir + '/' + ATrophies[I].TrophyTitleID;
    TmpDir := ABaseDir + '/' + TmpName;
    RenameRemoteDirIfExists(AFTP, TmpDir, OldDir, nil);
    RenameRemoteDirIfExists(AFTP, OldDir, TmpDir, ALog);
  end;

  for I := High(ATrophies) downto 0 do
  begin
    TmpName := '__az_tmp_' + ATrophies[I].TrophyTitleID;
    OldDir := ABaseDir + '/' + ATrophies[I].TrophyTitleID;
    TmpDir := ABaseDir + '/' + TmpName;
    RenameRemoteDirIfExists(AFTP, TmpDir, OldDir, ALog);
  end;
end;

procedure DownloadRemoteDb(AFTP: TIdFTP; const AUserID, ALocalDb: string);
var
  FS: TFileStream;
begin
  ForceDirectories(ExtractFileDir(ALocalDb));
  FS := TFileStream.Create(ALocalDb, fmCreate);
  try
    AFTP.Get('/user/home/' + AUserID + '/trophy/db/trophy_local.db', FS, False);
  finally
    FS.Free;
  end;
  EnsureSQLiteFile(ALocalDb);
end;

function TryDownloadRemoteDb(AFTP: TIdFTP; const AUserID, ALocalDb: string): Boolean;
begin
  Result := False;
  try
    DownloadRemoteDb(AFTP, AUserID, ALocalDb);
    Result := True;
  except
    try
      if FileExists(ALocalDb) then
        TFile.Delete(ALocalDb);
    except
    end;
  end;
end;

procedure UploadRemoteDb(AFTP: TIdFTP; const AUserID, ALocalDb: string);
begin
  AFTP.ChangeDir('/user/home/' + AUserID + '/trophy/db');
  AFTP.Put(ALocalDb, 'trophy_local.db');
  DeleteRemoteFileIfExists(AFTP, '/user/home/' + AUserID + '/trophy/db/trophy_local.db-wal', nil);
  DeleteRemoteFileIfExists(AFTP, '/user/home/' + AUserID + '/trophy/db/trophy_local.db-shm', nil);
  DeleteRemoteFileIfExists(AFTP, '/user/home/' + AUserID + '/trophy/db/trophy_local.db-journal', nil);
end;

procedure WriteTrophyStateBackupInfo(const ADestDir, AHost, AUserID: string);
var
  Info: TStringList;
begin
  ForceDirectories(ADestDir);
  Info := TStringList.Create;
  try
    Info.Add('PS4PKGDownloader Trophy State Backup');
    Info.Add('Criado em: ' + DateTimeToStr(Now));
    Info.Add('Host: ' + AHost);
    Info.Add('Usuario: ' + AUserID);
    Info.Add('');
    Info.Add('Conteudo:');
    Info.Add('/user/home/' + AUserID + '/trophy/db');
    Info.Add('/user/home/' + AUserID + '/trophy/data');
    Info.Add('/user/trophy/conf');
    Info.Add('');
    Info.Add('Restaurar este backup substitui esses caminhos no PS4 destino.');
    Info.SaveToFile(TPath.Combine(ADestDir, 'BACKUP_INFO.txt'), TEncoding.UTF8);
  finally
    Info.Free;
  end;
end;

function FirstPS4UserID(AFTP: TIdFTP): string;
var
  I: Integer;
begin
  Result := '';
  if TryListDir(AFTP, '/user/home') then
    for I := 0 to AFTP.DirectoryListing.Count - 1 do
      if AFTP.DirectoryListing[I].ItemType = ditDirectory then
        Exit(AFTP.DirectoryListing[I].FileName);
end;

function FindTrophyUserID(AFTP: TIdFTP; const ALocalDb: string): string;
var
  I: Integer;
  UserID: string;
begin
  Result := '';
  if not TryListDir(AFTP, '/user/home') then Exit;

  for I := 0 to AFTP.DirectoryListing.Count - 1 do
  begin
    if AFTP.DirectoryListing[I].ItemType <> ditDirectory then Continue;
    UserID := AFTP.DirectoryListing[I].FileName;
    if TryDownloadRemoteDb(AFTP, UserID, ALocalDb) then
      Exit(UserID);
  end;
end;

function ListPS4TrophyUsers(const AHost: string; APort: Word): TArray<TPS4TrophyUser>;
var
  FTP: TIdFTP;
  WorkDir, TestDb: string;
  I: Integer;
  User: TPS4TrophyUser;
begin
  SetLength(Result, 0);
  WorkDir := TPath.Combine(TPath.GetTempPath,
    'PS4PKGDownloader_trophy_users_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
  TestDb := TPath.Combine(WorkDir, 'trophy_local.db');

  FTP := ConnectFTP(AHost, APort);
  try
    if not TryListDir(FTP, '/user/home') then
      raise Exception.Create('Nao foi possivel listar /user/home.');

    for I := 0 to FTP.DirectoryListing.Count - 1 do
    begin
      if FTP.DirectoryListing[I].ItemType <> ditDirectory then Continue;
      User.UserID := FTP.DirectoryListing[I].FileName;
      User.HasTrophyDb := TryDownloadRemoteDb(FTP, User.UserID, TestDb);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := User;
    end;
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
    try
      TDirectory.Delete(WorkDir, True);
    except
    end;
  end;
end;

function ListPS4Trophies(const AHost: string; APort: Word): TArray<TPS4TrophyTitle>;
var
  FTP: TIdFTP;
  Db: TPS4TrophyDb;
  WorkDir, LocalDb, UserID: string;
begin
  SetLength(Result, 0);
  WorkDir := TPath.Combine(TPath.GetTempPath,
    'PS4PKGDownloader_trophy_list_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
  LocalDb := TPath.Combine(WorkDir, 'trophy_local.db');

  FTP := ConnectFTP(AHost, APort);
  try
    UserID := FindTrophyUserID(FTP, LocalDb);
    if UserID = '' then
      raise Exception.Create('Nenhum usuario com /trophy/db/trophy_local.db foi encontrado em /user/home.');
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;

  try
    EnsureSQLiteLoaded;
    Db := TPS4TrophyDb.Create(LocalDb);
    try
      Result := Db.ReadTitles(UserID);
    finally
      Db.Free;
    end;
  finally
    try
      TDirectory.Delete(WorkDir, True);
    except
    end;
  end;
end;

function ListPS4TrophiesForUser(const AHost: string; APort: Word;
  const AUserID: string): TArray<TPS4TrophyTitle>;
var
  FTP: TIdFTP;
  Db: TPS4TrophyDb;
  WorkDir, LocalDb, UserID: string;
begin
  SetLength(Result, 0);
  WorkDir := TPath.Combine(TPath.GetTempPath,
    'PS4PKGDownloader_trophy_list_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
  LocalDb := TPath.Combine(WorkDir, 'trophy_local.db');

  FTP := ConnectFTP(AHost, APort);
  try
    UserID := Trim(AUserID);
    if UserID = '' then
      UserID := FindTrophyUserID(FTP, LocalDb)
    else
    begin
      try
        DownloadRemoteDb(FTP, UserID, LocalDb);
      except
        on E: Exception do
        begin
          if Assigned(FTP) and FTP.Connected then
            FTP.Disconnect;
          FTP.Connect;
          UserID := FindTrophyUserID(FTP, LocalDb);
          if UserID = '' then
            Exit;
        end;
      end;
    end;
    if UserID = '' then
      Exit;
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;

  try
    EnsureSQLiteLoaded;
    Db := TPS4TrophyDb.Create(LocalDb);
    try
      Result := Db.ReadTitles(UserID);
    finally
      Db.Free;
    end;
  finally
    try
      TDirectory.Delete(WorkDir, True);
    except
    end;
  end;
end;

procedure SyncPS4TrophiesForUsers(const ALeftHost, ADestHost: string; APort: Word;
  const ALeftUserID, ADestUserID: string;
  const ATrophies: TArray<TPS4TrophyTitle>; AExistingMode: TPS4TrophyExistingMode;
  ALog: TPS4TrophyLogEvent);
var
  SrcFTP, DstFTP: TIdFTP;
  WorkDir, SrcDb, DstDb, SrcUserID, DstUserID: string;
  Trophy: TPS4TrophyTitle;
  I: Integer;
  LocalDataDir, LocalConfDir: string;
  Db: TPS4TrophyDb;
  NeedSceTropClear: Boolean;
begin
  if Length(ATrophies) = 0 then
    raise Exception.Create('Nenhum trofeu selecionado.');

  WorkDir := TPath.Combine(TPath.GetTempPath,
    'PS4PKGDownloader_trophy_sync_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
  SrcDb := TPath.Combine(WorkDir, 'Left_trophy_local.db');
  DstDb := TPath.Combine(WorkDir, 'dest_trophy_local.db');

  SrcFTP := nil;
  DstFTP := nil;
  NeedSceTropClear := False;
  try
    SrcFTP := ConnectFTP(ALeftHost, APort);
    DstFTP := ConnectFTP(ADestHost, APort);
    SrcUserID := Trim(ALeftUserID);
    if SrcUserID = '' then
      SrcUserID := ATrophies[0].UserID;
    if SrcUserID = '' then
      SrcUserID := FindTrophyUserID(SrcFTP, SrcDb);
    DstUserID := Trim(ADestUserID);
    if DstUserID = '' then
      DstUserID := FindTrophyUserID(DstFTP, DstDb);
    if SrcUserID = '' then raise Exception.Create('Nenhum usuario com trofeus encontrado no PS4 origem.');
    if DstUserID = '' then raise Exception.Create('Nenhum usuario com trofeus encontrado no PS4 destino.');

    if Assigned(ALog) then ALog('Baixando bancos de trofeus...');
    if not FileExists(SrcDb) then
      DownloadRemoteDb(SrcFTP, SrcUserID, SrcDb);
    if not FileExists(DstDb) then
      DownloadRemoteDb(DstFTP, DstUserID, DstDb);

    EnsureSQLiteLoaded;
    Db := TPS4TrophyDb.Create(DstDb);
    try
      for I := 0 to High(ATrophies) do
      begin
        Trophy := ATrophies[I];
        if Db.HasTitle(Trophy.TrophyTitleID) and (AExistingMode = temMerge) then
        begin
          if Assigned(ALog) then
            ALog('Mesclando desbloqueios: ' + Trophy.TrophyTitleID + ' - ' + Trophy.Title);
        end
        else
        begin
          if Assigned(ALog) then
          begin
            if Db.HasTitle(Trophy.TrophyTitleID) then
              ALog('Substituindo jogo de trofeus: ' + Trophy.TrophyTitleID + ' - ' + Trophy.Title)
            else
              ALog('Copiando novo jogo de trofeus: ' + Trophy.TrophyTitleID + ' - ' + Trophy.Title);
          end;
          LocalDataDir := TPath.Combine(TPath.Combine(WorkDir, 'data'), Trophy.TrophyTitleID);
          LocalConfDir := TPath.Combine(TPath.Combine(WorkDir, 'conf'), Trophy.TrophyTitleID);

          DownloadDir(SrcFTP, '/user/home/' + SrcUserID + '/trophy/data/' +
            Trophy.TrophyTitleID, LocalDataDir, ALog);
          DownloadDir(SrcFTP, '/user/trophy/conf/' + Trophy.TrophyTitleID,
            LocalConfDir, ALog);

          UploadDir(DstFTP, LocalDataDir, '/user/home/' + DstUserID +
            '/trophy/data/' + Trophy.TrophyTitleID, ALog);
          UploadDir(DstFTP, LocalConfDir, '/user/trophy/conf/' +
            Trophy.TrophyTitleID, ALog);
          NeedSceTropClear := True;
        end;
        Db.MergeFromLeft(SrcDb, Trophy.TrophyTitleID, AExistingMode);
      end;
    finally
      Db.Free;
    end;

    if Assigned(ALog) then ALog('Enviando trophy_local.db atualizado...');
    UploadRemoteDb(DstFTP, DstUserID, DstDb);
    if NeedSceTropClear then
    begin
      if Assigned(ALog) then
        ALog('Limpando cache sce_trop do usuario de destino...');
      ClearRemoteDir(DstFTP, '/user/home/' + DstUserID + '/trophy/data/sce_trop', ALog);
    end;
  finally
    if Assigned(SrcFTP) and SrcFTP.Connected then SrcFTP.Disconnect;
    if Assigned(DstFTP) and DstFTP.Connected then DstFTP.Disconnect;
    SrcFTP.Free;
    DstFTP.Free;
    try
      TDirectory.Delete(WorkDir, True);
    except
    end;
  end;
end;

procedure SyncPS4Trophies(const ALeftHost, ADestHost: string; APort: Word;
  const ATrophies: TArray<TPS4TrophyTitle>; AExistingMode: TPS4TrophyExistingMode;
  ALog: TPS4TrophyLogEvent);
begin
  SyncPS4TrophiesForUsers(ALeftHost, ADestHost, APort, '', '', ATrophies,
    AExistingMode, ALog);
end;

procedure RestorePS4TrophyTitles(const AHost: string; APort: Word;
  const AUserID, ABackupDir: string;
  const ATrophies: TArray<TPS4TrophyTitle>; AExistingMode: TPS4TrophyExistingMode;
  ALog: TPS4TrophyLogEvent; AProgress: TPS4TrophyProgressEvent);
var
  FTP: TIdFTP;
  WorkDir, TargetDb, SourceDb, UserID, SourceUserID: string;
  SourceDbs: TArray<string>;
  Trophy: TPS4TrophyTitle;
  I: Integer;
  Db: TPS4TrophyDb;
begin
  if Length(ATrophies) = 0 then
    raise Exception.Create('Nenhum trofeu selecionado.');
  WorkDir := TPath.Combine(TPath.GetTempPath,
    'PS4PKGDownloader_trophy_restore_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
  TargetDb := TPath.Combine(WorkDir, 'target_trophy_local.db');
  SourceDbs := TDirectory.GetFiles(ABackupDir, 'trophy_local.db', TSearchOption.soAllDirectories);
  if Length(SourceDbs) = 0 then
    raise Exception.Create('Backup invalido: trophy_local.db nao encontrado.');
  SourceDb := SourceDbs[0];
  FTP := nil;
  try
    ForceDirectories(WorkDir);
    FTP := ConnectFTP(AHost, APort);
    UserID := Trim(AUserID);
    if UserID = '' then
      raise Exception.Create('Usuario de destino nao informado.');
    DownloadRemoteDb(FTP, UserID, TargetDb);
    EnsureSQLiteLoaded;
    Db := TPS4TrophyDb.Create(TargetDb);
    try
      for I := 0 to High(ATrophies) do
      begin
        Trophy := ATrophies[I];
        if Assigned(ALog) then
          ALog('Restaurando jogo de trofeus: ' + Trophy.TrophyTitleID + ' - ' + Trophy.Title);
        Db.MergeFromLeft(SourceDb, Trophy.TrophyTitleID, AExistingMode);
        if Assigned(AProgress) then
          AProgress('Trofeu ' + IntToStr(I + 1) + ' de ' +
            IntToStr(Length(ATrophies)) + ' concluido: ' + Trophy.Title,
            I + 1, Length(ATrophies));
      end;
    finally
      Db.Free;
    end;
    UploadRemoteDb(FTP, UserID, TargetDb);
    SourceUserID := ExtractFileName(ExcludeTrailingPathDelimiter(ABackupDir));
    for Trophy in ATrophies do
    begin
      UploadDir(FTP,
        TPath.Combine(ABackupDir, 'user\home\' + SourceUserID + '\trophy\data\' + Trophy.TrophyTitleID),
        '/user/home/' + UserID + '/trophy/data/' + Trophy.TrophyTitleID, ALog);
      UploadDir(FTP,
        TPath.Combine(ABackupDir, 'user\trophy\conf\' + Trophy.TrophyTitleID),
        '/user/trophy/conf/' + Trophy.TrophyTitleID, ALog);
    end;
    ClearRemoteDir(FTP, '/user/home/' + UserID + '/trophy/data/sce_trop', ALog);
  finally
    if Assigned(FTP) and FTP.Connected then FTP.Disconnect;
    FTP.Free;
    try
      TDirectory.Delete(WorkDir, True);
    except
    end;
  end;
end;

procedure DeletePS4TrophiesForUser(const AHost: string; APort: Word;
  const AUserID: string; const ATrophies: TArray<TPS4TrophyTitle>;
  ALog: TPS4TrophyLogEvent);
var
  FTP: TIdFTP;
  WorkDir, LocalDb, UserID: string;
  Trophy: TPS4TrophyTitle;
  Db: TPS4TrophyDb;
begin
  if Length(ATrophies) = 0 then
    raise Exception.Create('Nenhum trofeu selecionado.');

  WorkDir := TPath.Combine(TPath.GetTempPath,
    'PS4PKGDownloader_trophy_delete_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
  LocalDb := TPath.Combine(WorkDir, 'trophy_local.db');

  FTP := nil;
  try
    FTP := ConnectFTP(AHost, APort);
    UserID := Trim(AUserID);
    if UserID = '' then
      UserID := ATrophies[0].UserID;
    if UserID = '' then
      UserID := FindTrophyUserID(FTP, LocalDb);
    if UserID = '' then
      raise Exception.Create('Nenhum usuario com trofeus encontrado no PS4.');

    if Assigned(ALog) then ALog('Baixando trophy_local.db para exclusao...');
    if not FileExists(LocalDb) then
      DownloadRemoteDb(FTP, UserID, LocalDb);

    EnsureSQLiteLoaded;
    Db := TPS4TrophyDb.Create(LocalDb);
    try
      for Trophy in ATrophies do
      begin
        if Assigned(ALog) then
          ALog('Excluindo jogo de trofeus: ' + Trophy.TrophyTitleID + ' - ' + Trophy.Title);
        Db.DeleteTitle(Trophy.TrophyTitleID);
        DeleteRemoteDir(FTP, '/user/home/' + UserID + '/trophy/data/' +
          Trophy.TrophyTitleID, ALog);
        DeleteRemoteDir(FTP, '/user/trophy/conf/' + Trophy.TrophyTitleID, ALog);
      end;
    finally
      Db.Free;
    end;

    if Assigned(ALog) then ALog('Enviando trophy_local.db atualizado...');
    UploadRemoteDb(FTP, UserID, LocalDb);
    if Assigned(ALog) then ALog('Limpando cache sce_trop do usuario...');
    ClearRemoteDir(FTP, '/user/home/' + UserID + '/trophy/data/sce_trop', ALog);
  finally
    if Assigned(FTP) and FTP.Connected then FTP.Disconnect;
    FTP.Free;
    try
      TDirectory.Delete(WorkDir, True);
    except
    end;
  end;
end;

procedure DeletePS4Trophies(const AHost: string; APort: Word;
  const ATrophies: TArray<TPS4TrophyTitle>; ALog: TPS4TrophyLogEvent);
begin
  DeletePS4TrophiesForUser(AHost, APort, '', ATrophies, ALog);
end;

procedure SortPS4TrophiesAlphabetically(const AHost: string; APort: Word;
  const AUserID: string; ALog: TPS4TrophyLogEvent);
var
  FTP: TIdFTP;
  WorkDir, LocalDb, UserID: string;
  Db: TPS4TrophyDb;
begin
  WorkDir := TPath.Combine(TPath.GetTempPath,
    'PS4PKGDownloader_trophy_sort_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
  LocalDb := TPath.Combine(WorkDir, 'trophy_local.db');

  FTP := nil;
  try
    FTP := ConnectFTP(AHost, APort);
    UserID := Trim(AUserID);
    if UserID = '' then
      UserID := FindTrophyUserID(FTP, LocalDb)
    else
      DownloadRemoteDb(FTP, UserID, LocalDb);
    if UserID = '' then
      raise Exception.Create('Nenhum usuario com trofeus encontrado no PS4.');

    if Assigned(ALog) then ALog('Ordenando trophy_local.db por nome do jogo...');
    EnsureSQLiteLoaded;
    Db := TPS4TrophyDb.Create(LocalDb);
    try
      Db.SortTitlesAlphabetically;
    finally
      Db.Free;
    end;

    if Assigned(ALog) then ALog('Enviando trophy_local.db ordenado...');
    UploadRemoteDb(FTP, UserID, LocalDb);
  finally
    if Assigned(FTP) and FTP.Connected then FTP.Disconnect;
    FTP.Free;
    try
      TDirectory.Delete(WorkDir, True);
    except
    end;
  end;
end;

procedure BackupPS4TrophyState(const AHost: string; APort: Word;
  const AUserID, ADestDir: string; ALog: TPS4TrophyLogEvent);
var
  FTP: TIdFTP;
  WorkDb, UserID: string;
begin
  if Trim(ADestDir) = '' then
    raise Exception.Create('Pasta de backup nao informada.');

  FTP := nil;
  WorkDb := TPath.Combine(TPath.GetTempPath,
    'PS4PKGDownloader_trophy_backup_probe_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now) + '.db');
  try
    FTP := ConnectFTP(AHost, APort);
    UserID := Trim(AUserID);
    if UserID = '' then
      UserID := FindTrophyUserID(FTP, WorkDb);
    if UserID = '' then
      raise Exception.Create('Nenhum usuario com trofeus encontrado no PS4.');

    if DirectoryExists(ADestDir) then
      TDirectory.Delete(ADestDir, True);
    ForceDirectories(ADestDir);

    if Assigned(ALog) then ALog('Baixando banco de trofeus...');
    DownloadDir(FTP, '/user/home/' + UserID + '/trophy/db',
      TPath.Combine(ADestDir, 'user\home\' + UserID + '\trophy\db'), ALog);
    if Assigned(ALog) then ALog('Baixando dados de trofeus...');
    DownloadDir(FTP, '/user/home/' + UserID + '/trophy/data',
      TPath.Combine(ADestDir, 'user\home\' + UserID + '\trophy\data'), ALog);
    if Assigned(ALog) then ALog('Baixando configuracoes de trofeus...');
    DownloadDir(FTP, '/user/trophy/conf',
      TPath.Combine(ADestDir, 'user\trophy\conf'), ALog);
    WriteTrophyStateBackupInfo(ADestDir, AHost, UserID);
  finally
    if Assigned(FTP) and FTP.Connected then FTP.Disconnect;
    FTP.Free;
    try
      if FileExists(WorkDb) then
        TFile.Delete(WorkDb);
    except
    end;
  end;
end;

procedure RestorePS4TrophyState(const AHost: string; APort: Word;
  const AUserID, ALeftDir: string; ALog: TPS4TrophyLogEvent);
var
  FTP: TIdFTP;
  WorkDb, UserID, LeftUserID, LeftHomeDir: string;
  LocalDbDir, LocalDataDir, LocalConfDir: string;
  LeftUsers: TStringDynArray;
begin
  if not DirectoryExists(ALeftDir) then
    raise Exception.Create('Pasta de backup nao encontrada.');

  FTP := nil;
  WorkDb := TPath.Combine(TPath.GetTempPath,
    'PS4PKGDownloader_trophy_restore_probe_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now) + '.db');
  try
    FTP := ConnectFTP(AHost, APort);
    UserID := Trim(AUserID);
    if UserID = '' then
      UserID := FindTrophyUserID(FTP, WorkDb);
    if UserID = '' then
      raise Exception.Create('Nenhum usuario com trofeus encontrado no PS4.');

    LeftHomeDir := TPath.Combine(ALeftDir, 'user\home');
    LeftUserID := UserID;
    if not DirectoryExists(TPath.Combine(LeftHomeDir, LeftUserID)) then
    begin
      LeftUsers := TDirectory.GetDirectories(LeftHomeDir);
      if Length(LeftUsers) = 0 then
        raise Exception.Create('Backup invalido: nenhum usuario encontrado em user\home.');
      LeftUserID := ExtractFileName(LeftUsers[0]);
    end;

    LocalDbDir := TPath.Combine(ALeftDir, 'user\home\' + LeftUserID + '\trophy\db');
    LocalDataDir := TPath.Combine(ALeftDir, 'user\home\' + LeftUserID + '\trophy\data');
    LocalConfDir := TPath.Combine(ALeftDir, 'user\trophy\conf');
    if not DirectoryExists(LocalDbDir) then
      raise Exception.Create('Backup invalido: pasta trophy\db nao encontrada para o usuario ' + LeftUserID + '.');
    if not DirectoryExists(LocalDataDir) then
      raise Exception.Create('Backup invalido: pasta trophy\data nao encontrada para o usuario ' + LeftUserID + '.');
    if not DirectoryExists(LocalConfDir) then
      raise Exception.Create('Backup invalido: pasta user\trophy\conf nao encontrada.');

    if Assigned(ALog) then ALog('Limpando trofeus atuais do destino...');
    ClearRemoteDir(FTP, '/user/home/' + UserID + '/trophy/db', ALog);
    ClearRemoteDir(FTP, '/user/home/' + UserID + '/trophy/data', ALog);
    ClearRemoteDir(FTP, '/user/trophy/conf', ALog);

    if Assigned(ALog) then ALog('Restaurando banco de trofeus...');
    UploadDir(FTP, LocalDbDir, '/user/home/' + UserID + '/trophy/db', ALog);
    if Assigned(ALog) then ALog('Restaurando dados de trofeus...');
    UploadDir(FTP, LocalDataDir, '/user/home/' + UserID + '/trophy/data', ALog);
    if Assigned(ALog) then ALog('Restaurando configuracoes de trofeus...');
    UploadDir(FTP, LocalConfDir, '/user/trophy/conf', ALog);
    DeleteRemoteFileIfExists(FTP, '/user/home/' + UserID + '/trophy/db/trophy_local.db-wal', nil);
    DeleteRemoteFileIfExists(FTP, '/user/home/' + UserID + '/trophy/db/trophy_local.db-shm', nil);
    DeleteRemoteFileIfExists(FTP, '/user/home/' + UserID + '/trophy/db/trophy_local.db-journal', nil);
  finally
    if Assigned(FTP) and FTP.Connected then FTP.Disconnect;
    FTP.Free;
    try
      if FileExists(WorkDb) then
        TFile.Delete(WorkDb);
    except
    end;
  end;
end;

end.
