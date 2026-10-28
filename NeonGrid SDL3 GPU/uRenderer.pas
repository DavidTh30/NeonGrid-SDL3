unit uRenderer;

{ CPU renderer of the neon dot-grid background.

  Frame pipeline (per worker thread, one horizontal band each, all cores):
    1. Dot pass     - colour/state of every dot whose sprite touches the band
                      (colour field + boundary + shadow + jitter + sparkles +
                      flow trail + highlights + breathing).
    2. Sprite pass  - additive accumulation of the pre-rendered dot sprite
                      (fill, center cut-out, ring, glow, contact sparks),
                      tinted per dot, into an integer accumulator.
    3. Final pass   - background + haze (bilinear blur of dot colours) +
                      accumulator, exposure and vignette, written into the
                      band's TBGRABitmap.
  The sprite layers themselves are drawn with BGRABitmap (antialiased
  ellipses, lines, radial blur) whenever a parameter that affects them changes.

  Frames are double-buffered: while the GPU waits for vsync, workers already
  render the next frame into the other buffer. }

{$mode objfpc}{$H+}
{$COPERATORS ON}
{$R-}{$Q-}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, Math, SyncObjs, GraphType, BGRABitmap, BGRABitmapTypes, uParams;

type
  TSpriteTexel = packed record
    A, B, C: Word;   // fill, ring+glow, spark  (8.8 fixed point)
  end;
  PSpriteTexel = ^TSpriteTexel;

  TDotState = record
    X, Y: Single;
    BaseR, BaseG, BaseB: Byte;          // dot colour (haze source)
    FR, FG, FB: Integer;                // fill tint 0..255
    RR, RG, RB: Integer;                // ring tint 0..1023
    Sparkle, Trail, Highlight: Single;  // animation factors (for previews)
  end;
  PDotState = ^TDotState;

  TFrameGeom = record
    W, H: Integer;
    Cell, OriginX, OriginY: Single;
    NCols, NRows: Integer;
    ShiftI, ShiftJ: Integer;
    Time: Double;
  end;

  TLayerKind = (lkBackground, lkColorField, lkBoundary, lkShadow, lkJitter,
    lkSparkles, lkTrail, lkHighlights, lkHaze, lkFill, lkCenter, lkGlow,
    lkRing, lkSparks, lkVignette);

  TLayerDef = record
    Name, Group, EnabledName, AmountName, Desc: string;
  end;

  TFrameStats = record
    FPS, FrameMs, WaitMs, UploadMs, SwapMs, CpuMs, MeasuredHz: Double;
    History: array[0..299] of Single;
    HistPos: Integer;
    Frames: Int64;
    RefreshHz: Integer;
    VSyncSupported, VSyncActive: Boolean;
    GLVendor, GLRenderer, GLVersion, TexFormat: string;
    ViewW, ViewH, RenderW, RenderH: Integer;
  end;

  TNeonRenderer = class;

  TRenderWorker = class(TThread)
  private
    FOwner: TNeonRenderer;
    FIndex: Integer;
    FStartEvt, FDoneEvt: TEvent;
    FAcc: array of Integer;
    FDots: array of TDotState;
    FVig: array of Word;
    FVigKey: array[0..8] of Single;
    FColIdx, FColFrac: array of Integer;
    FHaze: array of Integer;  // per-row vertically interpolated haze colours (x3)
    procedure RenderJob;
    procedure EnsureVignette(const Geo: TFrameGeom);
  protected
    procedure Execute; override;
  public
    Bands: array[0..1] of TBGRABitmap;
    Y0, Y1: Integer;
    JobMs, StartT, EndT: Double;
    PhaseMs: array[0..2] of Double;  // dot pass, sprite pass, final pass
    DotsComputed: Integer;
    constructor Create(AOwner: TNeonRenderer; AIndex: Integer);
    destructor Destroy; override;
  end;

  TNeonRenderer = class
  private
    FWorkers: array of TRenderWorker;
    FGeom, FReadyGeom: TFrameGeom;
    FSprite: array of TSpriteTexel;
    FSpanL, FSpanR: array of Integer;  // non-empty texel range per sprite row
    FSpriteN, FSpriteExt: Integer;
    FSpriteKey: array[0..11] of Single;
    FSpriteValid: Boolean;
    FBusy: Boolean;
    FWriteBuf, FReadyBuf: Integer;
    FBandW, FBandH: Integer;
    FSparkR, FSparkG, FSparkB: Integer;
    FLastCpuMs: Double;
    procedure EnsureWorkers;
    procedure EnsureBands(AW, AH: Integer);
    procedure ComputeGeom(AW, AH: Integer; ATime: Double; out Geo: TFrameGeom);
    procedure UpdateSprites;
    procedure BuildSprites;
    function PreviewGeom: TFrameGeom;
  public
    { BGRABitmap graphics of each sprite layer (white masks) + tinted composite }
    LayerFill, LayerCenter, LayerRing, LayerGlow, LayerSpark, SpriteComposite: TBGRABitmap;
    SpriteRebuilds: Integer;
    LastError: string;
    { when set, previews/field maps are evaluated at PreviewTime (used by exports) }
    PreviewTime: Double;
    UsePreviewTime: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure BeginFrame(AW, AH: Integer; ATime: Double);
    procedure WaitFrame;
    function WorkerCount: Integer;
    function Worker(AIndex: Integer): TRenderWorker;
    function BoundaryX(v, t: Single): Single;
    procedure FieldColor(u, v, t, aspect: Single; AModifiers: Boolean; out r, g, b: Single);
    procedure ComputeDot(i, j: Integer; const Geo: TFrameGeom; out D: TDotState);
    { GPU display: geometry + BGRABitmap sprite for a frame drawn by shaders.
      The geometry also becomes ReadyGeom, so previews match the window. }
    procedure PrepareDisplay(AW, AH: Integer; ATime: Double; out AGeo: TFrameGeom);
    function SpriteTexels: PSpriteTexel;
    function Snapshot(AW, AH: Integer): TBGRABitmap;
    { cheap 2x2-sampled thumbnail of the ready frame for live views (no full copy) }
    function SnapshotFast(AW, AH: Integer): TBGRABitmap;
    function BuildFieldMap(AW, AH: Integer; AModifiers: Boolean): TBGRABitmap;
    function BuildPreview(AKind: TLayerKind; AW, AH: Integer): TBGRABitmap;
    { Thread-safe variants: evaluate at an explicit geometry (see GeomAt), so
      export frames can be rendered in parallel on all cores. }
    function GeomAt(ATime: Double): TFrameGeom;
    function BuildFieldMapAt(AW, AH: Integer; AModifiers: Boolean; const AGeo: TFrameGeom): TBGRABitmap;
    function BuildPreviewAt(AKind: TLayerKind; AW, AH: Integer; const AGeo: TFrameGeom): TBGRABitmap;
    property Busy: Boolean read FBusy;
    property ReadyBuf: Integer read FReadyBuf;
    property ReadyGeom: TFrameGeom read FReadyGeom;
    property SpriteSize: Integer read FSpriteN;
    property SpriteExt: Integer read FSpriteExt;
    property LastCpuMs: Double read FLastCpuMs;
  end;

