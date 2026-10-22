unit UnitFunctions;

interface

uses
  System.Classes, System.SysUtils, System.IOUtils, System.Types, System.DateUtils,
  System.Generics.Collections, System.Generics.Defaults,
  IdFTP, IdFTPCommon, IdFTPList, IdTCPClient;

type
  TPS4SaveUser = record
    UserID: string;
    DisplayName: string;
  end;

  TPS4SaveGame = record
    Title: string;
    UserDisplayName: string;
    TitleID: string;
    SaveName: string;
    UserID: string;
    ModifiedAt: TDateTime;
    RemotePath: string;
    RemoteImagePath: string;
    RemoteMetaPath: string;
  end;

  TPS4ConsoleInfo = record
    Name: string;
    IP: string;
  end;

  TPS4SaveLogEvent = procedure(const AMsg: string) of object;

function DiscoverPS4Consoles(const ABaseIP: string; APort: Word;
  ALog: TPS4SaveLogEvent): TArray<TPS4ConsoleInfo>;
function ListPS4Users(const AHost: string; APort: Word): TArray<TPS4SaveUser>;
function ListPS4SaveGames(const AHost: string; APort: Word): TArray<TPS4SaveGame>;
function ListPS4SaveGamesForUser(const AHost: string; APort: Word;
  const AUserID: string): TArray<TPS4SaveGame>;
function PS4SaveDisplayText(const ASave: TPS4SaveGame): string;
procedure BackupPS4Saves(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestFolder: string;
  ALog: TPS4SaveLogEvent);
procedure ImportPS4SaveBackup(const AHost, AUserID, ABackupFolder: string;
  AAutomatic: Boolean; ALog: TPS4SaveLogEvent);
procedure BackupPS4Trophies(const AHost: string; APort: Word;
  const ADestFolder: string; ALog: TPS4SaveLogEvent);
procedure DeletePS4Saves(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; ALog: TPS4SaveLogEvent);
procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; ALog: TPS4SaveLogEvent); overload;
procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestUserID: string;
  ALog: TPS4SaveLogEvent); overload;
procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  ALog: TPS4SaveLogEvent); overload;

type
  TPS4SaveAgentLogEvent = procedure(const AMsg: string) of object;
  TPS4SaveAgentProgressEvent = procedure(const AMsg: string;
    APosition, AMax: Int64) of object;

procedure DownloadDecryptedSave(const AHost: string; const ASave: TPS4SaveGame;
  const ALocalZip: string; ALog: TPS4SaveAgentLogEvent;
  AProgress: TPS4SaveAgentProgressEvent);

procedure ExportPS4SavesDecrypted(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestFolder: string;
  ALog: TPS4SaveAgentLogEvent; AProgress: TPS4SaveAgentProgressEvent);

function PS4SaveAgentLocalPath: string;
function PS4SaveAgentRemotePath: string;
procedure EnsurePS4SaveAgentInstalled(const AHost: string;
  ALog: TPS4SaveAgentLogEvent);
procedure EnsurePS4SaveAgentReady(const AHost: string;
  ALog: TPS4SaveAgentLogEvent);
procedure EnsurePS4SaveAgentCurrent(const AHost: string;
  ALog: TPS4SaveAgentLogEvent);
function GetPS4SaveAgentAccountID(const AHost, AUserID: string;
  ALog: TPS4SaveAgentLogEvent): string;
procedure DeletePS4SaveWithAgent(const AHost: string;
  const ASave: TPS4SaveGame; ALog: TPS4SaveAgentLogEvent);
procedure CleanupPS4StaleSavesWithAgent(const AHost, AUserID: string;
  ALog: TPS4SaveAgentLogEvent);
procedure SyncPS4SavesDecrypted(const ALeftHost, ADestHost: string;
  const ALeftUserID, ADestUserID: string; const ASaves: TArray<TPS4SaveGame>;
  const ABackupRoot: string; ALog: TPS4SaveAgentLogEvent;
  AProgress: TPS4SaveAgentProgressEvent);
procedure SyncPS4SavesOnConsole(const AHost: string;
  const ALeftUserID, ADestUserID: string; const ASaves: TArray<TPS4SaveGame>;
  ALog: TPS4SaveAgentLogEvent);

{ Remocao de fundo por IA. Gera um PNG com canal alfa; a imagem original nunca
  e alterada. Usa o rembg local (offline) e, so se ele nao estiver instalado e
  houver uma chave configurada, a API remove.bg. }
{ bmFigure: logos/ilustracoes (fundo plano -> IA). bmHumanFace: foto de rosto
  humano (modelo de pessoas + refino da mascara). }
type
  TBgMode = (bmFigure, bmHumanFace);

function RemoveImageBackground(const AInputFile, AOutputFile: string;
  AMode: TBgMode; out AErrorMessage: string): Boolean; overload;
function RemoveImageBackground(const AInputFile, AOutputFile: string;
  out AErrorMessage: string): Boolean; overload;
function RemoveImageBackground(const AInputFile, AOutputFile: string): Boolean; overload;
function RemoveImageBackgroundBatch(const AInputFiles: TArray<string>;
  const AOutputDir: string; ALog: TPS4SaveLogEvent): Integer;
function PngFileHasTransparency(const AFileName: string): Boolean;
function PngTransparencyShare(const AFileName: string): Double;

implementation

uses
  System.NetEncoding, System.IniFiles,
  System.Net.URLClient, System.Net.HttpClient, System.Net.Mime,
  Vcl.Forms, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg,
  System.StrUtils, System.Sqlite, Winapi.Windows,
  IdComponent, IdException, IdExceptionCore, IdGlobal, IdHTTP,
  IdMultipartFormData, IdURI, IdStack,
  { Vcl.Graphics por ultimo: Winapi.Windows declara um TBitmap proprio
    (tagBITMAP) e a unit listada depois vence na resolucao do nome. }
  Vcl.Graphics;

type
  TAppDbCellArray = array[0..(MaxInt div SizeOf(MarshaledAString) - 1)] of MarshaledAString;
  PAppDbCellArray = ^TAppDbCellArray;

  TPS4UserInfo = record
    UserID: string;
    DisplayName: string;
  end;

  TPS4TitleInfo = record
    TitleID: string;
    TitleName: string;
  end;

function LooksLikeAnyTitleID(const S: string): Boolean;
var
  LValue: string;
  I: Integer;
begin
  LValue := UpperCase(Trim(S));
  Result := Length(LValue) = 9;
  if not Result then
    Exit;
  for I := 1 to 4 do
    if not CharInSet(LValue[I], ['A'..'Z']) then
      Exit(False);
  for I := 5 to 9 do
    if not CharInSet(LValue[I], ['0'..'9']) then
      Exit(False);
end;

function ResolveGameTitleOnline(const ATitleID: string): string;
begin
  Result := UpperCase(Trim(ATitleID));
end;

function AppDbQuoteIdent(const AValue: string): string;
begin
  Result := '"' + StringReplace(AValue, '"', '""', [rfReplaceAll]) + '"';
end;

function AppDbUtf8(const AValue: MarshaledAString): string;
begin
  if AValue = nil then
    Result := ''
  else
    Result := string(UTF8String(AValue));
end;

function AppDbQuery(const ADb: sqlite3; const ASQL: string): TStringList;
var
  Code, Rows, Cols, I, J: Integer;
  Table: PMarshaledAString;
  ErrorText: MarshaledAString;
  Cells: PAppDbCellArray;
  Utf8Sql: UTF8String;
  Line: string;
begin
  Result := TStringList.Create;
  Table := nil;
  ErrorText := nil;
  Utf8Sql := UTF8String(ASQL);
  Code := sqlite3_get_table(ADb, PAnsiChar(Utf8Sql), @Table, Rows, Cols, @ErrorText);
  if Code <> SQLITE_OK then
  begin
    try
      if ErrorText <> nil then
        raise Exception.Create('Falha ao consultar app.db: ' + AppDbUtf8(ErrorText))
      else
        raise Exception.CreateFmt('Falha ao consultar app.db (%d).', [Code]);
    finally
      if ErrorText <> nil then sqlite3_free(ErrorText);
      Result.Free;
    end;
  end;
  try
    Cells := PAppDbCellArray(Table);
    for I := 1 to Rows do
    begin
      Line := '';
      for J := 0 to Cols - 1 do
      begin
        if J > 0 then Line := Line + #9;
        Line := Line + AppDbUtf8(Cells[(I * Cols) + J]);
      end;
      Result.Add(Line);
    end;
  finally
    if Table <> nil then sqlite3_free_table(Table);
  end;
end;

function AppDbColumnExists(const ADb: sqlite3; const ATable, AColumn: string): Boolean;
var
  Rows: TStringList;
  Parts: TArray<string>;
  I: Integer;
