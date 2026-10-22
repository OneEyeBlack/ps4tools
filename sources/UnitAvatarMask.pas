unit UnitAvatarMask;

{ Editor manual de mascara (fundo transparente) para o avatar.
  A imagem comeca toda mantida (ou com o alfa que ja trouxer). Ferramentas:
    - Varinha: seleciona a regiao contigua de cor parecida com a do ponto
      clicado (tolerancia em %) e remove ou mantem essa regiao;
    - Pincel: pinta para remover ou manter, com tamanho e dureza;
    - Inverter, Desfazer (Ctrl+Z), Refazer (Ctrl+Y), Tudo mantido.
  Mouse: roda = zoom; botao direito ou do meio + arrastar = mover a vista.
  Ao confirmar, grava um PNG RGBA (alfa = mascara, bordas suavizadas e sem
  franja do fundo antigo). A imagem original nunca e alterada. A janela e
  criada por codigo (sem .dfm). }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Imaging.pngimage,
  UnitTranslations, UnitAvatarCrop,
  Vcl.Graphics;

{ Abre o editor; se o usuario confirmar, grava o resultado em AOutputPng e
  devolve True. Cancelar devolve False e nao grava nada. }
function ShowMaskEditor(const AImageFile, AOutputPng: string;
  ALanguage: TAppLanguage): Boolean;

implementation

const
  MAX_EDIT_SIDE = 2048;
  MAX_UNDO_BYTES = 160 * 1024 * 1024;

type
  TFormMaskEditor = class(TForm)
  private
    FImg: TAvatarPixels;
    FMask, FInitialMask: TBytes;
    FUndo, FRedo: TList<TBytes>;
    FLanguage: TAppLanguage;
    FBox: TPaintBox;
    FPanel: TPanel;
    FBuffer: TBitmap;
    FRgTool, FRgAction: TRadioGroup;
    FTbTol, FTbSize, FTbHard: TTrackBar;
    FLblTol, FLblSize, FLblHard, FLblHelp: TLabel;
    FChkSmooth: TCheckBox;
    FBtnInvert, FBtnUndo, FBtnRedo, FBtnReset, FBtnFit, FBtnOk, FBtnCancel: TButton;
    FScale, FOffX, FOffY: Double;
    FMouseX, FMouseY: Integer;
    FDirty, FStroking, FPanning: Boolean;
    FLastIX, FLastIY: Double;
    FLastPX, FLastPY: Integer;
    FColMap: TArray<Integer>;
    function T(const APt, AEn: string): string;
    procedure PushUndo;
    procedure DoUndo;
    procedure DoRedo;
    procedure UpdateLabels;
    procedure FitView;
    procedure ZoomAt(AX, AY: Integer; AFactor: Double);
    function KeepAction: Boolean;
    procedure WandAt(AIX, AIY: Integer);
    procedure Dab(ACX, ACY: Double);
    procedure Stroke(AX0, AY0, AX1, AY1: Double);
    procedure RenderBuffer;
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormShown(Sender: TObject);
    procedure FormResized(Sender: TObject);
    procedure SliderChanged(Sender: TObject);
    procedure InvertClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
  public
    constructor CreateEditor(const AImageFile: string; ALanguage: TAppLanguage);
    destructor Destroy; override;
    procedure SaveResult(const AOutputPng: string);
  end;

{ Reduz (media de area) uma imagem BGRA acima de MAX_EDIT_SIDE; cor ponderada
  pelo alfa. }
procedure DownscaleIfNeeded(var AImg: TAvatarPixels);
var
  NW, NH, X, Y, SX, SY, X0, X1, Y0, Y1, I, Cnt: Integer;
  Scale: Double;
  SumA, SumB, SumG, SumR: Int64;
  A: Integer;
  Dst: TArray<Byte>;
