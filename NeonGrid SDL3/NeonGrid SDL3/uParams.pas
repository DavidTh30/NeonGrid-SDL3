unit uParams;

{ Every tunable value of the background lives in the global record P.
  ParamDefs is a registry describing each value (group, name, hint, range,
  default) so the settings window, presets and the overview are generated
  from a single source of truth. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, BGRABitmapTypes;

const
  MaxBlobs = 8;
  PaletteSize = 6;

type
  TParamKind = (pkFloat, pkInt, pkBool, pkColor);

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
    Palette: array[0..PaletteSize - 1] of TBGRAPixel;
  end;

  TParamDef = record
    Group, Name, Hint: string;
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

procedure AddDef(const G, N, H: string; AKind: TParamKind; APtr: Pointer;
  AMin, AMax, ADef: Double; const ADefColor: TBGRAPixel);
var
  i: Integer;
begin
  i := Length(ParamDefs);
  SetLength(ParamDefs, i + 1);
  with ParamDefs[i] do
  begin
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
begin
  Result := PBGRAPixel(ParamDefs[AIndex].Ptr)^;
end;

procedure SetParamColor(AIndex: Integer; const AValue: TBGRAPixel);
begin
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
      pkColor: Result := ColorToHex(PBGRAPixel(Ptr)^);
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
      if Kind = pkColor then
        PBGRAPixel(Ptr)^ := DefColor
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
        if Kind = pkColor then
          ini.WriteString(Group, Name, ColorToHex(PBGRAPixel(Ptr)^))
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
        if Kind = pkColor then
          PBGRAPixel(Ptr)^ := HexToColor(s, PBGRAPixel(Ptr)^)
        else if TryStrToFloat(s, v, FS) then
          SetParam(i, v);
      end;
  finally
    ini.Free;
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
  g := 'Rendering';
  AddB(g, 'VSync', 'Wait for the monitor refresh in SDL_RenderPresent (SDL_SetRenderVSync).', P.VSync, True);
  AddF(g, 'Render scale', 'CPU render resolution relative to the window; SDL scales the texture up.', P.RenderScale, 0.25, 1.0, 1.0);
  AddB(g, 'Smooth upscale', 'Linear texture filtering when render scale is below 1.', P.SmoothUpscale, True);
  AddI(g, 'Threads', 'Worker threads (0 = one per logical CPU core).', P.ThreadCount, 0, 64, 0);
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

end.
