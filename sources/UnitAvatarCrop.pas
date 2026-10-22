unit UnitAvatarCrop;

{ Janela de enquadramento do avatar. Mostra a imagem com uma moldura na
  proporcao do avatar.png do PlayStation (440x400) e deixa o usuario ajustar o
  recorte:
    - arrastar com o botao esquerdo: mover a imagem;
    - roda do mouse: zoom em torno do cursor;
    - Shift + roda (ou botao direito + arrastar): girar;
    - botoes/barras: girar 90 graus, espelhar, angulo livre, zoom, restaurar.
  Ao confirmar, grava o recorte em PNG (RGBA) na resolucao da imagem. A imagem
  original nunca e alterada. A janela e criada por codigo (sem .dfm). }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math,
  Winapi.Windows,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg,
  UnitTranslations,
  Vcl.Graphics;

const
  AVATAR_ASPECT_W = 440;
  AVATAR_ASPECT_H = 400;

type
  { Imagem em memoria: BGRA, alfa reto (compartilhada com o editor de mascara). }
  TAvatarPixels = record
    W, H: Integer;
    HasAlpha: Boolean;
    Data: TArray<Byte>;
  end;

{ Le um arquivo de imagem para BGRA. PNG RGBA de 8 bits mantem o alfa; os
  demais formatos ficam opacos (sobre fundo branco). }
procedure LoadAvatarPixels(const AFileName: string; out AImg: TAvatarPixels);

{ True se a proporcao da imagem difere da do avatar (mais de 2%). }
function AvatarNeedsCrop(const AImageFile: string): Boolean;

{ Abre a janela; se o usuario confirmar, grava o recorte em AOutputPng e
  devolve True. Cancelar devolve False e nao grava nada. }
function ShowAvatarCropDialog(const AImageFile, AOutputPng: string;
  ALanguage: TAppLanguage): Boolean;

implementation

type
  { Transformacao da vista: o centro da vista mostra o ponto (CX, CY) da
    imagem; Scale = pixels da vista por pixel da imagem; depois vem o giro e o
    espelhamento. }
  TCropView = record
    CX, CY: Double;
    Scale: Double;
    CosA, SinA: Double;
    FlipH, FlipV: Boolean;
  end;

  TFormAvatarCrop = class(TForm)
  private
    FImg: TAvatarPixels;
    FLanguage: TAppLanguage;
    FBox: TPaintBox;
    FPanel: TPanel;
    FBuffer: TBitmap;
    FTbZoom, FTbAngle: TTrackBar;
    FLblZoom, FLblAngle, FLblHelp: TLabel;
    FBtnRotL, FBtnRotR, FBtnFlipH, FBtnFlipV, FBtnReset, FBtnOk, FBtnCancel: TButton;
    FCX, FCY, FScale, FBaseScale, FAngle: Double;
    FFlipH, FFlipV: Boolean;
    FFrame: TRect;
    FDragging, FRotating, FUpdating: Boolean;
    FLastX, FLastY: Integer;
    function T(const APt, AEn: string): string;
    function CurrentView(AScale: Double): TCropView;
    procedure UpdateFrame;
    procedure ResetView;
    procedure SyncControls;
    procedure SetAngle(AValue: Double);
    procedure ZoomAt(AX, AY: Double; AFactor: Double);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormResized(Sender: TObject);
    procedure FormShown(Sender: TObject);
    procedure ZoomChanged(Sender: TObject);
    procedure AngleChanged(Sender: TObject);
    procedure RotLClick(Sender: TObject);
    procedure RotRClick(Sender: TObject);
    procedure FlipHClick(Sender: TObject);
    procedure FlipVClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
  public
    constructor CreateCrop(const AImageFile: string; ALanguage: TAppLanguage);
    destructor Destroy; override;
    procedure SaveCrop(const AOutputPng: string);
  end;

{ ---------------------------------------------------------------------- }
{ Imagem em pixels e amostragem                                           }
{ ---------------------------------------------------------------------- }

procedure LoadAvatarPixels(const AFileName: string; out AImg: TAvatarPixels);
var
  Pic: TPicture;
  Png: TPngImage;
  Bmp: TBitmap;
  X, Y, I: Integer;
  Row, AlphaRow: PByte;
