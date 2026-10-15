unit UnitSaves;

interface

uses
  System.SysUtils,
  UnitFunctions;

type
  TPS4SaveUser = UnitFunctions.TPS4SaveUser;
  TPS4SaveGame = UnitFunctions.TPS4SaveGame;
  TPS4ConsoleInfo = UnitFunctions.TPS4ConsoleInfo;
  TPS4SaveLogEvent = UnitFunctions.TPS4SaveLogEvent;
  TPS4SaveAgentLogEvent = UnitFunctions.TPS4SaveAgentLogEvent;
  TPS4SaveAgentProgressEvent = UnitFunctions.TPS4SaveAgentProgressEvent;

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
procedure DeletePS4Saves(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; ALog: TPS4SaveLogEvent);
procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; ALog: TPS4SaveLogEvent); overload;
procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestUserID: string;
  ALog: TPS4SaveLogEvent); overload;
procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  ALog: TPS4SaveLogEvent); overload;
procedure DownloadDecryptedSave(const AHost: string; const ASave: TPS4SaveGame;
  const ALocalZip: string; ALog: TPS4SaveAgentLogEvent;
  AProgress: TPS4SaveAgentProgressEvent);
procedure ExportPS4SavesDecrypted(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestFolder: string;
  ALog: TPS4SaveAgentLogEvent);
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

implementation

function DiscoverPS4Consoles(const ABaseIP: string; APort: Word;
  ALog: TPS4SaveLogEvent): TArray<TPS4ConsoleInfo>;
begin
  Result := UnitFunctions.DiscoverPS4Consoles(ABaseIP, APort, ALog);
end;

function ListPS4Users(const AHost: string; APort: Word): TArray<TPS4SaveUser>;
begin
  Result := UnitFunctions.ListPS4Users(AHost, APort);
end;

function ListPS4SaveGames(const AHost: string; APort: Word): TArray<TPS4SaveGame>;
begin
  Result := UnitFunctions.ListPS4SaveGames(AHost, APort);
end;

function ListPS4SaveGamesForUser(const AHost: string; APort: Word;
  const AUserID: string): TArray<TPS4SaveGame>;
begin
  Result := UnitFunctions.ListPS4SaveGamesForUser(AHost, APort, AUserID);
end;

function PS4SaveDisplayText(const ASave: TPS4SaveGame): string;
begin
  Result := UnitFunctions.PS4SaveDisplayText(ASave);
end;

procedure BackupPS4Saves(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestFolder: string;
  ALog: TPS4SaveLogEvent);
begin
  UnitFunctions.BackupPS4Saves(AHost, APort, ASaves, ADestFolder, ALog);
end;

procedure ImportPS4SaveBackup(const AHost, AUserID, ABackupFolder: string;
  AAutomatic: Boolean; ALog: TPS4SaveLogEvent);
begin
  UnitFunctions.ImportPS4SaveBackup(AHost, AUserID, ABackupFolder,
    AAutomatic, ALog);
end;

procedure DeletePS4Saves(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; ALog: TPS4SaveLogEvent);
begin
  UnitFunctions.DeletePS4Saves(AHost, APort, ASaves, ALog);
end;

procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; ALog: TPS4SaveLogEvent);
begin
  UnitFunctions.SyncPS4Saves(ALeftHost, ADestHost, APort, ASaves, ALog);
end;

procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestUserID: string;
  ALog: TPS4SaveLogEvent);
begin
  UnitFunctions.SyncPS4Saves(ALeftHost, ADestHost, APort, ASaves,
    ADestUserID, ALog);
end;

procedure SyncPS4Saves(const ALeftHost, ADestHost: string; APort: Word;
  ALog: TPS4SaveLogEvent);
begin
  UnitFunctions.SyncPS4Saves(ALeftHost, ADestHost, APort, ALog);
end;

procedure DownloadDecryptedSave(const AHost: string; const ASave: TPS4SaveGame;
  const ALocalZip: string; ALog: TPS4SaveAgentLogEvent;
  AProgress: TPS4SaveAgentProgressEvent);
begin
  UnitFunctions.DownloadDecryptedSave(AHost, ASave, ALocalZip, ALog, AProgress);
end;

procedure ExportPS4SavesDecrypted(const AHost: string; APort: Word;
  const ASaves: TArray<TPS4SaveGame>; const ADestFolder: string;
  ALog: TPS4SaveAgentLogEvent);
begin
  UnitFunctions.ExportPS4SavesDecrypted(AHost, APort, ASaves, ADestFolder, ALog);
end;

function PS4SaveAgentLocalPath: string;
begin
  Result := UnitFunctions.PS4SaveAgentLocalPath;
end;

function PS4SaveAgentRemotePath: string;
begin
  Result := UnitFunctions.PS4SaveAgentRemotePath;
end;

procedure EnsurePS4SaveAgentInstalled(const AHost: string;
  ALog: TPS4SaveAgentLogEvent);
begin
  UnitFunctions.EnsurePS4SaveAgentInstalled(AHost, ALog);
end;

procedure EnsurePS4SaveAgentReady(const AHost: string;
  ALog: TPS4SaveAgentLogEvent);
begin
  UnitFunctions.EnsurePS4SaveAgentReady(AHost, ALog);
end;

procedure EnsurePS4SaveAgentCurrent(const AHost: string;
  ALog: TPS4SaveAgentLogEvent);
begin
  UnitFunctions.EnsurePS4SaveAgentCurrent(AHost, ALog);
end;

function GetPS4SaveAgentAccountID(const AHost, AUserID: string;
  ALog: TPS4SaveAgentLogEvent): string;
begin
  Result := UnitFunctions.GetPS4SaveAgentAccountID(AHost, AUserID, ALog);
end;

procedure DeletePS4SaveWithAgent(const AHost: string;
  const ASave: TPS4SaveGame; ALog: TPS4SaveAgentLogEvent);
begin
  UnitFunctions.DeletePS4SaveWithAgent(AHost, ASave, ALog);
end;

procedure CleanupPS4StaleSavesWithAgent(const AHost, AUserID: string;
  ALog: TPS4SaveAgentLogEvent);
begin
  UnitFunctions.CleanupPS4StaleSavesWithAgent(AHost, AUserID, ALog);
end;

procedure SyncPS4SavesDecrypted(const ALeftHost, ADestHost: string;
  const ALeftUserID, ADestUserID: string; const ASaves: TArray<TPS4SaveGame>;
  const ABackupRoot: string; ALog: TPS4SaveAgentLogEvent;
  AProgress: TPS4SaveAgentProgressEvent);
begin
  UnitFunctions.SyncPS4SavesDecrypted(ALeftHost, ADestHost, ALeftUserID,
    ADestUserID, ASaves, ABackupRoot, ALog, AProgress);
end;

procedure SyncPS4SavesOnConsole(const AHost: string;
  const ALeftUserID, ADestUserID: string; const ASaves: TArray<TPS4SaveGame>;
  ALog: TPS4SaveAgentLogEvent);
begin
  UnitFunctions.SyncPS4SavesOnConsole(AHost, ALeftUserID, ADestUserID,
    ASaves, ALog);
end;

end.
