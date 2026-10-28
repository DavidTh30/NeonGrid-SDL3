unit uSDLView;

{ SDL3 display window for the neon dot-grid background.

  Each frame (driven from the LCL idle loop, so the LCL info window and the
  SDL window share one main thread):
    1. poll SDL events (keys, close),
    2. collect the frame the BGRABitmap workers finished on all CPU cores
       during the previous present,
    3. immediately start the next frame on the workers,
    4. copy the finished bands into an SDL streaming texture
       (SDL_UpdateTexture, SDL_PIXELFORMAT_ARGB8888 = TBGRAPixel memory order),
    5. draw it with SDL_RenderTextureRotated and SDL_RenderPresent, which waits
       for the vertical blank when VSync is on (SDL_SetRenderVSync), so the
       frame rate follows the monitor: 60, 120, 144 Hz ... }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, GraphType, SDL3, BGRABitmap, BGRABitmapTypes,
  uParams, uRenderer;

type
  TSDLView = class
  private
    FWin: PSDL_Window;
    FRen: PSDL_Renderer;
    FTex: PSDL_Texture;
    FTexW, FTexH: Integer;
    FTexFlip: Boolean;
    FVSyncApplied: Integer;
    FLastTick, FFpsT0, FRefreshT, FSimTime: Double;
    FFpsFrames: Integer;
    FFullScreen, FRunning: Boolean;
    { --bench=SECONDS: record frame intervals, write a report, quit }
    FBenchSecs, FBenchT0: Double;
    FBench: array of Single;
    procedure BenchFrame(ANow, ADt: Double);
    procedure WriteBenchReport;
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure PollEvents;
    procedure HandleKey(AKey: TSDL_Keycode);
    procedure ApplyVSync;
    procedure UploadFrame;
    procedure UpdateRefreshRate;
  public
    Renderer: TNeonRenderer;
    constructor Create;
    destructor Destroy; override;
    procedure RenderFrame;
    procedure ToggleFullScreen;
    procedure ToggleInfo;
    function Left: Integer;
    function Top: Integer;
    function Width: Integer;
    function Height: Integer;
    property SimTime: Double read FSimTime;
    property FullScreen: Boolean read FFullScreen;
  end;

var
  View: TSDLView;

implementation

uses
  uInfoForm;

function SDLErr: string;
begin
  Result := StrPas(SDL_GetError);
end;

constructor TSDLView.Create;
var
  r: TSDL_Rect;
  w, h, ver: Integer;
