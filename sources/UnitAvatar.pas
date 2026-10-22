unit UnitAvatar;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.IOUtils, System.Types, System.IniFiles, System.Threading,
  UnitTranslations,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtDlgs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg;

type
  TAvatarDDSConverter = (adcTexconv, adcInternal);

  TAvatarController = record
  public
    FHost: string;
    FUser: string;
    edtName: TEdit;
    edtImage: TEdit;
    cmbConverter: TComboBox;
    chkTransparent: TCheckBox;
    chkKeepLocal: TCheckBox;
    cbImageType: TComboBox;
    btnBrowse: TButton;
    btnCreateImage: TButton;
    btnSend: TButton;
    imgPreview: TImage;
    memLog: TMemo;
    pbProgress: TProgressBar;
    lblHint: TLabel;
    CurrentLanguage: TAppLanguage;
    OpenPictureDialog: TOpenPictureDialog;
    FLastProfile: string;
    procedure AddLog(const AMsg: string);
    procedure SetStatus(const AMsg: string);
    procedure SetBusy(ABusy: Boolean);
    procedure btnBrowseClick(Sender: TObject);
    procedure btnCreateClick(Sender: TObject);
    procedure btnSendClick(Sender: TObject);
    procedure LoadPreview(const AFileName: string);
    procedure LoadSettings;
    procedure SaveSettings;
    function SelectedConverter: TAvatarDDSConverter;
  public
    procedure SetTarget(const AIP, AUser: string);
    procedure Browse;
    procedure CreateImages;
    procedure Send;
  end;

implementation

uses
  System.StrUtils, UnitFunctions, UnitAvatarCrop, UnitAvatarMask,
  IdFTP, IdFTPCommon, IdFTPList;

function AvatarProcessingText(ALanguage: TAppLanguage): string;
begin
  if ALanguage = alEnglish then
    Result := 'Image creation may take some time. Please wait while the process completes...'
  else
    Result := 'A cria' + #$00E7 + #$00E3 + 'o das imagens pode demorar. Aguarde enquanto o processo ' +
      'est' + #$00E1 + ' sendo conclu' + #$00ED + 'do...';
end;

function AvatarSentText(ALanguage: TAppLanguage): string;
begin
  if ALanguage = alEnglish then
    Result := 'Avatar sent. Restart the PS4 or log out and back in to the user.'
  else
    Result := 'Avatar enviado. Reinicie o PS4 ou fa' + #$00E7 + 'a logout/login no usu' +
      #$00E1 + 'rio.';
end;

const
  PS4_FTP_PORT = 2121;
  PS4_FTP_USER = 'anonymous';
  PS4_FTP_PASS = 'anonymous@';
  PS4_PROFILE_CACHE_DIR = '/system_data/priv/cache/profile';
  AVATAR_SETTINGS_SECTION = 'PS4Avatar';

type
  TDDSHeader = packed record
    Size: Cardinal;
    Flags: Cardinal;
    Height: Cardinal;
    Width: Cardinal;
    PitchOrLinearSize: Cardinal;
    Depth: Cardinal;
    MipMapCount: Cardinal;
    Reserved1: array[0..10] of Cardinal;
    PfSize: Cardinal;
    PfFlags: Cardinal;
    PfFourCC: Cardinal;
    PfRGBBitCount: Cardinal;
    PfRBitMask: Cardinal;
    PfGBitMask: Cardinal;
    PfBBitMask: Cardinal;
    PfABitMask: Cardinal;
    Caps: Cardinal;
    Caps2: Cardinal;
    Caps3: Cardinal;
    Caps4: Cardinal;
    Reserved2: Cardinal;
  end;

procedure MakeBitmapOpaque(ABitmap: TBitmap);
var
  X: Integer;
  Y: Integer;
  P: PByte;
begin
  ABitmap.PixelFormat := pf32bit;
  for Y := 0 to ABitmap.Height - 1 do
  begin
    P := ABitmap.ScanLine[Y];
    Inc(P, 3);
    for X := 0 to ABitmap.Width - 1 do
    begin
      P^ := $FF;
      Inc(P, 4);
    end;
  end;
end;

procedure RepaintTransparentPixels(ABitmap: TBitmap);
const
  MIN_SOURCE_ALPHA = 16;
  PASSES = 8;
var
  Pass: Integer;
  X: Integer;
  Y: Integer;
  NX: Integer;
  NY: Integer;
  DX: Integer;
  DY: Integer;
  RSum: Integer;
  GSum: Integer;
  BSum: Integer;
  Count: Integer;
  Pixel: PByte;
  Neighbor: PByte;
  Colors: TBytes;
begin
  ABitmap.PixelFormat := pf32bit;
  SetLength(Colors, ABitmap.Width * ABitmap.Height * 3);

  for Pass := 1 to PASSES do
  begin
    for Y := 0 to ABitmap.Height - 1 do
    begin
      Pixel := ABitmap.ScanLine[Y];
      for X := 0 to ABitmap.Width - 1 do
      begin
        Colors[(Y * ABitmap.Width + X) * 3] := Pixel^;
        Colors[(Y * ABitmap.Width + X) * 3 + 1] := PByte(NativeUInt(Pixel) + 1)^;
        Colors[(Y * ABitmap.Width + X) * 3 + 2] := PByte(NativeUInt(Pixel) + 2)^;
        Inc(Pixel, 4);
      end;
    end;

    for Y := 0 to ABitmap.Height - 1 do
    begin
      Pixel := ABitmap.ScanLine[Y];
      for X := 0 to ABitmap.Width - 1 do
      begin
        { So repinta pixels praticamente invisiveis (alfa < MIN_SOURCE_ALPHA):
          a cor deles e irrelevante e vira a dos vizinhos para o DDS nao
          escurecer as bordas. Repintar todo pixel com alfa < 255 apagava a
          cor propria de PNGs cujo alfa e 253/252 no miolo (cada pixel virava
          a media dos vizinhos, oito vezes: imagem toda borrada). }
        if PByte(NativeUInt(Pixel) + 3)^ < MIN_SOURCE_ALPHA then
        begin
          RSum := 0;
          GSum := 0;
          BSum := 0;
          Count := 0;
          for DY := -1 to 1 do
            for DX := -1 to 1 do
            begin
              if (DX = 0) and (DY = 0) then Continue;
              NX := X + DX;
              NY := Y + DY;
              if (NX < 0) or (NY < 0) or
                 (NX >= ABitmap.Width) or (NY >= ABitmap.Height) then Continue;
              Neighbor := ABitmap.ScanLine[NY];
              Inc(Neighbor, NX * 4);
              if PByte(NativeUInt(Neighbor) + 3)^ >= MIN_SOURCE_ALPHA then
              begin
                BSum := BSum + Colors[(NY * ABitmap.Width + NX) * 3];
                GSum := GSum + Colors[(NY * ABitmap.Width + NX) * 3 + 1];
                RSum := RSum + Colors[(NY * ABitmap.Width + NX) * 3 + 2];
                Inc(Count);
              end;
            end;
          if Count > 0 then
          begin
            Pixel^ := BSum div Count;
            PByte(NativeUInt(Pixel) + 1)^ := GSum div Count;
            PByte(NativeUInt(Pixel) + 2)^ := RSum div Count;
          end;
        end;
        Inc(Pixel, 4);
      end;
    end;
  end;