const
  LayerDefs: array[TLayerKind] of TLayerDef = (
    (Name: 'Background'; Group: 'Background'; EnabledName: ''; AmountName: '';
     Desc: 'Solid base colour. Visible as the black diamonds between the circles.'),
    (Name: 'Colour field'; Group: 'Color field'; EnabledName: ''; AmountName: 'Brightness';
     Desc: 'Eight drifting gaussian colour blobs averaged with an ambient colour: the large blurred "photo" sampled by the dots.'),
    (Name: 'Boundary'; Group: 'Boundary'; EnabledName: 'Enabled'; AmountName: 'Strength';
     Desc: 'Wavy diagonal edge; everything right of it is pushed towards dark navy.'),
    (Name: 'Corner shadow'; Group: 'Corner shadow'; EnabledName: 'Enabled'; AmountName: 'Strength';
     Desc: 'Radial darkening of the top-right corner.'),
    (Name: 'Dot variation'; Group: 'Dot variation'; EnabledName: ''; AmountName: 'Brightness jitter';
     Desc: 'Per-dot random brightness shimmer and palette hue mixing (final dot colours shown).'),
    (Name: 'Sparkles'; Group: 'Sparkles'; EnabledName: 'Enabled'; AmountName: 'Intensity';
     Desc: 'Random dots that slowly bloom into vivid palette colours (red, magenta, cyan...).'),
    (Name: 'Flow trail'; Group: 'Flow trail'; EnabledName: 'Enabled'; AmountName: 'Intensity';
     Desc: 'Segments of palette colours streaming down along the boundary.'),
    (Name: 'Highlights'; Group: 'Highlights'; EnabledName: 'Enabled'; AmountName: 'Probability';
     Desc: 'Dots whose ring flares to a white-hot outline (more likely near the trail).'),
    (Name: 'Haze'; Group: 'Haze layer'; EnabledName: 'Enabled'; AmountName: 'Intensity';
     Desc: 'Bilinear blur of the dot colours drawn under the sprites (bokeh glow).'),
    (Name: 'Fill'; Group: 'Fill layer'; EnabledName: 'Enabled'; AmountName: 'Opacity';
     Desc: 'Translucent disc with lens shading (BGRABitmap FillEllipseAntialias).'),
    (Name: 'Center mark'; Group: 'Center mark'; EnabledName: 'Enabled'; AmountName: 'Darkness';
     Desc: 'Dark cross + dot cut out of each disc (DrawLineAntialias).'),
    (Name: 'Glow'; Group: 'Glow layer'; EnabledName: 'Enabled'; AmountName: 'Intensity';
     Desc: 'Soft halo: thick ring blurred with BGRABitmap FilterBlurRadial.'),
    (Name: 'Ring'; Group: 'Ring layer'; EnabledName: 'Enabled'; AmountName: 'Intensity';
     Desc: 'Saturated neon outline (EllipseAntialias). Touching rings form the diamond edges.'),
    (Name: 'Contact sparks'; Group: 'Contact sparks'; EnabledName: 'Enabled'; AmountName: 'Intensity';
     Desc: 'Tiny red sparks at the four points where neighbouring circles touch.'),
    (Name: 'Vignette'; Group: 'Vignette'; EnabledName: 'Enabled'; AmountName: 'Strength';
     Desc: 'Final multiply that darkens towards the edges (with exposure).'));

var
  Stats: TFrameStats;

function HiResSeconds: Double;

implementation

function HiResSeconds: Double;
{$IFDEF WINDOWS}
var
  c, f: Int64;
begin
  QueryPerformanceCounter(c);
  QueryPerformanceFrequency(f);
  Result := c / f;
end;
{$ELSE}
begin
  Result := GetTickCount64 / 1000;
end;
{$ENDIF}

function Rnd(a, b, s: Integer): Single; inline;
var
  h: Cardinal;
begin
  h := Cardinal(a) * 374761393 + Cardinal(b) * 668265263 + Cardinal(s) * 2246822519;
  h := (h xor (h shr 13)) * 1274126177;
  h := h xor (h shr 16);
  Result := (h and $FFFFFF) / 16777216;
end;

function SmoothStep(e0, e1, x: Single): Single; inline;
begin
  if e1 = e0 then
  begin
    if x < e0 then Exit(0) else Exit(1);
  end;
  x := (x - e0) / (e1 - e0);
  if x < 0 then x := 0 else if x > 1 then x := 1;
  Result := x * x * (3 - 2 * x);
end;

procedure MixTo(var r, g, b: Single; const c: TBGRAPixel; t: Single); inline;
begin
  if t <= 0 then Exit;
  if t > 1 then t := 1;
  r += (c.red - r) * t;
  g += (c.green - g) * t;
  b += (c.blue - b) * t;
end;

function ClampI(v, lo, hi: Integer): Integer; inline;
begin
  if v < lo then Result := lo else if v > hi then Result := hi else Result := v;
end;

{ TRenderWorker }

constructor TRenderWorker.Create(AOwner: TNeonRenderer; AIndex: Integer);
begin
  FOwner := AOwner;
  FIndex := AIndex;
  FStartEvt := TEvent.Create(nil, False, False, '');
  FDoneEvt := TEvent.Create(nil, False, False, '');
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TRenderWorker.Destroy;
begin
  Terminate;
  FStartEvt.SetEvent;
  WaitFor;
  FStartEvt.Free;
  FDoneEvt.Free;
  Bands[0].Free;
  Bands[1].Free;
  inherited Destroy;
end;

procedure TRenderWorker.Execute;
begin
  while not Terminated do
  begin
    FStartEvt.WaitFor(INFINITE);
    if Terminated then Break;
    StartT := HiResSeconds;
    try
      RenderJob;
    except
      on E: Exception do FOwner.LastError := E.Message;
    end;
    EndT := HiResSeconds;
    JobMs := (EndT - StartT) * 1000;
    FDoneEvt.SetEvent;
  end;
end;

procedure TRenderWorker.EnsureVignette(const Geo: TFrameGeom);
var
  key: array[0..8] of Single;
  x, y, bh: Integer;
  dx, dy, v: Single;
