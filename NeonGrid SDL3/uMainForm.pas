unit uMainForm;

{ Main window: a TOpenGLControl showing the CPU-rendered background.
  Each paint: collect the frame the workers finished during the previous
  vsync wait, upload its bands with glTexSubImage2D, immediately start the
  next frame on all cores, draw a textured quad and SwapBuffers (vsync). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, Math, Forms, Controls, Graphics, LCLType, GraphType,
  OpenGLContext, GL, BGRABitmap, BGRABitmapTypes, uParams, uRenderer;

type
  TMainForm = class(TForm)
  private
    FGL: TOpenGLControl;
    FTex: GLuint;
    FTexW, FTexH: Integer;
    FTexTopDown: Boolean;
    FGLReady: Boolean;
    FVSyncApplied: Integer;
    FLastTick, FFpsT0, FRefreshT: Double;
    FFpsFrames: Integer;
    FSimTime: Double;
    FFullScreen: Boolean;
    FSavedBounds: TRect;
    { --bench=SECONDS: record frame intervals, write a report, quit }
    FBenchSecs, FBenchT0: Double;
    FBench: array of Single;
    procedure BenchFrame(ANow, ADt: Double);
    procedure WriteBenchReport;
    procedure GLPaint(Sender: TObject);
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure DoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure InitGL;
    procedure ApplyVSync;
    procedure UploadFrame;
    procedure DrawQuad(AW, AH: Integer);
    procedure UpdateRefreshRate;
  public
    Renderer: TNeonRenderer;
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure ToggleFullScreen;
    procedure ToggleInfo;
    property SimTime: Double read FSimTime;
  end;

var
  MainForm: TMainForm;

implementation

uses
  uInfoForm;

const
  GL_BGRA_EXT = $80E1;
  GL_CLAMP_TO_EDGE_ = $812F;

{$IFDEF WINDOWS}
type
  TSwapIntervalEXT = function(AInterval: LongInt): LongBool; stdcall;
  TGetSwapIntervalEXT = function: LongInt; stdcall;

var
  wglSwapIntervalEXT: TSwapIntervalEXT = nil;
  wglGetSwapIntervalEXT: TGetSwapIntervalEXT = nil;
{$ENDIF}

constructor TMainForm.Create(TheOwner: TComponent);
var
  h: Integer;
begin
  inherited CreateNew(TheOwner, 0);
  Caption := 'Neon Dot Grid  -  BGRABitmap x ' + IntToStr(TThread.ProcessorCount) +
    ' cores + OpenGL   [F1 info  F11 fullscreen  Space pause]';
  h := Round(Screen.WorkAreaHeight * 0.88);
  SetBounds(Screen.WorkAreaLeft + 40, Screen.WorkAreaTop + 16, Round(h * 9 / 16), h);
  Color := clBlack;
  KeyPreview := True;
  OnKeyDown := @DoKeyDown;

  FGL := TOpenGLControl.Create(Self);
  FGL.Parent := Self;
  FGL.Align := alClient;
  FGL.AutoResizeViewport := False;
  FGL.OnPaint := @GLPaint;

  Renderer := TNeonRenderer.Create;
  FVSyncApplied := -1;
  for h := 1 to ParamCount do
    if Pos('--bench=', ParamStr(h)) = 1 then
      FBenchSecs := StrToFloatDef(Copy(ParamStr(h), 9, 20), 10);
  Application.AddOnIdleHandler(@AppIdle);
end;

destructor TMainForm.Destroy;
begin
  Application.RemoveOnIdleHandler(@AppIdle);
  FreeAndNil(Renderer);
  inherited Destroy;
end;

procedure TMainForm.AppIdle(Sender: TObject; var Done: Boolean);
begin
  if Assigned(Renderer) and Assigned(FGL) and (WindowState <> wsMinimized) then
    FGL.Invalidate;
  Done := False;
end;

procedure TMainForm.InitGL;
begin
  FGL.MakeCurrent;
  if FTex <> 0 then glDeleteTextures(1, @FTex);
  glGenTextures(1, @FTex);
  glBindTexture(GL_TEXTURE_2D, FTex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE_);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE_);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  FTexW := 0;
  FTexH := 0;
  Stats.GLVendor := StrPas(PChar(glGetString(GL_VENDOR)));
  Stats.GLRenderer := StrPas(PChar(glGetString(GL_RENDERER)));
  Stats.GLVersion := StrPas(PChar(glGetString(GL_VERSION)));
  if TBGRAPixel_RGBAOrder then
    Stats.TexFormat := 'GL_RGBA / GL_UNSIGNED_BYTE'
  else
    Stats.TexFormat := 'GL_BGRA / GL_UNSIGNED_BYTE';
  {$IFDEF WINDOWS}
  Pointer(wglSwapIntervalEXT) := wglGetProcAddress('wglSwapIntervalEXT');
  Pointer(wglGetSwapIntervalEXT) := wglGetProcAddress('wglGetSwapIntervalEXT');
  Stats.VSyncSupported := Assigned(wglSwapIntervalEXT);
  {$ELSE}
  Stats.VSyncSupported := False;
  {$ENDIF}
  FVSyncApplied := -1;
  UpdateRefreshRate;
  FGLReady := True;