end;

function ConnectFTP(const AHost: string): TIdFTP;
begin
  Result := TIdFTP.Create(nil);
  try
    Result.Host := AHost;
    Result.Port := PS4_FTP_PORT;
    Result.Username := PS4_FTP_USER;
    Result.Password := PS4_FTP_PASS;
    Result.Passive := True;
    Result.TransferType := ftBinary;
    Result.ConnectTimeout := 8000;
    Result.ReadTimeout := 15000;
    Result.Connect;
  except
    Result.Free;
    raise;
  end;
end;

procedure ListProfiles(const AHost: string; out AProfiles: TArray<string>);
var
  FTP: TIdFTP;
  I: Integer;
begin
  SetLength(AProfiles, 0);
  FTP := ConnectFTP(AHost);
  try
    FTP.ChangeDir(PS4_PROFILE_CACHE_DIR);
    FTP.List('', True);
    for I := 0 to FTP.DirectoryListing.Count - 1 do
      if (FTP.DirectoryListing[I].ItemType = ditDirectory) and
         StartsText('0x', FTP.DirectoryListing[I].FileName) then
      begin
        SetLength(AProfiles, Length(AProfiles) + 1);
        AProfiles[High(AProfiles)] := FTP.DirectoryListing[I].FileName;
      end;
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;
end;

function JsonValue(const S: string): string;
begin
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
end;

{ Reduz um PNG RGBA de 8 bits para ADest dentro de ABitmap (pf32bit, alfa
  reto) fazendo a media da area de cada pixel de destino com a cor ponderada
  pelo alfa (alfa premultiplicado). Assim bordas e fios finos nao ganham halo
  claro/escuro e o alfa fica suave, ao contrario de StretchDraw + alfa por
  vizinho mais proximo. Fora de ADest tudo fica transparente. }
procedure ResampleRgbaPng(APng: TPngImage; ABitmap: TBitmap; const ADest: TRect);
var
  SrcW, SrcH, DstW, DstH, DX, DY, SX, SY, X0, X1, Y0, Y1, Area: Integer;
  SumA, SumR, SumG, SumB: Int64;
  A: Integer;
  Src, SrcAlpha, Dst: PByte;
  OutA: Integer;
begin
  SrcW := APng.Width;
  SrcH := APng.Height;
  DstW := ADest.Right - ADest.Left;
  DstH := ADest.Bottom - ADest.Top;
  if (SrcW <= 0) or (SrcH <= 0) or (DstW <= 0) or (DstH <= 0) then
    Exit;

  for DY := 0 to ABitmap.Height - 1 do
    FillChar(PByte(ABitmap.ScanLine[DY])^, ABitmap.Width * 4, 0);

  for DY := 0 to DstH - 1 do
  begin
    Y0 := (DY * SrcH) div DstH;
    Y1 := ((DY + 1) * SrcH) div DstH;
    if Y1 <= Y0 then
      Y1 := Y0 + 1;
    if Y1 > SrcH then
      Y1 := SrcH;
    Dst := ABitmap.ScanLine[ADest.Top + DY];
    Inc(Dst, ADest.Left * 4);
    for DX := 0 to DstW - 1 do
    begin
      X0 := (DX * SrcW) div DstW;
      X1 := ((DX + 1) * SrcW) div DstW;
      if X1 <= X0 then
        X1 := X0 + 1;
      if X1 > SrcW then
        X1 := SrcW;
      SumA := 0;
      SumR := 0;
      SumG := 0;
      SumB := 0;
      for SY := Y0 to Y1 - 1 do
      begin
        { o scanline do TPngImage guarda B, G, R; o alfa fica em outro vetor }
        Src := PByte(APng.Scanline[SY]);
        SrcAlpha := PByte(APng.AlphaScanline[SY]);
        for SX := X0 to X1 - 1 do
        begin
          A := PByte(NativeUInt(SrcAlpha) + NativeUInt(SX))^;
          SumA := SumA + A;
          SumB := SumB + Int64(PByte(NativeUInt(Src) + NativeUInt(SX) * 3)^) * A;
          SumG := SumG + Int64(PByte(NativeUInt(Src) + NativeUInt(SX) * 3 + 1)^) * A;
          SumR := SumR + Int64(PByte(NativeUInt(Src) + NativeUInt(SX) * 3 + 2)^) * A;
        end;
      end;
      Area := (X1 - X0) * (Y1 - Y0);
      OutA := Integer((SumA + Area div 2) div Area);
      { Ferramentas de recorte deixam o miolo com alfa 252/253; tratar como
        opaco evita um avatar levemente translucido. }
      if OutA >= 248 then
        OutA := 255;
      if SumA > 0 then
      begin
        Dst^ := Byte((SumB + SumA div 2) div SumA);
        PByte(NativeUInt(Dst) + 1)^ := Byte((SumG + SumA div 2) div SumA);
        PByte(NativeUInt(Dst) + 2)^ := Byte((SumR + SumA div 2) div SumA);
      end;
      PByte(NativeUInt(Dst) + 3)^ := Byte(OutA);
      Inc(Dst, 4);
    end;
  end;
end;

function CreateAvatarBitmap(const AFileName: string; AWidth, AHeight: Integer;
  APreserveTransparency: Boolean): TBitmap;
var
  Pic: TPicture;
  Png: TPngImage;
  Scale: Double;
  SrcW: Integer;
  SrcH: Integer;
  DstW: Integer;
  DstH: Integer;
  DstX: Integer;
  DstY: Integer;
  X: Integer;
  Y: Integer;
  SrcX: Integer;
  SrcY: Integer;
  AlphaLine: PByteArray;
  AlphaApplied: Boolean;
  Pixel: PByte;
  R: TRect;
  OldStretchMode: Integer;