begin
  key[0] := Geo.W; key[1] := Geo.H; key[2] := Y0; key[3] := Y1;
  key[4] := Ord(P.VignetteOn); key[5] := P.VignetteStrength;
  key[6] := P.VignetteInner; key[7] := P.VignetteOuter; key[8] := P.Exposure;
  bh := Y1 - Y0;
  if (Length(FVig) = Geo.W * bh) and CompareMem(@key, @FVigKey, SizeOf(key)) then Exit;
  FVigKey := key;
  SetLength(FVig, Geo.W * bh);
  for y := 0 to bh - 1 do
  begin
    dy := ((Y0 + y + 0.5) / Geo.H) * 2 - 1;
    for x := 0 to Geo.W - 1 do
    begin
      dx := ((x + 0.5) / Geo.W) * 2 - 1;
      v := 1;
      if P.VignetteOn then
        v := 1 - P.VignetteStrength * SmoothStep(P.VignetteInner, P.VignetteOuter, Sqrt(dx * dx + dy * dy));
      FVig[y * Geo.W + x] := ClampI(Round(v * P.Exposure * 256), 0, 1024);
    end;
  end;
end;

procedure TRenderWorker.RenderJob;
var
  O: TNeonRenderer;
  Geo: TFrameGeom;
  band: TBGRABitmap;
  W, bh, N, ext, j0, j1, nRows, i, j, x, y, sx0, sy0, xa, xb, ya, yb, need: Integer;
  d, rowA, rowB, d00, d10, d01, d11: PDotState;
  sp: PSpriteTexel;
  ap: PInteger;
  vp: PWord;
  pix: PBGRAPixel;
  fr, fg, fb, rr, rg, rb, sr, sg, sb, a, b, c: Integer;
  ix, fx, fy, iy, hz, bgR, bgG, bgB, tr, tg, tb, gain, top, bot: Integer;
  gx, gy: Single;
  sl, sr_: Integer;
  t0, t1: Double;
begin
  t0 := HiResSeconds;
  O := FOwner;
  Geo := O.FGeom;
  band := Bands[O.FWriteBuf];
  bh := Y1 - Y0;
  if (bh <= 0) or (band = nil) then Exit;
  W := Geo.W;
  N := O.FSpriteN;
  ext := O.FSpriteExt;

  { 1. dot pass: rows of dots that influence this band }
  j0 := ClampI(Floor((Y0 - ext - Geo.OriginY) / Geo.Cell) - 1, 0, Geo.NRows - 1);
  j1 := ClampI(Ceil((Y1 + ext - Geo.OriginY) / Geo.Cell) + 1, 0, Geo.NRows - 1);
  nRows := j1 - j0 + 1;
  if Length(FDots) < nRows * Geo.NCols then SetLength(FDots, nRows * Geo.NCols);
  for j := j0 to j1 do
    for i := 0 to Geo.NCols - 1 do
      O.ComputeDot(i, j, Geo, FDots[(j - j0) * Geo.NCols + i]);
  DotsComputed := nRows * Geo.NCols;
  t1 := HiResSeconds;
  PhaseMs[0] := (t1 - t0) * 1000;
  t0 := t1;

  { 2. sprite pass: additive, order independent }
  need := W * bh * 3;
  if Length(FAcc) <> need then SetLength(FAcc, need);
  FillDWord(FAcc[0], need, 0);
  sr := O.FSparkR; sg := O.FSparkG; sb := O.FSparkB;
  for j := j0 to j1 do
    for i := 0 to Geo.NCols - 1 do
    begin
      d := @FDots[(j - j0) * Geo.NCols + i];
      sx0 := Round(d^.X) - ext;
      sy0 := Round(d^.Y) - ext;
      ya := Max(sy0, Y0); yb := Min(sy0 + N - 1, Y1 - 1);
      if ya > yb then Continue;
      xa := Max(sx0, 0); xb := Min(sx0 + N - 1, W - 1);
      if xa > xb then Continue;
      fr := d^.FR; fg := d^.FG; fb := d^.FB;
      rr := d^.RR; rg := d^.RG; rb := d^.RB;
      for y := ya to yb do
      begin
        { only the non-empty span of this sprite row }
        sl := Max(xa, sx0 + O.FSpanL[y - sy0]);
        sr_ := Min(xb, sx0 + O.FSpanR[y - sy0]);
        if sl > sr_ then Continue;
        sp := @O.FSprite[(y - sy0) * N + (sl - sx0)];
        ap := @FAcc[((y - Y0) * W + sl) * 3];
        for x := sl to sr_ do
        begin
          a := sp^.A; b := sp^.B; c := sp^.C;
          if (a or b or c) <> 0 then
          begin
            ap[0] += a * fr + b * rr + c * sr;
            ap[1] += a * fg + b * rg + c * sg;
            ap[2] += a * fb + b * rb + c * sb;
          end;
          Inc(sp);
          Inc(ap, 3);
        end;
      end;
    end;

  t1 := HiResSeconds;
  PhaseMs[1] := (t1 - t0) * 1000;
  t0 := t1;

  { 3. final pass: background + haze + sprites, exposure * vignette }
  EnsureVignette(Geo);
  if Length(FColIdx) <> W then
  begin
    SetLength(FColIdx, W);
    SetLength(FColFrac, W);
  end;
  for x := 0 to W - 1 do
  begin
    gx := (x + 0.5 - Geo.OriginX) / Geo.Cell;
    ix := Floor(gx);
    fx := Round((gx - ix) * 256);
    if ix < 0 then begin ix := 0; fx := 0; end;
    if ix > Geo.NCols - 2 then begin ix := Geo.NCols - 2; fx := 256; end;
    FColIdx[x] := ix;
    FColFrac[x] := fx;
  end;
  hz := 0;
  if P.HazeOn then hz := Round(P.HazeIntensity * 256);
  bgR := P.BgColor.red shl 8; bgG := P.BgColor.green shl 8; bgB := P.BgColor.blue shl 8;

  if Length(FHaze) < Geo.NCols * 3 then SetLength(FHaze, Geo.NCols * 3);
  for y := Y0 to Y1 - 1 do
  begin
    ap := @FAcc[(y - Y0) * W * 3];
    vp := @FVig[(y - Y0) * W];
    pix := band.ScanLine[y - Y0];
    if hz > 0 then
    begin
      { vertical haze interpolation once per row and dot column }
      gy := (y + 0.5 - Geo.OriginY) / Geo.Cell;
      iy := Floor(gy);
      fy := Round((gy - iy) * 256);
      if iy < j0 then begin iy := j0; fy := 0; end;
      if iy > j1 - 1 then begin iy := j1 - 1; fy := 256; end;
      rowA := @FDots[(iy - j0) * Geo.NCols];
      rowB := rowA + Geo.NCols;
      for i := 0 to Geo.NCols - 1 do
      begin
        d00 := rowA + i;
        d01 := rowB + i;
        FHaze[i * 3] := ((Integer(d00^.BaseR) * (256 - fy) + Integer(d01^.BaseR) * fy) * hz) shr 8;
        FHaze[i * 3 + 1] := ((Integer(d00^.BaseG) * (256 - fy) + Integer(d01^.BaseG) * fy) * hz) shr 8;
        FHaze[i * 3 + 2] := ((Integer(d00^.BaseB) * (256 - fy) + Integer(d01^.BaseB) * fy) * hz) shr 8;
      end;
      for x := 0 to W - 1 do
      begin
        ix := FColIdx[x] * 3;
        fx := FColFrac[x];
        tr := bgR + ap[0] + FHaze[ix] + ((FHaze[ix + 3] - FHaze[ix]) * fx) div 256;
        tg := bgG + ap[1] + FHaze[ix + 1] + ((FHaze[ix + 4] - FHaze[ix + 1]) * fx) div 256;
        tb := bgB + ap[2] + FHaze[ix + 2] + ((FHaze[ix + 5] - FHaze[ix + 2]) * fx) div 256;
        if tr > 262143 then tr := 262143;
        if tg > 262143 then tg := 262143;
        if tb > 262143 then tb := 262143;
        gain := vp^;
        tr := (tr * gain) shr 16;
        tg := (tg * gain) shr 16;
        tb := (tb * gain) shr 16;
        if tr > 255 then tr := 255;
        if tg > 255 then tg := 255;
        if tb > 255 then tb := 255;
        pix^.red := tr; pix^.green := tg; pix^.blue := tb; pix^.alpha := 255;
        Inc(pix); Inc(ap, 3); Inc(vp);
      end;
    end
    else
      for x := 0 to W - 1 do
      begin
        tr := bgR + ap[0]; tg := bgG + ap[1]; tb := bgB + ap[2];
        if tr > 262143 then tr := 262143;
        if tg > 262143 then tg := 262143;
        if tb > 262143 then tb := 262143;
        gain := vp^;
        tr := (tr * gain) shr 16;
        tg := (tg * gain) shr 16;
        tb := (tb * gain) shr 16;
        if tr > 255 then tr := 255;
        if tg > 255 then tg := 255;
        if tb > 255 then tb := 255;
        pix^.red := tr; pix^.green := tg; pix^.blue := tb; pix^.alpha := 255;
        Inc(pix); Inc(ap, 3); Inc(vp);
      end;
  end;
  band.InvalidateBitmap;
  PhaseMs[2] := (HiResSeconds - t0) * 1000;