begin
  Result := False;
  Rows := AppDbQuery(ADb, 'PRAGMA table_info(' + AppDbQuoteIdent(ATable) + ')');
  try
    for I := 0 to Rows.Count - 1 do
    begin
      Parts := Rows[I].Split([#9]);
      if (Length(Parts) > 1) and SameText(Parts[1], AColumn) then
        Exit(True);
    end;
  finally
    Rows.Free;
  end;
end;

function AppDbReadDisplayName(const ADb: sqlite3; const AUserID: string): string;
const
  Tables: array[0..3] of string = ('tbl_user', 'tbl_account', 'tbl_accountinfo', 'tbl_userinfo');
  IDColumns: array[0..9] of string = ('userId', 'userid', 'user_id', 'id', 'accountId',
    'account_id', 'localUserId', 'local_user_id', 'loginUserId', 'login_user_id');
  NameColumns: array[0..13] of string = ('onlineId', 'onlineID', 'online_id', 'npOnlineId',
    'np_online_id', 'userName', 'username', 'name', 'nickName', 'nickname', 'displayName',
    'display_name', 'accountName', 'account_name');
var
  Table, IDColumn, NameColumn, WantedHex, WantedDec, RowID, RowName: string;
  Rows: TStringList;
  Parts: TArray<string>;
  I: Integer;
  WantedNumber, NumberValue: UInt64;
  function Matches(const AValue: string): Boolean;
  begin
    Result := SameText(Trim(AValue), AUserID) or SameText(Trim(AValue), WantedHex) or
      ((WantedDec <> '') and SameText(Trim(AValue), WantedDec));
    if Result then Exit;
    if TryStrToUInt64(Trim(AValue), NumberValue) then
      Result := SameText(IntToHex(NumberValue, 8), WantedHex)
    else
      Result := False;
  end;
begin
  Result := '';
  WantedHex := LowerCase(Trim(AUserID));
  WantedDec := '';
  if TryStrToUInt64('$' + WantedHex, WantedNumber) then
    WantedDec := UIntToStr(WantedNumber);
  for Table in Tables do
    for IDColumn in IDColumns do
      for NameColumn in NameColumns do
        if AppDbColumnExists(ADb, Table, IDColumn) and AppDbColumnExists(ADb, Table, NameColumn) then
        begin
          Rows := AppDbQuery(ADb, 'SELECT CAST(' + AppDbQuoteIdent(IDColumn) + ' AS TEXT), ' +
            AppDbQuoteIdent(NameColumn) + ' FROM ' + AppDbQuoteIdent(Table));
          try
            for I := 0 to Rows.Count - 1 do
            begin
              Parts := Rows[I].Split([#9]);
              if Length(Parts) < 2 then Continue;
              RowID := Trim(Parts[0]); RowName := Trim(Parts[1]);
              if (RowName <> '') and Matches(RowID) then Exit(RowName);
            end;
          finally
            Rows.Free;
          end;
        end;
end;

function AppDbDownload(const AHost: string; APort: Word;
  AForceRefresh: Boolean = False): string;
var
  FTP: TIdFTP;
  FileName: string;
  CacheHost: string;
begin
  Result := '';
  CacheHost := StringReplace(Trim(AHost), '.', '_', [rfReplaceAll]);
  CacheHost := StringReplace(CacheHost, ':', '_', [rfReplaceAll]);
  FileName := TPath.Combine(TPath.GetTempPath, 'PS4Tools_app_' + CacheHost + '.db');
  if (not AForceRefresh) and TFile.Exists(FileName) and
     (MinutesBetween(Now, TFile.GetLastWriteTime(FileName)) < 30) then
  begin
    Result := FileName;
    Exit;
  end;
  FTP := TIdFTP.Create(nil);
  try
    FTP.Host := Trim(AHost); FTP.Port := APort; FTP.Username := 'anonymous';
    FTP.Password := 'anonymous@'; FTP.Passive := True; FTP.TransferType := ftBinary;
    FTP.ConnectTimeout := 5000; FTP.ReadTimeout := 15000; FTP.Connect;
    FTP.Get('/system_data/priv/mms/app.db', FileName, True);
    Result := FileName;
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;
end;

function NormalizeGameTitle(const ATitle: string): string;
const
  LOWER_WORDS: array[0..15] of string = (
    'a', 'an', 'and', 'at', 'by', 'da', 'das', 'de', 'do', 'dos',
    'for', 'in', 'of', 'on', 'the', 'to');
var
  Text: string;
  WordText: string;
  I, StartPos: Integer;
  IsFirstWord: Boolean;
  KeepLower: Boolean;
begin
  Text := LowerCase(Trim(ATitle));
  Result := '';
  I := 1;
  IsFirstWord := True;
  while I <= Length(Text) do
  begin
    if CharInSet(Text[I], ['a'..'z', 'A'..'Z', #$00C0..#$00FF]) then
    begin
      StartPos := I;
      while (I <= Length(Text)) and
        CharInSet(Text[I], ['a'..'z', 'A'..'Z', #$00C0..#$00FF]) do
        Inc(I);
      WordText := Copy(Text, StartPos, I - StartPos);
      KeepLower := False;
      for StartPos := Low(LOWER_WORDS) to High(LOWER_WORDS) do
        if SameText(WordText, LOWER_WORDS[StartPos]) then
        begin
          KeepLower := True;
          Break;
        end;
      if (not IsFirstWord) and KeepLower then
        WordText := LowerCase(WordText)
      else if WordText <> '' then
        WordText := UpperCase(WordText[1]) + LowerCase(Copy(WordText, 2, MaxInt));
      Result := Result + WordText;
      IsFirstWord := False;
    end
    else
    begin
      Result := Result + Text[I];
      Inc(I);
    end;
  end;
end;

function ReadPS4UsernameFiles(const AHost: string; APort: Word;
  const AUserIDs: TArray<string>): TArray<string>;
var
  FTP: TIdFTP;
  TempFile: string;
  Lines: TStringList;
  I: Integer;
begin
  SetLength(Result, Length(AUserIDs));
  FTP := TIdFTP.Create(nil);
  try
    FTP.Host := Trim(AHost);
    FTP.Port := APort;
    FTP.Username := 'anonymous';
    FTP.Password := 'anonymous@';
    FTP.Passive := True;
    FTP.TransferType := ftBinary;
    FTP.ConnectTimeout := 5000;
    FTP.ReadTimeout := 15000;
    FTP.Connect;
    for I := 0 to High(AUserIDs) do
    begin
      TempFile := TPath.Combine(TPath.GetTempPath,
        'PS4Tools_user_' + IntToStr(GetTickCount) + '_' + IntToStr(I) + '.dat');
      try
        FTP.Get('/user/home/' + AUserIDs[I] + '/username.dat', TempFile, True);
        Lines := TStringList.Create;
        try
          Lines.LoadFromFile(TempFile, TEncoding.UTF8);
          if Lines.Count > 0 then
            Result[I] := Trim(Lines[0]);
        finally
          Lines.Free;
        end;
      except
        Result[I] := '';
      end;
      if TFile.Exists(TempFile) then
        TFile.Delete(TempFile);
    end;
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;
end;

function ResolvePS4UserDisplayNamesFromAppDb(const AHost: string;
  APort: Word; const AUserIDs: TArray<string>): TArray<TPS4UserInfo>;
var
  DbFile: string;
  Db: sqlite3;
  Code, I: Integer;
  Utf8Name: UTF8String;
  UserNames: TArray<string>;
begin
  SetLength(Result, Length(AUserIDs));
  if Length(AUserIDs) = 0 then Exit;
  UserNames := ReadPS4UsernameFiles(AHost, APort, AUserIDs);
  for I := 0 to High(AUserIDs) do
  begin
    Result[I].UserID := AUserIDs[I];
    Result[I].DisplayName := UserNames[I];
  end;

  try
    DbFile := AppDbDownload(AHost, APort, False);
  except
    Exit;
  end;
  Db := nil;
  try
    if GetModuleHandle('sqlite3.dll') = 0 then
      LoadLibrary(PChar(TPath.Combine(ExtractFileDir(ParamStr(0)), 'sqlite3.dll')));
    Utf8Name := UTF8String(DbFile);
    Code := sqlite3_open_v2(PAnsiChar(Utf8Name), Db, SQLITE_OPEN_READONLY or SQLITE_OPEN_FULLMUTEX, nil);
    if Code <> SQLITE_OK then
      raise Exception.CreateFmt('Não foi possível abrir o app.db do PS4 (%d).', [Code]);
    try
      for I := 0 to High(AUserIDs) do
      begin
        if Result[I].DisplayName = '' then
          Result[I].DisplayName := AppDbReadDisplayName(Db, AUserIDs[I]);
        if Result[I].DisplayName = '' then Result[I].DisplayName := AUserIDs[I];
      end;
    finally
      sqlite3_close(Db);
      Db := nil;
    end;
  finally
    if Db <> nil then sqlite3_close(Db);
  end;
end;

function ResolvePS4TitleNamesFromAppDb(const AHost: string; APort: Word;
  AForceRefresh: Boolean = False): TArray<TPS4TitleInfo>;
var
  DbFile: string;
  Db: sqlite3;
  Code, I, J: Integer;
  Utf8Name: UTF8String;
  Tables, Rows: TStringList;
  Parts: TArray<string>;
  Title: TPS4TitleInfo;
begin
  SetLength(Result, 0);
  DbFile := '';
  Db := nil;
  try
    DbFile := AppDbDownload(AHost, APort, AForceRefresh);
    if GetModuleHandle('sqlite3.dll') = 0 then
      LoadLibrary(PChar(TPath.Combine(ExtractFileDir(ParamStr(0)), 'sqlite3.dll')));
    Utf8Name := UTF8String(DbFile);
    Code := sqlite3_open_v2(PAnsiChar(Utf8Name), Db,
      SQLITE_OPEN_READONLY or SQLITE_OPEN_FULLMUTEX, nil);
    if Code <> SQLITE_OK then
      Exit;

    Tables := AppDbQuery(Db,
      'SELECT name FROM sqlite_master WHERE type = ''table'' AND name LIKE ''tbl_appbrowse_%''');
    try
      for I := 0 to Tables.Count - 1 do
      begin
        Rows := AppDbQuery(Db, 'SELECT titleId, titleName FROM ' +
          AppDbQuoteIdent(Tables[I]));
        try
          for J := 0 to Rows.Count - 1 do
          begin
            Parts := Rows[J].Split([#9]);
            if (Length(Parts) < 2) or (Trim(Parts[0]) = '') or
               (Trim(Parts[1]) = '') then
              Continue;
            Title.TitleID := UpperCase(Trim(Parts[0]));
            Title.TitleName := NormalizeGameTitle(Trim(Parts[1]));
            SetLength(Result, Length(Result) + 1);
            Result[High(Result)] := Title;
          end;
        finally
          Rows.Free;
        end;
      end;
    finally
      Tables.Free;
    end;
  finally
    if Db <> nil then sqlite3_close(Db);
  end;
end;

const
  PS4_FTP_USER = 'anonymous';
  PS4_FTP_PASS = 'anonymous@';
  APOLLO_FAKEUSB_ACCOUNT_ID = '0000000000000000';
  PS4_USER_ROOT = '/user';

function LooksLikePS4TitleID(const S: string): Boolean;
var
  T: string;
  I: Integer;
begin
  T := UpperCase(Trim(S));
  Result := (Length(T) = 9) and (Copy(T, 1, 4) = 'CUSA');
  if not Result then Exit;
  for I := 5 to 9 do
    if not CharInSet(T[I], ['0'..'9']) then
      Exit(False);
end;

function LooksLikePS4UserID(const S: string): Boolean;
var
  T: string;
  I: Integer;
begin
  T := LowerCase(Trim(S));
  Result := Length(T) = 8;
  if not Result then Exit;
  for I := 1 to Length(T) do
    if not CharInSet(T[I], ['0'..'9', 'a'..'f']) then
      Exit(False);
end;

function NormalizeRemotePath(const S: string): string;
begin
  Result := StringReplace(S, '\', '/', [rfReplaceAll]);
  while Pos('//', Result) > 0 do
    Result := StringReplace(Result, '//', '/', [rfReplaceAll]);
  if (Result = '') or (Result[1] <> '/') then
    Result := '/' + Result;
  if (Length(Result) > 1) and (Result[Length(Result)] = '/') then
    Delete(Result, Length(Result), 1);
end;

function RemoteCombine(const ABase, AName: string): string;
begin
  Result := NormalizeRemotePath(IncludeTrailingPathDelimiter(
    StringReplace(ABase, '/', '\', [rfReplaceAll])) + AName);
end;

function RemoteDirName(const ARemoteFile: string): string;
var
  P: Integer;
begin
  Result := NormalizeRemotePath(ARemoteFile);
  P := LastDelimiter('/', Result);
  if P > 1 then
    Result := Copy(Result, 1, P - 1)
  else
    Result := '/';
end;

function RemoteFileName(const ARemoteFile: string): string;
var
  P: Integer;
begin
  Result := NormalizeRemotePath(ARemoteFile);
  P := LastDelimiter('/', Result);
  if P > 0 then
    Result := Copy(Result, P + 1, MaxInt);
end;

function ExeTempRoot(const ANamePrefix: string): string;
begin
  Result := TPath.Combine(ExtractFileDir(ParamStr(0)), 'tmp');
  Result := TPath.Combine(Result, ANamePrefix + '_' +
    FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
end;

function IsPS4SaveImageFile(const AName: string; out ASaveName: string): Boolean;
const
  SDIMG_PREFIX = 'sdimg_';
begin
  Result := False;
  ASaveName := '';
  if not SameText(Copy(AName, 1, Length(SDIMG_PREFIX)), SDIMG_PREFIX) then Exit;

  ASaveName := Copy(AName, Length(SDIMG_PREFIX) + 1, MaxInt);
  Result := (ASaveName <> '') and
            not SameText(Copy(ASaveName, 1, 7), 'sce_bu_');
end;

function ApolloSaveFolderName(const ASave: TPS4SaveGame): string;
const
  INVALID_CHARS: TSysCharSet = ['\', '/', ':', '*', '?', '"', '<', '>', '|'];
var
  I: Integer;
begin
  Result := ASave.UserID + '_' + ASave.TitleID;
  if Trim(ASave.SaveName) <> '' then
    Result := Result + '_' + ASave.SaveName;
  for I := 1 to Length(Result) do
    if CharInSet(Result[I], INVALID_CHARS) then
      Result[I] := '_';
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

function LE32(const B: TBytes; O: Integer): UInt32; inline;
begin
  Result := UInt32(B[O]) or (UInt32(B[O+1]) shl 8) or
            (UInt32(B[O+2]) shl 16) or (UInt32(B[O+3]) shl 24);
end;

function LE16(const B: TBytes; O: Integer): Word; inline;
begin
  Result := Word(B[O]) or (Word(B[O+1]) shl 8);
end;

procedure PutLE32(var B: TBytes; O: Integer; V: UInt32); inline;
begin
  B[O] := Byte(V and $FF);
  B[O+1] := Byte((V shr 8) and $FF);
  B[O+2] := Byte((V shr 16) and $FF);
  B[O+3] := Byte((V shr 24) and $FF);
end;

function TryHexUserIDToUInt32(const AUserID: string; out AValue: UInt32): Boolean;
var
  N: UInt64;
begin
  Result := TryStrToUInt64('$' + Trim(AUserID), N) and (N <= High(UInt32));
  if Result then
    AValue := UInt32(N)
  else
    AValue := 0;
end;

function TryFindSfoEntry(const ASfo: TBytes; const AKey: string; out ADataOffset,
  ADataLen, ADataMaxLen: Integer): Boolean;
const
  SFO_MAGIC = $46535000;
var
  KeyTblOff, DataTblOff, Count: UInt32;
  I, EntryBase: Integer;
  KeyOff: Word;
  DataLen, DataMaxLen, DataOff, KO: UInt32;
  KStr: string;
begin
  Result := False;
  ADataOffset := 0;
  ADataLen := 0;
  ADataMaxLen := 0;
  if Length(ASfo) < 20 then Exit;
  if LE32(ASfo, 0) <> SFO_MAGIC then Exit;
  KeyTblOff := LE32(ASfo, 8);
  DataTblOff := LE32(ASfo, 12);
  Count := LE32(ASfo, 16);

  for I := 0 to Integer(Count) - 1 do
  begin
    EntryBase := 20 + I * 16;
    if EntryBase + 16 > Length(ASfo) then Break;
    KeyOff := LE16(ASfo, EntryBase);
    DataLen := LE32(ASfo, EntryBase + 4);
    DataMaxLen := LE32(ASfo, EntryBase + 8);
    DataOff := LE32(ASfo, EntryBase + 12);

    KO := KeyTblOff + KeyOff;
    KStr := '';
    while (KO < UInt32(Length(ASfo))) and (ASfo[KO] <> 0) do
    begin
      KStr := KStr + Char(ASfo[KO]);
      Inc(KO);
    end;

    if SameText(KStr, AKey) then
    begin
      ADataOffset := Integer(DataTblOff + DataOff);
      ADataLen := Integer(DataLen);
      ADataMaxLen := Integer(DataMaxLen);
      Result := (ADataOffset >= 0) and (ADataOffset < Length(ASfo));
      Exit;
    end;
  end;
end;

function SfoGetString(const ASfo: TBytes; const AKey: string): string;
const
  SFO_MAGIC = $46535000;
var
  KeyTblOff, DataTblOff, Count: UInt32;
  I, EntryBase, Len: Integer;
  KeyOff: Word;
  DataLen: UInt32;
  DataOff, VStart, KO: UInt32;
  KStr: string;
  ValueBytes: TBytes;
begin
  Result := '';
  if Length(ASfo) < 20 then Exit;
  if LE32(ASfo, 0) <> SFO_MAGIC then Exit;
  KeyTblOff := LE32(ASfo, 8);
  DataTblOff := LE32(ASfo, 12);
  Count := LE32(ASfo, 16);

  for I := 0 to Integer(Count) - 1 do
  begin
    EntryBase := 20 + I * 16;
    if EntryBase + 16 > Length(ASfo) then Break;
    KeyOff := LE16(ASfo, EntryBase);
    DataLen := LE32(ASfo, EntryBase + 4);
    DataOff := LE32(ASfo, EntryBase + 12);

    KO := KeyTblOff + KeyOff;
    KStr := '';
    while (KO < UInt32(Length(ASfo))) and (ASfo[KO] <> 0) do
    begin
      KStr := KStr + Char(ASfo[KO]);
      Inc(KO);
    end;

    if SameText(KStr, AKey) then
    begin
      VStart := DataTblOff + DataOff;
      Len := 0;
      while (VStart + UInt32(Len) < UInt32(Length(ASfo))) and
            (ASfo[VStart + UInt32(Len)] <> 0) and
            (Len < Integer(DataLen)) do
        Inc(Len);
      if Len <= 0 then Exit;
      SetLength(ValueBytes, Len);
      Move(ASfo[VStart], ValueBytes[0], Len);
      Result := TEncoding.UTF8.GetString(ValueBytes);
      Exit;
    end;
  end;
end;

function TryReadRemoteSfo(AFTP: TIdFTP; const ARemoteFile: string; out ASfo: TBytes): Boolean;
var
  MS: TMemoryStream;
  DirName: string;
  FileName: string;
  I: Integer;
  Found: Boolean;
begin
  Result := False;
  SetLength(ASfo, 0);

  DirName := RemoteDirName(ARemoteFile);
  FileName := RemoteFileName(ARemoteFile);
  Found := False;
  if (DirName = '') or (FileName = '') or not TryListDir(AFTP, DirName) then Exit;
  for I := 0 to AFTP.DirectoryListing.Count - 1 do
    if (AFTP.DirectoryListing[I].ItemType <> ditDirectory) and
       SameText(AFTP.DirectoryListing[I].FileName, FileName) then
    begin
      Found := True;
      Break;
    end;
  if not Found then Exit;

  MS := TMemoryStream.Create;
  try
    try
      AFTP.Get(ARemoteFile, MS, False);
      if (MS.Size <= 0) or (MS.Size > 1024 * 1024) then Exit;
      MS.Position := 0;
      SetLength(ASfo, MS.Size);
      MS.ReadBuffer(ASfo[0], MS.Size);
      Result := True;
    except
      Result := False;
    end;
  finally
    MS.Free;
  end;
end;

function TryReadTitleFromSfo(AFTP: TIdFTP; const ARemoteFile: string): string;
var
  Sfo: TBytes;
begin
  Result := '';
  if TryReadRemoteSfo(AFTP, ARemoteFile, Sfo) then
  begin
    Result := Trim(SfoGetString(Sfo, 'TITLE'));
    if Result = '' then
      Result := Trim(SfoGetString(Sfo, 'SAVEDATA_TITLE'));
    if Result = '' then
      Result := Trim(SfoGetString(Sfo, 'SUB_TITLE'));
  end;
end;

function TryReadTitleFromSaveFolder(AFTP: TIdFTP; const ASavePath: string): string;
var
  Names: TStringList;
  IsDir: TList<Boolean>;
  I: Integer;
  Name, RemotePath: string;
begin
  Result := TryReadTitleFromSfo(AFTP, ASavePath + '/sce_sys/param.sfo');
  if Result <> '' then Exit;

  Names := TStringList.Create;
  IsDir := TList<Boolean>.Create;
  try
    if not TryListDir(AFTP, ASavePath) then Exit;
    for I := 0 to AFTP.DirectoryListing.Count - 1 do
    begin
      Name := AFTP.DirectoryListing[I].FileName;
      if (Name = '.') or (Name = '..') then Continue;
      Names.Add(Name);
      IsDir.Add(AFTP.DirectoryListing[I].ItemType = ditDirectory);
    end;

    for I := 0 to Names.Count - 1 do
    begin
      if not IsDir[I] then Continue;
      RemotePath := ASavePath + '/' + Names[I] + '/sce_sys/param.sfo';
      Result := TryReadTitleFromSfo(AFTP, RemotePath);
      if Result <> '' then Exit;
    end;
  finally
    IsDir.Free;
    Names.Free;
  end;
end;

function TryReadSaveGameTitle(AFTP: TIdFTP; const ATitleID, ASavePath: string): string;
begin
  Result := TryReadTitleFromSfo(AFTP, PS4_USER_ROOT + '/appmeta/' + ATitleID + '/param.sfo');
  if Result <> '' then Exit;

  Result := TryReadTitleFromSfo(AFTP, PS4_USER_ROOT + '/app/' + ATitleID + '/sce_sys/param.sfo');
  if Result <> '' then Exit;

  Result := TryReadTitleFromSfo(AFTP, PS4_USER_ROOT + '/app/' + ATitleID + '/param.sfo');
  if Result <> '' then Exit;

  Result := TryReadTitleFromSaveFolder(AFTP, ASavePath);
end;

function TryGetConsoleName(const AHost: string): string;
begin
  Result := 'PS4 ' + AHost;
end;

function IPPrefix(const AIP: string): string;
var
  P: Integer;
begin
  Result := Trim(AIP);
  P := LastDelimiter('.', Result);
  if P > 0 then
    Result := Copy(Result, 1, P);
end;

function DiscoverPS4Consoles(const ABaseIP: string; APort: Word;
  ALog: TPS4SaveLogEvent): TArray<TPS4ConsoleInfo>;
var
  Prefix, Host: string;
  I: Integer;
  TCP: TIdTCPClient;
  FTP: TIdFTP;
  Item: TPS4ConsoleInfo;
begin
  SetLength(Result, 0);
  Prefix := IPPrefix(ABaseIP);
  if Prefix = '' then Exit;

  TCP := TIdTCPClient.Create(nil);
  try
    TCP.ConnectTimeout := 180;
    TCP.ReadTimeout := 180;
    for I := 1 to 254 do
    begin
      Host := Prefix + IntToStr(I);
      if Assigned(ALog) and ((I = 1) or (I mod 32 = 0)) then
        ALog('Buscando consoles na rede: ' + Host);

      try
        TCP.Host := Host;
        TCP.Port := APort;
        TCP.Connect;
        TCP.Disconnect;

        FTP := ConnectFTP(Host, APort);
        try
          SetLength(Result, Length(Result) + 1);
          Item.IP := Host;
          Item.Name := TryGetConsoleName(Host);
          Result[High(Result)] := Item;
          if Assigned(ALog) then
            ALog('Encontrado: ' + Item.Name);
        finally
          if FTP.Connected then FTP.Disconnect;
          FTP.Free;
        end;
      except
        try
          if TCP.Connected then TCP.Disconnect;
        except
        end;
      end;
    end;
  finally
    TCP.Free;
  end;
end;

function FindUserDisplayName(const AUsers: TArray<TPS4SaveUser>;
  const AUserID: string): string;
var
  User: TPS4SaveUser;
begin
  Result := '';
  for User in AUsers do
    if SameText(User.UserID, AUserID) then
      Exit(User.DisplayName);
end;

function PS4SaveGameTitle(const ASave: TPS4SaveGame): string;
begin
  Result := Trim(ASave.Title);
  if Result = '' then
    Result := ASave.TitleID;
end;

function PS4SaveDisplayText(const ASave: TPS4SaveGame): string;
var
  DateText: string;
begin
  if ASave.ModifiedAt > 0 then
    DateText := FormatDateTime('yyyy.mm.dd_hh:nn:ss', ASave.ModifiedAt)
  else
    DateText := 'sem data - sem hora';

  Result := Format('%s (%s) [%s] - %s (%s (%s))',
    [PS4SaveGameTitle(ASave), ASave.TitleID, DateText, ASave.SaveName,
     ASave.UserDisplayName, ASave.UserID]);
end;

function ComparePS4SaveGames(const Left, Right: TPS4SaveGame): Integer;
begin
  Result := CompareText(PS4SaveGameTitle(Left), PS4SaveGameTitle(Right));
  if Result <> 0 then Exit;

  if Left.ModifiedAt > Right.ModifiedAt then
    Exit(-1);
  if Left.ModifiedAt < Right.ModifiedAt then
    Exit(1);

  Result := CompareText(Left.TitleID, Right.TitleID);
  if Result <> 0 then Exit;

  Result := CompareText(Left.SaveName, Right.SaveName);
end;

function ListPS4Users(const AHost: string; APort: Word): TArray<TPS4SaveUser>;
var
  FTP: TIdFTP;
  AppDbUsers: TArray<TPS4UserInfo>;
  AppDbUser: TPS4UserInfo;
  User: TPS4SaveUser;
  UserIDs: TArray<string>;
  I: Integer;
begin
  SetLength(Result, 0);
  SetLength(UserIDs, 0);

  FTP := ConnectFTP(AHost, APort);
  try
    if TryListDir(FTP, '/user/home') then
      for I := 0 to FTP.DirectoryListing.Count - 1 do
      begin
        if (FTP.DirectoryListing[I].FileName = '.') or
           (FTP.DirectoryListing[I].FileName = '..') then Continue;
        if (FTP.DirectoryListing[I].ItemType = ditDirectory) and
           LooksLikePS4UserID(FTP.DirectoryListing[I].FileName) then
        begin
          SetLength(UserIDs, Length(UserIDs) + 1);
          UserIDs[High(UserIDs)] := FTP.DirectoryListing[I].FileName;
        end;
      end;
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;

  try
    AppDbUsers := ResolvePS4UserDisplayNamesFromAppDb(AHost, APort, UserIDs);
  except
    SetLength(AppDbUsers, 0);
  end;

  SetLength(Result, Length(UserIDs));
  for I := 0 to High(UserIDs) do
  begin
    User.UserID := UserIDs[I];
    User.DisplayName := User.UserID;
    for AppDbUser in AppDbUsers do
      if SameText(AppDbUser.UserID, User.UserID) then
      begin
        if Trim(AppDbUser.DisplayName) <> '' then
          User.DisplayName := AppDbUser.DisplayName;
        Break;
      end;
    Result[I] := User;
  end;
end;

function ListPS4SaveGamesInternal(const AHost: string; APort: Word;
  const AOnlyUserID: string): TArray<TPS4SaveGame>;
var
  FTP: TIdFTP;
  Users, Titles, SaveNames: TStringList;
  SaveUsers: TArray<TPS4SaveUser>;
  AppDbTitles: TArray<TPS4TitleInfo>;
  TitleMap: TDictionary<string, string>;
  AppDbTitle: TPS4TitleInfo;
  I, J, K: Integer;
  RefreshedTitleMap: Boolean;
  ModifiedAt: TDateTime;
  UserID, TitleID, SaveRoot, TitlePath, SaveName, TitleName: string;
  Save: TPS4SaveGame;
begin
  SetLength(Result, 0);
  Users := TStringList.Create;
  Titles := TStringList.Create;
  SaveNames := TStringList.Create;
  TitleMap := TDictionary<string, string>.Create;
  RefreshedTitleMap := False;
  FTP := ConnectFTP(AHost, APort);
  try
    SaveUsers := ListPS4Users(AHost, APort);
    if Trim(AOnlyUserID) <> '' then
    begin
      if LooksLikePS4UserID(AOnlyUserID) then
        Users.Add(LowerCase(Trim(AOnlyUserID)));
    end
    else
      for I := 0 to High(SaveUsers) do
        Users.Add(SaveUsers[I].UserID);

    try
      AppDbTitles := ResolvePS4TitleNamesFromAppDb(AHost, APort);
      for AppDbTitle in AppDbTitles do
        if (Trim(AppDbTitle.TitleID) <> '') and (Trim(AppDbTitle.TitleName) <> '') and
           not TitleMap.ContainsKey(UpperCase(Trim(AppDbTitle.TitleID))) then
          TitleMap.Add(UpperCase(Trim(AppDbTitle.TitleID)), Trim(AppDbTitle.TitleName));
    except
      TitleMap.Clear;
    end;

    for I := 0 to Users.Count - 1 do
    begin
      UserID := Users[I];
      if not LooksLikePS4UserID(UserID) then Continue;
      begin
        SaveRoot := PS4_USER_ROOT + '/home/' + UserID + '/savedata';
        Titles.Clear;
        if not TryListDir(FTP, SaveRoot) then Continue;

        for J := 0 to FTP.DirectoryListing.Count - 1 do
        begin
          if FTP.DirectoryListing[J].ItemType <> ditDirectory then Continue;
          TitleID := UpperCase(FTP.DirectoryListing[J].FileName);
          if not LooksLikePS4TitleID(TitleID) then Continue;
          Titles.Add(TitleID);
        end;

        for J := 0 to Titles.Count - 1 do
        begin
          TitleID := Titles[J];
          TitlePath := SaveRoot + '/' + TitleID;
          TitleName := '';
          if TitleMap.ContainsKey(UpperCase(TitleID)) then
            TitleName := TitleMap[UpperCase(TitleID)];
          if (TitleName = '') and not RefreshedTitleMap then
          begin
            { O cache pode ter sido criado antes deste jogo existir no PS4. }
            try
              AppDbTitles := ResolvePS4TitleNamesFromAppDb(AHost, APort, True);
              TitleMap.Clear;
              for AppDbTitle in AppDbTitles do
                if (Trim(AppDbTitle.TitleID) <> '') and
                   (Trim(AppDbTitle.TitleName) <> '') and
                   not TitleMap.ContainsKey(UpperCase(Trim(AppDbTitle.TitleID))) then
                  TitleMap.Add(UpperCase(Trim(AppDbTitle.TitleID)),
                    Trim(AppDbTitle.TitleName));
            except
              TitleMap.Clear;
            end;
            RefreshedTitleMap := True;
            if TitleMap.ContainsKey(UpperCase(TitleID)) then
              TitleName := TitleMap[UpperCase(TitleID)];
          end;
          if TitleName = '' then
            TitleName := ResolveGameTitleOnline(TitleID);
          if TitleName = '' then
            TitleName := TitleID;
          SaveNames.Clear;

          if TryListDir(FTP, TitlePath) then
            for K := 0 to FTP.DirectoryListing.Count - 1 do
              if (FTP.DirectoryListing[K].ItemType <> ditDirectory) and
                 IsPS4SaveImageFile(FTP.DirectoryListing[K].FileName, SaveName) then
                SaveNames.AddObject(SaveName,
                  TObject(NativeInt(DateTimeToFileDate(FTP.DirectoryListing[K].ModifiedDate))));

          if SaveNames.Count = 0 then
            Continue;

          for K := 0 to SaveNames.Count - 1 do
          begin
            SaveName := SaveNames[K];
            ModifiedAt := 0;
            if SaveNames.Objects[K] <> nil then
              ModifiedAt := FileDateToDateTime(Integer(NativeInt(SaveNames.Objects[K])));
            SetLength(Result, Length(Result) + 1);
            Save.TitleID := TitleID;
            Save.SaveName := SaveName;
            Save.UserID := UserID;
            Save.ModifiedAt := ModifiedAt;
            Save.UserDisplayName := FindUserDisplayName(SaveUsers, UserID);
            if Save.UserDisplayName = '' then
              Save.UserDisplayName := UserID;
            Save.RemotePath := TitlePath;
            Save.RemoteImagePath := TitlePath + '/sdimg_' + SaveName;
            Save.RemoteMetaPath := TitlePath + '/' + SaveName + '.bin';
            Save.Title := TitleName;
            Result[High(Result)] := Save;
          end;
        end;
      end;
    end;

    TArray.Sort<TPS4SaveGame>(Result, TComparer<TPS4SaveGame>.Construct(ComparePS4SaveGames));
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
    SaveNames.Free;
    Titles.Free;
    Users.Free;
    TitleMap.Free;
  end;
end;

function ListPS4SaveGames(const AHost: string; APort: Word): TArray<TPS4SaveGame>;
begin
  Result := ListPS4SaveGamesInternal(AHost, APort, '');
end;

function ListPS4SaveGamesForUser(const AHost: string; APort: Word;
  const AUserID: string): TArray<TPS4SaveGame>;
begin
  Result := ListPS4SaveGamesInternal(AHost, APort, AUserID);
end;

procedure EnsureRemoteDir(AFTP: TIdFTP; const APath: string);
var
  Part: string;
  CurrentPath: string;
begin
  CurrentPath := '';
  for Part in NormalizeRemotePath(APath).Split(['/']) do
  begin
    if Part = '' then Continue;
    CurrentPath := CurrentPath + '/' + Part;
    try
      AFTP.ChangeDir(CurrentPath);
    except
      try
        AFTP.MakeDir(CurrentPath);
      except
        // Pode falhar se a pasta ja existir ou se o FTP responder tarde;
        // a verificacao abaixo decide se realmente e erro.
      end;
      AFTP.ChangeDir(CurrentPath);
    end;
  end;
end;

procedure DownloadDir(AFTP: TIdFTP; const ARemoteDir, ALocalDir: string;
  ALog: TPS4SaveLogEvent);
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
      RemotePath := RemoteCombine(ARemoteDir, Names[I]);
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

procedure DownloadRequiredFile(AFTP: TIdFTP; const ARemoteFile, ALocalDir: string;
  ALog: TPS4SaveLogEvent);
var
  LocalPath: string;
begin
  if Trim(ARemoteFile) = '' then
    raise Exception.Create('Arquivo remoto do save nao informado.');
  ForceDirectories(ALocalDir);
  LocalPath := TPath.Combine(ALocalDir, RemoteFileName(ARemoteFile));
  try
    if Assigned(ALog) then
      ALog('Baixando ' + ARemoteFile);
    AFTP.Get(ARemoteFile, LocalPath, False);
  except
    on E: Exception do
      raise Exception.Create('Nao foi possivel baixar ' + ARemoteFile + ': ' + E.Message);
  end;

  if not TFile.Exists(LocalPath) then
    raise Exception.Create('Download nao criou o arquivo local: ' + LocalPath);
end;

function RemoteFileExists(AFTP: TIdFTP; const ARemoteFile: string): Boolean;
var
  DirName: string;
  FileName: string;
  I: Integer;
begin
  Result := False;
  if Trim(ARemoteFile) = '' then Exit;

  DirName := RemoteDirName(ARemoteFile);
  FileName := RemoteFileName(ARemoteFile);
  if FileName = '' then Exit;

  if not TryListDir(AFTP, DirName) then Exit;
  for I := 0 to AFTP.DirectoryListing.Count - 1 do
    if (AFTP.DirectoryListing[I].ItemType <> ditDirectory) and
       SameText(AFTP.DirectoryListing[I].FileName, FileName) then
      Exit(True);
end;

function FindEncryptedSaveRemoteFiles(AFTP: TIdFTP; const ASave: TPS4SaveGame;
  out AImagePath, AMetaPath, AAttempted: string): Boolean;
var
  BasePath: string;
  ImagePath: string;
  MetaPath: string;

  procedure AddAttempt(const APath: string);
  begin
    if AAttempted <> '' then
      AAttempted := AAttempted + ', ';
    AAttempted := AAttempted + APath;
  end;

  function TryPair(const ABasePath: string): Boolean;
  begin
    ImagePath := ABasePath + '/sdimg_' + ASave.SaveName;
    MetaPath := ABasePath + '/' + ASave.SaveName + '.bin';
    AddAttempt(ABasePath);
    Result := RemoteFileExists(AFTP, ImagePath) and RemoteFileExists(AFTP, MetaPath);
    if Result then
    begin
      AImagePath := ImagePath;
      AMetaPath := MetaPath;
    end;
  end;

begin
  Result := False;
  AImagePath := '';
  AMetaPath := '';
  AAttempted := '';

  if Trim(ASave.SaveName) = '' then Exit;

  if (ASave.RemotePath <> '') and TryPair(ASave.RemotePath) then
    Exit(True);

  begin
    BasePath := PS4_USER_ROOT + '/home/' + ASave.UserID + '/savedata/' + ASave.TitleID;
    if not SameText(NormalizeRemotePath(BasePath), NormalizeRemotePath(ASave.RemotePath)) then
      if TryPair(BasePath) then
        Exit(True);
  end;
end;

procedure DownloadSaveSlot(AFTP: TIdFTP; const ASave: TPS4SaveGame;
  const ALocalDir: string; ALog: TPS4SaveLogEvent);
var
  ImagePath: string;
  MetaPath: string;
  Attempted: string;
begin
  if Trim(ASave.SaveName) = '' then
  begin
    DownloadDir(AFTP, ASave.RemotePath, ALocalDir, ALog);
    Exit;
  end;

  if not FindEncryptedSaveRemoteFiles(AFTP, ASave, ImagePath, MetaPath, Attempted) then
    raise Exception.Create('Nao encontrei sdimg_' + ASave.SaveName + ' e ' +
      ASave.SaveName + '.bin no PS4 origem. Caminhos testados: ' + Attempted);

  DownloadRequiredFile(AFTP, ImagePath, ALocalDir, ALog);
  DownloadRequiredFile(AFTP, MetaPath, ALocalDir, ALog);
end;

procedure ValidateEncryptedSaveFiles(const ASave: TPS4SaveGame; const ALocalDir: string);
var
  ImageFile: string;
  MetaFile: string;
begin
  if Trim(ASave.SaveName) = '' then Exit;

  ImageFile := TPath.Combine(ALocalDir, 'sdimg_' + ASave.SaveName);
  MetaFile := TPath.Combine(ALocalDir, ASave.SaveName + '.bin');

  if not TFile.Exists(ImageFile) then
    raise Exception.Create('Arquivo criptografado nao encontrado apos download: ' + ImageFile);
  if not TFile.Exists(MetaFile) then
    raise Exception.Create('Arquivo .bin do save nao encontrado apos download: ' + MetaFile);
end;

procedure CopyLocalDir(const ALeftDir, ADestDir: string);
var
  Files, Dirs: TStringDynArray;
  F, D: string;
begin
  ForceDirectories(ADestDir);
  Files := TDirectory.GetFiles(ALeftDir);
  for F in Files do
    TFile.Copy(F, TPath.Combine(ADestDir, ExtractFileName(F)), True);

  Dirs := TDirectory.GetDirectories(ALeftDir);
  for D in Dirs do
    CopyLocalDir(D, TPath.Combine(ADestDir, ExtractFileName(D)));
end;

function FindLocalApolloSaveFolder(const ASave: TPS4SaveGame): string;
var
  Drive: Char;
  Root, ExpectedName: string;
  Matches: TStringDynArray;
begin
  Result := '';
  ExpectedName := ApolloSaveFolderName(ASave);
  for Drive := 'A' to 'Z' do
  begin
    Root := Drive + ':\PS4\APOLLO';
    if not TDirectory.Exists(Root) then Continue;

    Matches := TDirectory.GetDirectories(Root, ExpectedName,
      TSearchOption.soTopDirectoryOnly);
    if Length(Matches) > 0 then
      Exit(Matches[0]);
  end;
end;

function TryCopyLocalApolloSave(const ASave: TPS4SaveGame; const ALocalDir: string;
  ALog: TPS4SaveLogEvent): Boolean;
var
  LeftDir: string;
begin
  LeftDir := FindLocalApolloSaveFolder(ASave);
  Result := LeftDir <> '';
  if not Result then Exit;

  if Assigned(ALog) then
    ALog('Copiando exportacao do Apollo: ' + LeftDir);
  CopyLocalDir(LeftDir, ALocalDir);
end;

procedure WriteBackupInfoFile(const ASave: TPS4SaveGame; const ALocalDir: string);
var
  Info: TStringList;
begin
  ForceDirectories(ALocalDir);
  Info := TStringList.Create;
  try
    Info.Add('PS4 save backup');
    Info.Add('Title=' + ASave.Title);
    Info.Add('TitleID=' + ASave.TitleID);
    Info.Add('SaveName=' + ASave.SaveName);
    Info.Add('UserID=' + ASave.UserID);
    Info.Add('RemotePath=' + ASave.RemotePath);
    Info.Add('');
    Info.Add('Observacao: se esta pasta contem sce_sys e os arquivos do save,');
    Info.Add('ela foi copiada da exportacao descriptografada do Apollo em /PS4/APOLLO.');
    Info.Add('Se contem apenas sdimg_* e *.bin, veio direto do HDD via FTP e continua criptografada pelo PS4.');
    Info.Add('A descriptografia real e feita pelo Apollo dentro do console.');
    Info.SaveToFile(TPath.Combine(ALocalDir, 'BACKUP_INFO.txt'), TEncoding.UTF8);
  finally
    Info.Free;
  end;
end;

procedure UploadDir(AFTP: TIdFTP; const ALocalDir, ARemoteDir: string;
  ALog: TPS4SaveLogEvent);
var
  Files, Dirs: TStringDynArray;
  F, D: string;
begin
  if Assigned(ALog) then
    ALog('Preparando pasta remota ' + ARemoteDir);
  EnsureRemoteDir(AFTP, ARemoteDir);
  Files := TDirectory.GetFiles(ALocalDir);
  for F in Files do
  begin
    if Assigned(ALog) then
      ALog('Enviando ' + ExtractFileName(F) + ' para ' + ARemoteDir);
    AFTP.ChangeDir(ARemoteDir);
    AFTP.Put(F, ExtractFileName(F));
  end;

  Dirs := TDirectory.GetDirectories(ALocalDir);
  for D in Dirs do
    UploadDir(AFTP, D, RemoteCombine(ARemoteDir, ExtractFileName(D)), ALog);
end;

procedure UploadFileAs(AFTP: TIdFTP; const ALocalFile, ARemoteDir,
  ARemoteName: string; ALog: TPS4SaveLogEvent);
begin
  if not TFile.Exists(ALocalFile) then
    raise Exception.Create('Arquivo local nao encontrado para envio: ' + ALocalFile);

  EnsureRemoteDir(AFTP, ARemoteDir);
  if Assigned(ALog) then
    ALog('Enviando ' + ExtractFileName(ALocalFile) + ' como ' +
      ARemoteDir + '/' + ARemoteName);
  AFTP.ChangeDir(ARemoteDir);
  AFTP.Put(ALocalFile, ARemoteName);
end;

procedure UploadEncryptedSaveForApollo(AFTP: TIdFTP; const ASave: TPS4SaveGame;
  const ALocalDir, ARemoteDir: string; ALog: TPS4SaveLogEvent);
var
  ImageFile: string;
  MetaFile: string;
begin
  if Trim(ASave.SaveName) = '' then
    raise Exception.Create('Nome interno do save nao informado para ' + ASave.TitleID + '.');

  ImageFile := TPath.Combine(ALocalDir, 'sdimg_' + ASave.SaveName);
  MetaFile := TPath.Combine(ALocalDir, ASave.SaveName + '.bin');

  UploadFileAs(AFTP, ImageFile, ARemoteDir, ASave.SaveName, ALog);
  UploadFileAs(AFTP, MetaFile, ARemoteDir, ASave.SaveName + '.bin', ALog);
end;

function BackupSafeFolderName(const S: string): string;
const
  INVALID_CHARS: TSysCharSet = ['\', '/', ':', '*', '?', '"', '<', '>', '|'];
var
  I: Integer;
begin
  Result := Trim(S);
  if Result = '' then
    Result := 'save';
  for I := 1 to Length(Result) do
    if CharInSet(Result[I], INVALID_CHARS) then
      Result[I] := '_';
end;

procedure CreatePS4SavePack(const ALeftDir, AArchiveFile: string);
var
  Output: TFileStream;
  procedure WriteText(const AText: string);
  var
    B: UTF8String;
  begin
    B := UTF8String(AText);
    if Length(B) > 0 then Output.WriteBuffer(B[1], Length(B));
  end;
  procedure PackDirectory(const ARoot, ARelative: string);
  var
    DirName, RelName, FullName, Line: string;
    Dirs, Files: TStringDynArray;
    Input: TFileStream;
  begin
    Dirs := TDirectory.GetDirectories(TPath.Combine(ARoot, ARelative));
    for DirName in Dirs do
    begin
      RelName := TPath.Combine(ARelative, ExtractFileName(DirName));
      WriteText('D' + #9 + StringReplace(RelName, '\', '/', [rfReplaceAll]) + sLineBreak);
      PackDirectory(ARoot, RelName);
    end;
    Files := TDirectory.GetFiles(TPath.Combine(ARoot, ARelative));
    for FullName in Files do
    begin
      RelName := TPath.Combine(ARelative, ExtractFileName(FullName));
      Line := 'F' + #9 + IntToStr(TFile.GetSize(FullName)) + #9 +
        StringReplace(RelName, '\', '/', [rfReplaceAll]) + sLineBreak;
      WriteText(Line);
      Input := TFileStream.Create(FullName, fmOpenRead or fmShareDenyNone);
      try
        Output.CopyFrom(Input, 0);
      finally
        Input.Free;
      end;
      WriteText(sLineBreak);
    end;
  end;
begin
  Output := TFileStream.Create(AArchiveFile, fmCreate);
  try
    WriteText('PS4SAVEPACK1' + sLineBreak);
    PackDirectory(ALeftDir, '');
    WriteText('END' + sLineBreak);
  finally
    Output.Free;
  end;
end;

procedure BackupPS4Saves(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestFolder: string;
  ALog: TPS4SaveLogEvent);
var
  FTP: TIdFTP;
  Save: TPS4SaveGame;
  LocalDir: string;
begin
  ForceDirectories(ADestFolder);
  FTP := ConnectFTP(AHost, APort);
  try
    for Save in ASaves do
    begin
      LocalDir := TPath.Combine(ADestFolder,
        BackupSafeFolderName(Save.Title + ' [' + Save.TitleID + ']'));
      if Trim(Save.SaveName) <> '' then
        LocalDir := TPath.Combine(LocalDir, BackupSafeFolderName(Save.SaveName));
      if Assigned(ALog) then
        ALog('Backup de ' + Save.TitleID + ' / ' + Save.SaveName +
          ' (usuario ' + Save.UserID + ')');
      if not TryCopyLocalApolloSave(Save, LocalDir, ALog) then
      begin
        if Assigned(ALog) then
          ALog('Exportacao do Apollo nao encontrada no PC; baixando save bruto do HDD via FTP.');
        DownloadSaveSlot(FTP, Save, LocalDir, ALog);
      end;
      WriteBackupInfoFile(Save, LocalDir);
    end;
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;
end;

procedure UploadDecryptedSave(const AHost, ADestUserID: string;
  const ASave: TPS4SaveGame; const ALocalZip: string;
  ALog: TPS4SaveAgentLogEvent; AProgress: TPS4SaveAgentProgressEvent); forward;

procedure ImportPS4SaveBackup(const AHost, AUserID, ABackupFolder: string;
  AAutomatic: Boolean; ALog: TPS4SaveLogEvent);
var
  FTP: TIdFTP;
  GameDirs, SaveDirs, Files: TStringDynArray;
  GameDir, SaveDir, LocalFile, TitleID, RemoteDir, ZipPath: string;
  LeftUserID, SaveFileName: string;
  Save: TPS4SaveGame;
  I, P: Integer;
begin
  if Pos('[', ExtractFileName(ABackupFolder)) > 0 then
  begin
    SetLength(GameDirs, 1);
    GameDirs[0] := ExcludeTrailingPathDelimiter(ABackupFolder);
  end
  else
    GameDirs := TDirectory.GetDirectories(ABackupFolder);
  { O Sync ativa o usuario antes do upload. A importacao precisa fazer o
    mesmo, pois o Agent usa o Account ID ativo para recriar o save. }
  EnsurePS4SaveAgentReady(AHost, ALog);
  GetPS4SaveAgentAccountID(AHost, AUserID, ALog);
  FTP := ConnectFTP(AHost, 2121);
  try
    for GameDir in GameDirs do
    begin
      TitleID := '';
      P := LastDelimiter('[', GameDir);
      if P > 0 then
        TitleID := Copy(GameDir, P + 1, Length(GameDir) - P - 1);
      if not LooksLikePS4TitleID(TitleID) then
        Continue;

      SaveDirs := TDirectory.GetDirectories(GameDir);
      for SaveDir in SaveDirs do
      begin
        Save.TitleID := TitleID;
        Save.SaveName := ExtractFileName(SaveDir);
        Save.UserID := AUserID;
        Save.Title := ExtractFileName(GameDir);
        ZipPath := TPath.Combine(SaveDir, 'save.ps4sav');
        if not TFile.Exists(ZipPath) then
        begin
          Files := TDirectory.GetFiles(SaveDir, '*.ps4sav');
          if Length(Files) > 0 then
            ZipPath := Files[0];
        end;
        if TFile.Exists(ZipPath) then
        begin
          EnsurePS4SaveAgentReady(AHost, ALog);
          { A exportacao usa o mesmo nome de pacote do Sync:
            <usuario_origem>_<data>.ps4sav. Recuperar esse usuario permite
            repetir exatamente a chamada de upload do Sync. }
          SaveFileName := ExtractFileName(ZipPath);
          P := Pos('_', SaveFileName);
          if P > 1 then
          begin
            LeftUserID := Copy(SaveFileName, 1, P - 1);
            if Length(LeftUserID) >= 8 then
              Save.UserID := LeftUserID;
          end;
          UploadDecryptedSave(AHost, AUserID, Save, ZipPath, ALog, nil);
          Continue;
        end;
        if AAutomatic and TDirectory.Exists(TPath.Combine(SaveDir, 'sce_sys')) then
        begin
          ZipPath := TPath.Combine(TPath.GetTempPath,
            'PS4Tools_import_' + TitleID + '_' + IntToStr(GetTickCount) + '.ps4sav');
          CreatePS4SavePack(SaveDir, ZipPath);
          try
            UploadDecryptedSave(AHost, AUserID, Save, ZipPath, ALog, nil);
          finally
            if TFile.Exists(ZipPath) then TFile.Delete(ZipPath);
          end;
          Continue;
        end;
        RemoteDir := PS4_USER_ROOT + '/home/' + AUserID + '/savedata/' + TitleID;
        EnsureRemoteDir(FTP, RemoteDir);
        Files := TDirectory.GetFiles(SaveDir);
        for I := 0 to High(Files) do
        begin
          LocalFile := Files[I];
          if SameText(ExtractFileName(LocalFile), 'BACKUP_INFO.txt') then
            Continue;
          if (Pos('sdimg_', LowerCase(ExtractFileName(LocalFile))) = 1) or
             SameText(ExtractFileExt(LocalFile), '.bin') then
          begin
            if Assigned(ALog) then
              ALog('Importando ' + ExtractFileName(LocalFile) + ' para ' + TitleID + '...');
            FTP.Put(LocalFile, RemoteDir + '/' + ExtractFileName(LocalFile), False);
          end;
        end;
      end;
    end;
  finally
    if Assigned(FTP) and FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;
end;

procedure ExportPS4SavesDecrypted(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestFolder: string;
  ALog: TPS4SaveAgentLogEvent; AProgress: TPS4SaveAgentProgressEvent);
var
  Save: TPS4SaveGame;
  GameDir, SaveDir, ArchiveFile: string;
  I: Integer;
begin
  if Length(ASaves) = 0 then
    Exit;
  EnsurePS4SaveAgentReady(AHost, ALog);
  for I := 0 to High(ASaves) do
  begin
    Save := ASaves[I];
    GameDir := TPath.Combine(ADestFolder,
      BackupSafeFolderName(Save.Title + ' [' + Save.TitleID + ']'));
    SaveDir := TPath.Combine(GameDir, BackupSafeFolderName(Save.SaveName));
    ForceDirectories(SaveDir);
    ArchiveFile := TPath.Combine(SaveDir,
      BackupSafeFolderName(Save.UserID + '_' +
        FormatDateTime('yyyymmdd_hhnnss', Now)) + '.ps4sav');
    DownloadDecryptedSave(AHost, Save, ArchiveFile, ALog, nil);
    if Assigned(AProgress) then
      AProgress(Format('Save %d de %d concluido: %s / %s',
        [I + 1, Length(ASaves), Save.TitleID, Save.SaveName]),
        I + 1, Length(ASaves));
  end;
end;

procedure WriteTrophyBackupInfoFile(const ADestFolder: string);
var
  Info: TStringList;
begin
  ForceDirectories(ADestFolder);
  Info := TStringList.Create;
  try
    Info.Add('PS4 trophy backup');
    Info.Add('');
    Info.Add('Copie estas pastas de volta para o PS4, se precisar restaurar:');
    Info.Add('TROPHY\user\home\<UserID>\trophy\data  -> /user/home/<UserID>/trophy/data');
    Info.Add('TROPHY\user\home\<UserID>\trophy\db    -> /user/home/<UserID>/trophy/db');
    Info.Add('TROPHY\user\trophy\conf                -> /user/trophy/conf');
    Info.Add('');
    Info.Add('Observacao: reinicie totalmente o PS4 antes de abrir Trofeus apos restaurar arquivos.');
    Info.SaveToFile(TPath.Combine(ADestFolder, 'BACKUP_INFO.txt'), TEncoding.UTF8);
  finally
    Info.Free;
  end;
end;

procedure BackupPS4Trophies(const AHost: string; APort: Word;
  const ADestFolder: string; ALog: TPS4SaveLogEvent);
var
  FTP: TIdFTP;
  Users: TArray<TPS4SaveUser>;
  User: TPS4SaveUser;
  LocalDataDir, LocalDbDir, LocalConfDir: string;
begin
  ForceDirectories(ADestFolder);
  WriteTrophyBackupInfoFile(ADestFolder);

  if Assigned(ALog) then
    ALog('Listando usuarios do PS4...');
  Users := ListPS4Users(AHost, APort);

  FTP := ConnectFTP(AHost, APort);
  try
    for User in Users do
    begin
      if Assigned(ALog) then
        ALog('Backup de trofeus do usuario ' + User.UserID);

      LocalDataDir := TPath.Combine(TPath.Combine(TPath.Combine(TPath.Combine(
        ADestFolder, 'user'), 'home'), User.UserID), 'trophy\data');
      LocalDbDir := TPath.Combine(TPath.Combine(TPath.Combine(TPath.Combine(
        ADestFolder, 'user'), 'home'), User.UserID), 'trophy\db');

      DownloadDir(FTP, '/user/home/' + User.UserID + '/trophy/data',
        LocalDataDir, ALog);
      DownloadDir(FTP, '/user/home/' + User.UserID + '/trophy/db',
        LocalDbDir, ALog);
    end;

    LocalConfDir := TPath.Combine(TPath.Combine(TPath.Combine(ADestFolder,
      'user'), 'trophy'), 'conf');
    DownloadDir(FTP, '/user/trophy/conf', LocalConfDir, ALog);
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;
end;

procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; ALog: TPS4SaveLogEvent); overload;
begin
  SyncPS4Saves(ALeftHost, ADestHost, APort, ASaves, '', ALog);
end;

procedure DeleteRemoteFileIfExists(AFTP: TIdFTP; const ARemoteFile: string;
  ALog: TPS4SaveLogEvent);
begin
  if Trim(ARemoteFile) = '' then Exit;
  if not RemoteFileExists(AFTP, ARemoteFile) then Exit;

  if Assigned(ALog) then
    ALog('Deletando ' + ARemoteFile);
  AFTP.Delete(ARemoteFile);
end;

procedure DeletePS4Saves(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; ALog: TPS4SaveLogEvent);
var
  FTP: TIdFTP;
  Save: TPS4SaveGame;
  TitlePath: string;
begin
  if Length(ASaves) = 0 then Exit;

  FTP := ConnectFTP(AHost, APort);
  try
    for Save in ASaves do
    begin
      if Assigned(ALog) then
        ALog('Deletando save ' + Save.TitleID + ' / ' + Save.SaveName +
          ' do usuario ' + Save.UserID + ' em ' + AHost + '...');

      DeleteRemoteFileIfExists(FTP, Save.RemoteImagePath, ALog);
      DeleteRemoteFileIfExists(FTP, Save.RemoteMetaPath, ALog);

      TitlePath := PS4_USER_ROOT + '/home/' + Save.UserID + '/savedata/' +
        Save.TitleID;
      try
        if TryListDir(FTP, TitlePath) and (FTP.DirectoryListing.Count = 0) then
          FTP.RemoveDir(TitlePath);
      except
      end;
    end;
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;
end;

procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestUserID: string;
  ALog: TPS4SaveLogEvent); overload;
var
  SrcFTP, DstFTP: TIdFTP;
  Save: TPS4SaveGame;
  TempRoot, LocalDir, RemoteBasePath, RemoteDestPath, DestUserID: string;
begin
  TempRoot := ExeTempRoot('PS4PKGDownloader_saves');
  ForceDirectories(TempRoot);

  SrcFTP := nil;
  DstFTP := nil;
  try
    SrcFTP := ConnectFTP(ALeftHost, APort);
    DstFTP := ConnectFTP(ADestHost, APort);
    for Save in ASaves do
    begin
      DestUserID := Trim(ADestUserID);
      if DestUserID = '' then
        DestUserID := Save.UserID;
      LocalDir := TPath.Combine(TPath.Combine(TPath.Combine(TempRoot, Save.UserID),
        Save.TitleID), Save.SaveName);
      RemoteBasePath := '/data/fakeusb/PS4/SAVEDATA/' + APOLLO_FAKEUSB_ACCOUNT_ID;
      RemoteDestPath := RemoteBasePath + '/' + Save.TitleID;
      if Assigned(ALog) then
        ALog('Copiando save criptografado ' + Save.TitleID + ' / ' +
          Save.SaveName + ' para o Fake USB do Apollo no PS4 destino (' +
          RemoteDestPath + '). O Apollo fara a importacao para o usuario ' +
          DestUserID + '.');
      EnsureRemoteDir(DstFTP, RemoteDestPath);
      DownloadSaveSlot(SrcFTP, Save, LocalDir, ALog);
      ValidateEncryptedSaveFiles(Save, LocalDir);
      UploadEncryptedSaveForApollo(DstFTP, Save, LocalDir, RemoteDestPath, ALog);
    end;
  finally
    if Assigned(SrcFTP) and SrcFTP.Connected then SrcFTP.Disconnect;
    if Assigned(DstFTP) and DstFTP.Connected then DstFTP.Disconnect;
    SrcFTP.Free;
    DstFTP.Free;
    try
      TDirectory.Delete(TempRoot, True);
    except
    end;
  end;
end;

procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  ALog: TPS4SaveLogEvent); overload;
var
  Saves: TArray<TPS4SaveGame>;
begin
  Saves := ListPS4SaveGames(ALeftHost, APort);
  SyncPS4Saves(ALeftHost, ADestHost, APort, Saves, ALog);
end;


const
  PS4_FTP_PORT = 2121;
  PS4_SAVE_AGENT_PORT = 8084;
  PS4_AGENT_FTP_USER = 'anonymous';
  PS4_AGENT_FTP_PASS = 'anonymous@';
  PS4_SAVE_AGENT_FILE = 'ps4-save-agent.elf';
  PS4_SAVE_AGENT_REMOTE_DIR = '/data/payloads';
  PS4_SAVE_AGENT_PING = 'PS4SAVEAGENT';
  PS4_SAVE_AGENT_MIN_VERSION = 'PS4SAVEAGENT 2.7';
  PS4_BINLOADER_PORTS: array[0..2] of Word = (9090, 9021, 9020);

type
  THTTPProgress = class
  private
    FMessage: string;
    FProgress: TPS4SaveAgentProgressEvent;
    FMax: Int64;
  public
    constructor Create(const AMessage: string; AProgress: TPS4SaveAgentProgressEvent;
      ADefaultMax: Int64 = 0);
    procedure WorkBegin(ASender: TObject; AWorkMode: TWorkMode;
      AWorkCountMax: Int64);
    procedure Work(ASender: TObject; AWorkMode: TWorkMode; AWorkCount: Int64);
    procedure WorkEnd(ASender: TObject; AWorkMode: TWorkMode);
  end;

constructor THTTPProgress.Create(const AMessage: string;
  AProgress: TPS4SaveAgentProgressEvent; ADefaultMax: Int64);
begin
  inherited Create;
  FMessage := AMessage;
  FProgress := AProgress;
  FMax := ADefaultMax;
end;

procedure THTTPProgress.WorkBegin(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCountMax: Int64);
begin
  if AWorkCountMax > 0 then
    FMax := AWorkCountMax;
  if Assigned(FProgress) then
    FProgress(FMessage, 0, FMax);
end;

procedure THTTPProgress.Work(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCount: Int64);
begin
  if Assigned(FProgress) then
    FProgress(FMessage, AWorkCount, FMax);
end;

procedure THTTPProgress.WorkEnd(ASender: TObject; AWorkMode: TWorkMode);
begin
  if Assigned(FProgress) then
    FProgress(FMessage, FMax, FMax);
end;

function PS4SaveAgentLocalPath: string;
begin
  { A pasta payloads distribuida ao lado do executavel e a unica fonte
    oficial do ELF. Isso permite copiar a pasta PS4Tools inteira para outro
    computador sem depender do diretorio do projeto de desenvolvimento. }
  Result := TPath.Combine(ExtractFileDir(ParamStr(0)),
    TPath.Combine('payloads', PS4_SAVE_AGENT_FILE));
end;

function PS4SaveAgentRemotePath: string;
begin
  Result := PS4_SAVE_AGENT_REMOTE_DIR + '/' + PS4_SAVE_AGENT_FILE;
end;

procedure Log(ALog: TPS4SaveAgentLogEvent; const AMsg: string);
begin
  if Assigned(ALog) then
    ALog(AMsg);
end;

function ConnectAgentFTP(const AHost: string): TIdFTP;
begin
  Result := TIdFTP.Create(nil);
  try
    Result.Host := Trim(AHost);
    Result.Port := PS4_FTP_PORT;
    Result.Username := PS4_AGENT_FTP_USER;
    Result.Password := PS4_AGENT_FTP_PASS;
    Result.Passive := True;
    Result.TransferType := ftBinary;
    Result.ConnectTimeout := 8000;
    Result.ReadTimeout := 30000;
    Result.Connect;
  except
    Result.Free;
    raise;
  end;
end;

function AgentNormalizeRemotePath(const S: string): string;
begin
  Result := StringReplace(S, '\', '/', [rfReplaceAll]);
  while Pos('//', Result) > 0 do
    Result := StringReplace(Result, '//', '/', [rfReplaceAll]);
  if (Result = '') or (Result[1] <> '/') then
    Result := '/' + Result;
  if (Length(Result) > 1) and (Result[Length(Result)] = '/') then
    Delete(Result, Length(Result), 1);
end;

function AgentRemoteDirName(const ARemoteFile: string): string;
var
  P: Integer;
begin
  Result := AgentNormalizeRemotePath(ARemoteFile);
  P := LastDelimiter('/', Result);
  if P > 1 then
    Result := Copy(Result, 1, P - 1)
  else
    Result := '/';
end;

function AgentRemoteFileName(const ARemoteFile: string): string;
var
  P: Integer;
begin
  Result := AgentNormalizeRemotePath(ARemoteFile);
  P := LastDelimiter('/', Result);
  if P > 0 then
    Result := Copy(Result, P + 1, MaxInt);
end;

procedure AgentEnsureRemoteDir(AFTP: TIdFTP; const APath: string);
var
  Part: string;
  CurrentPath: string;
begin
  CurrentPath := '';
  for Part in AgentNormalizeRemotePath(APath).Split(['/']) do
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

function AgentRemoteFileExists(AFTP: TIdFTP; const ARemoteFile: string;
  out ASize: Int64): Boolean;
var
  DirName: string;
  FileName: string;
  I: Integer;
begin
  Result := False;
  ASize := -1;
  DirName := AgentRemoteDirName(ARemoteFile);
  FileName := AgentRemoteFileName(ARemoteFile);
  if FileName = '' then Exit;

  try
    AFTP.DirectoryListing.Clear;
    AFTP.ChangeDir(DirName);
    AFTP.List('', True);
  except
    Exit(False);
  end;

  for I := 0 to AFTP.DirectoryListing.Count - 1 do
    if (AFTP.DirectoryListing[I].ItemType <> ditDirectory) and
       SameText(AFTP.DirectoryListing[I].FileName, FileName) then
    begin
      ASize := AFTP.DirectoryListing[I].Size;
      Exit(True);
    end;
end;

procedure EnsureAgentUploaded(const AHost: string; ALog: TPS4SaveAgentLogEvent;
  AForce: Boolean = False);
var
  FTP: TIdFTP;
  RemoteSize: Int64;
  LocalSize: Int64;
  LocalPath: string;
begin
  LocalPath := PS4SaveAgentLocalPath;
  if not TFile.Exists(LocalPath) then
    raise Exception.Create('ELF do PS4 Save Agent nao encontrado: ' + LocalPath + sLineBreak +
      'Compile o payload em tools\ps4-save-agent e copie o ELF para a pasta payloads.');

  LocalSize := TFile.GetSize(LocalPath);
  FTP := ConnectAgentFTP(AHost);
  try
    if (not AForce) and AgentRemoteFileExists(FTP, PS4SaveAgentRemotePath, RemoteSize) and
       (RemoteSize = LocalSize) then
    begin
      Log(ALog, 'PS4 Save Agent ja esta no PS4: ' + PS4SaveAgentRemotePath);
      Exit;
    end;

    Log(ALog, 'Enviando PS4 Save Agent para ' + PS4SaveAgentRemotePath + '...');
    AgentEnsureRemoteDir(FTP, PS4_SAVE_AGENT_REMOTE_DIR);
    FTP.ChangeDir(PS4_SAVE_AGENT_REMOTE_DIR);
    FTP.Put(LocalPath, PS4_SAVE_AGENT_FILE);
    Log(ALog, 'PS4 Save Agent copiado para o PS4.');
  finally
    if FTP.Connected then
      FTP.Disconnect;
    FTP.Free;
  end;
end;

procedure EnsurePS4SaveAgentInstalled(const AHost: string; ALog: TPS4SaveAgentLogEvent);
var
  FTP: TIdFTP;
  RemoteSize: Int64;
begin
  FTP := ConnectAgentFTP(AHost);
  try
    if AgentRemoteFileExists(FTP, PS4SaveAgentRemotePath, RemoteSize) then
    begin
      Log(ALog, 'PS4 Save Agent ja esta no PS4: ' + PS4SaveAgentRemotePath);
      Exit;
    end;
  finally
    if FTP.Connected then
      FTP.Disconnect;
    FTP.Free;
  end;

  EnsureAgentUploaded(AHost, ALog);
end;

function TryDownloadAgentFromPS4(const AHost: string; ALog: TPS4SaveAgentLogEvent): Boolean;
var
  FTP: TIdFTP;
  RemoteSize: Int64;
  LocalPath: string;
begin
  //Result := False;
  LocalPath := PS4SaveAgentLocalPath;

  FTP := ConnectAgentFTP(AHost);
  try
    if not AgentRemoteFileExists(FTP, PS4SaveAgentRemotePath, RemoteSize) then
      Exit(False);

    ForceDirectories(ExtractFileDir(LocalPath));
    FTP.Get(PS4SaveAgentRemotePath, LocalPath, True);
    Result := TFile.Exists(LocalPath);
    if Result then
      Log(ALog, 'PS4 Save Agent baixado do PS4 para ' + LocalPath + '.');
  finally
    if FTP.Connected then
      FTP.Disconnect;
    FTP.Free;
  end;
end;

function AgentBaseURL(const AHost: string): string;
begin
  Result := 'http://' + Trim(AHost) + ':' + IntToStr(PS4_SAVE_AGENT_PORT);
end;

function TryPingAgent(const AHost: string): Boolean;
var
  HTTP: TIdHTTP;
  S: string;
begin
  //Result := False;
  HTTP := TIdHTTP.Create(nil);
  try
    HTTP.ConnectTimeout := 3000;
    HTTP.ReadTimeout := 5000;
    try
      S := HTTP.Get(AgentBaseURL(AHost) + '/api/ping');
      Result := Pos(PS4_SAVE_AGENT_PING, UpperCase(S)) > 0;
    except
      Result := False;
    end;
  finally
    HTTP.Free;
  end;
end;

function TryGetAgentVersion(const AHost: string; out AVersion: string): Boolean;
var
  HTTP: TIdHTTP;
  Attempt: Integer;
begin
  AVersion := '';
  Result := False;
  for Attempt := 1 to 3 do
  begin
    HTTP := TIdHTTP.Create(nil);
    try
      HTTP.ConnectTimeout := 3000;
      HTTP.ReadTimeout := 5000;
      try
        AVersion := Trim(HTTP.Get(AgentBaseURL(AHost) + '/api/version'));
        Result := Pos(PS4_SAVE_AGENT_MIN_VERSION, UpperCase(AVersion)) > 0;
      except
        AVersion := '';
        Result := False;
      end;
    finally
      HTTP.Free;
    end;
    if Result then
      Exit;
    if Attempt < 3 then
      Sleep(600);
  end;
end;

function WaitForAgentReady(const AHost: string; ASeconds: Integer;
  ALog: TPS4SaveAgentLogEvent): Boolean;
var
  StartedAt: TDateTime;
  AgentVersion: string;
  LastLogAt: TDateTime;
begin
  Result := False;
  StartedAt := Now;
  LastLogAt := 0;
  repeat
    if TryPingAgent(AHost) and TryGetAgentVersion(AHost, AgentVersion) then
      Exit(True);
    if (LastLogAt = 0) or (SecondsBetween(Now, LastLogAt) >= 3) then
    begin
      Log(ALog, 'Aguardando PS4 Save Agent responder...');
      LastLogAt := Now;
    end;
    Sleep(1000);
  until SecondsBetween(Now, StartedAt) >= ASeconds;
end;

function TrySendAgentToBinLoader(const AHost: string; ALog: TPS4SaveAgentLogEvent): Boolean;
var
  Payload: TBytes;
  IdPayload: TIdBytes;
  TCP: TIdTCPClient;
  Port: Word;
  LocalPath: string;
begin
  Result := False;
  LocalPath := PS4SaveAgentLocalPath;

  if not TFile.Exists(LocalPath) then
  begin
    Log(ALog, 'ELF local nao encontrado; tentando baixar do PS4...');
    if not TryDownloadAgentFromPS4(AHost, ALog) then
    begin
      Log(ALog, 'Nao foi possivel obter o ELF local para enviar ao BinLoader.');
      Exit(False);
    end;
  end;

  Payload := TFile.ReadAllBytes(LocalPath);
  if Length(Payload) = 0 then
  begin
    Log(ALog, 'ELF local esta vazio: ' + LocalPath);
    Exit(False);
  end;
  Log(ALog, Format('Usando ELF local %s (%d bytes).', [LocalPath, Length(Payload)]));

  SetLength(IdPayload, Length(Payload));
  if Length(Payload) > 0 then
    Move(Payload[0], IdPayload[0], Length(Payload));

  for Port in PS4_BINLOADER_PORTS do
  begin
    TCP := TIdTCPClient.Create(nil);
    try
      try
        Log(ALog, Format('Tentando iniciar PS4 Save Agent pelo BinLoader na porta %d...', [Port]));
        TCP.Host := Trim(AHost);
        TCP.Port := Port;
        TCP.ConnectTimeout := 7000;
        TCP.ReadTimeout := 7000;
        TCP.Connect;
        TCP.IOHandler.Write(IdPayload);
        Sleep(250);
        TCP.Disconnect;
        Log(ALog, Format('PS4 Save Agent enviado ao BinLoader na porta %d.', [Port]));
        Exit(True);
      except
        on E: Exception do
          Log(ALog, Format('BinLoader porta %d indisponivel (%s).', [Port, E.Message]));
      end;
    finally
      TCP.Free;
    end;
  end;
end;

procedure EnsurePS4SaveAgentReady(const AHost: string; ALog: TPS4SaveAgentLogEvent);
var
  AgentVersion: string;
  Attempt: Integer;
begin
  if TryPingAgent(AHost) then
  begin
    if not TryGetAgentVersion(AHost, AgentVersion) then
      raise Exception.Create('Existe um PS4 Save Agent antigo/minimo em execucao em ' +
        AHost + '. Ele responde /api/ping, mas nao tem /api/version nem as rotas ' +
        'de sincronia. O ELF novo ja pode estar em /data/payloads, mas o processo ' +
        'antigo continua na RAM. Reinicie o PS4 ou encerre/recarregue o payload e ' +
        'execute novamente.');
    Log(ALog, 'PS4 Save Agent ja esta em execucao em ' + AHost + '.');
    Exit;
  end;

  { /api/version is the authoritative probe.  A transient /api/ping timeout
    must not cause FTP/BinLoader to start a second process. }
  if TryGetAgentVersion(AHost, AgentVersion) then
  begin
    Log(ALog, 'PS4 Save Agent ja esta em execucao em ' + AHost + ': ' + AgentVersion);
    Exit;
  end;

  Log(ALog, 'PS4 Save Agent nao respondeu; verificando se o ELF existe no PS4...');
  EnsurePS4SaveAgentInstalled(AHost, ALog);

  if WaitForAgentReady(AHost, 3, ALog) then
  begin
    Log(ALog, 'PS4 Save Agent respondeu em ' + AHost + '.');
    Exit;
  end;

  Log(ALog, 'PS4 Save Agent nao esta em execucao; tentando iniciar pelo BinLoader do GoldHEN...');
  for Attempt := 1 to 1 do
  begin
    if Attempt > 1 then
    begin
      Log(ALog, 'PS4 Save Agent ainda nao respondeu; reenviando ao BinLoader...');
      Sleep(1500);
    end;

    if TrySendAgentToBinLoader(AHost, ALog) and WaitForAgentReady(AHost, 15, ALog) then
    begin
      Log(ALog, 'PS4 Save Agent iniciado automaticamente em ' + AHost + '.');
      Exit;
    end;
  end;

  raise Exception.Create('O arquivo ' + PS4SaveAgentRemotePath +
    ' existe no PS4, mas o Agent nao respondeu na porta ' +
    IntToStr(PS4_SAVE_AGENT_PORT) + ' depois do envio ao BinLoader. ' +
    'Quando isso acontece, o GoldHEN aceitou o arquivo mas o payload morreu ao iniciar. ' +
    'Execute manualmente pelo Payloader e veja se http://' + Trim(AHost) + ':' +
    IntToStr(PS4_SAVE_AGENT_PORT) + '/api/version responde.');
end;

function ExtractResponseValue(const AResponse, AName: string): string;
var
  Lines: TArray<string>;
  Line, Prefix: string;
begin
  Result := '';
  Prefix := LowerCase(AName) + '=';
  Lines := AResponse.Replace(#13, '').Split([#10]);
  for Line in Lines do
    if Pos(Prefix, LowerCase(Trim(Line))) = 1 then
      Exit(Trim(Copy(Trim(Line), Length(Prefix) + 1, MaxInt)));
end;

function GetPS4SaveAgentAccountID(const AHost, AUserID: string;
  ALog: TPS4SaveAgentLogEvent): string;
var
  HTTP: TIdHTTP;
  Response: string;
  Attempt: Integer;
begin
  EnsurePS4SaveAgentReady(AHost, ALog);

  Result := '0000000000000000';
  for Attempt := 1 to 3 do
  begin
    HTTP := TIdHTTP.Create(nil);
    try
      HTTP.ConnectTimeout := 5000;
      HTTP.ReadTimeout := 10000;
      Response := '';
      try
        Response := HTTP.Get(AgentBaseURL(AHost) + '/api/account_id?user=' +
          TIdURI.ParamsEncode(AUserID));
      except
        on E: EIdHTTPProtocolException do
          Response := E.ErrorMessage;
        on E: Exception do
          Response := '';
      end;
      Result := ExtractResponseValue(Response, 'account_id');
      if (Result <> '') and not SameText(Result, '0000000000000000') then
        Exit;
    finally
      HTTP.Free;
    end;

    if Attempt < 3 then
    begin
      Log(ALog, Format('Account ID do usuario %s nao foi retornado; repetindo validacao (%d/3).',
        [AUserID, Attempt + 1]));
      TryPingAgent(AHost);
      Sleep(300);
    end;
  end;
  Result := '0000000000000000';
end;

procedure ShutdownPS4SaveAgent(const AHost: string; ALog: TPS4SaveAgentLogEvent);
var
  HTTP: TIdHTTP;
begin
  if Trim(AHost) = '' then Exit;

  HTTP := TIdHTTP.Create(nil);
  try
    HTTP.ConnectTimeout := 1500;
    HTTP.ReadTimeout := 8000;
    try
      HTTP.Get(AgentBaseURL(AHost) + '/api/shutdown');
      Log(ALog, 'PS4 Save Agent finalizado em ' + AHost + '.');
    except
      on E: Exception do
        Log(ALog, 'PS4 Save Agent nao respondeu ao shutdown em ' + AHost + ': ' + E.Message);
    end;
  finally
    HTTP.Free;
  end;
end;

procedure EnsurePS4SaveAgentCurrent(const AHost: string;
  ALog: TPS4SaveAgentLogEvent);
var
  AgentVersion: string;
  Attempt: Integer;
begin
  { Ao conectar, sempre sincroniza o ELF local com o PS4. Isso elimina a
    ambiguidade entre o arquivo remoto e o processo antigo na RAM. }
  Log(ALog, 'Enviando PS4 Save Agent para ' + PS4SaveAgentRemotePath +
    ' (atualizacao forcada)...');
  EnsureAgentUploaded(AHost, ALog, True);

  { O processo anterior precisa liberar a porta 8084 antes do BinLoader. }
  ShutdownPS4SaveAgent(AHost, ALog);
  for Attempt := 1 to 12 do
  begin
    Sleep(150);
    if not TryPingAgent(AHost) then
      Break;
    if Attempt = 12 then
      raise Exception.Create('O PS4 Save Agent antigo ainda esta ocupando a porta 8084 em ' + AHost + '.');
  end;

  Log(ALog, 'Iniciando PS4 Save Agent pelo BinLoader na porta 9090...');
  if TrySendAgentToBinLoader(AHost, ALog) and
     WaitForAgentReady(AHost, 8, ALog) and
     TryGetAgentVersion(AHost, AgentVersion) then
  begin
    Log(ALog, 'PS4 Save Agent atualizado e iniciado em ' + AHost +
      ': ' + AgentVersion);
    Exit;
  end;

  raise Exception.Create('O PS4 Save Agent foi enviado, mas nao respondeu apos o inicio pelo BinLoader em ' + AHost + '.');
end;

function EncodeURLValue(const S: string): string;
begin
  Result := TIdURI.ParamsEncode(S);
end;

procedure DownloadDecryptedSave(const AHost: string; const ASave: TPS4SaveGame;
  const ALocalZip: string; ALog: TPS4SaveAgentLogEvent;
  AProgress: TPS4SaveAgentProgressEvent);
var
  HTTP: TIdHTTP;
  URL: string;
  FS: TFileStream;
  Progress: THTTPProgress;
begin
  ForceDirectories(ExtractFileDir(ALocalZip));
  URL := AgentBaseURL(AHost) + '/api/export_decrypted?user=' +
    EncodeURLValue(ASave.UserID) + '&title=' + EncodeURLValue(ASave.TitleID) +
    '&save=' + EncodeURLValue(ASave.SaveName);

  Log(ALog, 'Baixando save descriptografado de ' + AHost + ': ' +
    ASave.TitleID + ' / ' + ASave.SaveName);

  HTTP := TIdHTTP.Create(nil);
  FS := TFileStream.Create(ALocalZip, fmCreate);
  Progress := THTTPProgress.Create('Baixando ' + ASave.TitleID + ' / ' +
    ASave.SaveName + ' do PS4 origem...', AProgress);
  try
    HTTP.ConnectTimeout := 10000;
    HTTP.ReadTimeout := 300000;
    HTTP.OnWorkBegin := Progress.WorkBegin;
    HTTP.OnWork := Progress.Work;
    HTTP.OnWorkEnd := Progress.WorkEnd;
    try
      HTTP.Get(URL, FS);
    except
      on E: EIdConnClosedGracefully do
      begin
        if TFile.GetSize(ALocalZip) < Length('PS4SAVEPACK1') then
          raise;
        Log(ALog, 'O PS4 Save Agent fechou a conexao apos enviar o pacote completo.');
      end;
    end;
  finally
    Progress.Free;
    FS.Free;
    HTTP.Free;
  end;
end;

function VerifyImportedSave(const AHost, AUserID: string;
  const ASave: TPS4SaveGame): Boolean;
var
  FTP: TIdFTP;
  RemoteDir: string;
  I, K: Integer;
  HasImage, HasMeta: Boolean;
begin
  Result := False;
  RemoteDir := PS4_USER_ROOT + '/home/' + AUserID + '/savedata/' + ASave.TitleID;
  for I := 1 to 8 do
  begin
    FTP := ConnectFTP(AHost, PS4_FTP_PORT);
    try
      HasImage := False;
      HasMeta := False;
      try
        FTP.ChangeDir(RemoteDir);
        FTP.List('', True);
        for K := 0 to FTP.DirectoryListing.Count - 1 do
        begin
          if SameText(FTP.DirectoryListing[K].FileName,
            'sdimg_' + ASave.SaveName) then
            HasImage := True;
          if SameText(FTP.DirectoryListing[K].FileName,
            ASave.SaveName + '.bin') then
            HasMeta := True;
        end;
      except
        HasImage := False;
        HasMeta := False;
      end;
    finally
      if FTP.Connected then
        FTP.Disconnect;
      FTP.Free;
    end;

    if HasImage and HasMeta then
      Exit(True);
    Sleep(1500);
  end;
end;

procedure UploadDecryptedSave(const AHost, ADestUserID: string;
  const ASave: TPS4SaveGame; const ALocalZip: string; ALog: TPS4SaveAgentLogEvent;
  AProgress: TPS4SaveAgentProgressEvent);
var
  HTTP: TIdHTTP;
  FS: TFileStream;
  URL: string;
  Response: string;
  Progress: THTTPProgress;
  Attempt: Integer;
begin
  if not TFile.Exists(ALocalZip) then
    raise Exception.Create('Backup descriptografado nao encontrado para upload: ' + ALocalZip);

  URL := AgentBaseURL(AHost) + '/api/import_decrypted?user=' +
    EncodeURLValue(ADestUserID) + '&title=' + EncodeURLValue(ASave.TitleID) +
    '&save=' + EncodeURLValue(ASave.SaveName) + '&source_user=' +
    EncodeURLValue(ASave.UserID);

  Log(ALog, 'Enviando save descriptografado para ' + AHost + ': ' +
    ASave.TitleID + ' / ' + ASave.SaveName);

  FS := TFileStream.Create(ALocalZip, fmOpenRead or fmShareDenyWrite);
  try
    for Attempt := 1 to 2 do
    begin
      HTTP := TIdHTTP.Create(nil);
      Progress := THTTPProgress.Create('Enviando ' + ASave.TitleID + ' / ' +
        ASave.SaveName + ' para o PS4 destino...', AProgress, FS.Size);
      try
        FS.Position := 0;
        HTTP.ConnectTimeout := 10000;
        { O Agent deve responder assim que terminar a importacao. Nao deixe a
          interface ficar 30 minutos sem diagnostico se o payload travar. }
        HTTP.ReadTimeout := 60000;
        HTTP.Request.ContentType := 'application/octet-stream';
        HTTP.OnWorkBegin := Progress.WorkBegin;
        HTTP.OnWork := Progress.Work;
        HTTP.OnWorkEnd := Progress.WorkEnd;
        if TryPingAgent(AHost) then
          Log(ALog, 'Ping preparatorio respondido pelo PS4 Save Agent.')
        else
          Log(ALog, 'Ping preparatorio sem resposta; enviando mesmo assim.');
        Log(ALog, 'Aguardando confirmacao do PS4 Save Agent...');
        try
          Response := Trim(HTTP.Post(URL, FS));
          if Response <> '' then
            Log(ALog, 'Resposta do import: ' +
              StringReplace(Response, sLineBreak, ' | ', [rfReplaceAll]));
          if not VerifyImportedSave(AHost, ADestUserID, ASave) then
          begin
            Log(ALog, 'O import respondeu, mas os arquivos do save nao foram encontrados no PS4.');
            if Attempt = 2 then
              raise Exception.Create('Importacao nao confirmada no PS4.');
            Log(ALog, 'Tentando enviar o save novamente.');
            Continue;
          end;
          Log(ALog, 'Save confirmado no PS4 via FTP.');
          Exit;
        except
          on E: EIdSocketError do
          begin
            { O Agent pode aplicar o save e fechar o socket sem devolver uma
              resposta HTTP. Nao reinicie nem reenvie nesse caso. }
            if E.LastError = 10054 then
            begin
              Log(ALog, 'O PS4 Save Agent encerrou a conexao; verificando o save no PS4.');
              { Agent morto = nada foi importado; pular a verificacao por FTP
                (~14 s) e ir direto ao reinicio. }
              if TryPingAgent(AHost) and
                 VerifyImportedSave(AHost, ADestUserID, ASave) then
              begin
                Log(ALog, 'Save confirmado no PS4 via FTP.');
                Exit;
              end;
              if Attempt = 2 then
                raise Exception.Create('Conexao encerrada e importacao nao confirmada no PS4.');
              Log(ALog, 'Save nao encontrado; tentando enviar novamente.');
            end;
            if Attempt = 2 then
              raise;
            Log(ALog, 'Falha de socket durante o envio (' + E.Message + ').');
            Log(ALog, 'Tentando reiniciar o PS4 Save Agent e repetir o envio...');
            EnsurePS4SaveAgentReady(AHost, ALog);
          end;
          on E: EIdConnClosedGracefully do
          begin
            Log(ALog, 'O PS4 Save Agent encerrou a conexao; verificando o save no PS4.');
            if VerifyImportedSave(AHost, ADestUserID, ASave) then
            begin
              Log(ALog, 'Save confirmado no PS4 via FTP.');
              Exit;
            end;
            if Attempt = 2 then
              raise Exception.Create('Conexao encerrada e importacao nao confirmada no PS4.');
            Log(ALog, 'Save nao encontrado; tentando enviar novamente.');
          end;
          on E: Exception do
          begin
            if E is EIdHTTPProtocolException then
              Log(ALog, 'Detalhe HTTP do import: ' +
                StringReplace(EIdHTTPProtocolException(E).ErrorMessage,
                  sLineBreak, ' | ', [rfReplaceAll]));
            { As rotas de importacao/exportacao da versao 0.5 sao
              experimentais e podem aplicar o pacote sem devolver HTTP. Se o
              ping continuar respondendo depois do envio, nao bloquear a
              operacao aguardando uma resposta que o Agent nao envia. }
            if ((Pos('TIMEOUT', UpperCase(E.Message)) > 0) or
                (Pos('TIMED OUT', UpperCase(E.Message)) > 0)) and
               VerifyImportedSave(AHost, ADestUserID, ASave) then
            begin
              Log(ALog, 'Save confirmado no PS4 via FTP apos timeout.');
              Exit;
            end;
            if Attempt = 2 then
              raise;
            Log(ALog, 'PS4 Save Agent caiu durante o envio (' + E.Message + ').');
            Log(ALog, 'Tentando reiniciar o PS4 Save Agent e repetir o envio...');
            EnsurePS4SaveAgentReady(AHost, ALog);
          end;
        end;
      finally
        Progress.Free;
        HTTP.Free;
      end;
    end;
  finally
    FS.Free;
  end;
end;

procedure CopySaveOnConsole(const AHost: string; const ALeftUserID,
  ADestUserID: string; const ASave: TPS4SaveGame; ALog: TPS4SaveAgentLogEvent);
var
  HTTP: TIdHTTP;
  Body: TStringStream;
  URL: string;
  Response: string;
begin
  URL := AgentBaseURL(AHost) + '/api/sync_decrypted?source_user=' +
    EncodeURLValue(ALeftUserID) + '&dest_user=' + EncodeURLValue(ADestUserID) +
    '&title=' + EncodeURLValue(ASave.TitleID) + '&save=' +
    EncodeURLValue(ASave.SaveName);

  Log(ALog, 'Copiando save dentro do PS4 pelo payload: ' +
    ASave.TitleID + ' / ' + ASave.SaveName + ' de ' + ALeftUserID +
    ' para ' + ADestUserID);

  HTTP := TIdHTTP.Create(nil);
  Body := TStringStream.Create('', TEncoding.UTF8);
  try
    HTTP.ConnectTimeout := 10000;
    HTTP.ReadTimeout := 300000;
    try
      Response := Trim(HTTP.Post(URL, Body));
      if Response <> '' then
        Log(ALog, 'Resposta do PS4 Save Agent: ' +
          StringReplace(Response, sLineBreak, ' | ', [rfReplaceAll]));
    except
      on E: EIdHTTPProtocolException do
      begin
        Log(ALog, 'Erro do PS4 Save Agent: HTTP ' + IntToStr(E.ErrorCode) +
          ' - ' + Trim(E.ErrorMessage));
        raise Exception.Create('PS4 Save Agent recusou a sincronizacao: HTTP ' +
          IntToStr(E.ErrorCode) + ' - ' + Trim(E.ErrorMessage));
      end;
      on E: EIdConnClosedGracefully do
        Log(ALog, 'PS4 Save Agent fechou a conexao apos processar a requisicao.');
    end;
  finally
    Body.Free;
    HTTP.Free;
  end;
end;

procedure DeletePS4SaveWithAgent(const AHost: string; const ASave: TPS4SaveGame;
  ALog: TPS4SaveAgentLogEvent);
var
  HTTP: TIdHTTP;
  Body: TStringStream;
  URL: string;
  Response: string;
begin
  EnsurePS4SaveAgentReady(AHost, ALog);
  URL := AgentBaseURL(AHost) + '/api/delete_save?user=' +
    EncodeURLValue(ASave.UserID) + '&title=' + EncodeURLValue(ASave.TitleID) +
    '&save=' + EncodeURLValue(ASave.SaveName);

  Log(ALog, 'Deletando save pelo PS4 Save Agent: ' + ASave.TitleID + ' / ' +
    ASave.SaveName + ' usuario ' + ASave.UserID);

  HTTP := TIdHTTP.Create(nil);
  Body := TStringStream.Create('', TEncoding.UTF8);
  try
    HTTP.ConnectTimeout := 10000;
    HTTP.ReadTimeout := 120000;
    Response := Trim(HTTP.Post(URL, Body));
    if Response <> '' then
      Log(ALog, 'Resposta do delete: ' +
        StringReplace(Response, sLineBreak, ' | ', [rfReplaceAll]));
  finally
    Body.Free;
    HTTP.Free;
  end;
end;

procedure CleanupPS4StaleSavesWithAgent(const AHost, AUserID: string;
  ALog: TPS4SaveAgentLogEvent);
var
  HTTP: TIdHTTP;
  Body: TStringStream;
  URL: string;
  Response: string;
begin
  if Trim(AUserID) = '' then
    Exit;

  EnsurePS4SaveAgentReady(AHost, ALog);
  URL := AgentBaseURL(AHost) + '/api/cleanup_saves?user=' +
    EncodeURLValue(AUserID);

  Log(ALog, 'Limpando registros orfaos de saves do usuario ' + AUserID + '...');

  HTTP := TIdHTTP.Create(nil);
  Body := TStringStream.Create('', TEncoding.UTF8);
  try
    HTTP.ConnectTimeout := 10000;
    HTTP.ReadTimeout := 120000;
    Response := Trim(HTTP.Post(URL, Body));
    if Response <> '' then
      Log(ALog, 'Resposta da limpeza: ' +
        StringReplace(Response, sLineBreak, ' | ', [rfReplaceAll]));
  finally
    Body.Free;
    HTTP.Free;
  end;
end;

function SafeFolderName(const S: string): string;
const
  INVALID_CHARS: TSysCharSet = ['\', '/', ':', '*', '?', '"', '<', '>', '|'];
var
  I: Integer;
begin
  Result := Trim(S);
  if Result = '' then
    Result := 'save';
  for I := 1 to Length(Result) do
    if CharInSet(Result[I], INVALID_CHARS) then
      Result[I] := '_';
end;

type
  { Baixa o save N+1 da origem enquanto o save N e importado no destino.
    Origem e destino sao consoles diferentes, entao nao ha disputa. }
  TSaveFetchThread = class(TThread)
  private
    FHost: string;
    FSave: TPS4SaveGame;
    FZipPath: string;
    FLog: TPS4SaveAgentLogEvent;
    FProgress: TPS4SaveAgentProgressEvent;
  protected
    procedure Execute; override;
  public
    ErrorMessage: string;
    constructor Create(const AHost: string; const ASave: TPS4SaveGame;
      const AZipPath: string; ALog: TPS4SaveAgentLogEvent;
      AProgress: TPS4SaveAgentProgressEvent);
  end;

constructor TSaveFetchThread.Create(const AHost: string;
  const ASave: TPS4SaveGame; const AZipPath: string;
  ALog: TPS4SaveAgentLogEvent; AProgress: TPS4SaveAgentProgressEvent);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FHost := AHost;
  FSave := ASave;
  FZipPath := AZipPath;
  FLog := ALog;
  FProgress := AProgress;
end;

procedure TSaveFetchThread.Execute;
begin
  try
    DownloadDecryptedSave(FHost, FSave, FZipPath, FLog, FProgress);
  except
    on E: Exception do
      ErrorMessage := E.Message;
  end;
end;

procedure WaitFetch(AFetch: TSaveFetchThread);
var
  Msg: string;
begin
  AFetch.WaitFor;
  Msg := AFetch.ErrorMessage;
  AFetch.Free;
  if Msg <> '' then
    raise Exception.Create(Msg);
end;

function BackupZipPathFor(const ABackupRoot: string;
  const ASave: TPS4SaveGame): string;
var
  BackupDir: string;
begin
  BackupDir := TPath.Combine(ABackupRoot, SafeFolderName(ASave.TitleID));
  BackupDir := TPath.Combine(BackupDir, SafeFolderName(ASave.SaveName));
  ForceDirectories(BackupDir);
  Result := TPath.Combine(BackupDir, SafeFolderName(ASave.UserID + '_' +
    FormatDateTime('yyyymmdd_hhnnss', Now)) + '.ps4sav');
end;

procedure SyncPS4SavesDecrypted(const ALeftHost, ADestHost: string;
  const ALeftUserID, ADestUserID: string; const ASaves: TArray<TPS4SaveGame>;
  const ABackupRoot: string; ALog: TPS4SaveAgentLogEvent;
  AProgress: TPS4SaveAgentProgressEvent);
var
  WorkSaves: TArray<TPS4SaveGame>;
  ZipPaths: TArray<string>;
  Fetch: TSaveFetchThread;
  I: Integer;
begin
  if Length(ASaves) = 0 then
    raise Exception.Create('Nenhum save selecionado para sincronizar.');

  Log(ALog, 'Preparando PS4 Save Agent na origem...');
  EnsurePS4SaveAgentReady(ALeftHost, ALog);
  Log(ALog, 'Preparando PS4 Save Agent no destino...');
  EnsurePS4SaveAgentReady(ADestHost, ALog);

  ForceDirectories(ABackupRoot);
  SetLength(WorkSaves, Length(ASaves));
  SetLength(ZipPaths, Length(ASaves));
  for I := 0 to High(ASaves) do
  begin
    WorkSaves[I] := ASaves[I];
    WorkSaves[I].UserID := ALeftUserID;
    ZipPaths[I] := BackupZipPathFor(ABackupRoot, WorkSaves[I]);
  end;

  if Assigned(AProgress) then
    AProgress(Format('Save 1 de %d: %s / %s',
      [Length(ASaves), WorkSaves[0].TitleID, WorkSaves[0].SaveName]), 0, 0);
  DownloadDecryptedSave(ALeftHost, WorkSaves[0], ZipPaths[0], ALog, AProgress);

  for I := 0 to High(ASaves) do
  begin
    Fetch := nil;
    if I < High(ASaves) then
      Fetch := TSaveFetchThread.Create(ALeftHost, WorkSaves[I + 1],
        ZipPaths[I + 1], ALog, nil);
    try
      if Assigned(AProgress) then
        AProgress(Format('Save %d de %d: %s / %s',
          [I + 1, Length(ASaves), WorkSaves[I].TitleID, WorkSaves[I].SaveName]), 0, 0);
      UploadDecryptedSave(ADestHost, ADestUserID, WorkSaves[I], ZipPaths[I],
        ALog, AProgress);
    except
      if Fetch <> nil then
      begin
        Fetch.WaitFor;
        Fetch.Free;
      end;
      raise;
    end;
    if Fetch <> nil then
      WaitFetch(Fetch);
  end;
end;

procedure SyncPS4SavesOnConsole(const AHost: string;
  const ALeftUserID, ADestUserID: string; const ASaves: TArray<TPS4SaveGame>;
  ALog: TPS4SaveAgentLogEvent);
var
  Save: TPS4SaveGame;
  Attempt: Integer;
begin
  if Length(ASaves) = 0 then
    raise Exception.Create('Nenhum save selecionado para sincronizar.');
  if SameText(ALeftUserID, ADestUserID) then
    raise Exception.Create('O usuario de origem e destino precisa ser diferente.');

  Log(ALog, 'Preparando PS4 Save Agent em ' + AHost + '...');
  EnsurePS4SaveAgentReady(AHost, ALog);

  for Save in ASaves do
  begin
    for Attempt := 1 to 3 do
    begin
      try
        CopySaveOnConsole(AHost, ALeftUserID, ADestUserID, Save, ALog);
      except
        on E: Exception do
        begin
          { O payload pode aplicar o save e fechar o socket antes de devolver
            uma resposta HTTP. Primeiro confirme pelo FTP; somente se o save
            nao estiver no destino devemos preparar o Agent e repetir. }
          if VerifyImportedSave(AHost, ADestUserID, Save) then
          begin
            Log(ALog, 'Save confirmado no destino via FTP apos erro de comunicacao.');
            Break;
          end;

          if Attempt = 3 then
            raise;

          Log(ALog, 'Falha na copia dentro do PS4 (' + E.Message + ').');
          Log(ALog, Format('Save nao confirmado no destino (tentativa %d/3).',
            [Attempt]));
          Log(ALog, 'Tentando reiniciar o PS4 Save Agent e repetir a copia...');
          EnsurePS4SaveAgentReady(AHost, ALog);
        end;
      end;

      if VerifyImportedSave(AHost, ADestUserID, Save) then
      begin
        Log(ALog, 'Save confirmado no destino via FTP.');
        Break;
      end;

      Log(ALog, Format('Save nao confirmado no destino (tentativa %d/3).',
        [Attempt]));
      if Attempt = 3 then
        raise Exception.Create('Sync nao confirmado no PS4 destino para ' +
          Save.TitleID + ' / ' + Save.SaveName);
    end;
  end;
end;

{ ------------------------------------------------------------------------- }
{ Remocao de fundo                                                          }
{ ------------------------------------------------------------------------- }

const
  BG_MAX_INPUT_BYTES = 20 * 1024 * 1024;
  BG_LOCAL_TIMEOUT_MS = 300000;
  BG_CONNECT_TIMEOUT_MS = 15000;
  BG_RESPONSE_TIMEOUT_MS = 120000;
  BG_REMOVEBG_URL = 'https://api.remove.bg/v1.0/removebg';
  BG_API_KEY_ENV = 'REMOVEBG_API_KEY';
  BG_SETTINGS_SECTION = 'BackgroundRemoval';
  BG_DEFAULT_MODEL = 'u2net_human_seg';
  BG_PNG_SIGNATURE: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);

function BgReadSetting(const AName, ADefault: string): string;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(TPath.Combine(ExtractFilePath(ParamStr(0)), 'PS4Tools.ini'));
  try
    Result := Trim(Ini.ReadString(BG_SETTINGS_SECTION, AName, ADefault));
  finally
    Ini.Free;
  end;
end;

function BgReadHeader(const AFileName: string; ACount: Integer): TBytes;
var
  FS: TFileStream;
  Count: Integer;
begin
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, ACount);
    Count := FS.Read(Result[0], ACount);
    SetLength(Result, Count);
  finally
    FS.Free;
  end;
end;

function BgIsPngFile(const AFileName: string): Boolean;
var
  Header: TBytes;
begin
  Result := False;
  if not TFile.Exists(AFileName) then
    Exit;
  Header := BgReadHeader(AFileName, SizeOf(BG_PNG_SIGNATURE));
  Result := (Length(Header) = SizeOf(BG_PNG_SIGNATURE)) and
    CompareMem(@BG_PNG_SIGNATURE[0], @Header[0], SizeOf(BG_PNG_SIGNATURE));
end;

function BgIsJpegFile(const AFileName: string): Boolean;
var
  Header: TBytes;
begin
  Header := BgReadHeader(AFileName, 3);
  Result := (Length(Header) = 3) and (Header[0] = $FF) and (Header[1] = $D8) and
    (Header[2] = $FF);
end;

{ True somente se o PNG tem pelo menos um pixel nao totalmente opaco. }
function PngFileHasTransparency(const AFileName: string): Boolean;
var
  Png: TPngImage;
  X, Y: Integer;
  Alpha: PByteArray;
begin
  Result := False;
  if not BgIsPngFile(AFileName) then
    Exit;
  Png := TPngImage.Create;
  try
    try
      Png.LoadFromFile(AFileName);
    except
      Exit;
    end;
    if Png.Header.ColorType in [COLOR_RGBALPHA, COLOR_GRAYSCALEALPHA] then
    begin
      for Y := 0 to Png.Height - 1 do
      begin
        Alpha := Png.AlphaScanline[Y];
        if Alpha = nil then
          Continue;
        for X := 0 to Png.Width - 1 do
          if Alpha^[X] < 255 then
            Exit(True);
      end;
    end
    else
      Result := Png.TransparencyMode <> ptmNone;
  finally
    Png.Free;
  end;
end;

{ Fracao (0..1) de pixels nao totalmente opacos de um PNG com canal alfa; 0 se
  o arquivo nao for PNG ou nao tiver alfa. Serve para saber se a imagem ja vem
  transparente e dispensa a remocao de fundo. }
function PngTransparencyShare(const AFileName: string): Double;
var
  Png: TPngImage;
  X, Y, Count: Integer;
  Alpha: PByte;
begin
  Result := 0;
  if not BgIsPngFile(AFileName) then
    Exit;
  Png := TPngImage.Create;
  try
    try
      Png.LoadFromFile(AFileName);
    except
      Exit;
    end;
    if not (Png.Header.ColorType in [COLOR_RGBALPHA, COLOR_GRAYSCALEALPHA]) then
      Exit;
    if (Png.Width <= 0) or (Png.Height <= 0) then
      Exit;
    Count := 0;
    for Y := 0 to Png.Height - 1 do
    begin
      Alpha := PByte(Png.AlphaScanline[Y]);
      if Alpha = nil then
        Continue;
      for X := 0 to Png.Width - 1 do
        if PByte(NativeUInt(Alpha) + NativeUInt(X))^ < 255 then
          Inc(Count);
    end;
    Result := Count / (Int64(Png.Width) * Png.Height);
  finally
    Png.Free;
  end;
end;

{ Fracao (0..1) de pixels com alfa >= 128 em um PNG RGBA: quanto da imagem
  restou depois da remocao de fundo. }
function BgPngForegroundShare(const AFileName: string): Double;
var
  Png: TPngImage;
  X, Y, Count: Integer;
  Alpha: PByte;
begin
  Result := 1;
  Png := TPngImage.Create;
  try
    try
      Png.LoadFromFile(AFileName);
    except
      Exit;
    end;
    if (Png.Width <= 0) or (Png.Height <= 0) then
      Exit;
    Count := 0;
    for Y := 0 to Png.Height - 1 do
    begin
      Alpha := PByte(Png.AlphaScanline[Y]);
      if Alpha = nil then
      begin
        Inc(Count, Png.Width);
        Continue;
      end;
      for X := 0 to Png.Width - 1 do
        if PByte(NativeUInt(Alpha) + NativeUInt(X))^ >= 128 then
          Inc(Count);
    end;
    Result := Count / (Int64(Png.Width) * Png.Height);
  finally
    Png.Free;
  end;
end;

function BgValidateInput(const AInputFile: string; out AError: string): Boolean;
var
  Ext: string;
begin
  Result := False;
  AError := '';
  if Trim(AInputFile) = '' then
    AError := 'Nenhuma imagem foi informada.'
  else if not TFile.Exists(AInputFile) then
    AError := 'Imagem nao encontrada: ' + AInputFile
  else
  begin
    Ext := LowerCase(ExtractFileExt(AInputFile));
    if (Ext <> '.jpg') and (Ext <> '.jpeg') and (Ext <> '.png') then
      AError := 'Formato nao suportado (' + Ext + '). Use JPEG ou PNG.'
    else if TFile.GetSize(AInputFile) > BG_MAX_INPUT_BYTES then
      AError := Format('A imagem passa de %d MB.', [BG_MAX_INPUT_BYTES div (1024 * 1024)])
    else if TFile.GetSize(AInputFile) = 0 then
      AError := 'A imagem esta vazia.'
    else if not (BgIsPngFile(AInputFile) or BgIsJpegFile(AInputFile)) then
      AError := 'O conteudo do arquivo nao e uma imagem JPEG/PNG valida.'
    else
      Result := True;
  end;
end;

{ Unico lugar onde o rembg.exe e procurado: core\onnx\rembg.exe (ou o caminho
  de RembgPath em PS4Tools.ini). Se o arquivo nao existir, vale o onnxruntime
  direto da UnitFunctions. }
function BgFindRembgExe: string;
begin
  Result := BgReadSetting('RembgPath', '');
  if (Result <> '') and TFile.Exists(Result) then
    Exit;
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'core\onnx\rembg.exe');
  if not TFile.Exists(Result) then
    Result := '';
end;

function BgFindApiKey: string;
begin
  { A chave nunca fica no codigo: variavel de ambiente ou PS4Tools.ini. }
  Result := Trim(GetEnvironmentVariable(BG_API_KEY_ENV));
  if Result = '' then
    Result := BgReadSetting('ApiKey', '');
end;

function BgSafeModelName(const AModel: string): string;
var
  C: Char;
begin
  Result := '';
  for C in AModel do
    if CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '_', '-']) then
      Result := Result + C;
  if Result = '' then
    Result := BG_DEFAULT_MODEL;
end;

function BgReadLogTail(const ALogFile: string): string;
begin
  Result := '';
  try
    if TFile.Exists(ALogFile) then
    begin
      Result := Trim(TFile.ReadAllText(ALogFile, TEncoding.UTF8));
      if Length(Result) > 600 then
        Result := Copy(Result, Length(Result) - 599, 600);
    end;
  except
    Result := '';
  end;
end;

{ Executa um programa sem janela, grava stdout/stderr em ALogFile e espera ate
  ATimeoutMs. Se o chamador estiver na thread principal, continua tratando as
  mensagens para a tela nao congelar. }
function BgRunProcess(const ACommandLine, ALogFile: string; ATimeoutMs: Cardinal;
  out AExitCode: Cardinal; out ATimedOut: Boolean): Boolean;
var
  Security: TSecurityAttributes;
  StartInfo: TStartupInfo;
  ProcInfo: TProcessInformation;
  LogHandle, NulHandle: THandle;
  CmdLine: string;
  StartedAt: UInt64;
  WaitResult: DWORD;
begin
  Result := False;
  AExitCode := 0;
  ATimedOut := False;

  FillChar(Security, SizeOf(Security), 0);
  Security.nLength := SizeOf(Security);
  Security.bInheritHandle := True;

  LogHandle := CreateFile(PChar(ALogFile), GENERIC_WRITE, FILE_SHARE_READ,
    @Security, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  NulHandle := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
    @Security, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  try
    if (LogHandle = INVALID_HANDLE_VALUE) or (NulHandle = INVALID_HANDLE_VALUE) then
      Exit;

    FillChar(StartInfo, SizeOf(StartInfo), 0);
    StartInfo.cb := SizeOf(StartInfo);
    StartInfo.dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
    StartInfo.wShowWindow := SW_HIDE;
    StartInfo.hStdInput := NulHandle;
    StartInfo.hStdOutput := LogHandle;
    StartInfo.hStdError := LogHandle;
    FillChar(ProcInfo, SizeOf(ProcInfo), 0);

    CmdLine := ACommandLine;
    UniqueString(CmdLine);
    if not CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW,
         nil, nil, StartInfo, ProcInfo) then
      Exit;
    try
      CloseHandle(ProcInfo.hThread);
      StartedAt := GetTickCount64;
      repeat
        WaitResult := WaitForSingleObject(ProcInfo.hProcess, 100);
        if (WaitResult = WAIT_OBJECT_0) then
          Break;
        if GetCurrentThreadId = MainThreadID then
          Application.ProcessMessages;
        if GetTickCount64 - StartedAt > ATimeoutMs then
        begin
          ATimedOut := True;
          TerminateProcess(ProcInfo.hProcess, 1);
          WaitForSingleObject(ProcInfo.hProcess, 5000);
          Break;
        end;
      until False;
      Result := GetExitCodeProcess(ProcInfo.hProcess, AExitCode);
    finally
      CloseHandle(ProcInfo.hProcess);
    end;
  finally
    if LogHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(LogHandle);
    if NulHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(NulHandle);
  end;
end;

{ Alternativa A: rembg (U2-Net) local. A primeira execucao baixa o modelo. }
function BgRemoveWithRembg(const ARembgExe, AInputFile, AOutputTmp: string;
  out AError: string): Boolean;
var
  Model, CmdLine, LogFile, Extra: string;
  ExitCode: Cardinal;
  TimedOut: Boolean;
begin
  Result := False;
  AError := '';
  Model := BgSafeModelName(BgReadSetting('Model', BG_DEFAULT_MODEL));
  { Alpha matting melhora fios de cabelo, mas exige as dependencias extras do
    rembg e e bem mais lento; desligado por padrao (AlphaMatting=1 liga). }
  if BgReadSetting('AlphaMatting', '0') = '1' then
    Extra := ' -a -ae 15'
  else
    Extra := '';
  CmdLine := '"' + ARembgExe + '" i -m ' + Model + Extra + ' "' + AInputFile +
    '" "' + AOutputTmp + '"';
  LogFile := TPath.Combine(TPath.GetTempPath,
    'ps4tools_rembg_' + IntToStr(GetCurrentProcessId) + '.log');
  try
    if not BgRunProcess(CmdLine, LogFile, BG_LOCAL_TIMEOUT_MS, ExitCode, TimedOut) then
    begin
      AError := 'Nao foi possivel executar o rembg: ' + ARembgExe;
      Exit;
    end;
    if TimedOut then
    begin
      AError := Format('O rembg passou de %d s e foi encerrado. Na primeira execucao ' +
        'ele baixa o modelo; tente de novo com a internet ligada.',
        [BG_LOCAL_TIMEOUT_MS div 1000]);
      Exit;
    end;
    if ExitCode <> 0 then
    begin
      AError := Format('O rembg terminou com erro (codigo %d). %s',
        [ExitCode, BgReadLogTail(LogFile)]);
      Exit;
    end;
    Result := True;
  finally
    if TFile.Exists(LogFile) then
      TFile.Delete(LogFile);
  end;
end;

{ Alternativa B: API HTTP remove.bg (multipart/form-data). Envia a foto para um
  servico externo; so e usada se uma chave for configurada de proposito. }
function BgRemoveWithApi(const AApiKey, AInputFile, AOutputTmp: string;
  out AError: string): Boolean;
var
  Client: THTTPClient;
  Form: TMultipartFormData;
  Body: TMemoryStream;
  Response: IHTTPResponse;
  Headers: TNetHeaders;
  Bytes: TBytes;
  Detail: string;
begin
  Result := False;
  AError := '';
  Client := THTTPClient.Create;
  Form := TMultipartFormData.Create;
  Body := TMemoryStream.Create;
  try
    Client.ConnectionTimeout := BG_CONNECT_TIMEOUT_MS;
    Client.ResponseTimeout := BG_RESPONSE_TIMEOUT_MS;
    Form.AddFile('image_file', AInputFile);
    Form.AddField('size', 'auto');
    Form.AddField('format', 'png');
    SetLength(Headers, 1);
    Headers[0] := TNameValuePair.Create('X-Api-Key', AApiKey);

    Response := Client.Post(BG_REMOVEBG_URL, Form, Body, Headers);
    if Response.StatusCode <> 200 then
    begin
      Detail := '';
      if Body.Size > 0 then
      begin
        SetLength(Bytes, Body.Size);
        Body.Position := 0;
        Body.ReadBuffer(Bytes[0], Body.Size);
        Detail := Trim(TEncoding.UTF8.GetString(Bytes));
        if Length(Detail) > 300 then
          Detail := Copy(Detail, 1, 300);
      end;
      AError := Format('A API de remocao de fundo respondeu HTTP %d. %s',
        [Response.StatusCode, Detail]);
      Exit;
    end;
    if Body.Size = 0 then
    begin
      AError := 'A API de remocao de fundo respondeu sem imagem.';
      Exit;
    end;
    Body.SaveToFile(AOutputTmp);
    Result := True;
  finally
    Body.Free;
    Form.Free;
    Client.Free;
  end;
end;

{ Alternativa C: o mesmo pipeline do rembg (sessions/u2net_human_seg.py +
  bg.naive_cutout) executado direto pelo onnxruntime.dll, sem Python e sem
  rembg.exe:
    1. imagem -> RGB, reduzida para 320x320;
    2. valores divididos pelo maior valor da imagem reduzida (nao por 255),
       depois (v - media) / desvio com media (0.485, 0.456, 0.406) e desvio
       (0.229, 0.224, 0.225), em formato NCHW float32;
    3. primeira saida do modelo, canal 0, normalizada por min-max para 0..1;
    4. a mascara e ampliada ate o tamanho original e vira o canal alfa.
  Chama a C API do onnxruntime (OrtApi) por indice na tabela de funcoes; os
  indices abaixo vem de onnxruntime_c_api.h da versao 1.17 (ORT_API_VERSION 17),
  que e estavel porque a tabela so cresce no fim. O programa e 32 bits, entao a
  DLL precisa ser a x86. }
const
  ORT_API_VERSION_USED = 17;
  ORT_LOGGING_LEVEL_WARNING = 2;
  ORT_ENABLE_ALL = 99;
  ORT_ARENA_ALLOCATOR = 1;
  ORT_MEM_TYPE_DEFAULT = 0;
  ORT_TENSOR_FLOAT = 1;
  ORT_IDX_GET_ERROR_MESSAGE = 2;
  ORT_IDX_CREATE_ENV = 3;
  ORT_IDX_CREATE_SESSION = 7;
  ORT_IDX_RUN = 9;
  ORT_IDX_CREATE_SESSION_OPTIONS = 10;
  ORT_IDX_SET_GRAPH_OPTIMIZATION = 23;
  ORT_IDX_SET_INTRA_OP_THREADS = 24;
  ORT_IDX_SESSION_GET_INPUT_NAME = 36;
  ORT_IDX_SESSION_GET_OUTPUT_NAME = 37;
  ORT_IDX_CREATE_TENSOR_WITH_DATA = 49;
  ORT_IDX_GET_TENSOR_MUTABLE_DATA = 51;
  ORT_IDX_GET_DIMENSIONS_COUNT = 61;
  ORT_IDX_GET_DIMENSIONS = 62;
  ORT_IDX_GET_TENSOR_TYPE_AND_SHAPE = 65;
  ORT_IDX_CREATE_CPU_MEMORY_INFO = 69;
  ORT_IDX_ALLOCATOR_FREE = 76;
  ORT_IDX_GET_ALLOCATOR = 78;
  ORT_IDX_RELEASE_ENV = 92;
  ORT_IDX_RELEASE_STATUS = 93;
  ORT_IDX_RELEASE_MEMORY_INFO = 94;
  ORT_IDX_RELEASE_SESSION = 95;
  ORT_IDX_RELEASE_VALUE = 96;
  ORT_IDX_RELEASE_TENSOR_TYPE_AND_SHAPE = 99;
  ORT_IDX_RELEASE_SESSION_OPTIONS = 100;
  BG_ONNX_INPUT_SIZE = 320;
  BG_ONNX_DEFAULT_MODEL = 'u2net_human_seg.onnx';
  BG_ONNX_GENERAL_MODEL = 'u2net.onnx';
  BG_MIN_FOREGROUND_SHARE = 0.08;

type
  TOrtGetApiBaseFn = function: Pointer; stdcall;
  TOrtGetApiFn = function(AVersion: Cardinal): Pointer; stdcall;
  TOrtGetErrorMessageFn = function(AStatus: Pointer): PAnsiChar; stdcall;
  TOrtReleaseFn = procedure(AHandle: Pointer); stdcall;
  TOrtCreateEnvFn = function(ALogLevel: Integer; ALogId: PAnsiChar;
    out AEnv: Pointer): Pointer; stdcall;
  TOrtCreateSessionOptionsFn = function(out AOptions: Pointer): Pointer; stdcall;
  TOrtSetIntFn = function(AOptions: Pointer; AValue: Integer): Pointer; stdcall;
  TOrtCreateSessionFn = function(AEnv: Pointer; AModelPath: PWideChar;
    AOptions: Pointer; out ASession: Pointer): Pointer; stdcall;
  TOrtGetAllocatorFn = function(out AAllocator: Pointer): Pointer; stdcall;
  TOrtSessionGetNameFn = function(ASession: Pointer; AIndex: NativeUInt;
    AAllocator: Pointer; out AName: PAnsiChar): Pointer; stdcall;
  TOrtAllocatorFreeFn = function(AAllocator: Pointer; AMemory: Pointer): Pointer; stdcall;
  TOrtCreateCpuMemoryInfoFn = function(AAllocType, AMemType: Integer;
    out AInfo: Pointer): Pointer; stdcall;
  TOrtCreateTensorFn = function(AInfo: Pointer; AData: Pointer; ADataLen: NativeUInt;
    AShape: PInt64; AShapeLen: NativeUInt; AElementType: Integer;
    out AValue: Pointer): Pointer; stdcall;
  TOrtRunFn = function(ASession: Pointer; ARunOptions: Pointer;
    AInputNames: PPAnsiChar; AInputs: PPointer; AInputCount: NativeUInt;
    AOutputNames: PPAnsiChar; AOutputCount: NativeUInt;
    AOutputs: PPointer): Pointer; stdcall;
  TOrtGetTensorDataFn = function(AValue: Pointer; out AData: Pointer): Pointer; stdcall;
  TOrtGetTypeAndShapeFn = function(AValue: Pointer; out AInfo: Pointer): Pointer; stdcall;
  TOrtGetDimensionsCountFn = function(AInfo: Pointer; out ACount: NativeUInt): Pointer; stdcall;
  TOrtGetDimensionsFn = function(AInfo: Pointer; ADims: PInt64;
    ACount: NativeUInt): Pointer; stdcall;

function OrtApiFn(AApi: Pointer; AIndex: Integer): Pointer;
begin
  Result := PPointer(NativeUInt(AApi) + NativeUInt(AIndex) * SizeOf(Pointer))^;
end;

function BgOnnxDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'core\onnx');
end;

function BgFindOnnxRuntimeDll: string;
begin
  Result := BgReadSetting('OnnxRuntimePath', '');
  if (Result = '') or not TFile.Exists(Result) then
    Result := TPath.Combine(BgOnnxDir, 'onnxruntime.dll');
  if not TFile.Exists(Result) then
    Result := '';
end;

{ Rosto: u2net_human_seg (treinado para pessoas). Figuras: se existir, o
  modelo geral u2net.onnx (objeto de destaque qualquer: personagens,
  ilustracoes); sem ele usa o de pessoas, que falha em quem nao e humano. }
function BgFindOnnxModel(AMode: TBgMode): string;
begin
  if AMode = bmFigure then
  begin
    Result := BgReadSetting('OnnxModelFigure', '');
    if (Result = '') or not TFile.Exists(Result) then
      Result := TPath.Combine(BgOnnxDir, BG_ONNX_GENERAL_MODEL);
    if TFile.Exists(Result) then
      Exit;
  end;
  Result := BgReadSetting('OnnxModelPath', '');
  if (Result = '') or not TFile.Exists(Result) then
    Result := TPath.Combine(BgOnnxDir, BG_ONNX_DEFAULT_MODEL);
  if not TFile.Exists(Result) then
    Result := '';
end;

{ Reduz a imagem por media de area para ASize x ASize e monta o tensor NCHW
  float32 como em BaseSession.normalize do rembg. }
procedure BgBuildModelInput(ABitmap: TBitmap; ASize: Integer;
  out AData: TArray<Single>);
const
  MEAN: array[0..2] of Single = (0.485, 0.456, 0.406);
  STD: array[0..2] of Single = (0.229, 0.224, 0.225);
var
  Pixels: TArray<Byte>;
  Acc: TArray<Cardinal>;
  X0, X1: TArray<Integer>;
  W, H, DX, DY, SX, SY, Y0, Y1, C, Count: Integer;
  Line: PByte;
  MaxValue: Single;
begin
  W := ABitmap.Width;
  H := ABitmap.Height;
  SetLength(Pixels, ASize * ASize * 3);
  SetLength(Acc, ASize * 3);
  SetLength(X0, ASize);
  SetLength(X1, ASize);
  for DX := 0 to ASize - 1 do
  begin
    X0[DX] := (DX * W) div ASize;
    X1[DX] := ((DX + 1) * W) div ASize;
    if X1[DX] <= X0[DX] then
      X1[DX] := X0[DX] + 1;
    if X1[DX] > W then
      X1[DX] := W;
    if X0[DX] >= X1[DX] then
      X0[DX] := X1[DX] - 1;
  end;

  for DY := 0 to ASize - 1 do
  begin
    Y0 := (DY * H) div ASize;
    Y1 := ((DY + 1) * H) div ASize;
    if Y1 <= Y0 then
      Y1 := Y0 + 1;
    if Y1 > H then
      Y1 := H;
    if Y0 >= Y1 then
      Y0 := Y1 - 1;
    for C := 0 to High(Acc) do
      Acc[C] := 0;
    for SY := Y0 to Y1 - 1 do
    begin
      Line := ABitmap.ScanLine[SY];
      for DX := 0 to ASize - 1 do
        for SX := X0[DX] to X1[DX] - 1 do
        begin
          { pf24bit guarda B, G, R }
          Inc(Acc[DX * 3 + 0], PByte(NativeUInt(Line) + NativeUInt(SX) * 3 + 2)^);
          Inc(Acc[DX * 3 + 1], PByte(NativeUInt(Line) + NativeUInt(SX) * 3 + 1)^);
          Inc(Acc[DX * 3 + 2], PByte(NativeUInt(Line) + NativeUInt(SX) * 3 + 0)^);
        end;
    end;
    for DX := 0 to ASize - 1 do
    begin
      Count := (Y1 - Y0) * (X1[DX] - X0[DX]);
      for C := 0 to 2 do
        Pixels[(DY * ASize + DX) * 3 + C] := Byte((Acc[DX * 3 + C] + Cardinal(Count div 2)) div Cardinal(Count));
    end;
  end;

  MaxValue := 0;
  for C := 0 to High(Pixels) do
    if Pixels[C] > MaxValue then
      MaxValue := Pixels[C];
  if MaxValue < 0.000001 then
    MaxValue := 0.000001;

  SetLength(AData, 3 * ASize * ASize);
  for C := 0 to 2 do
    for DY := 0 to ASize - 1 do
      for DX := 0 to ASize - 1 do
        AData[(C * ASize + DY) * ASize + DX] :=
          (Pixels[(DY * ASize + DX) * 3 + C] / MaxValue - MEAN[C]) / STD[C];
end;

{ Le o campo Machine do cabecalho PE: $14C = x86, $8664 = x64, 0 = ilegivel. }
function BgPeMachine(const AFileName: string): Word;
var
  Header: TBytes;
  PeOffset: Integer;
begin
  Result := 0;
  try
    Header := BgReadHeader(AFileName, 1024);
    if Length(Header) < $40 then
      Exit;
    PeOffset := PInteger(@Header[$3C])^;
    if (PeOffset < 0) or (PeOffset + 6 > Length(Header)) then
      Exit;
    if PCardinal(@Header[PeOffset])^ <> $00004550 then { 'PE'#0#0 }
      Exit;
    Result := PWord(@Header[PeOffset + 4])^;
  except
    Result := 0;
  end;
end;

function BgRemoveWithOnnx(const ADllPath, AModelPath, AInputFile, AOutputTmp: string;
  out AError: string): Boolean;
var
  Lib: HMODULE;
  GetApiBase: TOrtGetApiBaseFn;
  ApiBase: Pointer;
  Api: Pointer;
  GetErrorMessage: TOrtGetErrorMessageFn;
  ReleaseStatus, ReleaseEnv, ReleaseOptions, ReleaseSession, ReleaseValue,
    ReleaseMemInfo, ReleaseShapeInfo: TOrtReleaseFn;
  Env, Options, Session, Allocator, MemInfo, InputTensor, OutputTensor,
    ShapeInfo, OutData: Pointer;
  InputName, OutputName: PAnsiChar;
  InputNames, OutputNames: array[0..0] of PAnsiChar;
  Inputs, Outputs: array[0..0] of Pointer;
  Shape: array[0..3] of Int64;
  Dims: array[0..7] of Int64;
  DimCount: NativeUInt;
  Pic: TPicture;
  Bmp: TBitmap;
  Png: TPngImage;
  Data: TArray<Single>;
  MaskPtr: PSingle;
  Mask: TArray<Single>;
  MaskW, MaskH, MaskCount, I: Integer;
  MinV, MaxV, V: Single;
  W, H, X, Y, XA, YA: Integer;
  FX, FY, WX, WY, V0, V1: Single;
  ColX0, ColX1: TArray<Integer>;
  ColW: TArray<Single>;
  Alpha: PByteArray;
  Row: PByte;
  Status: Pointer;
  Threads: Integer;
  DllMachine: Word;

  procedure Check(AStatus: Pointer; const AWhat: string);
  var
    Msg: string;
  begin
    if AStatus = nil then
      Exit;
    Msg := string(AnsiString(GetErrorMessage(AStatus)));
    ReleaseStatus(AStatus);
    raise Exception.Create('onnxruntime: ' + AWhat + ' falhou: ' + Msg);
  end;

begin
  Result := False;
  AError := '';
  Lib := 0;
  GetErrorMessage := nil; ReleaseStatus := nil; ReleaseEnv := nil;
  ReleaseOptions := nil; ReleaseSession := nil; ReleaseValue := nil;
  ReleaseMemInfo := nil; ReleaseShapeInfo := nil;
  Env := nil; Options := nil; Session := nil; MemInfo := nil;
  InputTensor := nil; OutputTensor := nil; ShapeInfo := nil;
  InputName := nil; OutputName := nil; Allocator := nil;
  Pic := nil; Bmp := nil; Png := nil;
  try
    try
      { Erro 193 do LoadLibrary = DLL de outra arquitetura: avisar com clareza. }
      DllMachine := BgPeMachine(ADllPath);
{$IFDEF CPUX64}
      if (DllMachine <> 0) and (DllMachine <> $8664) then
        raise Exception.Create('A onnxruntime.dll em ' + ADllPath +
          ' nao e de 64 bits, mas o programa e de 64 bits. Use a DLL x64.');
{$ELSE}
      if (DllMachine <> 0) and (DllMachine <> $14C) then
        raise Exception.Create('A onnxruntime.dll em ' + ADllPath + ' e de ' +
          IfThen(DllMachine = $8664, '64', 'outra arquitetura de') +
          ' bits, mas o programa e de 32 bits. Use a DLL x86 (win-x86) ou ' +
          'compile o programa para Win64.');
{$ENDIF}
      Lib := LoadLibraryEx(PChar(ADllPath), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
      if Lib = 0 then
        raise Exception.Create('Nao foi possivel carregar ' + ADllPath +
          ' (erro ' + IntToStr(GetLastError) + '). Falta alguma dependencia, ' +
          'como o Visual C++ Redistributable?');
      @GetApiBase := GetProcAddress(Lib, 'OrtGetApiBase');
      if not Assigned(GetApiBase) then
        @GetApiBase := GetProcAddress(Lib, '_OrtGetApiBase@0');
      if not Assigned(GetApiBase) then
        raise Exception.Create('A DLL nao exporta OrtGetApiBase.');
      ApiBase := GetApiBase;
      Api := TOrtGetApiFn(PPointer(ApiBase)^)(ORT_API_VERSION_USED);
      if Api = nil then
        raise Exception.Create('A DLL do onnxruntime e mais antiga que a 1.17.');

      GetErrorMessage := TOrtGetErrorMessageFn(OrtApiFn(Api, ORT_IDX_GET_ERROR_MESSAGE));
      ReleaseStatus := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_STATUS));
      ReleaseEnv := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_ENV));
      ReleaseOptions := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_SESSION_OPTIONS));
      ReleaseSession := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_SESSION));
      ReleaseValue := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_VALUE));
      ReleaseMemInfo := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_MEMORY_INFO));
      ReleaseShapeInfo := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_TENSOR_TYPE_AND_SHAPE));

      { --- imagem de entrada -> bitmap 24 bits sobre fundo branco --- }
      Pic := TPicture.Create;
      Pic.LoadFromFile(AInputFile);
      if (Pic.Width <= 0) or (Pic.Height <= 0) then
        raise Exception.Create('Imagem invalida.');
      Bmp := TBitmap.Create;
      Bmp.PixelFormat := pf24bit;
      Bmp.SetSize(Pic.Width, Pic.Height);
      Bmp.Canvas.Brush.Color := clWhite;
      Bmp.Canvas.FillRect(Rect(0, 0, Bmp.Width, Bmp.Height));
      Bmp.Canvas.Draw(0, 0, Pic.Graphic);
      W := Bmp.Width;
      H := Bmp.Height;
      FreeAndNil(Pic);

      BgBuildModelInput(Bmp, BG_ONNX_INPUT_SIZE, Data);

      { --- sessao --- }
      Check(TOrtCreateEnvFn(OrtApiFn(Api, ORT_IDX_CREATE_ENV))(
        ORT_LOGGING_LEVEL_WARNING, 'ps4tools', Env), 'CreateEnv');
      Check(TOrtCreateSessionOptionsFn(OrtApiFn(Api, ORT_IDX_CREATE_SESSION_OPTIONS))(
        Options), 'CreateSessionOptions');
      Threads := TThread.ProcessorCount;
      if Threads > 4 then
        Threads := 4;
      if Threads < 1 then
        Threads := 1;
      Check(TOrtSetIntFn(OrtApiFn(Api, ORT_IDX_SET_INTRA_OP_THREADS))(
        Options, Threads), 'SetIntraOpNumThreads');
      Check(TOrtSetIntFn(OrtApiFn(Api, ORT_IDX_SET_GRAPH_OPTIMIZATION))(
        Options, ORT_ENABLE_ALL), 'SetSessionGraphOptimizationLevel');
      Check(TOrtCreateSessionFn(OrtApiFn(Api, ORT_IDX_CREATE_SESSION))(
        Env, PWideChar(AModelPath), Options, Session), 'CreateSession (modelo)');

      Check(TOrtGetAllocatorFn(OrtApiFn(Api, ORT_IDX_GET_ALLOCATOR))(Allocator),
        'GetAllocatorWithDefaultOptions');
      Check(TOrtSessionGetNameFn(OrtApiFn(Api, ORT_IDX_SESSION_GET_INPUT_NAME))(
        Session, 0, Allocator, InputName), 'SessionGetInputName');
      Check(TOrtSessionGetNameFn(OrtApiFn(Api, ORT_IDX_SESSION_GET_OUTPUT_NAME))(
        Session, 0, Allocator, OutputName), 'SessionGetOutputName');

      { --- tensor de entrada e execucao --- }
      Check(TOrtCreateCpuMemoryInfoFn(OrtApiFn(Api, ORT_IDX_CREATE_CPU_MEMORY_INFO))(
        ORT_ARENA_ALLOCATOR, ORT_MEM_TYPE_DEFAULT, MemInfo), 'CreateCpuMemoryInfo');
      Shape[0] := 1;
      Shape[1] := 3;
      Shape[2] := BG_ONNX_INPUT_SIZE;
      Shape[3] := BG_ONNX_INPUT_SIZE;
      Check(TOrtCreateTensorFn(OrtApiFn(Api, ORT_IDX_CREATE_TENSOR_WITH_DATA))(
        MemInfo, @Data[0], NativeUInt(Length(Data)) * SizeOf(Single), @Shape[0], 4,
        ORT_TENSOR_FLOAT, InputTensor), 'CreateTensorWithDataAsOrtValue');

      InputNames[0] := InputName;
      OutputNames[0] := OutputName;
      Inputs[0] := InputTensor;
      Outputs[0] := nil;
      Check(TOrtRunFn(OrtApiFn(Api, ORT_IDX_RUN))(Session, nil, @InputNames[0],
        @Inputs[0], 1, @OutputNames[0], 1, @Outputs[0]), 'Run');
      OutputTensor := Outputs[0];
      { Os nomes foram alocados pelo alocador do onnxruntime. }
      Status := TOrtAllocatorFreeFn(OrtApiFn(Api, ORT_IDX_ALLOCATOR_FREE))(
        Allocator, InputName);
      if Status <> nil then
        ReleaseStatus(Status);
      Status := TOrtAllocatorFreeFn(OrtApiFn(Api, ORT_IDX_ALLOCATOR_FREE))(
        Allocator, OutputName);
      if Status <> nil then
        ReleaseStatus(Status);

      { --- mascara: canal 0 da primeira saida, min-max para 0..1 --- }
      Check(TOrtGetTypeAndShapeFn(OrtApiFn(Api, ORT_IDX_GET_TENSOR_TYPE_AND_SHAPE))(
        OutputTensor, ShapeInfo), 'GetTensorTypeAndShape');
      Check(TOrtGetDimensionsCountFn(OrtApiFn(Api, ORT_IDX_GET_DIMENSIONS_COUNT))(
        ShapeInfo, DimCount), 'GetDimensionsCount');
      if (Integer(DimCount) < 2) or (Integer(DimCount) > Length(Dims)) then
        raise Exception.Create('Formato de saida do modelo inesperado.');
      Check(TOrtGetDimensionsFn(OrtApiFn(Api, ORT_IDX_GET_DIMENSIONS))(
        ShapeInfo, @Dims[0], DimCount), 'GetDimensions');
      MaskH := Integer(Dims[Integer(DimCount) - 2]);
      MaskW := Integer(Dims[Integer(DimCount) - 1]);
      if (MaskW <= 1) or (MaskH <= 1) then
        raise Exception.Create('Mascara de saida invalida.');
      Check(TOrtGetTensorDataFn(OrtApiFn(Api, ORT_IDX_GET_TENSOR_MUTABLE_DATA))(
        OutputTensor, OutData), 'GetTensorMutableData');
      MaskCount := MaskW * MaskH;
      SetLength(Mask, MaskCount);
      MaskPtr := PSingle(OutData);
      MinV := MaskPtr^;
      MaxV := MinV;
      for I := 0 to MaskCount - 1 do
      begin
        V := PSingle(NativeUInt(MaskPtr) + NativeUInt(I) * SizeOf(Single))^;
        Mask[I] := V;
        if V < MinV then MinV := V;
        if V > MaxV then MaxV := V;
      end;
      if MaxV - MinV < 0.0000001 then
        raise Exception.Create('O modelo nao detectou nenhuma pessoa na imagem.');
      for I := 0 to MaskCount - 1 do
        Mask[I] := (Mask[I] - MinV) / (MaxV - MinV);

      { --- PNG RGBA: cores originais + mascara ampliada (bilinear) como alfa --- }
      SetLength(ColX0, W);
      SetLength(ColX1, W);
      SetLength(ColW, W);
      for X := 0 to W - 1 do
      begin
        FX := (X + 0.5) * MaskW / W - 0.5;
        if FX < 0 then FX := 0;
        if FX > MaskW - 1 then FX := MaskW - 1;
        XA := Trunc(FX);
        if XA > MaskW - 2 then XA := MaskW - 2;
        ColX0[X] := XA;
        ColX1[X] := XA + 1;
        ColW[X] := FX - XA;
      end;
      Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, W, H);
      for Y := 0 to H - 1 do
      begin
        FY := (Y + 0.5) * MaskH / H - 0.5;
        if FY < 0 then FY := 0;
        if FY > MaskH - 1 then FY := MaskH - 1;
        YA := Trunc(FY);
        if YA > MaskH - 2 then YA := MaskH - 2;
        WY := FY - YA;
        Row := Bmp.ScanLine[Y];
        Move(Row^, PByte(Png.Scanline[Y])^, W * 3);
        Alpha := Png.AlphaScanline[Y];
        for X := 0 to W - 1 do
        begin
          WX := ColW[X];
          V0 := Mask[YA * MaskW + ColX0[X]] * (1 - WX) + Mask[YA * MaskW + ColX1[X]] * WX;
          V1 := Mask[(YA + 1) * MaskW + ColX0[X]] * (1 - WX) + Mask[(YA + 1) * MaskW + ColX1[X]] * WX;
          V := V0 * (1 - WY) + V1 * WY;
          I := Round(V * 255);
          if I < 0 then I := 0;
          if I > 255 then I := 255;
          Alpha^[X] := Byte(I);
        end;
      end;
      Png.SaveToFile(AOutputTmp);
      Result := True;
    except
      on E: Exception do
      begin
        Result := False;
        AError := E.Message;
      end;
    end;
  finally
    Png.Free;
    Bmp.Free;
    Pic.Free;
    if Lib <> 0 then
    begin
      if Assigned(@ReleaseValue) then
      begin
        if OutputTensor <> nil then ReleaseValue(OutputTensor);
        if InputTensor <> nil then ReleaseValue(InputTensor);
      end;
      if Assigned(@ReleaseShapeInfo) and (ShapeInfo <> nil) then ReleaseShapeInfo(ShapeInfo);
      if Assigned(@ReleaseMemInfo) and (MemInfo <> nil) then ReleaseMemInfo(MemInfo);
      if Assigned(@ReleaseSession) and (Session <> nil) then ReleaseSession(Session);
      if Assigned(@ReleaseOptions) and (Options <> nil) then ReleaseOptions(Options);
      if Assigned(@ReleaseEnv) and (Env <> nil) then ReleaseEnv(Env);
      FreeLibrary(Lib);
    end;
  end;
