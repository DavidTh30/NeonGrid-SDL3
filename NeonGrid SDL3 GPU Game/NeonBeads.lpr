program NeonBeads;

{ Neon Beads - a bead-popping puzzle on the animated neon dot grid.

    NeonBeads.lpr   window, input, layout, main loop (this file)
    uBeadGame.pas   rules: groups, special beads, stones, scoring, gravity,
                    levels, stars, time attack, undo, animation
    uAchievements   achievements, high scores, stars, XP ranks, bead themes
    uParticles.pas  spark particle bursts (CPU simulation, drawn by a GPU pass)
    uGameGPU.pas    SDL3 GPU output: dots / composite / particles / HUD passes
    uGPUShaders.pas DXIL + DXBC bytecode built by build_shaders.ps1 from
                    shaders\*.hlsl (the game versions of the NeonGrid shaders)
    uRenderer.pas   NeonGrid colour model + BGRABitmap dot sprite
    uGameHud.pas    HUD, animated menus and screens (BGRABitmap + SDL3_ttf)
    uGameAudio.pas  synthesized sound effects + mixer (SDL3 audio stream)
    uGameMusic.pas  live-synthesized background music

  Main menu: PLAY, MODE (CLASSIC / TIME ATTACK / SURVIVAL / VS BOT), LEVEL
  (classic start level, with its stars) or BOT (VS BOT: EASY / NORMAL /
  HARD), HIGH SCORES (one table per mode), ACHIEVEMENTS (GENERAL / SURVIVAL /
  VS BOT groups), OPTIONS (music track, music / sound
  volume, bead THEME, fullscreen, VSync), EXIT - mouse, or Up/Down +
  Left/Right + Enter. The main menu also shows the player rank and XP.
  In game: hover shows the move, left click pops it, right click undoes.
  Special beads: BOMB and LINE (click alone to blast), x2, RAINBOW; grey
  STONES only break in blasts. Pops, blasts, new specials, cleared boards and
  levels burst into GPU particles.
  Esc or P pauses (RESUME, RESTART, OPTIONS, MAIN MENU, EXIT); the game also
  pauses when the window loses focus.
  Keys: U undo, R restart, H high scores (after a game), M mute, F11 fullscreen.
  A game-over score that makes the top 10 of its mode asks for a name.
  VS BOT: the player's board on the left, the bot's on the right (the window
  widens to landscape for the match and gets its size back afterwards).
  Music: 7 synthesized songs, one fixed or SHUFFLE (a new song every level).
  Command line: --fullscreen, --novsync (uncapped frame rate), --autoplay (plays
  by itself), --autotime (autoplay in TIME ATTACK), --autosurvival (autoplay
  in SURVIVAL), --autovs (autoplay against the bot), --bench=SECONDS (frame
  pacing report in NeonBeads-bench.txt), --preview=FILE (the GPU preview window
  of NeonVisualEditor, see uPreview).
  Needs SDL3.dll and SDL3_ttf.dll next to the program and Direct3D 12.
  Progress (best score, levels, stars, XP, theme, high scores, achievements)
  is kept in NeonBeads.ini. Music, sound effects and menu effects are
  NeonBeads.music / .sfx / .menufx (shared units in ..\NeonGrid SDL3 GPU
  Shared; editors in ..\NeonGrid SDL3 GPU Tools); the game reloads them when
  they change. }

{$mode objfpc}{$H+}
{$COPERATORS ON}
{$IFDEF WINDOWS}{$APPTYPE GUI}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Types, Math, IniFiles, SDL3, SDL3_ttf, BGRABitmap, BGRABitmapTypes,
  uParams, uRenderer, uGPUShaders, uGameCode, uBeadGame, uAchievements, uParticles, uGameAudio, uGameMusic, uGameSfx, uMenuFx, uGameFx, uGameHud, uGameGPU, uPreview, uVoice, uShapes, uBeadRules, uBeadBot, uIronFlow;

type
  TApp = class
    Win: PSDL_Window;
    Gpu: TGameGPU;
    Renderer: TNeonRenderer;
    Game: TBeadGame;
    Bot: TBeadGame;               // VS BOT: the bot's board
    BotLevel: Integer;            // 0 EASY, 1 NORMAL, 2 HARD (menu choice)
    BotAI: TBeadBot;              // the VS BOT opponent (uBeadBot)
    LeftAI: TBeadBot;             // --vssim: the bot on the player's side
    SimEndT: Double;              // --vssim: seconds since the match ended
    VsRecorded: Boolean;          // the match result went into the statistics
    VsSaved: TSDL_Rect;           // window before it widened for VS BOT (w = 0: none)
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
    GX0b: Integer;                // VS BOT: grid column of the bot board's cell (0, 0)
    Cells, Fx: array of THalf4;
    MouseX, MouseY: Single;       // window pixels
    Running, FullScreen, VSync: Boolean;
    ArgVSync, ArgFullScreen: Boolean;  // set by --novsync / --fullscreen: not saved
    MusicVol, SfxVol: Integer;       // 0..100
    MenuScreen, MenuSel: Integer;    // 0 = main, 1 = options, 2 = pause, 3 = high scores, 4 = achievements
    Paused: Boolean;
    OptionsFrom: Integer;            // screen to return to from the options
    ScoresOpen: Boolean;             // high-score table shown over the game-over panel
    PlayerName: string;              // last name typed for the high scores
    PlayMode: TGameMode;             // mode PLAY starts
    LastState: TGameState;
    MusicTrack: Integer;             // -1 = shuffle
    MenuTime, MenuItemTime: Single;
    SimTime: Double;
    IniName: string;
    AssetAge: array[0..7] of LongInt;
    BlankHud: TBGRABitmap;      // --preview background scene: no HUD
    HudForce: Boolean;          // upload the HUD on the next frame (scene change)
    FxIdx: array[TFxKind] of Integer;  // effect definitions (uGameFx) of the game's effects   // file times of the asset files
    AssetT: Double;                    // seconds since the last file check
    AutoPlay: Boolean;          // --autoplay: pops groups by itself (testing / attract)
    AutoTime: Boolean;          // --autotime: autoplay in time attack
    AutoSurvival: Boolean;      // --autosurvival: autoplay in survival
    AutoVs: Boolean;            // --autovs: autoplay against the bot
    AutoT: Double;
    BenchSecs, BenchT: Double;  // --bench=SECONDS: frame pacing report, then quit
    BenchDt: array of Single;
    StageMax: array[0..4] of Double;   // worst ms: update, hud, cells, gpu, checks (bench report)
    procedure BenchReport;
    procedure SpawnFx;
    procedure SpawnFxOf(AGame: TBeadGame; AX0: Single);
    procedure StartVersus;
    procedure VersusStep;
    procedure BotStep(dt: Double);
    procedure BotSound(ASound: TGameSound; AParam: Integer);
    procedure SetVersusWindow(AOn: Boolean);
    procedure StateChecks;
    procedure SubmitName;
    procedure OpenCodeEntry;
    procedure CloseCodeEntry;
    procedure AddCodeText(const S: string);
    procedure PasteCode;
    procedure ApplyCode;
    procedure CopyLevelCode;
    function LevelCode: string;
    procedure StartPlay;
    procedure RestartRun;
    function MenuShown: Boolean;
    procedure AutoStep(dt: Double);
    procedure BuildMenu;
    function UnlockedThemes: Integer;
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
    procedure MouseToCell;
    procedure Activate;
    procedure HandleKey(AKey: TSDL_Keycode);
    procedure SetScene(AScene: Integer);
    function PreviewKey(AKey: TSDL_Keycode): Boolean;
    procedure VsSimStep(dt: Double);
    procedure VsSimStart;
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
  SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, 'Neon Beads', PAnsiChar(AWhat), nil);
  Halt(1);