end;

{ TNeonRenderer }

constructor TNeonRenderer.Create;
begin
  inherited Create;
  FReadyBuf := 0;
  FBandW := -1;
end;

destructor TNeonRenderer.Destroy;
var
  i: Integer;
begin
  WaitFrame;
  for i := 0 to High(FWorkers) do FWorkers[i].Free;
  LayerFill.Free; LayerCenter.Free; LayerRing.Free; LayerGlow.Free;
  LayerSpark.Free; SpriteComposite.Free;
  inherited Destroy;
end;

function TNeonRenderer.WorkerCount: Integer;
begin
  Result := Length(FWorkers);
end;

function TNeonRenderer.Worker(AIndex: Integer): TRenderWorker;
begin
  Result := FWorkers[AIndex];
end;

procedure TNeonRenderer.EnsureWorkers;
var
  n, i: Integer;
begin
  n := P.ThreadCount;
  if n <= 0 then n := TThread.ProcessorCount;
  n := EnsureRange(n, 1, 64);
  if n = Length(FWorkers) then Exit;
  for i := 0 to High(FWorkers) do FWorkers[i].Free;
  SetLength(FWorkers, n);
  for i := 0 to n - 1 do FWorkers[i] := TRenderWorker.Create(Self, i);
  FBandW := -1;
end;

procedure TNeonRenderer.EnsureBands(AW, AH: Integer);
var
  i, n, b: Integer;
  w: TRenderWorker;
begin
  if (AW = FBandW) and (AH = FBandH) then Exit;
  n := Length(FWorkers);
  for i := 0 to n - 1 do
  begin
    w := FWorkers[i];
    w.Y0 := (AH * i) div n;
    w.Y1 := (AH * (i + 1)) div n;
    for b := 0 to 1 do
    begin
      FreeAndNil(w.Bands[b]);
      if w.Y1 > w.Y0 then
        w.Bands[b] := TBGRABitmap.Create(AW, w.Y1 - w.Y0, BGRABlack);
    end;
  end;
  FBandW := AW;
  FBandH := AH;
  FReadyGeom.W := 0;
end;

procedure TNeonRenderer.ComputeGeom(AW, AH: Integer; ATime: Double; out Geo: TFrameGeom);
var
  s: Double;
begin
  Geo.W := AW;
  Geo.H := AH;
  Geo.Time := ATime;
  Geo.Cell := Min(AW, AH) / Max(2, P.Columns);
  s := ATime * P.ScrollX;
  Geo.ShiftI := Floor(s);
  Geo.OriginX := (s - Geo.ShiftI) * Geo.Cell - Geo.Cell * 1.5;
  s := ATime * P.ScrollY;
  Geo.ShiftJ := Floor(s);
  Geo.OriginY := (s - Geo.ShiftJ) * Geo.Cell - Geo.Cell * 1.5;
  Geo.NCols := Ceil((AW - Geo.OriginX) / Geo.Cell) + 2;
  Geo.NRows := Ceil((AH - Geo.OriginY) / Geo.Cell) + 2;
end;

procedure TNeonRenderer.BeginFrame(AW, AH: Integer; ATime: Double);
var
  i: Integer;
begin
  if FBusy then WaitFrame;
  EnsureWorkers;
  EnsureBands(AW, AH);
  ComputeGeom(AW, AH, ATime, FGeom);
  UpdateSprites;
  FSparkR := P.SparkColor.red;
  FSparkG := P.SparkColor.green;
  FSparkB := P.SparkColor.blue;
  FWriteBuf := 1 - FReadyBuf;
  FBusy := True;
  for i := 0 to High(FWorkers) do FWorkers[i].FStartEvt.SetEvent;
end;

procedure TNeonRenderer.WaitFrame;
var
  i: Integer;
  t0, t1: Double;
begin
  if not FBusy then Exit;
  for i := 0 to High(FWorkers) do FWorkers[i].FDoneEvt.WaitFor(INFINITE);
  FBusy := False;
  FReadyBuf := FWriteBuf;
  FReadyGeom := FGeom;
  t0 := 1e30; t1 := 0;
  for i := 0 to High(FWorkers) do
  begin
    t0 := Min(t0, FWorkers[i].StartT);
    t1 := Max(t1, FWorkers[i].EndT);
  end;
  FLastCpuMs := Max(0, (t1 - t0) * 1000);