end;

{ ========================================================================= }
{ Modo ROSTO HUMANO (chkHumanFace)                                         }
{ Mesmo modelo u2net_human_seg do onnxruntime, mas com refino da mascara:   }
{   1. a mascara 320x320 e ampliada para um tamanho de trabalho (<= 1024);  }
{   2. limpeza: mantem so o(s) maior(es) componente(s) e fecha buracos;     }
{   3. guided filter (guia = luminancia da foto) cola a borda da mascara nos }
{      contornos reais da imagem (cabelo, ombros);                          }
{   4. curva suave no alfa, ampliacao bilinear ate o tamanho original;      }
{   5. nas bordas, a cor do pixel vem de vizinhos opacos (sem franja do     }
{      fundo antigo).                                                       }
{ O modo "figuras" (BgRemoveFlatBackground + cadeia atual) nao e alterado.  }
{ ========================================================================= }

{ Media em janela (2R+1)^2, normalizada nas bordas, por imagem integral. }
function BgBoxMean(const ASrc: TArray<Single>; AW, AH, AR: Integer): TArray<Single>;
var
  II: TArray<Double>;
  X, Y, X0, X1, Y0, Y1, Stride: Integer;
  RowSum, Sum: Double;
begin
  Stride := AW + 1;
  SetLength(II, Stride * (AH + 1));
  for Y := 0 to AH - 1 do
  begin
    RowSum := 0;
    for X := 0 to AW - 1 do
    begin
      RowSum := RowSum + ASrc[Y * AW + X];
      II[(Y + 1) * Stride + X + 1] := II[Y * Stride + X + 1] + RowSum;
    end;
  end;
  SetLength(Result, AW * AH);
  for Y := 0 to AH - 1 do
  begin
    Y0 := Y - AR;
    if Y0 < 0 then Y0 := 0;
    Y1 := Y + AR + 1;
    if Y1 > AH then Y1 := AH;
    for X := 0 to AW - 1 do
    begin
      X0 := X - AR;
      if X0 < 0 then X0 := 0;
      X1 := X + AR + 1;
      if X1 > AW then X1 := AW;
      Sum := II[Y1 * Stride + X1] - II[Y0 * Stride + X1] -
        II[Y1 * Stride + X0] + II[Y0 * Stride + X0];
      Result[Y * AW + X] := Sum / ((Y1 - Y0) * (X1 - X0));
    end;
  end;