begin
  inherited Create;
  if not SDL_Init(SDL_INIT_VIDEO) then
    raise Exception.Create('SDL_Init failed: ' + SDLErr);
  if not SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @r) then
  begin
    r.x := 0; r.y := 0; r.w := 1280; r.h := 900;
  end;
  h := Round(r.h * 0.88);
  w := Round(h * 9 / 16);
  FWin := SDL_CreateWindow('Neon Dot Grid - SDL3 + BGRABitmap   [F1 info  F11 fullscreen  Space pause]',
    w, h, SDL_WINDOW_RESIZABLE or SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if FWin = nil then raise Exception.Create('SDL_CreateWindow failed: ' + SDLErr);
  SDL_SetWindowPosition(FWin, r.x + 40, r.y + 40);
  FRen := SDL_CreateRenderer(FWin, nil);
  if FRen = nil then raise Exception.Create('SDL_CreateRenderer failed: ' + SDLErr);

  ver := SDL_GetVersion;
  Stats.GLVendor := Format('SDL %d.%d.%d', [ver div 1000000, (ver div 1000) mod 1000, ver mod 1000]);
  Stats.GLRenderer := StrPas(SDL_GetRendererName(FRen));
  Stats.GLVersion := 'SDL_Renderer, streaming texture, SDL_RenderPresent';
  if TBGRAPixel_RGBAOrder then
    Stats.TexFormat := 'SDL_PIXELFORMAT_ABGR8888 (= TBGRAPixel RGBA bytes)'
  else
    Stats.TexFormat := 'SDL_PIXELFORMAT_ARGB8888 (= TBGRAPixel BGRA bytes)';
  Stats.VSyncSupported := True;
  FVSyncApplied := -1;
  UpdateRefreshRate;

  Renderer := TNeonRenderer.Create;
  FRunning := True;
  for ver := 1 to ParamCount do
    if Pos('--bench=', ParamStr(ver)) = 1 then
      FBenchSecs := StrToFloatDef(Copy(ParamStr(ver), 9, 20), 10);
  Application.AddOnIdleHandler(@AppIdle);
end;

destructor TSDLView.Destroy;
begin
  Application.RemoveOnIdleHandler(@AppIdle);
  FreeAndNil(Renderer);
  if FTex <> nil then SDL_DestroyTexture(FTex);
  if FRen <> nil then SDL_DestroyRenderer(FRen);
  if FWin <> nil then SDL_DestroyWindow(FWin);
  SDL_Quit;
  inherited Destroy;
end;

procedure TSDLView.AppIdle(Sender: TObject; var Done: Boolean);
begin
  if FRunning then RenderFrame;
  Done := False;
end;

procedure TSDLView.HandleKey(AKey: TSDL_Keycode);
begin
  case AKey of
    SDLK_F1: ToggleInfo;
    SDLK_F11: ToggleFullScreen;
    SDLK_SPACE: P.Paused := not P.Paused;
    SDLK_ESCAPE: if FFullScreen then ToggleFullScreen;
  end;
end;

procedure TSDLView.PollEvents;
var
  e: TSDL_Event;
begin
  while SDL_PollEvent(@e) do
    case e._type of
      SDL_EVENT_QUIT, SDL_EVENT_WINDOW_CLOSE_REQUESTED:
        begin
          FRunning := False;
          Application.Terminate;
        end;
      SDL_EVENT_KEY_DOWN:
        if not e.key._repeat then HandleKey(e.key.key);
    end;
end;

procedure TSDLView.ApplyVSync;
var
  v: LongInt;
begin
  if Ord(P.VSync) = FVSyncApplied then Exit;
  FVSyncApplied := Ord(P.VSync);
  SDL_SetRenderVSync(FRen, FVSyncApplied);
  v := 0;
  SDL_GetRenderVSync(FRen, @v);
  Stats.VSyncActive := v <> 0;
end;

procedure TSDLView.UpdateRefreshRate;
var
  mode: PSDL_DisplayMode;
begin
  mode := SDL_GetCurrentDisplayMode(SDL_GetDisplayForWindow(FWin));
  if mode <> nil then Stats.RefreshHz := Round(mode^.refresh_rate);
end;

procedure TSDLView.UploadFrame;
var
  Geo: TFrameGeom;
  i, bh: Integer;
  wk: TRenderWorker;
  band: TBGRABitmap;
  rc: TSDL_Rect;
  fmt: TSDL_PixelFormat;
begin
  Geo := Renderer.ReadyGeom;
  if Geo.W <= 0 then Exit;
  if (FTex = nil) or (FTexW <> Geo.W) or (FTexH <> Geo.H) then
  begin
    if FTex <> nil then SDL_DestroyTexture(FTex);
    if TBGRAPixel_RGBAOrder then fmt := SDL_PIXELFORMAT_ABGR8888 else fmt := SDL_PIXELFORMAT_ARGB8888;
    FTex := SDL_CreateTexture(FRen, fmt, SDL_TEXTUREACCESS_STREAMING, Geo.W, Geo.H);
    FTexW := Geo.W;
    FTexH := Geo.H;
    if FTex = nil then Exit;
  end;
  if P.SmoothUpscale then
    SDL_SetTextureScaleMode(FTex, SDL_SCALEMODE_LINEAR)
  else
    SDL_SetTextureScaleMode(FTex, SDL_SCALEMODE_NEAREST);
  for i := 0 to Renderer.WorkerCount - 1 do
  begin
    wk := Renderer.Worker(i);
    band := wk.Bands[Renderer.ReadyBuf];
    bh := wk.Y1 - wk.Y0;
    if (band = nil) or (bh <= 0) or (band.Width <> Geo.W) then Continue;
    { bottom-up bands are uploaded as-is into a vertically flipped texture }
    FTexFlip := band.LineOrder = riloBottomToTop;
    rc.x := 0;
    rc.w := Geo.W;
    rc.h := bh;
    if FTexFlip then rc.y := Geo.H - wk.Y1 else rc.y := wk.Y0;
    SDL_UpdateTexture(FTex, @rc, band.Data, Geo.W * SizeOf(TBGRAPixel));
  end;
end;

procedure TSDLView.RenderFrame;
var
  w, h, rw, rh, i: Integer;
  tnow, dt, t0, t1, t2, t3, sum: Double;
  dst: TSDL_FRect;
begin
  PollEvents;
  if not FRunning or (Renderer = nil) then Exit;
  if (SDL_GetWindowFlags(FWin) and SDL_WINDOW_MINIMIZED) <> 0 then
  begin
    Sleep(15);
    Exit;
  end;
  ApplyVSync;
  w := 0;
  h := 0;
  SDL_GetWindowSizeInPixels(FWin, @w, @h);
  if (w < 4) or (h < 4) then Exit;

  tnow := HiResSeconds;
  if FLastTick = 0 then
  begin
    FLastTick := tnow;
    FFpsT0 := tnow;
    FRefreshT := tnow;
  end;
  dt := tnow - FLastTick;
  FLastTick := tnow;
  if not P.Paused then FSimTime += Min(dt, 0.1) * P.TimeScale;
  rw := Max(16, Round(w * P.RenderScale));
  rh := Max(16, Round(h * P.RenderScale));

  { 1. collect the frame rendered during the previous present }
  t0 := HiResSeconds;
  if not Renderer.Busy then Renderer.BeginFrame(rw, rh, FSimTime);
  Renderer.WaitFrame;
  t1 := HiResSeconds;
  { 2. start the next frame on all cores (workers write the other buffer) }
  Renderer.BeginFrame(rw, rh, FSimTime);
  { 3. upload the finished buffer to the SDL texture }
  UploadFrame;
  t2 := HiResSeconds;
  { 4. draw and present (waits for vblank when VSync is on) }
  SDL_SetRenderDrawColor(FRen, 0, 0, 0, 255);
  SDL_RenderClear(FRen);
  if FTex <> nil then
  begin
    dst.x := 0;
    dst.y := 0;
    dst.w := w;
    dst.h := h;
    if FTexFlip then
      SDL_RenderTextureRotated(FRen, FTex, nil, @dst, 0, nil, SDL_FLIP_VERTICAL)
    else
      SDL_RenderTexture(FRen, FTex, nil, @dst);
  end;
  SDL_RenderPresent(FRen);
  t3 := HiResSeconds;

  Stats.WaitMs := (t1 - t0) * 1000;
  Stats.UploadMs := (t2 - t1) * 1000;
  Stats.SwapMs := (t3 - t2) * 1000;
  Stats.CpuMs := Renderer.LastCpuMs;
  Stats.FrameMs := dt * 1000;
  Stats.ViewW := w; Stats.ViewH := h;
  Stats.RenderW := rw; Stats.RenderH := rh;
  Stats.History[Stats.HistPos] := dt * 1000;
  Stats.HistPos := (Stats.HistPos + 1) mod Length(Stats.History);
  Inc(Stats.Frames);
  Inc(FFpsFrames);
  if tnow - FFpsT0 >= 0.5 then
  begin
    Stats.FPS := FFpsFrames / (tnow - FFpsT0);
    FFpsFrames := 0;
    FFpsT0 := tnow;
    sum := 0;
    for i := 0 to High(Stats.History) do sum += Stats.History[i];
    if sum > 0 then Stats.MeasuredHz := 1000 * Length(Stats.History) / sum;
  end;
  if tnow - FRefreshT > 2 then
  begin
    FRefreshT := tnow;
    UpdateRefreshRate;
  end;
  if FBenchSecs > 0 then BenchFrame(tnow, dt);
end;

procedure TSDLView.BenchFrame(ANow, ADt: Double);
begin
  if FBenchT0 = 0 then FBenchT0 := ANow + 2;  // 2 s warm-up
  if ANow < FBenchT0 then Exit;
  SetLength(FBench, Length(FBench) + 1);
  FBench[High(FBench)] := ADt * 1000;
  if ANow - FBenchT0 >= FBenchSecs then
  begin
    WriteBenchReport;
    FRunning := False;
    Application.Terminate;
  end;
end;

procedure TSDLView.WriteBenchReport;
var
  sl: TStringList;
  sorted: array of Single;
  i, j, n, missed: Integer;
  sum, budget: Double;
  t: Single;
begin
  n := Length(FBench);
  if n = 0 then Exit;
  sorted := Copy(FBench);
  for i := 1 to n - 1 do  // insertion sort, n is small
  begin
    t := sorted[i];
    j := i - 1;
    while (j >= 0) and (sorted[j] > t) do
    begin
      sorted[j + 1] := sorted[j];
      Dec(j);
    end;
    sorted[j + 1] := t;
  end;
  sum := 0;
  for i := 0 to n - 1 do sum += FBench[i];
  if Stats.RefreshHz > 1 then budget := 1000 / Stats.RefreshHz else budget := 1000 / 60;
  missed := 0;
  for i := 0 to n - 1 do
    if FBench[i] > budget * 1.5 then Inc(missed);
  sl := TStringList.Create;
  try
    sl.Add('Neon Dot Grid SDL3 benchmark  ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    sl.Add(Format('backend %s, %s, vsync %s, monitor %d Hz', [Stats.GLRenderer, Stats.GLVendor,
      BoolToStr(Stats.VSyncActive, 'on', 'off'), Stats.RefreshHz]));
    sl.Add(Format('window %d x %d, render %d x %d, threads %d, fullscreen %s',
      [Stats.ViewW, Stats.ViewH, Stats.RenderW, Stats.RenderH, Renderer.WorkerCount,
       BoolToStr(FFullScreen, 'yes', 'no')]));
    sl.Add(Format('frames %d in %.1f s  ->  %.2f fps', [n, sum / 1000, n * 1000 / sum]));
    sl.Add(Format('interval ms: mean %.2f  median %.2f  p99 %.2f  max %.2f', [sum / n,
      sorted[n div 2], sorted[Min(n - 1, Round(n * 0.99))], sorted[n - 1]]));
    sl.Add(Format('frames over 1.5x budget (missed vblank): %d (%.2f%%)', [missed, missed * 100 / n]));
    sl.Add(Format('last CPU render %.2f ms on all threads', [Stats.CpuMs]));
    if Assigned(InfoForm) then
      sl.Add(Format('info window: visible %s, perf paints %d (max %.1f ms), timer tick max %.1f ms',
        [BoolToStr(InfoForm.Visible, 'yes', 'no'), InfoForm.PaintCount, InfoForm.PaintMsMax, InfoForm.TickMsMax]));
    if Assigned(InfoForm) and (InfoForm.PaintCount > 0) then
      sl.Add(Format('info paint avg %.1f ms', [InfoForm.PaintMsSum / InfoForm.PaintCount]));
    sl.SaveToFile(ChangeFileExt(ParamStr(0), '-bench.txt'));
  finally
    sl.Free;
  end;