end;

procedure TNeonRenderer.UpdateSprites;
var
  key: array[0..11] of Single;
begin
  key[0] := FGeom.Cell; key[1] := P.DotRadius;
  key[2] := IfThen(P.FillOn, P.FillOpacity, -1); key[3] := P.FillLens;
  key[4] := IfThen(P.CenterOn, P.CenterDarkness, -1); key[5] := P.CenterSize;
  key[6] := P.RingWidth; key[7] := IfThen(P.RingOn, P.RingIntensity, -1);
  key[8] := P.GlowRadius; key[9] := IfThen(P.GlowOn, P.GlowIntensity, -1);
  key[10] := P.SparkSize; key[11] := IfThen(P.SparkOn, P.SparkIntensity, -1);
  if FSpriteValid and CompareMem(@key, @FSpriteKey, SizeOf(key)) then Exit;
  FSpriteKey := key;
  FSpriteValid := True;
  BuildSprites;
end;

procedure TNeonRenderer.BuildSprites;
var
  C, R, rw, gp, sp, cs, cc, d, f, lens, cm, va, vb, vc, gnorm, snorm: Single;
  ext, N, x, y, m: Integer;
  pf, pc, pr, pg, ps, po: PBGRAPixel;
  t: PSpriteTexel;
  sample: TBGRAPixel;

  function MaxGreen(B: TBGRABitmap): Integer;
  var
    k: Integer;
    q: PBGRAPixel;
  begin
    Result := 1;
    q := B.Data;
    for k := 0 to B.NbPixels - 1 do
    begin
      if q^.green > Result then Result := q^.green;
      Inc(q);
    end;
  end;

begin
  C := FGeom.Cell;
  R := P.DotRadius * C;
  rw := Max(1, P.RingWidth * C);
  gp := Max(0.5, P.GlowRadius * C);
  sp := Max(0.6, P.SparkSize * C);
  cs := Max(1, P.CenterSize * C * 0.5);
  ext := Ceil(Max(R + rw + 3 * gp, C * 0.5 + sp * 2)) + 2;
  N := 2 * ext + 1;
  cc := ext;

  FreeAndNil(LayerFill); FreeAndNil(LayerCenter); FreeAndNil(LayerRing);
  FreeAndNil(LayerGlow); FreeAndNil(LayerSpark); FreeAndNil(SpriteComposite);

  LayerFill := TBGRABitmap.Create(N, N, BGRABlack);
  LayerFill.FillEllipseAntialias(cc, cc, R, R, BGRAWhite);

  LayerCenter := TBGRABitmap.Create(N, N, BGRABlack);
  LayerCenter.FillEllipseAntialias(cc, cc, cs * 0.35, cs * 0.35, BGRAWhite);
  LayerCenter.DrawLineAntialias(cc - cs, cc, cc + cs, cc, BGRAWhite, Max(1, cs * 0.22));
  LayerCenter.DrawLineAntialias(cc, cc - cs, cc, cc + cs, BGRAWhite, Max(1, cs * 0.22));

  LayerRing := TBGRABitmap.Create(N, N, BGRABlack);
  LayerRing.EllipseAntialias(cc, cc, R, R, BGRAWhite, rw);

  LayerGlow := TBGRABitmap.Create(N, N, BGRABlack);
  LayerGlow.EllipseAntialias(cc, cc, R, R, BGRAWhite, rw * 2);
  BGRAReplace(LayerGlow, LayerGlow.FilterBlurRadial(gp, rbNormal));
  gnorm := 255 / MaxGreen(LayerGlow);

  LayerSpark := TBGRABitmap.Create(N, N, BGRABlack);
  LayerSpark.FillEllipseAntialias(cc - C * 0.5, cc, sp, sp, BGRAWhite);
  LayerSpark.FillEllipseAntialias(cc + C * 0.5, cc, sp, sp, BGRAWhite);
  LayerSpark.FillEllipseAntialias(cc, cc - C * 0.5, sp, sp, BGRAWhite);
  LayerSpark.FillEllipseAntialias(cc, cc + C * 0.5, sp, sp, BGRAWhite);
  BGRAReplace(LayerSpark, LayerSpark.FilterBlurRadial(Max(0.5, sp * 0.7), rbNormal));
  snorm := 255 / MaxGreen(LayerSpark);

  SpriteComposite := TBGRABitmap.Create(N, N, BGRABlack);
  sample := BGRA(205, 125, 45);

  SetLength(FSprite, N * N);
  for y := 0 to N - 1 do
  begin
    pf := LayerFill.ScanLine[y];
    pc := LayerCenter.ScanLine[y];
    pr := LayerRing.ScanLine[y];
    pg := LayerGlow.ScanLine[y];
    ps := LayerSpark.ScanLine[y];
    po := SpriteComposite.ScanLine[y];
    for x := 0 to N - 1 do
    begin
      d := Sqrt(Sqr(x - cc) + Sqr(y - cc)) / Max(R, 0.5);
      f := pf[x].green / 255;
      lens := 1 - P.FillLens * (1 - Min(1, d * d));
      cm := 0;
      if P.CenterOn then cm := pc[x].green / 255 * P.CenterDarkness;
      va := 0;
      if P.FillOn then va := f * P.FillOpacity * lens * (1 - cm);
      vb := 0;
      if P.RingOn then vb += pr[x].green / 255 * P.RingIntensity;
      if P.GlowOn then vb += Min(1, pg[x].green * gnorm / 255) * P.GlowIntensity;
      vc := 0;
      if P.SparkOn then vc := Min(1, ps[x].green * snorm / 255) * P.SparkIntensity * 0.5;
      t := @FSprite[y * N + x];
      t^.A := ClampI(Round(va * 256), 0, 65535);
      t^.B := ClampI(Round(vb * 256), 0, 65535);
      t^.C := ClampI(Round(vc * 256), 0, 65535);
      m := Round(sample.red * va + Min(255, sample.red * 1.4) * vb + P.SparkColor.red * vc);
      po[x].red := ClampI(m, 0, 255);
      m := Round(sample.green * va + Min(255, sample.green * 1.4) * vb + P.SparkColor.green * vc);
      po[x].green := ClampI(m, 0, 255);
      m := Round(sample.blue * va + Min(255, sample.blue * 1.4) * vb + P.SparkColor.blue * vc);
      po[x].blue := ClampI(m, 0, 255);
      po[x].alpha := 255;
    end;
  end;
  SpriteComposite.InvalidateBitmap;
  SetLength(FSpanL, N);
  SetLength(FSpanR, N);
  for y := 0 to N - 1 do
  begin
    FSpanL[y] := N;
    FSpanR[y] := -1;
    for x := 0 to N - 1 do
      with FSprite[y * N + x] do
        if (A or B or C) <> 0 then
        begin
          if x < FSpanL[y] then FSpanL[y] := x;
          FSpanR[y] := x;
        end;
  end;
  FSpriteN := N;
  FSpriteExt := ext;
  Inc(SpriteRebuilds);