begin
  Result := TBitmap.Create;
  Result.SetSize(AWidth, AHeight);
  Result.PixelFormat := pf32bit;
  if APreserveTransparency then
    Result.Canvas.Brush.Color := clWhite
  else
    Result.Canvas.Brush.Color := clBlack;
  Result.Canvas.FillRect(Rect(0, 0, AWidth, AHeight));

  Pic := TPicture.Create;
  try
    Pic.LoadFromFile(AFileName);
    SrcW := Pic.Width;
    SrcH := Pic.Height;
    if (SrcW <= 0) or (SrcH <= 0) then
      raise Exception.Create('Imagem invalida.');

    Scale := AWidth / SrcW;
    if (SrcH * Scale) > AHeight then
      Scale := AHeight / SrcH;

    DstW := Round(SrcW * Scale);
    DstH := Round(SrcH * Scale);
    DstX := (AWidth - DstW) div 2;
    DstY := (AHeight - DstH) div 2;
    R := Rect(DstX, DstY, DstX + DstW, DstY + DstH);
    OldStretchMode := SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    try
      SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
      Result.Canvas.StretchDraw(R, Pic.Graphic);
    finally
      SetStretchBltMode(Result.Canvas.Handle, OldStretchMode);
    end;
    AlphaApplied := False;
    if not APreserveTransparency then
      MakeBitmapOpaque(Result)
    else if SameText(ExtractFileExt(AFileName), '.png') then
    begin
      Png := TPngImage.Create;
      try
        Png.LoadFromFile(AFileName);
        if (Png.Header.ColorType = COLOR_RGBALPHA) and (Png.Header.BitDepth = 8) then
        begin
          { PNG RGBA comum (inclusive o gerado pela remocao de fundo):
            reducao por media de area, sem halo. }
          ResampleRgbaPng(Png, Result, R);
          AlphaApplied := True;
        end
        else if Png.TransparencyMode = ptmPartial then
        begin
          AlphaApplied := True;
          for Y := 0 to AHeight - 1 do
          begin
            Pixel := Result.ScanLine[Y];
            Inc(Pixel, 3);
            for X := 0 to AWidth - 1 do
            begin
              if (X < DstX) or (X >= DstX + DstW) or
                 (Y < DstY) or (Y >= DstY + DstH) then
              begin
                Pixel^ := 0;
              end
              else
              begin
                SrcX := MulDiv(X - DstX, SrcW, DstW);
                SrcY := MulDiv(Y - DstY, SrcH, DstH);
                if SrcX < 0 then SrcX := 0;
                if SrcY < 0 then SrcY := 0;
                if SrcX >= SrcW then SrcX := SrcW - 1;
                if SrcY >= SrcH then SrcY := SrcH - 1;
                AlphaLine := Png.AlphaScanline[SrcY];
                if Assigned(AlphaLine) then
                  Pixel^ := AlphaLine[SrcX]
                else
                  Pixel^ := $FF;
              end;
              Inc(Pixel, 4);
            end;
          end;
        end;
      finally
        Png.Free;
      end;
      if AlphaApplied then
      begin
        RepaintTransparentPixels(Result);
        Result.AlphaFormat := afDefined
      end
      else
        MakeBitmapOpaque(Result);
    end
    else
      MakeBitmapOpaque(Result);
  finally
    Pic.Free;
  end;
end;

procedure SaveBitmapAsPng(const ABitmap: TBitmap; const AFileName: string);
var
  Png: TPngImage;
  Bmp: TBitmap;
  X: Integer;
  Y: Integer;
  Src: PByte;
  Dst: PByte;
  Alpha: PByteArray;
begin
  Bmp := TBitmap.Create;
  Png := TPngImage.Create;
  try
    Bmp.Assign(ABitmap);
    Bmp.PixelFormat := pf32bit;
    Png.CreateBlank(COLOR_RGBALPHA, 8, Bmp.Width, Bmp.Height);
    for Y := 0 to Bmp.Height - 1 do
    begin
      Src := Bmp.ScanLine[Y];
      Dst := Png.Scanline[Y];
      Alpha := Png.AlphaScanline[Y];
      for X := 0 to Bmp.Width - 1 do
      begin
        Dst^ := Src^; Inc(Dst);
        Dst^ := PByte(NativeUInt(Src) + 1)^; Inc(Dst);
        Dst^ := PByte(NativeUInt(Src) + 2)^; Inc(Dst);
        Alpha[X] := PByte(NativeUInt(Src) + 3)^;
        Inc(Src, 4);
      end;
    end;
    Png.SaveToFile(AFileName);
  finally
    Png.Free;
    Bmp.Free;
  end;
end;

function DDSFourCC(const S: AnsiString): Cardinal;
begin
  Result := Ord(S[1]) or (Ord(S[2]) shl 8) or (Ord(S[3]) shl 16) or (Ord(S[4]) shl 24);
end;

function DDSColorTo565(R, G, B: Byte): Word;
begin
  Result := ((R shr 3) shl 11) or ((G shr 2) shl 5) or (B shr 3);
end;

procedure DDSColorFrom565(C: Word; out R, G, B: Integer);
begin
  R := ((C shr 11) and $1F) * 255 div 31;
  G := ((C shr 5) and $3F) * 255 div 63;
  B := (C and $1F) * 255 div 31;
end;

function DDSColorDistance(R1, G1, B1, R2, G2, B2: Integer): Integer;
begin
  Result := Sqr(R1 - R2) + Sqr(G1 - G2) + Sqr(B1 - B2);
end;

procedure DDSWriteWord(AStream: TStream; AValue: Word);
begin
  AStream.WriteBuffer(AValue, SizeOf(AValue));
end;

procedure DDSWriteDWord(AStream: TStream; AValue: Cardinal);
begin
  AStream.WriteBuffer(AValue, SizeOf(AValue));
end;

procedure SaveBitmapAsDDS(const ABitmap: TBitmap; const AFileName: string;
  APreserveTransparency: Boolean);
const
  DDS_MAGIC = $20534444;
  DDSD_CAPS = $00000001;
  DDSD_HEIGHT = $00000002;
  DDSD_WIDTH = $00000004;
  DDSD_LINEARSIZE = $00080000;
  DDSD_PIXELFORMAT = $00001000;
  DDPF_FOURCC = $00000004;
  DDSCAPS_TEXTURE = $00001000;
