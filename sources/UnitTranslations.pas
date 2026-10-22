unit UnitTranslations;

interface

uses
  System.SysUtils;

type
  TAppLanguage = (alEnglish, alPortugueseBrazil, alSpanish, alGerman,
    alFrench, alRussian, alJapanese);

  TTranslations = record
    FormCaption: string;
    LeftIP: string;
    RightIP: string;
    LeftUser: string;
    RightUser: string;
    Language: string;
    LoadUsers: string;
    SyncType: string;
    Automatic: string;
    Manual: string;
    SyncPayload: string;
    SyncManual: string;
    SelectAll: string;
    SelectNone: string;
    StartSync: string;
    StartBackup: string;
    ExportSave: string;
    ImportSave: string;
    Delete: string;
    SavesTab: string;
    TrophiesTab: string;
    GamesTab: string;
    TrophyLoad: string;
    TrophyBackup: string;
    TrophyRestore: string;
    TrophyDelete: string;
    TrophySort: string;
    TrophySortLeft: string;
    TrophySortRight: string;
    TrophyCopyRight: string;
    TrophyCopyLeft: string;
    HintConnect: string;
    HintLoad: string;
    HintExport: string;
    HintImport: string;
    HintSync: string;
    HintCopy: string;
    HintDelete: string;
    HintSort: string;
    HintSelectAll: string;
    HintSelectNone: string;
    HintBackup: string;
    HintRestore: string;
    TrophyColumnNPWR: string;
    TrophyColumnGame: string;
    TrophyColumnTotal: string;
    TrophyColumnObtained: string;
    AvatarTab: string;
    DescricaoUsuarioDestino: string;
    AvatarHint: string;
    AvatarBrowse: string;
    AvatarCreate: string;
    AvatarSend: string;
    AvatarHintBrowse: string;
    AvatarHintCreate: string;
    AvatarHintSend: string;
    OperationMode: string;
    SamePlayStation: string;
    OtherPlayStation: string;
    Converter: string;
    ConverterTexconv: string;
    ConverterInternal: string;
    Image: string;
    Name: string;
    SaveLocally: string;
    TransparentBackground: string;
    ImageFilter: string;
  end;

function LanguageName(ALanguage: TAppLanguage): string;
function GetTranslations(ALanguage: TAppLanguage): TTranslations;
function TranslateText(const AText: string; ALanguage: TAppLanguage): string;
function TranslateSyncText(const AKey: string; ALanguage: TAppLanguage;
  ACount: Integer = 0; const AUser: string = ''; const APath: string = ''): string;

implementation

function LanguageName(ALanguage: TAppLanguage): string;
begin
  case ALanguage of
    alEnglish: Result := 'English';
    alPortugueseBrazil: Result := 'Português (Brasil)';
    alSpanish: Result := 'Español';
    alGerman: Result := 'Deutsch';
    alFrench: Result := 'Français';
    alRussian: Result := 'Русский';
    alJapanese: Result := '日本語';
  end;

end;

