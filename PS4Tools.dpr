program PS4Tools;

uses
  Vcl.Forms,
  Vcl.Themes,
  Vcl.Styles,
  UnitMain in 'sources\UnitMain.pas' {FormMain},
  UnitFunctions in 'sources\UnitFunctions.pas',
  UnitSaves in 'sources\UnitSaves.pas',
  UnitTranslations in 'sources\UnitTranslations.pas',
  UnitTropheus in 'sources\UnitTropheus.pas',
  UnitAvatar in 'sources\UnitAvatar.pas',
  UnitAvatarCrop in 'sources\UnitAvatarCrop.pas',
  UnitAvatarMask in 'sources\UnitAvatarMask.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  TStyleManager.TrySetStyle('Carbon');
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