begin
  AImg.HasAlpha := False;
  Pic := TPicture.Create;
  try
    Pic.LoadFromFile(AFileName);
    AImg.W := Pic.Width;
    AImg.H := Pic.Height;
    if (AImg.W <= 0) or (AImg.H <= 0) then
      raise Exception.Create('Imagem invalida.');
    SetLength(AImg.Data, AImg.W * AImg.H * 4);
    if (Pic.Graphic is TPngImage) and
       (TPngImage(Pic.Graphic).Header.ColorType = COLOR_RGBALPHA) and
       (TPngImage(Pic.Graphic).Header.BitDepth = 8) then
    begin
      Png := TPngImage(Pic.Graphic);
      for Y := 0 to AImg.H - 1 do
      begin
        { o scanline do TPngImage guarda B, G, R; o alfa fica em outro vetor }
        Row := PByte(Png.Scanline[Y]);
        AlphaRow := PByte(Png.AlphaScanline[Y]);
        for X := 0 to AImg.W - 1 do
        begin
          I := (Y * AImg.W + X) * 4;
          AImg.Data[I] := PByte(NativeUInt(Row) + NativeUInt(X) * 3)^;
          AImg.Data[I + 1] := PByte(NativeUInt(Row) + NativeUInt(X) * 3 + 1)^;
          AImg.Data[I + 2] := PByte(NativeUInt(Row) + NativeUInt(X) * 3 + 2)^;
          AImg.Data[I + 3] := PByte(NativeUInt(AlphaRow) + NativeUInt(X))^;
        end;
      end;
      AImg.HasAlpha := True;
    end
    else
    begin
      Bmp := TBitmap.Create;
      try
        Bmp.PixelFormat := pf24bit;
        Bmp.SetSize(AImg.W, AImg.H);
        Bmp.Canvas.Brush.Color := clWhite;
        Bmp.Canvas.FillRect(Rect(0, 0, AImg.W, AImg.H));
        Bmp.Canvas.Draw(0, 0, Pic.Graphic);
        for Y := 0 to AImg.H - 1 do
        begin
          Row := Bmp.ScanLine[Y];
          for X := 0 to AImg.W - 1 do
          begin
            I := (Y * AImg.W + X) * 4;
            AImg.Data[I] := PByte(NativeUInt(Row) + NativeUInt(X) * 3)^;
            AImg.Data[I + 1] := PByte(NativeUInt(Row) + NativeUInt(X) * 3 + 1)^;
            AImg.Data[I + 2] := PByte(NativeUInt(Row) + NativeUInt(X) * 3 + 2)^;
            AImg.Data[I + 3] := 255;
          end;
        end;
      finally
        Bmp.Free;
      end;
    end;
  finally
    Pic.Free;
  end;
end;

{ Amostra a imagem no ponto continuo (U, V) em pixels da imagem (o pixel i
  cobre [i, i+1)). Bilinear com cores ponderadas pelo alfa, ou vizinho mais
  proximo. Fora da imagem o alfa e 0. }
procedure SampleImage(const AImg: TAvatarPixels; U, V: Double; ABilinear: Boolean;
  out R, G, B, A: Byte);
var
  GX, GY, FX, FY, W00, W10, W01, W11, A00, A10, A01, A11, Alpha, SumR, SumG, SumB: Double;
  X0, Y0, X1, Y1, I: Integer;

  function Fetch(AX, AY: Integer; out AAlpha: Double; out AIndex: Integer): Boolean;
  begin
    Result := (AX >= 0) and (AY >= 0) and (AX < AImg.W) and (AY < AImg.H);
    if Result then
    begin
      AIndex := (AY * AImg.W + AX) * 4;
      AAlpha := AImg.Data[AIndex + 3] / 255;
    end
    else
    begin
      AIndex := 0;
      AAlpha := 0;
    end;
  end;

var
  I00, I10, I01, I11: Integer;