var
  Header: TDDSHeader;
  FS: TFileStream;
  Bmp: TBitmap;
  Magic: Cardinal;
  X: Integer;
  Y: Integer;
  BX: Integer;
  BY: Integer;
  I: Integer;
  PX: Integer;
  PY: Integer;
  A: Byte;
  MinA: Byte;
  MaxA: Byte;
  AlphaValues: array[0..15] of Byte;
  AlphaPal: array[0..7] of Integer;
  AlphaIdx: UInt64;
  AlphaBest: Integer;
  AlphaBestD: Integer;
  BlockR: array[0..15] of Byte;
  BlockG: array[0..15] of Byte;
  BlockB: array[0..15] of Byte;
  BlockLum: array[0..15] of Integer;
  R: Byte;
  G: Byte;
  B: Byte;
  MinLum: Integer;
  MaxLum: Integer;
  Lum: Integer;
  MinR: Byte;
  MinG: Byte;
  MinB: Byte;
  MaxR: Byte;
  MaxG: Byte;
  MaxB: Byte;
  C0: Word;
  C1: Word;
  PalR: array[0..3] of Integer;
  PalG: array[0..3] of Integer;
  PalB: array[0..3] of Integer;
  Indices: Cardinal;
  Best: Integer;
  BestD: Integer;
  BestErr: Int64;
  Err: Int64;
  TestD: Integer;
  AlphaWeight: Integer;
  ColorWeight: Integer;
  TestC0: Word;
  TestC1: Word;
  TmpC: Word;
  TestPalR: array[0..3] of Integer;
  TestPalG: array[0..3] of Integer;
  TestPalB: array[0..3] of Integer;
  J: Integer;
  K: Integer;
  D: Integer;
  Pixel: PByte;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.Assign(ABitmap);
    Bmp.PixelFormat := pf32bit;

    FillChar(Header, SizeOf(Header), 0);
    Header.Size := 124;
    Header.Flags := DDSD_CAPS or DDSD_HEIGHT or DDSD_WIDTH or DDSD_LINEARSIZE or DDSD_PIXELFORMAT;
    Header.Height := Bmp.Height;
    Header.Width := Bmp.Width;
    if APreserveTransparency then
      Header.PitchOrLinearSize := ((Bmp.Width + 3) div 4) * ((Bmp.Height + 3) div 4) * 16
    else
      Header.PitchOrLinearSize := ((Bmp.Width + 3) div 4) * ((Bmp.Height + 3) div 4) * 8;
    Header.PfSize := 32;
    Header.PfFlags := DDPF_FOURCC;
    if APreserveTransparency then
      Header.PfFourCC := DDSFourCC('DXT5')
    else
      Header.PfFourCC := DDSFourCC('DXT1');
    Header.Caps := DDSCAPS_TEXTURE;

    FS := TFileStream.Create(AFileName, fmCreate);
    try
      Magic := DDS_MAGIC;
      FS.WriteBuffer(Magic, SizeOf(Magic));
      FS.WriteBuffer(Header, SizeOf(Header));

      for BY := 0 to (Bmp.Height div 4) - 1 do
      begin
        for BX := 0 to (Bmp.Width div 4) - 1 do
        begin
          MinLum := MaxInt;
          MaxLum := -1;
          MinA := 255;
          MaxA := 0;
          MinR := 0; MinG := 0; MinB := 0;
          MaxR := 255; MaxG := 255; MaxB := 255;

          for Y := 0 to 3 do
            for X := 0 to 3 do
            begin
              PX := BX * 4 + X;
              PY := BY * 4 + Y;
              Pixel := Bmp.ScanLine[PY];
              Inc(Pixel, PX * 4);
              B := Pixel^; Inc(Pixel);
              G := Pixel^; Inc(Pixel);
              R := Pixel^; Inc(Pixel);
              A := Pixel^;
              AlphaValues[Y * 4 + X] := A;
              BlockR[Y * 4 + X] := R;
              BlockG[Y * 4 + X] := G;
              BlockB[Y * 4 + X] := B;
              if A < MinA then MinA := A;
              if A > MaxA then MaxA := A;
              Lum := R * 299 + G * 587 + B * 114;
              BlockLum[Y * 4 + X] := Lum;
              if Lum < MinLum then
              begin
                MinLum := Lum;
                MinR := R; MinG := G; MinB := B;
              end;
              if Lum > MaxLum then
              begin
                MaxLum := Lum;
                MaxR := R; MaxG := G; MaxB := B;
              end;
            end;

          if APreserveTransparency then
          begin
            AlphaPal[0] := MaxA;
            AlphaPal[1] := MinA;
            if MaxA > MinA then
            begin
              AlphaPal[2] := (6 * MaxA + 1 * MinA) div 7;
              AlphaPal[3] := (5 * MaxA + 2 * MinA) div 7;
              AlphaPal[4] := (4 * MaxA + 3 * MinA) div 7;
              AlphaPal[5] := (3 * MaxA + 4 * MinA) div 7;
              AlphaPal[6] := (2 * MaxA + 5 * MinA) div 7;
              AlphaPal[7] := (1 * MaxA + 6 * MinA) div 7;
            end
            else
            begin
              AlphaPal[2] := (4 * MaxA + 1 * MinA) div 5;
              AlphaPal[3] := (3 * MaxA + 2 * MinA) div 5;
              AlphaPal[4] := (2 * MaxA + 3 * MinA) div 5;
              AlphaPal[5] := (1 * MaxA + 4 * MinA) div 5;
              AlphaPal[6] := 0;
              AlphaPal[7] := 255;
            end;

            AlphaIdx := 0;
            for I := 0 to 15 do
            begin
              AlphaBest := 0;
              AlphaBestD := MaxInt;
              for D := 0 to 7 do
                if Abs(Integer(AlphaValues[I]) - AlphaPal[D]) < AlphaBestD then
                begin
                  AlphaBest := D;
                  AlphaBestD := Abs(Integer(AlphaValues[I]) - AlphaPal[D]);
                end;
              AlphaIdx := AlphaIdx or (UInt64(AlphaBest) shl (I * 3));
            end;

            FS.WriteBuffer(MaxA, SizeOf(MaxA));
            FS.WriteBuffer(MinA, SizeOf(MinA));
            for I := 0 to 5 do
            begin
              A := Byte((AlphaIdx shr (I * 8)) and $FF);
              FS.WriteBuffer(A, SizeOf(A));
            end;
          end;

          C0 := DDSColorTo565(MaxR, MaxG, MaxB);
          C1 := DDSColorTo565(MinR, MinG, MinB);
          BestErr := High(Int64);

          for J := 0 to 15 do
            for K := 0 to 15 do
            begin
              TestC0 := DDSColorTo565(BlockR[J], BlockG[J], BlockB[J]);
              TestC1 := DDSColorTo565(BlockR[K], BlockG[K], BlockB[K]);
              if TestC0 = TestC1 then Continue;
              if TestC0 < TestC1 then
              begin
                TmpC := TestC0;
                TestC0 := TestC1;
                TestC1 := TmpC;
              end;

              DDSColorFrom565(TestC0, TestPalR[0], TestPalG[0], TestPalB[0]);
              DDSColorFrom565(TestC1, TestPalR[1], TestPalG[1], TestPalB[1]);
              TestPalR[2] := (2 * TestPalR[0] + TestPalR[1]) div 3;
              TestPalG[2] := (2 * TestPalG[0] + TestPalG[1]) div 3;
              TestPalB[2] := (2 * TestPalB[0] + TestPalB[1]) div 3;
              TestPalR[3] := (TestPalR[0] + 2 * TestPalR[1]) div 3;
              TestPalG[3] := (TestPalG[0] + 2 * TestPalG[1]) div 3;
              TestPalB[3] := (TestPalB[0] + 2 * TestPalB[1]) div 3;

              Err := 0;
              for I := 0 to 15 do
              begin
                if APreserveTransparency then
                  AlphaWeight := AlphaValues[I]
                else
                  AlphaWeight := 255;
                if AlphaWeight = 0 then Continue;
                if BlockLum[I] > 160000 then
                  ColorWeight := 4
                else if BlockLum[I] > 96000 then
                  ColorWeight := 2
                else
                  ColorWeight := 1;
                BestD := MaxInt;
                for D := 0 to 3 do
                begin
                  TestD := DDSColorDistance(BlockR[I], BlockG[I], BlockB[I],
                    TestPalR[D], TestPalG[D], TestPalB[D]);
                  if TestD < BestD then
                  begin
                    BestD := TestD;
                  end;
                end;
                Err := Err + Int64(BestD) * AlphaWeight * ColorWeight;
              end;

              if Err < BestErr then
              begin
                BestErr := Err;
                C0 := TestC0;
                C1 := TestC1;
              end;
            end;

          if BestErr = High(Int64) then
          begin
            C0 := DDSColorTo565(MaxR, MaxG, MaxB);
            C1 := DDSColorTo565(MinR, MinG, MinB);
            if C0 <= C1 then
            begin
              C0 := DDSColorTo565(255, 255, 255);
              C1 := DDSColorTo565(0, 0, 0);
            end;
          end;

          DDSColorFrom565(C0, PalR[0], PalG[0], PalB[0]);
          DDSColorFrom565(C1, PalR[1], PalG[1], PalB[1]);
          PalR[2] := (2 * PalR[0] + PalR[1]) div 3;
          PalG[2] := (2 * PalG[0] + PalG[1]) div 3;
          PalB[2] := (2 * PalB[0] + PalB[1]) div 3;
          PalR[3] := (PalR[0] + 2 * PalR[1]) div 3;
          PalG[3] := (PalG[0] + 2 * PalG[1]) div 3;
          PalB[3] := (PalB[0] + 2 * PalB[1]) div 3;

          Indices := 0;
          I := 0;
          for Y := 0 to 3 do
            for X := 0 to 3 do
            begin
              PX := BX * 4 + X;
              PY := BY * 4 + Y;
              Pixel := Bmp.ScanLine[PY];
              Inc(Pixel, PX * 4);
              B := Pixel^; Inc(Pixel);
              G := Pixel^; Inc(Pixel);
              R := Pixel^;
              Best := 0;
              BestD := MaxInt;
              for D := 0 to 3 do
              begin
                TestD := DDSColorDistance(R, G, B, PalR[D], PalG[D], PalB[D]);
                if TestD < BestD then
                begin
                  Best := D;
                  BestD := TestD;
                end;
              end;
              Indices := Indices or (Cardinal(Best) shl (I * 2));
              Inc(I);
            end;

          DDSWriteWord(FS, C0);
          DDSWriteWord(FS, C1);
          DDSWriteDWord(FS, Indices);
        end;
      end;
    finally
      FS.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

