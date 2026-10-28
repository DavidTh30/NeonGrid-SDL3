unit uGPUView;

{ SDL3 GPU display of the neon dot-grid background: the whole image is
  rendered by shaders (SDL_gpu, Direct3D 12 backend, DXIL or DXBC).

  Per frame (driven from the LCL idle loop, like the SDL3 CPU version):
    1. wait for a swapchain image (SDL_WaitAndAcquireGPUSwapchainTexture:
       paced by VSync),
    2. CPU: geometry + uniforms; when sprite parameters change, the dot sprite
       is rebuilt with BGRABitmap (TNeonRenderer) and uploaded as an RGBA16F
       texture (fill, ring+glow, sparks weights),
    3. pass 1  dots_ps.hlsl       NCols x NRows dot states -> RGBA16F texture,
    4. pass 2  composite_ps.hlsl  every pixel: sprite x nearby dots + haze +
                                  vignette -> frame texture (render scale),
    5. SDL_BlitGPUTexture frame -> swapchain, submit.
  The frame texture is also what "Capture PNG" downloads. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, SDL3, BGRABitmap, BGRABitmapTypes,
  uParams, uRenderer, uGPUShaders;

type
  TVec4 = array[0..3] of Single;

  TDotUniforms = record
    Grid, Frame, Field0, Ambient: TVec4;
    BlobPos, BlobAnim, BlobCol: array[0..MaxBlobs - 1] of TVec4;
    Bound0, Bound1, BoundCol, Shadow, Jitter, Sparkle, Trail0, Trail1, Highlight: TVec4;
    Palette: array[0..PaletteSize - 1] of TVec4;
  end;

  TCompositeUniforms = record
    Grid, Frame, Sprite, Ring, HiCol, Bg, Spark, Vig: TVec4;
  end;

  TGPUView = class
  private
    FWin: PSDL_Window;
    FDev: PSDL_GPUDevice;
    FShaderFormat: TSDL_GPUShaderFormat;
    FSwapFormat: TSDL_GPUTextureFormat;
    FVS, FDotsFS, FCompFS: PSDL_GPUShader;
    FDotsPipe, FCompPipe: PSDL_GPUGraphicsPipeline;
    FSampler: PSDL_GPUSampler;
    FDotTex, FSprTex, FFrameTex: PSDL_GPUTexture;
    FDotW, FDotH, FSprN, FFrameW, FFrameH: Integer;
    FSprRebuilds: Integer;
    FPresentApplied: Integer;
    FLastTick, FFpsT0, FRefreshT, FSimTime: Double;
    FFpsFrames: Integer;
    FFullScreen, FRunning: Boolean;
    FBenchSecs, FBenchT0: Double;
    FBench: array of Single;
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure PollEvents;
    procedure HandleKey(AKey: TSDL_Keycode);
    procedure ApplyPresentMode;
    procedure UpdateRefreshRate;
    function MakeShader(const ACode; ASize: Integer; AStage: TSDL_GPUShaderStage;
      ASamplers, AUniforms: Integer): PSDL_GPUShader;
    function MakePipeline(AFrag: PSDL_GPUShader; AFormat: TSDL_GPUTextureFormat): PSDL_GPUGraphicsPipeline;
    function MakeTexture(AW, AH: Integer; AFormat: TSDL_GPUTextureFormat;
      AUsage: TSDL_GPUTextureUsageFlags): PSDL_GPUTexture;
    procedure EnsureTextures(const Geo: TFrameGeom; ARW, ARH: Integer);
    procedure UploadSprite(ACmd: PSDL_GPUCommandBuffer);
    procedure FillUniforms(const Geo: TFrameGeom; out D: TDotUniforms; out C: TCompositeUniforms);
    procedure BenchFrame(ANow, ADt: Double);
    procedure WriteBenchReport;
  public
    Renderer: TNeonRenderer;  // colour model, BGRABitmap sprites, previews, CPU exports
    constructor Create;
    destructor Destroy; override;
    procedure RenderFrame;
    procedure ToggleFullScreen;
    procedure ToggleInfo;
    { downloads the last rendered frame from the GPU }
    function CaptureFrame: TBGRABitmap;
    function CaptureThumb(AW, AH: Integer): TBGRABitmap;
    function Left: Integer;
    function Top: Integer;
    function Width: Integer;
    function Height: Integer;
    property SimTime: Double read FSimTime;
    property FullScreen: Boolean read FFullScreen;
  end;

var
  View: TGPUView;

implementation

uses
  uInfoForm;

function SDLErr: string;
begin
  Result := StrPas(SDL_GetError);
end;

function V4(a, b, c, d: Single): TVec4;
begin
  Result[0] := a; Result[1] := b; Result[2] := c; Result[3] := d;
end;

function C4(const C: TBGRAPixel; w: Single): TVec4;
begin
  Result := V4(C.red, C.green, C.blue, w);
end;

function FloatToHalf(f: Single): Word;
var
  x, m: LongWord;
  e: Integer;
begin
  x := PLongWord(@f)^;
  Result := (x shr 16) and $8000;
  e := Integer((x shr 23) and $FF) - 127 + 15;
  m := x and $7FFFFF;
  if e <= 0 then Exit;                     // tiny -> 0
  if e >= 31 then Exit(Result or $7C00);   // huge -> inf
  Result := Result or Word(e shl 10) or Word(m shr 13);
  if (m and $1000) <> 0 then Inc(Result);  // round
end;

{ TGPUView }

constructor TGPUView.Create;
var
  r: TSDL_Rect;
  w, h, ver, i: Integer;
  si: TSDL_GPUSamplerCreateInfo;
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
  FWin := SDL_CreateWindow('Neon Dot Grid - SDL3 GPU shaders   [F1 info  F11 fullscreen  Space pause]',
    w, h, SDL_WINDOW_RESIZABLE or SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if FWin = nil then raise Exception.Create('SDL_CreateWindow failed: ' + SDLErr);
  SDL_SetWindowPosition(FWin, r.x + 40, r.y + 40);

  FDev := SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_DXIL or SDL_GPU_SHADERFORMAT_DXBC, False, nil);
  if FDev = nil then
    raise Exception.Create('SDL_CreateGPUDevice failed (needs Direct3D 12): ' + SDLErr);
  if not SDL_ClaimWindowForGPUDevice(FDev, FWin) then
    raise Exception.Create('SDL_ClaimWindowForGPUDevice failed: ' + SDLErr);
  if (SDL_GetGPUShaderFormats(FDev) and SDL_GPU_SHADERFORMAT_DXIL) <> 0 then
    FShaderFormat := SDL_GPU_SHADERFORMAT_DXIL
  else
    FShaderFormat := SDL_GPU_SHADERFORMAT_DXBC;
  FSwapFormat := SDL_GetGPUSwapchainTextureFormat(FDev, FWin);

  if FShaderFormat = SDL_GPU_SHADERFORMAT_DXIL then
  begin
    FVS := MakeShader(FullscreenVS_DXIL, SizeOf(FullscreenVS_DXIL), SDL_GPU_SHADERSTAGE_VERTEX, 0, 0);
    FDotsFS := MakeShader(DotsPS_DXIL, SizeOf(DotsPS_DXIL), SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 1);
    FCompFS := MakeShader(CompositePS_DXIL, SizeOf(CompositePS_DXIL), SDL_GPU_SHADERSTAGE_FRAGMENT, 2, 1);
  end
  else
  begin
    FVS := MakeShader(FullscreenVS_DXBC, SizeOf(FullscreenVS_DXBC), SDL_GPU_SHADERSTAGE_VERTEX, 0, 0);
    FDotsFS := MakeShader(DotsPS_DXBC, SizeOf(DotsPS_DXBC), SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 1);
    FCompFS := MakeShader(CompositePS_DXBC, SizeOf(CompositePS_DXBC), SDL_GPU_SHADERSTAGE_FRAGMENT, 2, 1);
  end;
  FDotsPipe := MakePipeline(FDotsFS, SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT);
  FCompPipe := MakePipeline(FCompFS, SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM);

  FillChar(si, SizeOf(si), 0);
  si.min_filter := SDL_GPU_FILTER_LINEAR;
  si.mag_filter := SDL_GPU_FILTER_LINEAR;
  si.mipmap_mode := SDL_GPU_SAMPLERMIPMAPMODE_NEAREST;
  si.address_mode_u := SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
  si.address_mode_v := SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
  si.address_mode_w := SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
  FSampler := SDL_CreateGPUSampler(FDev, @si);
  if FSampler = nil then raise Exception.Create('SDL_CreateGPUSampler failed: ' + SDLErr);

  ver := SDL_GetVersion;
  Stats.GLVendor := Format('SDL %d.%d.%d GPU API', [ver div 1000000, (ver div 1000) mod 1000, ver mod 1000]);
  Stats.GLRenderer := StrPas(SDL_GetGPUDeviceDriver(FDev));
  if FShaderFormat = SDL_GPU_SHADERFORMAT_DXIL then
    Stats.GLVersion := 'shaders: DXIL (Shader Model 6.0, dxc)'
  else
    Stats.GLVersion := 'shaders: DXBC (Shader Model 5.1, fxc)';
  Stats.TexFormat := 'frame B8G8R8A8_UNORM -> SDL_BlitGPUTexture -> swapchain';
  Stats.VSyncSupported := True;
  FPresentApplied := -1;
  FSprRebuilds := -1;
  UpdateRefreshRate;

  Renderer := TNeonRenderer.Create;
  FRunning := True;
  for i := 1 to ParamCount do
    if Pos('--bench=', ParamStr(i)) = 1 then
      FBenchSecs := StrToFloatDef(Copy(ParamStr(i), 9, 20), 10);
  Application.AddOnIdleHandler(@AppIdle);
end;

destructor TGPUView.Destroy;
begin
  Application.RemoveOnIdleHandler(@AppIdle);
  FreeAndNil(Renderer);
  if FDev <> nil then
  begin
    SDL_WaitForGPUIdle(FDev);
    if FDotTex <> nil then SDL_ReleaseGPUTexture(FDev, FDotTex);
    if FSprTex <> nil then SDL_ReleaseGPUTexture(FDev, FSprTex);
    if FFrameTex <> nil then SDL_ReleaseGPUTexture(FDev, FFrameTex);
    if FSampler <> nil then SDL_ReleaseGPUSampler(FDev, FSampler);
    if FDotsPipe <> nil then SDL_ReleaseGPUGraphicsPipeline(FDev, FDotsPipe);
    if FCompPipe <> nil then SDL_ReleaseGPUGraphicsPipeline(FDev, FCompPipe);
    if FVS <> nil then SDL_ReleaseGPUShader(FDev, FVS);
    if FDotsFS <> nil then SDL_ReleaseGPUShader(FDev, FDotsFS);
    if FCompFS <> nil then SDL_ReleaseGPUShader(FDev, FCompFS);
    if FWin <> nil then SDL_ReleaseWindowFromGPUDevice(FDev, FWin);
    SDL_DestroyGPUDevice(FDev);
  end;
  if FWin <> nil then SDL_DestroyWindow(FWin);
  SDL_Quit;
  inherited Destroy;
end;

function TGPUView.MakeShader(const ACode; ASize: Integer; AStage: TSDL_GPUShaderStage;
  ASamplers, AUniforms: Integer): PSDL_GPUShader;
var
  ci: TSDL_GPUShaderCreateInfo;
begin
  FillChar(ci, SizeOf(ci), 0);
  ci.code_size := ASize;
  ci.code := @ACode;
  ci.entrypoint := 'main';
  ci.format := FShaderFormat;
  ci.stage := AStage;
  ci.num_samplers := ASamplers;
  ci.num_uniform_buffers := AUniforms;
  Result := SDL_CreateGPUShader(FDev, @ci);
  if Result = nil then raise Exception.Create('SDL_CreateGPUShader failed: ' + SDLErr);
end;

function TGPUView.MakePipeline(AFrag: PSDL_GPUShader; AFormat: TSDL_GPUTextureFormat): PSDL_GPUGraphicsPipeline;
var
  pi: TSDL_GPUGraphicsPipelineCreateInfo;
  ctd: TSDL_GPUColorTargetDescription;
begin
  FillChar(ctd, SizeOf(ctd), 0);
  ctd.format := AFormat;
  FillChar(pi, SizeOf(pi), 0);
  pi.vertex_shader := FVS;
  pi.fragment_shader := AFrag;
  pi.primitive_type := SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
  pi.rasterizer_state.fill_mode := SDL_GPU_FILLMODE_FILL;
  pi.rasterizer_state.cull_mode := SDL_GPU_CULLMODE_NONE;
  pi.multisample_state.sample_count := SDL_GPU_SAMPLECOUNT_1;
  pi.target_info.color_target_descriptions := @ctd;
  pi.target_info.num_color_targets := 1;
  Result := SDL_CreateGPUGraphicsPipeline(FDev, @pi);
  if Result = nil then raise Exception.Create('SDL_CreateGPUGraphicsPipeline failed: ' + SDLErr);
end;

function TGPUView.MakeTexture(AW, AH: Integer; AFormat: TSDL_GPUTextureFormat;
  AUsage: TSDL_GPUTextureUsageFlags): PSDL_GPUTexture;
var
  ti: TSDL_GPUTextureCreateInfo;
begin
  FillChar(ti, SizeOf(ti), 0);
  ti._type := SDL_GPU_TEXTURETYPE_2D;
  ti.format := AFormat;
  ti.usage := AUsage;
  ti.Width := Max(1, AW);
  ti.Height := Max(1, AH);
  ti.layer_count_or_depth := 1;
  ti.num_levels := 1;
  ti.sample_count := SDL_GPU_SAMPLECOUNT_1;
  Result := SDL_CreateGPUTexture(FDev, @ti);
  if Result = nil then raise Exception.Create('SDL_CreateGPUTexture failed: ' + SDLErr);
end;

procedure TGPUView.EnsureTextures(const Geo: TFrameGeom; ARW, ARH: Integer);
begin
  if (FDotTex = nil) or (FDotW <> Geo.NCols) or (FDotH <> Geo.NRows) then
  begin
    if FDotTex <> nil then SDL_ReleaseGPUTexture(FDev, FDotTex);
    FDotTex := MakeTexture(Geo.NCols, Geo.NRows, SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
      SDL_GPU_TEXTUREUSAGE_COLOR_TARGET or SDL_GPU_TEXTUREUSAGE_SAMPLER);
    FDotW := Geo.NCols;
    FDotH := Geo.NRows;
  end;
  if (FFrameTex = nil) or (FFrameW <> ARW) or (FFrameH <> ARH) then
  begin
    if FFrameTex <> nil then SDL_ReleaseGPUTexture(FDev, FFrameTex);
    FFrameTex := MakeTexture(ARW, ARH, SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
      SDL_GPU_TEXTUREUSAGE_COLOR_TARGET or SDL_GPU_TEXTUREUSAGE_SAMPLER);
    FFrameW := ARW;
    FFrameH := ARH;
  end;
end;

procedure TGPUView.UploadSprite(ACmd: PSDL_GPUCommandBuffer);
var
  n, i: Integer;
  tb: PSDL_GPUTransferBuffer;
  tbi: TSDL_GPUTransferBufferCreateInfo;
  src: PSpriteTexel;
  dst: PWord;
  cp: PSDL_GPUCopyPass;
  tti: TSDL_GPUTextureTransferInfo;
  reg: TSDL_GPUTextureRegion;
begin
  { the sprite channels (8.8 fixed point weights) as an RGBA16F texture }
  n := Renderer.SpriteSize;
  src := Renderer.SpriteTexels;
  if (n <= 0) or (src = nil) then Exit;
  if (FSprTex = nil) or (FSprN <> n) then
  begin
    if FSprTex <> nil then SDL_ReleaseGPUTexture(FDev, FSprTex);
    FSprTex := MakeTexture(n, n, SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT, SDL_GPU_TEXTUREUSAGE_SAMPLER);
    FSprN := n;
  end;
  FillChar(tbi, SizeOf(tbi), 0);
  tbi.usage := SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
  tbi.size := n * n * 8;
  tb := SDL_CreateGPUTransferBuffer(FDev, @tbi);
  if tb = nil then Exit;
  dst := SDL_MapGPUTransferBuffer(FDev, tb, False);
  for i := 0 to n * n - 1 do
  begin
    dst[0] := FloatToHalf(src^.A / 256);
    dst[1] := FloatToHalf(src^.B / 256);
    dst[2] := FloatToHalf(src^.C / 256);
    dst[3] := 0;
    Inc(dst, 4);
    Inc(src);
  end;
  SDL_UnmapGPUTransferBuffer(FDev, tb);
  cp := SDL_BeginGPUCopyPass(ACmd);
  FillChar(tti, SizeOf(tti), 0);
  tti.transfer_buffer := tb;
  FillChar(reg, SizeOf(reg), 0);
  reg.texture := FSprTex;
  reg.w := n;
  reg.h := n;
  reg.d := 1;
  SDL_UploadToGPUTexture(cp, @tti, @reg, False);
  SDL_EndGPUCopyPass(cp);
  SDL_ReleaseGPUTransferBuffer(FDev, tb);  // freed once the GPU is done with it
  FSprRebuilds := Renderer.SpriteRebuilds;
end;

procedure TGPUView.FillUniforms(const Geo: TFrameGeom; out D: TDotUniforms; out C: TCompositeUniforms);
var
  i: Integer;
  t: Single;
begin
  FillChar(D, SizeOf(D), 0);
  FillChar(C, SizeOf(C), 0);
  t := Geo.Time;
  D.Grid := V4(Geo.Cell, Geo.OriginX, Geo.OriginY, t);
  D.Frame := V4(Geo.W, Geo.H, Geo.ShiftI, Geo.ShiftJ);
  D.Field0 := V4(P.AmbientWeight, P.FieldBrightness, P.FieldSaturation, 0);
  D.Ambient := C4(P.AmbientColor, 0);
  for i := 0 to MaxBlobs - 1 do
    with P.Blobs[i] do
    begin
      D.BlobPos[i] := V4(X, Y, Radius, Weight);
      D.BlobAnim[i] := V4(DriftAmp, DriftSpeed, Ord(Enabled), 0);
      D.BlobCol[i] := C4(Color, 0);
    end;
  D.Bound0 := V4(P.BoundaryTopX, P.BoundaryBottomX, P.BoundarySoftness, P.BoundaryStrength);
  D.Bound1 := V4(P.BoundaryWaveAmp, P.BoundaryWaveFreq, P.BoundaryWaveSpeed, Ord(P.BoundaryOn));
  D.BoundCol := C4(P.BoundaryColor, 0);
  if P.ShadowOn then
    D.Shadow := V4(P.ShadowX, P.ShadowY, P.ShadowRadius, P.ShadowStrength);
  D.Jitter := V4(P.JitterBrightness, P.JitterHue, P.JitterSpeed, 0);
  D.Sparkle := V4(Ord(P.SparkleOn), P.SparkleProb, P.SparkleSpeed, P.SparkleIntensity);
  D.Trail0 := V4(Ord(P.TrailOn), P.TrailOffset, P.TrailWidth, P.TrailSpeed);
  D.Trail1 := V4(P.TrailIntensity, P.TrailDensity, 0, 0);
  D.Highlight := V4(Ord(P.HighlightOn), P.HighlightProb, P.HighlightSpeed, 0);
  for i := 0 to PaletteSize - 1 do D.Palette[i] := C4(P.Palette[i], 0);

  C.Grid := D.Grid;
  C.Frame := V4(Geo.W, Geo.H, Geo.NCols, Geo.NRows);
  C.Sprite := V4(Renderer.SpriteSize, Renderer.SpriteExt,
    Max(1, Ceil((Renderer.SpriteExt + 1) / Geo.Cell)), 0);
  C.Ring := V4(P.RingSaturation, P.RingWhiteMix, P.BreathAmp, P.BreathSpeed);
  C.HiCol := C4(P.HighlightColor, P.HighlightBoost);
  if P.HazeOn then C.Bg := C4(P.BgColor, P.HazeIntensity) else C.Bg := C4(P.BgColor, 0);
  C.Spark := C4(P.SparkColor, 0);
  if P.VignetteOn then
    C.Vig := V4(P.VignetteStrength, P.VignetteInner, P.VignetteOuter, P.Exposure)
  else
    C.Vig := V4(0, P.VignetteInner, P.VignetteOuter, P.Exposure);
end;

procedure TGPUView.AppIdle(Sender: TObject; var Done: Boolean);
begin
  if FRunning then RenderFrame;
  Done := False;
end;

procedure TGPUView.HandleKey(AKey: TSDL_Keycode);
begin
  case AKey of
    SDLK_F1: ToggleInfo;
    SDLK_F11: ToggleFullScreen;
    SDLK_SPACE: P.Paused := not P.Paused;
    SDLK_ESCAPE: if FFullScreen then ToggleFullScreen;
  end;
end;

procedure TGPUView.PollEvents;
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

procedure TGPUView.ApplyPresentMode;
var
  mode: TSDL_GPUPresentMode;
begin
  if Ord(P.VSync) = FPresentApplied then Exit;
  FPresentApplied := Ord(P.VSync);
  if P.VSync then
    mode := SDL_GPU_PRESENTMODE_VSYNC
  else if SDL_WindowSupportsGPUPresentMode(FDev, FWin, SDL_GPU_PRESENTMODE_IMMEDIATE) then
    mode := SDL_GPU_PRESENTMODE_IMMEDIATE
  else
    mode := SDL_GPU_PRESENTMODE_MAILBOX;
  SDL_SetGPUSwapchainParameters(FDev, FWin, SDL_GPU_SWAPCHAINCOMPOSITION_SDR, mode);
  Stats.VSyncActive := mode = SDL_GPU_PRESENTMODE_VSYNC;
end;

procedure TGPUView.UpdateRefreshRate;
var
  mode: PSDL_DisplayMode;
begin
  mode := SDL_GetCurrentDisplayMode(SDL_GetDisplayForWindow(FWin));
  if mode <> nil then Stats.RefreshHz := Round(mode^.refresh_rate);
end;

procedure TGPUView.RenderFrame;
var
  cmd: PSDL_GPUCommandBuffer;
  swap: PSDL_GPUTexture;
  sw, sh: TUint32;
  rw, rh, i: Integer;
  Geo: TFrameGeom;
  du: TDotUniforms;
  cu: TCompositeUniforms;
  cti: TSDL_GPUColorTargetInfo;
  rp: PSDL_GPURenderPass;
  binds: array[0..1] of TSDL_GPUTextureSamplerBinding;
  bi: TSDL_GPUBlitInfo;
  tnow, dt, t0, t1, t2, t3, sum: Double;
begin
  PollEvents;
  if not FRunning or (Renderer = nil) then Exit;
  if (SDL_GetWindowFlags(FWin) and SDL_WINDOW_MINIMIZED) <> 0 then
  begin
    Sleep(15);
    Exit;
  end;
  ApplyPresentMode;

  { 1. swapchain image (blocks for VSync) }
  t0 := HiResSeconds;
  cmd := SDL_AcquireGPUCommandBuffer(FDev);
  if cmd = nil then Exit;
  swap := nil;
  sw := 0;
  sh := 0;
  if not SDL_WaitAndAcquireGPUSwapchainTexture(cmd, FWin, @swap, @sw, @sh) or (swap = nil) then
  begin
    SDL_SubmitGPUCommandBuffer(cmd);
    Exit;
  end;
  t1 := HiResSeconds;

  tnow := t1;
  if FLastTick = 0 then
  begin
    FLastTick := tnow;
    FFpsT0 := tnow;
    FRefreshT := tnow;
  end;
  dt := tnow - FLastTick;
  FLastTick := tnow;
  if not P.Paused then FSimTime += Min(dt, 0.1) * P.TimeScale;
  rw := Max(16, Round(sw * P.RenderScale));
  rh := Max(16, Round(sh * P.RenderScale));

  { 2. geometry, sprite (BGRABitmap, only when its parameters change), uniforms }
  Renderer.PrepareDisplay(rw, rh, FSimTime, Geo);
  EnsureTextures(Geo, rw, rh);
  if (FSprTex = nil) or (FSprRebuilds <> Renderer.SpriteRebuilds) then UploadSprite(cmd);
  FillUniforms(Geo, du, cu);

  { 3. pass 1: dot states }
  FillChar(cti, SizeOf(cti), 0);
  cti.texture := FDotTex;
  cti.load_op := SDL_GPU_LOADOP_DONT_CARE;
  cti.store_op := SDL_GPU_STOREOP_STORE;
  cti.cycle := True;
  rp := SDL_BeginGPURenderPass(cmd, @cti, 1, nil);
  SDL_BindGPUGraphicsPipeline(rp, FDotsPipe);
  SDL_PushGPUFragmentUniformData(cmd, 0, @du, SizeOf(du));
  SDL_DrawGPUPrimitives(rp, 3, 1, 0, 0);
  SDL_EndGPURenderPass(rp);

  { 4. pass 2: composite every pixel }
  cti.texture := FFrameTex;
  rp := SDL_BeginGPURenderPass(cmd, @cti, 1, nil);
  SDL_BindGPUGraphicsPipeline(rp, FCompPipe);
  binds[0].texture := FDotTex;
  binds[0].sampler := FSampler;
  binds[1].texture := FSprTex;
  binds[1].sampler := FSampler;
  SDL_BindGPUFragmentSamplers(rp, 0, @binds[0], 2);
  SDL_PushGPUFragmentUniformData(cmd, 0, @cu, SizeOf(cu));
  SDL_DrawGPUPrimitives(rp, 3, 1, 0, 0);
  SDL_EndGPURenderPass(rp);

  { 5. scale to the window and present }
  FillChar(bi, SizeOf(bi), 0);
  bi.Source.texture := FFrameTex;
  bi.Source.w := rw;
  bi.Source.h := rh;
  bi.destination.texture := swap;
  bi.destination.w := sw;
  bi.destination.h := sh;
  bi.load_op := SDL_GPU_LOADOP_DONT_CARE;
  if P.SmoothUpscale then bi.filter := SDL_GPU_FILTER_LINEAR else bi.filter := SDL_GPU_FILTER_NEAREST;
  SDL_BlitGPUTexture(cmd, @bi);
  t2 := HiResSeconds;
  SDL_SubmitGPUCommandBuffer(cmd);
  t3 := HiResSeconds;

  Stats.WaitMs := (t1 - t0) * 1000;
  Stats.CpuMs := (t2 - t1) * 1000;
  Stats.UploadMs := 0;
  Stats.SwapMs := (t3 - t2) * 1000;
  Stats.FrameMs := dt * 1000;
  Stats.ViewW := sw; Stats.ViewH := sh;
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

function TGPUView.CaptureFrame: TBGRABitmap;
var
  cmd: PSDL_GPUCommandBuffer;
  cp: PSDL_GPUCopyPass;
  tb: PSDL_GPUTransferBuffer;
  tbi: TSDL_GPUTransferBufferCreateInfo;
  reg: TSDL_GPUTextureRegion;
  tti: TSDL_GPUTextureTransferInfo;
  fence: PSDL_GPUFence;
  src: PByte;
  y: Integer;
begin
  Result := nil;
  if (FFrameTex = nil) or (FFrameW <= 0) then Exit;
  FillChar(tbi, SizeOf(tbi), 0);
  tbi.usage := SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD;
  tbi.size := FFrameW * FFrameH * 4;
  tb := SDL_CreateGPUTransferBuffer(FDev, @tbi);
  if tb = nil then Exit;
  try
    cmd := SDL_AcquireGPUCommandBuffer(FDev);
    cp := SDL_BeginGPUCopyPass(cmd);
    FillChar(reg, SizeOf(reg), 0);
    reg.texture := FFrameTex;
    reg.w := FFrameW;
    reg.h := FFrameH;
    reg.d := 1;
    FillChar(tti, SizeOf(tti), 0);
    tti.transfer_buffer := tb;
    SDL_DownloadFromGPUTexture(cp, @reg, @tti);
    SDL_EndGPUCopyPass(cp);
    fence := SDL_SubmitGPUCommandBufferAndAcquireFence(cmd);
    if fence = nil then Exit;
    SDL_WaitForGPUFences(FDev, True, @fence, 1);
    SDL_ReleaseGPUFence(FDev, fence);
    src := SDL_MapGPUTransferBuffer(FDev, tb, False);
    if src = nil then Exit;
    Result := TBGRABitmap.Create(FFrameW, FFrameH);
    { B8G8R8A8 rows, top-down = TBGRAPixel memory order on Windows }
    for y := 0 to FFrameH - 1 do
      Move(src[y * FFrameW * 4], Result.ScanLine[y]^, FFrameW * 4);
    if TBGRAPixel_RGBAOrder then Result.SwapRedBlue;
    Result.InvalidateBitmap;
    SDL_UnmapGPUTransferBuffer(FDev, tb);
  finally
    SDL_ReleaseGPUTransferBuffer(FDev, tb);
  end;
end;

function TGPUView.CaptureThumb(AW, AH: Integer): TBGRABitmap;
begin
  Result := CaptureFrame;
  if Assigned(Result) and ((Result.Width <> AW) or (Result.Height <> AH)) then
    BGRAReplace(Result, Result.Resample(Max(1, AW), Max(1, AH), rmSimpleStretch));
end;

procedure TGPUView.BenchFrame(ANow, ADt: Double);
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

procedure TGPUView.WriteBenchReport;
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
  for i := 1 to n - 1 do
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
    sl.Add('Neon Dot Grid SDL3 GPU benchmark  ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    sl.Add(Format('driver %s, %s, %s, vsync %s, monitor %d Hz', [Stats.GLRenderer, Stats.GLVendor,
      Stats.GLVersion, BoolToStr(Stats.VSyncActive, 'on', 'off'), Stats.RefreshHz]));
    sl.Add(Format('window %d x %d, render %d x %d, fullscreen %s',
      [Stats.ViewW, Stats.ViewH, Stats.RenderW, Stats.RenderH, BoolToStr(FFullScreen, 'yes', 'no')]));
    sl.Add(Format('frames %d in %.1f s  ->  %.2f fps', [n, sum / 1000, n * 1000 / sum]));
    sl.Add(Format('interval ms: mean %.2f  median %.2f  p99 %.2f  max %.2f', [sum / n,
      sorted[n div 2], sorted[Min(n - 1, Round(n * 0.99))], sorted[n - 1]]));
    sl.Add(Format('frames over 1.5x budget (missed vblank): %d (%.2f%%)', [missed, missed * 100 / n]));
    sl.Add(Format('CPU per frame %.2f ms (uniforms + command recording)', [Stats.CpuMs]));
    sl.SaveToFile(ChangeFileExt(ParamStr(0), '-bench.txt'));
  finally
    sl.Free;
  end;
end;

procedure TGPUView.ToggleFullScreen;
begin
  FFullScreen := not FFullScreen;
  SDL_SetWindowFullscreen(FWin, FFullScreen);
  if Assigned(InfoForm) then
    if FFullScreen then InfoForm.FormStyle := fsStayOnTop else InfoForm.FormStyle := fsNormal;
end;

procedure TGPUView.ToggleInfo;
begin
  if not Assigned(InfoForm) then Exit;
  InfoForm.Visible := not InfoForm.Visible;
  if InfoForm.Visible then InfoForm.BringToFront else SDL_RaiseWindow(FWin);
end;

function TGPUView.Left: Integer;
var
  x, y: LongInt;
begin
  SDL_GetWindowPosition(FWin, @x, @y);
  Result := x;
end;

function TGPUView.Top: Integer;
var
  x, y: LongInt;
begin
  SDL_GetWindowPosition(FWin, @x, @y);
  Result := y;
end;

function TGPUView.Width: Integer;
var
  w, h: LongInt;
begin
  SDL_GetWindowSize(FWin, @w, @h);
  Result := w;
end;

function TGPUView.Height: Integer;
var
  w, h: LongInt;
begin
  SDL_GetWindowSize(FWin, @w, @h);
  Result := h;
end;

end.