end;

{ Guided filter (He et al.): suaviza AInput seguindo as bordas de AGuide. }
function BgGuidedFilter(const AGuide, AInput: TArray<Single>; AW, AH, AR: Integer;
  AEps: Single): TArray<Single>;
var
  N, I: Integer;
  Tmp, MI, MP, MIP, MII, A, B, MA, MB: TArray<Single>;
  Variance, Covariance: Single;
begin
  N := AW * AH;
  SetLength(Tmp, N);
  MI := BgBoxMean(AGuide, AW, AH, AR);
  MP := BgBoxMean(AInput, AW, AH, AR);
  for I := 0 to N - 1 do
    Tmp[I] := AGuide[I] * AInput[I];
  MIP := BgBoxMean(Tmp, AW, AH, AR);
  for I := 0 to N - 1 do
    Tmp[I] := AGuide[I] * AGuide[I];
  MII := BgBoxMean(Tmp, AW, AH, AR);
  SetLength(A, N);
  SetLength(B, N);
  for I := 0 to N - 1 do
  begin
    Variance := MII[I] - MI[I] * MI[I];
    Covariance := MIP[I] - MI[I] * MP[I];
    A[I] := Covariance / (Variance + AEps);
    B[I] := MP[I] - A[I] * MI[I];
  end;
  MA := BgBoxMean(A, AW, AH, AR);
  MB := BgBoxMean(B, AW, AH, AR);
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    Result[I] := MA[I] * AGuide[I] + MB[I];
    if Result[I] < 0 then Result[I] := 0;
    if Result[I] > 1 then Result[I] := 1;
  end;