end;

function TNeonRenderer.BoundaryX(v, t: Single): Single;
begin
  Result := P.BoundaryTopX + (P.BoundaryBottomX - P.BoundaryTopX) * v +
    P.BoundaryWaveAmp * Sin(v * P.BoundaryWaveFreq * 2 * Pi + t * P.BoundaryWaveSpeed);
end;

procedure TNeonRenderer.FieldColor(u, v, t, aspect: Single; AModifiers: Boolean; out r, g, b: Single);
var
  i: Integer;
  sw, w, dx, dy, bx, by, gray, side, d, s: Single;
begin
  sw := Max(P.AmbientWeight, 1e-4);
  r := P.AmbientColor.red * sw;
  g := P.AmbientColor.green * sw;
  b := P.AmbientColor.blue * sw;
  for i := 0 to MaxBlobs - 1 do
    if P.Blobs[i].Enabled then
    begin
      bx := P.Blobs[i].X + P.Blobs[i].DriftAmp * Sin(t * P.Blobs[i].DriftSpeed + i * 1.7);
      by := P.Blobs[i].Y + P.Blobs[i].DriftAmp * Cos(t * P.Blobs[i].DriftSpeed * 0.83 + i * 2.9);
      dx := (u - bx) * aspect;
      dy := v - by;
      w := P.Blobs[i].Weight * Exp(-(dx * dx + dy * dy) / Max(1e-4, Sqr(P.Blobs[i].Radius)));
      r += P.Blobs[i].Color.red * w;
      g += P.Blobs[i].Color.green * w;
      b += P.Blobs[i].Color.blue * w;
      sw += w;
    end;
  r /= sw; g /= sw; b /= sw;
  gray := (r + g + b) / 3;
  r := (gray + (r - gray) * P.FieldSaturation) * P.FieldBrightness;
  g := (gray + (g - gray) * P.FieldSaturation) * P.FieldBrightness;
  b := (gray + (b - gray) * P.FieldSaturation) * P.FieldBrightness;
  if not AModifiers then Exit;
  if P.BoundaryOn then
  begin
    side := SmoothStep(-P.BoundarySoftness, P.BoundarySoftness, u - BoundaryX(v, t)) * P.BoundaryStrength;
    MixTo(r, g, b, P.BoundaryColor, side);
  end;
  if P.ShadowOn then
  begin
    d := Sqrt(Sqr((u - P.ShadowX) * aspect) + Sqr(v - P.ShadowY)) / Max(P.ShadowRadius, 1e-3);
    s := 1 - P.ShadowStrength * (1 - SmoothStep(0, 1, d));
    r *= s; g *= s; b *= s;
  end;
end;

procedure TNeonRenderer.ComputeDot(i, j: Integer; const Geo: TFrameGeom; out D: TDotState);
var
  k, l, idx: Integer;
  u, v, t, r, g, b, a, tw, flow, f, p1, p2, hl, br, gray, rr, rg, rb, boost: Single;
  c1, c2: TBGRAPixel;
  tc: TBGRAPixel;
begin
  k := i - Geo.ShiftI;
  l := j - Geo.ShiftJ;
  t := Geo.Time;
  D.X := Geo.OriginX + i * Geo.Cell;
  D.Y := Geo.OriginY + j * Geo.Cell;
  u := D.X / Geo.W;
  v := D.Y / Geo.H;
  FieldColor(u, v, t, Geo.W / Geo.H, True, r, g, b);

  { brightness shimmer + hue jitter }
  a := 1 + P.JitterBrightness * ((Rnd(k, l, 1) * 2 - 1) * 0.7 +
    0.3 * Sin(2 * Pi * t * P.JitterSpeed * (0.5 + Rnd(k, l, 2)) + Rnd(k, l, 3) * 2 * Pi));
  r *= a; g *= a; b *= a;
  MixTo(r, g, b, P.Palette[Trunc(Rnd(k, l, 5) * PaletteSize) mod PaletteSize],
    P.JitterHue * Sqr(Rnd(k, l, 4)) * 0.6);

  { sparkles }
  D.Sparkle := 0;
  if P.SparkleOn and (Rnd(k, l, 6) < P.SparkleProb) then
  begin
    a := Sin(2 * Pi * t * P.SparkleSpeed * (0.5 + Rnd(k, l, 7)) + Rnd(k, l, 8) * 2 * Pi);
    if a > 0 then D.Sparkle := a * a * P.SparkleIntensity;
    MixTo(r, g, b, P.Palette[Trunc(Rnd(k, l, 9) * PaletteSize) mod PaletteSize], D.Sparkle);
  end;

  { flow trail along the boundary }
  D.Trail := 0;
  tw := 0;
  if P.TrailOn then
  begin
    a := (u - BoundaryX(v, t) - P.TrailOffset) * Geo.W / Geo.Cell;
    tw := Exp(-Sqr(a / Max(0.05, P.TrailWidth)));
    if tw > 0.01 then
    begin
      flow := l - t * P.TrailSpeed;
      idx := Floor(flow);
      f := flow - idx;
      p1 := Ord(Rnd(k, idx, 10) < P.TrailDensity);
      p2 := Ord(Rnd(k, idx + 1, 10) < P.TrailDensity);
      c1 := P.Palette[Trunc(Rnd(k, idx, 11) * PaletteSize) mod PaletteSize];
      c2 := P.Palette[Trunc(Rnd(k, idx + 1, 11) * PaletteSize) mod PaletteSize];
      tc := BGRA(Round(c1.red + (c2.red - c1.red) * f), Round(c1.green + (c2.green - c1.green) * f),
        Round(c1.blue + (c2.blue - c1.blue) * f));
      D.Trail := tw * (p1 + (p2 - p1) * f) * P.TrailIntensity;
      MixTo(r, g, b, tc, D.Trail);
    end;
  end;

  { white-hot highlights }
  hl := 0;
  if P.HighlightOn and (Rnd(k, l, 12) < P.HighlightProb * (1 + 4 * tw)) then
  begin
    hl := Sin(2 * Pi * t * P.HighlightSpeed * (0.6 + 0.8 * Rnd(k, l, 13)) + Rnd(k, l, 14) * 2 * Pi);
    if hl > 0 then hl := Power(hl, 6) else hl := 0;
  end;
  D.Highlight := hl;

  r := EnsureRange(r, 0, 255); g := EnsureRange(g, 0, 255); b := EnsureRange(b, 0, 255);
  D.BaseR := Round(r); D.BaseG := Round(g); D.BaseB := Round(b);
  D.FR := Round(r + (P.HighlightColor.red - r) * hl * 0.35);
  D.FG := Round(g + (P.HighlightColor.green - g) * hl * 0.35);
  D.FB := Round(b + (P.HighlightColor.blue - b) * hl * 0.35);

  { ring colour: saturated + white mix, flare and breathing }
  gray := (r + g + b) / 3;
  rr := Max(0, gray + (r - gray) * P.RingSaturation) + 255 * P.RingWhiteMix;
  rg := Max(0, gray + (g - gray) * P.RingSaturation) + 255 * P.RingWhiteMix;
  rb := Max(0, gray + (b - gray) * P.RingSaturation) + 255 * P.RingWhiteMix;
  rr += (P.HighlightColor.red - rr) * hl;
  rg += (P.HighlightColor.green - rg) * hl;
  rb += (P.HighlightColor.blue - rb) * hl;
  br := 1 + P.BreathAmp * Sin(2 * Pi * t * P.BreathSpeed + v * 3);
  boost := br * (1 + hl * (P.HighlightBoost - 1));
  D.RR := ClampI(Round(rr * boost), 0, 1023);
  D.RG := ClampI(Round(rg * boost), 0, 1023);
  D.RB := ClampI(Round(rb * boost), 0, 1023);
