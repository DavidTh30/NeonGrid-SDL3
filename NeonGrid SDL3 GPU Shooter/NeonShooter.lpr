program NeonShooter;

{ Neon Shooter - a bead shooter on the animated neon dot grid.

    NeonShooter.lpr   window, input, layout, main loop (this file)
    uShooterGame.pas  rules: aiming, flight, bounces, matching, drops, new
                      ceiling rows, specials (bomb, rainbow), levels, demo AI
    uAchievements     achievements + top-10 high scores (kept in NeonShooter.ini)
    uParticles.pas    spark particle bursts (CPU simulation, drawn by a GPU pass)
    uGameGPU.pas      SDL3 GPU output: dots / composite / HUD shader passes
    uGPUShaders.pas   DXIL + DXBC bytecode built by build_shaders.ps1 from
                      shaders\*.hlsl (the game versions of the NeonGrid shaders)
    uRenderer.pas     NeonGrid colour model + BGRABitmap dot sprite
    uGameHud.pas      HUD (aim line), animated menus and screens (BGRABitmap + SDL3_ttf)
    uGameAudio.pas    synthesized sound effects + mixer (SDL3 audio stream)

  Main menu: PLAY, LEVEL (start level), HIGH SCORES, ACHIEVEMENTS, OPTIONS,
  CHEAT CODE, EXIT - mouse, or Up/Down + Left/Right + Enter.
  In game: the mouse aims (or Left / Right, A / D), a click / Space / Up
  shoots, a right click / X / Down / Tab swaps the current and the next bead;
  Enter or click continues after a level, R restarts the level, Esc or P
  pauses. M mute, F11 fullscreen. An AI plays behind the title menu.
  Command line: --fullscreen, --novsync, --autoplay (the AI plays),
  --bench=SECONDS (frame pacing report in NeonShooter-bench.txt),
  --preview=FILE / --shapes=FILE (the GPU previews of the editors, uPreview).
  Needs SDL3.dll and SDL3_ttf.dll next to the program and Direct3D 12.
  Best score, unlocked levels, high scores and achievements are kept in
  NeonShooter.ini. Music, sound effects, menu effects, visuals and shapes are
  NeonShooter.music / .sfx / .menufx / .visuals / .shapes (the editors in
  ..\NeonGrid SDL3 GPU Tools edit them; the game reloads them when they
  change). }

{$mode objfpc}{$H+}
{$COPERATORS ON}
{$IFDEF WINDOWS}{$APPTYPE GUI}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Types, Math, IniFiles, SDL3, SDL3_ttf, BGRABitmap, BGRABitmapTypes,
  uParams, uRenderer, uGPUShaders, uGameCode, uShooterGame, uAchievements, uParticles, uGameAudio, uGameMusic, uGameSfx, uMenuFx, uGameFx, uGameHud, uGameGPU, uPreview, uVoice, uShapes;

type
  TApp = class
    Win: PSDL_Window;
    Gpu: TGameGPU;
    Renderer: TNeonRenderer;
    Game: TShooterGame;
    Ach: TAchievements;
    Parts: TParticles;
    PartCount: Integer;
    Audio: TGameAudio;
    Hud: TGameHud;
    LastCombo, LastPop: Integer;  // the announcer (uVoice) watches these
    Look: TGameLook;
    L: TLayout;
    Geo: TFrameGeom;
    GX0, GY0: Integer;            // grid index of board cell (0, 0)
    Cells, Fx: array of THalf4;
    MouseX, MouseY: Single;       // window pixels
    Running, FullScreen, VSync: Boolean;
    ArgVSync, ArgFullScreen: Boolean;  // set by --novsync / --fullscreen: not saved
    MusicVol, SfxVol: Integer;       // 0..100
    MenuScreen, MenuSel: Integer;    // 0 = main, 1 = options, 2 = pause
    Paused: Boolean;
    OptionsFrom: Integer;            // screen to return to from the options
    ScoresOpen: Boolean;             // high-score table shown over the game-over panel
    PlayerName: string;              // last name typed for the high scores
    LastState: TGameState;
    MusicTrack: Integer;             // -1 = shuffle
    MenuTime, MenuItemTime: Single;
    SimTime: Double;
    IniName: string;
    AssetAge: array[0..4] of LongInt;
    BlankHud: TBGRABitmap;      // --preview background scene: no HUD
    HudForce: Boolean;          // upload the HUD on the next frame (scene change)
    FxIdx: array[TFxKind] of Integer;  // effect definitions (uGameFx) of the game's effects   // file times of the asset files
    AssetT: Double;                    // seconds since the last file check
    AutoPlay: Boolean;          // --autoplay: the AI steers (testing)
    AutoCrash: Boolean;         // --autocrash: autoplay that crashes on purpose (testing)
    AutoT: Double;
    BenchSecs, BenchT: Double;  // --bench=SECONDS: frame pacing report, then quit
    BenchDt: array of Single;
    StageMax: array[0..3] of Double;   // worst ms: update, hud, cells, gpu (bench report)
    procedure BenchReport;
    procedure SpawnFx;
    procedure GameOverCheck;
    procedure SubmitName;
    procedure OpenCodeEntry;
    procedure CloseCodeEntry;
    procedure AddCodeText(const S: string);
    procedure PasteCode;
    procedure ApplyCode;
    procedure CopyLevelCode;
    function LevelCode: string;
    function MenuShown: Boolean;
    procedure AutoStep(dt: Double);
    procedure BuildMenu;
    procedure MenuMove(ADelta: Integer);
    procedure MenuChange(ADelta: Integer);
    procedure MenuChoose;
    procedure MenuBack;
    procedure ShowMenu(AScreen: Integer; AIntro: Boolean);
    procedure SetFullScreen(AOn: Boolean);
    procedure ApplyAudio;
    procedure PickSong(ANew: Boolean);
    procedure StartGameLevel(ALevel: Integer; AKeepScore, ANewSong: Boolean);
    procedure OpenPause;
    procedure ResumeGame;
    procedure LoadIni;
    procedure RegisterVisuals;
    function AssetFile(AIndex: Integer): string;   // 0 .music, 1 .sfx, 2 .menufx, 3 .visuals
    procedure LoadAsset(AIndex: Integer; AStartup: Boolean);
    procedure CheckAssets(dt: Double);
    procedure SaveIni;
    procedure DoLayout;
    procedure BuildCells(out AMaxOffX, AMaxOffY: Integer);
    procedure Activate;
    procedure HandleKey(AKey: TSDL_Keycode);
    procedure SetScene(AScene: Integer);
    function PreviewKey(AKey: TSDL_Keycode): Boolean;
    procedure HandleEvent(const E: TSDL_Event);
    procedure Run;
  end;

{ --name, -name or /name on the command line }
function HasArg(const AName: string): Boolean;
var
  i: Integer;
  a: string;
