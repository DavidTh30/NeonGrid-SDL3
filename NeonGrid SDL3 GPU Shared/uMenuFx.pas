unit uMenuFx;

{ Menu effect settings of Neon Beads and Neon Trail (shared unit).

  The HUD (uGameHud) reads the global MenuFx for the animated title, the
  light comets around the menu panel, the animated headings and the menu
  items. Values are multipliers (1 = the original look, 0 = off) or counts.
  The settings live in NeonBeads.menufx / NeonTrail.menufx (INI text,
  [MenuFx]); the defaults are written when a file is missing. The menu
  effect editor (NeonGrid SDL3 GPU Tools\NeonMenuFxEditor) edits these files
  and the games reload them while running.

  Level / Score / Best of the in-game top bar have their own effects, each
  set apart ([Level], [Score], [Best] in the file, TMenuFx.Stat): a looping
  style (pulse, glow, wave, light sweep, flicker, bounce, heartbeat, jelly,
  glitch), a reaction when the value changes (pop, flash, count up, shake,
  sparkle burst, rolling digits), a colour mode (the game's colour, an own
  colour, rainbow, the menu palette, a two-colour gradient) and strength,
  speed, size, glow and reaction time. The HUDs draw them every frame
  (hudstats.inc).

  The menu items that are not selected have their own look too ([Items],
  TMenuFx.Item, drawn by hudmenuitems.inc): size, colour, an art style
  (pixel art, neon tube, 3D block, chrome, scanlines, LED dots, soft glow),
  a gentle idle motion, a reaction when the selector leaves the item
  (slingshot, shake and settle, rubber band, jelly, drop bounce, flip) and a
  trail the selector leaves behind (dust, liquid drips, sparks, bubbles,
  confetti).

  The frames (panels) have their own effects too ([Frame: Top bar],
  [Frame: Status bar], [Frame: Message boxes], TMenuFx.Frame, drawn by
  hudframes.inc): border style, colour, brightness, width, corners, glow,
  speed, fill and an intro when the frame appears. The status bar text is
  the fourth stat ([Status]) and the status bar has a progress bar style and
  animated key hints ([Status bar extras], TMenuFx.StatusX). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, IniFiles;

const
  FxParamCount = 26;

  { Level / Score / Best }
  StatCount = 4;
  stLevel = 0;
  stScore = 1;
  stBest = 2;
  stStatus = 3;               // the main text of the status bar (SPARKS / BEADS / IRON)
  StatNames: array[0..StatCount - 1] of string = ('Level', 'Score', 'Best', 'Status');

  { frames: top bar, status bar, message boxes (TFrameFx.V) }
  FrameCount = 3;
  frTop = 0;
  frStatus = 1;
  frBox = 2;
  FrameNames: array[0..FrameCount - 1] of string = ('Top bar', 'Status bar', 'Message boxes');
  FrameParamCount = 12;
  fpStyle = 0;
  fpColourMode = 1;
  fpBright = 2;
  fpWidth = 3;
  fpRadius = 4;
  fpGlow = 5;
  fpSpeed = 6;
  fpCount = 7;
  fpFill = 8;
  fpFillStyle = 9;
  fpIntro = 10;
  fpIntroTime = 11;
  FrameStyleCount = 10;
  FrameStyleNames: array[0..FrameStyleCount - 1] of string = ('Static (original)', 'Breathing glow',
    'Running lights', 'Rainbow flow', 'Marching dashes', 'Pulse rings', 'Electric', 'Neon flicker',
    'Corner brackets', 'Scan line');
  FrameColourCount = 5;
  FrameColourNames: array[0..FrameColourCount - 1] of string = ('Original cyan', 'Own colour', 'Rainbow',
    'Menu palette', 'Two-colour gradient');
  FrameFillCount = 4;
  FrameFillNames: array[0..FrameFillCount - 1] of string = ('Solid', 'Gradient', 'Glass', 'Tinted');
  FrameIntroCount = 4;
  FrameIntroNames: array[0..FrameIntroCount - 1] of string = ('None', 'Border draws in', 'Flash', 'Expand');

  { status bar extras (TMenuFx.StatusX) }
  StatusXCount = 4;
  sxBar = 0;
  sxBarGlow = 1;
  sxHints = 2;
  sxHintAmount = 3;
  BarStyleCount = 7;
  BarStyleNames: array[0..BarStyleCount - 1] of string = ('Original', 'Glow', 'Striped (moving)',
    'Liquid wave', 'LED segments', 'Rainbow', 'Pulse');
  HintStyleCount = 5;
  HintStyleNames: array[0..HintStyleCount - 1] of string = ('Static', 'Breathing', 'Colour cycle',
    'Light sweep', 'Wave');

  { the values of one stat (TStatFx.V) }
  StatParamCount = 8;
  spStyle = 0;
  spReact = 1;
  spColourMode = 2;
  spStrength = 3;
  spSpeed = 4;
  spSize = 5;
  spGlow = 6;
  spReactTime = 7;

  StatStyleCount = 10;
  StatStyleNames: array[0..StatStyleCount - 1] of string = ('Static', 'Pulse', 'Glow pulse', 'Wave',
    'Light sweep', 'Neon flicker', 'Bounce', 'Heartbeat', 'Jelly', 'Glitch');
  StatReactCount = 8;
  StatReactNames: array[0..StatReactCount - 1] of string = ('None', 'Pop', 'Flash', 'Count up',
    'Count up + pop', 'Shake', 'Sparkle burst', 'Rolling digits');
  StatColourCount = 5;
  StatColourNames: array[0..StatColourCount - 1] of string = ('Game colour', 'Own colour', 'Rainbow',
    'Menu palette', 'Two-colour gradient');

  { menu items that are not selected (TItemFx.V) }
  ItemParamCount = 13;
  ipSize = 0;
  ipColourMode = 1;
  ipArt = 2;
  ipPixel = 3;
  ipIdle = 4;
  ipIdleAmount = 5;
  ipLeave = 6;
  ipLeaveStrength = 7;
  ipLeaveTime = 8;
  ipTrail = 9;
  ipTrailAmount = 10;
  ipTrailTime = 11;
  ipGlow = 12;

  ItemColourCount = 5;
  ItemColourNames: array[0..ItemColourCount - 1] of string = ('Breathing palette (original)', 'Own colour',
    'Rainbow', 'Menu palette', 'Two-colour gradient');
  ItemArtCount = 8;
  ItemArtNames: array[0..ItemArtCount - 1] of string = ('Plain', 'Pixel art', 'Neon tube', '3D block',
    'Chrome', 'Retro scanlines', 'LED dots', 'Soft glow');
  ItemIdleCount = 5;
  ItemIdleNames: array[0..ItemIdleCount - 1] of string = ('Still', 'Float', 'Sway', 'Breathe (size)',
    'Shimmer');
  ItemLeaveCount = 7;
  ItemLeaveNames: array[0..ItemLeaveCount - 1] of string = ('None', 'Slingshot', 'Shake and settle',
    'Rubber band', 'Jelly', 'Drop bounce', 'Flip');
  ItemTrailCount = 6;
  ItemTrailNames: array[0..ItemTrailCount - 1] of string = ('None', 'Dust', 'Liquid drips', 'Sparks',
    'Bubbles', 'Confetti');

type
  TFrameFx = record
    V: array[0..FrameParamCount - 1] of Single;
    Colour, Colour2, FillColour: Cardinal;   // $RRGGBB
  end;

  { a frame as DrawBase placed it (the fill is in the cached base, the border
    and its effects are drawn every frame when they move) }
  THudFrame = record
    Kind: Integer;
    X1, Y1, X2, Y2, R: Single;
    T0: Double;               // when it appeared (intro)
    Live: Boolean;            // drawn every frame
  end;

  { an animated key hint of the status bar }
  THudHint = record
    Font: Integer;
    Text: string;
    X, Y: Single;
    Colour: Cardinal;
    Align: Integer;
  end;

  TItemFx = record
    V: array[0..ItemParamCount - 1] of Single;
    Colour, Colour2: Cardinal;   // $RRGGBB: own colour / gradient
  end;

  { a particle of the selector trail (dust, drips, ...) }
  TMenuPart = record
    X, Y, VX, VY, Size, Age, Life, Spin: Single;
    Kind: Integer;              // ItemTrail mode
    Colour: Cardinal;           // $RRGGBB
  end;

  { what a HUD remembers of one menu item between frames }
  TMenuItemState = record
    LeaveT: Double;             // clock when the selector left it (-1000 = never)
    Dir: Single;                // +1 the selector went down, -1 up
    W, H: Single;               // drawn text size (trail spawn area)
    X, Y: Single;               // drawn centre
  end;

  TStatFx = record
    V: array[0..StatParamCount - 1] of Single;
    Colour, Colour2: Cardinal;   // $RRGGBB: own colour / gradient
  end;

  TMenuFx = record
    V: array[0..FxParamCount - 1] of Single;
    CustomPalette: Boolean;
    Palette: array[0..3] of Cardinal;   // $RRGGBB, used when CustomPalette
    Stat: array[0..StatCount - 1] of TStatFx;
    Item: TItemFx;
    Frame: array[0..FrameCount - 1] of TFrameFx;
    StatusX: array[0..StatusXCount - 1] of Single;
  end;

  { a stat of the top bar as DrawBase places it (drawn every frame) }
  THudStat = record
    Kind: Integer;            // stLevel, stScore, stBest
    Font: Integer;            // THudFont of the HUD
    Prefix: string;           // e.g. 'LEVEL '
    Text: string;             // the whole text instead of Prefix + Value ('' = number)
    Value: Int64;
    X, Y: Single;
    Colour: Cardinal;         // $RRGGBB: the game's colour
    Align: Integer;           // -1 left, 0 centre, 1 right
  end;

  { what a HUD remembers of a stat between frames (the change reaction) }
  THudStatState = record
    Known: Boolean;
    Val, OldVal: Int64;
    OldText, LastText: string;
    T0: Double;               // clock of the last change
  end;

  TFxParamInfo = record
    Key, Caption, Group, Hint: string;
    Min, Max, Def: Single;
    IsInt: Boolean;
  end;

const
  { indices into TMenuFx.V }
  fxColourSpeed = 0;
  fxTitleWave = 1;
  fxTitleGlow = 2;
  fxTitleFlash = 3;
  fxTitleSpotlight = 4;
  fxTitleSparkles = 5;
  fxTitleIntro = 6;
  fxPanelBorder = 7;
  fxPanelComets = 8;
  fxCometSpeed = 9;
  fxCometSize = 10;
  fxCometTail = 11;
  fxHeadIntro = 12;
  fxHeadGlow = 13;
  fxHeadLines = 14;
  fxHeadSweep = 15;
  fxHeadSplit = 16;
  fxItemSlide = 17;
  fxItemBreath = 18;
  fxSelGlow = 19;
  fxSelRing = 20;
  fxSelSweep = 21;
  fxSelSparks = 22;
  fxChevronBounce = 23;
  fxSelPulse = 24;
  fxMenuSpeed = 25;

  FxParams: array[0..FxParamCount - 1] of TFxParamInfo = (
    (Key: 'ColourSpeed'; Caption: 'Colour cycle speed'; Group: 'Colours';
      Hint: 'how fast the menu colours run through the palette'; Min: 0; Max: 4; Def: 1; IsInt: False),
    (Key: 'TitleWave'; Caption: 'Title wave'; Group: 'Title';
      Hint: 'height of the wave running through the title letters'; Min: 0; Max: 4; Def: 1; IsInt: False),
    (Key: 'TitleGlow'; Caption: 'Title glow'; Group: 'Title';
      Hint: 'strength of the coloured halo around the title letters'; Min: 0; Max: 2; Def: 1; IsInt: False),
    (Key: 'TitleFlash'; Caption: 'Title flash sweep'; Group: 'Title';
      Hint: 'the white-hot flash that sweeps across the title'; Min: 0; Max: 2; Def: 1; IsInt: False),
    (Key: 'TitleSpotlight'; Caption: 'Title spotlight'; Group: 'Title';
      Hint: 'the breathing coloured light behind the title'; Min: 0; Max: 3; Def: 1; IsInt: False),
    (Key: 'TitleSparkles'; Caption: 'Title sparkles'; Group: 'Title';
      Hint: 'number of twinkling glints around the title'; Min: 0; Max: 24; Def: 8; IsInt: True),
    (Key: 'TitleIntro'; Caption: 'Title drop-in speed'; Group: 'Title';
      Hint: 'speed of the letters dropping in when the menu opens'; Min: 0.25; Max: 4; Def: 1; IsInt: False),
    (Key: 'PanelBorder'; Caption: 'Panel border light'; Group: 'Panel';
      Hint: 'the menu panel border breathing in the palette colours'; Min: 0; Max: 2.5; Def: 1; IsInt: False),
    (Key: 'PanelComets'; Caption: 'Panel comets'; Group: 'Panel';
      Hint: 'light comets running around the menu panel'; Min: 0; Max: 8; Def: 2; IsInt: True),
    (Key: 'CometSpeed'; Caption: 'Comet speed'; Group: 'Panel';
      Hint: 'laps per second of the comets'; Min: 0; Max: 5; Def: 1; IsInt: False),
    (Key: 'CometSize'; Caption: 'Comet size'; Group: 'Panel';
      Hint: 'size of the comet heads'; Min: 0.3; Max: 3; Def: 1; IsInt: False),
    (Key: 'CometTail'; Caption: 'Comet tail'; Group: 'Panel';
      Hint: 'number of dots in a comet tail'; Min: 1; Max: 48; Def: 16; IsInt: True),
    (Key: 'HeadIntro'; Caption: 'Heading rise'; Group: 'Headings';
      Hint: 'how far headings rise into place when they appear'; Min: 0; Max: 3; Def: 1; IsInt: False),
    (Key: 'HeadGlow'; Caption: 'Heading halo'; Group: 'Headings';
      Hint: 'the pulsing halo behind headings'; Min: 0; Max: 2.5; Def: 1; IsInt: False),
    (Key: 'HeadLines'; Caption: 'Heading light lines'; Group: 'Headings';
      Hint: 'length of the light lines at both sides of headings'; Min: 0; Max: 2.5; Def: 1; IsInt: False),
    (Key: 'HeadSweep'; Caption: 'Heading light sweep'; Group: 'Headings';
      Hint: 'the white sweep running across headings'; Min: 0; Max: 1.5; Def: 1; IsInt: False),
    (Key: 'HeadSplit'; Caption: 'Heading colour split'; Group: 'Headings';
      Hint: 'magenta / cyan edges of headings'; Min: 0; Max: 3; Def: 1; IsInt: False),
    (Key: 'ItemSlide'; Caption: 'Item slide-in'; Group: 'Items';
      Hint: 'distance the menu items slide in from'; Min: 0; Max: 3; Def: 1; IsInt: False),
    (Key: 'ItemBreath'; Caption: 'Item colour breathing'; Group: 'Items';
      Hint: 'how much the other items shimmer in the palette'; Min: 0; Max: 5; Def: 1; IsInt: False),
    (Key: 'SelGlow'; Caption: 'Selected text glow'; Group: 'Selection';
      Hint: 'halo around the selected item'; Min: 0; Max: 2.5; Def: 1; IsInt: False),
    (Key: 'SelRing'; Caption: 'Selected outer ring'; Group: 'Selection';
      Hint: 'the soft light ring around the selection bar'; Min: 0; Max: 3; Def: 1; IsInt: False),
    (Key: 'SelSweep'; Caption: 'Selected light sweep'; Group: 'Selection';
      Hint: 'sheen running across the selection bar and text'; Min: 0; Max: 3; Def: 1; IsInt: False),
    (Key: 'SelSparks'; Caption: 'Selected sparks'; Group: 'Selection';
      Hint: 'sparks travelling along the selection bar'; Min: 0; Max: 20; Def: 6; IsInt: True),
    (Key: 'ChevronBounce'; Caption: 'Chevron bounce'; Group: 'Selection';
      Hint: 'how far the > < arrows bounce'; Min: 0; Max: 4; Def: 1; IsInt: False),
    (Key: 'SelPulse'; Caption: 'Selection pulse speed'; Group: 'Selection';
      Hint: 'speed of the selection bar pulse'; Min: 0; Max: 4; Def: 1; IsInt: False),
    (Key: 'MenuSpeed'; Caption: 'Overall animation speed'; Group: 'Colours';
      Hint: 'speed of all menu animations (comets, waves, sweeps)'; Min: 0.2; Max: 3; Def: 1; IsInt: False));

  StatParams: array[0..StatParamCount - 1] of TFxParamInfo = (
    (Key: 'Style'; Caption: 'Style'; Group: '';
      Hint: 'the looping effect'; Min: 0; Max: StatStyleCount - 1; Def: 0; IsInt: True),
    (Key: 'Reaction'; Caption: 'When it changes'; Group: '';
      Hint: 'what happens when the value changes'; Min: 0; Max: StatReactCount - 1; Def: 0; IsInt: True),
    (Key: 'ColourMode'; Caption: 'Colour'; Group: '';
      Hint: 'where the colour comes from'; Min: 0; Max: StatColourCount - 1; Def: 0; IsInt: True),
    (Key: 'Strength'; Caption: 'Strength'; Group: '';
      Hint: 'how strong the style and the reaction are'; Min: 0; Max: 3; Def: 1; IsInt: False),
    (Key: 'Speed'; Caption: 'Speed'; Group: '';
      Hint: 'speed of the style and the colours'; Min: 0.1; Max: 4; Def: 1; IsInt: False),
    (Key: 'Size'; Caption: 'Size'; Group: '';
      Hint: 'size of the text (1 = the original)'; Min: 0.6; Max: 1.6; Def: 1; IsInt: False),
    (Key: 'Glow'; Caption: 'Glow'; Group: '';
      Hint: 'the halo around the text'; Min: 0; Max: 2; Def: 0; IsInt: False),
    (Key: 'ReactTime'; Caption: 'Reaction time'; Group: '';
      Hint: 'seconds the reaction lasts'; Min: 0.1; Max: 3; Def: 0.6; IsInt: False));

  ItemParams: array[0..ItemParamCount - 1] of TFxParamInfo = (
    (Key: 'Size'; Caption: 'Size'; Group: 'Look';
      Hint: 'size of the items that are not selected (1 = the original)'; Min: 0.6; Max: 1.6; Def: 1; IsInt: False),
    (Key: 'ColourMode'; Caption: 'Colour'; Group: 'Look';
      Hint: 'colour of the items that are not selected'; Min: 0; Max: ItemColourCount - 1; Def: 0; IsInt: True),
    (Key: 'Art'; Caption: 'Art style'; Group: 'Look';
      Hint: 'how the letters are drawn'; Min: 0; Max: ItemArtCount - 1; Def: 0; IsInt: True),
    (Key: 'Pixel'; Caption: 'Pixel size'; Group: 'Look';
      Hint: 'block size of pixel art / LED dots, depth of 3D block'; Min: 2; Max: 8; Def: 3; IsInt: True),
    (Key: 'Idle'; Caption: 'Idle motion'; Group: 'Idle';
      Hint: 'motion while nothing happens'; Min: 0; Max: ItemIdleCount - 1; Def: 1; IsInt: True),
    (Key: 'IdleAmount'; Caption: 'Idle amount'; Group: 'Idle';
      Hint: 'how much the idle motion moves'; Min: 0; Max: 3; Def: 0.6; IsInt: False),
    (Key: 'Leave'; Caption: 'When the selector leaves'; Group: 'Selector leaves';
      Hint: 'what the item does when the selection moves away'; Min: 0; Max: ItemLeaveCount - 1; Def: 3; IsInt: True),
    (Key: 'LeaveStrength'; Caption: 'Strength'; Group: 'Selector leaves';
      Hint: 'how hard the item reacts'; Min: 0; Max: 3; Def: 1; IsInt: False),
    (Key: 'LeaveTime'; Caption: 'Reaction time'; Group: 'Selector leaves';
      Hint: 'seconds until the item is still again'; Min: 0.2; Max: 3; Def: 0.9; IsInt: False),
    (Key: 'Trail'; Caption: 'Selector trail'; Group: 'Selector trail';
      Hint: 'what the selector leaves behind on the item it passes'; Min: 0; Max: ItemTrailCount - 1; Def: 1; IsInt: True),
    (Key: 'TrailAmount'; Caption: 'Amount'; Group: 'Selector trail';
      Hint: 'how many particles'; Min: 0; Max: 3; Def: 1; IsInt: False),
    (Key: 'TrailTime'; Caption: 'Fade time'; Group: 'Selector trail';
      Hint: 'seconds until the particles are gone'; Min: 0.2; Max: 4; Def: 1.2; IsInt: False),
    (Key: 'Glow'; Caption: 'Glow'; Group: 'Look';
      Hint: 'halo around the items that are not selected'; Min: 0; Max: 2; Def: 0; IsInt: False));

  FrameParams: array[0..FrameParamCount - 1] of TFxParamInfo = (
    (Key: 'Style'; Caption: 'Border style'; Group: '';
      Hint: 'animation and light of the border'; Min: 0; Max: FrameStyleCount - 1; Def: 0; IsInt: True),
    (Key: 'ColourMode'; Caption: 'Border colour'; Group: '';
      Hint: 'where the border colour comes from'; Min: 0; Max: FrameColourCount - 1; Def: 0; IsInt: True),
    (Key: 'Brightness'; Caption: 'Brightness'; Group: '';
      Hint: 'brightness of the border (1 = the original)'; Min: 0; Max: 2.3; Def: 1; IsInt: False),
    (Key: 'Width'; Caption: 'Border width'; Group: '';
      Hint: 'line width of the border in pixels'; Min: 0.5; Max: 5; Def: 1.5; IsInt: False),
    (Key: 'Radius'; Caption: 'Corner radius'; Group: '';
      Hint: 'roundness of the corners (1 = the original, 0 = square)'; Min: 0; Max: 2; Def: 1; IsInt: False),
    (Key: 'Glow'; Caption: 'Glow'; Group: '';
      Hint: 'soft light around the border'; Min: 0; Max: 2; Def: 0; IsInt: False),
    (Key: 'Speed'; Caption: 'Speed'; Group: '';
      Hint: 'speed of the border animation'; Min: 0.1; Max: 4; Def: 1; IsInt: False),
    (Key: 'Count'; Caption: 'Lights / dashes'; Group: '';
      Hint: 'number of running lights, dash density, rings'; Min: 1; Max: 8; Def: 2; IsInt: True),
    (Key: 'Fill'; Caption: 'Fill opacity'; Group: '';
      Hint: 'opacity of the frame fill (1 = the original)'; Min: 0; Max: 1.3; Def: 1; IsInt: False),
    (Key: 'FillStyle'; Caption: 'Fill style'; Group: '';
      Hint: 'how the inside is filled'; Min: 0; Max: FrameFillCount - 1; Def: 0; IsInt: True),
    (Key: 'Intro'; Caption: 'When it appears'; Group: '';
      Hint: 'animation when the frame appears'; Min: 0; Max: FrameIntroCount - 1; Def: 0; IsInt: True),
    (Key: 'IntroTime'; Caption: 'Intro time'; Group: '';
      Hint: 'seconds of the intro'; Min: 0.1; Max: 2; Def: 0.6; IsInt: False));

  StatusXParams: array[0..StatusXCount - 1] of TFxParamInfo = (
    (Key: 'Bar'; Caption: 'Progress bar'; Group: '';
      Hint: 'style of the progress bar (Neon Trail sparks)'; Min: 0; Max: BarStyleCount - 1; Def: 2; IsInt: True),
    (Key: 'BarGlow'; Caption: 'Bar glow'; Group: '';
      Hint: 'light around the progress bar'; Min: 0; Max: 2; Def: 0.4; IsInt: False),
    (Key: 'Hints'; Caption: 'Key hints'; Group: '';
      Hint: 'animation of the key hints on the right'; Min: 0; Max: HintStyleCount - 1; Def: 1; IsInt: True),
    (Key: 'HintAmount'; Caption: 'Hint amount'; Group: '';
      Hint: 'how much the key hints move / shine'; Min: 0; Max: 2; Def: 0.6; IsInt: False));

var
  MenuFx: TMenuFx;
  { changes whenever the effects change (a file loaded, an editor change):
    the HUDs redraw their cached base (frame fills, still borders) }
  MenuFxStamp: Integer = 0;

function DefaultMenuFx: TMenuFx;
function LoadMenuFxFile(const AFile: string; var AFx: TMenuFx): Boolean;
procedure SaveMenuFxFile(const AFile: string; const AFx: TMenuFx);
function FxI(AIndex: Integer): Integer;   // MenuFx.V[AIndex] as a count
function DefaultStatFx(AKind: Integer): TStatFx;
function DefaultItemFx: TItemFx;
function DefaultFrameFx(AKind: Integer): TFrameFx;

implementation

var
  FS: TFormatSettings;

const
  DefPalette: array[0..3] of Cardinal = ($23D7F0, $E62891, $F59623, $964BF0);

{ the defaults give each stat a look of its own: LEVEL a light sweep that
  pops on a new level, SCORE a soft glow that counts up, BEST a slow wave
  that bursts into sparkles on a new best }
function DefaultStatFx(AKind: Integer): TStatFx;
const
  { Style, Reaction, ColourMode, Strength, Speed, Size, Glow, ReactTime }
  Defs: array[0..StatCount - 1, 0..StatParamCount - 1] of Single = (
    (4, 1, 0, 1, 1, 1, 0.4, 0.7),
    (2, 4, 0, 0.8, 1, 1, 0.3, 0.6),
    (3, 6, 0, 0.5, 0.8, 1, 0.2, 0.9),
    (2, 1, 0, 0.6, 1, 1, 0.2, 0.5));
  Own: array[0..StatCount - 1] of Cardinal = ($46DCF0, $F0F0F5, $FFD75A, $78EB6E);
var
  i: Integer;
begin
  AKind := EnsureRange(AKind, 0, StatCount - 1);
  for i := 0 to StatParamCount - 1 do Result.V[i] := Defs[AKind, i];
  Result.Colour := Own[AKind];
  Result.Colour2 := $E62891;
end;

{ the top bar has running lights, the status bar breathes, message boxes
  draw their border in and light their corners }
function DefaultFrameFx(AKind: Integer): TFrameFx;
var
  i: Integer;
begin
  for i := 0 to FrameParamCount - 1 do Result.V[i] := FrameParams[i].Def;
  case AKind of
    frTop:
      begin
        Result.V[fpStyle] := 2;
        Result.V[fpGlow] := 0.3;
      end;
    frStatus:
      begin
        Result.V[fpStyle] := 1;
        Result.V[fpGlow] := 0.5;
      end;
  else
    begin
      Result.V[fpStyle] := 8;
      Result.V[fpIntro] := 1;
    end;
  end;
  Result.Colour := $46C8E6;
  Result.Colour2 := $E62891;
  Result.FillColour := $080A16;
end;

function DefaultItemFx: TItemFx;
var
  i: Integer;
begin
  for i := 0 to ItemParamCount - 1 do Result.V[i] := ItemParams[i].Def;
  Result.Colour := $C8CEDE;
  Result.Colour2 := $23D7F0;
end;

function DefaultMenuFx: TMenuFx;
var
  i: Integer;
begin
  for i := 0 to FxParamCount - 1 do Result.V[i] := FxParams[i].Def;
  Result.CustomPalette := False;
  for i := 0 to 3 do Result.Palette[i] := DefPalette[i];
  for i := 0 to StatCount - 1 do Result.Stat[i] := DefaultStatFx(i);
  Result.Item := DefaultItemFx;
  for i := 0 to FrameCount - 1 do Result.Frame[i] := DefaultFrameFx(i);
  for i := 0 to StatusXCount - 1 do Result.StatusX[i] := StatusXParams[i].Def;
end;

function ReadHex(ini: TMemIniFile; const ASec, AKey: string; ADef: Cardinal): Cardinal;
var
  s: string;
begin
  s := Trim(ini.ReadString(ASec, AKey, ''));
  if (s <> '') and (s[1] = '#') then Delete(s, 1, 1);
  Result := Cardinal(StrToIntDef('$' + s, ADef)) and $FFFFFF;
end;

function FxI(AIndex: Integer): Integer;
begin
  Result := Round(MenuFx.V[AIndex]);
end;

function LoadMenuFxFile(const AFile: string; var AFx: TMenuFx): Boolean;
var
  ini: TMemIniFile;
  i, k: Integer;
  v: Single;
  s: string;
  def: TStatFx;
  idef: TItemFx;
  fdef: TFrameFx;
  sec: string;
begin
  Result := False;
  if not FileExists(AFile) then Exit;
  try
    ini := TMemIniFile.Create(AFile);
    try
      for i := 0 to FxParamCount - 1 do
      begin
        v := StrToFloatDef(Trim(ini.ReadString('MenuFx', FxParams[i].Key, '')), FxParams[i].Def, FS);
        v := EnsureRange(v, FxParams[i].Min, FxParams[i].Max);
        if FxParams[i].IsInt then v := Round(v);
        AFx.V[i] := v;
      end;
      AFx.CustomPalette := ini.ReadBool('MenuFx', 'CustomPalette', False);
      for i := 0 to 3 do
      begin
        s := Trim(ini.ReadString('MenuFx', 'Colour' + IntToStr(i + 1), ''));
        if (s <> '') and (s[1] = '#') then Delete(s, 1, 1);
        AFx.Palette[i] := Cardinal(StrToIntDef('$' + s, DefPalette[i])) and $FFFFFF;
      end;
      { [Level] [Score] [Best]: a file without them keeps the defaults }
      for k := 0 to StatCount - 1 do
      begin
        def := DefaultStatFx(k);
        for i := 0 to StatParamCount - 1 do
        begin
          v := StrToFloatDef(Trim(ini.ReadString(StatNames[k], StatParams[i].Key, '')), def.V[i], FS);
          v := EnsureRange(v, StatParams[i].Min, StatParams[i].Max);
          if StatParams[i].IsInt then v := Round(v);
          AFx.Stat[k].V[i] := v;
        end;
        AFx.Stat[k].Colour := ReadHex(ini, StatNames[k], 'Colour', def.Colour);
        AFx.Stat[k].Colour2 := ReadHex(ini, StatNames[k], 'Colour2', def.Colour2);
      end;
      { [Items]: the menu items that are not selected }
      idef := DefaultItemFx;
      for i := 0 to ItemParamCount - 1 do
      begin
        v := StrToFloatDef(Trim(ini.ReadString('Items', ItemParams[i].Key, '')), idef.V[i], FS);
        v := EnsureRange(v, ItemParams[i].Min, ItemParams[i].Max);
        if ItemParams[i].IsInt then v := Round(v);
        AFx.Item.V[i] := v;
      end;
      AFx.Item.Colour := ReadHex(ini, 'Items', 'Colour', idef.Colour);
      AFx.Item.Colour2 := ReadHex(ini, 'Items', 'Colour2', idef.Colour2);
      { frames and the status bar extras }
      for k := 0 to FrameCount - 1 do
      begin
        fdef := DefaultFrameFx(k);
        sec := 'Frame: ' + FrameNames[k];
        for i := 0 to FrameParamCount - 1 do
        begin
          v := StrToFloatDef(Trim(ini.ReadString(sec, FrameParams[i].Key, '')), fdef.V[i], FS);
          v := EnsureRange(v, FrameParams[i].Min, FrameParams[i].Max);
          if FrameParams[i].IsInt then v := Round(v);
          AFx.Frame[k].V[i] := v;
        end;
        AFx.Frame[k].Colour := ReadHex(ini, sec, 'Colour', fdef.Colour);
        AFx.Frame[k].Colour2 := ReadHex(ini, sec, 'Colour2', fdef.Colour2);
        AFx.Frame[k].FillColour := ReadHex(ini, sec, 'FillColour', fdef.FillColour);
      end;
      for i := 0 to StatusXCount - 1 do
      begin
        v := StrToFloatDef(Trim(ini.ReadString('Status bar extras', StatusXParams[i].Key, '')),
          StatusXParams[i].Def, FS);
        v := EnsureRange(v, StatusXParams[i].Min, StatusXParams[i].Max);
        if StatusXParams[i].IsInt then v := Round(v);
        AFx.StatusX[i] := v;
      end;
      Inc(MenuFxStamp);
    finally
      ini.Free;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

function NameList(const ANames: array of string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ANames) do
  begin
    if i > 0 then Result += ', ';
    Result += IntToStr(i) + ' ' + ANames[i];
  end;
end;

procedure SaveMenuFxFile(const AFile: string; const AFx: TMenuFx);
var
  sl: TStringList;
  i, k: Integer;
  g: string;
begin
  sl := TStringList.Create;
  try
    sl.Add('; Neon game menu effects - edit with NeonMenuFxEditor (NeonGrid SDL3 GPU Tools) or by hand.');
    sl.Add('; Multipliers: 1 = the original look, 0 = off. The game reloads this file while it runs.');
    sl.Add('[MenuFx]');
    g := '';
    for i := 0 to FxParamCount - 1 do
    begin
      if FxParams[i].Group <> g then
      begin
        g := FxParams[i].Group;
        sl.Add('; ---- ' + g);
      end;
      sl.Add('; ' + FxParams[i].Hint + Format(' (%s .. %s)',
        [FormatFloat('0.##', FxParams[i].Min, FS), FormatFloat('0.##', FxParams[i].Max, FS)]));
      sl.Add(FxParams[i].Key + '=' + FormatFloat('0.###', AFx.V[i], FS));
    end;
    sl.Add('; ---- Palette (CustomPalette=1 replaces the bead colours of the menu)');
    sl.Add('CustomPalette=' + IntToStr(Ord(AFx.CustomPalette)));
    for i := 0 to 3 do sl.Add('Colour' + IntToStr(i + 1) + '=#' + IntToHex(AFx.Palette[i] and $FFFFFF, 6));
    { the in-game top bar: one section per stat }
    for k := 0 to StatCount - 1 do
    begin
      sl.Add('');
      sl.Add('; ---- ' + StatNames[k] + ' (top bar while playing)');
      sl.Add('[' + StatNames[k] + ']');
      sl.Add('; Style: ' + NameList(StatStyleNames));
      sl.Add('; Reaction: ' + NameList(StatReactNames));
      sl.Add('; ColourMode: ' + NameList(StatColourNames) + '; Colour2 is the gradient end');
      for i := 0 to StatParamCount - 1 do
        sl.Add(StatParams[i].Key + '=' + FormatFloat('0.###', AFx.Stat[k].V[i], FS));
      sl.Add('Colour=#' + IntToHex(AFx.Stat[k].Colour and $FFFFFF, 6));
      sl.Add('Colour2=#' + IntToHex(AFx.Stat[k].Colour2 and $FFFFFF, 6));
    end;
    sl.Add('');
    sl.Add('; ---- Menu items that are not selected');
    sl.Add('[Items]');
    sl.Add('; ColourMode: ' + NameList(ItemColourNames) + '; Colour2 is the gradient end');
    sl.Add('; Art: ' + NameList(ItemArtNames));
    sl.Add('; Idle: ' + NameList(ItemIdleNames));
    sl.Add('; Leave: ' + NameList(ItemLeaveNames));
    sl.Add('; Trail: ' + NameList(ItemTrailNames));
    for i := 0 to ItemParamCount - 1 do
      sl.Add(ItemParams[i].Key + '=' + FormatFloat('0.###', AFx.Item.V[i], FS));
    sl.Add('Colour=#' + IntToHex(AFx.Item.Colour and $FFFFFF, 6));
    sl.Add('Colour2=#' + IntToHex(AFx.Item.Colour2 and $FFFFFF, 6));
    for k := 0 to FrameCount - 1 do
    begin
      sl.Add('');
      sl.Add('; ---- Frame of the ' + LowerCase(FrameNames[k]));
      sl.Add('[Frame: ' + FrameNames[k] + ']');
      sl.Add('; Style: ' + NameList(FrameStyleNames));
      sl.Add('; ColourMode: ' + NameList(FrameColourNames) + '; Colour2 is the gradient end');
      sl.Add('; FillStyle: ' + NameList(FrameFillNames) + '; Intro: ' + NameList(FrameIntroNames));
      for i := 0 to FrameParamCount - 1 do
        sl.Add(FrameParams[i].Key + '=' + FormatFloat('0.###', AFx.Frame[k].V[i], FS));
      sl.Add('Colour=#' + IntToHex(AFx.Frame[k].Colour and $FFFFFF, 6));
      sl.Add('Colour2=#' + IntToHex(AFx.Frame[k].Colour2 and $FFFFFF, 6));
      sl.Add('FillColour=#' + IntToHex(AFx.Frame[k].FillColour and $FFFFFF, 6));
    end;
    sl.Add('');
    sl.Add('; ---- Status bar: progress bar and key hints');
    sl.Add('[Status bar extras]');
    sl.Add('; Bar: ' + NameList(BarStyleNames));
    sl.Add('; Hints: ' + NameList(HintStyleNames));
    for i := 0 to StatusXCount - 1 do
      sl.Add(StatusXParams[i].Key + '=' + FormatFloat('0.###', AFx.StatusX[i], FS));
    sl.SaveToFile(AFile);
  finally
    sl.Free;
  end;
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  MenuFx := DefaultMenuFx;

end.