end;

{ ---- music, sound effects and menu effects live in files next to the game
  (.music, .sfx, .menufx; written with the defaults when missing) and are
  reloaded while the game runs when an editor saves them }

function TApp.AssetFile(AIndex: Integer): string;
const
  Ext: array[0..7] of string = ('.music', '.sfx', '.menufx', '.visuals', '.scoring', '.versus', '.ironflow',
    '.shapes');
begin
  { --preview: NeonVisualEditor's live copy of the visuals }
  if (AIndex = 3) and Preview.Active and (Preview.VisualsFile <> '') then Exit(Preview.VisualsFile);
  if (AIndex = 6) and Preview.VsSim then Exit(Preview.FlowFile);
  if (AIndex = 7) and (Preview.ShapesFile <> '') then Exit(Preview.ShapesFile);
  Result := ChangeFileExt(ParamStr(0), Ext[AIndex]);
end;

procedure TApp.LoadAsset(AIndex: Integer; AStartup: Boolean);
var
  songs: TSongArray;
  bank: TSfxBank;
  mfx: TMenuFx;
  f: string;
  missing: Integer;
  k: TRuleKind;
begin
  f := AssetFile(AIndex);
  case AIndex of
    0:
      begin
        if not LoadSongsFile(f, songs) then
        begin
          songs := DefaultSongs(MusicGameBeads);
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
    6:
      begin
        { the VS BOT iron flowchart (NeonIronFlow); none = the built-in rules as a flow }
        if not IronFlow.LoadFromFile(f) then
        begin
          DefaultFlow(IronFlow);
          if AStartup and not FileExists(f) and not Preview.Active then
            try IronFlow.SaveToFile(f); except end;
        end;
      end;
    4, 5:
      begin
        { the rules (uBeadRules): scoring, VS BOT; missing file = the original rules }
        if AIndex = 4 then k := rkScoring else k := rkVersus;
        if not LoadRulesFile(k, f) then
        begin
          DefaultRules(k);
          if AStartup and not FileExists(f) and not Preview.Active then
            try SaveRulesFile(k, f); except end;
        end;
      end;
    7:
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
            try SaveParamsFile(f, 'Neon Beads visuals - background, board, beads, effects, popups'); except end;
        end
        else if AStartup and (missing > 0) and not Preview.Active then
          try SaveParamsFile(f, 'Neon Beads visuals - background, board, beads, effects, popups'); except end;
      Ach.ApplyTheme(Ach.Theme);   // the theme colours may have changed
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
  if (AIndex = 3) and Preview.Active and (Preview.VisualsFile <> '') then PreviewLoaded;
end;

procedure TApp.CheckAssets(dt: Double);
var
  i: Integer;
  a: LongInt;
begin
  { --preview: the editor's copy is compared by content ten times a second
    (file times are too coarse for sliders) }
  if Preview.Active and PreviewChanged(dt) then LoadAsset(3, False);
  if ShapesChanged(dt) then LoadAsset(7, False);   // --shapes: NeonShapeEditor's live copy
  if Preview.VsSim and FlowChanged(dt) then LoadAsset(6, False);
  AssetT += dt;
  if AssetT < 0.5 then Exit;
  AssetT := 0;
  for i := 0 to 7 do
  begin
    if (i = 3) and Preview.Active then Continue;
    if (i = 7) and (Preview.ShapesFile <> '') then Continue;
    if (i = 6) and Preview.VsSim then Continue;
    a := FileAge(AssetFile(i));
    if (a <> -1) and (a <> AssetAge[i]) then LoadAsset(i, False);
  end;
end;

{ ---- everything visual is registered in the uParams registry and lives in
  NeonBeads.visuals: the background (uParams), the board look, the bead
  colours of the themes, animation speeds, the particle effects (uGameFx)
  and the score popups. Defaults are set here. }

function BeadFxColour(AIndex: Integer): TBGRAPixel;
var
  k: Integer;
begin
  k := AIndex mod MaxColours;
  Result := BGRA(BeadRGB[k, 0], BeadRGB[k, 1], BeadRGB[k, 2]);
end;

procedure TApp.RegisterVisuals;
const
  DefTheme: array[0..ThemeCount - 1, 0..MaxColours - 1, 0..2] of Byte = (
    ((245, 150, 35), (35, 215, 240), (230, 40, 145), (150, 230, 55), (150, 75, 240), (245, 55, 55)),
    ((255, 185, 120), (130, 215, 255), (255, 150, 205), (175, 240, 150), (195, 165, 255), (255, 125, 125)),
    ((255, 210, 40), (255, 120, 20), (225, 30, 30), (255, 80, 150), (170, 35, 95), (255, 245, 170)),
    ((25, 195, 255), (40, 105, 255), (0, 225, 170), (140, 255, 235), (135, 85, 255), (235, 250, 255)),
    ((255, 85, 180), (255, 220, 60), (90, 230, 255), (135, 255, 115), (200, 115, 255), (255, 140, 55)));
var
  t, i: Integer;
  e: TFxEmitter;
begin
  { background: the game's own defaults, the desktop-only values hidden }
  SetParamDefault('Grid', 'Scroll X', 0);
  SetParamDefault('Grid', 'Scroll Y', 0);
  SetParamDefault('Sparkles', 'Probability', 0.03);
  HideParam('Rendering', 'VSync');
  HideParam('Rendering', 'Render scale');
  HideParam('Rendering', 'Smooth upscale');
  HideParam('Rendering', 'Threads');

  ParamCategory('Board');
  Look.DimOutside := 0.55;
  Look.DimEmpty := 0.28;
  Look.Shimmer := 0.07;
  Look.BgHighlight := 0.5;
  Look.PopGrowth := 0.3;
  AddF('Board look', 'Dim outside', 'Dimming of the dot grid around the board (0 = as bright as the board).',
    Look.DimOutside, 0, 1, 0.55);
  AddF('Board look', 'Dim empty', 'Dimming of empty board cells.', Look.DimEmpty, 0, 1, 0.28);
  AddF('Board look', 'Shimmer', 'Brightness shimmer of the beads.', Look.Shimmer, 0, 1, 0.07);
  AddF('Board look', 'Background highlight', 'Ring flares of the background dots on the board.',
    Look.BgHighlight, 0, 2, 0.5);
  AddF('Board look', 'Pop growth', 'How much a popping bead swells.', Look.PopGrowth, 0, 2, 0.3);
  AddF('Animation', 'Pop time', 'Seconds a popped group flashes before it disappears.', PopTime, 0.03, 2, 0.24);
  AddF('Animation', 'Fall gravity', 'Falling speed-up of the beads in cells per second squared.', Gravity, 5, 400, 70);
  AddF('Animation', 'Slide speed', 'Speed of columns sliding left in cells per second.', SlideSpeed, 1, 100, 16);
  for t := 0 to ThemeCount - 1 do
    for i := 0 to MaxColours - 1 do
      AddRGB('Theme ' + ThemeNames[t], 'Colour ' + IntToStr(i + 1),
        Format('Bead colour %d of the %s theme.', [i + 1, ThemeNames[t]]), ThemeRGB[t, i],
        BGRA(DefTheme[t, i, 0], DefTheme[t, i, 1], DefTheme[t, i, 2]));
  AddRGB('Special beads', 'Stone', 'Colour of the grey stone blockers.', StoneRGB, BGRA(105, 108, 125));
  AddRGB('Special beads', 'Iron', 'Colour of the iron beads (survival, VS BOT).', IronRGB, BGRA(170, 182, 200));

  ParamCategory('Effects');
  e := FxBurst(9, 4.5, 0.24, 0.55);
  e.DelayPerN := 0.006;
  e.DelayNMax := 40;
  FxIdx[fxPop] := RegisterFx(FxDef('Pop', e), 'Every popped bead (N = its order in the group).');
  e := FxFixed(FxBurst(30, 10, 0.25, 0.8), 255, 255, 255);
  e.CountPerN := 1;
  e.CountNMax := 40;
  FxIdx[fxBigPop] := RegisterFx(FxDef('Big pop', FxRing(40, 9, 0.26, 0.6), e), 'A group of 10+ beads (N = group size).');
  FxIdx[fxBomb] := RegisterFx(FxDef('Bomb', FxFixed(FxBurst(70, 12, 0.4, 0.9), 255, 153, 51),
    FxFixed(FxRing(36, 10, 0.3, 0.45), 255, 230, 153)), 'A bomb bead goes off.');
  FxIdx[fxLine] := RegisterFx(FxDef('Line', FxBurst(5, 3, 0.25, 0.5)), 'A line bead clears its row.');
  FxDefs[FxIdx[fxLine]].Position := 2;
  FxDefs[FxIdx[fxLine]].BurstDelay := 0.015;
  SetParamDefault('Effect: Line', 'Position', 2);
  SetParamDefault('Effect: Line', 'Burst delay', 0.015);
  FxIdx[fxStone] := RegisterFx(FxDef('Stone', FxBurst(16, 6, 0.32, 0.8)), 'A stone or iron bead breaks / lands.');
  FxIdx[fxSpawn] := RegisterFx(FxDef('Special appears', FxFixed(FxRing(28, 5, 0.22, 0.5), 255, 255, 255)),
    'A special bead is created.');
  FxIdx[fxTime] := RegisterFx(FxDef('Extra time', FxRing(24, 6, 0.22, 0.5)), 'Time attack: extra seconds.');
  FxIdx[fxIron] := RegisterFx(FxDef('Iron rain', FxBurst(6, 3, 0.22, 0.6)),
    'Survival / VS BOT: iron beads drop in (N = iron count).');
  with FxDefs[FxIdx[fxIron]] do
  begin
    Position := 3; Bursts := 6; BurstsPerN := 3; BurstDelay := 0.02;
  end;
  SetParamDefault('Effect: Iron rain', 'Position', 3);
  SetParamDefault('Effect: Iron rain', 'Bursts', 6);
  SetParamDefault('Effect: Iron rain', 'Bursts per N', 3);
  SetParamDefault('Effect: Iron rain', 'Burst delay', 0.02);
  e := FxBurst(70, 11, 0.4, 1.3);
  e.ColourMode := 2;
  FxIdx[fxLevel] := RegisterFx(FxDef('Level fireworks', e), 'Level complete: fireworks over the board.');
  FxIdx[fxClear] := RegisterFx(FxDef('Board cleared fireworks', e), 'A cleared board: more fireworks.');
  for t in [FxIdx[fxLevel], FxIdx[fxClear]] do
    with FxDefs[t] do
    begin
      Position := 1; BurstDelay := 0.18;
      if t = FxIdx[fxLevel] then Bursts := 6 else Bursts := 12;
      SetParamDefault('Effect: ' + Name, 'Position', 1);
      SetParamDefault('Effect: ' + Name, 'Burst delay', 0.18);
      SetParamDefault('Effect: ' + Name, 'Bursts', Bursts);
    end;
  FxBeadColour := @BeadFxColour;

  ParamCategory('Popups');
  RegisterPopupFx(1.1);
end;

procedure TApp.LoadIni;
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(IniName);
  try
    Game.BestNormal := ini.ReadInteger('Game', 'Best', 0);
    Game.BestSurvival := ini.ReadInteger('Game', 'BestSurvival', 0);
    Game.BestVersus := ini.ReadInteger('Game', 'BestVersus', 0);
    BotLevel := EnsureRange(ini.ReadInteger('Game', 'BotLevel', 1), 0, BotLevels - 1);
    Game.MaxLevel := Max(1, ini.ReadInteger('Game', 'MaxLevel', 1));
    Hud.Muted := ini.ReadBool('Game', 'Muted', False);
    PlayerName := Copy(ini.ReadString('Game', 'PlayerName', ''), 1, MaxNameLen);
    PlayMode := TGameMode(EnsureRange(ini.ReadInteger('Game', 'Mode', 0), Ord(Low(TGameMode)), Ord(High(TGameMode))));
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
      Game.Best := Max(Game.Best, Game.Score);
      ini.WriteInteger('Game', 'Best', Game.BestNormal);
      ini.WriteInteger('Game', 'BestSurvival', Game.BestSurvival);
      ini.WriteInteger('Game', 'BestVersus', Game.BestVersus);
      ini.WriteInteger('Game', 'BotLevel', BotLevel);
      ini.WriteInteger('Game', 'MaxLevel', Game.MaxLevel);
      ini.WriteBool('Game', 'Muted', Hud.Muted);
      ini.WriteString('Game', 'PlayerName', PlayerName);
      ini.WriteInteger('Game', 'Mode', Ord(PlayMode));
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
  if Ach <> nil then Ach.Save;
end;

{ fit the board between the HUD bars and build a dot grid around it that
  covers the whole window }
procedure TApp.DoLayout;
const
  VsGap = 2;   // empty grid columns between the two VS BOT boards
var
  w, h: LongInt;
  cols: Integer;
  cell, bx, by, m: Single;
begin
  SDL_GetWindowSizeInPixels(Win, @w, @h);
  L.W := Max(64, w);
  L.H := Max(64, h);
  L.TopH := Round(L.H * 0.095);
  L.BottomH := Round(L.H * 0.075);
  L.Versus := (Game.Mode = gmVersus) and (Game.State <> gsTitle);
  if L.Versus then cols := Game.W * 2 + VsGap else cols := Game.W;
  m := Min(L.W, L.H) * 0.035;
  cell := Min((L.W - 2 * m) / cols, (L.H - L.TopH - L.BottomH - m) / Game.H);
  cell := Max(6, cell);
  L.Cell := cell;
  L.BoardX0 := (L.W - cols * cell) / 2 + cell / 2;
  L.Board2X0 := L.BoardX0 + (Game.W + VsGap) * cell;
  L.BoardY0 := L.TopH + (L.H - L.TopH - L.BottomH - Game.H * cell) / 2 + cell / 2;
  bx := L.BoardX0;
  by := L.BoardY0;
  GX0 := Ceil((bx + cell * 0.5) / cell) + 1;
  GY0 := Ceil((by + cell * 0.5) / cell) + 1;
  GX0b := GX0 + Game.W + VsGap;
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

{ hue (0..1) -> bright RGB }
procedure HueRGB(Hue: Single; out R, G, B: Single);
var
  k: Integer;
  f: Single;
begin
  Hue := Frac(Frac(Hue) + 1) * 6;
  k := Trunc(Hue) mod 6;
  f := Frac(Hue);
  case k of
    0: begin R := 1; G := f; B := 0; end;
    1: begin R := 1 - f; G := 1; B := 0; end;
    2: begin R := 0; G := 1; B := f; end;
    3: begin R := 0; G := 1 - f; B := 1; end;
    4: begin R := f; G := 0; B := 1; end;
  else
    begin R := 1; G := 0; B := 1 - f; end;
  end;
  R := 0.25 + 0.75 * R;
  G := 0.25 + 0.75 * G;
  B := 0.25 + 0.75 * B;
end;

procedure TApp.BuildCells(out AMaxOffX, AMaxOffY: Integer);
var
  i, j, bx, by, c, n, sp: Integer;
  G: TBeadGame;
  f: PCellFx;
  mx, my, cr, cg, cb, fl: Single;
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
      G := Game;
      if L.Versus and (bx >= Game.W) then
      begin
        bx := i - GX0b;   // the bot board on the right
        G := Bot;
      end;
      if (bx < 0) or (by < 0) or (bx >= G.W) or (by >= G.H) or (Preview.Scene = 2) then
      begin
        Cells[j * Geo.NCols + i] := Half4(0, 0, 0, -1);   // outside the board
        Fx[j * Geo.NCols + i] := Half4(0, 0, 0, 0);
        Continue;
      end;
      c := G.Cell(bx, by);
      sp := G.Spec(bx, by);
      f := G.Fx(bx, by);
      fl := f^.Flash;
      if c >= 0 then
      begin
        case sp of
          SpStone:
            begin
              cr := StoneRGB[0] / 255; cg := StoneRGB[1] / 255; cb := StoneRGB[2] / 255;
            end;
          SpIron:
            begin
              { steel with a slow sheen running across the board }
              fl := Max(fl, 0.05 + 0.05 * Sin(SimTime * 2 - (bx + by) * 0.5));
              cr := IronRGB[0] / 255; cg := IronRGB[1] / 255; cb := IronRGB[2] / 255;
            end;
          SpRainbow:
            HueRGB(SimTime * 0.6 + (bx + by) * 0.08, cr, cg, cb);
        else
          begin
            cr := BeadRGB[c, 0] / 255; cg := BeadRGB[c, 1] / 255; cb := BeadRGB[c, 2] / 255;
            { bombs and lines glow in a slow pulse }
            if sp in [SpBomb, SpLine] then fl := Max(fl, 0.12 + 0.12 * Sin(SimTime * 5 + bx));
          end;
        end;
        Cells[j * Geo.NCols + i] := Half4(cr, cg, cb, f^.Presence);
      end
      else
        Cells[j * Geo.NCols + i] := Half4(0, 0, 0, 0);    // empty board cell
      Fx[j * Geo.NCols + i] := Half4(f^.Hover, fl, f^.OffY, f^.OffX);
      mx := Max(mx, f^.OffX);
      my := Max(my, f^.OffY);
    end;
  AMaxOffX := Ceil(mx);
  AMaxOffY := Ceil(my);
end;

procedure TApp.MouseToCell;
var
  gx, gy: Single;
  bx, by: Integer;
begin
  gx := (MouseX - L.BoardX0) / L.Cell;
  gy := (MouseY - L.BoardY0) / L.Cell;
  bx := Round(gx);
  by := Round(gy);
  if (bx < 0) or (by < 0) or (bx >= Game.W) or (by >= Game.H) then
  begin
    bx := -1;
    by := -1;
  end;
  Game.SetMouseCell(bx, by);
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

function TApp.UnlockedThemes: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to ThemeCount - 1 do
    if Ach.ThemeUnlocked(i) then Inc(Result);
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
        Add('MODE', ModeName(PlayMode));
        if PlayMode = gmVersus then Add('BOT', BotNames[BotLevel])
        else if PlayMode <> gmClassic then Add('LEVEL', '-')
        else Add('LEVEL', IntToStr(Hud.StartLevel));
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
        Add('THEME', ThemeNames[Ach.Theme] + Format('  (%d / %d)', [UnlockedThemes, ThemeCount]));
        Add('FULLSCREEN', OnOff(FullScreen));
        Add('VSYNC', OnOff(VSync));
        Add('BACK', '');
      end;
  else
    begin
      Add('RESUME', '');
      if Game.Mode <> gmClassic then Add('RESTART RUN', '') else Add('RESTART LEVEL', '');
      Add('OPTIONS', '');
      Add('MAIN MENU', '');
      Add('EXIT', '');
    end;
  end;
  MenuSel := EnsureRange(MenuSel, 0, High(Hud.Menu.Items));
  Hud.Menu.Active := True;
  if Paused then Hud.Menu.Title := 'PAUSED'
  else if ScoresOpen then Hud.Menu.Title := 'GAME OVER'
  else Hud.Menu.Title := 'NEON BEADS';
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
var
  k: Integer;
begin
  if MenuScreen = 0 then
  begin
    case MenuSel of
      1:
        begin
          PlayMode := TGameMode((Ord(PlayMode) + ADelta + 4) mod 4);
          Audio.Play(gsndMenuMove, 0);
          SaveIni;
        end;
      2:
        if PlayMode = gmClassic then
        begin
          Hud.StartLevel := EnsureRange(Hud.StartLevel + ADelta, 1, Game.MaxLevel);
          Audio.Play(gsndMenuMove, 0);
        end
        else if PlayMode = gmVersus then
        begin
          BotLevel := (BotLevel + ADelta + BotLevels) mod BotLevels;
          Audio.Play(gsndMenuMove, 0);
          SaveIni;
        end;
    end;
    Exit;
  end;
  if MenuScreen = 4 then
  begin
    Hud.AchPage := (Hud.AchPage + ADelta + AchGroups) mod AchGroups;
    Audio.Play(gsndMenuMove, 0);
    Exit;
  end;
  if MenuScreen = 3 then
  begin
    Hud.ScoreMode := TGameMode((Ord(Hud.ScoreMode) + ADelta + 4) mod 4);
    Audio.Play(gsndMenuMove, 0);
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
        { the next unlocked theme }
        k := Ach.Theme;
        repeat
          k := (k + ADelta + ThemeCount) mod ThemeCount;
        until Ach.ThemeUnlocked(k);
        Ach.ApplyTheme(k);
      end;
    4:
      begin
        SetFullScreen(not FullScreen);
        ArgFullScreen := False;
      end;
    5:
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
            StartPlay;
          end;
        1:
          MenuChange(1);
        2:
          if PlayMode = gmVersus then
            MenuChange(1)
          else if (PlayMode = gmClassic) and (Game.MaxLevel > 1) then
          begin
            { cycle through the unlocked levels }
            if Hud.StartLevel >= Game.MaxLevel then Hud.StartLevel := 1
            else Inc(Hud.StartLevel);
            Audio.Play(gsndMenuMove, 0);
          end;
        3, 4:
          begin
            Audio.Play(gsndMenuSelect, 0);
            Hud.NewRank := -1;
            Hud.ScoreMode := PlayMode;
            case PlayMode of
              gmSurvival: Hud.AchPage := 1;
              gmVersus: Hud.AchPage := 2;
            else
              Hud.AchPage := 0;
            end;
            ShowMenu(MenuSel, False);   // 3 = high scores, 4 = achievements
          end;
        5:
          begin
            Audio.Play(gsndMenuSelect, 0);
            OptionsFrom := 0;
            ShowMenu(1, False);
          end;
        6:
          begin
            Audio.Play(gsndMenuSelect, 0);
            OpenCodeEntry;
          end;
        7:
          Running := False;
      end;
    1:
      if MenuSel = 6 then MenuBack else MenuChange(1);
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
          if Game.Mode <> gmClassic then
          begin
            Paused := False;
            RestartRun;
          end
          else
          begin
            Game.Score := Game.LevelStartScore;
            StartGameLevel(Game.Level, True, False);
          end;
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
        SaveIni;
        ShowMenu(OptionsFrom, False);
        if OptionsFrom = 0 then MenuSel := 5 else MenuSel := 2;   // the OPTIONS item
      end;
    2:
      ResumeGame;
    5:
      begin
        Audio.Play(gsndMenuSelect, 0);
        CloseCodeEntry;
        ShowMenu(0, False);
        MenuSel := 6;               // the CHEAT CODE item
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
          MenuSel := k;             // the HIGH SCORES / ACHIEVEMENTS item
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
    gsPlaying:
      Game.Click;
    gsLevelDone:
      begin
        SaveIni;
        StartGameLevel(Game.Level + 1, True, True);
      end;
    gsGameOver:
      if Hud.NameEntry then
        SubmitName
      else if Game.Mode <> gmClassic then
      begin
        RestartRun;
        PickSong(True);
      end
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
  Result := MakeGameCode(GameIdBeads, Game.Level, Game.Score, 0);
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
  if not ReadGameCode(Hud.CodeText, GameIdBeads, lv, sc, li) then
  begin
    if Length(Hud.CodeText) < GameCodeLen then Hud.CodeMsg := Format('the code has %d letters', [GameCodeLen])
    else Hud.CodeMsg := 'INVALID CODE';
    Audio.Play(gsndInvalid, 0);
    Exit;
  end;
  CloseCodeEntry;
  Audio.Play(gsndMenuSelect, 0);
  PlayMode := gmClassic;
  StartGameLevel(Min(lv + 1, 255), False, True);
  Game.Score := sc;
  Game.LevelStartScore := sc;
  Ach.ResetScoreWatch(sc);   // the code's score is no new XP
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
  SDL_SetWindowTitle(Win, PAnsiChar(PreviewTitle('Neon Beads')));
end;

{ True: the key was for the preview (other game keys are ignored) }
function TApp.PreviewKey(AKey: TSDL_Keycode): Boolean;
begin
  Result := True;
  if Preview.VsSim then
  begin
    case AKey of
      SDLK_1, SDLK_KP_1: Preview.Speed := 1;
      SDLK_2, SDLK_KP_2: Preview.Speed := 2;
      SDLK_3, SDLK_KP_3: Preview.Speed := 4;
      SDLK_4, SDLK_KP_4: Preview.Speed := 8;
      SDLK_R: VsSimStart;
      SDLK_ESCAPE: Running := False;
      SDLK_M, SDLK_F11: Result := False;
    end;
    SDL_SetWindowTitle(Win, PAnsiChar(PreviewTitle('Neon Beads')));
    Exit;
  end;
  case AKey of
    SDLK_1, SDLK_KP_1: SetScene(0);
    SDLK_2, SDLK_KP_2: SetScene(1);
    SDLK_3, SDLK_KP_3: SetScene(2);
    SDLK_TAB: SetScene(Preview.Scene + 1);
    SDLK_ESCAPE: Running := False;
    SDLK_M, SDLK_F11: Result := False;
  end;
end;

{ ---- --vssim (NeonIronFlow): two bots, the iron flowchart, endless matches }

var
  TraceName: string;
  TraceMatch: Integer;
  TraceTime: Single;

{ uIronFlow reports every node that runs: "match time side node amount" }
procedure TraceFlow(ASide, ANode, AAmount: Integer);
var
  f: TextFile;
begin
  if TraceName = '' then Exit;
  try
    AssignFile(f, TraceName);
    if FileExists(TraceName) then Append(f) else Rewrite(f);
    WriteLn(f, Format('%d %.2f %d %d %d', [TraceMatch, TraceTime, ASide, ANode, AAmount], DefaultFormatSettings));
    CloseFile(f);
  except
    { the editor is reading it: this line is lost }
  end;
end;

procedure TApp.VsSimStart;
begin
  Inc(TraceMatch);
  PlayMode := gmVersus;
  BotLevel := EnsureRange(Preview.RightLevel, 0, BotLevels - 1);
  StartVersus;
  LeftAI.Level := EnsureRange(Preview.LeftLevel, 0, BotLevels - 1);
  LeftAI.Reset(1.2);
  SimEndT := 0;
  Hud.Menu.Active := False;
end;

procedure TApp.VsSimStep(dt: Double);
begin
  TraceTime := Game.VsTime;
  if Game.VsResult = 0 then
  begin
    if Game.State = gsPlaying then LeftAI.Step(Game, dt);
  end
  else
  begin
    { the match is over: a new one after a few seconds }
    SimEndT += dt;
    if SimEndT > 4 then VsSimStart;
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
    SDLK_RETURN, SDLK_KP_ENTER, SDLK_SPACE:
      if Game.State <> gsPlaying then Activate;
    SDLK_U, SDLK_BACKSPACE:
      Game.Undo;
    SDLK_R:
      if Game.State in [gsPlaying, gsGameOver, gsLevelDone] then
      begin
        if Game.Mode <> gmClassic then
          RestartRun
        else
        begin
          Game.Score := Game.LevelStartScore;
          StartGameLevel(Game.Level, True, False);
        end;
      end;
    SDLK_H:
      if Game.State = gsGameOver then
      begin
        Audio.Play(gsndMenuSelect, 0);
        Hud.ScoreMode := Game.Mode;
        ScoresOpen := True;
        ShowMenu(3, True);
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
      if not AutoPlay and not Preview.Active then OpenPause;
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
        end;
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
        if Hud.NameEntry then Exit;
        MouseToCell;
        if E.button.button = SDL_BUTTON_LEFT then
          Activate
        else if E.button.button = SDL_BUTTON_RIGHT then
          Game.Undo;
      end;
  end;
end;

function TApp.MenuShown: Boolean;
begin
  Result := (Game.State = gsTitle) or Paused or ScoresOpen;
end;

{ a new time attack / survival run }
procedure TApp.RestartRun;
begin
  Game.Best := Max(Game.Best, Game.Score);
  case Game.Mode of
    gmSurvival: Game.StartSurvival;
    gmVersus: StartVersus;
  else
    Game.StartTimeAttack;
  end;
end;

{ VS BOT: both boards start together }
procedure TApp.StartVersus;
begin
  Paused := False;
  Game.Best := Max(Game.Best, Game.Score);
  Game.StartRun(gmVersus);
  Game.VsBotLevel := BotLevel;
  Bot.Reseed(Cardinal(Random($7FFFFFFF)) + 1);
  Bot.StartRun(gmVersus);
  Bot.VsBotLevel := BotLevel;
  BotAI.Level := BotLevel;
  BotAI.Reset(1.2);
  VsRecorded := False;
  SetVersusWindow(True);
end;

{ VS BOT: the score gap, iron between the boards, who ran out of pairs first (uBeadBot) }
procedure TApp.VersusStep;
begin
  if (Game.Mode <> gmVersus) or (Game.State = gsTitle) then Exit;
  VersusExchange(Game, Bot);
end;

{ the bot: thinks, aims (its hover shows the move), clicks }
procedure TApp.BotStep(dt: Double);
begin
  if (Game.Mode <> gmVersus) or (Game.State = gsTitle) or (Game.VsResult <> 0) then Exit;
  BotAI.Level := BotLevel;
  BotAI.Step(Bot, dt);
end;

procedure TApp.BotSound(ASound: TGameSound; AParam: Integer);
begin
  { only the bot's big moments: iron landing on its board, bonus beads }
  if ASound in [gsndCrash, gsndPower] then Audio.Play(ASound, AParam);
end;

{ VS BOT needs a landscape window: widen it for the match, restore it later }
procedure TApp.SetVersusWindow(AOn: Boolean);
var
  w, h, x, y, nw: LongInt;
  r: TSDL_Rect;
begin
  if AOn then
  begin
    if FullScreen or (VsSaved.w > 0) then Exit;
    SDL_GetWindowSize(Win, @w, @h);
    if w >= h * 1.25 then Exit;
    SDL_GetWindowPosition(Win, @x, @y);
    VsSaved.x := x; VsSaved.y := y; VsSaved.w := w; VsSaved.h := h;
    if not SDL_GetDisplayUsableBounds(SDL_GetDisplayForWindow(Win), @r) then
    begin
      r.x := 0; r.y := 0; r.w := Round(h * 1.4); r.h := h;
    end;
    nw := Min(Round(h * 1.32), r.w - 40);
    SDL_SetWindowSize(Win, nw, h);
    SDL_SetWindowPosition(Win, r.x + (r.w - nw) div 2, y);
  end
  else if VsSaved.w > 0 then
  begin
    if not FullScreen then
    begin
      SDL_SetWindowSize(Win, VsSaved.w, VsSaved.h);
      SDL_SetWindowPosition(Win, VsSaved.x, VsSaved.y);
    end;
    VsSaved.w := 0;
  end;
end;

procedure TApp.StartPlay;
begin
  Paused := False;
  if PlayMode = gmVersus then
  begin
    StartVersus;
    PickSong(True);
  end
  else if PlayMode <> gmClassic then
  begin
    Game.Best := Max(Game.Best, Game.Score);
    if PlayMode = gmSurvival then Game.StartSurvival else Game.StartTimeAttack;
    PickSong(True);
  end
  else
    StartGameLevel(Hud.StartLevel, False, True);
end;

{ reacts to the game's state changes: stars, high-score entry, hints }
procedure TApp.StateChecks;
const
  Hints: array[SpBomb..SpIron, 0..1] of string = (
    ('NEW: BOMB BEAD', 'click it, even alone: blasts 3 x 3'),
    ('NEW: LINE BEAD', 'click it, even alone: clears its row'),
    ('NEW: x2 BEAD', 'doubles the points of its move'),
    ('NEW: RAINBOW BEAD', 'matches every colour'),
    ('NEW: STONES', 'only bombs and lines break them'),
    ('NEW: IRON BEADS', 'nothing breaks them: pops of 2 or 3 bring more'));
var
  rank, k, bits: Integer;
begin
  if Game.State <> LastState then
  begin
    case Game.State of
      gsLevelDone:
        begin
          Hud.StarTime := 0;
          Hud.NewStarBest := Ach.RecordLevel(Game.Level, Game.Stars);
          SaveIni;
        end;
      gsTitle:
        SetVersusWindow(False);
      gsGameOver:
        begin
          AutoT := 0;
          if (Game.Mode = gmVersus) and not VsRecorded then
          begin
            Ach.RecordVersus(Game.VsResult = 1);
            VsRecorded := True;
          end;
          rank := Ach.ScoreRank(Game.Mode, Game.Score);
          Hud.ScoreRank := rank;
          Hud.NewRankMode := Game.Mode;
          if (rank >= 0) and not Preview.Active then
          begin
            Hud.NameEntry := True;
            Hud.NameText := PlayerName;
            if AutoPlay and (Hud.NameText = '') then Hud.NameText := 'AUTOPLAY';
            SDL_StartTextInput(Win);
          end;
          SaveIni;
        end;
    end;
    if (Game.State <> gsGameOver) and Hud.NameEntry then
    begin
      Hud.NameEntry := False;
      SDL_StopTextInput(Win);
    end;
    LastState := Game.State;
  end;
  { first meeting with a special bead: a hint card }
  if Game.State = gsPlaying then
  begin
    bits := Game.SpecialsOnBoard and not Ach.Seen;
    if bits <> 0 then
    begin
      for k := SpBomb to SpIron do
        if bits and (1 shl k) <> 0 then
          Ach.AddToast(Hints[k, 0], Hints[k, 1], 150, 230, 55);
      Ach.Seen := Ach.Seen or bits;
      Ach.Save;
    end;
  end;
end;

procedure TApp.SubmitName;
begin
  if not Hud.NameEntry then Exit;
  Hud.NameEntry := False;
  SDL_StopTextInput(Win);
  PlayerName := Trim(Hud.NameText);
  if Game.Mode = gmTime then
    Hud.NewRank := Ach.AddScore(gmTime, PlayerName, Game.Score, Game.Boards)
  else if Game.Mode = gmSurvival then
    Hud.NewRank := Ach.AddScore(gmSurvival, PlayerName, Game.Score, Game.Pops)
  else if Game.Mode = gmVersus then
    Hud.NewRank := Ach.AddScore(gmVersus, PlayerName, Game.Score, Game.VsBotLevel)
  else
    Hud.NewRank := Ach.AddScore(gmClassic, PlayerName, Game.Score, Game.Level);
  Hud.NewRankMode := Game.Mode;
  Hud.ScoreMode := Game.Mode;
  SaveIni;
  Audio.Play(gsndLevel, 0);
  { show the table with the new row lit }
  ScoresOpen := True;
  ShowMenu(3, True);
end;

{ the game's effect events become particle bursts (cell -> window pixels) }
procedure TApp.SpawnFx;
begin
  Parts.Gravity := L.Cell * ParticleGravity;
  Parts.Drag := ParticleDrag;
  SpawnFxOf(Game, L.BoardX0);
  if L.Versus then SpawnFxOf(Bot, L.Board2X0)
  else SetLength(Bot.FxEvents, 0);
end;

procedure TApp.SpawnFxOf(AGame: TBeadGame; AX0: Single);
var
  i: Integer;
  ev: TFxEvent;
  brd: TFxBoard;
begin
  brd.X0 := AX0;
  brd.Y0 := L.BoardY0;
  brd.Cell := L.Cell;
  brd.W := AGame.W;
  brd.H := AGame.H;
  for i := 0 to High(AGame.FxEvents) do
  begin
    ev := AGame.FxEvents[i];
    brd.EventX := ev.X;
    { the effect definitions come from NeonBeads.visuals (uGameFx) }
    SpawnFxDef(Parts, FxIdx[ev.Kind], AX0 + ev.X * L.Cell, L.BoardY0 + ev.Y * L.Cell, ev.R, ev.G, ev.B, ev.N, brd);
  end;
  SetLength(AGame.FxEvents, 0);
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
  WriteLn(f, Format('Neon Beads benchmark: driver %s, shaders %s, window %d x %d, board %d x %d',
    [Gpu.Driver, Gpu.ShaderInfo, L.W, L.H, Game.W, Game.H]));
  WriteLn(f, Format('frames %d in %.1f s -> %.2f fps', [n, sum / 1000, n * 1000 / sum]));
  WriteLn(f, Format('interval ms: mean %.2f median %.2f p99 %.2f max %.2f; over 25 ms: %d',
    [sum / n, sorted[n div 2], sorted[Min(n - 1, Round(n * 0.99))], mx, missed]));
  WriteLn(f, Format('worst stage ms: game update %.2f, progress checks %.2f, HUD %.2f, cells %.2f, GPU submit/wait %.2f',
    [StageMax[0], StageMax[4], StageMax[1], StageMax[2], StageMax[3]]));
  CloseFile(f);
end;

procedure TApp.AutoStep(dt: Double);
var
  x, y, n, best, bx, by: Integer;
begin
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
        if Game.State = gsTitle then
        begin
          MenuSel := 0;
          if AutoVs then PlayMode := gmVersus
          else if AutoSurvival then PlayMode := gmSurvival
          else if AutoTime then PlayMode := gmTime
          else PlayMode := gmClassic;
        end;
        Activate;
      end;
    gsPlaying:
      if (AutoT > 0.35) and ((Game.Mode <> gmVersus) or (AutoT > 1.6)) then
      begin
        AutoT := 0;
        { prefer small groups of the colour that is not the most common:
          clears boards reasonably well }
        best := MaxInt;
        bx := -1;
        by := -1;
        for x := 0 to Game.W - 1 do
          for y := 0 to Game.H - 1 do
          begin
            n := Game.GroupSize(x, y);
            { in time attack big moves are better (more time); survival autoplay
              takes the small ones (brings iron: tests the end of a run) }
            if (Game.Mode in [gmTime, gmVersus]) and (n > 0) then n := 1000 - n;
            if (n >= 1) and (n < best) then
            begin
              best := n;
              bx := x;
              by := y;
            end;
          end;
        if bx >= 0 then
        begin
          MouseX := L.BoardX0 + bx * L.Cell;
          MouseY := L.BoardY0 + by * L.Cell;
          MouseToCell;
          Game.Click;
        end;
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
  sub: Integer;
begin
  if not SDL_Init(SDL_INIT_VIDEO or SDL_INIT_AUDIO) then Fail('SDL_Init failed: ' + StrPas(SDL_GetError));
  if not TTF_Init then Fail('TTF_Init failed: ' + StrPas(SDL_GetError));
  if not SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @r) then
  begin
    r.x := 0; r.y := 0; r.w := 1280; r.h := 900;
  end;
  h := Round(r.h * 0.9);
  w := Round(h * 0.68);
  Win := SDL_CreateWindow('Neon Beads  -  NeonGrid SDL3 GPU', w, h,
    SDL_WINDOW_RESIZABLE or SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if Win = nil then Fail('SDL_CreateWindow failed: ' + StrPas(SDL_GetError));
  try
    Gpu := TGameGPU.Create(Win);
  except
    on Ex: Exception do Fail(Ex.Message);
  end;
  if HasArg('novsync') then Gpu.SetVSync(False);
  AutoTime := HasArg('autotime');
  AutoSurvival := HasArg('autosurvival');
  AutoVs := HasArg('autovs');
  AutoPlay := HasArg('autoplay') or AutoTime or AutoSurvival or AutoVs;
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

  { the background keeps the NeonGrid look, a bit calmer behind the board;
    every visual value is registered with its default (NeonBeads.visuals) }
  RegisterVisuals;

  Renderer := TNeonRenderer.Create;
  Game := TBeadGame.Create;
  Bot := TBeadGame.Create;
  BotAI := TBeadBot.Create(1);
  LeftAI := TBeadBot.Create(1);
  Bot.OnSound := @BotSound;
  Parts := TParticles.Create;
  Audio := TGameAudio.Create;
  Hud := TGameHud.Create;
  Game.OnSound := @Audio.Play;
  IniName := ChangeFileExt(ParamStr(0), '.ini');
  { --preview: keeps no records (a temp copy of the ini) }
  PreviewInit;
  if Preview.Active then
  begin
    AutoPlay := not Preview.VsSim;   // --vssim: two bots play, no menu autoplay
    IniName := PreviewIni(IniName);
  end;
  Ach := TAchievements.Create(IniName);
  Hud.Ach := Ach;
  Hud.Bot := Bot;
  VSync := True;
  LoadAsset(0, True);   // songs before LoadIni (it checks the track)
  LoadAsset(1, True);
  LoadAsset(2, True);
  LoadAsset(3, True);
  LoadAsset(7, True);   // dot / bead shapes (NeonShapeEditor)
  LoadAsset(4, True);   // scoring rules (NeonScoreEditor)
  LoadAsset(5, True);   // VS BOT rules (NeonVsEditor)
  LoadAsset(6, True);   // VS BOT iron flowchart (NeonIronFlow)
  LoadIni;
  if Preview.Active then
  begin
    Hud.Muted := True;
    ApplyAudio;
    SDL_SetWindowTitle(Win, PAnsiChar(PreviewTitle('Neon Beads')));
  end;
  if ArgVSync then VSync := False;
  if ArgFullScreen then FullScreen := True;
  Gpu.SetVSync(VSync);
  if FullScreen then SDL_SetWindowFullscreen(Win, True);
  Game.ShowTitle;
  ShowMenu(0, True);
  Randomize;
  PickSong(True);
  if Preview.VsSim then
  begin
    { --vssim: the trace for NeonIronFlow, the first match at once }
    TraceName := Preview.FlowFile + '.trace';
    FlowTrace := @TraceFlow;
    VsSimStart;
  end;

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
      { --vssim runs 1, 2, 4 or 8 game steps per frame }
      for sub := 1 to IfThen(Preview.VsSim, Preview.Speed, 1) do
      begin
        Game.Update(dt);
        if (Game.Mode = gmVersus) and (Game.State <> gsTitle) then
        begin
          Bot.Update(dt);
          BotStep(dt);
          VersusStep;
        end;
        if Preview.VsSim then VsSimStep(dt);
      end;
      Parts.Update(Min(dt, 0.05));
      Hud.StarTime += Min(dt, 0.1);
    end;
    { the announcer: a chain (time attack) is a combo; a big pop gets praise }
    if Game.State <> gsTitle then
    begin
      if (Game.Chain > LastCombo) and (Game.Chain >= 2) then Audio.Say(ComboClipName(Game.Chain))
      else if Game.PopCount <> LastPop then
      begin
        if Game.LastGroup >= 15 then Audio.Say('excellent')
        else if Game.LastGroup >= 10 then Audio.Say('great');
      end;
    end;
    LastCombo := Game.Chain;
    LastPop := Game.PopCount;
    if BenchT > 2 then StageMax[0] := Max(StageMax[0], SDL_GetTicksNS / 1e6 - ts);
    ts := SDL_GetTicksNS / 1e6;
    if not Preview.Active and Ach.Check(Game) then Audio.Play(gsndGold, 0);
    Ach.UpdateToasts(Min(dt, 0.1));
    StateChecks;
    if BenchT > 2 then StageMax[4] := Max(StageMax[4], SDL_GetTicksNS / 1e6 - ts);
    if MenuShown then
      BuildMenu
    else
      Hud.Menu.Active := False;
    if Game.State = gsTitle then Audio.SetMusicIntensity(0) else Audio.SetMusicIntensity(1);
    Audio.SetMuffle(Paused);
    DoLayout;
    if AutoPlay then
    begin
      if Preview.Scene <> 1 then AutoStep(dt);
    end
    else if not MenuShown then MouseToCell;
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
  SetVersusWindow(False);
  Bot.Free;
  BotAI.Free;
  LeftAI.Free;
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