function CoreDir: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)) + 'core');
  if not DirectoryExists(Result) then
    ForceDirectories(Result);
end;

function TexconvFileName: string;
begin
  Result := TPath.Combine(CoreDir, 'texconv.exe');
  if not FileExists(Result) then
    Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'texconv.exe');
end;

function RunProcessAndWait(const ACommandLine: string): Boolean;
var
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  Cmd: string;
  ExitCode: Cardinal;
begin
  Result := False;
  FillChar(StartupInfo, SizeOf(StartupInfo), 0);
  StartupInfo.cb := SizeOf(StartupInfo);
  StartupInfo.dwFlags := STARTF_USESHOWWINDOW;
  StartupInfo.wShowWindow := SW_HIDE;
  FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
  Cmd := ACommandLine;
  UniqueString(Cmd);
  if CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW,
    nil, nil, StartupInfo, ProcessInfo) then
  begin
    try
      WaitForSingleObject(ProcessInfo.hProcess, INFINITE);
      if GetExitCodeProcess(ProcessInfo.hProcess, ExitCode) then
        Result := ExitCode = 0;
    finally
      CloseHandle(ProcessInfo.hThread);
      CloseHandle(ProcessInfo.hProcess);
    end;
  end;
end;

function SaveBitmapAsDDSWithTexconv(const ABitmap: TBitmap; const AFileName: string;
  APreserveTransparency: Boolean): Boolean;
var
  Texconv: string;
  TempDir: string;
  TempPng: string;
  TempDDS: string;
  FormatName: string;
  Cmd: string;
begin
  Result := False;
  Texconv := TexconvFileName;
  if not FileExists(Texconv) then Exit;

  TempDir := TPath.Combine(TPath.GetTempPath, 'PS4PKGDownloaderAvatarTexconv');
  ForceDirectories(TempDir);
  TempPng := TPath.Combine(TempDir, TPath.GetFileNameWithoutExtension(AFileName) + '.png');
  TempDDS := TPath.ChangeExtension(TempPng, '.dds');
  if FileExists(TempDDS) then
    System.SysUtils.DeleteFile(TempDDS);

  SaveBitmapAsPng(ABitmap, TempPng);
  if APreserveTransparency then
    FormatName := 'BC3_UNORM'
  else
    FormatName := 'BC1_UNORM';

  Cmd := '"' + Texconv + '" -nologo -y -m 1 -f ' + FormatName +
    ' -bc uq -o "' + TempDir + '" "' + TempPng + '"';
  Result := RunProcessAndWait(Cmd) and FileExists(TempDDS);
  if Result then
  begin
    if FileExists(AFileName) then
      System.SysUtils.DeleteFile(AFileName);
    TFile.Move(TempDDS, AFileName);
  end;
end;

procedure SaveAvatarDDS(const ABitmap: TBitmap; const AFileName: string;
  APreserveTransparency: Boolean; AConverter: TAvatarDDSConverter);
begin
  if AConverter = adcTexconv then
  begin
    if not SaveBitmapAsDDSWithTexconv(ABitmap, AFileName, APreserveTransparency) then
      raise Exception.Create('Falha ao converter DDS com texconv.exe. Verifique se core\texconv.exe existe.');
  end
  else
  begin
    SaveBitmapAsDDS(ABitmap, AFileName, APreserveTransparency);
  end;
end;

procedure BuildAvatarFiles(const AImageFile, AOutputDir, AOnlineName: string;
  APreserveTransparency: Boolean; AConverter: TAvatarDDSConverter;
  const AProgress: TProc<Integer, string> = nil; APngOnly: Boolean = False);
var
  Bmp: TBitmap;
  Name: string;
begin
  ForceDirectories(AOutputDir);
  Bmp := CreateAvatarBitmap(AImageFile, 440, 400, APreserveTransparency);
  try SaveBitmapAsPng(Bmp, TPath.Combine(AOutputDir, 'avatar.png'));
  finally Bmp.Free; end;
  if Assigned(AProgress) then AProgress(1, 'avatar.png');
  { "Criar imagem" gera so o avatar.png; DDS e online.json ficam para o envio. }
  if APngOnly then
    Exit;
  Bmp := CreateAvatarBitmap(AImageFile, 440, 440, APreserveTransparency);
  try SaveAvatarDDS(Bmp, TPath.Combine(AOutputDir, 'avatar440.dds'), APreserveTransparency, AConverter);
  finally Bmp.Free; end;
  if Assigned(AProgress) then AProgress(2, 'avatar440.dds');
  Bmp := CreateAvatarBitmap(AImageFile, 260, 260, APreserveTransparency);
  try SaveAvatarDDS(Bmp, TPath.Combine(AOutputDir, 'avatar260.dds'), APreserveTransparency, AConverter);
  finally Bmp.Free; end;
  if Assigned(AProgress) then AProgress(3, 'avatar260.dds');
  Bmp := CreateAvatarBitmap(AImageFile, 128, 128, APreserveTransparency);
  try SaveAvatarDDS(Bmp, TPath.Combine(AOutputDir, 'avatar128.dds'), APreserveTransparency, AConverter);
  finally Bmp.Free; end;
  if Assigned(AProgress) then AProgress(4, 'avatar128.dds');
  Bmp := CreateAvatarBitmap(AImageFile, 64, 64, APreserveTransparency);
  try SaveAvatarDDS(Bmp, TPath.Combine(AOutputDir, 'avatar64.dds'), APreserveTransparency, AConverter);
  finally Bmp.Free; end;
  if Assigned(AProgress) then AProgress(5, 'avatar64.dds');
  Name := Trim(AOnlineName);
  if Name = '' then Name := 'User';
  TFile.WriteAllText(TPath.Combine(AOutputDir, 'online.json'),
    '{"onlineId":"' + JsonValue(Name) + '","firstName":"' + JsonValue(Name) + '"}', TEncoding.UTF8);
  if Assigned(AProgress) then AProgress(6, 'online.json');