begin
  R := 0; G := 0; B := 0; A := 0;
  if not ABilinear then
  begin
    X0 := Floor(U);
    Y0 := Floor(V);
    if Fetch(X0, Y0, A00, I00) then
    begin
      B := AImg.Data[I00];
      G := AImg.Data[I00 + 1];
      R := AImg.Data[I00 + 2];
      A := AImg.Data[I00 + 3];
    end;
    Exit;
  end;

  GX := U - 0.5;
  GY := V - 0.5;
  X0 := Floor(GX);
  Y0 := Floor(GY);
  X1 := X0 + 1;
  Y1 := Y0 + 1;
  FX := GX - X0;
  FY := GY - Y0;
  W00 := (1 - FX) * (1 - FY);
  W10 := FX * (1 - FY);
  W01 := (1 - FX) * FY;
  W11 := FX * FY;
  Fetch(X0, Y0, A00, I00);
  Fetch(X1, Y0, A10, I10);
  Fetch(X0, Y1, A01, I01);
  Fetch(X1, Y1, A11, I11);
  Alpha := W00 * A00 + W10 * A10 + W01 * A01 + W11 * A11;
  if Alpha <= 0 then
    Exit;
  SumB := W00 * A00 * AImg.Data[I00] + W10 * A10 * AImg.Data[I10] +
    W01 * A01 * AImg.Data[I01] + W11 * A11 * AImg.Data[I11];
  SumG := W00 * A00 * AImg.Data[I00 + 1] + W10 * A10 * AImg.Data[I10 + 1] +
    W01 * A01 * AImg.Data[I01 + 1] + W11 * A11 * AImg.Data[I11 + 1];
  SumR := W00 * A00 * AImg.Data[I00 + 2] + W10 * A10 * AImg.Data[I10 + 2] +
    W01 * A01 * AImg.Data[I01 + 2] + W11 * A11 * AImg.Data[I11 + 2];
  B := Byte(Round(SumB / Alpha));
  G := Byte(Round(SumG / Alpha));
  R := Byte(Round(SumR / Alpha));
  I := Round(Alpha * 255);
  if I > 255 then I := 255;
  A := Byte(I);
end;

{ Ponto continuo (X, Y) da vista de tamanho AW x AH -> ponto da imagem. }
procedure ViewToImage(const AView: TCropView; X, Y: Double; AW, AH: Integer;
  out U, V: Double);
var
  VX, VY, SX, SY: Double;
begin
  VX := X - AW / 2;
  VY := Y - AH / 2;
  SX := VX * AView.CosA + VY * AView.SinA;
  SY := -VX * AView.SinA + VY * AView.CosA;
  if AView.FlipH then SX := -SX;
  if AView.FlipV then SY := -SY;
  U := AView.CX + SX / AView.Scale;
  V := AView.CY + SY / AView.Scale;
end;

{ ---------------------------------------------------------------------- }
{ Funcoes publicas                                                        }
{ ---------------------------------------------------------------------- }

function AvatarNeedsCrop(const AImageFile: string): Boolean;
var
  Pic: TPicture;
  Ratio, Target: Double;
begin
  Pic := TPicture.Create;
  try
    Pic.LoadFromFile(AImageFile);
    if (Pic.Width <= 0) or (Pic.Height <= 0) then
      Exit(False);
    Ratio := Pic.Width / Pic.Height;
    Target := AVATAR_ASPECT_W / AVATAR_ASPECT_H;
    Result := Abs(Ratio / Target - 1) > 0.02;
  finally
    Pic.Free;
  end;
end;

function ShowAvatarCropDialog(const AImageFile, AOutputPng: string;
  ALanguage: TAppLanguage): Boolean;
var
  Form: TFormAvatarCrop;
begin
  Form := TFormAvatarCrop.CreateCrop(AImageFile, ALanguage);
  try
    Result := Form.ShowModal = mrOk;
    if Result then
      Form.SaveCrop(AOutputPng);
  finally
    Form.Free;
  end;
end;

{ ---------------------------------------------------------------------- }
{ TFormAvatarCrop                                                         }
{ ---------------------------------------------------------------------- }