function GetTranslations(ALanguage: TAppLanguage): TTranslations;
begin
  Result.FormCaption := 'PS4 Tools';
  Result.LeftIP := 'PS4 IP';
  Result.RightIP := 'PS4 Destination IP';
  Result.LeftUser := 'Left User';
  Result.RightUser := 'Destination User';
  Result.Language := 'Language';
  Result.LoadUsers := 'Load Users';
  Result.SyncType := 'Sync Type:';
  Result.Automatic := 'Automatic';
  Result.Manual := 'Manual';
  Result.SyncPayload := 'Payload';
  Result.SyncManual := 'Manual';
  Result.SelectAll := 'Select All';
  Result.SelectNone := 'Select None';
  Result.StartSync := 'Start Sync';
  Result.StartBackup := 'Start Backup';
  Result.ExportSave := 'Export Save';
  Result.ImportSave := 'Import Save';
  Result.Delete := 'Delete';
  Result.SavesTab := 'Saves';
  Result.TrophiesTab := 'Trophies';
  Result.GamesTab := 'Games';
  Result.TrophyLoad := 'Load';
  Result.TrophyBackup := 'Backup';
  Result.TrophyRestore := 'Restore';
  Result.TrophyDelete := 'Delete';
  Result.TrophySort := 'A-Z';
  Result.TrophySortLeft := 'A-Z L';
  Result.TrophySortRight := 'A-Z R';
  Result.TrophyCopyRight := '->';
  Result.TrophyCopyLeft := '<-';
  Result.HintConnect := 'Connect to the PS4 and load users';
  Result.HintLoad := 'Load the trophy list for the selected user';
  Result.HintExport := 'Export the selected save games to the PC';
  Result.HintImport := 'Import save games from the PC to the PS4';
  Result.HintSync := 'Synchronize the selected save games';
  Result.HintCopy := 'Add the selected trophy games to the other PS4 user';
  Result.HintDelete := 'Delete the selected trophy games from this PS4 user';
  Result.HintSort := 'Sort this trophy list alphabetically';
  Result.HintSelectAll := 'Select all items in this list';
  Result.HintSelectNone := 'Clear all selections in this list';
  Result.HintBackup := 'Back up this user trophy data to the PC';
  Result.HintRestore := 'Restore trophy data to this PS4 user';
  Result.TrophyColumnNPWR := 'NPWR';
  Result.TrophyColumnGame := 'Game';
  Result.TrophyColumnTotal := 'Total';
  Result.TrophyColumnObtained := 'Obtained';
  Result.AvatarTab := 'Avatar';
  Result.DescricaoUsuarioDestino := 'The user selected in [Destination User] will receive the Avatar.';
  Result.AvatarHint := 'Creates avatar.png (440x400), avatar64/128/260/440.dds and online.json.';
  Result.AvatarBrowse := 'Select...';
  Result.AvatarCreate := 'Create image';
  Result.AvatarSend := 'Send avatar';
  Result.AvatarHintBrowse := 'Select the source image for the avatar';
  Result.AvatarHintCreate := 'Generate only avatar.png locally (DDS and online.json are created when sending)';
  Result.AvatarHintSend := 'Generate and send the avatar files to the destination user';
  Result.OperationMode := 'Source user';
  Result.SamePlayStation := 'SAME PLAYSTATION';
  Result.OtherPlayStation := 'TO ANOTHER PLAYSTATION';
  Result.Converter := 'Converter:';
  Result.ConverterTexconv := 'Texconv.exe (DirectXTex)';
  Result.ConverterInternal := 'Internal Delphi code (simple)';
  Result.Image := 'Image:';
  Result.Name := 'Name:';
  Result.SaveLocally := 'Save files locally';
  Result.TransparentBackground := 'Remove background (transparent)';
  Result.ImageFilter := 'Images|*.png;*.jpg;*.jpeg;*.bmp|All files|*.*';
  if ALanguage = alPortugueseBrazil then
  begin
    Result.AvatarTab := 'Avatar';
    Result.DescricaoUsuarioDestino := 'O usuário selecionado em [Usuário Destino] é quem receberá o Avatar.';
    Result.AvatarHint := 'O envio cria avatar.png (440x400), avatar64/128/260/440.dds e online.json.';
    Result.AvatarBrowse := 'Selecionar...';
    Result.AvatarCreate := 'Criar imagem';
    Result.AvatarSend := 'Enviar avatar';
    Result.AvatarHintBrowse := 'Selecionar a imagem de origem do avatar';
    Result.AvatarHintCreate := 'Gerar localmente apenas o avatar.png (DDS e online.json são criados no envio)';
    Result.AvatarHintSend := 'Gerar e enviar os arquivos para o usuário destino';
  end;
  if ALanguage = alSpanish then
  begin
    Result.DescricaoUsuarioDestino := 'El usuario seleccionado en [Usuario de destino] recibirá el Avatar.';
    Result.AvatarHint := 'Crea avatar.png (440x400), avatar64/128/260/440.dds y online.json.';
  end
  else if ALanguage = alGerman then
  begin
    Result.DescricaoUsuarioDestino := 'Der unter [Zielbenutzer] ausgewählte Benutzer erhält den Avatar.';
    Result.AvatarHint := 'Erstellt avatar.png (440x400), avatar64/128/260/440.dds und online.json.';
  end
  else if ALanguage = alFrench then
  begin
    Result.DescricaoUsuarioDestino := 'L’utilisateur sélectionné dans [Utilisateur destination] recevra l’Avatar.';
    Result.AvatarHint := 'Crée avatar.png (440x400), avatar64/128/260/440.dds et online.json.';
  end
  else if ALanguage = alRussian then
  begin
    Result.DescricaoUsuarioDestino := 'Аватар получит пользователь, выбранный в разделе [Пользователь назначения].';
    Result.AvatarHint := 'Создает avatar.png (440x400), avatar64/128/260/440.dds и online.json.';
  end
  else if ALanguage = alJapanese then
  begin
    Result.DescricaoUsuarioDestino := '[送信先ユーザー]で選択したユーザーがアバターを受け取ります。';
    Result.AvatarHint := 'avatar.png (440x400)、avatar64/128/260/440.dds、online.jsonを作成します。';
  end;

  if ALanguage = alPortugueseBrazil then
  begin
    Result.OperationMode := 'Usuário origem'; Result.SamePlayStation := 'MESMO PLAYSTATION';
    Result.OtherPlayStation := 'PARA OUTRO PLAYSTATION'; Result.Converter := 'Conversor:';
    Result.ConverterInternal := 'Código interno Delphi (simples)'; Result.Image := 'Imagem:';
    Result.Name := 'Nome:'; Result.SaveLocally := 'Salvar arquivos localmente';
    Result.TransparentBackground := 'Remover fundo (transparente)';
    Result.ImageFilter := 'Imagens|*.png;*.jpg;*.jpeg;*.bmp|Todos os arquivos|*.*';
    Result.GamesTab := 'Jogos';
    Result.SyncPayload := 'Payload';
    Result.SyncManual := 'Manual';
  end;
  case ALanguage of
    alSpanish: Result.GamesTab := 'Juegos';
    alGerman: Result.GamesTab := 'Spiele';
    alFrench: Result.GamesTab := 'Jeux';
    alRussian: Result.GamesTab := 'Игры';
    alJapanese: Result.GamesTab := 'ゲーム';
  end;
  case ALanguage of
    alSpanish: Result.ImageFilter := 'Imágenes|*.png;*.jpg;*.jpeg;*.bmp|Todos los archivos|*.*';
    alGerman: Result.ImageFilter := 'Bilder|*.png;*.jpg;*.jpeg;*.bmp|Alle Dateien|*.*';
    alFrench: Result.ImageFilter := 'Images|*.png;*.jpg;*.jpeg;*.bmp|Tous les fichiers|*.*';
    alRussian: Result.ImageFilter := 'Изображения|*.png;*.jpg;*.jpeg;*.bmp|Все файлы|*.*';
    alJapanese: Result.ImageFilter := '画像|*.png;*.jpg;*.jpeg;*.bmp|すべてのファイル|*.*';
  end;

  case ALanguage of
    alPortugueseBrazil:
      begin
        Result.FormCaption := 'PS4 Tools';
        Result.LeftIP := 'IP PS4 Origem';
        Result.RightIP := 'IP PS4 Destino';
        Result.LeftUser := 'Usuário Origem';
        Result.RightUser := 'Usuário Destino';
        Result.Language := 'Idioma';
        Result.LoadUsers := 'Carregar usuários';
        Result.SyncType := 'Tipo de sincronia:';
        Result.Automatic := 'Automático';
        Result.Manual := 'Manual';
        Result.SelectAll := 'Marcar todos';
        Result.SelectNone := 'Desmarcar';
        Result.StartSync := 'Iniciar sincronia';
        Result.StartBackup := 'Iniciar backup';
        Result.ExportSave := 'Exportar save'; Result.ImportSave := 'Importar save';
        Result.Delete := 'Deletar';
        Result.SavesTab := 'Saves';
        Result.TrophiesTab := 'Troféus';
        Result.TrophyLoad := 'Carregar'; Result.TrophyBackup := 'Backup';
        Result.TrophyRestore := 'Restaurar'; Result.TrophyDelete := 'Excluir';
        Result.TrophySort := 'A-Z'; Result.TrophyCopyRight := '->'; Result.TrophyCopyLeft := '<-';
      end;
    alSpanish:
      begin
        Result.FormCaption := 'PS4 Tools'; Result.LeftIP := 'IP PS4 Origen';
        Result.RightIP := 'IP PS4 Destino'; Result.LeftUser := 'Usuario Origen';
        Result.RightUser := 'Usuario Destino'; Result.Language := 'Idioma';
        Result.LoadUsers := 'Cargar usuarios'; Result.SyncType := 'Tipo de sincronización:';
        Result.Automatic := 'Automático'; Result.SelectAll := 'Seleccionar todos';
        Result.SelectNone := 'Deseleccionar'; Result.StartSync := 'Iniciar sincronización';
        Result.Delete := 'Eliminar'; Result.SavesTab := 'Partidas guardadas'; Result.TrophiesTab := 'Trofeos';
        Result.StartBackup := 'Iniciar copia de seguridad';
        Result.ExportSave := 'Exportar partida'; Result.ImportSave := 'Importar partida';
      end;
    alGerman:
      begin
        Result.FormCaption := 'PS4 Tools'; Result.LeftIP := 'PS4-IP Quelle';
        Result.RightIP := 'PS4-IP Ziel'; Result.LeftUser := 'Quellbenutzer';
        Result.RightUser := 'Zielbenutzer'; Result.Language := 'Sprache';
        Result.LoadUsers := 'Benutzer laden'; Result.SyncType := 'Synchronisationstyp:';
        Result.Automatic := 'Automatisch'; Result.SelectAll := 'Alle auswählen';
        Result.SelectNone := 'Auswahl aufheben'; Result.StartSync := 'Synchronisation starten';
        Result.Delete := 'Löschen'; Result.SavesTab := 'Spielstände'; Result.TrophiesTab := 'Trophäen';
        Result.StartBackup := 'Backup starten';
        Result.ExportSave := 'Spielstand exportieren'; Result.ImportSave := 'Spielstand importieren';
      end;
    alFrench:
      begin
        Result.FormCaption := 'PS4 Tools'; Result.LeftIP := 'IP PS4 Left';
        Result.RightIP := 'IP PS4 destination'; Result.LeftUser := 'Utilisateur Left';
        Result.RightUser := 'Utilisateur destination'; Result.Language := 'Langue';
        Result.LoadUsers := 'Charger les utilisateurs'; Result.SyncType := 'Type de synchronisation :';
        Result.Automatic := 'Automatique'; Result.SelectAll := 'Tout sélectionner';
        Result.SelectNone := 'Tout désélectionner'; Result.StartSync := 'Démarrer la synchronisation';
        Result.Delete := 'Supprimer'; Result.SavesTab := 'Sauvegardes'; Result.TrophiesTab := 'Trophées';
        Result.StartBackup := 'Démarrer la sauvegarde';
        Result.ExportSave := 'Exporter la sauvegarde'; Result.ImportSave := 'Importer la sauvegarde';
      end;
    alRussian:
      begin
        Result.FormCaption := 'PS4 Tools'; Result.LeftIP := 'IP источника PS4';
        Result.RightIP := 'IP назначения PS4'; Result.LeftUser := 'Пользователь источника';
        Result.RightUser := 'Пользователь назначения'; Result.Language := 'Язык';
        Result.LoadUsers := 'Загрузить пользователей'; Result.SyncType := 'Тип синхронизации:';
        Result.Automatic := 'Автоматически'; Result.SelectAll := 'Выбрать все';
        Result.SelectNone := 'Снять выбор'; Result.StartSync := 'Начать синхронизацию';
        Result.Delete := 'Удалить'; Result.SavesTab := 'Сохранения'; Result.TrophiesTab := 'Трофеи';
        Result.StartBackup := 'Начать резервное копирование';
        Result.ExportSave := 'Экспортировать сохранение'; Result.ImportSave := 'Импортировать сохранение';
      end;
    alJapanese:
      begin
        Result.FormCaption := 'PS4 Tools'; Result.LeftIP := 'PS4 元のIP';
        Result.RightIP := 'PS4 宛先のIP'; Result.LeftUser := '元のユーザー';
        Result.RightUser := '宛先ユーザー'; Result.Language := '言語';
        Result.LoadUsers := 'ユーザーを読み込む'; Result.SyncType := '同期モード:';
        Result.Automatic := '自動'; Result.SelectAll := 'すべて選択';
        Result.SelectNone := '選択解除'; Result.StartSync := '同期を開始';
        Result.Delete := '削除'; Result.SavesTab := 'セーブデータ'; Result.TrophiesTab := 'トロフィー';
        Result.StartBackup := 'バックアップを開始';
        Result.ExportSave := 'セーブをエクスポート'; Result.ImportSave := 'セーブをインポート';
      end;
  end;

  case ALanguage of
    alEnglish:
      begin
        Result.TrophyLoad := 'Load'; Result.TrophyBackup := 'Backup';
        Result.TrophyRestore := 'Restore'; Result.TrophyDelete := 'Delete';
        Result.TrophySort := 'A-Z'; Result.TrophyCopyRight := '->'; Result.TrophyCopyLeft := '<-';
        Result.TrophyColumnGame := 'Game'; Result.TrophyColumnTotal := 'Total'; Result.TrophyColumnObtained := 'Obtained';
      end;
    alPortugueseBrazil:
      begin
        Result.TrophyLoad := 'Carregar'; Result.TrophyBackup := 'Backup';
        Result.TrophyRestore := 'Restaurar'; Result.TrophyDelete := 'Excluir';
        Result.TrophySort := 'A-Z'; Result.TrophyCopyRight := '->'; Result.TrophyCopyLeft := '<-';
        Result.TrophyColumnGame := 'Jogo'; Result.TrophyColumnTotal := 'Total'; Result.TrophyColumnObtained := 'Obtidos';
      end;
    alSpanish:
      begin
        Result.TrophyLoad := 'Cargar'; Result.TrophyBackup := 'Copia';
        Result.TrophyRestore := 'Restaurar'; Result.TrophyDelete := 'Eliminar';
        Result.TrophySort := 'A-Z'; Result.TrophyCopyRight := '->'; Result.TrophyCopyLeft := '<-';
        Result.TrophyColumnGame := 'Juego'; Result.TrophyColumnTotal := 'Total'; Result.TrophyColumnObtained := 'Obtenidos';
      end;
    alGerman:
      begin
        Result.TrophyLoad := 'Laden'; Result.TrophyBackup := 'Backup';
        Result.TrophyRestore := 'Wiederherstellen'; Result.TrophyDelete := 'Löschen';
        Result.TrophySort := 'A-Z'; Result.TrophyCopyRight := '->'; Result.TrophyCopyLeft := '<-';
        Result.TrophyColumnGame := 'Spiel'; Result.TrophyColumnTotal := 'Gesamt'; Result.TrophyColumnObtained := 'Erhalten';
      end;
    alFrench:
      begin
        Result.TrophyLoad := 'Charger'; Result.TrophyBackup := 'Sauvegarde';
        Result.TrophyRestore := 'Restaurer'; Result.TrophyDelete := 'Supprimer';
        Result.TrophySort := 'A-Z'; Result.TrophyCopyRight := '->'; Result.TrophyCopyLeft := '<-';
        Result.TrophyColumnGame := 'Jeu'; Result.TrophyColumnTotal := 'Total'; Result.TrophyColumnObtained := 'Obtenus';
      end;
    alRussian:
      begin
        Result.TrophyLoad := 'Загрузить'; Result.TrophyBackup := 'Резервная копия';
        Result.TrophyRestore := 'Восстановить'; Result.TrophyDelete := 'Удалить';
        Result.TrophySort := 'А-Я'; Result.TrophyCopyRight := '->'; Result.TrophyCopyLeft := '<-';
        Result.TrophyColumnGame := 'Игра'; Result.TrophyColumnTotal := 'Всего'; Result.TrophyColumnObtained := 'Получено';
      end;
    alJapanese:
      begin
        Result.TrophyLoad := '読み込む'; Result.TrophyBackup := 'バックアップ';
        Result.TrophyRestore := '復元'; Result.TrophyDelete := '削除';
        Result.TrophySort := 'A-Z'; Result.TrophyCopyRight := '->'; Result.TrophyCopyLeft := '<-';
        Result.TrophyColumnGame := 'ゲーム'; Result.TrophyColumnTotal := '合計'; Result.TrophyColumnObtained := '取得済み';
      end;
  end;

  case ALanguage of
    alEnglish:
      begin
        Result.LoadUsers := 'Connect';
        Result.StartSync := 'Start Sync';
        Result.ExportSave := 'Export'; Result.ImportSave := 'Import';
        Result.TrophyBackup := 'Export'; Result.TrophyRestore := 'Import';
        Result.TrophySortLeft := 'A-Z'; Result.TrophySortRight := 'A-Z';
      end;
    alPortugueseBrazil:
      begin
        Result.LoadUsers := 'Conectar';
        Result.StartSync := 'Iniciar Sincronia';
        Result.ExportSave := 'Exportar'; Result.ImportSave := 'Importar';
        Result.TrophyBackup := 'Exportar'; Result.TrophyRestore := 'Importar';
        Result.TrophySortLeft := 'A-Z'; Result.TrophySortRight := 'A-Z';
      end;
    alSpanish:
      begin
        Result.LoadUsers := 'Conectar';
        Result.StartSync := 'Iniciar sincronización';
        Result.ExportSave := 'Exportar'; Result.ImportSave := 'Importar';
        Result.TrophyBackup := 'Exportar'; Result.TrophyRestore := 'Importar';
        Result.TrophySortLeft := 'A-Z'; Result.TrophySortRight := 'A-Z';
      end;
    alGerman:
      begin
        Result.LoadUsers := 'Verbinden';
        Result.StartSync := 'Synchronisieren';
        Result.ExportSave := 'Exportieren'; Result.ImportSave := 'Importieren';
        Result.TrophyBackup := 'Exportieren'; Result.TrophyRestore := 'Importieren';
        Result.TrophySortLeft := 'A-Z'; Result.TrophySortRight := 'A-Z';
      end;
    alFrench:
      begin
        Result.LoadUsers := 'Connecter';
        Result.StartSync := 'Synchroniser';
        Result.ExportSave := 'Exporter'; Result.ImportSave := 'Importer';
        Result.TrophyBackup := 'Exporter'; Result.TrophyRestore := 'Importer';
        Result.TrophySortLeft := 'A-Z'; Result.TrophySortRight := 'A-Z';
      end;
    alRussian:
      begin
        Result.LoadUsers := 'Подключить';
        Result.StartSync := 'Синхронизация';
        Result.ExportSave := 'Экспорт'; Result.ImportSave := 'Импорт';
        Result.TrophyBackup := 'Экспорт'; Result.TrophyRestore := 'Импорт';
        Result.TrophySortLeft := 'А-Я'; Result.TrophySortRight := 'А-Я';
      end;
    alJapanese:
      begin
        Result.LoadUsers := '接続';
        Result.StartSync := '同期開始';
        Result.ExportSave := 'エクスポート'; Result.ImportSave := 'インポート';
        Result.TrophyBackup := 'エクスポート'; Result.TrophyRestore := 'インポート';
        Result.TrophySortLeft := 'A-Z'; Result.TrophySortRight := 'A-Z';
      end;
  end;

  case ALanguage of
    alPortugueseBrazil:
      begin
        Result.HintConnect := 'Conectar ao PS4 e carregar os usuarios'; Result.HintLoad := 'Carregar a lista de trofeus do usuario selecionado';
        Result.HintExport := 'Exportar os saves selecionados para o PC'; Result.HintImport := 'Importar saves do PC para o PS4';
        Result.HintSync := 'Sincronizar os saves selecionados'; Result.HintCopy := 'Adicionar os jogos de trofeus selecionados ao outro usuario';
        Result.HintDelete := 'Excluir os jogos de trofeus selecionados deste usuario'; Result.HintSort := 'Ordenar esta lista de trofeus por nome';
        Result.HintSelectAll := 'Marcar todos os itens desta lista'; Result.HintSelectNone := 'Desmarcar todos os itens desta lista';
        Result.HintBackup := 'Fazer backup dos trofeus deste usuario no PC'; Result.HintRestore := 'Restaurar os trofeus para este usuario do PS4';
      end;
    alSpanish:
      begin
        Result.HintConnect := 'Conectar al PS4 y cargar usuarios';
        Result.HintLoad := 'Cargar trofeos del usuario seleccionado';
        Result.HintExport := 'Exportar partidas seleccionadas al PC';
        Result.HintImport := 'Importar partidas del PC al PS4';
        Result.HintSync := 'Sincronizar partidas seleccionadas';
        Result.HintCopy := 'Agregar juegos de trofeos seleccionados al otro usuario';
        Result.HintDelete := 'Eliminar juegos de trofeos seleccionados';
        Result.HintSort := 'Ordenar esta lista de trofeos';
        Result.HintSelectAll := 'Seleccionar todos los elementos';
        Result.HintSelectNone := 'Deseleccionar todos los elementos';
        Result.HintBackup := 'Respaldar trofeos de este usuario';
        Result.HintRestore := 'Restaurar trofeos para este usuario';
      end;
    alGerman:
      begin
        Result.HintConnect := 'Mit der PS4 verbinden und Benutzer laden';
        Result.HintLoad := 'Trophäen des ausgewählten Benutzers laden';
        Result.HintExport := 'Ausgewählte Spielstände auf den PC exportieren';
        Result.HintImport := 'Spielstände vom PC auf die PS4 importieren';
        Result.HintSync := 'Ausgewählte Spielstände synchronisieren';
        Result.HintCopy := 'Ausgewählte Trophäenspiele zum anderen Benutzer hinzufügen';
        Result.HintDelete := 'Ausgewählte Trophäenspiele löschen';
        Result.HintSort := 'Diese Trophäenliste alphabetisch sortieren';
        Result.HintSelectAll := 'Alle Elemente auswählen';
        Result.HintSelectNone := 'Auswahl aufheben';
        Result.HintBackup := 'Trophäen dieses Benutzers sichern';
        Result.HintRestore := 'Trophäen für diesen Benutzer wiederherstellen';
      end;
    alFrench:
      begin
        Result.HintConnect := 'Se connecter à la PS4 et charger les utilisateurs';
        Result.HintLoad := 'Charger les trophées de l’utilisateur sélectionné';
        Result.HintExport := 'Exporter les sauvegardes sélectionnées vers le PC';
        Result.HintImport := 'Importer les sauvegardes du PC vers la PS4';
        Result.HintSync := 'Synchroniser les sauvegardes sélectionnées';
        Result.HintCopy := 'Ajouter les jeux de trophées sélectionnés à l’autre utilisateur';
        Result.HintDelete := 'Supprimer les jeux de trophées sélectionnés';
        Result.HintSort := 'Trier cette liste de trophées';
        Result.HintSelectAll := 'Sélectionner tous les éléments';
        Result.HintSelectNone := 'Tout désélectionner';
        Result.HintBackup := 'Sauvegarder les trophées de cet utilisateur';
        Result.HintRestore := 'Restaurer les trophées de cet utilisateur';
      end;
    alRussian:
      begin
        Result.HintConnect := 'Подключиться к PS4 и загрузить пользователей';
        Result.HintLoad := 'Загрузить трофеи выбранного пользователя';
        Result.HintExport := 'Экспортировать выбранные сохранения на ПК';
        Result.HintImport := 'Импортировать сохранения с ПК на PS4';
        Result.HintSync := 'Синхронизировать выбранные сохранения';
        Result.HintCopy := 'Добавить выбранные игры трофеев другому пользователю';
        Result.HintDelete := 'Удалить выбранные игры трофеев';
        Result.HintSort := 'Сортировать список трофеев';
        Result.HintSelectAll := 'Выбрать все элементы';
        Result.HintSelectNone := 'Снять выбор';
        Result.HintBackup := 'Создать резервную копию трофеев';
        Result.HintRestore := 'Восстановить трофеи пользователя';
      end;
    alJapanese:
      begin
        Result.HintConnect := 'PS4に接続してユーザーを読み込む';
        Result.HintLoad := '選択したユーザーのトロフィーを読み込む';
        Result.HintExport := '選択したセーブをPCへエクスポート';
        Result.HintImport := 'PCからPS4へセーブをインポート';
        Result.HintSync := '選択したセーブを同期';
        Result.HintCopy := '選択したトロフィーゲームを他のユーザーに追加';
        Result.HintDelete := '選択したトロフィーゲームを削除';
        Result.HintSort := 'トロフィー一覧を名前順に並べ替え';
        Result.HintSelectAll := 'すべての項目を選択';
        Result.HintSelectNone := '選択を解除';
        Result.HintBackup := 'ユーザーのトロフィーをバックアップ';
        Result.HintRestore := 'ユーザーのトロフィーを復元';
      end;
  end;

  { Source/Destination express the role of each side, not its visual position. }
  case ALanguage of
    alEnglish:
      begin
        Result.LeftIP := 'PS4 IP';
        Result.StartSync := 'Start Sync';
        Result.LeftUser := 'Source User'; Result.RightUser := 'Destination User';
        Result.OperationMode := 'Operation Mode';
      end;
    alPortugueseBrazil:
      begin
        Result.LeftIP := 'IP PS4';
        Result.StartSync := 'Iniciar Sincronia';
        Result.LeftUser := 'Usuário Origem'; Result.RightUser := 'Usuário Destino';
        Result.OperationMode := 'Modo de Operação';
      end;
    alSpanish:
      begin
        Result.LeftIP := 'IP PS4';
        Result.StartSync := 'Iniciar sincronización';
        Result.LeftUser := 'Usuario de origen'; Result.RightUser := 'Usuario de destino';
        Result.OperationMode := 'Modo de operación';
      end;
    alGerman:
      begin
        Result.LeftIP := 'PS4-IP';
        Result.StartSync := 'Synchronisieren';
        Result.LeftUser := 'Quellbenutzer'; Result.RightUser := 'Zielbenutzer';
        Result.OperationMode := 'Betriebsmodus';
      end;
    alFrench:
      begin
        Result.LeftIP := 'IP PS4';
        Result.StartSync := 'Synchroniser';
        Result.LeftUser := 'Utilisateur source'; Result.RightUser := 'Utilisateur destination';
        Result.OperationMode := 'Mode opératoire';
      end;
    alRussian:
      begin
        Result.LeftIP := 'IP PS4';
        Result.StartSync := 'Синхронизация';
        Result.LeftUser := 'Пользователь источника'; Result.RightUser := 'Пользователь назначения';
        Result.OperationMode := 'Режим работы';
      end;
    alJapanese:
      begin
        Result.LeftIP := 'PS4 IP';
        Result.StartSync := '同期開始';
        Result.LeftUser := '元のユーザー'; Result.RightUser := '宛先ユーザー';
        Result.OperationMode := '操作モード';
      end;
  end;