end;

{ Remove manchas soltas (componentes < 15% do maior) e fecha buracos pequenos
  de fundo cercados pela pessoa (< 0,3% da imagem). }
procedure BgCleanupMask(var A: TArray<Single>; AW, AH: Integer);
var
  N, I, K, Largest, Border: Integer;
  Lab, Sizes, Stack: TArray<Integer>;
  TouchesBorder: TArray<Boolean>;

  procedure LabelMask(AInverse: Boolean);
  var
    P, Q, Cur, Count, SP, QX, QY: Integer;
  begin
    SetLength(Lab, 0);
    SetLength(Lab, N);
    SetLength(Sizes, 1);
    for P := 0 to N - 1 do
    begin
      if (Lab[P] <> 0) or ((A[P] >= 0.5) = AInverse) then
        Continue;
      Cur := Length(Sizes);
      SetLength(Sizes, Cur + 1);
      Count := 0;
      SP := 0;
      Stack[SP] := P;
      Inc(SP);
      Lab[P] := Cur;
      while SP > 0 do
      begin
        Dec(SP);
        Q := Stack[SP];
        Inc(Count);
        QY := Q div AW;
        QX := Q - QY * AW;
        if (QX > 0) and (Lab[Q - 1] = 0) and ((A[Q - 1] >= 0.5) <> AInverse) then
        begin
          Lab[Q - 1] := Cur; Stack[SP] := Q - 1; Inc(SP);
        end;
        if (QX < AW - 1) and (Lab[Q + 1] = 0) and ((A[Q + 1] >= 0.5) <> AInverse) then
        begin
          Lab[Q + 1] := Cur; Stack[SP] := Q + 1; Inc(SP);
        end;
        if (QY > 0) and (Lab[Q - AW] = 0) and ((A[Q - AW] >= 0.5) <> AInverse) then
        begin
          Lab[Q - AW] := Cur; Stack[SP] := Q - AW; Inc(SP);
        end;
        if (QY < AH - 1) and (Lab[Q + AW] = 0) and ((A[Q + AW] >= 0.5) <> AInverse) then
        begin
          Lab[Q + AW] := Cur; Stack[SP] := Q + AW; Inc(SP);
        end;
      end;
      Sizes[Cur] := Count;
    end;
  end;