end;

{ Mapeia o indice do cbImageType (0 = Figuras, 1 = Rostos) para o modo de
  remocao de fundo. }
function ImageTypeToMode(AImageTypeIndex: Integer): TBgMode;
begin
  { cbImageType: 0 = Figuras, 1 = Rostos }
  if AImageTypeIndex = 1 then
    Result := bmHumanFace
  else
    Result := bmFigure;
end;

function PrepareAvatarSourceImage(const AImageFile, AOutputDir: string;
  ATransparent: Boolean; AMode: TBgMode): string;
const
  { PNG que ja tem pelo menos 1% de pixels transparentes dispensa a remocao. }
  ALREADY_TRANSPARENT_SHARE = 0.01;
var
  ErrorMessage: string;
begin
  Result := AImageFile;
  if not ATransparent then
    Exit;
  if PngTransparencyShare(AImageFile) >= ALREADY_TRANSPARENT_SHARE then
    Exit;
  { O PNG sem fundo e so um intermediario: fica na pasta temporaria e e
    apagado depois (DeleteAvatarTempSource), nao na pasta do avatar. }
  Result := TPath.Combine(TPath.GetTempPath,
    'ps4tools_sem_fundo_' + IntToStr(GetCurrentProcessId) + '_' +
    IntToStr(GetTickCount) + '.png');
  if not RemoveImageBackground(AImageFile, Result, AMode, ErrorMessage) then
    raise Exception.Create(ErrorMessage);
end;

{ Se a proporcao da imagem nao e a do avatar, abre a janela de enquadramento e
  grava o recorte numa PNG temporaria (ACroppedFile). Devolve False se o usuario
  cancelar (a operacao deve parar). ACroppedFile fica vazio quando nao ha recorte;
  quem chamou apaga o arquivo com DeleteAvatarTempSource. }
function CropAvatarSourceIfNeeded(const AImageFile: string;
  ALanguage: TAppLanguage; out ACroppedFile: string): Boolean;
begin
  ACroppedFile := '';
  Result := True;
  try
    if not AvatarNeedsCrop(AImageFile) then
      Exit;
    ACroppedFile := TPath.Combine(TPath.GetTempPath,
      'ps4tools_recorte_' + IntToStr(GetCurrentProcessId) + '_' +
      IntToStr(GetTickCount) + '.png');
    Result := ShowAvatarCropDialog(AImageFile, ACroppedFile, ALanguage);
    if not Result then
      ACroppedFile := '';
  except
    on E: Exception do
    begin
      ACroppedFile := '';
      Result := False;
      ShowMessage('Falha ao abrir o enquadramento da imagem: ' + E.Message);
    end;
  end;
end;

{ Opcao "Manual" do cbImageType: abre o editor de mascara sobre a imagem (ja
  enquadrada, se for o caso) e grava o resultado numa PNG temporaria. Devolve
  False se o usuario cancelar. AEditedFile fica vazio quando nao se aplica. }
function EditAvatarMaskIfNeeded(const AImageFile: string; ATransparent: Boolean;
  AImageTypeIndex: Integer; ALanguage: TAppLanguage;
  out AEditedFile: string): Boolean;
begin
  AEditedFile := '';
  Result := True;
  if (not ATransparent) or (AImageTypeIndex <> 2) then
    Exit;
  try
    AEditedFile := TPath.Combine(TPath.GetTempPath,
      'ps4tools_manual_' + IntToStr(GetCurrentProcessId) + '_' +
      IntToStr(GetTickCount) + '.png');
    Result := ShowMaskEditor(AImageFile, AEditedFile, ALanguage);
    if not Result then
      AEditedFile := '';
  except
    on E: Exception do
    begin
      AEditedFile := '';
      Result := False;
      ShowMessage('Falha ao abrir o editor de fundo: ' + E.Message);
    end;
  end;
end;

procedure DeleteAvatarTempSource(const ASourceImage, AOriginalImage: string);
begin
  if SameText(ASourceImage, AOriginalImage) then
    Exit;
  try
    if TFile.Exists(ASourceImage) then
      TFile.Delete(ASourceImage);
  except
  end;
end;

procedure UploadAvatarFiles(const AHost, AProfile, ALocalDir: string);
const
  FILES: array[0..5] of string = (
    'avatar.png', 'avatar64.dds', 'avatar128.dds', 'avatar260.dds',
    'avatar440.dds', 'online.json'
  );
var
  FTP: TIdFTP;
  RemoteDir: string;
  FileName: string;
begin
  FTP := ConnectFTP(AHost);
  try
    RemoteDir := PS4_PROFILE_CACHE_DIR + '/' + AProfile;
    if not StartsText('0x', AProfile) then
      RemoteDir := PS4_PROFILE_CACHE_DIR + '/0x' + UpperCase(AProfile);
    FTP.ChangeDir(RemoteDir);
    for FileName in FILES do
      FTP.Put(TPath.Combine(ALocalDir, FileName), FileName);
  finally
    if FTP.Connected then FTP.Disconnect;
    FTP.Free;
  end;
end;

function SaveAvatarFilesLocalCopy(const ALocalDir: string): string;
const
  FILES: array[0..5] of string = (
    'avatar.png', 'avatar64.dds', 'avatar128.dds', 'avatar260.dds',
    'avatar440.dds', 'online.json'
  );
var
  BaseDir: string;
  FileName: string;
begin
  BaseDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'avatar-output');
  Result := TPath.Combine(BaseDir, FormatDateTime('yyyy-mm-dd_hhnnss', Now));
  ForceDirectories(Result);
  for FileName in FILES do
    TFile.Copy(TPath.Combine(ALocalDir, FileName),
      TPath.Combine(Result, FileName), True);
end;

function NewAvatarOutputDir(const AImageFile: string): string;
var
  BaseDir: string;
  FolderName: string;
begin
  BaseDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'avatar');
  FolderName := TPath.GetFileNameWithoutExtension(AImageFile);
  FolderName := StringReplace(FolderName, ' ', '_', [rfReplaceAll]);
  Result := TPath.Combine(BaseDir, FolderName);
  ForceDirectories(Result);