end;

procedure TMainForm.ApplyVSync;
var
  want: Integer;
begin
  want := Ord(P.VSync);
  if want = FVSyncApplied then Exit;
  FVSyncApplied := want;
  {$IFDEF WINDOWS}
  if Assigned(wglSwapIntervalEXT) then wglSwapIntervalEXT(want);
  if Assigned(wglGetSwapIntervalEXT) then
    Stats.VSyncActive := wglGetSwapIntervalEXT() > 0
  else
    Stats.VSyncActive := Stats.VSyncSupported and P.VSync;
  {$ELSE}
  Stats.VSyncActive := False;
  {$ENDIF}
end;

procedure TMainForm.UpdateRefreshRate;
{$IFDEF WINDOWS}
var
  dm: TDevMode;
{$ENDIF}
begin
  Stats.RefreshHz := 0;
  {$IFDEF WINDOWS}
  FillChar(dm, SizeOf(dm), 0);
  dm.dmSize := SizeOf(dm);
  if EnumDisplaySettings(nil, DWORD(-1), @dm) then
    Stats.RefreshHz := dm.dmDisplayFrequency;
  {$ENDIF}
end;

procedure TMainForm.UploadFrame;
var
  G: TFrameGeom;
  i, yoff, bh: Integer;
  w: TRenderWorker;
  band: TBGRABitmap;
  fmt: GLenum;
begin
  G := Renderer.ReadyGeom;
  if G.W <= 0 then Exit;
  if TBGRAPixel_RGBAOrder then fmt := GL_RGBA else fmt := GL_BGRA_EXT;
  glBindTexture(GL_TEXTURE_2D, FTex);
  if (FTexW <> G.W) or (FTexH <> G.H) then
  begin
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, G.W, G.H, 0, fmt, GL_UNSIGNED_BYTE, nil);
    FTexW := G.W;
    FTexH := G.H;
  end;
  for i := 0 to Renderer.WorkerCount - 1 do
  begin
    w := Renderer.Worker(i);
    band := w.Bands[Renderer.ReadyBuf];
    bh := w.Y1 - w.Y0;
    if (band = nil) or (bh <= 0) or (band.Width <> G.W) then Continue;
    FTexTopDown := band.LineOrder = riloTopToBottom;
    if FTexTopDown then yoff := w.Y0 else yoff := G.H - w.Y1;
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, yoff, G.W, bh, fmt, GL_UNSIGNED_BYTE, band.Data);
  end;
end;

procedure TMainForm.DrawQuad(AW, AH: Integer);
var
  t0, t1: Single;
  filt: GLint;
begin
  glViewport(0, 0, AW, AH);
  glClearColor(0, 0, 0, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, 1, 0, 1, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  if FTexW = 0 then Exit;
  glEnable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, FTex);
  if P.SmoothUpscale then filt := GL_LINEAR else filt := GL_NEAREST;
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filt);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filt);
  { texture row 0 = image top when bands are top-down, else image bottom }
  if FTexTopDown then begin t0 := 1; t1 := 0; end else begin t0 := 0; t1 := 1; end;
  glColor4f(1, 1, 1, 1);
  glBegin(GL_QUADS);
    glTexCoord2f(0, t0); glVertex2f(0, 0);
    glTexCoord2f(1, t0); glVertex2f(1, 0);
    glTexCoord2f(1, t1); glVertex2f(1, 1);
    glTexCoord2f(0, t1); glVertex2f(0, 1);
  glEnd;
  glDisable(GL_TEXTURE_2D);
end;

procedure TMainForm.GLPaint(Sender: TObject);
var
  w, h, rw, rh, i: Integer;
  tnow, dt, t0, t1, t2, t3, sum: Double;