begin
  if (AImg.W <= MAX_EDIT_SIDE) and (AImg.H <= MAX_EDIT_SIDE) then
    Exit;
  Scale := MAX_EDIT_SIDE / Max(AImg.W, AImg.H);
  NW := Max(1, Round(AImg.W * Scale));
  NH := Max(1, Round(AImg.H * Scale));
  SetLength(Dst, NW * NH * 4);
  for Y := 0 to NH - 1 do
  begin
    Y0 := (Y * AImg.H) div NH;
    Y1 := ((Y + 1) * AImg.H) div NH;
    if Y1 <= Y0 then Y1 := Y0 + 1;
    for X := 0 to NW - 1 do
    begin
      X0 := (X * AImg.W) div NW;
      X1 := ((X + 1) * AImg.W) div NW;
      if X1 <= X0 then X1 := X0 + 1;
      SumA := 0; SumB := 0; SumG := 0; SumR := 0; Cnt := 0;
      for SY := Y0 to Y1 - 1 do
        for SX := X0 to X1 - 1 do
        begin
          I := (SY * AImg.W + SX) * 4;
          A := AImg.Data[I + 3];
          SumA := SumA + A;
          SumB := SumB + Int64(AImg.Data[I]) * A;
          SumG := SumG + Int64(AImg.Data[I + 1]) * A;
          SumR := SumR + Int64(AImg.Data[I + 2]) * A;
          Inc(Cnt);
        end;
      I := (Y * NW + X) * 4;
      if SumA > 0 then
      begin
        Dst[I] := Byte(SumB div SumA);
        Dst[I + 1] := Byte(SumG div SumA);
        Dst[I + 2] := Byte(SumR div SumA);
      end;
      Dst[I + 3] := Byte(SumA div Cnt);
    end;
  end;
  AImg.W := NW;
  AImg.H := NH;
  AImg.Data := Dst;
end;

function ShowMaskEditor(const AImageFile, AOutputPng: string;
  ALanguage: TAppLanguage): Boolean;
var
  Form: TFormMaskEditor;
begin
  Form := TFormMaskEditor.CreateEditor(AImageFile, ALanguage);
  try
    Result := Form.ShowModal = mrOk;
    if Result then
      Form.SaveResult(AOutputPng);
  finally
    Form.Free;
  end;
end;

{ ---------------------------------------------------------------------- }
{ TFormMaskEditor                                                         }
{ ---------------------------------------------------------------------- }