end;

function TranslateText(const AText: string; ALanguage: TAppLanguage): string;
begin
  Result := AText;
  if ALanguage = alPortugueseBrazil then
    Exit;

  if ALanguage = alEnglish then
  begin
    Result := StringReplace(Result, 'Carregando usuarios', 'Loading users', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregando SAVES', 'Loading saves', [rfReplaceAll]);
    Result := StringReplace(Result, 'Falha ao carregar usuarios', 'Failed to load users', [rfReplaceAll]);
    Result := StringReplace(Result, 'Falha ao carregar SAVES de origem', 'Failed to load Left saves', [rfReplaceAll]);
    Result := StringReplace(Result, 'Falha ao carregar SAVES de destino', 'Failed to load destination saves', [rfReplaceAll]);
    Result := StringReplace(Result, 'Falha na sincronia', 'Synchronization failed', [rfReplaceAll]);
    Result := StringReplace(Result, 'Sincronia manual concluida', 'Manual synchronization completed', [rfReplaceAll]);
    Result := StringReplace(Result, 'Sincronia descriptografada concluida', 'Decrypted synchronization completed', [rfReplaceAll]);
    Result := StringReplace(Result, 'Sincronia interna pelo payload concluida', 'On-console synchronization completed', [rfReplaceAll]);
    Result := StringReplace(Result, 'Processando...', 'Processing...', [rfReplaceAll]);
    Result := StringReplace(Result, 'usuario(s)', 'user(s)', [rfReplaceAll]);
    Result := StringReplace(Result, 'save(s)', 'save(s)', [rfReplaceAll]);
    Result := StringReplace(Result, 'A criação das imagens pode demorar. Aguarde enquanto o processo é concluído...', 'Image creation may take some time. Please wait while the process completes...', [rfReplaceAll]);
    Result := StringReplace(Result, 'Avatar enviado. Reinicie o PS4 ou faça logout/login no usuário.', 'Avatar sent. Restart the PS4 or log out and back in to the user.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecionar saves para enviar', 'Select saves to send', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecionar trofeus para enviar', 'Select trophies to send', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecionar todos', 'Select all', [rfReplaceAll]);
    Result := StringReplace(Result, 'Enviar selecionados', 'Send selected', [rfReplaceAll]);
    Result := StringReplace(Result, 'Cancelar', 'Cancel', [rfReplaceAll]);
    Result := StringReplace(Result, 'Informe o IP do PS4.', 'Enter the PS4 IP address.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione uma imagem valida.', 'Select a valid image.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue e selecione o perfil cache.', 'Load and select the cache profile.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Criando imagens localmente...', 'Creating images locally...', [rfReplaceAll]);
    Result := StringReplace(Result, 'Imagens criadas em:', 'Images created in:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Falha ao criar imagens.', 'Failed to create images.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Preparando imagens do avatar...', 'Preparing avatar images...', [rfReplaceAll]);
    Result := StringReplace(Result, 'Gerando arquivos do avatar...', 'Generating avatar files...', [rfReplaceAll]);
    Result := StringReplace(Result, 'Arquivos salvos em:', 'Files saved in:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Enviando para', 'Uploading to', [rfReplaceAll]);
    Result := StringReplace(Result, 'Falha ao enviar avatar:', 'Failed to send avatar:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Imagem selecionada:', 'Selected image:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuário destino antes de enviar o avatar.', 'Select the destination user before sending the avatar.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Verificando PS4 Save Agent na origem...', 'Checking PS4 Save Agent on the source...', [rfReplaceAll]);
    Result := StringReplace(Result, 'Verificando PS4 Save Agent no destino...', 'Checking PS4 Save Agent on the destination...', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregando usuarios do PS4 de origem...', 'Loading users from the source PS4...', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregando usuarios do PS4 de destino...', 'Loading users from the destination PS4...', [rfReplaceAll]);
    Result := StringReplace(Result, 'Falha ao conectar/carregar origem:', 'Failed to connect/load source:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Falha ao conectar/carregar destino:', 'Failed to connect/load destination:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Delete concluido.', 'Delete completed.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Exportacao concluida:', 'Export completed:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Importacao concluida', 'Import completed', [rfReplaceAll]);
    Result := StringReplace(Result, 'Backup concluido:', 'Backup completed:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Sincronizacao concluida.', 'Synchronization completed.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Informe o IP dos dois PS4.', 'Enter both PS4 IP addresses.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione pelo menos um jogo na lista de origem.', 'Select at least one game in the source list.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Todos os trofeus selecionados ja existem no destino e foram ignorados:', 'All selected trophies already exist on the destination and were skipped:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Erro ao sincronizar trofeus:', 'Error synchronizing trophies:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Informe o IP e marque pelo menos um jogo de trofeus.', 'Enter the IP and select at least one trophy game.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Erro ao excluir trofeus:', 'Error deleting trophies:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Erro ao ordenar trofeus:', 'Error sorting trophies:', [rfReplaceAll]);
    Result := StringReplace(Result, 'Restaurar trofeus', 'Restore trophies', [rfReplaceAll]);
    Result := StringReplace(Result, 'Restauracao de trofeus concluida.', 'Trophy restoration completed.', [rfReplaceAll]);
  end;

  if ALanguage = alSpanish then
  begin
    Result := StringReplace(Result, 'Informe o IP de origem e o IP de destino.', 'Introduzca la IP de origen y la IP de destino.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue os SAVES do IP de origem antes de iniciar a sincronia.', 'Cargue los SAVES de la IP de origen antes de iniciar la sincronización.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de origem.', 'Seleccione el usuario de origen.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de destino.', 'Seleccione el usuario de destino.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue os SAVES do usuario de origem selecionado antes de iniciar a sincronia.', 'Cargue los SAVES del usuario de origen seleccionado antes de iniciar la sincronización.', [rfReplaceAll]);
    Result := StringReplace(Result, 'No mesmo PS4, selecione usuarios diferentes para origem e destino.', 'En la misma PS4, seleccione usuarios diferentes para el origen y el destino.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue e selecione ao menos um jogo para sincronizar.', 'Cargue y seleccione al menos un juego para sincronizar.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Sincronia manual concluida.', 'Sincronización manual completada.', [rfReplaceAll]);
    Result := StringReplace(Result, 'A criação das imagens pode demorar. Aguarde enquanto o processo é concluído...', 'La creación de imágenes puede tardar. Espere mientras finaliza el proceso...', [rfReplaceAll]);
    Result := StringReplace(Result, 'Avatar enviado. Reinicie o PS4 ou faça logout/login no usuário.', 'Avatar enviado. Reinicie la PS4 o cierre e inicie sesión de nuevo.', [rfReplaceAll]);
  end
  else if ALanguage = alGerman then
  begin
    Result := StringReplace(Result, 'Informe o IP de origem e o IP de destino.', 'Geben Sie die Quell- und Ziel-IP ein.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue os SAVES do IP de origem antes de iniciar a sincronia.', 'Laden Sie die SAVES der Quell-IP, bevor Sie die Synchronisierung starten.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de origem.', 'Wählen Sie den Quellbenutzer aus.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de destino.', 'Wählen Sie den Zielbenutzer aus.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue e selecione ao menos um jogo para sincronizar.', 'Laden und wählen Sie mindestens ein Spiel zur Synchronisierung aus.', [rfReplaceAll]);
  end
  else if ALanguage = alFrench then
  begin
    Result := StringReplace(Result, 'Informe o IP de origem e o IP de destino.', 'Indiquez l’adresse IP Left et l’adresse IP destination.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue os SAVES do IP de origem antes de iniciar a sincronia.', 'Chargez les sauvegardes de l’IP Left avant de démarrer la synchronisation.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de origem.', 'Sélectionnez l’utilisateur Left.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de destino.', 'Sélectionnez l’utilisateur destination.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue e selecione ao menos um jogo para sincronizar.', 'Chargez et sélectionnez au moins un jeu à synchroniser.', [rfReplaceAll]);
  end
  else if ALanguage = alRussian then
  begin
    Result := StringReplace(Result, 'Informe o IP de origem e o IP de destino.', 'Укажите IP-адрес источника и назначения.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de origem.', 'Выберите пользователя источника.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de destino.', 'Выберите пользователя назначения.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue e selecione ao menos um jogo para sincronizar.', 'Загрузите и выберите хотя бы одну игру для синхронизации.', [rfReplaceAll]);
  end
  else if ALanguage = alJapanese then
  begin
    Result := StringReplace(Result, 'Informe o IP de origem e o IP de destino.', '送信元と送信先のIPアドレスを入力してください。', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de origem.', '送信元ユーザーを選択してください。', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de destino.', '送信先ユーザーを選択してください。', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue e selecione ao menos um jogo para sincronizar.', '同期するゲームを1つ以上読み込んで選択してください。', [rfReplaceAll]);
  end
  else if ALanguage = alEnglish then
  begin
    Result := StringReplace(Result, 'Informe o IP de origem e o IP de destino.', 'Enter the source and destination IP addresses.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue os SAVES do IP de origem antes de iniciar a sincronia.', 'Load the source IP saves before starting synchronization.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de origem.', 'Select the source user.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Selecione o usuario de destino.', 'Select the destination user.', [rfReplaceAll]);
    Result := StringReplace(Result, 'Carregue e selecione ao menos um jogo para sincronizar.', 'Load and select at least one game to synchronize.', [rfReplaceAll]);
  end;
end;

function TranslateSyncText(const AKey: string; ALanguage: TAppLanguage;
  ACount: Integer; const AUser: string; const APath: string): string;
begin
  case ALanguage of
    alEnglish:
      begin
        if AKey = 'NeedGame' then Exit('Load and select at least one game to synchronize.');
        if AKey = 'ManualTitle' then Exit(Format('Synchronize %d save(s) in Manual mode?', [ACount]));
        if AKey = 'ManualBody' then Exit('The program will copy the encrypted saves to Apollo Fake USB on the destination PS4.' + sLineBreak + sLineBreak + 'Then open Apollo on the destination PS4, import/sign the saves, and copy them to the HDD manually.');
        if AKey = 'SameTitle' then Exit(Format('Synchronize %d save(s) on the same PS4 using the payload?', [ACount]));
        if AKey = 'SameBody' then Exit('The payload will mount/decrypt the Left user save, copy it to the destination user, and unmount it so the PS4 re-encrypts everything on the console.');
        if AKey = 'AgentTitle' then Exit(Format('Synchronize %d save(s) using PS4 Save Agent?', [ACount]));
        if AKey = 'AgentBody' then Exit('The program will create a decrypted backup on the PC and send the save to the destination PS4, where the Agent will recreate/re-encrypt it for user ' + AUser + '.');
        if AKey = 'ManualLog' then Exit('Manual synchronization completed. Open Apollo on the destination PS4 to import/sign the saves.');
        if AKey = 'ManualDone' then Exit('Manual synchronization completed.' + sLineBreak + 'Now open Apollo on the destination PS4 and import/sign the saves from Fake USB to the HDD.');
        if AKey = 'SameLog' then Exit('On-console synchronization completed.');
        if AKey = 'AgentLog' then Exit('Decrypted synchronization completed.');
        if AKey = 'AgentDone' then Exit('Decrypted backup and synchronization completed.' + sLineBreak + 'Local backups: ' + APath);
        if AKey = 'SyncError' then Exit('Synchronization failed: ');
      end;
    alSpanish:
      begin
        if AKey = 'NeedGame' then Exit('Cargue y seleccione al menos un juego para sincronizar.');
        if AKey = 'ManualTitle' then Exit(Format('¿Sincronizar %d partida(s) en modo manual?', [ACount]));
        if AKey = 'SameTitle' then Exit(Format('¿Sincronizar %d partida(s) en la misma PS4 mediante el payload?', [ACount]));
        if AKey = 'AgentTitle' then Exit(Format('¿Sincronizar %d partida(s) mediante PS4 Save Agent?', [ACount]));
        if AKey = 'ManualLog' then Exit('Sincronización manual completada. Abra Apollo en la PS4 de destino para importar y firmar las partidas.');
        if AKey = 'SameLog' then Exit('Sincronización interna completada.');
        if AKey = 'AgentLog' then Exit('Sincronización descifrada completada.');
        if AKey = 'SyncError' then Exit('Error de sincronización: ');
      end;
    alGerman:
      begin
        if AKey = 'NeedGame' then Exit('Laden und wählen Sie mindestens ein Spiel zur Synchronisierung aus.');
        if AKey = 'ManualTitle' then Exit(Format('%d Spielstand/Spielstände im manuellen Modus synchronisieren?', [ACount]));
        if AKey = 'SameTitle' then Exit(Format('%d Spielstand/Spielstände auf derselben PS4 über das Payload synchronisieren?', [ACount]));
        if AKey = 'AgentTitle' then Exit(Format('%d Spielstand/Spielstände mit dem PS4 Save Agent synchronisieren?', [ACount]));
        if AKey = 'ManualLog' then Exit('Manuelle Synchronisierung abgeschlossen. Öffnen Sie Apollo auf der Ziel-PS4.');
        if AKey = 'SameLog' then Exit('Synchronisierung auf der Konsole abgeschlossen.');
        if AKey = 'AgentLog' then Exit('Entschlüsselte Synchronisierung abgeschlossen.');
        if AKey = 'SyncError' then Exit('Synchronisierungsfehler: ');
      end;
    alFrench:
      begin
        if AKey = 'NeedGame' then Exit('Chargez et sélectionnez au moins un jeu à synchroniser.');
        if AKey = 'ManualTitle' then Exit(Format('Synchroniser %d sauvegarde(s) en mode manuel ?', [ACount]));
        if AKey = 'SameTitle' then Exit(Format('Synchroniser %d sauvegarde(s) sur la même PS4 avec le payload ?', [ACount]));
        if AKey = 'AgentTitle' then Exit(Format('Synchroniser %d sauvegarde(s) avec PS4 Save Agent ?', [ACount]));
        if AKey = 'ManualLog' then Exit('Synchronisation manuelle terminée. Ouvrez Apollo sur la PS4 destination.');
        if AKey = 'SameLog' then Exit('Synchronisation sur la console terminée.');
        if AKey = 'AgentLog' then Exit('Synchronisation déchiffrée terminée.');
        if AKey = 'SyncError' then Exit('Échec de la synchronisation : ');
      end;
    alRussian:
      begin
        if AKey = 'NeedGame' then Exit('Загрузите и выберите хотя бы одну игру для синхронизации.');
        if AKey = 'ManualTitle' then Exit(Format('Синхронизировать %d сохранений в ручном режиме?', [ACount]));
        if AKey = 'SameTitle' then Exit(Format('Синхронизировать %d сохранений на одной PS4 через payload?', [ACount]));
        if AKey = 'AgentTitle' then Exit(Format('Синхронизировать %d сохранений через PS4 Save Agent?', [ACount]));
        if AKey = 'ManualLog' then Exit('Ручная синхронизация завершена. Откройте Apollo на целевой PS4.');
        if AKey = 'SameLog' then Exit('Синхронизация на консоли завершена.');
        if AKey = 'AgentLog' then Exit('Расшифрованная синхронизация завершена.');
        if AKey = 'SyncError' then Exit('Ошибка синхронизации: ');
      end;
    alJapanese:
      begin
        if AKey = 'NeedGame' then Exit('同期するゲームを1つ以上読み込んで選択してください。');
        if AKey = 'ManualTitle' then Exit(Format('%d個のセーブを手動モードで同期しますか？', [ACount]));
        if AKey = 'SameTitle' then Exit(Format('ペイロードを使って同じPS4で%d個のセーブを同期しますか？', [ACount]));
        if AKey = 'AgentTitle' then Exit(Format('PS4 Save Agentで%d個のセーブを同期しますか？', [ACount]));
        if AKey = 'ManualLog' then Exit('手動同期が完了しました。宛先PS4でApolloを開いてください。');
        if AKey = 'SameLog' then Exit('本体内同期が完了しました。');
        if AKey = 'AgentLog' then Exit('復号同期が完了しました。');
        if AKey = 'SyncError' then Exit('同期エラー: ');
      end;
  end;

  if AKey = 'NeedGame' then Result := 'Carregue e selecione ao menos um jogo para sincronizar.'
  else if AKey = 'ManualTitle' then Result := Format('Sincronizar %d save(s) em modo Manual?', [ACount])
  else if AKey = 'SameTitle' then Result := Format('Sincronizar %d save(s) dentro do mesmo PS4 pelo payload?', [ACount])
  else if AKey = 'AgentTitle' then Result := Format('Sincronizar %d save(s) pelo PS4 Save Agent?', [ACount])
  else if AKey = 'ManualBody' then Result := 'O programa vai copiar os saves criptografados para o Fake USB do Apollo no PS4 destino.' + sLineBreak + sLineBreak + 'Depois voce ainda precisa abrir o Apollo no PS4 destino, importar/assinar os saves e copiar para o HDD manualmente.'
  else if AKey = 'SameBody' then Result := 'O payload vai montar/descriptografar o save do usuario origem, copiar para o usuario destino e desmontar para o PS4 recriptografar tudo no proprio console.'
  else if AKey = 'AgentBody' then Result := 'O programa fara backup descriptografado no PC e enviara o save para o PS4 destino, onde o Agent deve recriar/recriptografar para o usuario ' + AUser + '.'
  else if AKey = 'ManualLog' then Result := 'Sincronia manual concluida. Abra o Apollo no PS4 destino para importar/assinar os saves.'
  else if AKey = 'ManualDone' then Result := 'Sincronia manual concluida.' + sLineBreak + 'Agora abra o Apollo no PS4 destino e importe/assine os saves do Fake USB para o HDD.'
  else if AKey = 'SameLog' then Result := 'Sincronia interna pelo payload concluida.'
  else if AKey = 'AgentLog' then Result := 'Sincronia descriptografada concluida.'
  else if AKey = 'AgentDone' then Result := 'Backup e sincronia descriptografada concluidos.' + sLineBreak + 'Backups locais: ' + APath
  else if AKey = 'SyncError' then Result := 'Falha na sincronia: '
  else Result := AKey;
end;

end.