begin
  if Renderer = nil then Exit;
  if not FGLReady then InitGL;
  ApplyVSync;
  w := FGL.Width;
  h := FGL.Height;
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

  { 1. collect the frame rendered during the previous upload + vsync wait }
  t0 := HiResSeconds;
  if not Renderer.Busy then Renderer.BeginFrame(rw, rh, FSimTime);
  Renderer.WaitFrame;
  t1 := HiResSeconds;
  { 2. start the next frame on all cores (workers write the other buffer) }
  Renderer.BeginFrame(rw, rh, FSimTime);
  { 3. meanwhile upload the finished buffer, then present (blocks on vsync) }
  UploadFrame;
  t2 := HiResSeconds;
  DrawQuad(w, h);
  FGL.SwapBuffers;
  if P.GpuSync then glFinish;
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

procedure TMainForm.BenchFrame(ANow, ADt: Double);
begin
  if FBenchT0 = 0 then FBenchT0 := ANow + 2;  // 2 s warm-up
  if ANow < FBenchT0 then Exit;
  SetLength(FBench, Length(FBench) + 1);
  FBench[High(FBench)] := ADt * 1000;
  if ANow - FBenchT0 >= FBenchSecs then
  begin
    WriteBenchReport;
    FBenchSecs := 0;
    Application.Terminate;
  end;
end;

procedure TMainForm.WriteBenchReport;
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
    sl.Add('Neon Dot Grid OpenGL benchmark  ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    sl.Add(Format('renderer %s, vsync %s, gpu sync %s, monitor %d Hz', [Stats.GLRenderer,
      BoolToStr(Stats.VSyncActive, 'on', 'off'), BoolToStr(P.GpuSync, 'on', 'off'), Stats.RefreshHz]));
    sl.Add(Format('window %d x %d, render %d x %d, threads %d, fullscreen %s',
      [Stats.ViewW, Stats.ViewH, Stats.RenderW, Stats.RenderH, Renderer.WorkerCount,
       BoolToStr(FFullScreen, 'yes', 'no')]));
    sl.Add(Format('frames %d in %.1f s  ->  %.2f fps', [n, sum / 1000, n * 1000 / sum]));
    sl.Add(Format('interval ms: mean %.2f  median %.2f  p99 %.2f  max %.2f', [sum / n,
      sorted[n div 2], sorted[Min(n - 1, Round(n * 0.99))], sorted[n - 1]]));
    sl.Add(Format('frames over 1.5x budget (missed vblank): %d (%.2f%%)', [missed, missed * 100 / n]));
    sl.Add(Format('last CPU render %.2f ms on all threads', [Stats.CpuMs]));
    if Assigned(InfoForm) then
      sl.Add(Format('info window: visible %s, tab %d, perf paints %d (max %.1f ms), timer tick max %.1f ms',
        [BoolToStr(InfoForm.Visible, 'yes', 'no'), InfoForm.ActiveTab, InfoForm.PaintCount,
         InfoForm.PaintMsMax, InfoForm.TickMsMax]));
    if Assigned(InfoForm) and (InfoForm.PaintCount > 0) then
      sl.Add(Format('info paint avg %.1f ms', [InfoForm.PaintMsSum / InfoForm.PaintCount]));
    sl.SaveToFile(ChangeFileExt(ParamStr(0), '-bench.txt'));
  finally
    sl.Free;
  end;
end;

procedure TMainForm.ToggleFullScreen;
begin
  if not FFullScreen then
  begin
    FSavedBounds := BoundsRect;
    BorderStyle := bsNone;
    BoundsRect := Monitor.BoundsRect;
    FFullScreen := True;
    if Assigned(InfoForm) then InfoForm.FormStyle := fsStayOnTop;
  end
  else
  begin
    BorderStyle := bsSizeable;
    BoundsRect := FSavedBounds;
    FFullScreen := False;
    if Assigned(InfoForm) then InfoForm.FormStyle := fsNormal;
  end;
  FGLReady := False;  // the GL context may be recreated with the window
end;

procedure TMainForm.ToggleInfo;
begin
  if Assigned(InfoForm) then
  begin
    InfoForm.Visible := not InfoForm.Visible;
    if InfoForm.Visible then InfoForm.BringToFront;
  end;
end;

procedure TMainForm.DoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_F1: ToggleInfo;
    VK_F11: ToggleFullScreen;
    VK_RETURN: if ssAlt in Shift then ToggleFullScreen;
    VK_SPACE: P.Paused := not P.Paused;
    VK_ESCAPE: if FFullScreen then ToggleFullScreen;
  else
    Exit;
  end;
  Key := 0;
end;

end.
