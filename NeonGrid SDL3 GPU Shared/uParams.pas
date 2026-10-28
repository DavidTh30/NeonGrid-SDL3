unit uParams;

{ Every tunable value of the background lives in the global record P.
  ParamDefs is a registry describing each value (category, group, name,
  hint, range, default). Shared by Neon Beads and Neon Trail: the games
  register their own values too (board look, bead colours, animation,
  effects, popups - see uGameFx and the game programs), and the whole
  registry is the game's .visuals file:

    ;@category Background            (a category starts)
    [Group]                          (one INI section per group)
    ;@float|0|4|1|hint               (kind|min|max|default|hint of the next key)
    Key=value

  The file is self-describing, so NeonVisualEditor (NeonGrid SDL3 GPU
  Tools) edits whatever a game registers, and values added later appear in
  the file and the editor without further work. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, BGRABitmapTypes;

const
  MaxBlobs = 8;
  PaletteSize = 6;

type
  TParamKind = (pkFloat, pkInt, pkBool, pkColor, pkRGB);   // pkRGB: 3 bytes r, g, b

  TBlob = record
    Enabled: Boolean;
    X, Y, Radius, Weight, DriftAmp, DriftSpeed: Single;
    Color: TBGRAPixel;
  end;

  TNeonParams = record
    { Rendering }
    VSync, GpuSync, Paused, SmoothUpscale: Boolean;
    ThreadCount: Integer;
    RenderScale, TimeScale, Exposure: Single;
    { Grid }
    Columns: Integer;
    DotRadius, ScrollX, ScrollY: Single;
    { Background }
    BgColor: TBGRAPixel;
    { Colour field }
    AmbientColor: TBGRAPixel;
    AmbientWeight, FieldBrightness, FieldSaturation: Single;
    Blobs: array[0..MaxBlobs - 1] of TBlob;
    BoundaryOn: Boolean;
    BoundaryTopX, BoundaryBottomX, BoundarySoftness, BoundaryStrength,
    BoundaryWaveAmp, BoundaryWaveFreq, BoundaryWaveSpeed: Single;
    BoundaryColor: TBGRAPixel;
    ShadowOn: Boolean;
    ShadowX, ShadowY, ShadowRadius, ShadowStrength: Single;
    { Per-dot animation }
    JitterBrightness, JitterHue, JitterSpeed: Single;
    SparkleOn: Boolean;
    SparkleProb, SparkleSpeed, SparkleIntensity: Single;
    TrailOn: Boolean;
    TrailOffset, TrailWidth, TrailSpeed, TrailIntensity, TrailDensity: Single;
    HighlightOn: Boolean;
    HighlightProb, HighlightSpeed, HighlightBoost: Single;
    HighlightColor: TBGRAPixel;
    BreathAmp, BreathSpeed: Single;
    { Pixel layers (dot sprite) }
    HazeOn: Boolean; HazeIntensity: Single;
    FillOn: Boolean; FillOpacity, FillLens: Single;
    CenterOn: Boolean; CenterSize, CenterDarkness: Single;
    RingOn: Boolean; RingWidth, RingIntensity, RingSaturation, RingWhiteMix: Single;
    GlowOn: Boolean; GlowRadius, GlowIntensity: Single;
    SparkOn: Boolean; SparkSize, SparkIntensity: Single; SparkColor: TBGRAPixel;
    VignetteOn: Boolean; VignetteStrength, VignetteInner, VignetteOuter: Single;
    { Background motion (the games: dots_ps MoveField) }
    MotionMode: Integer;
    MotionSpeed, MotionAmount, MotionAngle, MotionFreq, MotionCX, MotionCY: Single;
    { colour show (dots_ps ShowColor) }
    ShowMode, ShowRainbow, ShowBars: Integer;
    ShowStrength, ShowSpeed, ShowSize, ShowCX, ShowCY: Single;
    { dot motion (composite_ps DotMove) }
    MoveMode, MovePull: Integer;
    MoveAmount, MoveSpeed, MoveFreq, MoveCX, MoveCY: Single;
    MoveBeads: Boolean;
    { dot shape (uRenderer sprite) and its rotation (composite_ps) }
    DotShape: Integer;
    ShapeAngle, ShapeSpin, ShapeVary: Single;
    ShapeBeads: Boolean;
    { the game beads with a shape of their own (else they follow Dot shape) }
    BeadOwnShape: Boolean;
    BeadShape: Integer;
    BeadAngle, BeadSpin, BeadVary: Single;
    Palette: array[0..PaletteSize - 1] of TBGRAPixel;
  end;

  TParamDef = record
    Category, Group, Name, Hint: string;
    Hidden: Boolean;     // not written to the .visuals file (not used by the games)
    Kind: TParamKind;
    Ptr: Pointer;
    MinV, MaxV, DefV: Double;
    DefColor: TBGRAPixel;
  end;

var
  P: TNeonParams;
  ParamDefs: array of TParamDef;

function GetParam(AIndex: Integer): Double;
procedure SetParam(AIndex: Integer; AValue: Double);
function GetParamColor(AIndex: Integer): TBGRAPixel;
procedure SetParamColor(AIndex: Integer; const AValue: TBGRAPixel);
function ParamToText(AIndex: Integer): string;
function FindParam(const AGroup, AName: string): Integer;
procedure GetGroups(AList: TStrings);
procedure ResetDefaults;
procedure SaveParams(const AFileName: string);
procedure LoadParams(const AFileName: string);
function ColorToHex(const C: TBGRAPixel): string;
function HexToColor(const S: string; const ADefault: TBGRAPixel): TBGRAPixel;
{ registration (the games add their own values; ParamCategory sets the
  category of the values registered after it) }
procedure ParamCategory(const ACategory: string);
procedure AddF(const G, N, H: string; var V: Single; AMin, AMax, ADef: Double);
procedure AddI(const G, N, H: string; var V: Integer; AMin, AMax, ADef: Integer);
procedure AddB(const G, N, H: string; var V: Boolean; ADef: Boolean);
procedure AddC(const G, N, H: string; var V: TBGRAPixel; const ADef: TBGRAPixel);
procedure AddRGB(const G, N, H: string; var V; const ADef: TBGRAPixel);   // V: array[0..2] of Byte
{ a game's own default for a registered value (also sets the value) }
procedure SetParamDefault(const AGroup, AName: string; AValue: Double);
procedure SetParamDefaultColor(const AGroup, AName: string; const AValue: TBGRAPixel);
procedure HideParam(const AGroup, AName: string);
{ the self-describing .visuals file; LoadParamsFile is False when it does not exist }
procedure SaveParamsFile(const AFileName, ATitle: string);
function LoadParamsFile(const AFileName: string; out AMissing: Integer): Boolean;

implementation

var
  FS: TFormatSettings;

function ColorToHex(const C: TBGRAPixel): string;
begin
  Result := Format('#%.2X%.2X%.2X', [C.red, C.green, C.blue]);
end;

function HexToColor(const S: string; const ADefault: TBGRAPixel): TBGRAPixel;
var
  v: Integer;
  t: string;
begin
  t := Trim(S);
  if (t <> '') and (t[1] = '#') then Delete(t, 1, 1);
  if (Length(t) = 6) and TryStrToInt('$' + t, v) then
    Result := BGRA((v shr 16) and 255, (v shr 8) and 255, v and 255)
  else
    Result := ADefault;
end;

var
  CurCategory: string = 'Background';

procedure ParamCategory(const ACategory: string);
begin
  CurCategory := ACategory;
end;

procedure AddDef(const G, N, H: string; AKind: TParamKind; APtr: Pointer;
  AMin, AMax, ADef: Double; const ADefColor: TBGRAPixel);
var
  i: Integer;
begin
  i := Length(ParamDefs);
  SetLength(ParamDefs, i + 1);
  with ParamDefs[i] do
  begin
    Category := CurCategory; Hidden := False;
    Group := G; Name := N; Hint := H; Kind := AKind; Ptr := APtr;
    MinV := AMin; MaxV := AMax; DefV := ADef; DefColor := ADefColor;
  end;
end;

procedure AddF(const G, N, H: string; var V: Single; AMin, AMax, ADef: Double);
begin
  AddDef(G, N, H, pkFloat, @V, AMin, AMax, ADef, BGRABlack);
end;

procedure AddI(const G, N, H: string; var V: Integer; AMin, AMax, ADef: Integer);
begin
  AddDef(G, N, H, pkInt, @V, AMin, AMax, ADef, BGRABlack);
end;

procedure AddB(const G, N, H: string; var V: Boolean; ADef: Boolean);
begin
  AddDef(G, N, H, pkBool, @V, 0, 1, Ord(ADef), BGRABlack);
end;

procedure AddC(const G, N, H: string; var V: TBGRAPixel; const ADef: TBGRAPixel);
begin
  AddDef(G, N, H, pkColor, @V, 0, 0, 0, ADef);
end;

procedure AddRGB(const G, N, H: string; var V; const ADef: TBGRAPixel);
begin
  AddDef(G, N, H, pkRGB, @V, 0, 0, 0, ADef);
end;

procedure SetParamDefault(const AGroup, AName: string; AValue: Double);
var
  i: Integer;
begin
  i := FindParam(AGroup, AName);
  if i < 0 then Exit;
  ParamDefs[i].DefV := AValue;
  SetParam(i, AValue);
end;

procedure SetParamDefaultColor(const AGroup, AName: string; const AValue: TBGRAPixel);
var
  i: Integer;
begin
  i := FindParam(AGroup, AName);
  if i < 0 then Exit;
  ParamDefs[i].DefColor := AValue;
  SetParamColor(i, AValue);
end;

procedure HideParam(const AGroup, AName: string);
var
  i: Integer;
begin
  i := FindParam(AGroup, AName);
  if i >= 0 then ParamDefs[i].Hidden := True;
end;

function GetParam(AIndex: Integer): Double;
begin
  with ParamDefs[AIndex] do
    case Kind of
      pkFloat: Result := PSingle(Ptr)^;
      pkInt: Result := PInteger(Ptr)^;
      pkBool: Result := Ord(PBoolean(Ptr)^);
    else
      Result := 0;
    end;
end;

procedure SetParam(AIndex: Integer; AValue: Double);
begin
  with ParamDefs[AIndex] do
  begin
    if AValue < MinV then AValue := MinV;
    if AValue > MaxV then AValue := MaxV;
    case Kind of
      pkFloat: PSingle(Ptr)^ := AValue;
      pkInt: PInteger(Ptr)^ := Round(AValue);
      pkBool: PBoolean(Ptr)^ := AValue >= 0.5;
    end;
  end;
end;

function GetParamColor(AIndex: Integer): TBGRAPixel;
var
  b: PByte;
begin
  if ParamDefs[AIndex].Kind = pkRGB then
  begin
    b := ParamDefs[AIndex].Ptr;
    Result := BGRA(b[0], b[1], b[2]);
  end
  else
    Result := PBGRAPixel(ParamDefs[AIndex].Ptr)^;
end;

procedure SetParamColor(AIndex: Integer; const AValue: TBGRAPixel);
var
  b: PByte;
begin
  if ParamDefs[AIndex].Kind = pkRGB then
  begin
    b := ParamDefs[AIndex].Ptr;
    b[0] := AValue.red;
    b[1] := AValue.green;
    b[2] := AValue.blue;
  end
  else
    PBGRAPixel(ParamDefs[AIndex].Ptr)^ := BGRA(AValue.red, AValue.green, AValue.blue);
end;

function ParamToText(AIndex: Integer): string;
begin
  Result := '';
  with ParamDefs[AIndex] do
    case Kind of
      pkFloat: Result := FormatFloat('0.####', PSingle(Ptr)^, FS);
      pkInt: Result := IntToStr(PInteger(Ptr)^);
      pkBool: Result := BoolToStr(PBoolean(Ptr)^, 'On', 'Off');
      pkColor, pkRGB: Result := ColorToHex(GetParamColor(AIndex));
    end;
end;

function FindParam(const AGroup, AName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(ParamDefs) do
    if SameText(ParamDefs[i].Group, AGroup) and SameText(ParamDefs[i].Name, AName) then
      Exit(i);
  Result := -1;
end;

procedure GetGroups(AList: TStrings);
var
  i: Integer;
begin
  AList.Clear;
  for i := 0 to High(ParamDefs) do
    if AList.IndexOf(ParamDefs[i].Group) < 0 then
      AList.Add(ParamDefs[i].Group);
end;

procedure ResetDefaults;
var
  i: Integer;
begin
  for i := 0 to High(ParamDefs) do
    with ParamDefs[i] do
      if Kind in [pkColor, pkRGB] then
        SetParamColor(i, DefColor)
      else
        SetParam(i, DefV);
end;

procedure SaveParams(const AFileName: string);
var
  ini: TIniFile;
  i: Integer;
begin
  ini := TIniFile.Create(AFileName);
  try
    for i := 0 to High(ParamDefs) do
      with ParamDefs[i] do
        if Kind in [pkColor, pkRGB] then
          ini.WriteString(Group, Name, ColorToHex(GetParamColor(i)))
        else
          ini.WriteString(Group, Name, FloatToStr(GetParam(i), FS));
    ini.UpdateFile;
  finally
    ini.Free;
  end;
end;

procedure LoadParams(const AFileName: string);
var
  ini: TIniFile;
  i: Integer;
  s: string;
  v: Double;
begin
  ini := TIniFile.Create(AFileName);
  try
    for i := 0 to High(ParamDefs) do
      with ParamDefs[i] do
      begin
        s := ini.ReadString(Group, Name, '');
        if s = '' then Continue;
        if Kind in [pkColor, pkRGB] then
          SetParamColor(i, HexToColor(s, GetParamColor(i)))
        else if TryStrToFloat(s, v, FS) then
          SetParam(i, v);
      end;
  finally
    ini.Free;
  end;
end;

function LoadParamsFile(const AFileName: string; out AMissing: Integer): Boolean;
var
  ini: TMemIniFile;
  i: Integer;
  s: string;
  v: Double;
begin
  AMissing := 0;
  Result := FileExists(AFileName);
  if not Result then Exit;
  try
    ini := TMemIniFile.Create(AFileName);
    try
      for i := 0 to High(ParamDefs) do
        with ParamDefs[i] do
        begin
          if Hidden then Continue;
          s := Trim(ini.ReadString(Group, Name, ''));
          if s = '' then
          begin
            Inc(AMissing);   // a value added after the file was written
            Continue;
          end;
          if Kind in [pkColor, pkRGB] then
            SetParamColor(i, HexToColor(s, GetParamColor(i)))
          else if SameText(s, 'On') or SameText(s, 'True') then
            SetParam(i, 1)
          else if SameText(s, 'Off') or SameText(s, 'False') then
            SetParam(i, 0)
          else if TryStrToFloat(s, v, FS) then
            SetParam(i, v);
        end;
    finally
      ini.Free;
    end;
  except
    Result := False;
  end;
end;

procedure SaveParamsFile(const AFileName, ATitle: string);
const
  KindNames: array[TParamKind] of string = ('float', 'int', 'bool', 'color', 'color');
var
  sl, groups: TStringList;
  i, k: Integer;
  cat, def: string;

  function Clean(const S: string): string;
  begin
    Result := StringReplace(StringReplace(S, '|', '/', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  end;

begin
  sl := TStringList.Create;
  groups := TStringList.Create;
  try
    sl.Add('; ' + ATitle);
    sl.Add('; Every visual value of the game: background, board, beads, effects, popups.');
    sl.Add('; Edit with NeonVisualEditor (NeonGrid SDL3 GPU Tools) or by hand; the game');
    sl.Add('; reloads this file while it runs. ";@kind|min|max|default|hint" describes the');
    sl.Add('; key below it; values outside the range are clamped. Missing keys keep defaults.');
    { groups in registration order, each once }
    for i := 0 to High(ParamDefs) do
      if not ParamDefs[i].Hidden and (groups.IndexOf(ParamDefs[i].Group) < 0) then
        groups.AddObject(ParamDefs[i].Group, TObject(PtrInt(i)));
    cat := '';
    for k := 0 to groups.Count - 1 do
    begin
      i := PtrInt(groups.Objects[k]);
      if ParamDefs[i].Category <> cat then
      begin
        cat := ParamDefs[i].Category;
        sl.Add('');
        sl.Add(';@category ' + cat);
      end;
      sl.Add('');
      sl.Add('[' + groups[k] + ']');
      for i := 0 to High(ParamDefs) do
        with ParamDefs[i] do
        begin
          if Hidden or (Group <> groups[k]) then Continue;
          if Kind in [pkColor, pkRGB] then def := ColorToHex(DefColor)
          else def := FormatFloat('0.####', DefV, FS);
          sl.Add(Format(';@%s|%s|%s|%s|%s', [KindNames[Kind], FormatFloat('0.####', MinV, FS),
            FormatFloat('0.####', MaxV, FS), def, Clean(Hint)]));
          if Kind in [pkColor, pkRGB] then
            sl.Add(Name + '=' + ColorToHex(GetParamColor(i)))
          else if Kind = pkBool then
            sl.Add(Name + '=' + IntToStr(Round(GetParam(i))))
          else
            sl.Add(Name + '=' + FormatFloat('0.####', GetParam(i), FS));
        end;
    end;
    sl.SaveToFile(AFileName);
  finally
    groups.Free;
    sl.Free;
  end;
end;

procedure RegisterParams;
const
  BlobDef: array[0..MaxBlobs - 1, 0..8] of Single = (
    { X     Y     R     W    amp   spd   r    g    b }
    (0.06, 0.42, 0.24, 1.4, 0.04, 0.11, 206, 124,  44),  // orange
    (0.16, 0.66, 0.13, 0.9, 0.05, 0.17, 214, 152,  62),  // amber
    (0.10, 0.84, 0.24, 1.3, 0.05, 0.09,  32, 138, 152),  // teal
    (0.45, 0.97, 0.22, 0.8, 0.06, 0.13,  24,  92, 132),  // deep teal
    (0.36, 0.30, 0.12, 0.8, 0.07, 0.21,  42, 112, 176),  // blue
    (0.26, 0.10, 0.10, 0.7, 0.05, 0.19, 140,  58,  96),  // mauve
    (0.86, 0.62, 0.38, 1.0, 0.03, 0.07,  16,  48, 110),  // navy
    (0.30, 0.54, 0.10, 0.6, 0.08, 0.23, 128,  92, 104)); // dusty rose
  PalDef: array[0..PaletteSize - 1, 0..2] of Byte = (
    (228, 26, 42), (204, 38, 124), (44, 212, 232),
    (232, 140, 40), (124, 52, 168), (214, 122, 152));
var
  i: Integer;
  g: string;
begin
  ParamCategory('Background');
  g := 'Rendering';
  AddB(g, 'VSync', 'Present with SDL_GPU_PRESENTMODE_VSYNC (off = immediate / mailbox).', P.VSync, True);
  AddF(g, 'Render scale', 'GPU render resolution relative to the window; SDL_BlitGPUTexture scales it up.', P.RenderScale, 0.25, 1.0, 1.0);
  AddB(g, 'Smooth upscale', 'Linear texture filtering when render scale is below 1.', P.SmoothUpscale, True);
  AddI(g, 'Threads', 'CPU worker threads for GIF/MP4 exports (0 = one per logical core).', P.ThreadCount, 0, 64, 0);
  AddF(g, 'Time scale', 'Animation speed multiplier.', P.TimeScale, 0, 4, 1);
  AddB(g, 'Paused', 'Freeze animation time (rendering continues).', P.Paused, False);
  AddF(g, 'Exposure', 'Global brightness gain applied in the final pass.', P.Exposure, 0.2, 3, 1);

  g := 'Grid';
  AddI(g, 'Columns', 'Dots across the shorter window side; cell size = min(width, height) / columns.', P.Columns, 4, 80, 21);
  AddF(g, 'Dot radius', 'Circle radius as a fraction of the cell (0.5 = neighbours touch and leave black diamonds).', P.DotRadius, 0.3, 0.75, 0.5);
  AddF(g, 'Scroll X', 'Grid scroll speed in cells per second (horizontal).', P.ScrollX, -3, 3, 0);
  AddF(g, 'Scroll Y', 'Grid scroll speed in cells per second (vertical).', P.ScrollY, -3, 3, 0);

  g := 'Background';
  AddC(g, 'Color', 'Base colour behind all dots (the diamond gaps).', P.BgColor, BGRA(0, 0, 0));

  g := 'Color field';
  AddC(g, 'Ambient color', 'Colour used where no blob has influence.', P.AmbientColor, BGRA(12, 28, 62));
  AddF(g, 'Ambient weight', 'Weight of the ambient colour in the blob average.', P.AmbientWeight, 0, 1, 0.08);
  AddF(g, 'Brightness', 'Brightness multiplier of the colour field.', P.FieldBrightness, 0, 2, 1);
  AddF(g, 'Saturation', 'Saturation multiplier of the colour field.', P.FieldSaturation, 0, 2, 1.15);

  for i := 0 to MaxBlobs - 1 do
  begin
    g := 'Blob ' + IntToStr(i + 1);
    AddB(g, 'Enabled', 'Include this gaussian colour source.', P.Blobs[i].Enabled, True);
    AddF(g, 'X', 'Horizontal centre (0 = left, 1 = right).', P.Blobs[i].X, -0.5, 1.5, BlobDef[i, 0]);
    AddF(g, 'Y', 'Vertical centre (0 = top, 1 = bottom).', P.Blobs[i].Y, -0.5, 1.5, BlobDef[i, 1]);
    AddF(g, 'Radius', 'Gaussian radius in window-height units.', P.Blobs[i].Radius, 0.02, 1, BlobDef[i, 2]);
    AddF(g, 'Weight', 'Relative influence in the weighted colour average.', P.Blobs[i].Weight, 0, 3, BlobDef[i, 3]);
    AddF(g, 'Drift amp', 'How far the blob wanders (Lissajous drift).', P.Blobs[i].DriftAmp, 0, 0.3, BlobDef[i, 4]);
    AddF(g, 'Drift speed', 'Drift speed in radians per second.', P.Blobs[i].DriftSpeed, 0, 2, BlobDef[i, 5]);
    AddC(g, 'Color', 'Blob colour.', P.Blobs[i].Color,
      BGRA(Round(BlobDef[i, 6]), Round(BlobDef[i, 7]), Round(BlobDef[i, 8])));
  end;

  g := 'Boundary';
  AddB(g, 'Enabled', 'Diagonal edge that pushes the right side towards dark navy.', P.BoundaryOn, True);
  AddF(g, 'Top X', 'Boundary position at the top edge.', P.BoundaryTopX, -0.5, 1.5, 0.40);
  AddF(g, 'Bottom X', 'Boundary position at the bottom edge.', P.BoundaryBottomX, -0.5, 1.5, 0.68);
  AddF(g, 'Softness', 'Width of the transition across the boundary.', P.BoundarySoftness, 0.001, 0.3, 0.035);
  AddF(g, 'Strength', 'How strongly the right side is replaced by the boundary colour.', P.BoundaryStrength, 0, 1, 0.8);
  AddF(g, 'Wave amp', 'Sideways waviness of the boundary.', P.BoundaryWaveAmp, 0, 0.2, 0.025);
  AddF(g, 'Wave freq', 'Number of waves from top to bottom.', P.BoundaryWaveFreq, 0, 5, 1.3);
  AddF(g, 'Wave speed', 'Wave animation speed (rad/s).', P.BoundaryWaveSpeed, 0, 3, 0.25);
  AddC(g, 'Color', 'Colour of the right side.', P.BoundaryColor, BGRA(10, 30, 75));

  g := 'Corner shadow';
  AddB(g, 'Enabled', 'Darkens a corner (top-right in the reference image).', P.ShadowOn, True);
  AddF(g, 'X', 'Shadow centre X.', P.ShadowX, -0.5, 1.5, 1.0);
  AddF(g, 'Y', 'Shadow centre Y.', P.ShadowY, -0.5, 1.5, -0.02);
  AddF(g, 'Radius', 'Shadow radius in window-height units.', P.ShadowRadius, 0.05, 1.5, 0.6);
  AddF(g, 'Strength', 'Maximum darkening at the centre.', P.ShadowStrength, 0, 1, 0.85);

  g := 'Dot variation';
  AddF(g, 'Brightness jitter', 'Random per-dot brightness variation.', P.JitterBrightness, 0, 1, 0.32);
  AddF(g, 'Hue jitter', 'Random per-dot mix towards a palette colour.', P.JitterHue, 0, 1, 0.2);
  AddF(g, 'Jitter speed', 'How fast the per-dot brightness shimmers (Hz).', P.JitterSpeed, 0, 3, 0.15);

  g := 'Sparkles';
  AddB(g, 'Enabled', 'Random dots that bloom into vivid palette colours.', P.SparkleOn, True);
  AddF(g, 'Probability', 'Fraction of dots that can sparkle.', P.SparkleProb, 0, 0.5, 0.035);
  AddF(g, 'Speed', 'Sparkle cycle frequency (Hz).', P.SparkleSpeed, 0, 3, 0.25);
  AddF(g, 'Intensity', 'Maximum colour takeover of a sparkling dot.', P.SparkleIntensity, 0, 1, 0.9);

  g := 'Flow trail';
  AddB(g, 'Enabled', 'Stream of colourful dots flowing down along the boundary.', P.TrailOn, True);
  AddF(g, 'Offset', 'Horizontal offset of the trail from the boundary.', P.TrailOffset, -0.3, 0.3, 0.0);
  AddF(g, 'Width', 'Trail half-width in cells.', P.TrailWidth, 0.1, 6, 1.2);
  AddF(g, 'Speed', 'Flow speed in cells per second (negative = upwards).', P.TrailSpeed, -6, 6, 1.2);
  AddF(g, 'Intensity', 'Colour takeover inside the trail.', P.TrailIntensity, 0, 1, 0.85);
  AddF(g, 'Density', 'Fraction of trail segments that carry colour.', P.TrailDensity, 0, 1, 0.7);

  g := 'Highlights';
  AddB(g, 'Enabled', 'Dots whose ring flares to a white-hot outline.', P.HighlightOn, True);
  AddF(g, 'Probability', 'Fraction of dots that can flare (x5 near the trail).', P.HighlightProb, 0, 0.2, 0.018);
  AddF(g, 'Speed', 'Flare cycle frequency (Hz).', P.HighlightSpeed, 0, 2, 0.18);
  AddF(g, 'Boost', 'Ring brightness multiplier at the peak.', P.HighlightBoost, 1, 4, 1.8);
  AddC(g, 'Color', 'Ring colour at the peak of a flare.', P.HighlightColor, BGRA(255, 236, 225));

  g := 'Breathing';
  AddF(g, 'Amplitude', 'Global ring brightness pulsation.', P.BreathAmp, 0, 0.5, 0.08);
  AddF(g, 'Speed', 'Pulsation frequency (Hz).', P.BreathSpeed, 0, 2, 0.25);

  g := 'Haze layer';
  AddB(g, 'Enabled', 'Bilinear blur of dot colours under everything (bokeh haze).', P.HazeOn, True);
  AddF(g, 'Intensity', 'Haze brightness.', P.HazeIntensity, 0, 1, 0.14);

  g := 'Fill layer';
  AddB(g, 'Enabled', 'Translucent disc inside each circle.', P.FillOn, True);
  AddF(g, 'Opacity', 'Disc brightness.', P.FillOpacity, 0, 1, 0.75);
  AddF(g, 'Lens', 'Positive = darker centre / glassy rim, negative = domed.', P.FillLens, -1, 1, 0.15);

  g := 'Center mark';
  AddB(g, 'Enabled', 'Small dark cross cut out of every disc centre.', P.CenterOn, True);
  AddF(g, 'Size', 'Cross size as a fraction of the cell.', P.CenterSize, 0, 0.5, 0.14);
  AddF(g, 'Darkness', 'How much fill the cross removes.', P.CenterDarkness, 0, 1, 0.75);

  g := 'Ring layer';
  AddB(g, 'Enabled', 'Neon outline of each circle (forms the diamond edges).', P.RingOn, True);
  AddF(g, 'Width', 'Line width as a fraction of the cell.', P.RingWidth, 0.005, 0.15, 0.035);
  AddF(g, 'Intensity', 'Ring brightness.', P.RingIntensity, 0, 4, 0.8);
  AddF(g, 'Saturation', 'Saturation boost of the ring colour vs. the fill.', P.RingSaturation, 0, 3, 1.6);
  AddF(g, 'White mix', 'Amount of white added to every ring.', P.RingWhiteMix, 0, 1, 0.0);

  g := 'Glow layer';
  AddB(g, 'Enabled', 'Blurred halo around the ring (BGRABitmap radial blur).', P.GlowOn, True);
  AddF(g, 'Radius', 'Blur radius as a fraction of the cell.', P.GlowRadius, 0.01, 0.3, 0.07);
  AddF(g, 'Intensity', 'Halo brightness.', P.GlowIntensity, 0, 4, 0.45);

  g := 'Contact sparks';
  AddB(g, 'Enabled', 'Tiny coloured sparks where neighbouring circles touch.', P.SparkOn, True);
  AddF(g, 'Size', 'Spark radius as a fraction of the cell.', P.SparkSize, 0.01, 0.2, 0.035);
  AddF(g, 'Intensity', 'Spark brightness.', P.SparkIntensity, 0, 4, 1.0);
  AddC(g, 'Color', 'Spark colour.', P.SparkColor, BGRA(255, 40, 50));

  g := 'Vignette';
  AddB(g, 'Enabled', 'Darkens towards the window edges.', P.VignetteOn, True);
  AddF(g, 'Strength', 'Darkening at the outer radius.', P.VignetteStrength, 0, 1, 0.5);
  AddF(g, 'Inner', 'Normalised radius where darkening starts.', P.VignetteInner, 0, 1.5, 0.5);
  AddF(g, 'Outer', 'Normalised radius of full darkening.', P.VignetteOuter, 0.2, 2, 1.35);

  g := 'Motion';
  AddI(g, 'Mode', 'How the background colours move: 0 still, 1 pan (drifts on), 2 sway (back and forth), ' +
    '3 orbit (circles), 4 rotate, 5 zoom pulse, 6 wave, 7 swirl. The dots stay on the board grid.',
    P.MotionMode, 0, 7, 0);
  AddF(g, 'Speed', 'Speed of the motion (pan: field widths per 20 s, others: radians per second).',
    P.MotionSpeed, 0, 5, 0.4);
  AddF(g, 'Amount', 'Size of the motion (sway, orbit, zoom, wave, swirl).', P.MotionAmount, 0, 2, 0.5);
  AddF(g, 'Direction', 'Direction in degrees for pan and sway (0 = right, 90 = down).', P.MotionAngle, 0, 360, 30);
  AddF(g, 'Frequency', 'Waves across the screen (wave); size of the swirl (swirl).', P.MotionFreq, 0.1, 6, 1.5);
  AddF(g, 'Centre X', 'Centre of rotate, zoom and swirl (0 = left, 1 = right).', P.MotionCX, -0.5, 1.5, 0.5);
  AddF(g, 'Centre Y', 'Centre of rotate, zoom and swirl (0 = top, 1 = bottom).', P.MotionCY, -0.5, 1.5, 0.5);

  g := 'Colour show';
  AddI(g, 'Mode', 'A clearly visible moving pattern over the background colours: 0 off, 1 audio equalizer ' +
    'bars, 2 spinning colour wheel, 3 cartoon runners, 4 ripples, 5 spinning spiral, 6 plasma waves, 7 rain.',
    P.ShowMode, 0, 7, 0);
  AddF(g, 'Strength', 'How strongly the pattern covers the background colours.', P.ShowStrength, 0, 1, 0.85);
  AddF(g, 'Speed', 'Speed of the pattern.', P.ShowSpeed, 0, 5, 1);
  AddF(g, 'Size', 'Size of the pattern (bar height, wheel twist, cartoon size, ripple spacing...).',
    P.ShowSize, 0.2, 3, 1);
  AddI(g, 'Rainbow', '0 = the palette colours, 1 = rainbow colours.', P.ShowRainbow, 0, 1, 0);
  AddI(g, 'Bars / arms', 'Number of equalizer bars, colour wheel sectors or spiral arms.', P.ShowBars, 1, 40, 12);
  AddF(g, 'Centre X', 'Centre of the wheel, ripples and spiral (0 = left, 1 = right).', P.ShowCX, -0.5, 1.5, 0.5);
  AddF(g, 'Centre Y', 'Centre / height of the wheel, ripples, spiral and cartoon (0 = top, 1 = bottom).',
    P.ShowCY, -0.5, 1.5, 0.5);

  g := 'Dot motion';
  AddI(g, 'Mode', 'The background dots move: 0 still, 1 shake (explosion bursts), 2 squeezed back and forth, ' +
    '3 pushed / pulled by a moving point, 4 blast waves, 5 swirling orbits, 6 breathing.', P.MoveMode, 0, 6, 0);
  AddF(g, 'Amount', 'How far the dots move, in cells.', P.MoveAmount, 0, 2, 0.35);
  AddF(g, 'Speed', 'Speed of the motion.', P.MoveSpeed, 0, 5, 1);
  AddF(g, 'Frequency', 'Shake speed, wave length, size of the push area, blast spacing.', P.MoveFreq, 0.1, 5, 1);
  AddI(g, 'Push / pull', 'Mode 3: 0 the point pushes the dots away, 1 it pulls them in, 2 both in turn.',
    P.MovePull, 0, 2, 0);
  AddF(g, 'Centre X', 'Centre of the push point, blasts and breathing (0 = left, 1 = right).', P.MoveCX, -0.5, 1.5, 0.5);
  AddF(g, 'Centre Y', 'Centre of the push point, blasts and breathing (0 = top, 1 = bottom).', P.MoveCY, -0.5, 1.5, 0.5);
  AddB(g, 'Beads too', 'Also move the game beads (off keeps the board readable).', P.MoveBeads, False);

  g := 'Dot shape';
  AddI(g, 'Shape', 'Shape of every dot: 0 circle, 1 square, 2 diamond, 3 triangle, 4 hexagon, 5 star, ' +
    '6 flower, 7 heart, 8.. more (the shapes file, NeonShapeEditor).', P.DotShape, 0, 63, 0);
  AddF(g, 'Angle', 'Fixed rotation of the shapes in degrees.', P.ShapeAngle, -180, 180, 0);
  AddF(g, 'Spin', 'Spinning speed in degrees per second (0 = no spin).', P.ShapeSpin, -720, 720, 0);
  AddF(g, 'Variation', 'Different spin per dot: neighbours turn the other way, speeds vary.', P.ShapeVary, 0, 1, 0);
  AddB(g, 'Beads too', 'Also turn the game beads (when the beads have no own shape, see Bead shape).',
    P.ShapeBeads, True);

  { the beads of the game play, apart from the background dots }
  g := 'Bead shape (game play)';
  AddB(g, 'Own shape', 'The game beads get the shape below; off = the same shape as the background dots.',
    P.BeadOwnShape, False);
  AddI(g, 'Shape', 'Shape of the game beads: 0 circle, 1 square, 2 diamond, 3 triangle, 4 hexagon, 5 star, ' +
    '6 flower, 7 heart, 8.. more (the shapes file, NeonShapeEditor).', P.BeadShape, 0, 63, 0);
  AddF(g, 'Angle', 'Fixed rotation of the bead shapes in degrees.', P.BeadAngle, -180, 180, 0);
  AddF(g, 'Spin', 'Spinning speed of the beads in degrees per second (0 = no spin).', P.BeadSpin, -720, 720, 0);
  AddF(g, 'Variation', 'Different spin per bead: neighbours turn the other way, speeds vary.', P.BeadVary, 0, 1, 0);

  g := 'Palette';
  for i := 0 to PaletteSize - 1 do
    AddC(g, 'Color ' + IntToStr(i + 1), 'Accent colour used by jitter, sparkles and the trail.',
      P.Palette[i], BGRA(PalDef[i, 0], PalDef[i, 1], PalDef[i, 2]));
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  RegisterParams;
  ResetDefaults;
  { the games add their own categories after this }
  ParamCategory('Game');

end.