constructor TFormAvatarCrop.CreateCrop(const AImageFile: string;
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

begin
  inherited CreateNew(nil);
  FLanguage := ALanguage;
  LoadAvatarPixels(AImageFile, FImg);

  Caption := T('Enquadrar imagem', 'Crop image');
  Position := poScreenCenter;
  BorderStyle := bsSizeable;
  ClientWidth := 920;
  ClientHeight := 720;
  Constraints.MinWidth := 760;
  Constraints.MinHeight := 560;
  DoubleBuffered := True;
  KeyPreview := True;
  OnKeyDown := FormKey;
  OnMouseWheel := FormWheel;
  OnResize := FormResized;
  OnShow := FormShown;

  FPanel := TPanel.Create(Self);
  FPanel.Parent := Self;
  FPanel.Align := alBottom;
  FPanel.Height := 104;
  FPanel.BevelOuter := bvNone;

  FBox := TPaintBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseDown := BoxMouseDown;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;

  FLblZoom := TLabel.Create(Self);
  FLblZoom.Parent := FPanel;
  FLblZoom.SetBounds(12, 12, 50, 17);
  FLblZoom.Caption := 'Zoom';
  FTbZoom := TTrackBar.Create(Self);
  FTbZoom.Parent := FPanel;
  FTbZoom.SetBounds(62, 4, 300, 32);
  FTbZoom.Min := 0;
  FTbZoom.Max := 200;
  FTbZoom.TickStyle := tsNone;
  FTbZoom.OnChange := ZoomChanged;

  FLblAngle := TLabel.Create(Self);
  FLblAngle.Parent := FPanel;
  FLblAngle.SetBounds(384, 12, 120, 17);
  FTbAngle := TTrackBar.Create(Self);
  FTbAngle.Parent := FPanel;
  FTbAngle.SetBounds(506, 4, 300, 32);
  FTbAngle.Min := -180;
  FTbAngle.Max := 180;
  FTbAngle.TickStyle := tsNone;
  FTbAngle.OnChange := AngleChanged;

  FBtnRotL := NewButton(T('Girar -90', 'Rotate -90') + Chr(176), 12, 44, 100, RotLClick);
  FBtnRotR := NewButton(T('Girar +90', 'Rotate +90') + Chr(176), 118, 44, 100, RotRClick);
  FBtnFlipH := NewButton(T('Espelhar H', 'Flip H'), 224, 44, 100, FlipHClick);
  FBtnFlipV := NewButton(T('Espelhar V', 'Flip V'), 330, 44, 100, FlipVClick);
  FBtnReset := NewButton(T('Restaurar', 'Reset'), 436, 44, 100, ResetClick);

  FBtnOk := TButton.Create(Self);
  FBtnOk.Parent := FPanel;
  FBtnOk.SetBounds(ClientWidth - 220, 44, 100, 28);
  FBtnOk.Anchors := [akRight, akTop];
  FBtnOk.Caption := T('Confirmar', 'OK');
  FBtnOk.ModalResult := mrOk;
  FBtnOk.Default := True;
  FBtnCancel := TButton.Create(Self);
  FBtnCancel.Parent := FPanel;
  FBtnCancel.SetBounds(ClientWidth - 112, 44, 100, 28);
  FBtnCancel.Anchors := [akRight, akTop];
  FBtnCancel.Caption := T('Cancelar', 'Cancel');
  FBtnCancel.ModalResult := mrCancel;
  FBtnCancel.Cancel := True;

  FLblHelp := TLabel.Create(Self);
  FLblHelp.Parent := FPanel;
  FLblHelp.SetBounds(12, 80, 880, 17);
  FLblHelp.Caption := T(
    'Arraste para mover  |  Roda: zoom  |  Shift+roda ou botao direito+arrastar: girar',
    'Drag to move  |  Wheel: zoom  |  Shift+wheel or right-drag: rotate');

  FBuffer := TBitmap.Create;
  FBuffer.PixelFormat := pf32bit;
  UpdateFrame;
  ResetView;
end;

destructor TFormAvatarCrop.Destroy;
begin
  FBuffer.Free;
  inherited Destroy;
end;

function TFormAvatarCrop.T(const APt, AEn: string): string;
begin
  if FLanguage = alEnglish then
    Result := AEn
  else
    Result := APt;
end;

function TFormAvatarCrop.CurrentView(AScale: Double): TCropView;
begin
  Result.CX := FCX;
  Result.CY := FCY;
  Result.Scale := AScale;
  Result.CosA := Cos(FAngle * Pi / 180);
  Result.SinA := Sin(FAngle * Pi / 180);
  Result.FlipH := FFlipH;
  Result.FlipV := FFlipV;
end;

procedure TFormAvatarCrop.UpdateFrame;
var
  BW, BH, FW, FH: Integer;
begin
  BW := FBox.Width;
  BH := FBox.Height;
  FW := Round(Min(BW * 0.86, BH * 0.86 * AVATAR_ASPECT_W / AVATAR_ASPECT_H));
  if FW < 40 then FW := 40;
  FH := Round(FW * AVATAR_ASPECT_H / AVATAR_ASPECT_W);
  FFrame := Rect((BW - FW) div 2, (BH - FH) div 2,
    (BW - FW) div 2 + FW, (BH - FH) div 2 + FH);
end;

{ Zoom inicial: a imagem cobre toda a moldura ("cover"), centralizada. }
procedure TFormAvatarCrop.ResetView;
var
  FW, FH: Integer;
begin
  FW := FFrame.Right - FFrame.Left;
  FH := FFrame.Bottom - FFrame.Top;
  FBaseScale := Max(FW / FImg.W, FH / FImg.H);
  FScale := FBaseScale;
  FCX := FImg.W / 2;
  FCY := FImg.H / 2;
  FAngle := 0;
  FFlipH := False;
  FFlipV := False;
  SyncControls;
  FBox.Invalidate;
end;

procedure TFormAvatarCrop.SyncControls;
var
  Pos: Integer;
begin
  FUpdating := True;
  try
    { zoom em escala logaritmica: 0..200 = 1/16x .. 16x do zoom inicial }
    Pos := Round(25 * Log2(FScale / FBaseScale)) + 100;
    if Pos < 0 then Pos := 0;
    if Pos > 200 then Pos := 200;
    FTbZoom.Position := Pos;
    FTbAngle.Position := Round(FAngle);
    FLblAngle.Caption := T('Angulo: ', 'Angle: ') + IntToStr(Round(FAngle)) + Chr(176);
  finally
    FUpdating := False;
  end;
end;

procedure TFormAvatarCrop.SetAngle(AValue: Double);
begin
  while AValue > 180 do AValue := AValue - 360;
  while AValue <= -180 do AValue := AValue + 360;
  FAngle := AValue;
  SyncControls;
  FBox.Invalidate;
end;

{ Zoom mantendo fixo o ponto da imagem que esta sob o cursor (AX, AY na vista). }
procedure TFormAvatarCrop.ZoomAt(AX, AY: Double; AFactor: Double);
var
  View: TCropView;
  PX, PY, NewScale, MX, MY: Double;
begin
  NewScale := FScale * AFactor;
  if NewScale < FBaseScale / 16 then NewScale := FBaseScale / 16;
  if NewScale > FBaseScale * 16 then NewScale := FBaseScale * 16;
  View := CurrentView(FScale);
  ViewToImage(View, AX, AY, FBox.Width, FBox.Height, PX, PY);
  { vetor (sem translacao) do centro da vista ate o cursor, ja girado/espelhado }
  MX := (PX - FCX) * FScale;
  MY := (PY - FCY) * FScale;
  FScale := NewScale;
  FCX := PX - MX / FScale;
  FCY := PY - MY / FScale;
  SyncControls;
  FBox.Invalidate;
end;

procedure TFormAvatarCrop.BoxPaint(Sender: TObject);
var
  BW, BH, X, Y, Shade: Integer;
  View: TCropView;
  U, V: Double;
  R, G, B, A: Byte;
  Row: PByte;
  Px: PByte;
  Inside, Fast: Boolean;
  Bg, OutR, OutG, OutB: Integer;
begin
  BW := FBox.Width;
  BH := FBox.Height;
  if (BW <= 0) or (BH <= 0) then
    Exit;
  if (FBuffer.Width <> BW) or (FBuffer.Height <> BH) then
    FBuffer.SetSize(BW, BH);
  View := CurrentView(FScale);
  Fast := FDragging or FRotating;
  for Y := 0 to BH - 1 do
  begin
    Row := FBuffer.ScanLine[Y];
    for X := 0 to BW - 1 do
    begin
      ViewToImage(View, X + 0.5, Y + 0.5, BW, BH, U, V);
      SampleImage(FImg, U, V, not Fast, R, G, B, A);
      { fundo xadrez para as areas transparentes }
      if (((X shr 3) + (Y shr 3)) and 1) = 0 then
        Bg := 96
      else
        Bg := 128;
      OutR := (R * A + Bg * (255 - A)) div 255;
      OutG := (G * A + Bg * (255 - A)) div 255;
      OutB := (B * A + Bg * (255 - A)) div 255;
      Inside := (X >= FFrame.Left) and (X < FFrame.Right) and
        (Y >= FFrame.Top) and (Y < FFrame.Bottom);
      if not Inside then
      begin
        OutR := OutR * 40 div 100;
        OutG := OutG * 40 div 100;
        OutB := OutB * 40 div 100;
      end;
      Px := PByte(NativeUInt(Row) + NativeUInt(X) * 4);
      Px^ := Byte(OutB);
      PByte(NativeUInt(Px) + 1)^ := Byte(OutG);
      PByte(NativeUInt(Px) + 2)^ := Byte(OutR);
      PByte(NativeUInt(Px) + 3)^ := 255;
    end;
  end;
  FBox.Canvas.Draw(0, 0, FBuffer);

  { moldura e cantos }
  FBox.Canvas.Pen.Color := clWhite;
  FBox.Canvas.Pen.Width := 1;
  FBox.Canvas.Brush.Style := bsClear;
  FBox.Canvas.Rectangle(FFrame.Left, FFrame.Top, FFrame.Right, FFrame.Bottom);
  FBox.Canvas.Pen.Width := 3;
  Shade := 18;
  FBox.Canvas.MoveTo(FFrame.Left, FFrame.Top + Shade);
  FBox.Canvas.LineTo(FFrame.Left, FFrame.Top);
  FBox.Canvas.LineTo(FFrame.Left + Shade, FFrame.Top);
  FBox.Canvas.MoveTo(FFrame.Right - Shade, FFrame.Top);
  FBox.Canvas.LineTo(FFrame.Right - 1, FFrame.Top);
  FBox.Canvas.LineTo(FFrame.Right - 1, FFrame.Top + Shade);
  FBox.Canvas.MoveTo(FFrame.Left, FFrame.Bottom - Shade);
  FBox.Canvas.LineTo(FFrame.Left, FFrame.Bottom - 1);
  FBox.Canvas.LineTo(FFrame.Left + Shade, FFrame.Bottom - 1);
  FBox.Canvas.MoveTo(FFrame.Right - Shade, FFrame.Bottom - 1);
  FBox.Canvas.LineTo(FFrame.Right - 1, FFrame.Bottom - 1);
  FBox.Canvas.LineTo(FFrame.Right - 1, FFrame.Bottom - Shade);
end;

procedure TFormAvatarCrop.BoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FLastX := X;
  FLastY := Y;
  if Button = mbLeft then
    FDragging := True
  else if Button = mbRight then
    FRotating := True;
end;

procedure TFormAvatarCrop.BoxMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  View: TCropView;
  DX, DY, MX, MY: Double;
begin
  if FDragging then
  begin
    { a imagem acompanha o mouse: o centro da vista anda no sentido oposto,
      no espaco da imagem (giro e espelhamento aplicados ao deslocamento) }
    View := CurrentView(FScale);
    DX := X - FLastX;
    DY := Y - FLastY;
    MX := DX * View.CosA + DY * View.SinA;
    MY := -DX * View.SinA + DY * View.CosA;
    if FFlipH then MX := -MX;
    if FFlipV then MY := -MY;
    FCX := FCX - MX / FScale;
    FCY := FCY - MY / FScale;
    FBox.Invalidate;
  end
  else if FRotating then
    SetAngle(FAngle + (X - FLastX) * 0.25);
  FLastX := X;
  FLastY := Y;
end;

procedure TFormAvatarCrop.BoxMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDragging := False;
  FRotating := False;
  FBox.Invalidate; { redesenha com amostragem de boa qualidade }
end;

procedure TFormAvatarCrop.FormWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  P: TPoint;
begin
  Handled := True;
  if ssShift in Shift then
  begin
    if WheelDelta > 0 then SetAngle(FAngle + 1) else SetAngle(FAngle - 1);
    Exit;
  end;
  P := FBox.ScreenToClient(MousePos);
  if WheelDelta > 0 then
    ZoomAt(P.X, P.Y, 1.1)
  else
    ZoomAt(P.X, P.Y, 1 / 1.1);
end;

procedure TFormAvatarCrop.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    ModalResult := mrCancel;
end;

procedure TFormAvatarCrop.FormResized(Sender: TObject);
begin
  if FBox = nil then
    Exit;
  UpdateFrame;
  FBox.Invalidate;
end;

{ So agora o tamanho real da area da imagem e conhecido: recalcula a moldura e
  o zoom inicial (cobrir a moldura). }
procedure TFormAvatarCrop.FormShown(Sender: TObject);
begin
  UpdateFrame;
  ResetView;
end;

procedure TFormAvatarCrop.ZoomChanged(Sender: TObject);
var
  NewScale: Double;
begin
  if FUpdating then
    Exit;
  NewScale := FBaseScale * Power(2, (FTbZoom.Position - 100) / 25);
  FScale := NewScale;
  FBox.Invalidate;
end;

procedure TFormAvatarCrop.AngleChanged(Sender: TObject);
begin
  if FUpdating then
    Exit;
  SetAngle(FTbAngle.Position);
end;

procedure TFormAvatarCrop.RotLClick(Sender: TObject);
begin
  SetAngle(FAngle - 90);
end;

procedure TFormAvatarCrop.RotRClick(Sender: TObject);
begin
  SetAngle(FAngle + 90);
end;

procedure TFormAvatarCrop.FlipHClick(Sender: TObject);
begin
  FFlipH := not FFlipH;
  FBox.Invalidate;
end;

procedure TFormAvatarCrop.FlipVClick(Sender: TObject);
begin
  FFlipV := not FFlipV;
  FBox.Invalidate;
end;

procedure TFormAvatarCrop.ResetClick(Sender: TObject);
begin
  ResetView;
end;

{ Grava o que esta dentro da moldura: largura do recorte em pixels da imagem,
  limitada a 440..2048, na proporcao do avatar. Fora da imagem fica transparente
  quando a origem tem alfa e branco quando e opaca. }
procedure TFormAvatarCrop.SaveCrop(const AOutputPng: string);
var
  FrameW, SrcWidth, ExportScale: Double;
  OW, OH, X, Y: Integer;
  View: TCropView;
  U, V: Double;
  R, G, B, A: Byte;
  Png: TPngImage;
  Row, AlphaRow: PByte;
begin
  FrameW := FFrame.Right - FFrame.Left;
  SrcWidth := FrameW / FScale;
  OW := Round(SrcWidth);
  if OW < AVATAR_ASPECT_W then OW := AVATAR_ASPECT_W;
  if OW > 2048 then OW := 2048;
  OH := Round(OW * AVATAR_ASPECT_H / AVATAR_ASPECT_W);
  ExportScale := OW / SrcWidth;
  View := CurrentView(ExportScale);
  { o centro da vista de saida e o centro da moldura, que e o centro da vista }
  Png := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, OW, OH);
  try
    for Y := 0 to OH - 1 do
    begin
      Row := PByte(Png.Scanline[Y]);
      AlphaRow := PByte(Png.AlphaScanline[Y]);
      for X := 0 to OW - 1 do
      begin
        ViewToImage(View, X + 0.5, Y + 0.5, OW, OH, U, V);
        SampleImage(FImg, U, V, True, R, G, B, A);
        if (A = 0) and (not FImg.HasAlpha) then
        begin
          R := 255; G := 255; B := 255; A := 255;
        end;
        { o scanline do TPngImage guarda B, G, R }
        PByte(NativeUInt(Row) + NativeUInt(X) * 3)^ := B;
        PByte(NativeUInt(Row) + NativeUInt(X) * 3 + 1)^ := G;
        PByte(NativeUInt(Row) + NativeUInt(X) * 3 + 2)^ := R;
        PByte(NativeUInt(AlphaRow) + NativeUInt(X))^ := A;
      end;
    end;
    Png.SaveToFile(AOutputPng);
  finally
    Png.Free;
  end;
end;

end.