end;

function AvatarSettingsFileName: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'PS4Tools.ini');
end;

procedure TAvatarController.SetTarget(const AIP, AUser: string);
begin
  FHost := Trim(AIP);
  FUser := Trim(AUser);
  if FUser <> '' then
    FLastProfile := FUser;
end;

procedure TAvatarController.Browse;
begin
  btnBrowseClick(nil);
end;

procedure TAvatarController.CreateImages;
begin
  btnCreateClick(nil);
end;

procedure TAvatarController.Send;
begin
  btnSendClick(nil);
end;

procedure TAvatarController.AddLog(const AMsg: string);
begin
  SetStatus(AMsg);
  memLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + AMsg);
  memLog.SelStart := memLog.GetTextLen;
  memLog.Perform(EM_SCROLLCARET, 0, 0);
  Application.ProcessMessages;
end;

procedure TAvatarController.SetStatus(const AMsg: string);
begin
  Application.ProcessMessages;
end;

procedure TAvatarController.SetBusy(ABusy: Boolean);
begin
  edtName.Enabled := not ABusy;
  chkTransparent.Enabled := not ABusy;
  chkKeepLocal.Enabled := not ABusy;
  { O tipo de imagem so vale com "Fundo transparente" marcado. }
  cbImageType.Enabled := (not ABusy) and chkTransparent.Checked;
  cmbConverter.Enabled := not ABusy;
  btnBrowse.Enabled := not ABusy;
  btnCreateImage.Enabled := not ABusy;
  btnSend.Enabled := not ABusy;
  if ABusy then Screen.Cursor := crHourGlass else Screen.Cursor := crDefault;
end;

procedure TAvatarController.LoadSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(AvatarSettingsFileName);
  try
    FHost := Ini.ReadString(AVATAR_SETTINGS_SECTION, 'IP', '');
    edtName.Text := Ini.ReadString(AVATAR_SETTINGS_SECTION, 'Name', '');
    edtImage.Text := Ini.ReadString(AVATAR_SETTINGS_SECTION, 'Image', '');
    FLastProfile := Ini.ReadString(AVATAR_SETTINGS_SECTION, 'Profile', '');
    chkTransparent.Checked := Ini.ReadBool(AVATAR_SETTINGS_SECTION, 'Transparent', False);
    chkKeepLocal.Checked := Ini.ReadBool(AVATAR_SETTINGS_SECTION, 'KeepLocal', False);
    cbImageType.ItemIndex := Ini.ReadInteger(AVATAR_SETTINGS_SECTION, 'ImageType', 0);
    if (cbImageType.ItemIndex < 0) or (cbImageType.ItemIndex >= cbImageType.Items.Count) then
      cbImageType.ItemIndex := 0;
    cbImageType.Enabled := chkTransparent.Checked;
    cmbConverter.ItemIndex := Ini.ReadInteger(AVATAR_SETTINGS_SECTION, 'Converter', 0);
    if (cmbConverter.ItemIndex < 0) or
       (cmbConverter.ItemIndex >= cmbConverter.Items.Count) then
      cmbConverter.ItemIndex := 0;
  finally
    Ini.Free;
  end;

  if (edtImage.Text <> '') and FileExists(edtImage.Text) then
    LoadPreview(edtImage.Text);
end;

procedure TAvatarController.SaveSettings;
var
  Ini: TIniFile;
begin
  if FUser <> '' then
    FLastProfile := FUser;

  Ini := TIniFile.Create(AvatarSettingsFileName);
  try
    Ini.WriteString(AVATAR_SETTINGS_SECTION, 'IP', FHost);
    Ini.WriteString(AVATAR_SETTINGS_SECTION, 'Name', Trim(edtName.Text));
    Ini.WriteString(AVATAR_SETTINGS_SECTION, 'Image', Trim(edtImage.Text));
    Ini.WriteString(AVATAR_SETTINGS_SECTION, 'Profile', FLastProfile);
    Ini.WriteBool(AVATAR_SETTINGS_SECTION, 'Transparent', chkTransparent.Checked);
    Ini.WriteBool(AVATAR_SETTINGS_SECTION, 'KeepLocal', chkKeepLocal.Checked);
    Ini.WriteInteger(AVATAR_SETTINGS_SECTION, 'ImageType', cbImageType.ItemIndex);
    Ini.WriteInteger(AVATAR_SETTINGS_SECTION, 'Converter', cmbConverter.ItemIndex);
  finally
    Ini.Free;
  end;
end;

function TAvatarController.SelectedConverter: TAvatarDDSConverter;
begin
  if cmbConverter.ItemIndex = 1 then
    Result := adcInternal
  else
    Result := adcTexconv;
end;

procedure TAvatarController.LoadPreview(const AFileName: string);
begin
  imgPreview.Picture.LoadFromFile(AFileName);
end;

procedure TAvatarController.btnBrowseClick(Sender: TObject);
begin
  if OpenPictureDialog.Execute then
  begin
    edtImage.Text := OpenPictureDialog.FileName;
    LoadPreview(OpenPictureDialog.FileName);
    SaveSettings;
    AddLog('Imagem selecionada: ' + OpenPictureDialog.FileName);
  end;
end;

procedure TAvatarController.btnCreateClick(Sender: TObject);
var
  OutputDir: string;
  SourceImage, CroppedFile, WorkImage, EditedFile: string;
  ManualMask: Boolean;
  Progress: TProc<Integer, string>;
  ProgressBar: TProgressBar;
begin
  if (edtImage.Text = '') or not FileExists(edtImage.Text) then
  begin
    ShowMessage('Selecione uma imagem valida.');
    Exit;
  end;

  { Proporcao diferente da do avatar: o usuario enquadra antes de criar. }
  if not CropAvatarSourceIfNeeded(edtImage.Text, CurrentLanguage, CroppedFile) then
    Exit;
  WorkImage := edtImage.Text;
  if CroppedFile <> '' then
    WorkImage := CroppedFile;

  { Tipo "Manual": o usuario edita a mascara (apos o enquadramento). }
  if not EditAvatarMaskIfNeeded(WorkImage, chkTransparent.Checked,
       cbImageType.ItemIndex, CurrentLanguage, EditedFile) then
  begin
    DeleteAvatarTempSource(CroppedFile, '');
    Exit;
  end;
  ManualMask := EditedFile <> '';
  if ManualMask then
    WorkImage := EditedFile;

  SaveSettings;
  SetBusy(True);
  try
    AddLog('Criando avatar.png localmente...');
    OutputDir := NewAvatarOutputDir(edtImage.Text);
    ProgressBar := pbProgress;
    ProgressBar.Max := 1;
    ProgressBar.Position := 0;
    Progress :=
      procedure(APosition: Integer; AFileName: string)
      begin
        ProgressBar.Position := APosition;
        Application.ProcessMessages;
      end;
    if chkTransparent.Checked then
      AddLog('Removendo o fundo da imagem...');
    SourceImage := '';
    try
      { Com a mascara manual a transparencia ja esta feita: nao remove de novo. }
      SourceImage := PrepareAvatarSourceImage(WorkImage, OutputDir,
        chkTransparent.Checked and (not ManualMask),
        ImageTypeToMode(cbImageType.ItemIndex));
      BuildAvatarFiles(SourceImage, OutputDir, edtName.Text,
        chkTransparent.Checked, SelectedConverter, Progress, True);
    finally
      DeleteAvatarTempSource(SourceImage, WorkImage);
      DeleteAvatarTempSource(CroppedFile, '');
      DeleteAvatarTempSource(EditedFile, '');
    end;
    AddLog('Imagem criada: ' + TPath.Combine(OutputDir, 'avatar.png'));
    ShowMessage('Imagem criada:' + sLineBreak + TPath.Combine(OutputDir, 'avatar.png'));
  except
    on E: Exception do
    begin
      SetStatus('Falha ao criar imagens.');
      ShowMessage('Falha ao criar imagens: ' + E.Message);
    end;
  end;
  SetBusy(False);