begin
  N := AW * AH;
  SetLength(Stack, N);

  { manchas soltas }
  LabelMask(False);
  Largest := 0;
  for K := 1 to High(Sizes) do
    if Sizes[K] > Largest then
      Largest := Sizes[K];
  if Largest > 0 then
    for I := 0 to N - 1 do
      if (Lab[I] > 0) and (Sizes[Lab[I]] < 0.15 * Largest) then
        A[I] := 0;

  { buracos pequenos que nao tocam a borda }
  LabelMask(True);
  SetLength(TouchesBorder, Length(Sizes));
  for I := 0 to AW - 1 do
  begin
    Border := Lab[I];
    TouchesBorder[Border] := True;
    Border := Lab[(AH - 1) * AW + I];
    TouchesBorder[Border] := True;
  end;
  for I := 0 to AH - 1 do
  begin
    Border := Lab[I * AW];
    TouchesBorder[Border] := True;
    Border := Lab[I * AW + AW - 1];
    TouchesBorder[Border] := True;
  end;
  for I := 0 to N - 1 do
    if (Lab[I] > 0) and (not TouchesBorder[Lab[I]]) and
       (Sizes[Lab[I]] < 0.003 * N) then
      A[I] := 1;
end;

{ Executa o modelo e devolve a mascara (canal 0 da primeira saida) normalizada
  por min-max para 0..1, no tamanho nativo da saida (320x320). }