end;

procedure TNeonRenderer.PrepareDisplay(AW, AH: Integer; ATime: Double; out AGeo: TFrameGeom);
begin
  ComputeGeom(AW, AH, ATime, FGeom);
  UpdateSprites;
  FReadyGeom := FGeom;
  AGeo := FGeom;
end;

function TNeonRenderer.SpriteTexels: PSpriteTexel;
begin
  if Length(FSprite) = 0 then Exit(nil);
  Result := @FSprite[0];
end;

function TNeonRenderer.Snapshot(AW, AH: Integer): TBGRABitmap;
var
  full: TBGRABitmap;
  i: Integer;
  band: TBGRABitmap;
begin
  Result := nil;
  if (FReadyGeom.W <= 0) or (FReadyGeom.W <> FBandW) or (FReadyGeom.H <> FBandH) then Exit;
  full := TBGRABitmap.Create(FReadyGeom.W, FReadyGeom.H, BGRABlack);
  for i := 0 to High(FWorkers) do
  begin
    band := FWorkers[i].Bands[FReadyBuf];
    if Assigned(band) and (band.Width = FReadyGeom.W) then
      full.PutImage(0, FWorkers[i].Y0, band, dmSet);
  end;
  if (AW <> full.Width) or (AH <> full.Height) then
    BGRAReplace(full, full.Resample(Max(1, AW), Max(1, AH), rmFineResample));
  Result := full;
end;

function TNeonRenderer.SnapshotFast(AW, AH: Integer): TBGRABitmap;
var
  x, y, k, sx0, sx1, r, g, b: Integer;
  dst: PBGRAPixel;
  rows: array[0..1] of PBGRAPixel;
  c: TBGRAPixel;

  function RowPtr(AY: Integer): PBGRAPixel;
  var
    i: Integer;
  begin
    AY := EnsureRange(AY, 0, FReadyGeom.H - 1);
    for i := 0 to High(FWorkers) do
      if (AY >= FWorkers[i].Y0) and (AY < FWorkers[i].Y1) and Assigned(FWorkers[i].Bands[FReadyBuf]) then
        Exit(FWorkers[i].Bands[FReadyBuf].ScanLine[AY - FWorkers[i].Y0]);
    Result := nil;
  end;

begin
  Result := nil;
  if (FReadyGeom.W <= 0) or (FReadyGeom.W <> FBandW) or (FReadyGeom.H <> FBandH) then Exit;
  Result := TBGRABitmap.Create(Max(1, AW), Max(1, AH), BGRABlack);
  for y := 0 to Result.Height - 1 do
  begin
    { 2 x 2 samples per output pixel, source rows looked up once per row }
    rows[0] := RowPtr(((y * 4 + 1) * FReadyGeom.H) div (Result.Height * 4));
    rows[1] := RowPtr(((y * 4 + 3) * FReadyGeom.H) div (Result.Height * 4));
    if (rows[0] = nil) or (rows[1] = nil) then Continue;
    dst := Result.ScanLine[y];
    for x := 0 to Result.Width - 1 do
    begin
      sx0 := Min(FReadyGeom.W - 1, ((x * 4 + 1) * FReadyGeom.W) div (Result.Width * 4));
      sx1 := Min(FReadyGeom.W - 1, ((x * 4 + 3) * FReadyGeom.W) div (Result.Width * 4));
      r := 0; g := 0; b := 0;
      for k := 0 to 1 do
      begin
        c := rows[k][sx0]; r += c.red; g += c.green; b += c.blue;
        c := rows[k][sx1]; r += c.red; g += c.green; b += c.blue;
      end;
      dst^ := BGRA(r shr 2, g shr 2, b shr 2);
      Inc(dst);
    end;
  end;
  Result.InvalidateBitmap;
end;

function TNeonRenderer.PreviewGeom: TFrameGeom;
begin
  if UsePreviewTime then
  begin
    if FReadyGeom.W > 0 then
      ComputeGeom(FReadyGeom.W, FReadyGeom.H, PreviewTime, Result)
    else
      ComputeGeom(600, 1066, PreviewTime, Result);
  end
  else if FReadyGeom.W > 0 then
    Result := FReadyGeom
  else
    ComputeGeom(600, 1066, 0, Result);
end;

function TNeonRenderer.GeomAt(ATime: Double): TFrameGeom;
begin
  if FReadyGeom.W > 0 then
    ComputeGeom(FReadyGeom.W, FReadyGeom.H, ATime, Result)
  else
    ComputeGeom(600, 1066, ATime, Result);
end;

function TNeonRenderer.BuildFieldMap(AW, AH: Integer; AModifiers: Boolean): TBGRABitmap;
begin
  Result := BuildFieldMapAt(AW, AH, AModifiers, PreviewGeom);
end;

function TNeonRenderer.BuildPreview(AKind: TLayerKind; AW, AH: Integer): TBGRABitmap;
begin
  Result := BuildPreviewAt(AKind, AW, AH, PreviewGeom);
end;

function TNeonRenderer.BuildFieldMapAt(AW, AH: Integer; AModifiers: Boolean; const AGeo: TFrameGeom): TBGRABitmap;
var
  Geo: TFrameGeom;
  x, y: Integer;
  r, g, b: Single;
  q: PBGRAPixel;