constructor TFormMaskEditor.CreateEditor(const AImageFile: string;
  ALanguage: TAppLanguage);

  function NewButton(const ACaption: string; ALeft, ATop, AWidth: Integer;
    AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := FPanel;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

  function NewLabel(ATop: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := FPanel;
    Result.SetBounds(12, ATop, 226, 17);
  end;

  function NewSlider(ATop, AMin, AMax, APos: Integer): TTrackBar;
  begin
    Result := TTrackBar.Create(Self);
    Result.Parent := FPanel;
    Result.SetBounds(6, ATop, 236, 28);
    Result.Min := AMin;
    Result.Max := AMax;
    Result.Position := APos;
    Result.TickStyle := tsNone;
    Result.OnChange := SliderChanged;
  end;

begin
  inherited CreateNew(nil);
  FLanguage := ALanguage;
  FUndo := TList<TBytes>.Create;
  FRedo := TList<TBytes>.Create;
  LoadAvatarPixels(AImageFile, FImg);
  DownscaleIfNeeded(FImg);
  SetLength(FMask, FImg.W * FImg.H);
  for var I := 0 to FImg.W * FImg.H - 1 do
    FMask[I] := FImg.Data[I * 4 + 3];
  FInitialMask := Copy(FMask);

  Caption := T('Editar fundo (manual)', 'Edit background (manual)');
  Position := poScreenCenter;
  BorderStyle := bsSizeable;
  ClientWidth := 1180;
  ClientHeight := 780;
  Constraints.MinWidth := 900;
  Constraints.MinHeight := 640;
  DoubleBuffered := True;
  KeyPreview := True;
  OnKeyDown := FormKey;
  OnMouseWheel := FormWheel;
  OnResize := FormResized;
  OnShow := FormShown;

  FPanel := TPanel.Create(Self);
  FPanel.Parent := Self;
  FPanel.Align := alRight;
  FPanel.Width := 250;
  FPanel.BevelOuter := bvNone;

  FBox := TPaintBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.Cursor := crCross;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseDown := BoxMouseDown;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;

  FRgTool := TRadioGroup.Create(Self);
  FRgTool.Parent := FPanel;
  FRgTool.SetBounds(8, 8, 234, 62);
  FRgTool.Caption := T('Ferramenta', 'Tool');
  FRgTool.Items.Add(T('Varinha (por cor)', 'Magic wand (by color)'));
  FRgTool.Items.Add(T('Pincel', 'Brush'));
  FRgTool.ItemIndex := 0;

  FRgAction := TRadioGroup.Create(Self);
  FRgAction.Parent := FPanel;
  FRgAction.SetBounds(8, 76, 234, 62);
  FRgAction.Caption := T('Acao', 'Action');
  FRgAction.Items.Add(T('Remover (fundo)', 'Remove (background)'));
  FRgAction.Items.Add(T('Manter', 'Keep'));
  FRgAction.ItemIndex := 0;

  FLblTol := NewLabel(146);
  FTbTol := NewSlider(162, 0, 100, 30);
  FLblSize := NewLabel(194);
  FTbSize := NewSlider(210, 1, 400, 40);
  FLblHard := NewLabel(242);
  FTbHard := NewSlider(258, 0, 100, 60);

  FChkSmooth := TCheckBox.Create(Self);
  FChkSmooth.Parent := FPanel;
  FChkSmooth.SetBounds(12, 294, 226, 17);
  FChkSmooth.Caption := T('Suavizar bordas', 'Smooth edges');
  FChkSmooth.Checked := True;

  FBtnInvert := NewButton(T('Inverter', 'Invert'), 8, 322, 114, InvertClick);
  FBtnUndo := NewButton(T('Desfazer', 'Undo'), 128, 322, 114, UndoClick);
  FBtnRedo := NewButton(T('Refazer', 'Redo'), 8, 356, 114, RedoClick);
  FBtnReset := NewButton(T('Tudo mantido', 'Keep all'), 128, 356, 114, ResetClick);
  FBtnFit := NewButton(T('Ajustar a janela', 'Fit to window'), 8, 390, 234, FitClick);

  FLblHelp := TLabel.Create(Self);
  FLblHelp.Parent := FPanel;
  FLblHelp.SetBounds(12, 430, 226, 150);
  FLblHelp.AutoSize := False;
  FLblHelp.WordWrap := True;
  FLblHelp.Caption := T(
    'Varinha: clique numa cor; ela age na regiao contigua parecida (tolerancia em %). ' +
    'Pincel: arraste. Roda: zoom. Botao direito ou do meio + arrastar: mover. ' +
    'Ctrl+Z desfaz, Ctrl+Y refaz.',
    'Wand: click a color; it acts on the contiguous similar region (tolerance %). ' +
    'Brush: drag. Wheel: zoom. Right or middle button + drag: pan. ' +
    'Ctrl+Z undo, Ctrl+Y redo.');

  FBtnOk := TButton.Create(Self);
  FBtnOk.Parent := FPanel;
  FBtnOk.SetBounds(8, 700, 114, 30);
  FBtnOk.Anchors := [akLeft, akBottom];
  FBtnOk.Caption := T('Confirmar', 'OK');
  FBtnOk.ModalResult := mrOk;
  FBtnOk.Default := True;
  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent := FPanel;
  FBtnCancel.SetBounds(128, 700, 114, 30);
  FBtnCancel.Anchors := [akLeft, akBottom];
  FBtnCancel.Caption := T('Cancelar', 'Cancel');
  FBtnCancel.ModalResult := mrCancel;
  FBtnCancel.Cancel := True;

  FBuffer := TBitmap.Create;
  FBuffer.PixelFormat := pf32bit;
  FDirty := True;
  UpdateLabels;
  FitView;
end;

destructor TFormMaskEditor.Destroy;
begin
  FBuffer.Free;
  FUndo.Free;
  FRedo.Free;
  inherited Destroy;
end;

function TFormMaskEditor.T(const APt, AEn: string): string;
begin
  if FLanguage = alEnglish then
    Result := AEn
  else
    Result := APt;
end;

procedure TFormMaskEditor.UpdateLabels;
begin
  FLblTol.Caption := T('Tolerancia: ', 'Tolerance: ') + IntToStr(FTbTol.Position) + '%';
  FLblSize.Caption := T('Tamanho do pincel: ', 'Brush size: ') + IntToStr(FTbSize.Position) + ' px';
  FLblHard.Caption := T('Dureza do pincel: ', 'Brush hardness: ') + IntToStr(FTbHard.Position) + '%';
  FBtnUndo.Enabled := FUndo.Count > 0;
  FBtnRedo.Enabled := FRedo.Count > 0;
end;

procedure TFormMaskEditor.SliderChanged(Sender: TObject);
begin
  UpdateLabels;
  FBox.Invalidate;
end;

{ ---------------------------------------------------------------------- }
{ Desfazer / refazer                                                      }
{ ---------------------------------------------------------------------- }

procedure TFormMaskEditor.PushUndo;
var
  MaxCount: Integer;
begin
  FUndo.Add(Copy(FMask));
  FRedo.Clear;
  MaxCount := Max(3, MAX_UNDO_BYTES div Max(1, Length(FMask)));
  while FUndo.Count > MaxCount do
    FUndo.Delete(0);
  UpdateLabels;
end;

procedure TFormMaskEditor.DoUndo;
begin
  if FUndo.Count = 0 then
    Exit;
  FRedo.Add(Copy(FMask));
  FMask := FUndo[FUndo.Count - 1];
  FUndo.Delete(FUndo.Count - 1);
  FDirty := True;
  UpdateLabels;
  FBox.Invalidate;
end;

procedure TFormMaskEditor.DoRedo;
begin
  if FRedo.Count = 0 then
    Exit;
  FUndo.Add(Copy(FMask));
  FMask := FRedo[FRedo.Count - 1];
  FRedo.Delete(FRedo.Count - 1);
  FDirty := True;
  UpdateLabels;
  FBox.Invalidate;
end;

procedure TFormMaskEditor.UndoClick(Sender: TObject);
begin
  DoUndo;
end;

procedure TFormMaskEditor.RedoClick(Sender: TObject);
begin
  DoRedo;
end;

procedure TFormMaskEditor.InvertClick(Sender: TObject);
var
  I: Integer;
begin
  PushUndo;
  for I := 0 to High(FMask) do
    FMask[I] := 255 - FMask[I];
  FDirty := True;
  FBox.Invalidate;
end;

procedure TFormMaskEditor.ResetClick(Sender: TObject);
begin
  PushUndo;
  FMask := Copy(FInitialMask);
  FDirty := True;
  FBox.Invalidate;
end;

{ ---------------------------------------------------------------------- }
{ Vista                                                                   }
{ ---------------------------------------------------------------------- }

procedure TFormMaskEditor.FitView;
var
  BW, BH: Integer;
begin
  BW := Max(1, FBox.Width);
  BH := Max(1, FBox.Height);
  FScale := Min(BW / FImg.W, BH / FImg.H) * 0.96;
  FOffX := (BW - FImg.W * FScale) / 2;
  FOffY := (BH - FImg.H * FScale) / 2;
  FDirty := True;
  FBox.Invalidate;
end;

procedure TFormMaskEditor.FitClick(Sender: TObject);
begin
  FitView;
end;

procedure TFormMaskEditor.FormShown(Sender: TObject);
begin
  FitView;
end;

procedure TFormMaskEditor.FormResized(Sender: TObject);
begin
  if FBox = nil then
    Exit;
  FDirty := True;
  FBox.Invalidate;
end;

procedure TFormMaskEditor.ZoomAt(AX, AY: Integer; AFactor: Double);
var
  PX, PY, NewScale: Double;
begin
  NewScale := FScale * AFactor;
  if NewScale < 0.05 then NewScale := 0.05;
  if NewScale > 40 then NewScale := 40;
  PX := (AX - FOffX) / FScale;
  PY := (AY - FOffY) / FScale;
  FScale := NewScale;
  FOffX := AX - PX * FScale;
  FOffY := AY - PY * FScale;
  FDirty := True;
  FBox.Invalidate;
end;

{ ---------------------------------------------------------------------- }
{ Ferramentas                                                             }
{ ---------------------------------------------------------------------- }

function TFormMaskEditor.KeepAction: Boolean;
begin
  Result := FRgAction.ItemIndex = 1;
end;

{ Varinha: regiao 4-conexa cuja cor esta a ate Tolerancia% (distancia RMS dos
  canais / 255) da cor do ponto clicado. }
procedure TFormMaskEditor.WandAt(AIX, AIY: Integer);
var
  N, W, H, SP, I, X, Y, SR, SG, SB, DR, DG, DB: Integer;
  Limit: Int64;
  Visited: TBytes;
  Stack: TArray<Integer>;
  Value: Byte;

  function Similar(AIndex: Integer): Boolean;
  begin
    DB := FImg.Data[AIndex * 4] - SB;
    DG := FImg.Data[AIndex * 4 + 1] - SG;
    DR := FImg.Data[AIndex * 4 + 2] - SR;
    Result := Int64(DR) * DR + Int64(DG) * DG + Int64(DB) * DB <= Limit;
  end;

  procedure Push(AIndex: Integer);
  begin
    Visited[AIndex] := 1;
    Stack[SP] := AIndex;
    Inc(SP);
  end;

begin
  W := FImg.W;
  H := FImg.H;
  if (AIX < 0) or (AIY < 0) or (AIX >= W) or (AIY >= H) then
    Exit;
  N := W * H;
  I := AIY * W + AIX;
  SB := FImg.Data[I * 4];
  SG := FImg.Data[I * 4 + 1];
  SR := FImg.Data[I * 4 + 2];
  Limit := Round(3 * Sqr(FTbTol.Position / 100 * 255));
  SetLength(Visited, N);
  SetLength(Stack, N);
  SP := 0;
  PushUndo;
  Push(I);
  while SP > 0 do
  begin
    Dec(SP);
    I := Stack[SP];
    Y := I div W;
    X := I - Y * W;
    if (X > 0) and (Visited[I - 1] = 0) and Similar(I - 1) then Push(I - 1);
    if (X < W - 1) and (Visited[I + 1] = 0) and Similar(I + 1) then Push(I + 1);
    if (Y > 0) and (Visited[I - W] = 0) and Similar(I - W) then Push(I - W);
    if (Y < H - 1) and (Visited[I + W] = 0) and Similar(I + W) then Push(I + W);
  end;
  if KeepAction then Value := 255 else Value := 0;
  for I := 0 to N - 1 do
    if Visited[I] = 1 then
      FMask[I] := Value;
  FDirty := True;
end;

{ Um toque do pincel circular. Dureza 100% = borda nitida (com 1 px de
  suavizacao); menos que isso cria uma transicao macia ate a borda. }
procedure TFormMaskEditor.Dab(ACX, ACY: Double);
var
  R, Inner, Fall, D, S, Cur: Double;
  X0, X1, Y0, Y1, X, Y, I, V: Integer;
  Keep: Boolean;
begin
  R := FTbSize.Position / 2;
  Fall := Max(R * (1 - FTbHard.Position / 100), 1);
  Inner := R - Fall;
  Keep := KeepAction;
  X0 := Max(0, Floor(ACX - R - 1));
  X1 := Min(FImg.W - 1, Ceil(ACX + R + 1));
  Y0 := Max(0, Floor(ACY - R - 1));
  Y1 := Min(FImg.H - 1, Ceil(ACY + R + 1));
  for Y := Y0 to Y1 do
    for X := X0 to X1 do
    begin
      D := Sqrt(Sqr(X + 0.5 - ACX) + Sqr(Y + 0.5 - ACY));
      if D >= R then
        Continue;
      if D <= Inner then
        S := 1
      else
        S := (R - D) / Fall;
      S := S * S * (3 - 2 * S);
      I := Y * FImg.W + X;
      Cur := FMask[I];
      if Keep then
        V := Round(Max(Cur, 255 * S))
      else
        V := Round(Min(Cur, 255 - 255 * S));
      FMask[I] := Byte(V);
    end;
  FDirty := True;
end;

procedure TFormMaskEditor.Stroke(AX0, AY0, AX1, AY1: Double);
var
  Dist, Step, Tt: Double;
  N, K: Integer;
begin
  Step := Max(1.0, FTbSize.Position * 0.15);
  Dist := Sqrt(Sqr(AX1 - AX0) + Sqr(AY1 - AY0));
  N := Max(1, Trunc(Dist / Step));
  for K := 0 to N do
  begin
    Tt := K / N;
    Dab(AX0 + (AX1 - AX0) * Tt, AY0 + (AY1 - AY0) * Tt);
  end;
end;

{ ---------------------------------------------------------------------- }
{ Mouse e teclado                                                         }
{ ---------------------------------------------------------------------- }

procedure TFormMaskEditor.BoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  IX, IY: Double;
begin
  FLastPX := X;
  FLastPY := Y;
  if (Button = mbRight) or (Button = mbMiddle) then
  begin
    FPanning := True;
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  IX := (X - FOffX) / FScale;
  IY := (Y - FOffY) / FScale;
  if FRgTool.ItemIndex = 0 then
  begin
    WandAt(Floor(IX), Floor(IY));
    UpdateLabels;
    FBox.Invalidate;
  end
  else
  begin
    PushUndo;
    FStroking := True;
    FLastIX := IX;
    FLastIY := IY;
    Dab(IX, IY);
    FBox.Invalidate;
  end;
end;

procedure TFormMaskEditor.BoxMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  IX, IY: Double;
begin
  FMouseX := X;
  FMouseY := Y;
  if FPanning then
  begin
    FOffX := FOffX + (X - FLastPX);
    FOffY := FOffY + (Y - FLastPY);
    FDirty := True;
  end
  else if FStroking then
  begin
    IX := (X - FOffX) / FScale;
    IY := (Y - FOffY) / FScale;
    Stroke(FLastIX, FLastIY, IX, IY);
    FLastIX := IX;
    FLastIY := IY;
  end;
  FLastPX := X;
  FLastPY := Y;
  FBox.Invalidate;
end;

procedure TFormMaskEditor.BoxMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FStroking := False;
  FPanning := False;
end;

procedure TFormMaskEditor.FormWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  P: TPoint;
begin
  Handled := True;
  P := FBox.ScreenToClient(MousePos);
  if WheelDelta > 0 then
    ZoomAt(P.X, P.Y, 1.15)
  else
    ZoomAt(P.X, P.Y, 1 / 1.15);
end;

procedure TFormMaskEditor.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (ssCtrl in Shift) and (Key = Ord('Z')) then
    DoUndo
  else if (ssCtrl in Shift) and (Key = Ord('Y')) then
    DoRedo
  else if Key = VK_ESCAPE then
    ModalResult := mrCancel;
end;

{ ---------------------------------------------------------------------- }
{ Desenho                                                                 }
{ ---------------------------------------------------------------------- }

procedure TFormMaskEditor.RenderBuffer;
var
  BW, BH, X, Y, IX, IY, I, A, Bg, R, G, B: Integer;
  Row, Px: PByte;
begin
  BW := FBox.Width;
  BH := FBox.Height;
  if (FBuffer.Width <> BW) or (FBuffer.Height <> BH) then
    FBuffer.SetSize(BW, BH);
  SetLength(FColMap, BW);
  for X := 0 to BW - 1 do
  begin
    IX := Floor((X + 0.5 - FOffX) / FScale);
    if (IX < 0) or (IX >= FImg.W) then
      FColMap[X] := -1
    else
      FColMap[X] := IX;
  end;
  for Y := 0 to BH - 1 do
  begin
    Row := FBuffer.ScanLine[Y];
    IY := Floor((Y + 0.5 - FOffY) / FScale);
    for X := 0 to BW - 1 do
    begin
      Px := PByte(NativeUInt(Row) + NativeUInt(X) * 4);
      IX := FColMap[X];
      if (IX < 0) or (IY < 0) or (IY >= FImg.H) then
      begin
        Px^ := 40;
        PByte(NativeUInt(Px) + 1)^ := 40;
        PByte(NativeUInt(Px) + 2)^ := 40;
      end
      else
      begin
        I := IY * FImg.W + IX;
        A := FMask[I];
        if (((X shr 3) + (Y shr 3)) and 1) = 0 then
          Bg := 96
        else
          Bg := 136;
        B := FImg.Data[I * 4];
        G := FImg.Data[I * 4 + 1];
        R := FImg.Data[I * 4 + 2];
        Px^ := Byte((B * A + Bg * (255 - A)) div 255);
        PByte(NativeUInt(Px) + 1)^ := Byte((G * A + Bg * (255 - A)) div 255);
        PByte(NativeUInt(Px) + 2)^ := Byte((R * A + Bg * (255 - A)) div 255);
      end;
      PByte(NativeUInt(Px) + 3)^ := 255;
    end;
  end;
  FDirty := False;
end;

procedure TFormMaskEditor.BoxPaint(Sender: TObject);
var
  Rad: Integer;
begin
  if (FBox.Width <= 0) or (FBox.Height <= 0) then
    Exit;
  if FDirty or (FBuffer.Width <> FBox.Width) or (FBuffer.Height <> FBox.Height) then
    RenderBuffer;
  FBox.Canvas.Draw(0, 0, FBuffer);
  { contorno do pincel }
  if FRgTool.ItemIndex = 1 then
  begin
    Rad := Round(FTbSize.Position / 2 * FScale);
    FBox.Canvas.Pen.Color := clWhite;
    FBox.Canvas.Pen.Width := 1;
    FBox.Canvas.Brush.Style := bsClear;
    FBox.Canvas.Ellipse(FMouseX - Rad, FMouseY - Rad, FMouseX + Rad + 1, FMouseY + Rad + 1);
  end;
end;

{ ---------------------------------------------------------------------- }
{ Resultado                                                               }
{ ---------------------------------------------------------------------- }

{ Alfa final = mascara, com borda suavizada (binomial 3x3) e a cor dos pixels
  de borda trocada pela de vizinhos opacos (sem franja do fundo antigo). }
procedure TFormMaskEditor.SaveResult(const AOutputPng: string);
var
  W, H, X, Y, I, NX, NY, DX, DY, SumB, SumG, SumR, Cnt, V: Integer;
  Alpha, Tmp: TBytes;
  Png: TPngImage;
  Row, AlphaRow, P: PByte;
  ColorBuf: TArray<Byte>;

begin
  W := FImg.W;
  H := FImg.H;
  Alpha := Copy(FMask);
  if FChkSmooth.Checked then
  begin
    Tmp := Copy(Alpha);
    { horizontal [1 2 1]/4 }
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        I := Y * W + X;
        V := Alpha[I] * 2;
        if X > 0 then Inc(V, Alpha[I - 1]) else Inc(V, Alpha[I]);
        if X < W - 1 then Inc(V, Alpha[I + 1]) else Inc(V, Alpha[I]);
        Tmp[I] := Byte((V + 2) div 4);
      end;
    { vertical [1 2 1]/4 }
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        I := Y * W + X;
        V := Tmp[I] * 2;
        if Y > 0 then Inc(V, Tmp[I - W]) else Inc(V, Tmp[I]);
        if Y < H - 1 then Inc(V, Tmp[I + W]) else Inc(V, Tmp[I]);
        Alpha[I] := Byte((V + 2) div 4);
      end;
  end;

  ColorBuf := Copy(FImg.Data);
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      I := Y * W + X;
      if (Alpha[I] = 0) or (Alpha[I] > 250) then
        Continue;
      SumB := 0; SumG := 0; SumR := 0; Cnt := 0;
      for DY := -2 to 2 do
      begin
        NY := Y + DY;
        if (NY < 0) or (NY >= H) then Continue;
        for DX := -2 to 2 do
        begin
          NX := X + DX;
          if (NX < 0) or (NX >= W) then Continue;
          if Alpha[NY * W + NX] > 250 then
          begin
            Inc(SumB, FImg.Data[(NY * W + NX) * 4]);
            Inc(SumG, FImg.Data[(NY * W + NX) * 4 + 1]);
            Inc(SumR, FImg.Data[(NY * W + NX) * 4 + 2]);
            Inc(Cnt);
          end;
        end;
      end;
      if Cnt > 0 then
      begin
        ColorBuf[I * 4] := Byte(SumB div Cnt);
        ColorBuf[I * 4 + 1] := Byte(SumG div Cnt);
        ColorBuf[I * 4 + 2] := Byte(SumR div Cnt);
      end;
    end;

  Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, W, H);
  try
    for Y := 0 to H - 1 do
    begin
      { o scanline do TPngImage guarda B, G, R; o alfa fica em outro vetor }
      Row := PByte(Png.Scanline[Y]);
      AlphaRow := PByte(Png.AlphaScanline[Y]);
      for X := 0 to W - 1 do
      begin
        I := Y * W + X;
        P := PByte(NativeUInt(Row) + NativeUInt(X) * 3);
        P^ := ColorBuf[I * 4];
        PByte(NativeUInt(P) + 1)^ := ColorBuf[I * 4 + 1];
        PByte(NativeUInt(P) + 2)^ := ColorBuf[I * 4 + 2];
        PByte(NativeUInt(AlphaRow) + NativeUInt(X))^ := Alpha[I];
      end;
    end;
    Png.SaveToFile(AOutputPng);
  finally
    Png.Free;
  end;
end;

end.