function BgOnnxMask(const ADllPath, AModelPath: string; ABitmap: TBitmap;
  out AMask: TArray<Single>; out AMaskW, AMaskH: Integer;
  out AError: string): Boolean;
var
  Lib: HMODULE;
  GetApiBase: TOrtGetApiBaseFn;
  ApiBase, Api: Pointer;
  GetErrorMessage: TOrtGetErrorMessageFn;
  ReleaseStatus, ReleaseEnv, ReleaseOptions, ReleaseSession, ReleaseValue,
    ReleaseMemInfo, ReleaseShapeInfo: TOrtReleaseFn;
  Env, Options, Session, Allocator, MemInfo, InputTensor, OutputTensor,
    ShapeInfo, OutData, Status: Pointer;
  InputName, OutputName: PAnsiChar;
  InputNames, OutputNames: array[0..0] of PAnsiChar;
  Inputs, Outputs: array[0..0] of Pointer;
  Shape: array[0..3] of Int64;
  Dims: array[0..7] of Int64;
  DimCount: NativeUInt;
  Data: TArray<Single>;
  I, MaskCount, Threads: Integer;
  MinV, MaxV, V: Single;
  DllMachine: Word;

  procedure Check(AStatus: Pointer; const AWhat: string);
  var
    Msg: string;
  begin
    if AStatus = nil then
      Exit;
    Msg := string(AnsiString(GetErrorMessage(AStatus)));
    ReleaseStatus(AStatus);
    raise Exception.Create('onnxruntime: ' + AWhat + ' falhou: ' + Msg);
  end;

begin
  Result := False;
  AError := '';
  AMaskW := 0;
  AMaskH := 0;
  Lib := 0;
  GetErrorMessage := nil; ReleaseStatus := nil; ReleaseEnv := nil;
  ReleaseOptions := nil; ReleaseSession := nil; ReleaseValue := nil;
  ReleaseMemInfo := nil; ReleaseShapeInfo := nil;
  Env := nil; Options := nil; Session := nil; MemInfo := nil;
  InputTensor := nil; OutputTensor := nil; ShapeInfo := nil;
  InputName := nil; OutputName := nil; Allocator := nil;
  try
    try
      DllMachine := BgPeMachine(ADllPath);
{$IFDEF CPUX64}
      if (DllMachine <> 0) and (DllMachine <> $8664) then
        raise Exception.Create('A onnxruntime.dll em ' + ADllPath +
          ' nao e de 64 bits, mas o programa e de 64 bits. Use a DLL x64.');
{$ELSE}
      if (DllMachine <> 0) and (DllMachine <> $14C) then
        raise Exception.Create('A onnxruntime.dll em ' + ADllPath +
          ' nao e de 32 bits, mas o programa e de 32 bits. Use a DLL x86.');
{$ENDIF}
      Lib := LoadLibraryEx(PChar(ADllPath), 0, LOAD_WITH_ALTERED_SEARCH_PATH);
      if Lib = 0 then
        raise Exception.Create('Nao foi possivel carregar ' + ADllPath +
          ' (erro ' + IntToStr(GetLastError) + ').');
      @GetApiBase := GetProcAddress(Lib, 'OrtGetApiBase');
      if not Assigned(GetApiBase) then
        @GetApiBase := GetProcAddress(Lib, '_OrtGetApiBase@0');
      if not Assigned(GetApiBase) then
        raise Exception.Create('A DLL nao exporta OrtGetApiBase.');
      ApiBase := GetApiBase;
      Api := TOrtGetApiFn(PPointer(ApiBase)^)(ORT_API_VERSION_USED);
      if Api = nil then
        raise Exception.Create('A DLL do onnxruntime e mais antiga que a 1.17.');

      GetErrorMessage := TOrtGetErrorMessageFn(OrtApiFn(Api, ORT_IDX_GET_ERROR_MESSAGE));
      ReleaseStatus := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_STATUS));
      ReleaseEnv := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_ENV));
      ReleaseOptions := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_SESSION_OPTIONS));
      ReleaseSession := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_SESSION));
      ReleaseValue := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_VALUE));
      ReleaseMemInfo := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_MEMORY_INFO));
      ReleaseShapeInfo := TOrtReleaseFn(OrtApiFn(Api, ORT_IDX_RELEASE_TENSOR_TYPE_AND_SHAPE));

      BgBuildModelInput(ABitmap, BG_ONNX_INPUT_SIZE, Data);

      Check(TOrtCreateEnvFn(OrtApiFn(Api, ORT_IDX_CREATE_ENV))(
        ORT_LOGGING_LEVEL_WARNING, 'ps4tools', Env), 'CreateEnv');
      Check(TOrtCreateSessionOptionsFn(OrtApiFn(Api, ORT_IDX_CREATE_SESSION_OPTIONS))(
        Options), 'CreateSessionOptions');
      Threads := TThread.ProcessorCount;
      if Threads > 4 then Threads := 4;
      if Threads < 1 then Threads := 1;
      Check(TOrtSetIntFn(OrtApiFn(Api, ORT_IDX_SET_INTRA_OP_THREADS))(
        Options, Threads), 'SetIntraOpNumThreads');
      Check(TOrtSetIntFn(OrtApiFn(Api, ORT_IDX_SET_GRAPH_OPTIMIZATION))(
        Options, ORT_ENABLE_ALL), 'SetSessionGraphOptimizationLevel');
      Check(TOrtCreateSessionFn(OrtApiFn(Api, ORT_IDX_CREATE_SESSION))(
        Env, PWideChar(AModelPath), Options, Session), 'CreateSession (modelo)');
      Check(TOrtGetAllocatorFn(OrtApiFn(Api, ORT_IDX_GET_ALLOCATOR))(Allocator),
        'GetAllocatorWithDefaultOptions');
      Check(TOrtSessionGetNameFn(OrtApiFn(Api, ORT_IDX_SESSION_GET_INPUT_NAME))(
        Session, 0, Allocator, InputName), 'SessionGetInputName');
      Check(TOrtSessionGetNameFn(OrtApiFn(Api, ORT_IDX_SESSION_GET_OUTPUT_NAME))(
        Session, 0, Allocator, OutputName), 'SessionGetOutputName');

      Check(TOrtCreateCpuMemoryInfoFn(OrtApiFn(Api, ORT_IDX_CREATE_CPU_MEMORY_INFO))(
        ORT_ARENA_ALLOCATOR, ORT_MEM_TYPE_DEFAULT, MemInfo), 'CreateCpuMemoryInfo');
      Shape[0] := 1;
      Shape[1] := 3;
      Shape[2] := BG_ONNX_INPUT_SIZE;
      Shape[3] := BG_ONNX_INPUT_SIZE;
      Check(TOrtCreateTensorFn(OrtApiFn(Api, ORT_IDX_CREATE_TENSOR_WITH_DATA))(
        MemInfo, @Data[0], NativeUInt(Length(Data)) * SizeOf(Single), @Shape[0], 4,
        ORT_TENSOR_FLOAT, InputTensor), 'CreateTensorWithDataAsOrtValue');
      InputNames[0] := InputName;
      OutputNames[0] := OutputName;
      Inputs[0] := InputTensor;
      Outputs[0] := nil;
      Check(TOrtRunFn(OrtApiFn(Api, ORT_IDX_RUN))(Session, nil, @InputNames[0],
        @Inputs[0], 1, @OutputNames[0], 1, @Outputs[0]), 'Run');
      OutputTensor := Outputs[0];
      Status := TOrtAllocatorFreeFn(OrtApiFn(Api, ORT_IDX_ALLOCATOR_FREE))(
        Allocator, InputName);
      if Status <> nil then ReleaseStatus(Status);
      Status := TOrtAllocatorFreeFn(OrtApiFn(Api, ORT_IDX_ALLOCATOR_FREE))(
        Allocator, OutputName);
      if Status <> nil then ReleaseStatus(Status);

      Check(TOrtGetTypeAndShapeFn(OrtApiFn(Api, ORT_IDX_GET_TENSOR_TYPE_AND_SHAPE))(
        OutputTensor, ShapeInfo), 'GetTensorTypeAndShape');
      Check(TOrtGetDimensionsCountFn(OrtApiFn(Api, ORT_IDX_GET_DIMENSIONS_COUNT))(
        ShapeInfo, DimCount), 'GetDimensionsCount');
      if (Integer(DimCount) < 2) or (Integer(DimCount) > Length(Dims)) then
        raise Exception.Create('Formato de saida do modelo inesperado.');
      Check(TOrtGetDimensionsFn(OrtApiFn(Api, ORT_IDX_GET_DIMENSIONS))(
        ShapeInfo, @Dims[0], DimCount), 'GetDimensions');
      AMaskH := Integer(Dims[Integer(DimCount) - 2]);
      AMaskW := Integer(Dims[Integer(DimCount) - 1]);
      if (AMaskW <= 1) or (AMaskH <= 1) then
        raise Exception.Create('Mascara de saida invalida.');
      Check(TOrtGetTensorDataFn(OrtApiFn(Api, ORT_IDX_GET_TENSOR_MUTABLE_DATA))(
        OutputTensor, OutData), 'GetTensorMutableData');
      MaskCount := AMaskW * AMaskH;
      SetLength(AMask, MaskCount);
      MinV := PSingle(OutData)^;
      MaxV := MinV;
      for I := 0 to MaskCount - 1 do
      begin
        V := PSingle(NativeUInt(OutData) + NativeUInt(I) * SizeOf(Single))^;
        AMask[I] := V;
        if V < MinV then MinV := V;
        if V > MaxV then MaxV := V;
      end;
      if MaxV - MinV < 0.0000001 then
        raise Exception.Create('O modelo nao detectou nenhuma pessoa na imagem.');
      for I := 0 to MaskCount - 1 do
        AMask[I] := (AMask[I] - MinV) / (MaxV - MinV);
      Result := True;
    except
      on E: Exception do
      begin
        Result := False;
        AError := E.Message;
      end;
    end;
  finally
    if Lib <> 0 then
    begin
      if Assigned(@ReleaseValue) then
      begin
        if OutputTensor <> nil then ReleaseValue(OutputTensor);
        if InputTensor <> nil then ReleaseValue(InputTensor);
      end;
      if Assigned(@ReleaseShapeInfo) and (ShapeInfo <> nil) then ReleaseShapeInfo(ShapeInfo);
      if Assigned(@ReleaseMemInfo) and (MemInfo <> nil) then ReleaseMemInfo(MemInfo);
      if Assigned(@ReleaseSession) and (Session <> nil) then ReleaseSession(Session);
      if Assigned(@ReleaseOptions) and (Options <> nil) then ReleaseOptions(Options);
      if Assigned(@ReleaseEnv) and (Env <> nil) then ReleaseEnv(Env);
      FreeLibrary(Lib);
    end;
  end;
end;

function BgRemoveHumanFace(const ADllPath, AModelPath, AInputFile, AOutputTmp: string;
  out AError: string): Boolean;
const
  WORK_MAX = 1024;
  MAX_PIXELS = 16000000;
var
  Pic: TPicture;
  Bmp: TBitmap;
  Png: TPngImage;
  W, H, WW, WH, X, Y, I, X0, X1, Y0, Y1, SX, SY, MaskW, MaskH, Radius,
    XA, YA, Cnt, Reach, DX, DY, NX, NY, SumB, SumG, SumR, Value: Integer;
  Scale, FX, FY, WtX, WtY, V0, V1, T, Q: Single;
  Mask, Guide, Alpha, Refined: TArray<Single>;
  Acc: TArray<Cardinal>;
  ColX0, ColX1: TArray<Integer>;
  ColW: TArray<Single>;
  Line: PByte;
  RowPtrs, AlphaPtrs: TArray<PByte>;
  P: PByte;
  Gray: Single;
  Err: string;
begin
  Result := False;
  AError := '';
  Pic := TPicture.Create;
  Bmp := TBitmap.Create;
  Png := nil;
  try
    try
      Pic.LoadFromFile(AInputFile);
      W := Pic.Width;
      H := Pic.Height;
      if (W < 16) or (H < 16) then
        raise Exception.Create('Imagem muito pequena.');
      if Int64(W) * H > MAX_PIXELS then
        raise Exception.Create('Imagem grande demais para o modo rosto (limite de 16 megapixels).');
      Bmp.PixelFormat := pf24bit;
      Bmp.SetSize(W, H);
      Bmp.Canvas.Brush.Color := clWhite;
      Bmp.Canvas.FillRect(Rect(0, 0, W, H));
      Bmp.Canvas.Draw(0, 0, Pic.Graphic);
      FreeAndNil(Pic);

      { --- 1. mascara bruta do modelo --- }
      if not BgOnnxMask(ADllPath, AModelPath, Bmp, Mask, MaskW, MaskH, Err) then
        raise Exception.Create(Err);

      { --- 2. tamanho de trabalho e guia (luminancia por media de area) --- }
      Scale := 1;
      if W > H then
      begin
        if W > WORK_MAX then Scale := WORK_MAX / W;
      end
      else if H > WORK_MAX then
        Scale := WORK_MAX / H;
      WW := Round(W * Scale);
      WH := Round(H * Scale);
      if WW < 8 then WW := 8;
      if WH < 8 then WH := 8;

      SetLength(Guide, WW * WH);
      SetLength(Acc, WW * 3);
      for Y := 0 to WH - 1 do
      begin
        Y0 := (Y * H) div WH;
        Y1 := ((Y + 1) * H) div WH;
        if Y1 <= Y0 then Y1 := Y0 + 1;
        if Y1 > H then Y1 := H;
        for I := 0 to High(Acc) do
          Acc[I] := 0;
        for SY := Y0 to Y1 - 1 do
        begin
          Line := Bmp.ScanLine[SY];
          for X := 0 to WW - 1 do
          begin
            X0 := (X * W) div WW;
            X1 := ((X + 1) * W) div WW;
            if X1 <= X0 then X1 := X0 + 1;
            if X1 > W then X1 := W;
            for SX := X0 to X1 - 1 do
            begin
              { pf24bit guarda B, G, R }
              Inc(Acc[X * 3], PByte(NativeUInt(Line) + NativeUInt(SX) * 3 + 2)^);
              Inc(Acc[X * 3 + 1], PByte(NativeUInt(Line) + NativeUInt(SX) * 3 + 1)^);
              Inc(Acc[X * 3 + 2], PByte(NativeUInt(Line) + NativeUInt(SX) * 3)^);
            end;
          end;
        end;
        for X := 0 to WW - 1 do
        begin
          X0 := (X * W) div WW;
          X1 := ((X + 1) * W) div WW;
          if X1 <= X0 then X1 := X0 + 1;
          if X1 > W then X1 := W;
          Cnt := (Y1 - Y0) * (X1 - X0);
          Gray := (0.299 * Acc[X * 3] + 0.587 * Acc[X * 3 + 1] +
            0.114 * Acc[X * 3 + 2]) / (255.0 * Cnt);
          Guide[Y * WW + X] := Gray;
        end;
      end;

      { --- 3. mascara ampliada (bilinear) ate o tamanho de trabalho --- }
      SetLength(ColX0, WW);
      SetLength(ColX1, WW);
      SetLength(ColW, WW);
      for X := 0 to WW - 1 do
      begin
        FX := (X + 0.5) * MaskW / WW - 0.5;
        if FX < 0 then FX := 0;
        if FX > MaskW - 1 then FX := MaskW - 1;
        XA := Trunc(FX);
        if XA > MaskW - 2 then XA := MaskW - 2;
        ColX0[X] := XA;
        ColX1[X] := XA + 1;
        ColW[X] := FX - XA;
      end;
      SetLength(Alpha, WW * WH);
      for Y := 0 to WH - 1 do
      begin
        FY := (Y + 0.5) * MaskH / WH - 0.5;
        if FY < 0 then FY := 0;
        if FY > MaskH - 1 then FY := MaskH - 1;
        YA := Trunc(FY);
        if YA > MaskH - 2 then YA := MaskH - 2;
        WtY := FY - YA;
        for X := 0 to WW - 1 do
        begin
          WtX := ColW[X];
          V0 := Mask[YA * MaskW + ColX0[X]] * (1 - WtX) + Mask[YA * MaskW + ColX1[X]] * WtX;
          V1 := Mask[(YA + 1) * MaskW + ColX0[X]] * (1 - WtX) + Mask[(YA + 1) * MaskW + ColX1[X]] * WtX;
          Alpha[Y * WW + X] := V0 * (1 - WtY) + V1 * WtY;
        end;
      end;
      Mask := nil;

      { --- 4. limpeza + guided filter + curva --- }
      BgCleanupMask(Alpha, WW, WH);
      if WW > WH then Radius := Round(WW * 0.01) else Radius := Round(WH * 0.01);
      if Radius < 4 then Radius := 4;
      Refined := BgGuidedFilter(Guide, Alpha, WW, WH, Radius, 0.0001);
      for I := 0 to High(Refined) do
      begin
        T := (Refined[I] - 0.08) / 0.84;
        if T < 0 then T := 0;
        if T > 1 then T := 1;
        Refined[I] := T * T * (3 - 2 * T);
      end;
      Alpha := nil;
      Guide := nil;

      { --- 5. PNG RGBA no tamanho original --- }
      SetLength(ColX0, W);
      SetLength(ColX1, W);
      SetLength(ColW, W);
      for X := 0 to W - 1 do
      begin
        FX := (X + 0.5) * WW / W - 0.5;
        if FX < 0 then FX := 0;
        if FX > WW - 1 then FX := WW - 1;
        XA := Trunc(FX);
        if XA > WW - 2 then XA := WW - 2;
        ColX0[X] := XA;
        ColX1[X] := XA + 1;
        ColW[X] := FX - XA;
      end;
      Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, W, H);
      SetLength(RowPtrs, H);
      SetLength(AlphaPtrs, H);
      for Y := 0 to H - 1 do
      begin
        RowPtrs[Y] := PByte(Png.Scanline[Y]);
        AlphaPtrs[Y] := PByte(Png.AlphaScanline[Y]);
        FY := (Y + 0.5) * WH / H - 0.5;
        if FY < 0 then FY := 0;
        if FY > WH - 1 then FY := WH - 1;
        YA := Trunc(FY);
        if YA > WH - 2 then YA := WH - 2;
        WtY := FY - YA;
        Move(PByte(Bmp.ScanLine[Y])^, RowPtrs[Y]^, W * 3);
        for X := 0 to W - 1 do
        begin
          WtX := ColW[X];
          V0 := Refined[YA * WW + ColX0[X]] * (1 - WtX) + Refined[YA * WW + ColX1[X]] * WtX;
          V1 := Refined[(YA + 1) * WW + ColX0[X]] * (1 - WtX) + Refined[(YA + 1) * WW + ColX1[X]] * WtX;
          Q := V0 * (1 - WtY) + V1 * WtY;
          Value := Round(Q * 255);
          if Value < 0 then Value := 0;
          if Value > 255 then Value := 255;
          PByte(NativeUInt(AlphaPtrs[Y]) + NativeUInt(X))^ := Byte(Value);
        end;
      end;
      Refined := nil;

      { --- 6. bordas: cor vinda de vizinhos opacos (sem franja do fundo) --- }
      Reach := 3;
      if Scale < 1 then
        Inc(Reach, Round(1 / Scale));
      if Reach > 8 then Reach := 8;
      for Y := 0 to H - 1 do
        for X := 0 to W - 1 do
        begin
          Value := PByte(NativeUInt(AlphaPtrs[Y]) + NativeUInt(X))^;
          if (Value = 0) or (Value > 250) then
            Continue;
          SumB := 0; SumG := 0; SumR := 0; Cnt := 0;
          for DY := -Reach to Reach do
          begin
            NY := Y + DY;
            if (NY < 0) or (NY >= H) then Continue;
            for DX := -Reach to Reach do
            begin
              NX := X + DX;
              if (NX < 0) or (NX >= W) then Continue;
              if PByte(NativeUInt(AlphaPtrs[NY]) + NativeUInt(NX))^ > 250 then
              begin
                P := PByte(NativeUInt(RowPtrs[NY]) + NativeUInt(NX) * 3);
                Inc(SumB, P^);
                Inc(SumG, PByte(NativeUInt(P) + 1)^);
                Inc(SumR, PByte(NativeUInt(P) + 2)^);
                Inc(Cnt);
              end;
            end;
          end;
          if Cnt > 0 then
          begin
            P := PByte(NativeUInt(RowPtrs[Y]) + NativeUInt(X) * 3);
            P^ := Byte(SumB div Cnt);
            PByte(NativeUInt(P) + 1)^ := Byte(SumG div Cnt);
            PByte(NativeUInt(P) + 2)^ := Byte(SumR div Cnt);
          end;
        end;

      Png.SaveToFile(AOutputTmp);
      Result := True;
    except
      on E: Exception do
      begin
        Result := False;
        AError := E.Message;
      end;
    end;
  finally
    Png.Free;
    Bmp.Free;
    Pic.Free;
  end;