end;

procedure TSDLView.ToggleFullScreen;
begin
  FFullScreen := not FFullScreen;
  SDL_SetWindowFullscreen(FWin, FFullScreen);  // borderless desktop fullscreen
  if Assigned(InfoForm) then
    if FFullScreen then InfoForm.FormStyle := fsStayOnTop else InfoForm.FormStyle := fsNormal;
end;

procedure TSDLView.ToggleInfo;
begin
  if not Assigned(InfoForm) then Exit;
  InfoForm.Visible := not InfoForm.Visible;
  if InfoForm.Visible then InfoForm.BringToFront else SDL_RaiseWindow(FWin);
end;

function TSDLView.Left: Integer;
var
  x, y: LongInt;
begin
  SDL_GetWindowPosition(FWin, @x, @y);
  Result := x;
end;

function TSDLView.Top: Integer;
var
  x, y: LongInt;
begin
  SDL_GetWindowPosition(FWin, @x, @y);
  Result := y;
end;

function TSDLView.Width: Integer;
var
  w, h: LongInt;
begin
  SDL_GetWindowSize(FWin, @w, @h);
  Result := w;
end;

function TSDLView.Height: Integer;
var
  w, h: LongInt;
begin
  SDL_GetWindowSize(FWin, @w, @h);
  Result := h;
end;

end.