end;

procedure TAvatarController.btnSendClick(Sender: TObject);
var
  IP: string;
  Profile: string;
  WorkDir: string;
  SavedDir: string;
  Progress: TProc<Integer, string>;
  ProgressBar: TProgressBar;
  LImageFile, LOutputDir, LOnlineName, LHost, LProfile: string;
  LCroppedFile, LWorkImage, LEditedFile: string;
  LTransparent, LKeepLocal, LManualMask: Boolean;
  LMode: TBgMode;
  LConverter: TAvatarDDSConverter;
  LProgressBar, LButtonSend, LButtonCreate, LButtonBrowse: TButton;
  LBar: TProgressBar;
  LHint: TLabel;
  LOriginalHint: string;
  LLanguage: TAppLanguage;
  Worker: TThread;
begin
  IP := FHost;
  Profile := FUser;
  if IP = '' then
  begin
    ShowMessage('Informe o IP do PS4.');
    Exit;
  end;
  if Profile = '' then
  begin
    ShowMessage('Carregue e selecione o perfil cache.');
    Exit;
  end;
  if (edtImage.Text = '') or not FileExists(edtImage.Text) then
  begin
    ShowMessage('Selecione uma imagem valida.');
    Exit;
  end;

  { Proporcao diferente da do avatar: o usuario enquadra antes de enviar. A
    pasta de saida continua levando o nome da imagem original. }
  if not CropAvatarSourceIfNeeded(edtImage.Text, CurrentLanguage, LCroppedFile) then
    Exit;
  LImageFile := edtImage.Text;
  LWorkImage := LImageFile;
  if LCroppedFile <> '' then
    LWorkImage := LCroppedFile;
  { Tipo "Manual": o usuario edita a mascara (apos o enquadramento). }
  if not EditAvatarMaskIfNeeded(LWorkImage, chkTransparent.Checked,
       cbImageType.ItemIndex, CurrentLanguage, LEditedFile) then
  begin
    DeleteAvatarTempSource(LCroppedFile, '');
    Exit;
  end;
  LManualMask := LEditedFile <> '';
  if LManualMask then
    LWorkImage := LEditedFile;
  LOutputDir := NewAvatarOutputDir(LImageFile);
  LOnlineName := edtName.Text;
  LHost := IP;
  LProfile := Profile;
  LTransparent := chkTransparent.Checked;
  LKeepLocal := chkKeepLocal.Checked;
  LMode := ImageTypeToMode(cbImageType.ItemIndex);
  LConverter := SelectedConverter;
  LBar := pbProgress;
  LHint := lblHint;
  LOriginalHint := LHint.Caption;
  LLanguage := CurrentLanguage;
  LButtonSend := btnSend;
  LButtonCreate := btnCreateImage;
  LButtonBrowse := btnBrowse;
  SetBusy(True);
  LBar.Style := pbstMarquee;
  LHint.Caption := AvatarProcessingText(LLanguage);
  LBar.Max := 6;
  LBar.Position := 0;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var ErrorText, LocalCopy, LSourceImage: string;
    begin
      LSourceImage := '';
      try
        try
          LSourceImage := PrepareAvatarSourceImage(LWorkImage, LOutputDir,
            LTransparent and (not LManualMask), LMode);
          BuildAvatarFiles(LSourceImage, LOutputDir, LOnlineName,
            LTransparent, LConverter,
            procedure(APosition: Integer; AFileName: string)
            begin
              TThread.Queue(nil,
                procedure
                begin
                  LBar.Position := APosition;
                  LBar.Hint := 'Criando ' + AFileName;
                end);
            end);
        finally
          DeleteAvatarTempSource(LSourceImage, LWorkImage);
          DeleteAvatarTempSource(LCroppedFile, '');
          DeleteAvatarTempSource(LEditedFile, '');
        end;
        if LKeepLocal then
          LocalCopy := SaveAvatarFilesLocalCopy(LOutputDir);
        UploadAvatarFiles(LHost, LProfile, LOutputDir);
      except
        on E: Exception do ErrorText := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          LButtonSend.Enabled := True;
          LButtonCreate.Enabled := True;
          LButtonBrowse.Enabled := True;
          Screen.Cursor := crDefault;
          LBar.Style := pbstNormal;
          LBar.Position := 0;
          LHint.Caption := LOriginalHint;
          if ErrorText <> '' then
            ShowMessage(TranslateText('Falha ao enviar o avatar: ' + ErrorText,
              LLanguage))
          else
            ShowMessage(AvatarSentText(LLanguage));
        end);
    end);
  Worker.FreeOnTerminate := True;
  Worker.Start;
  Exit;

  SaveSettings;
  SetBusy(True);
  try
    SetStatus('Preparando imagens do avatar...');
    WorkDir := NewAvatarOutputDir(edtImage.Text);
    ProgressBar := pbProgress;
    ProgressBar.Max := 6;
    ProgressBar.Position := 0;
    Progress :=
      procedure(APosition: Integer; AFileName: string)
      begin
        ProgressBar.Position := APosition;
        Application.ProcessMessages;
      end;

    AddLog('Gerando arquivos do avatar...');
    BuildAvatarFiles(edtImage.Text, WorkDir, edtName.Text,
      chkTransparent.Checked, SelectedConverter, Progress);
    if chkKeepLocal.Checked then
    begin
      SavedDir := SaveAvatarFilesLocalCopy(WorkDir);
      AddLog('Arquivos salvos em: ' + SavedDir);
    end;
    AddLog('Enviando para ' + PS4_PROFILE_CACHE_DIR + '/' + Profile + '...');
    UploadAvatarFiles(IP, Profile, WorkDir);
    AddLog('Avatar enviado. Reinicie o PS4 ou faca logout/login no usuario.');
    ShowMessage('Avatar enviado. Reinicie o PS4 ou faca logout/login no usuario.');
  except
    on E: Exception do
    begin
      SetStatus('Falha ao enviar avatar.');
      ShowMessage('Falha ao enviar avatar: ' + E.Message);
    end;
  end;
  SetBusy(False);
end;

end.