end;

{ Motor para logos e ilustracoes de fundo plano: o fundo e branco/cinza claro
  ou o xadrez de "transparente" gravado nos proprios pixels (comum em PNGs de
  bancos de imagens). Modelos de IA de pessoas tratam isso mal (mascara mole,
  partes brancas viram transparentes); aqui o fundo e achado por preenchimento
  a partir das bordas, e as bordas ganham alfa suave sem halo:
    1. cores de fundo = cores claras e neutras que dominam a borda da imagem;
    2. preenchimento 4-conexo a partir da borda por pixels perto dessas cores
       (o branco dentro da figura nao e alcancado se houver contorno escuro);
    3. nos 2 px ao redor do fundo, alfa pela projecao da cor entre a cor do
       fundo e a cor da figura vizinha, e cor trocada pela da figura (sem halo).
  AApplicable = False quando a imagem nao parece ter fundo plano; nesse caso
  o chamador segue para os motores de IA. }
function BgRemoveFlatBackground(const AInputFile, AOutputTmp: string;
  out AApplicable: Boolean; out AError: string): Boolean;
const
  TOLERANCE = 24;
  MAX_PIXELS = 8000000;
  MIN_BORDER_SHARE = 0.01;
  MIN_BORDER_COVERAGE = 0.90;
  MIN_REMOVED_SHARE = 0.01;
  MIN_COLOR_SPREAD_SQ = 24 * 24;
var
  Pic: TPicture;
  Bmp: TBitmap;
  Png: TPngImage;
  Counts: TDictionary<Cardinal, Integer>;
  Pair: TPair<Cardinal, Integer>;
  BgKeys: TArray<Cardinal>;
  Pix: TArray<Byte>;
  Near, State, Dist: TArray<Byte>;
  Stack: TArray<Integer>;
  SP, W, H, N, X, Y, I, K, DX, DY, NX, NY, NI, Layer, Total, Covered,
    Removed, BgCount, Cnt, R, G, B, SR, SG, SB, BR, BG2, BB, FR, FG, FB,
    PR, PG, PB, Den, Dot, Hi, Lo: Integer;
  Line: PByte;
  Alpha: Single;
  Row, AlphaRow: PByte;

  procedure CountBorder(AX, AY: Integer);
  var
    P: Integer;
    CK: Cardinal;
    Old: Integer;
  begin
    P := (AY * W + AX) * 3;
    CK := (Cardinal(Pix[P]) shl 16) or (Cardinal(Pix[P + 1]) shl 8) or Cardinal(Pix[P + 2]);
    if Counts.TryGetValue(CK, Old) then
      Counts[CK] := Old + 1
    else
      Counts.Add(CK, 1);
    Inc(Total);
  end;

  procedure Push(AIndex: Integer);
  begin
    State[AIndex] := 1;
    Stack[SP] := AIndex;
    Inc(SP);
  end;

begin
  Result := False;
  AApplicable := False;
  AError := '';
  Pic := TPicture.Create;
  Bmp := TBitmap.Create;
  Counts := TDictionary<Cardinal, Integer>.Create;
  Png := nil;
  try
    try
      Pic.LoadFromFile(AInputFile);
      W := Pic.Width;
      H := Pic.Height;
      if (W < 8) or (H < 8) or (Int64(W) * H > MAX_PIXELS) then
        Exit;
      Bmp.PixelFormat := pf24bit;
      Bmp.SetSize(W, H);
      Bmp.Canvas.Brush.Color := clWhite;
      Bmp.Canvas.FillRect(Rect(0, 0, W, H));
      Bmp.Canvas.Draw(0, 0, Pic.Graphic);
      FreeAndNil(Pic);
      N := W * H;

      { pf24bit guarda B, G, R; aqui o vetor fica em R, G, B. }
      SetLength(Pix, N * 3);
      for Y := 0 to H - 1 do
      begin
        Line := Bmp.ScanLine[Y];
        for X := 0 to W - 1 do
        begin
          I := (Y * W + X) * 3;
          Pix[I] := PByte(NativeUInt(Line) + NativeUInt(X) * 3 + 2)^;
          Pix[I + 1] := PByte(NativeUInt(Line) + NativeUInt(X) * 3 + 1)^;
          Pix[I + 2] := PByte(NativeUInt(Line) + NativeUInt(X) * 3)^;
        end;
      end;

      { 1. cores de fundo: claras, neutras e frequentes na borda }
      Total := 0;
      for X := 0 to W - 1 do
      begin
        CountBorder(X, 0);
        CountBorder(X, H - 1);
      end;
      for Y := 1 to H - 2 do
      begin
        CountBorder(0, Y);
        CountBorder(W - 1, Y);
      end;
      SetLength(BgKeys, 0);
      Covered := 0;
      for Pair in Counts do
      begin
        if Pair.Value < Total * MIN_BORDER_SHARE then
          Continue;
        R := (Pair.Key shr 16) and $FF;
        G := (Pair.Key shr 8) and $FF;
        B := Pair.Key and $FF;
        if (R < 170) or (G < 170) or (B < 170) then
          Continue;
        Hi := R;
        if G > Hi then Hi := G;
        if B > Hi then Hi := B;
        Lo := R;
        if G < Lo then Lo := G;
        if B < Lo then Lo := B;
        if Hi - Lo > 16 then
          Continue;
        SetLength(BgKeys, Length(BgKeys) + 1);
        BgKeys[High(BgKeys)] := Pair.Key;
        Inc(Covered, Pair.Value);
      end;
      if (Length(BgKeys) = 0) or (Covered < Total * MIN_BORDER_COVERAGE) then
        Exit;

      { pixels perto de alguma cor de fundo }
      SetLength(Near, N);
      for I := 0 to N - 1 do
      begin
        R := Pix[I * 3];
        G := Pix[I * 3 + 1];
        B := Pix[I * 3 + 2];
        for K := 0 to High(BgKeys) do
          if (Abs(R - Integer((BgKeys[K] shr 16) and $FF)) <= TOLERANCE) and
             (Abs(G - Integer((BgKeys[K] shr 8) and $FF)) <= TOLERANCE) and
             (Abs(B - Integer(BgKeys[K] and $FF)) <= TOLERANCE) then
          begin
            Near[I] := 1;
            Break;
          end;
      end;

      { 2. preenchimento 4-conexo a partir da borda }
      SetLength(State, N);
      SetLength(Stack, N);
      SP := 0;
      for X := 0 to W - 1 do
      begin
        if (Near[X] = 1) and (State[X] = 0) then Push(X);
        I := (H - 1) * W + X;
        if (Near[I] = 1) and (State[I] = 0) then Push(I);
      end;
      for Y := 0 to H - 1 do
      begin
        I := Y * W;
        if (Near[I] = 1) and (State[I] = 0) then Push(I);
        I := Y * W + W - 1;
        if (Near[I] = 1) and (State[I] = 0) then Push(I);
      end;
      while SP > 0 do
      begin
        Dec(SP);
        I := Stack[SP];
        Y := I div W;
        X := I - Y * W;
        if (X > 0) and (Near[I - 1] = 1) and (State[I - 1] = 0) then Push(I - 1);
        if (X < W - 1) and (Near[I + 1] = 1) and (State[I + 1] = 0) then Push(I + 1);
        if (Y > 0) and (Near[I - W] = 1) and (State[I - W] = 0) then Push(I - W);
        if (Y < H - 1) and (Near[I + W] = 1) and (State[I + W] = 0) then Push(I + W);
      end;
      Stack := nil;
      Near := nil;

      Removed := 0;
      for I := 0 to N - 1 do
        if State[I] = 1 then
          Inc(Removed);
      if Removed < N * MIN_REMOVED_SHARE then
        Exit;
      AApplicable := True;

      { camadas: 0 fundo, 1 e 2 = banda de borda, 3 interior }
      SetLength(Dist, N);
      for I := 0 to N - 1 do
        if State[I] = 1 then
          Dist[I] := 0
        else
          Dist[I] := 3;
      for Layer := 1 to 2 do
        for Y := 0 to H - 1 do
          for X := 0 to W - 1 do
          begin
            I := Y * W + X;
            if Dist[I] <> 3 then
              Continue;
            for DY := -1 to 1 do
              for DX := -1 to 1 do
              begin
                NX := X + DX;
                NY := Y + DY;
                if (NX < 0) or (NY < 0) or (NX >= W) or (NY >= H) then
                  Continue;
                NI := NY * W + NX;
                if (Layer = 1) and (State[NI] = 1) then
                  Dist[I] := Byte(1)
                else if (Layer = 2) and (Dist[NI] = 1) and (Dist[I] = 3) then
                  Dist[I] := Byte(2);
              end;
          end;

      { cor da figura vizinha (do interior para fora), cor de fundo local e
        alfa pela projecao. Os pixels de fundo usados vem de Pix, que so e
        alterado nos pixels da banda, depois de lidos. }
      for Layer := 2 downto 1 do
      begin
        for Y := 0 to H - 1 do
          for X := 0 to W - 1 do
          begin
            I := Y * W + X;
            if Dist[I] <> Layer then
              Continue;
            SR := 0; SG := 0; SB := 0; Cnt := 0;
            for DY := -1 to 1 do
              for DX := -1 to 1 do
              begin
                if (DX = 0) and (DY = 0) then
                  Continue;
                NX := X + DX;
                NY := Y + DY;
                if (NX < 0) or (NY < 0) or (NX >= W) or (NY >= H) then
                  Continue;
                NI := NY * W + NX;
                if Dist[NI] > Layer then
                begin
                  Inc(SR, Pix[NI * 3]);
                  Inc(SG, Pix[NI * 3 + 1]);
                  Inc(SB, Pix[NI * 3 + 2]);
                  Inc(Cnt);
                end;
              end;
            if Cnt = 0 then
              Continue;
            FR := SR div Cnt;
            FG := SG div Cnt;
            FB := SB div Cnt;

            { cor de fundo local: media dos pixels de fundo em 5x5 }
            SR := 0; SG := 0; SB := 0; BgCount := 0;
            for DY := -2 to 2 do
              for DX := -2 to 2 do
              begin
                NX := X + DX;
                NY := Y + DY;
                if (NX < 0) or (NY < 0) or (NX >= W) or (NY >= H) then
                  Continue;
                NI := NY * W + NX;
                if State[NI] = 1 then
                begin
                  Inc(SR, Pix[NI * 3]);
                  Inc(SG, Pix[NI * 3 + 1]);
                  Inc(SB, Pix[NI * 3 + 2]);
                  Inc(BgCount);
                end;
              end;
            if BgCount = 0 then
              Continue;
            BR := SR div BgCount;
            BG2 := SG div BgCount;
            BB := SB div BgCount;

            PR := Pix[I * 3];
            PG := Pix[I * 3 + 1];
            PB := Pix[I * 3 + 2];
            Den := (FR - BR) * (FR - BR) + (FG - BG2) * (FG - BG2) +
              (FB - BB) * (FB - BB);
            if Den <= MIN_COLOR_SPREAD_SQ then
              Continue;
            Dot := (PR - BR) * (FR - BR) + (PG - BG2) * (FG - BG2) +
              (PB - BB) * (FB - BB);
            Alpha := Dot / Den;
            if Alpha < 0 then Alpha := 0;
            if Alpha > 1 then Alpha := 1;
            { State passa a guardar o alfa da banda: 2 + alfa * 253 }
            Pix[I * 3] := Byte(FR);
            Pix[I * 3 + 1] := Byte(FG);
            Pix[I * 3 + 2] := Byte(FB);
            State[I] := Byte(2 + Round(Alpha * 253));
          end;
      end;

      { PNG RGBA: State 1 = transparente; 2..255 = alfa da banda; 0 = opaco }
      Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, W, H);
      for Y := 0 to H - 1 do
      begin
        Row := PByte(Png.Scanline[Y]);
        AlphaRow := PByte(Png.AlphaScanline[Y]);
        for X := 0 to W - 1 do
        begin
          I := Y * W + X;
          { o scanline do TPngImage guarda B, G, R }
          PByte(NativeUInt(Row) + NativeUInt(X) * 3)^ := Pix[I * 3 + 2];
          PByte(NativeUInt(Row) + NativeUInt(X) * 3 + 1)^ := Pix[I * 3 + 1];
          PByte(NativeUInt(Row) + NativeUInt(X) * 3 + 2)^ := Pix[I * 3];
          case State[I] of
            0: PByte(NativeUInt(AlphaRow) + NativeUInt(X))^ := 255;
            1: PByte(NativeUInt(AlphaRow) + NativeUInt(X))^ := 0;
          else
            PByte(NativeUInt(AlphaRow) + NativeUInt(X))^ :=
              Byte(Round((State[I] - 2) * 255 / 253));
          end;
        end;
      end;
      Png.SaveToFile(AOutputTmp);
      Result := True;
    except
      on E: Exception do
      begin
        Result := False;
        AError := E.Message;
      end;
    end;
  finally
    Png.Free;
    Counts.Free;
    Bmp.Free;
    Pic.Free;
  end;
end;

function RemoveImageBackground(const AInputFile, AOutputFile: string;
  AMode: TBgMode; out AErrorMessage: string): Boolean;
var
  OutputDir, TmpFile, RembgExe, ApiKey, StepError, OnnxDll, OnnxModel: string;
  Done, HasOnnx, FlatApplicable: Boolean;
  Share: Double;
begin
  Result := False;
  AErrorMessage := '';
  TmpFile := '';
  try
    if not BgValidateInput(AInputFile, AErrorMessage) then
      Exit;
    if not SameText(ExtractFileExt(AOutputFile), '.png') then
    begin
      AErrorMessage := 'O arquivo de saida precisa ter a extensao .png.';
      Exit;
    end;
    if SameText(TPath.GetFullPath(AInputFile), TPath.GetFullPath(AOutputFile)) then
    begin
      AErrorMessage := 'A saida nao pode ser o proprio arquivo de entrada.';
      Exit;
    end;
    OutputDir := ExtractFilePath(TPath.GetFullPath(AOutputFile));
    if not ForceDirectories(OutputDir) then
    begin
      AErrorMessage := 'Nao foi possivel criar a pasta de saida: ' + OutputDir;
      Exit;
    end;

    { Gera num arquivo temporario e so substitui a saida se estiver valido. }
    TmpFile := ChangeFileExt(TPath.GetFullPath(AOutputFile), '') + '.tmp.png';
    if TFile.Exists(TmpFile) then
      TFile.Delete(TmpFile);

    { Ordem: core\onnx\rembg.exe -> onnxruntime direto (onnxruntime.dll +
      modelo em core\onnx) -> API. Se o rembg.exe existir mas falhar, tenta o
      onnxruntime direto antes de desistir. }
    RembgExe := BgFindRembgExe;
    OnnxDll := BgFindOnnxRuntimeDll;
    OnnxModel := BgFindOnnxModel(AMode);
    ApiKey := BgFindApiKey;
    HasOnnx := (OnnxDll <> '') and (OnnxModel <> '');
    Done := False;
    StepError := '';
    FlatApplicable := False;
    { Logos e ilustracoes de fundo plano ou com xadrez gravado nos pixels:
      corte classico (nitido, sem IA). Desligue com FlatBackground=0 na secao
      [BackgroundRemoval] do PS4Tools.ini. Fotos seguem para os motores de IA. }
    if AMode = bmHumanFace then
    begin
      { Foto de rosto: modelo de pessoas com refino da mascara (onnxruntime).
        Sem a DLL/modelo, cai para o rembg.exe e depois para a API. O motor de
        fundo plano nao entra aqui. FlatApplicable = True so pula a cadeia
        de "figuras" abaixo. }
      FlatApplicable := True;
      if HasOnnx then
        Done := BgRemoveHumanFace(OnnxDll, OnnxModel, TPath.GetFullPath(AInputFile),
          TmpFile, StepError)
      else if RembgExe <> '' then
        Done := BgRemoveWithRembg(RembgExe, TPath.GetFullPath(AInputFile), TmpFile, StepError)
      else if ApiKey <> '' then
        Done := BgRemoveWithApi(ApiKey, TPath.GetFullPath(AInputFile), TmpFile, StepError)
      else
      begin
        AErrorMessage := 'Nenhum motor de remocao de fundo configurado. Coloque ' +
          'onnxruntime.dll (x86) e ' + BG_ONNX_DEFAULT_MODEL + ' em core\onnx ' +
          '(recomendado para rostos), ou rembg.exe, ou defina a variavel de ' +
          'ambiente ' + BG_API_KEY_ENV + ' para usar a API.';
        Exit;
      end;
    end
    else if BgReadSetting('FlatBackground', '1') <> '0' then
      Done := BgRemoveFlatBackground(TPath.GetFullPath(AInputFile), TmpFile,
        FlatApplicable, StepError);
    if FlatApplicable then
    begin
      { o motor escolhido acima ja decidiu: Done e StepError estao definidos }
    end
    else if RembgExe <> '' then
    begin
      Done := BgRemoveWithRembg(RembgExe, TPath.GetFullPath(AInputFile), TmpFile, StepError);
      if (not Done) and HasOnnx then
      begin
        if TFile.Exists(TmpFile) then
          TFile.Delete(TmpFile);
        Done := BgRemoveWithOnnx(OnnxDll, OnnxModel, TPath.GetFullPath(AInputFile),
          TmpFile, StepError);
      end;
    end
    else if HasOnnx then
      Done := BgRemoveWithOnnx(OnnxDll, OnnxModel, TPath.GetFullPath(AInputFile),
        TmpFile, StepError)
    else if ApiKey <> '' then
      Done := BgRemoveWithApi(ApiKey, TPath.GetFullPath(AInputFile), TmpFile, StepError)
    else
    begin
      AErrorMessage := 'Nenhum motor de remocao de fundo configurado. Coloque ' +
        'rembg.exe, ou onnxruntime.dll (x86) e ' + BG_ONNX_DEFAULT_MODEL +
        ', em core\onnx; ou defina a variavel de ambiente ' + BG_API_KEY_ENV +
        ' para usar a API.';
      Exit;
    end;
    if not Done then
    begin
      AErrorMessage := StepError;
      Exit;
    end;

    if not BgIsPngFile(TmpFile) then
    begin
      AErrorMessage := 'A ferramenta nao gerou um PNG valido.';
      Exit;
    end;
    if not PngFileHasTransparency(TmpFile) then
    begin
      AErrorMessage := 'O PNG gerado nao tem transparencia; a remocao de fundo falhou.';
      Exit;
    end;
    { Figuras com IA podem "achar" so um pedaco da cena (modelo de pessoas em
      ilustracao, por exemplo) e apagar quase tudo. Se restou pouco, e melhor
      avisar do que entregar uma imagem destruida. O motor de fundo plano e o
      modo Rostos nao passam por esta checagem. }
    if (AMode = bmFigure) and (not FlatApplicable) then
    begin
      { Valido so para Figuras com IA; o caminho de Rostos nao passa por aqui. }
      Share := BgPngForegroundShare(TmpFile);
      if Share < BG_MIN_FOREGROUND_SHARE then
      begin
        AErrorMessage := Format('A remocao de fundo manteve so %.0f%% da imagem; ' +
          'provavelmente nao achou o objeto (o modelo e feito para pessoas, ou a ' +
          'imagem nao tem um fundo para remover). Desmarque "Remover fundo" para ' +
          'usar a imagem como esta' +
          '%s', [Share * 100,
            IfThen((AMode = bmFigure) and
              (not FileExists(TPath.Combine(BgOnnxDir, BG_ONNX_GENERAL_MODEL))),
              ', ou coloque o modelo geral ' + BG_ONNX_GENERAL_MODEL + ' em core\onnx.', '.')]);
        Exit;
      end;
    end;

    TFile.Copy(TmpFile, AOutputFile, True);
    Result := True;
  except
    on E: Exception do
    begin
      Result := False;
      AErrorMessage := 'Falha ao remover o fundo: ' + E.Message;
    end;
  end;
  if (TmpFile <> '') and TFile.Exists(TmpFile) then
    try
      TFile.Delete(TmpFile);
    except
    end;
end;

function RemoveImageBackground(const AInputFile, AOutputFile: string;
  out AErrorMessage: string): Boolean;
begin
  Result := RemoveImageBackground(AInputFile, AOutputFile, bmFigure, AErrorMessage);
end;

function RemoveImageBackground(const AInputFile, AOutputFile: string): Boolean;
var
  ErrorMessage: string;
begin
  Result := RemoveImageBackground(AInputFile, AOutputFile, bmFigure, ErrorMessage);
end;

function RemoveImageBackgroundBatch(const AInputFiles: TArray<string>;
  const AOutputDir: string; ALog: TPS4SaveLogEvent): Integer;
var
  InputFile, OutputFile, ErrorMessage: string;
begin
  Result := 0;
  for InputFile in AInputFiles do
  begin
    OutputFile := TPath.Combine(AOutputDir,
      TPath.GetFileNameWithoutExtension(InputFile) + '-sem-fundo.png');
    if RemoveImageBackground(InputFile, OutputFile, ErrorMessage) then
    begin
      Inc(Result);
      if Assigned(ALog) then
        ALog('Fundo removido: ' + OutputFile);
    end
    else if Assigned(ALog) then
      ALog('Falha em ' + InputFile + ': ' + ErrorMessage);
  end;
end;

end.