begin
  for i := 1 to ParamCount do
  begin
    a := LowerCase(ParamStr(i));
    while (a <> '') and (a[1] in ['-', '/']) do Delete(a, 1, 1);
    if a = LowerCase(AName) then Exit(True);
  end;
  Result := False;
end;

procedure Fail(const AWhat: string);
begin
  SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, 'Neon Shooter', PAnsiChar(AWhat), nil);
  Halt(1);
end;

{ ---- music, sound effects and menu effects live in files next to the game
  (.music, .sfx, .menufx; written with the defaults when missing) and are
  reloaded while the game runs when an editor saves them }

function TApp.AssetFile(AIndex: Integer): string;
const
  Ext: array[0..4] of string = ('.music', '.sfx', '.menufx', '.visuals', '.shapes');
begin
  { --preview: NeonVisualEditor's live copy of the visuals }
  if (AIndex = 3) and Preview.Active then Exit(Preview.VisualsFile);
  if (AIndex = 4) and (Preview.ShapesFile <> '') then Exit(Preview.ShapesFile);
  Result := ChangeFileExt(ParamStr(0), Ext[AIndex]);
end;

procedure TApp.LoadAsset(AIndex: Integer; AStartup: Boolean);
var
  songs: TSongArray;
  bank: TSfxBank;
  mfx: TMenuFx;
  f: string;
  missing: Integer;
begin
  f := AssetFile(AIndex);
  case AIndex of
    0:
      begin
        if not LoadSongsFile(f, songs) then
        begin
          songs := DefaultSongs(MusicGameShooter);   // its own song set (NeonMusicEditor)
          if AStartup and not FileExists(f) then
            try SaveSongsFile(f, songs); except end;
        end;
        SetSongs(songs);
        if not AStartup then
        begin
          MusicTrack := EnsureRange(MusicTrack, -1, SongCount - 1);
          if Audio.CurrentSong >= SongCount then PickSong(True) else Audio.ReloadMusic;
        end;
      end;
    1:
      begin
        bank := DefaultSfxBank;
        if not LoadSfxFile(f, bank) and AStartup and not FileExists(f) then
          try SaveSfxFile(f, bank); except end;
        Audio.Sfx := bank;
      end;
    4:
      begin
        { the dot / bead shapes (uShapes, NeonShapeEditor); missing = the defaults }
        if not LoadShapesFile(f) then
        begin
          DefaultShapes;
          if AStartup and not FileExists(f) and not Preview.Active then
            try SaveShapesFile(f); except end;
        end;
      end;
    3:
      begin
        { every visual value (uParams registry); a file that lacks values added
          later is rewritten with them }
        if not LoadParamsFile(f, missing) then
        begin
          if AStartup and not FileExists(f) and not Preview.Active then
            try SaveParamsFile(f, 'Neon Shooter visuals - background, board, beads, effects, popups'); except end;
        end
        else if AStartup and (missing > 0) and not Preview.Active then
          try SaveParamsFile(f, 'Neon Shooter visuals - background, board, beads, effects, popups'); except end;
      end;
  else
    begin
      mfx := DefaultMenuFx;
      if not LoadMenuFxFile(f, mfx) and AStartup and not FileExists(f) then
        try SaveMenuFxFile(f, mfx); except end;
      MenuFx := mfx;
    end;
  end;
  AssetAge[AIndex] := FileAge(f);
  if (AIndex = 3) and Preview.Active then PreviewLoaded;
end;

procedure TApp.CheckAssets(dt: Double);
var
  i: Integer;
  a: LongInt;
begin
  { --preview: the editor's copy is compared by content ten times a second
    (file times are too coarse for sliders) }
  if Preview.Active and PreviewChanged(dt) then LoadAsset(3, False);
  if ShapesChanged(dt) then LoadAsset(4, False);   // --shapes: NeonShapeEditor's live copy
  AssetT += dt;
  if AssetT < 0.5 then Exit;
  AssetT := 0;
  for i := 0 to 4 do
  begin
    if (i = 3) and Preview.Active then Continue;
    if (i = 4) and (Preview.ShapesFile <> '') then Continue;
    a := FileAge(AssetFile(i));
    if (a <> -1) and (a <> AssetAge[i]) then LoadAsset(i, False);
  end;
end;

{ ---- everything visual is registered in the uParams registry and lives in
  NeonShooter.visuals: the background (uParams), the board look, the trail and
  power-up colours, the particle effects (uGameFx) and the score popups.
  Defaults are set here. }

function TrailFxColour(AIndex: Integer): TBGRAPixel;
var
  k: Integer;
begin
  k := AIndex mod MaxColours;
  Result := BGRA(BeadRGB[k, 0], BeadRGB[k, 1], BeadRGB[k, 2]);
end;

procedure TApp.RegisterVisuals;
const
  DefBead: array[0..MaxColours - 1, 0..2] of Byte = (
    (245, 150, 35), (35, 215, 240), (230, 40, 145), (150, 230, 55), (150, 75, 240), (245, 55, 55));
var
  i: Integer;
  e: TFxEmitter;
begin
  { background: the game's own defaults (calm inside the board), desktop-only values hidden }
  SetParamDefault('Grid', 'Scroll X', 0);
  SetParamDefault('Grid', 'Scroll Y', 0);
  SetParamDefault('Sparkles', 'Probability', 0.008);
  SetParamDefault('Highlights', 'Probability', 0.004);
  HideParam('Rendering', 'VSync');
  HideParam('Rendering', 'Render scale');
  HideParam('Rendering', 'Smooth upscale');
  HideParam('Rendering', 'Threads');

  ParamCategory('Board');
  Look.DimOutside := 0.55;
  Look.DimEmpty := 0.3;
  Look.Shimmer := 0.06;
  Look.BgHighlight := 0;
  Look.PopGrowth := 0.3;
  AddF('Board look', 'Dim outside', 'Dimming of the dot grid around the board (0 = black, 1 = as bright as the board).',
    Look.DimOutside, 0, 1, 0.55);
  AddF('Board look', 'Dim empty', 'Dimming of empty board cells.', Look.DimEmpty, 0, 1, 0.3);
  AddF('Board look', 'Shimmer', 'Brightness shimmer of the beads.', Look.Shimmer, 0, 1, 0.06);
  AddF('Board look', 'Background highlight', 'Ring flares of the background dots on the board.',
    Look.BgHighlight, 0, 2, 0);
  AddF('Board look', 'Pop growth', 'How much a new / glowing bead swells.', Look.PopGrowth, 0, 2, 0.3);
  for i := 0 to MaxColours - 1 do
    AddRGB('Bead colours', 'Colour ' + IntToStr(i + 1), Format('Bead colour %d.', [i + 1]),
      BeadRGB[i], BGRA(DefBead[i, 0], DefBead[i, 1], DefBead[i, 2]));

  ParamCategory('Effects');
  e := FxBurst(16, 6, 0.3, 0.6);
  e.DelayPerN := 0.02;
  FxIdx[fxPop] := RegisterFx(FxDef('Pop', e), 'Every bead of a popped group (N = bead index).');
  e := FxBurst(10, 5, 0.3, 0.9);
  e.DelayPerN := 0.03;
  FxIdx[fxDrop] := RegisterFx(FxDef('Drop', e), 'Every bead that drops off (N = bead index).');
  e := FxBurst(26, 8, 0.32, 0.7);
  e.CountPerN := 4;
  e.CountNMax := 12;
  FxIdx[fxCombo] := RegisterFx(FxDef('Combo', e, FxRing(24, 7, 0.22, 0.45)), 'A combo (N = combo count).');
  FxIdx[fxBomb] := RegisterFx(FxDef('Bomb', FxFixed(FxBurst(60, 10, 0.4, 0.9), 255, 200, 90),
    FxFixed(FxRing(40, 9, 0.3, 0.55), 255, 230, 140)), 'A bomb bead goes off.');
  FxIdx[fxRow] := RegisterFx(FxDef('New row', FxFixed(FxBurst(40, 8, 0.3, 0.6), 255, 90, 90)),
    'A new ceiling row comes in.');
  FxIdx[fxLand] := RegisterFx(FxDef('Land', FxBurst(6, 3, 0.2, 0.3)), 'A bead sticks without a pop.');
  e := FxBurst(70, 11, 0.4, 1.3);
  e.ColourMode := 2;
  FxIdx[fxLevel] := RegisterFx(FxDef('Level fireworks', e), 'Level complete: fireworks over the board.');
  with FxDefs[FxIdx[fxLevel]] do
  begin
    Position := 1; Bursts := 10; BurstDelay := 0.16; AreaX0 := 0.15; AreaX1 := 0.85;
  end;
  SetParamDefault('Effect: Level fireworks', 'Position', 1);
  SetParamDefault('Effect: Level fireworks', 'Bursts', 10);
  SetParamDefault('Effect: Level fireworks', 'Burst delay', 0.16);
  SetParamDefault('Effect: Level fireworks', 'Area x0', 0.15);
  SetParamDefault('Effect: Level fireworks', 'Area x1', 0.85);
  FxIdx[fxGameOver] := RegisterFx(FxDef('Game over', FxFixed(FxBurst(50, 9, 0.4, 1.0), 255, 60, 60)),
    'The beads reached the danger line.');
  FxBeadColour := @TrailFxColour;

  ParamCategory('Popups');
  RegisterPopupFx(1.2);
  PopupFx.FadeStart := 0.6;
  SetParamDefault('Popups', 'Fade start', 0.6);
end;

procedure TApp.LoadIni;
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(IniName);
  try
    Game.Best := ini.ReadInteger('Game', 'Best', 0);
    Game.MaxLevel := Max(1, ini.ReadInteger('Game', 'MaxLevel', 1));
    Hud.Muted := ini.ReadBool('Game', 'Muted', False);
    PlayerName := Copy(ini.ReadString('Game', 'PlayerName', ''), 1, MaxNameLen);
    Hud.StartLevel := Game.MaxLevel;
    MusicVol := EnsureRange(ini.ReadInteger('Options', 'MusicVolume', 60), 0, 100);
    SfxVol := EnsureRange(ini.ReadInteger('Options', 'SoundVolume', 80), 0, 100);
    FullScreen := ini.ReadBool('Options', 'Fullscreen', False);
    VSync := ini.ReadBool('Options', 'VSync', True);
    MusicTrack := EnsureRange(ini.ReadInteger('Options', 'MusicTrack', -1), -1, SongCount - 1);
    ApplyAudio;
  finally
    ini.Free;
  end;
end;

procedure TApp.SaveIni;
var
  ini: TIniFile;
begin
  try
    ini := TIniFile.Create(IniName);
    try
      ini.WriteInteger('Game', 'Best', Max(Game.Best, Game.Score));
      ini.WriteInteger('Game', 'MaxLevel', Game.MaxLevel);
      ini.WriteBool('Game', 'Muted', Hud.Muted);
      ini.WriteString('Game', 'PlayerName', PlayerName);
      ini.WriteInteger('Options', 'MusicVolume', MusicVol);
      ini.WriteInteger('Options', 'SoundVolume', SfxVol);
      if not ArgFullScreen then ini.WriteBool('Options', 'Fullscreen', FullScreen);
      if not ArgVSync then ini.WriteBool('Options', 'VSync', VSync);
      ini.WriteInteger('Options', 'MusicTrack', MusicTrack);
    finally
      ini.Free;
    end;
  except
    { read-only folder: progress is simply not kept }
  end;
end;

{ fit the board between the HUD bars and build a dot grid around it that
  covers the whole window }
procedure TApp.DoLayout;
var
  w, h: LongInt;
  cell, bx, by, m: Single;
begin
  SDL_GetWindowSizeInPixels(Win, @w, @h);
  L.W := Max(64, w);
  L.H := Max(64, h);
  L.TopH := Round(L.H * 0.095);
  L.BottomH := Round(L.H * 0.075);
  m := Min(L.W, L.H) * 0.035;
  cell := Min((L.W - 2 * m) / Game.W, (L.H - L.TopH - L.BottomH - m) / Game.H);
  cell := Max(6, cell);
  L.Cell := cell;
  L.BoardX0 := (L.W - Game.W * cell) / 2 + cell / 2;
  L.BoardY0 := L.TopH + (L.H - L.TopH - L.BottomH - Game.H * cell) / 2 + cell / 2;
  bx := L.BoardX0;
  by := L.BoardY0;
  GX0 := Ceil((bx + cell * 0.5) / cell) + 1;
  GY0 := Ceil((by + cell * 0.5) / cell) + 1;
  Geo.W := L.W;
  Geo.H := L.H;
  Geo.Cell := cell;
  Geo.OriginX := bx - GX0 * cell;
  Geo.OriginY := by - GY0 * cell;
  Geo.NCols := Ceil((L.W - Geo.OriginX) / cell) + 2;
  Geo.NRows := Ceil((L.H - Geo.OriginY) / cell) + 2;
  Geo.ShiftI := 0;
  Geo.ShiftJ := 0;
  Geo.Time := SimTime;
end;

procedure TApp.BuildCells(out AMaxOffX, AMaxOffY: Integer);
var
  i, j, bx, by, n: Integer;
  v: TCellView;
  mx, my: Single;
begin
  n := Geo.NCols * Geo.NRows;
  if Length(Cells) <> n then
  begin
    SetLength(Cells, n);
    SetLength(Fx, n);
  end;
  mx := 0;
  my := 0;
  for j := 0 to Geo.NRows - 1 do
    for i := 0 to Geo.NCols - 1 do
    begin
      bx := i - GX0;
      by := j - GY0;
      if (bx < 0) or (by < 0) or (bx >= Game.W) or (by >= Game.H) or (Preview.Scene = 2) then
      begin
        Cells[j * Geo.NCols + i] := Half4(0, 0, 0, -1);   // outside the board
        Fx[j * Geo.NCols + i] := Half4(0, 0, 0, 0);
        Continue;
      end;
      v := Game.View(bx, by);
      Cells[j * Geo.NCols + i] := Half4(v.R, v.G, v.B, v.Presence);
      Fx[j * Geo.NCols + i] := Half4(v.Hover, v.Flash, v.OffY, v.OffX);
      mx := Max(mx, Abs(v.OffX));
      my := Max(my, Abs(v.OffY));
    end;
  AMaxOffX := Ceil(mx);
  AMaxOffY := Ceil(my);
end;

procedure TApp.ApplyAudio;
begin
  Audio.Muted := Hud.Muted;
  Audio.MusicVolume := MusicVol / 100;
  Audio.SfxVolume := SfxVol / 100;
end;

procedure TApp.SetFullScreen(AOn: Boolean);
begin
  FullScreen := AOn;
  SDL_SetWindowFullscreen(Win, FullScreen);
end;

function OnOff(B: Boolean): string;
begin
  if B then Result := 'ON' else Result := 'OFF';
end;

procedure TApp.PickSong(ANew: Boolean);
var
  k, cur: Integer;
begin
  if MusicTrack >= 0 then
  begin
    Audio.SelectSong(MusicTrack);
    Exit;
  end;
  { shuffle: a different song }
  cur := Audio.CurrentSong;
  if (cur >= 0) and not ANew then Exit;
  k := Random(SongCount);
  if (SongCount > 1) and (k = cur) then k := (k + 1 + Random(SongCount - 1)) mod SongCount;
  Audio.SelectSong(k);
end;

procedure TApp.StartGameLevel(ALevel: Integer; AKeepScore, ANewSong: Boolean);
begin
  Paused := False;
  Game.StartLevel(ALevel, AKeepScore);
  if ANewSong then PickSong(True);
end;

procedure TApp.OpenPause;
begin
  if Paused or (Game.State = gsTitle) then Exit;
  Paused := True;
  ShowMenu(2, True);
  Audio.Play(gsndMenuSelect, 0);
end;

procedure TApp.ResumeGame;
begin
  Paused := False;
  Hud.Menu.Active := False;
  Audio.Play(gsndMenuSelect, 0);
end;

procedure TApp.BuildMenu;
  procedure Add(const C, V: string);
  var
    n: Integer;
  begin
    n := Length(Hud.Menu.Items);
    SetLength(Hud.Menu.Items, n + 1);
    Hud.Menu.Items[n].Caption := C;
    Hud.Menu.Items[n].Value := V;
  end;
var
  track: string;
begin
  SetLength(Hud.Menu.Items, 0);
  case MenuScreen of
    0:
      begin
        Add('PLAY', '');
        Add('LEVEL', IntToStr(Hud.StartLevel));
        Add('HIGH SCORES', '');
        Add('ACHIEVEMENTS', '');
        Add('OPTIONS', '');
        Add('CHEAT CODE', '');
        Add('EXIT', '');
      end;
    3, 4:
      Add('BACK', '');
    5:
      begin
        Add('START', '');
        Add('BACK', '');
      end;
    1:
      begin
        if MusicTrack < 0 then track := 'SHUFFLE' else track := UpperCase(SongName(MusicTrack));
        Add('MUSIC', track);
        Add('MUSIC VOLUME', IntToStr(MusicVol) + '%');
        Add('SOUND VOLUME', IntToStr(SfxVol) + '%');
        Add('FULLSCREEN', OnOff(FullScreen));
        Add('VSYNC', OnOff(VSync));
        Add('BACK', '');
      end;
  else
    begin
      Add('RESUME', '');
      Add('RESTART LEVEL', '');
      Add('OPTIONS', '');
      Add('MAIN MENU', '');
      Add('EXIT', '');
    end;
  end;
  MenuSel := EnsureRange(MenuSel, 0, High(Hud.Menu.Items));
  Hud.Menu.Active := True;
  if Paused then Hud.Menu.Title := 'PAUSED'
  else if ScoresOpen then Hud.Menu.Title := 'GAME OVER'
  else Hud.Menu.Title := 'NEON SHOOTER';
  Hud.Menu.NowPlaying := SongName(Audio.CurrentSong);
  Hud.Menu.Screen := MenuScreen;
  Hud.Menu.Sel := MenuSel;
  Hud.Menu.Time := MenuTime;
  Hud.Menu.ItemTime := MenuItemTime;
  Hud.Menu.Clock := SimTime;
end;

procedure TApp.ShowMenu(AScreen: Integer; AIntro: Boolean);
begin
  MenuScreen := AScreen;
  MenuSel := 0;
  MenuItemTime := 0;
  if AIntro then MenuTime := 0;
end;

procedure TApp.MenuMove(ADelta: Integer);
var
  n: Integer;
begin
  n := Length(Hud.Menu.Items);
  if n = 0 then Exit;
  MenuSel := (MenuSel + ADelta + n) mod n;
  Audio.Play(gsndMenuMove, 0);
end;

{ Left / Right on a value item }
procedure TApp.MenuChange(ADelta: Integer);
begin
  if MenuScreen = 0 then
  begin
    if MenuSel = 1 then
    begin
      Hud.StartLevel := EnsureRange(Hud.StartLevel + ADelta, 1, Game.MaxLevel);
      Audio.Play(gsndMenuMove, 0);
    end;
    Exit;
  end;
  if MenuScreen <> 1 then Exit;
  case MenuSel of
    0:
      begin
        { -1 (shuffle), 0 .. SongCount - 1; the chosen song starts at once }
        MusicTrack := MusicTrack + ADelta;
        if MusicTrack < -1 then MusicTrack := SongCount - 1;
        if MusicTrack >= SongCount then MusicTrack := -1;
        PickSong(True);
      end;
    1: MusicVol := EnsureRange(MusicVol + ADelta * 10, 0, 100);
    2: SfxVol := EnsureRange(SfxVol + ADelta * 10, 0, 100);
    3:
      begin
        SetFullScreen(not FullScreen);
        ArgFullScreen := False;
      end;
    4:
      begin
        VSync := not VSync;
        ArgVSync := False;
        Gpu.SetVSync(VSync);
      end;
  else
    Exit;
  end;
  ApplyAudio;
  Audio.Play(gsndMenuMove, 0);
  SaveIni;
end;

procedure TApp.MenuChoose;
begin
  case MenuScreen of
    0:
      case MenuSel of
        0:
          begin
            Audio.Play(gsndMenuSelect, 0);
            StartGameLevel(Hud.StartLevel, False, True);
          end;
        1:
          if Game.MaxLevel > 1 then
          begin
            { cycle through the unlocked levels }
            if Hud.StartLevel >= Game.MaxLevel then Hud.StartLevel := 1
            else Inc(Hud.StartLevel);
            Audio.Play(gsndMenuMove, 0);
          end;
        2, 3:
          begin
            Audio.Play(gsndMenuSelect, 0);
            Hud.NewRank := -1;
            ShowMenu(MenuSel + 1, False);   // 3 = high scores, 4 = achievements
          end;
        4:
          begin
            Audio.Play(gsndMenuSelect, 0);
            OptionsFrom := 0;
            ShowMenu(1, False);
          end;
        5:
          begin
            Audio.Play(gsndMenuSelect, 0);
            OpenCodeEntry;
          end;
        6:
          Running := False;
      end;
    1:
      if MenuSel = 5 then MenuBack else MenuChange(1);
    3, 4:
      MenuBack;
    5:
      if MenuSel = 0 then ApplyCode else MenuBack;
  else
    case MenuSel of
      0: ResumeGame;
      1:
        begin
          Audio.Play(gsndMenuSelect, 0);
          Game.Score := Game.LevelStartScore;
          StartGameLevel(Game.Level, True, False);
        end;
      2:
        begin
          Audio.Play(gsndMenuSelect, 0);
          OptionsFrom := 2;
          ShowMenu(1, False);
        end;
      3:
        begin
          Audio.Play(gsndMenuSelect, 0);
          Game.Best := Max(Game.Best, Game.Score);
          SaveIni;
          Paused := False;
          Hud.StartLevel := Min(Hud.StartLevel, Game.MaxLevel);
          Game.ShowTitle;
          ShowMenu(0, True);
        end;
      4:
        Running := False;
    end;
  end;
end;

procedure TApp.MenuBack;
var
  k: Integer;
begin
  case MenuScreen of
    1:
      begin
        Audio.Play(gsndMenuSelect, 0);
        ShowMenu(OptionsFrom, False);
        if OptionsFrom = 0 then MenuSel := 4 else MenuSel := 2;   // the OPTIONS item
      end;
    2:
      ResumeGame;
    5:
      begin
        Audio.Play(gsndMenuSelect, 0);
        CloseCodeEntry;
        ShowMenu(0, False);
        MenuSel := 5;               // the CHEAT CODE item
      end;
    3, 4:
      begin
        Audio.Play(gsndMenuSelect, 0);
        Hud.NewRank := -1;
        if ScoresOpen then
          ScoresOpen := False       // back to the game-over panel
        else
        begin
          k := MenuScreen;
          ShowMenu(0, False);
          MenuSel := k - 1;          // the HIGH SCORES / ACHIEVEMENTS item
        end;
      end;
  else
    Running := False;
  end;
end;

{ left click / Enter }
procedure TApp.Activate;
begin
  case Game.State of
    gsTitle:
      MenuChoose;
    gsLevelDone:
      begin
        SaveIni;
        StartGameLevel(Game.Level + 1, True, True);
      end;
    gsGameOver:
      if Hud.NameEntry then
        SubmitName
      else
      begin
        Game.Score := Game.LevelStartScore;
        StartGameLevel(Game.Level, True, False);
      end;
  end;
end;

{ ---- continue codes (uGameCode): shown when a level is completed, typed or
  pasted on the CHEAT CODE screen (main menu) }

function CtrlDown: Boolean;
begin
  Result := (SDL_GetModState and SDL_KMOD_CTRL) <> 0;
end;

function TApp.LevelCode: string;
begin
  Result := MakeGameCode(GameIdShooter, Game.Level, Game.Score, 0);
end;

procedure TApp.CopyLevelCode;
var
  code: string;
begin
  code := LevelCode;
  if SDL_SetClipboardText(PAnsiChar(code)) then
  begin
    Hud.CodeCopied := True;
    Audio.Play(gsndMenuSelect, 0);
  end;
end;

procedure TApp.OpenCodeEntry;
begin
  Hud.CodeText := '';
  Hud.CodeMsg := '';
  ShowMenu(5, False);
  SDL_StartTextInput(Win);
end;

procedure TApp.CloseCodeEntry;
begin
  SDL_StopTextInput(Win);
  Hud.CodeMsg := '';
end;

procedure TApp.AddCodeText(const S: string);
begin
  Hud.CodeText := Copy(CleanGameCode(Hud.CodeText + S), 1, GameCodeLen);
  Hud.CodeMsg := '';
  Audio.Play(gsndMenuMove, 0);
end;

procedure TApp.PasteCode;
var
  p: PAnsiChar;
  txt: string;
begin
  p := SDL_GetClipboardText;
  if p = nil then Exit;
  txt := StrPas(p);
  SDL_free(p);
  Hud.CodeText := '';
  AddCodeText(txt);
end;

{ a valid code continues with the level after the one it was made on }
procedure TApp.ApplyCode;
var
  lv, sc, li: Integer;
begin
  if not ReadGameCode(Hud.CodeText, GameIdShooter, lv, sc, li) then
  begin
    if Length(Hud.CodeText) < GameCodeLen then Hud.CodeMsg := Format('the code has %d letters', [GameCodeLen])
    else Hud.CodeMsg := 'INVALID CODE';
    Audio.Play(gsndInvalid, 0);
    Exit;
  end;
  CloseCodeEntry;
  Audio.Play(gsndMenuSelect, 0);
  StartGameLevel(Min(lv + 1, 255), False, True);
  Game.Score := sc;
  Game.LevelStartScore := sc;
  Hud.StartLevel := Game.Level;
end;

{ ---- --preview (uPreview): scenes for NeonVisualEditor }

procedure TApp.SetScene(AScene: Integer);
begin
  Preview.Scene := (AScene + PreviewScenes) mod PreviewScenes;
  HudForce := True;
  AutoT := 0;
  Paused := False;
  ScoresOpen := False;
  if Preview.Scene = 1 then
  begin
    Game.ShowTitle;
    ShowMenu(0, True);
  end;
  SDL_SetWindowTitle(Win, PAnsiChar(PreviewTitle('Neon Shooter')));
end;

{ True: the key was for the preview (other game keys are ignored) }
function TApp.PreviewKey(AKey: TSDL_Keycode): Boolean;
begin
  Result := True;
  case AKey of
    SDLK_1, SDLK_KP_1: SetScene(0);
    SDLK_2, SDLK_KP_2: SetScene(1);
    SDLK_3, SDLK_KP_3: SetScene(2);
    SDLK_TAB: SetScene(Preview.Scene + 1);
    SDLK_ESCAPE: Running := False;
    SDLK_M, SDLK_F11: Result := False;
  end;
end;

procedure TApp.HandleKey(AKey: TSDL_Keycode);
begin
  if Preview.Active and PreviewKey(AKey) then Exit;
  if Hud.NameEntry then
  begin
    { typing a name for the high-score table (the letters come as text input) }
    case AKey of
      SDLK_BACKSPACE:
        if Hud.NameText <> '' then
        begin
          SetLength(Hud.NameText, Length(Hud.NameText) - 1);
          Audio.Play(gsndMenuMove, 0);
        end;
      SDLK_RETURN, SDLK_KP_ENTER, SDLK_ESCAPE:
        SubmitName;
    end;
    Exit;
  end;
  if MenuShown and (MenuScreen = 5) then
  begin
    { CHEAT CODE: letters come as text input }
    case AKey of
      SDLK_BACKSPACE:
        if Hud.CodeText <> '' then
        begin
          SetLength(Hud.CodeText, Length(Hud.CodeText) - 1);
          Hud.CodeMsg := '';
          Audio.Play(gsndMenuMove, 0);
        end;
      SDLK_RETURN, SDLK_KP_ENTER:
        if MenuSel = 1 then MenuBack else ApplyCode;
      SDLK_ESCAPE:
        MenuBack;
      SDLK_UP:
        MenuMove(-1);
      SDLK_DOWN:
        MenuMove(1);
      SDLK_P, SDLK_V:
        if CtrlDown then PasteCode;
    end;
    Exit;
  end;
  if (AKey = SDLK_C) and CtrlDown and (Game.State = gsLevelDone) and not MenuShown then
  begin
    CopyLevelCode;
    Exit;
  end;
  if MenuShown then
  begin
    case AKey of
      SDLK_P: if Paused then ResumeGame;
      SDLK_UP, SDLK_W: MenuMove(-1);
      SDLK_DOWN, SDLK_S: MenuMove(1);
      SDLK_LEFT, SDLK_A: MenuChange(-1);
      SDLK_RIGHT, SDLK_D: MenuChange(1);
      SDLK_RETURN, SDLK_KP_ENTER, SDLK_SPACE: MenuChoose;
      SDLK_ESCAPE, SDLK_BACKSPACE: MenuBack;
      SDLK_M:
        begin
          Hud.Muted := not Hud.Muted;
          ApplyAudio;
          SaveIni;
        end;
      SDLK_F11:
        begin
          SetFullScreen(not FullScreen);
          SaveIni;
        end;
    end;
    Exit;
  end;
  case AKey of
    SDLK_ESCAPE, SDLK_P:
      OpenPause;
    SDLK_LEFT, SDLK_A: Game.AimLeft := True;
    SDLK_RIGHT, SDLK_D: Game.AimRight := True;
    SDLK_SPACE, SDLK_UP, SDLK_W:
      Game.Shoot;
    SDLK_X, SDLK_DOWN, SDLK_S, SDLK_TAB:
      Game.Swap;
    SDLK_RETURN, SDLK_KP_ENTER:
      if Game.State in [gsLevelDone, gsGameOver] then Activate else Game.Shoot;
    SDLK_H:
      if Game.State = gsGameOver then
      begin
        Audio.Play(gsndMenuSelect, 0);
        ScoresOpen := True;
        ShowMenu(3, True);
      end;
    SDLK_R:
      if Game.State in [gsPlaying, gsGameOver, gsLevelDone] then
      begin
        Game.Score := Game.LevelStartScore;
        StartGameLevel(Game.Level, True, False);
      end;
    SDLK_M:
      begin
        Hud.Muted := not Hud.Muted;
        ApplyAudio;
        SaveIni;
      end;
    SDLK_F11:
      begin
        SetFullScreen(not FullScreen);
        SaveIni;
      end;
  end;
end;

function MenuItemAt(const R: array of TRect; X, Y: Single): Integer;
var
  i: Integer;
begin
  for i := 0 to High(R) do
    if (X >= R[i].Left) and (X < R[i].Right) and (Y >= R[i].Top) and (Y < R[i].Bottom) then
      Exit(i);
  Result := -1;
end;

procedure TApp.HandleEvent(const E: TSDL_Event);
var
  d: Single;
  k: Integer;
  txt: string;
begin
  case E._type of
    SDL_EVENT_QUIT, SDL_EVENT_WINDOW_CLOSE_REQUESTED:
      Running := False;
    SDL_EVENT_KEY_DOWN:
      if not E.key._repeat then HandleKey(E.key.key);
    SDL_EVENT_KEY_UP:
      case E.key.key of
        SDLK_LEFT, SDLK_A: Game.AimLeft := False;
        SDLK_RIGHT, SDLK_D: Game.AimRight := False;
      end;
    SDL_EVENT_TEXT_INPUT:
      if Hud.NameEntry and (E.text.Text <> nil) then
      begin
        { printable ASCII only (the HUD font and the ini file stay simple) }
        txt := StrPas(E.text.Text);
        for k := 1 to Length(txt) do
          if (txt[k] >= ' ') and (txt[k] <= '~') and (txt[k] <> '|') and (Length(Hud.NameText) < MaxNameLen) then
            Hud.NameText := Hud.NameText + UpCase(txt[k]);
        Audio.Play(gsndMenuMove, 0);
      end
      else if MenuShown and (MenuScreen = 5) and (E.text.Text <> nil) then
        AddCodeText(StrPas(E.text.Text));
    SDL_EVENT_WINDOW_FOCUS_LOST:
      if not AutoPlay then OpenPause;
    SDL_EVENT_MOUSE_MOTION:
      begin
        d := SDL_GetWindowPixelDensity(Win);
        MouseX := E.motion.x * d;
        MouseY := E.motion.y * d;
        if Hud.Menu.Active then
        begin
          k := MenuItemAt(Hud.ItemRects, MouseX, MouseY);
          if (k >= 0) and (k <> MenuSel) and (k < Length(Hud.Menu.Items)) then
          begin
            MenuSel := k;
            Audio.Play(gsndMenuMove, 0);
          end;
        end
        else if (Game.State = gsPlaying) and not AutoPlay then
          Game.AimAt((MouseX - L.BoardX0) / L.Cell, (MouseY - L.BoardY0) / L.Cell);
      end;
    SDL_EVENT_MOUSE_BUTTON_DOWN:
      begin
        if Preview.Active then Exit;   // the preview plays by itself
        d := SDL_GetWindowPixelDensity(Win);
        MouseX := E.button.x * d;
        MouseY := E.button.y * d;
        if Hud.Menu.Active then
        begin
          k := MenuItemAt(Hud.ItemRects, MouseX, MouseY);
          if E.button.button = SDL_BUTTON_RIGHT then
          begin
            { back one screen; never exits the game from the main menu }
            if MenuScreen <> 0 then MenuBack;
          end
          else if (k >= 0) and (k < Length(Hud.Menu.Items)) then
          begin
            MenuSel := k;
            { value items: left half lowers, right half raises }
            if Hud.Menu.Items[k].Value <> '' then
            begin
              if MouseX < (Hud.ItemRects[k].Left + Hud.ItemRects[k].Right) / 2 then MenuChange(-1)
              else MenuChange(1);
            end
            else
              MenuChoose;
          end;
          Exit;
        end;
        if (E.button.button = SDL_BUTTON_LEFT) and (Game.State in [gsLevelDone, gsGameOver]) then
          Activate
        else if Game.State = gsPlaying then
        begin
          { the mouse aims; left shoots, right swaps }
          Game.AimAt((MouseX - L.BoardX0) / L.Cell, (MouseY - L.BoardY0) / L.Cell);
          if E.button.button = SDL_BUTTON_RIGHT then Game.Swap else Game.Shoot;
        end;
      end;
  end;
end;

function TApp.MenuShown: Boolean;
begin
  Result := (Game.State = gsTitle) or Paused or ScoresOpen;
end;

{ game over: a score for the top 10 asks for a name }
procedure TApp.GameOverCheck;
var
  rank: Integer;
begin
  if (Game.State = gsGameOver) and (LastState <> gsGameOver) then
  begin
    AutoT := 0;
    rank := Ach.ScoreRank(Game.Score);
    Hud.ScoreRank := rank;
    if rank >= 0 then
    begin
      Hud.NameEntry := True;
      Hud.NameText := PlayerName;
      if AutoPlay and (Hud.NameText = '') then Hud.NameText := 'AUTOPILOT';
      SDL_StartTextInput(Win);
    end;
  end;
  if (Game.State <> gsGameOver) and Hud.NameEntry then
  begin
    Hud.NameEntry := False;
    SDL_StopTextInput(Win);
  end;
  LastState := Game.State;
end;

procedure TApp.SubmitName;
begin
  if not Hud.NameEntry then Exit;
  Hud.NameEntry := False;
  SDL_StopTextInput(Win);
  PlayerName := Trim(Hud.NameText);
  Hud.NewRank := Ach.AddScore(PlayerName, Game.Score, Game.Level);
  SaveIni;
  Audio.Play(gsndLevel, 0);
  { show the table with the new row lit }
  ScoresOpen := True;
  ShowMenu(3, True);
end;

{ the game's effect events become particle bursts (cell -> window pixels) }
procedure TApp.SpawnFx;
var
  i: Integer;
  ev: TFxEvent;
  brd: TFxBoard;
begin
  Parts.Gravity := L.Cell * ParticleGravity;
  Parts.Drag := ParticleDrag;
  brd.X0 := L.BoardX0;
  brd.Y0 := L.BoardY0;
  brd.Cell := L.Cell;
  brd.W := Game.W;
  brd.H := Game.H;
  for i := 0 to High(Game.Fx) do
  begin
    ev := Game.Fx[i];
    brd.EventX := ev.X;
    { the effect definitions come from NeonShooter.visuals (uGameFx) }
    SpawnFxDef(Parts, FxIdx[ev.Kind], L.BoardX0 + ev.X * L.Cell, L.BoardY0 + ev.Y * L.Cell, ev.R, ev.G, ev.B,
      ev.N, brd);
  end;
  SetLength(Game.Fx, 0);
end;

procedure TApp.BenchReport;
var
  f: TextFile;
  n, i, missed: Integer;
  sum, mx: Double;
  sorted: array of Single;
  t: Single;
  j: Integer;
begin
  n := Length(BenchDt);
  if n = 0 then Exit;
  sorted := Copy(BenchDt);
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
  mx := 0;
  missed := 0;
  for i := 0 to n - 1 do
  begin
    sum += BenchDt[i];
    mx := Max(mx, BenchDt[i]);
    if BenchDt[i] > 25 then Inc(missed);
  end;
  AssignFile(f, ChangeFileExt(ParamStr(0), '-bench.txt'));
  Rewrite(f);
  WriteLn(f, Format('Neon Shooter benchmark: driver %s, shaders %s, window %d x %d, board %d x %d',
    [Gpu.Driver, Gpu.ShaderInfo, L.W, L.H, Game.W, Game.H]));
  WriteLn(f, Format('frames %d in %.1f s -> %.2f fps', [n, sum / 1000, n * 1000 / sum]));
  WriteLn(f, Format('interval ms: mean %.2f median %.2f p99 %.2f max %.2f; over 25 ms: %d',
    [sum / n, sorted[n div 2], sorted[Min(n - 1, Round(n * 0.99))], mx, missed]));
  WriteLn(f, Format('worst stage ms: game update %.2f, HUD %.2f, cells %.2f, GPU submit/wait %.2f',
    [StageMax[0], StageMax[1], StageMax[2], StageMax[3]]));
  CloseFile(f);
end;

procedure TApp.AutoStep(dt: Double);
begin
  Game.AutoPilot := Game.State <> gsTitle;
  { --autocrash: let go of the steering after a few sparkles (tests game over) }
  AutoT += dt;
  if ScoresOpen then
  begin
    if AutoT > 2.5 then
    begin
      AutoT := 0;
      MenuBack;
    end;
    Exit;
  end;
  case Game.State of
    gsTitle, gsLevelDone, gsGameOver:
      if AutoT > 1.5 then
      begin
        AutoT := 0;
        if Game.State = gsTitle then MenuSel := 0;
        Activate;
      end;
  end;
end;

procedure TApp.Run;
var
  e: TSDL_Event;
  t0, now, dt, ts: Double;
  r: TSDL_Rect;
  w, h, mox, moy: Integer;
  hudDirty: Boolean;
  lk: TGameLook;
begin
  if not SDL_Init(SDL_INIT_VIDEO or SDL_INIT_AUDIO) then Fail('SDL_Init failed: ' + StrPas(SDL_GetError));
  if not TTF_Init then Fail('TTF_Init failed: ' + StrPas(SDL_GetError));
  if not SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @r) then
  begin
    r.x := 0; r.y := 0; r.w := 1280; r.h := 900;
  end;
  h := Round(r.h * 0.9);
  w := Round(h * 0.68);
  Win := SDL_CreateWindow('Neon Shooter  -  NeonGrid SDL3 GPU', w, h,
    SDL_WINDOW_RESIZABLE or SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if Win = nil then Fail('SDL_CreateWindow failed: ' + StrPas(SDL_GetError));
  try
    Gpu := TGameGPU.Create(Win);
  except
    on Ex: Exception do Fail(Ex.Message);
  end;
  if HasArg('novsync') then Gpu.SetVSync(False);
  AutoCrash := HasArg('autocrash');
  AutoPlay := HasArg('autoplay') or AutoCrash;
  ArgVSync := HasArg('novsync');
  ArgFullScreen := HasArg('fullscreen');
  if ArgFullScreen then
  begin
    FullScreen := True;
    SDL_SetWindowFullscreen(Win, True);
  end;
  for w := 1 to ParamCount do
    if Pos('--bench=', LowerCase(ParamStr(w))) = 1 then
      BenchSecs := StrToFloatDef(Copy(ParamStr(w), 9, 20), 10);

  { the background keeps the NeonGrid look, calm inside the board; every
    visual value is registered with its default (NeonShooter.visuals) }
  RegisterVisuals;

  Renderer := TNeonRenderer.Create;
  Game := TShooterGame.Create;
  Parts := TParticles.Create;
  Audio := TGameAudio.Create;
  Hud := TGameHud.Create;
  Game.OnSound := @Audio.Play;
  IniName := ChangeFileExt(ParamStr(0), '.ini');
  { --preview: keeps no records (a temp copy of the ini) }
  PreviewInit;
  if Preview.Active then
  begin
    AutoPlay := True;
    IniName := PreviewIni(IniName);
  end;
  Ach := TAchievements.Create(IniName);
  Hud.Ach := Ach;
  VSync := True;
  LoadAsset(0, True);   // songs before LoadIni (it checks the track)
  LoadAsset(1, True);
  LoadAsset(2, True);
  LoadAsset(3, True);
  LoadAsset(4, True);   // dot / bead shapes (NeonShapeEditor)
  LoadIni;
  if Preview.Active then
  begin
    Hud.Muted := True;
    ApplyAudio;
    SDL_SetWindowTitle(Win, PAnsiChar(PreviewTitle('Neon Shooter')));
  end;
  if ArgVSync then VSync := False;
  if ArgFullScreen then FullScreen := True;
  Gpu.SetVSync(VSync);
  if FullScreen then SDL_SetWindowFullscreen(Win, True);
  Game.ShowTitle;
  ShowMenu(0, True);
  Randomize;
  PickSong(True);

  Running := True;
  t0 := SDL_GetTicksNS / 1e9;
  while Running do
  begin
    while SDL_PollEvent(@e) do HandleEvent(e);
    if (SDL_GetWindowFlags(Win) and SDL_WINDOW_MINIMIZED) <> 0 then
    begin
      SDL_Delay(20);
      Continue;
    end;
    now := SDL_GetTicksNS / 1e9;
    dt := now - t0;
    t0 := now;
    SimTime += Min(dt, 0.1);
    CheckAssets(dt);
    MenuTime += Min(dt, 0.1);
    MenuItemTime += Min(dt, 0.1);
    ts := SDL_GetTicksNS / 1e6;
    if not Paused then
    begin
      Game.Update(dt);
      Parts.Update(Min(dt, 0.05));
    end;
    if not Preview.Active and Ach.Check(Game) then Audio.Play(gsndGold, 0);
    Ach.UpdateToasts(Min(dt, 0.1));
    if not Preview.Active then GameOverCheck;
    { the announcer: a new combo (not the demo behind the title) }
    if (Game.Combo <> LastCombo) and not Game.Demo and (Game.State <> gsTitle) then
    begin
      if Game.Combo > LastCombo then
        if Game.Combo >= 2 then Audio.Say(ComboClipName(Game.Combo));
    end;
    LastCombo := Game.Combo;
    if BenchT > 2 then StageMax[0] := Max(StageMax[0], SDL_GetTicksNS / 1e6 - ts);
    if MenuShown then
      BuildMenu
    else
      Hud.Menu.Active := False;
    if Game.State = gsTitle then Audio.SetMusicIntensity(0) else Audio.SetMusicIntensity(1);
    Audio.SetMuffle(Paused);
    DoLayout;
    if AutoPlay and (Preview.Scene <> 1) then AutoStep(dt);
    Renderer.PrepareDisplayGeom(Geo);   // BGRABitmap sprite at the bead size
    ts := SDL_GetTicksNS / 1e6;
    BuildCells(mox, moy);
    SpawnFx;
    PartCount := Parts.Build;
    if BenchT > 2 then StageMax[2] := Max(StageMax[2], SDL_GetTicksNS / 1e6 - ts);
    ts := SDL_GetTicksNS / 1e6;
    if Game.State = gsLevelDone then
      Hud.LevelCode := LevelCode
    else
    begin
      Hud.LevelCode := '';
      Hud.CodeCopied := False;
    end;
    hudDirty := Hud.Update(Game, L);
    if BenchT > 2 then StageMax[1] := Max(StageMax[1], SDL_GetTicksNS / 1e6 - ts);
    ts := SDL_GetTicksNS / 1e6;
    if Preview.Scene = 2 then
    begin
      { --preview background scene: the whole grid at full brightness, no HUD }
      lk := Look;
      lk.DimOutside := 1;   // a brightness factor: the full background
      if (BlankHud = nil) or (BlankHud.Width <> Hud.Bmp.Width) or (BlankHud.Height <> Hud.Bmp.Height) then
      begin
        BlankHud.Free;
        BlankHud := TBGRABitmap.Create(Hud.Bmp.Width, Hud.Bmp.Height, BGRAPixelTransparent);
        HudForce := True;
      end;
      Gpu.Frame(Renderer, Geo, lk, Cells, Fx, mox, moy, BlankHud, HudForce, Parts.GPU, 0);
    end
    else
      Gpu.Frame(Renderer, Geo, Look, Cells, Fx, mox, moy, Hud.Bmp, hudDirty or HudForce, Parts.GPU, PartCount);
    HudForce := False;
    if BenchT > 2 then StageMax[3] := Max(StageMax[3], SDL_GetTicksNS / 1e6 - ts);
    if BenchSecs > 0 then
    begin
      BenchT += dt;
      if BenchT > 2 then   // after 2 s warm-up
      begin
        SetLength(BenchDt, Length(BenchDt) + 1);
        BenchDt[High(BenchDt)] := dt * 1000;
        if BenchT > 2 + BenchSecs then
        begin
          BenchReport;
          Running := False;
        end;
      end;
    end;
  end;

  Game.Best := Max(Game.Best, Game.Score);
  SaveIni;
  BlankHud.Free;
  Hud.Free;
  Audio.Free;
  Ach.Free;
  Parts.Free;
  Game.Free;
  Renderer.Free;
  Gpu.Free;
  SDL_DestroyWindow(Win);
  TTF_Quit;
  SDL_Quit;
end;

var
  App: TApp;

begin
  App := TApp.Create;
  try
    App.Run;
  finally
    App.Free;
  end;
end.