begin
  Geo := AGeo;
  Result := TBGRABitmap.Create(AW, AH, BGRABlack);
  for y := 0 to AH - 1 do
  begin
    q := Result.ScanLine[y];
    for x := 0 to AW - 1 do
    begin
      FieldColor((x + 0.5) / AW, (y + 0.5) / AH, Geo.Time, Geo.W / Geo.H, AModifiers, r, g, b);
      q^ := BGRA(ClampI(Round(r), 0, 255), ClampI(Round(g), 0, 255), ClampI(Round(b), 0, 255));
      Inc(q);
    end;
  end;
  Result.InvalidateBitmap;
end;

function TNeonRenderer.BuildPreviewAt(AKind: TLayerKind; AW, AH: Integer; const AGeo: TFrameGeom): TBGRABitmap;
var
  Geo: TFrameGeom;
  x, y, i, j: Integer;
  sx, sy, rad, v, r, g, b, side, d: Single;
  q: PBGRAPixel;
  Dot: TDotState;
  c: TBGRAPixel;
  src: TBGRABitmap;

  procedure PutMask(ADest, AMask: TBGRABitmap; const ATint: TBGRAPixel);
  var
    tmp: TBGRABitmap;
    k: Integer;
    p: PBGRAPixel;
  begin
    if AMask = nil then Exit;
    tmp := AMask.Resample(AW, AH, rmFineResample) as TBGRABitmap;
    p := tmp.Data;
    for k := 0 to tmp.NbPixels - 1 do
    begin
      p^ := BGRA(ATint.red * p^.green div 255, ATint.green * p^.green div 255, ATint.blue * p^.green div 255);
      Inc(p);
    end;
    tmp.InvalidateBitmap;
    ADest.PutImage(0, 0, tmp, dmSet);
    tmp.Free;
  end;

begin
  Geo := AGeo;
  sx := AW / Geo.W;
  sy := AH / Geo.H;
  case AKind of
    lkBackground:
      Result := TBGRABitmap.Create(AW, AH, P.BgColor);
    lkColorField:
      begin
        Result := BuildFieldMapAt(AW, AH, False, Geo);
        for i := 0 to MaxBlobs - 1 do
          if P.Blobs[i].Enabled then
          begin
            r := (P.Blobs[i].X + P.Blobs[i].DriftAmp * Sin(Geo.Time * P.Blobs[i].DriftSpeed + i * 1.7)) * AW;
            g := (P.Blobs[i].Y + P.Blobs[i].DriftAmp * Cos(Geo.Time * P.Blobs[i].DriftSpeed * 0.83 + i * 2.9)) * AH;
            Result.EllipseAntialias(r, g, 3, 3, BGRAWhite, 1);
          end;
      end;
    lkHaze:
      begin
        Result := BuildFieldMapAt(AW, AH, True, Geo);
        if not P.HazeOn then Result.FillRect(0, 0, AW, AH, BGRA(0, 0, 0, 160), dmDrawWithTransparency);
      end;
    lkBoundary, lkShadow, lkVignette:
      begin
        Result := TBGRABitmap.Create(AW, AH, BGRABlack);
        for y := 0 to AH - 1 do
        begin
          q := Result.ScanLine[y];
          for x := 0 to AW - 1 do
          begin
            r := (x + 0.5) / AW; g := (y + 0.5) / AH;
            case AKind of
              lkBoundary:
                begin
                  side := SmoothStep(-P.BoundarySoftness, P.BoundarySoftness, r - BoundaryX(g, Geo.Time)) * P.BoundaryStrength;
                  if not P.BoundaryOn then side := 0;
                  q^ := BGRA(Round(200 * (1 - side) + P.BoundaryColor.red * side),
                    Round(150 * (1 - side) + P.BoundaryColor.green * side),
                    Round(90 * (1 - side) + P.BoundaryColor.blue * side));
                end;
              lkShadow:
                begin
                  d := Sqrt(Sqr((r - P.ShadowX) * Geo.W / Geo.H) + Sqr(g - P.ShadowY)) / Max(P.ShadowRadius, 1e-3);
                  v := 1 - P.ShadowStrength * (1 - SmoothStep(0, 1, d));
                  if not P.ShadowOn then v := 1;
                  q^ := BGRA(Round(230 * v), Round(230 * v), Round(230 * v));
                end;
              lkVignette:
                begin
                  d := Sqrt(Sqr(r * 2 - 1) + Sqr(g * 2 - 1));
                  v := 1;
                  if P.VignetteOn then v := 1 - P.VignetteStrength * SmoothStep(P.VignetteInner, P.VignetteOuter, d);
                  q^ := BGRA(Round(230 * v), Round(230 * v), Round(230 * v));
                end;
            end;
            Inc(q);
          end;
        end;
        Result.InvalidateBitmap;
      end;
    lkJitter, lkSparkles, lkTrail, lkHighlights:
      begin
        Result := TBGRABitmap.Create(AW, AH, BGRABlack);
        rad := Max(0.8, P.DotRadius * Geo.Cell * sx * 0.92);
        for j := 0 to Geo.NRows - 1 do
          for i := 0 to Geo.NCols - 1 do
          begin
            ComputeDot(i, j, Geo, Dot);
            c := BGRA(Dot.BaseR, Dot.BaseG, Dot.BaseB);
            case AKind of
              lkSparkles: c := BGRA(Round(Dot.BaseR * Dot.Sparkle), Round(Dot.BaseG * Dot.Sparkle), Round(Dot.BaseB * Dot.Sparkle));
              lkTrail: c := BGRA(Round(Dot.BaseR * Min(1, Dot.Trail)), Round(Dot.BaseG * Min(1, Dot.Trail)), Round(Dot.BaseB * Min(1, Dot.Trail)));
              lkHighlights:
                begin
                  v := Dot.Highlight;
                  c := BGRA(Round(25 + P.HighlightColor.red * v * 0.9), Round(25 + P.HighlightColor.green * v * 0.9),
                    Round(30 + P.HighlightColor.blue * v * 0.9));
                end;
            end;
            Result.FillEllipseAntialias(Dot.X * sx, Dot.Y * sy, rad, rad, c);
          end;
      end;
  else
    begin
      Result := TBGRABitmap.Create(AW, AH, BGRABlack);
      case AKind of
        lkFill: src := LayerFill;
        lkCenter: src := LayerCenter;
        lkGlow: src := LayerGlow;
        lkRing: src := LayerRing;
      else
        src := LayerSpark;
      end;
      case AKind of
        lkFill: c := BGRA(205, 125, 45);
        lkCenter: c := BGRA(200, 200, 200);
        lkGlow: c := BGRA(60, 200, 230);
        lkRing: c := BGRA(255, 190, 70);
      else
        c := P.SparkColor;
      end;
      PutMask(Result, src, c);
    end;
  end;
end;

end.
