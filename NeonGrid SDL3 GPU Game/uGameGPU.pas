unit uGameGPU;

{ SDL3 GPU output for Neon Beads (Direct3D 12, DXIL or DXBC shaders).

  Per frame:
    copy pass   board textures (GameTex, GameFx: one RGBA16F texel per dot),
                the dot sprite when it was rebuilt, the HUD when it changed
    pass 1      dots_ps       background colour model + board -> dot texture
    pass 2      composite_ps  every pixel: sprite x nearby dots (with fall /
                              slide offsets and pop growth) + haze + vignette
                              -> swapchain
    pass 3      particles     spark particles (storage buffer, additive)
    pass 4      overlay_ps    HUD (SDL3_ttf text + BGRABitmap panels), alpha
                              blended -> swapchain
  SDL_WaitAndAcquireGPUSwapchainTexture with SDL_GPU_PRESENTMODE_VSYNC paces
  the game to the monitor refresh.

  Texture uploads keep D3D12's copy layout: rows padded to 256 bytes, each
  image starting on a 512 byte boundary. Otherwise SDL realigns the data on
  the CPU, reading back the write-combined transfer buffer (~12 ms for the
  window-sized HUD). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, SDL3, BGRABitmap, BGRABitmapTypes, uParams, uRenderer, uGPUShaders,
  uParticles;

type
  TVec4 = array[0..3] of Single;
  THalf4 = array[0..3] of Word;

  TDotUniforms = record
    Grid, Frame, Field0, Ambient: TVec4;
    BlobPos, BlobAnim, BlobCol: array[0..MaxBlobs - 1] of TVec4;
    Bound0, Bound1, BoundCol, Shadow, Jitter, Sparkle, Trail0, Trail1, Highlight: TVec4;
    Palette: array[0..PaletteSize - 1] of TVec4;
    Game: TVec4;
    Motion0, Motion1: TVec4;   // background motion (dots_ps MoveField)
    Show0, Show1: TVec4;       // colour show (dots_ps ShowColor)
  end;

  TCompositeUniforms = record
    Grid, Frame, Sprite, Ring, HiCol, Bg, Spark, Vig, Game: TVec4;
    Move0, Move1, Shape: TVec4;   // dot motion and dot shape rotation (composite_ps)
    Shape2: TVec4;                // bead shape: angle, spin, variation, own shape (right half of the sprite)
  end;

  TGameLook = record
    DimOutside, DimEmpty, Shimmer, BgHighlight, PopGrowth: Single;
  end;

  TGameGPU = class
  private
    FWin: PSDL_Window;
    FDev: PSDL_GPUDevice;
    FShaderFormat: TSDL_GPUShaderFormat;
    FSwapFormat: TSDL_GPUTextureFormat;
    FVS, FDotsFS, FCompFS, FHudFS, FPartVS, FPartFS: PSDL_GPUShader;
    FDotsPipe, FCompPipe, FHudPipe, FPartPipe: PSDL_GPUGraphicsPipeline;
    FPartBuf: PSDL_GPUBuffer;
    FPartTB: PSDL_GPUTransferBuffer;
    FSampler: PSDL_GPUSampler;
    FDotTex, FGameTex, FGameFx, FSprTex, FHudTex: PSDL_GPUTexture;
    FDotW, FDotH, FSprN, FHudW, FHudH: Integer;
    FSprRebuilds: Integer;
    FCellBuf, FHudBuf: PSDL_GPUTransferBuffer;
    FCellBufSize, FHudBufSize: Integer;
    FVSync: Integer;
    function MakeShader(const ACode; ASize: Integer; AStage: TSDL_GPUShaderStage;
      ASamplers, AUniforms: Integer; AStorage: Integer = 0): PSDL_GPUShader;
    { ABlend: 0 = none, 1 = alpha, 2 = additive (premultiplied) }
    function MakePipeline(AFrag: PSDL_GPUShader; AFormat: TSDL_GPUTextureFormat;
      ABlend: Integer; AVert: PSDL_GPUShader = nil): PSDL_GPUGraphicsPipeline;
    function MakeTexture(AW, AH: Integer; AFormat: TSDL_GPUTextureFormat;
      AUsage: TSDL_GPUTextureUsageFlags): PSDL_GPUTexture;
    procedure Upload(ACopy: PSDL_GPUCopyPass; ABuf: PSDL_GPUTransferBuffer; AOffset: Integer;
      ATex: PSDL_GPUTexture; AW, AH, ARowPixels: Integer);
  public
    Driver, ShaderInfo: string;
    constructor Create(AWin: PSDL_Window);
    destructor Destroy; override;
    procedure SetVSync(AOn: Boolean);
    { returns False when no swapchain image was available (minimized) }
    function Frame(R: TNeonRenderer; const Geo: TFrameGeom; const ALook: TGameLook;
      const ACells, AFx: array of THalf4; AMaxOffX, AMaxOffY: Integer;
      AHud: TBGRABitmap; AHudDirty: Boolean;
      const AParts: array of TParticleGPU; APartCount: Integer): Boolean;
  end;

function FloatToHalf(f: Single): Word;
function Half4(a, b, c, d: Single): THalf4;

implementation

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

{ texels per transfer row so a row is a multiple of 256 bytes (ATexel = 4 or 8) }
function RowPixels(AW, ATexel: Integer): Integer;
begin
  Result := (AW * ATexel + 255) div 256 * 256 div ATexel;
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
  if e <= 0 then Exit;
  if e >= 31 then Exit(Result or $7C00);
  Result := Result or Word(e shl 10) or Word(m shr 13);
  if (m and $1000) <> 0 then Inc(Result);
end;

function Half4(a, b, c, d: Single): THalf4;
begin
  Result[0] := FloatToHalf(a);
  Result[1] := FloatToHalf(b);
  Result[2] := FloatToHalf(c);
  Result[3] := FloatToHalf(d);
end;

{ TGameGPU }

constructor TGameGPU.Create(AWin: PSDL_Window);
var
  si: TSDL_GPUSamplerCreateInfo;
  bci: TSDL_GPUBufferCreateInfo;
  tci: TSDL_GPUTransferBufferCreateInfo;
begin
  inherited Create;
  FWin := AWin;
  FDev := SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_DXIL or SDL_GPU_SHADERFORMAT_DXBC, False, nil);
  if FDev = nil then raise Exception.Create('SDL_CreateGPUDevice failed (needs Direct3D 12): ' + SDLErr);
  if not SDL_ClaimWindowForGPUDevice(FDev, FWin) then
    raise Exception.Create('SDL_ClaimWindowForGPUDevice failed: ' + SDLErr);
  if (SDL_GetGPUShaderFormats(FDev) and SDL_GPU_SHADERFORMAT_DXIL) <> 0 then
  begin
    FShaderFormat := SDL_GPU_SHADERFORMAT_DXIL;
    ShaderInfo := 'DXIL SM6.0';
    FVS := MakeShader(FullscreenVS_DXIL, SizeOf(FullscreenVS_DXIL), SDL_GPU_SHADERSTAGE_VERTEX, 0, 0);
    FDotsFS := MakeShader(DotsPS_DXIL, SizeOf(DotsPS_DXIL), SDL_GPU_SHADERSTAGE_FRAGMENT, 2, 1);
    FCompFS := MakeShader(CompositePS_DXIL, SizeOf(CompositePS_DXIL), SDL_GPU_SHADERSTAGE_FRAGMENT, 3, 1);
    FHudFS := MakeShader(OverlayPS_DXIL, SizeOf(OverlayPS_DXIL), SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 0);
    FPartVS := MakeShader(ParticlesVS_DXIL, SizeOf(ParticlesVS_DXIL), SDL_GPU_SHADERSTAGE_VERTEX, 0, 1, 1);
    FPartFS := MakeShader(ParticlesPS_DXIL, SizeOf(ParticlesPS_DXIL), SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
  end
  else
  begin
    FShaderFormat := SDL_GPU_SHADERFORMAT_DXBC;
    ShaderInfo := 'DXBC SM5.1';
    FVS := MakeShader(FullscreenVS_DXBC, SizeOf(FullscreenVS_DXBC), SDL_GPU_SHADERSTAGE_VERTEX, 0, 0);
    FDotsFS := MakeShader(DotsPS_DXBC, SizeOf(DotsPS_DXBC), SDL_GPU_SHADERSTAGE_FRAGMENT, 2, 1);
    FCompFS := MakeShader(CompositePS_DXBC, SizeOf(CompositePS_DXBC), SDL_GPU_SHADERSTAGE_FRAGMENT, 3, 1);
    FHudFS := MakeShader(OverlayPS_DXBC, SizeOf(OverlayPS_DXBC), SDL_GPU_SHADERSTAGE_FRAGMENT, 1, 0);
    FPartVS := MakeShader(ParticlesVS_DXBC, SizeOf(ParticlesVS_DXBC), SDL_GPU_SHADERSTAGE_VERTEX, 0, 1, 1);
    FPartFS := MakeShader(ParticlesPS_DXBC, SizeOf(ParticlesPS_DXBC), SDL_GPU_SHADERSTAGE_FRAGMENT, 0, 0);
  end;
  FSwapFormat := SDL_GetGPUSwapchainTextureFormat(FDev, FWin);
  FDotsPipe := MakePipeline(FDotsFS, SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT, 0);
  FCompPipe := MakePipeline(FCompFS, FSwapFormat, 0);
  FHudPipe := MakePipeline(FHudFS, FSwapFormat, 1);
  FPartPipe := MakePipeline(FPartFS, FSwapFormat, 2, FPartVS);
  FillChar(bci, SizeOf(bci), 0);
  bci.usage := SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ;
  bci.size := MaxParticles * SizeOf(TParticleGPU);
  FPartBuf := SDL_CreateGPUBuffer(FDev, @bci);
  FillChar(tci, SizeOf(tci), 0);
  tci.usage := SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
  tci.size := MaxParticles * SizeOf(TParticleGPU);
  FPartTB := SDL_CreateGPUTransferBuffer(FDev, @tci);
  FillChar(si, SizeOf(si), 0);
  si.min_filter := SDL_GPU_FILTER_LINEAR;
  si.mag_filter := SDL_GPU_FILTER_LINEAR;
  si.mipmap_mode := SDL_GPU_SAMPLERMIPMAPMODE_NEAREST;
  si.address_mode_u := SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
  si.address_mode_v := SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
  si.address_mode_w := SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
  FSampler := SDL_CreateGPUSampler(FDev, @si);
  Driver := StrPas(SDL_GetGPUDeviceDriver(FDev));
  FSprRebuilds := -1;
  FVSync := -1;
  SetVSync(True);
end;

destructor TGameGPU.Destroy;
begin
  if FDev <> nil then
  begin
    SDL_WaitForGPUIdle(FDev);
    if FCellBuf <> nil then SDL_ReleaseGPUTransferBuffer(FDev, FCellBuf);
    if FHudBuf <> nil then SDL_ReleaseGPUTransferBuffer(FDev, FHudBuf);
    if FPartTB <> nil then SDL_ReleaseGPUTransferBuffer(FDev, FPartTB);
    if FPartBuf <> nil then SDL_ReleaseGPUBuffer(FDev, FPartBuf);
    if FPartPipe <> nil then SDL_ReleaseGPUGraphicsPipeline(FDev, FPartPipe);
    if FPartVS <> nil then SDL_ReleaseGPUShader(FDev, FPartVS);
    if FPartFS <> nil then SDL_ReleaseGPUShader(FDev, FPartFS);
    if FDotTex <> nil then SDL_ReleaseGPUTexture(FDev, FDotTex);
    if FGameTex <> nil then SDL_ReleaseGPUTexture(FDev, FGameTex);
    if FGameFx <> nil then SDL_ReleaseGPUTexture(FDev, FGameFx);
    if FSprTex <> nil then SDL_ReleaseGPUTexture(FDev, FSprTex);
    if FHudTex <> nil then SDL_ReleaseGPUTexture(FDev, FHudTex);
    if FSampler <> nil then SDL_ReleaseGPUSampler(FDev, FSampler);
    if FDotsPipe <> nil then SDL_ReleaseGPUGraphicsPipeline(FDev, FDotsPipe);
    if FCompPipe <> nil then SDL_ReleaseGPUGraphicsPipeline(FDev, FCompPipe);
    if FHudPipe <> nil then SDL_ReleaseGPUGraphicsPipeline(FDev, FHudPipe);
    if FVS <> nil then SDL_ReleaseGPUShader(FDev, FVS);
    if FDotsFS <> nil then SDL_ReleaseGPUShader(FDev, FDotsFS);
    if FCompFS <> nil then SDL_ReleaseGPUShader(FDev, FCompFS);
    if FHudFS <> nil then SDL_ReleaseGPUShader(FDev, FHudFS);
    SDL_ReleaseWindowFromGPUDevice(FDev, FWin);
    SDL_DestroyGPUDevice(FDev);
  end;
  inherited Destroy;
end;

function TGameGPU.MakeShader(const ACode; ASize: Integer; AStage: TSDL_GPUShaderStage;
  ASamplers, AUniforms: Integer; AStorage: Integer): PSDL_GPUShader;
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
  ci.num_storage_buffers := AStorage;
  Result := SDL_CreateGPUShader(FDev, @ci);
  if Result = nil then raise Exception.Create('SDL_CreateGPUShader failed: ' + SDLErr);
end;

function TGameGPU.MakePipeline(AFrag: PSDL_GPUShader; AFormat: TSDL_GPUTextureFormat;
  ABlend: Integer; AVert: PSDL_GPUShader): PSDL_GPUGraphicsPipeline;
var
  pi: TSDL_GPUGraphicsPipelineCreateInfo;
  ctd: TSDL_GPUColorTargetDescription;
begin
  FillChar(ctd, SizeOf(ctd), 0);
  ctd.format := AFormat;
  if ABlend = 2 then
    with ctd.blend_state do
    begin
      enable_blend := True;
      src_color_blendfactor := SDL_GPU_BLENDFACTOR_ONE;
      dst_color_blendfactor := SDL_GPU_BLENDFACTOR_ONE;
      color_blend_op := SDL_GPU_BLENDOP_ADD;
      src_alpha_blendfactor := SDL_GPU_BLENDFACTOR_ONE;
      dst_alpha_blendfactor := SDL_GPU_BLENDFACTOR_ONE;
      alpha_blend_op := SDL_GPU_BLENDOP_ADD;
    end
  else if ABlend = 1 then
    with ctd.blend_state do
    begin
      enable_blend := True;
      src_color_blendfactor := SDL_GPU_BLENDFACTOR_SRC_ALPHA;
      dst_color_blendfactor := SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
      color_blend_op := SDL_GPU_BLENDOP_ADD;
      src_alpha_blendfactor := SDL_GPU_BLENDFACTOR_ONE;
      dst_alpha_blendfactor := SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
      alpha_blend_op := SDL_GPU_BLENDOP_ADD;
    end;
  FillChar(pi, SizeOf(pi), 0);
  if AVert <> nil then pi.vertex_shader := AVert else pi.vertex_shader := FVS;
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

function TGameGPU.MakeTexture(AW, AH: Integer; AFormat: TSDL_GPUTextureFormat;
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

procedure TGameGPU.Upload(ACopy: PSDL_GPUCopyPass; ABuf: PSDL_GPUTransferBuffer; AOffset: Integer;
  ATex: PSDL_GPUTexture; AW, AH, ARowPixels: Integer);
var
  tti: TSDL_GPUTextureTransferInfo;
  reg: TSDL_GPUTextureRegion;
begin
  FillChar(tti, SizeOf(tti), 0);
  tti.transfer_buffer := ABuf;
  tti.offset := AOffset;
  tti.pixels_per_row := ARowPixels;
  tti.rows_per_layer := AH;
  FillChar(reg, SizeOf(reg), 0);
  reg.texture := ATex;
  reg.w := AW;
  reg.h := AH;
  reg.d := 1;
  SDL_UploadToGPUTexture(ACopy, @tti, @reg, True);
end;

procedure TGameGPU.SetVSync(AOn: Boolean);
var
  mode: TSDL_GPUPresentMode;
begin
  if Ord(AOn) = FVSync then Exit;
  FVSync := Ord(AOn);
  if AOn then
    mode := SDL_GPU_PRESENTMODE_VSYNC
  else if SDL_WindowSupportsGPUPresentMode(FDev, FWin, SDL_GPU_PRESENTMODE_IMMEDIATE) then
    mode := SDL_GPU_PRESENTMODE_IMMEDIATE
  else
    mode := SDL_GPU_PRESENTMODE_MAILBOX;
  SDL_SetGPUSwapchainParameters(FDev, FWin, SDL_GPU_SWAPCHAINCOMPOSITION_SDR, mode);
end;

function TGameGPU.Frame(R: TNeonRenderer; const Geo: TFrameGeom; const ALook: TGameLook;
  const ACells, AFx: array of THalf4; AMaxOffX, AMaxOffY: Integer;
  AHud: TBGRABitmap; AHudDirty: Boolean;
  const AParts: array of TParticleGPU; APartCount: Integer): Boolean;
var
  tloc: TSDL_GPUTransferBufferLocation;
  breg: TSDL_GPUBufferRegion;
  scr: array[0..3] of Single;
  cmd: PSDL_GPUCommandBuffer;
  swap: PSDL_GPUTexture;
  sw, sh: TUint32;
  du: TDotUniforms;
  cu: TCompositeUniforms;
  cti: TSDL_GPUColorTargetInfo;
  rp: PSDL_GPURenderPass;
  cp: PSDL_GPUCopyPass;
  binds: array[0..2] of TSDL_GPUTextureSamplerBinding;
  tbi: TSDL_GPUTransferBufferCreateInfo;
  pb: PByte;
  ps: PSpriteTexel;
  ph: PWord;
  i, k, n, cellBytes, y, rowPix, rowBytes: Integer;
  tb: PSDL_GPUTransferBuffer;
begin
  Result := False;
  cmd := SDL_AcquireGPUCommandBuffer(FDev);
  if cmd = nil then Exit;
  swap := nil;
  if not SDL_WaitAndAcquireGPUSwapchainTexture(cmd, FWin, @swap, @sw, @sh) or (swap = nil) then
  begin
    SDL_SubmitGPUCommandBuffer(cmd);
    Exit;
  end;

  { textures that depend on the grid / window size }
  if (FDotTex = nil) or (FDotW <> Geo.NCols) or (FDotH <> Geo.NRows) then
  begin
    if FDotTex <> nil then SDL_ReleaseGPUTexture(FDev, FDotTex);
    if FGameTex <> nil then SDL_ReleaseGPUTexture(FDev, FGameTex);
    if FGameFx <> nil then SDL_ReleaseGPUTexture(FDev, FGameFx);
    FDotTex := MakeTexture(Geo.NCols, Geo.NRows, SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
      SDL_GPU_TEXTUREUSAGE_COLOR_TARGET or SDL_GPU_TEXTUREUSAGE_SAMPLER);
    FGameTex := MakeTexture(Geo.NCols, Geo.NRows, SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT, SDL_GPU_TEXTUREUSAGE_SAMPLER);
    FGameFx := MakeTexture(Geo.NCols, Geo.NRows, SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT, SDL_GPU_TEXTUREUSAGE_SAMPLER);
    FDotW := Geo.NCols;
    FDotH := Geo.NRows;
  end;
  if (FHudTex = nil) or (FHudW <> AHud.Width) or (FHudH <> AHud.Height) then
  begin
    if FHudTex <> nil then SDL_ReleaseGPUTexture(FDev, FHudTex);
    FHudTex := MakeTexture(AHud.Width, AHud.Height, SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM, SDL_GPU_TEXTUREUSAGE_SAMPLER);
    FHudW := AHud.Width;
    FHudH := AHud.Height;
    AHudDirty := True;
  end;

  cp := SDL_BeginGPUCopyPass(cmd);
  { board state: two RGBA16F textures, one texel per dot }
  n := Geo.NCols * Geo.NRows;
  rowPix := RowPixels(Geo.NCols, SizeOf(THalf4));
  rowBytes := rowPix * SizeOf(THalf4);
  cellBytes := (rowBytes * Geo.NRows + 511) div 512 * 512;
  if (FCellBuf = nil) or (FCellBufSize < cellBytes * 2) then
  begin
    if FCellBuf <> nil then SDL_ReleaseGPUTransferBuffer(FDev, FCellBuf);
    FillChar(tbi, SizeOf(tbi), 0);
    tbi.usage := SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
    tbi.size := cellBytes * 2;
    FCellBuf := SDL_CreateGPUTransferBuffer(FDev, @tbi);
    FCellBufSize := cellBytes * 2;
  end;
  pb := SDL_MapGPUTransferBuffer(FDev, FCellBuf, True);
  for y := 0 to Geo.NRows - 1 do
  begin
    Move(ACells[y * Geo.NCols], pb[y * rowBytes], Geo.NCols * SizeOf(THalf4));
    Move(AFx[y * Geo.NCols], pb[cellBytes + y * rowBytes], Geo.NCols * SizeOf(THalf4));
  end;
  SDL_UnmapGPUTransferBuffer(FDev, FCellBuf);
  Upload(cp, FCellBuf, 0, FGameTex, Geo.NCols, Geo.NRows, rowPix);
  Upload(cp, FCellBuf, cellBytes, FGameFx, Geo.NCols, Geo.NRows, rowPix);

  { dot sprite (BGRABitmap) when it was rebuilt }
  if (FSprTex = nil) or (FSprRebuilds <> R.SpriteRebuilds) then
  begin
    n := R.SpriteSize;
    if (FSprTex = nil) or (FSprN <> n) then
    begin
      if FSprTex <> nil then SDL_ReleaseGPUTexture(FDev, FSprTex);
      FSprTex := MakeTexture(2 * n, n, SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT, SDL_GPU_TEXTUREUSAGE_SAMPLER);
      FSprN := n;
    end;
    FillChar(tbi, SizeOf(tbi), 0);
    tbi.usage := SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
    rowPix := RowPixels(2 * n, 8);
    tbi.size := rowPix * n * 8;
    tb := SDL_CreateGPUTransferBuffer(FDev, @tbi);
    pb := SDL_MapGPUTransferBuffer(FDev, tb, False);
    { left half: the background dot, right half: the bead }
    for k := 0 to 1 do
    begin
      if k = 0 then ps := R.SpriteTexels else ps := R.SpriteTexels2;
      for y := 0 to n - 1 do
      begin
        ph := PWord(pb + y * rowPix * 8 + k * n * 8);
        for i := 0 to n - 1 do
        begin
          ph[0] := FloatToHalf(ps^.A / 256);
          ph[1] := FloatToHalf(ps^.B / 256);
          ph[2] := FloatToHalf(ps^.C / 256);
          ph[3] := 0;
          Inc(ph, 4);
          Inc(ps);
        end;
      end;
    end;
    SDL_UnmapGPUTransferBuffer(FDev, tb);
    Upload(cp, tb, 0, FSprTex, 2 * n, n, rowPix);
    SDL_ReleaseGPUTransferBuffer(FDev, tb);
    FSprRebuilds := R.SpriteRebuilds;
  end;

  { HUD only when it changed }
  if AHudDirty then
  begin
    rowPix := RowPixels(AHud.Width, 4);
    if (FHudBuf = nil) or (FHudBufSize < rowPix * AHud.Height * 4) then
    begin
      if FHudBuf <> nil then SDL_ReleaseGPUTransferBuffer(FDev, FHudBuf);
      FillChar(tbi, SizeOf(tbi), 0);
      tbi.usage := SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
      tbi.size := rowPix * AHud.Height * 4;
      FHudBuf := SDL_CreateGPUTransferBuffer(FDev, @tbi);
      FHudBufSize := tbi.size;
    end;
    pb := SDL_MapGPUTransferBuffer(FDev, FHudBuf, True);
    for y := 0 to AHud.Height - 1 do
      Move(AHud.ScanLine[y]^, pb[y * rowPix * 4], AHud.Width * 4);
    SDL_UnmapGPUTransferBuffer(FDev, FHudBuf);
    Upload(cp, FHudBuf, 0, FHudTex, AHud.Width, AHud.Height, rowPix);
  end;
  { particles }
  APartCount := Min(APartCount, MaxParticles);
  if (APartCount > 0) and (FPartBuf <> nil) and (FPartTB <> nil) then
  begin
    pb := SDL_MapGPUTransferBuffer(FDev, FPartTB, True);
    Move(AParts[0], pb^, APartCount * SizeOf(TParticleGPU));
    SDL_UnmapGPUTransferBuffer(FDev, FPartTB);
    tloc.transfer_buffer := FPartTB;
    tloc.offset := 0;
    breg.buffer := FPartBuf;
    breg.offset := 0;
    breg.size := APartCount * SizeOf(TParticleGPU);
    SDL_UploadToGPUBuffer(cp, @tloc, @breg, True);
  end;
  SDL_EndGPUCopyPass(cp);

  { uniforms }
  FillChar(du, SizeOf(du), 0);
  du.Grid := V4(Geo.Cell, Geo.OriginX, Geo.OriginY, Geo.Time);
  du.Frame := V4(Geo.W, Geo.H, Geo.ShiftI, Geo.ShiftJ);
  du.Field0 := V4(P.AmbientWeight, P.FieldBrightness, P.FieldSaturation, 0);
  du.Ambient := C4(P.AmbientColor, 0);
  for i := 0 to MaxBlobs - 1 do
    with P.Blobs[i] do
    begin
      du.BlobPos[i] := V4(X, Y, Radius, Weight);
      du.BlobAnim[i] := V4(DriftAmp, DriftSpeed, Ord(Enabled), 0);
      du.BlobCol[i] := C4(Color, 0);
    end;
  du.Bound0 := V4(P.BoundaryTopX, P.BoundaryBottomX, P.BoundarySoftness, P.BoundaryStrength);
  du.Bound1 := V4(P.BoundaryWaveAmp, P.BoundaryWaveFreq, P.BoundaryWaveSpeed, Ord(P.BoundaryOn));
  du.BoundCol := C4(P.BoundaryColor, 0);
  if P.ShadowOn then du.Shadow := V4(P.ShadowX, P.ShadowY, P.ShadowRadius, P.ShadowStrength);
  du.Jitter := V4(P.JitterBrightness, P.JitterHue, P.JitterSpeed, 0);
  du.Sparkle := V4(Ord(P.SparkleOn), P.SparkleProb, P.SparkleSpeed, P.SparkleIntensity);
  du.Trail0 := V4(Ord(P.TrailOn), P.TrailOffset, P.TrailWidth, P.TrailSpeed);
  du.Trail1 := V4(P.TrailIntensity, P.TrailDensity, 0, 0);
  du.Highlight := V4(Ord(P.HighlightOn), P.HighlightProb, P.HighlightSpeed, 0);
  for i := 0 to PaletteSize - 1 do du.Palette[i] := C4(P.Palette[i], 0);
  du.Game := V4(ALook.DimOutside, ALook.DimEmpty, ALook.Shimmer, ALook.BgHighlight);
  du.Motion0 := V4(P.MotionMode, P.MotionSpeed, P.MotionAmount, P.MotionAngle * Pi / 180);
  du.Motion1 := V4(P.MotionFreq, P.MotionCX, P.MotionCY, 0);
  du.Show0 := V4(P.ShowMode, P.ShowStrength, P.ShowSpeed, P.ShowSize);
  du.Show1 := V4(P.ShowRainbow, P.ShowCX, P.ShowCY, P.ShowBars);

  FillChar(cu, SizeOf(cu), 0);
  cu.Grid := du.Grid;
  cu.Frame := V4(Geo.W, Geo.H, Geo.NCols, Geo.NRows);
  cu.Sprite := V4(R.SpriteSize, R.SpriteExt, Max(1, Ceil((R.SpriteExt + 1) * (1 + ALook.PopGrowth) / Geo.Cell)), 0);
  cu.Ring := V4(P.RingSaturation, P.RingWhiteMix, P.BreathAmp, P.BreathSpeed);
  cu.HiCol := C4(P.HighlightColor, P.HighlightBoost);
  if P.HazeOn then cu.Bg := C4(P.BgColor, P.HazeIntensity) else cu.Bg := C4(P.BgColor, 0);
  cu.Spark := C4(P.SparkColor, 0);
  if P.VignetteOn then
    cu.Vig := V4(P.VignetteStrength, P.VignetteInner, P.VignetteOuter, P.Exposure)
  else
    cu.Vig := V4(0, P.VignetteInner, P.VignetteOuter, P.Exposure);
  cu.Game := V4(AMaxOffX, AMaxOffY, ALook.PopGrowth, 0);
  cu.Move0 := V4(P.MoveMode, P.MoveAmount, P.MoveSpeed, P.MoveFreq);
  cu.Move1 := V4(P.MoveCX, P.MoveCY, P.MovePull, Ord(P.MoveBeads));
  cu.Shape := V4(P.ShapeAngle * Pi / 180, P.ShapeSpin * Pi / 180, P.ShapeVary, Ord(P.ShapeBeads));
  cu.Shape2 := V4(P.BeadAngle * Pi / 180, P.BeadSpin * Pi / 180, P.BeadVary, Ord(P.BeadOwnShape));

  { pass 1: dot states }
  FillChar(cti, SizeOf(cti), 0);
  cti.texture := FDotTex;
  cti.load_op := SDL_GPU_LOADOP_DONT_CARE;
  cti.store_op := SDL_GPU_STOREOP_STORE;
  cti.cycle := True;
  rp := SDL_BeginGPURenderPass(cmd, @cti, 1, nil);
  SDL_BindGPUGraphicsPipeline(rp, FDotsPipe);
  binds[0].texture := FGameTex; binds[0].sampler := FSampler;
  binds[1].texture := FGameFx; binds[1].sampler := FSampler;
  SDL_BindGPUFragmentSamplers(rp, 0, @binds[0], 2);
  SDL_PushGPUFragmentUniformData(cmd, 0, @du, SizeOf(du));
  SDL_DrawGPUPrimitives(rp, 3, 1, 0, 0);
  SDL_EndGPURenderPass(rp);

  { pass 2: composite straight into the swapchain image }
  cti.texture := swap;
  cti.cycle := False;
  rp := SDL_BeginGPURenderPass(cmd, @cti, 1, nil);
  SDL_BindGPUGraphicsPipeline(rp, FCompPipe);
  binds[0].texture := FDotTex; binds[0].sampler := FSampler;
  binds[1].texture := FSprTex; binds[1].sampler := FSampler;
  binds[2].texture := FGameFx; binds[2].sampler := FSampler;
  SDL_BindGPUFragmentSamplers(rp, 0, @binds[0], 3);
  SDL_PushGPUFragmentUniformData(cmd, 0, @cu, SizeOf(cu));
  SDL_DrawGPUPrimitives(rp, 3, 1, 0, 0);
  SDL_EndGPURenderPass(rp);

  { pass 3: spark particles, additive }
  cti.load_op := SDL_GPU_LOADOP_LOAD;
  if (APartCount > 0) and (FPartBuf <> nil) then
  begin
    rp := SDL_BeginGPURenderPass(cmd, @cti, 1, nil);
    SDL_BindGPUGraphicsPipeline(rp, FPartPipe);
    SDL_BindGPUVertexStorageBuffers(rp, 0, @FPartBuf, 1);
    scr[0] := sw; scr[1] := sh; scr[2] := 0; scr[3] := 0;
    SDL_PushGPUVertexUniformData(cmd, 0, @scr, SizeOf(scr));
    SDL_DrawGPUPrimitives(rp, APartCount * 6, 1, 0, 0);
    SDL_EndGPURenderPass(rp);
  end;

  { pass 4: HUD overlay }
  rp := SDL_BeginGPURenderPass(cmd, @cti, 1, nil);
  SDL_BindGPUGraphicsPipeline(rp, FHudPipe);
  binds[0].texture := FHudTex; binds[0].sampler := FSampler;
  SDL_BindGPUFragmentSamplers(rp, 0, @binds[0], 1);
  SDL_DrawGPUPrimitives(rp, 3, 1, 0, 0);
  SDL_EndGPURenderPass(rp);

  SDL_SubmitGPUCommandBuffer(cmd);
  Result := True;
end;

end.
