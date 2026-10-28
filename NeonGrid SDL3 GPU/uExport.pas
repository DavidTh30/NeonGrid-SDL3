unit uExport;

{ Export helpers: render layers, graphics and full frames into TBGRABitmap
  images and write them as PNG or animated GIF (TBGRAAnimatedGif, colour
  quantised per frame with Floyd-Steinberg dithering). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, BGRABitmap, BGRABitmapTypes, BGRAAnimatedGif,
  BGRAPalette, BGRAColorQuantization, uParams, uRenderer;

type
  TGraphicItem = (giSprite, giFill, giCenter, giRing, giGlow, giSpark,
    giFieldBlobs, giFieldFull, giDotColours, giFinalFrame, giPalette, giSheet);

const
  GraphicNames: array[TGraphicItem] of string = (
    'Dot sprite composite', 'Fill disc mask', 'Center cross mask', 'Ring outline mask',
    'Glow mask', 'Contact sparks mask', 'Colour field (blobs)', 'Colour field + modifiers',
    'Dot colours', 'Final frame', 'Colour swatches', 'Graphics sheet');
  { items that change over time (others are written as a single-frame GIF) }
  GraphicAnimated: array[TGraphicItem] of Boolean = (
    False, False, False, False, False, False, True, True, True, True, False, False);

function LayerAnimated(AKind: TLayerKind): Boolean;
function SafeName(const S: string): string;
function TimeStamp: string;
{ Mask graphics are scaled by an integer factor (crisp pixels) to fit AW x AH. }
function RenderSpriteItem(R: TNeonRenderer; AItem: TGraphicItem; AW, AH: Integer): TBGRABitmap;
function RenderSwatches(AW, AH: Integer): TBGRABitmap;

type
  TFrameFunc = function(AIndex: Integer): TBGRABitmap of object;
  TFrameSink = procedure(AIndex: Integer; AFrame: TBGRABitmap) of object;
  TIdleProc = procedure of object;

  { Renders preview frames of one layer or graphic at precomputed geometries.
    Frame() only reads renderer state, so it may run on several threads. }
  TPreviewJob = class
  public
    R: TNeonRenderer;
    IsLayer: Boolean;
    Kind: TLayerKind;
    Graphic: TGraphicItem;
    W, H: Integer;
    Geos: array of TFrameGeom;
    constructor Create(AR: TNeonRenderer; AIsLayer: Boolean; AKind: TLayerKind;
      AGraphic: TGraphicItem; AW, AH, ACount: Integer; AT0, ADt: Double);
    function Frame(AIndex: Integer): TBGRABitmap;
  end;

const
  { graphics whose frames can be rendered in parallel (the final frame uses its own renderer) }
  ParallelGraphics = [giFieldBlobs, giFieldFull, giDotColours];

{ Renders frames 0..ACount-1 with AFunc in batches on all CPU cores, then passes
  them in order to ASink (which must not keep them: they are freed afterwards).
  AIdle is called while waiting so the UI stays responsive. }
procedure RenderFramesParallel(AFunc: TFrameFunc; ACount: Integer; ASink: TFrameSink; AIdle: TIdleProc);

type
  { Collects frames and writes an endlessly looping animated GIF. }
  TGifWriter = class
  private
    FGif: TBGRAAnimatedGif;
    FDelayMs: Integer;
  public
    constructor Create(AW, AH, ADelayMs: Integer);
    destructor Destroy; override;
    procedure Add(AFrame: TBGRABitmap);
    procedure Save(const AFileName: string);
  end;

implementation

function LayerAnimated(AKind: TLayerKind): Boolean;
begin
  Result := AKind in [lkColorField, lkBoundary, lkJitter, lkSparkles, lkTrail,
    lkHighlights, lkHaze];
end;

function SafeName(const S: string): string;
var
  c: Char;
begin
  Result := '';
  for c in LowerCase(S) do
    if c in ['a'..'z', '0'..'9'] then
      Result += c
    else if (Result <> '') and (Result[Length(Result)] <> '_') then
      Result += '_';
  while (Result <> '') and (Result[Length(Result)] = '_') do
    Delete(Result, Length(Result), 1);
end;

function TimeStamp: string;
begin
  Result := FormatDateTime('yyyymmdd_hhnnss', Now);
end;

function RenderSpriteItem(R: TNeonRenderer; AItem: TGraphicItem; AW, AH: Integer): TBGRABitmap;
var
  src: TBGRABitmap;
  z: Integer;
begin
  case AItem of
    giSprite: src := R.SpriteComposite;
    giFill: src := R.LayerFill;
    giCenter: src := R.LayerCenter;
    giRing: src := R.LayerRing;
    giGlow: src := R.LayerGlow;
  else
    src := R.LayerSpark;
  end;
  if src = nil then Exit(TBGRABitmap.Create(Max(1, AW), Max(1, AH), BGRABlack));
  z := Max(1, Min(AW, AH) div src.Width);
  Result := src.Resample(src.Width * z, src.Height * z, rmSimpleStretch) as TBGRABitmap;
end;

function RenderSwatches(AW, AH: Integer): TBGRABitmap;
var
  names: array of string;
  cols: array of TBGRAPixel;
  i, n, nc, nr, cw, ch, x, y: Integer;

  procedure Add(const AName: string; const C: TBGRAPixel);
  begin
    SetLength(names, Length(names) + 1);
    SetLength(cols, Length(cols) + 1);
    names[High(names)] := AName;
    cols[High(cols)] := C;
  end;

begin
  names := nil;
  cols := nil;
  Add('Background', P.BgColor);
  Add('Ambient', P.AmbientColor);
  Add('Boundary', P.BoundaryColor);
  Add('Spark', P.SparkColor);
  Add('Highlight', P.HighlightColor);
  for i := 0 to PaletteSize - 1 do Add('Palette ' + IntToStr(i + 1), P.Palette[i]);
  for i := 0 to MaxBlobs - 1 do Add('Blob ' + IntToStr(i + 1), P.Blobs[i].Color);
  n := Length(cols);
  nc := Max(1, Round(Sqrt(n * AW / Max(1, AH))));
  nr := Ceil(n / nc);
  cw := AW div nc;
  ch := AH div nr;
  Result := TBGRABitmap.Create(AW, AH, BGRA(16, 18, 26));
  Result.FontName := 'Segoe UI';
  Result.FontHeight := EnsureRange(ch div 7, 9, 18);
  Result.FontQuality := fqFineAntialiasing;
  for i := 0 to n - 1 do
  begin
    x := (i mod nc) * cw;
    y := (i div nc) * ch;
    Result.FillRect(x + 4, y + 4, x + cw - 4, y + ch - 2 * Result.FontHeight - 8, cols[i], dmSet);
    Result.TextOut(x + 4, y + ch - 2 * Result.FontHeight - 6, names[i], BGRA(220, 220, 228));
    Result.TextOut(x + 4, y + ch - Result.FontHeight - 4, ColorToHex(cols[i]), BGRA(150, 150, 160));
  end;
end;

{ TPreviewJob }

constructor TPreviewJob.Create(AR: TNeonRenderer; AIsLayer: Boolean; AKind: TLayerKind;
  AGraphic: TGraphicItem; AW, AH, ACount: Integer; AT0, ADt: Double);
var
  i: Integer;
begin
  inherited Create;
  R := AR;
  IsLayer := AIsLayer;
  Kind := AKind;
  Graphic := AGraphic;
  W := AW;
  H := AH;
  SetLength(Geos, ACount);
  for i := 0 to ACount - 1 do
    Geos[i] := R.GeomAt(AT0 + i * ADt);
end;

function TPreviewJob.Frame(AIndex: Integer): TBGRABitmap;
begin
  if IsLayer then
    Exit(R.BuildPreviewAt(Kind, W, H, Geos[AIndex]));
  case Graphic of
    giFieldBlobs: Result := R.BuildFieldMapAt(W, H, False, Geos[AIndex]);
    giFieldFull: Result := R.BuildFieldMapAt(W, H, True, Geos[AIndex]);
  else
    Result := R.BuildPreviewAt(lkJitter, W, H, Geos[AIndex]);
  end;
end;

{ parallel frame rendering }

type
  TFrameThread = class(TThread)
  private
    FFunc: TFrameFunc;
    FNext: PLongInt;
    FFirst, FCount: Integer;
    FOut: PPointer;
  protected
    procedure Execute; override;
  public
    Error: string;
    constructor Create(AFunc: TFrameFunc; ANext: PLongInt; AFirst, ACount: Integer; AOut: PPointer);
  end;

constructor TFrameThread.Create(AFunc: TFrameFunc; ANext: PLongInt; AFirst, ACount: Integer; AOut: PPointer);
begin
  FFunc := AFunc;
  FNext := ANext;
  FFirst := AFirst;
  FCount := ACount;
  FOut := AOut;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TFrameThread.Execute;
var
  i: LongInt;
begin
  try
    repeat
      i := InterLockedIncrement(FNext^) - 1;
      if i >= FCount then Break;
      FOut[i] := FFunc(FFirst + i);
    until False;
  except
    on E: Exception do Error := E.Message;
  end;
end;

procedure RenderFramesParallel(AFunc: TFrameFunc; ACount: Integer; ASink: TFrameSink; AIdle: TIdleProc);
var
  threads: array of TFrameThread;
  frames: array of TBGRABitmap;
  nThreads, batch, first, cnt, i: Integer;
  next: LongInt;
  err: string;
begin
  nThreads := Max(1, TThread.ProcessorCount);
  batch := nThreads * 2;
  SetLength(frames, batch);
  SetLength(threads, nThreads);
  first := 0;
  while first < ACount do
  begin
    cnt := Min(batch, ACount - first);
    FillChar(frames[0], SizeOf(Pointer) * batch, 0);
    next := 0;
    for i := 0 to nThreads - 1 do
      threads[i] := TFrameThread.Create(AFunc, @next, first, cnt, @frames[0]);
    err := '';
    for i := 0 to nThreads - 1 do
    begin
      while not threads[i].Finished do
      begin
        if Assigned(AIdle) then AIdle;
        Sleep(1);
      end;
      threads[i].WaitFor;
      if threads[i].Error <> '' then err := threads[i].Error;
      threads[i].Free;
    end;
    try
      if err <> '' then raise Exception.Create('Frame rendering failed: ' + err);
      for i := 0 to cnt - 1 do
        if Assigned(frames[i]) then ASink(first + i, frames[i]);
    finally
      for i := 0 to cnt - 1 do FreeAndNil(frames[i]);
    end;
    Inc(first, cnt);
  end;
end;

{ TGifWriter }

constructor TGifWriter.Create(AW, AH, ADelayMs: Integer);
begin
  inherited Create;
  FGif := TBGRAAnimatedGif.Create;
  FGif.SetSize(AW, AH);
  FGif.LoopCount := 0;  // loop forever
  FDelayMs := Max(10, ADelayMs);
end;

destructor TGifWriter.Destroy;
begin
  FGif.Free;
  inherited Destroy;
end;

procedure TGifWriter.Add(AFrame: TBGRABitmap);
begin
  FGif.AddFullFrame(AFrame, FDelayMs, True);
end;

procedure TGifWriter.Save(const AFileName: string);
begin
  FGif.SaveToFile(AFileName);
end;

initialization
  BGRAColorQuantizerFactory := TBGRAColorQuantizer;

end.
