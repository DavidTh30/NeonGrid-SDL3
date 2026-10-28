unit uBeadGame;

{ Neon Beads - game rules (SameGame style) on the neon dot grid.

  Click a group of 2 or more touching beads of the same colour: the group
  flashes white-hot and pops, the beads above fall down and empty columns
  slide to the left. A group of n beads scores n x (n - 1) x 5.

  Special beads (from level 3; big groups also leave one behind):
    BOMB     pops the 3 x 3 area around it          - can be clicked alone
    LINE     pops its whole row                     - can be clicked alone
    x2       doubles the points of the move that pops it
    RAINBOW  matches every colour (joins any group it touches)
    STONE    grey blocker (from level 5): never matches, only bombs and lines
             break it; stones do not count as beads left
  A bomb or line caught in a blast goes off too (chain reaction). Every bead
  popped by a blast scores 20 (a stone 30).

  CLASSIC: when no move is left the level ends: it is passed when at most
  Goal beads remain (bonus 50 per bead under the goal, +1000 for a cleared
  board) and earns 1 - 3 stars; otherwise the game is over and the level
  can be retried. 3 undos per level.
  TIME ATTACK: 90 seconds on 12 x 15 boards; a board without moves is
  replaced by a fresh one (board bonus), big groups and blasts add time, and
  quick pops build a CHAIN multiplier (+0.1 per step, at most x2).
  SURVIVAL: no clock, 12 x 15 boards with 5 colours. Columns never slide:
  popped beads are refilled from the top. A pop of 2 beads brings 2 IRON
  beads with the refill, a pop of 3 brings 1; iron never matches and no
  blast breaks it. A pop of 7+ beads brings a bonus special (bomb, line, x2
  or rainbow), one more at 10, 14, 19 and 25. The game ends when no move is
  left; survival keeps its own best score and high-score table.
  VS BOT: survival rules on two 10 x 14 boards, the player (left) against a
  bot (right, 3 levels, played by the program). Iron only works while the
  scores are more than VsIronGap apart, and only the side that leads makes
  it: its pop of 9+ beads sends 1 iron bead to a random cell of the other
  board (one more at 12, 17 and 23), and the iron of its pops of 2 or 3
  (survival refill) goes to the other board too. The side behind makes no
  iron; within VsIronGap nobody does. The side that runs out of pairs first
  loses. No stalling: a side that has not popped for VsIdleSecs loses
  VsIdlePenalty points.

  Board coordinates: x = column (0 = left), y = row (0 = top). Animation
  offsets are in cells: a bead is drawn OffX cells to the right of and OffY
  cells above its board position, and both run down to 0.
  The game reports effects (FxEvents: particle bursts) and keeps per-game
  statistics for the achievements.

  The numbers of these rules (points, bonuses, rewards, time attack,
  survival, VS BOT) are editable: uBeadRules (NeonBeads.scoring,
  NeonBeads.versus); the defaults are the rules described above. The iron
  of VS BOT can also come from a flowchart (uIronFlow, NeonBeads.ironflow):
  when it is enabled it replaces MoveIron and the stalling rule. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, uGameFx, uBeadRules, uIronFlow;

const
  MaxColours = 6;
  UndosPerLevel = 3;
  { TimeAttackSecs, ChainWindow, MaxChainMult: uBeadRules (editable) }

  { special beads }
  SpNone = 0;
  SpBomb = 1;
  SpLine = 2;
  SpDouble = 3;
  SpRainbow = 4;
  SpStone = 5;
  SpIron = 6;          // survival: never matches, unbreakable
  { VsIdleSecs, VsIdlePenalty, VsIronGap: uBeadRules (editable) }
  BotLevels = 3;
  BotNames: array[0..BotLevels - 1] of string = ('EASY', 'NORMAL', 'HARD');

var
  { animation and colours: defaults here, the values come from NeonBeads.visuals }
  PopTime: Single = 0.24;
  Gravity: Single = 70;        // cells / s^2
  SlideSpeed: Single = 16;     // cells / s
  StoneRGB: array[0..2] of Byte = (105, 108, 125);
  IronRGB: array[0..2] of Byte = (170, 182, 200);
  { the bead colours of the current theme (uAchievements.ApplyTheme) }
  BeadRGB: array[0..MaxColours - 1, 0..2] of Byte = (
    (245, 150, 35),    // amber
    (35, 215, 240),    // cyan
    (230, 40, 145),    // magenta
    (150, 230, 55),    // lime
    (150, 75, 240),    // violet
    (245, 55, 55));    // red

type
  TGameState = (gsTitle, gsPlaying, gsPopping, gsSettling, gsLevelDone, gsGameOver);
  TGameMode = (gmClassic, gmTime, gmSurvival, gmVersus);
  TGameSound = (gsndPop, gsndInvalid, gsndLand, gsndUndo, gsndLevel, gsndGameOver, gsndStart,
    gsndMenuMove, gsndMenuSelect, gsndCrash, gsndGold, gsndPower);
  TSoundEvent = procedure(ASound: TGameSound; AParam: Integer) of object;
  TFxKind = (fxPop, fxBigPop, fxBomb, fxLine, fxStone, fxSpawn, fxLevel, fxClear, fxTime, fxIron);

  TCellFx = record
    Presence, Flash, Hover, OffX, OffY, VelY: Single;
  end;
  PCellFx = ^TCellFx;

  TLevelInfo = record
    W, H, Colours, Goal, Specials, Stones: Integer;
    Twist: string;
  end;

  TPopup = record
    X, Y: Single;      // board coordinates (cells)
    Age: Single;
    Text: string;
    Colour: Integer;   // bead colour, -1 = gold
  end;

  TBoardSnap = record
    Cells, Spec: array of ShortInt;
    Score, LevelScore: Integer;
  end;

  { a particle effect request for the program (board cell coordinates) }
  TFxEvent = record
    Kind: TFxKind;
    X, Y: Single;
    R, G, B: Byte;
    N: Integer;        // order in a pop (stagger), size, ...
  end;

  TBeadGame = class
  private
    FBoard: array of ShortInt;       // W * H, -1 = empty
    FSpec: array of ShortInt;        // special kind per cell
    FFx: array of TCellFx;
    FMark: array of Integer;         // flood-fill stamps
    FStamp: Integer;
    FHover: array of Integer;        // cells the hovered move would pop
    FHoverPts: Integer;
    FHoverGroup: Integer;
    FPopped: array of Integer;
    FTimer: Single;
    FUndo: array of TBoardSnap;
    FMouseX, FMouseY: Integer;
    FRng: Cardinal;
    FReward: Integer;                // special to leave behind after the pop
    FRewardX, FRewardY: Single;
    FBestOf: array[TGameMode] of Integer;   // time attack shares the classic best
    FEndPending, FEndWin: Boolean;        // VS BOT: the match ended, stop when settled
    FRefillIron, FRefillBonus: Integer;  // survival: what the next refill brings
    FTickT: Single;                      // VS BOT: seconds to the next "every second" flow
    FFlowRnd: Cardinal;                  // VS BOT: the flow's own random numbers (the board's stay the same)
    function Rand: Single;
    function Idx(x, y: Integer): Integer; inline;
    function Matches(j, c: Integer): Boolean; inline;
    procedure FindGroup(x, y, c: Integer; var AList: array of Integer; out ACount: Integer);
    function PopSet(x, y: Integer; var AList: array of Integer; out ACount, AGroup, APts,
      ASpecials: Integer): Boolean;
    procedure UpdateHover;
    procedure RemovePopped;
    procedure FinishBoard;
    procedure PlaceSpecials(ACount, AStones: Integer);
    procedure Sound(S: TGameSound; AParam: Integer = 0);
    procedure AddFx(AKind: TFxKind; x, y: Single; R, G, B: Byte; AN: Integer = 0);
    procedure AddPopup(x, y: Single; const AText: string; AColour: Integer);
    procedure CellRGBBytes(i: Integer; out R, G, B: Byte);
    procedure Refill;
    procedure ApplyIncoming;
    procedure DropIron(ACount: Integer; AIdle: Boolean);
    procedure ApplyEnd;
    function GetBest: Integer;
    procedure SetBest(AValue: Integer);
    function GetBestOf(AIndex: Integer): Integer;
    procedure SetBestOf(AIndex: Integer; AValue: Integer);
  public
    State: TGameState;
    Mode: TGameMode;
    Level, Score, LevelScore, LevelStartScore, MaxLevel, UndoLeft, Bonus: Integer;
    W, H, Colours, Goal, Moves, Stars: Integer;
    Twist: string;
    TimeLeft, ChainTimer: Single;
    Chain, Boards: Integer;
    Popups: array of TPopup;
    FxEvents: array of TFxEvent;     // consumed (cleared) by the program
    OnSound: TSoundEvent;
    { statistics for the achievements (per game, i.e. since PLAY) }
    Pops, MaxGroup, BombsUsed, LinesUsed, MaxSpecialsInMove, RainbowGroups, StonesBroken,
    BoardsCleared, NoUndoClears, MaxChain, LevelsPassed: Integer;
    UsedUndo: Boolean;
    { survival / VS BOT statistics }
    IronGained, IronReceived, IronSent, BonusGained, MaxPopCount, MaxAttack: Integer;
    { VS BOT: iron to send to the other side (taken by the program), iron
      waiting to land on this board, result 0 running / 1 won / 2 lost / 3 draw }
    OutIron, PendingIron, VsResult, VsBotLevel: Integer;
    VsWon: Boolean;
    IdleT: Single;                   // VS BOT: seconds since the last pop
    VsLead: Integer;                 // VS BOT: +1 ahead by more than VsIronGap, -1 behind, 0 within
    VsIronOn: Boolean;               // VS BOT: the gap is big enough for iron (set with VsLead)
    VsSide: Integer;                 // VS BOT: 0 left (player), 1 right (bot) - flow traces
    VsOtherScore, VsOtherIron: Integer;   // VS BOT: the other board (set by VersusExchange)
    VsTime: Single;                  // VS BOT: seconds of the match
    LastGroup, PopCount: Integer;    // the last pop's group size, pops so far (the announcer)
    constructor Create;
    class function LevelInfo(ALevel: Integer): TLevelInfo;
    procedure NewBoard(ALevel: Integer);
    procedure StartLevel(ALevel: Integer; AKeepScore: Boolean);
    procedure StartTimeAttack;
    procedure StartSurvival;
    procedure StartRun(AMode: TGameMode);   // survival or VS BOT
    { VS BOT: the match is over; stops the board once its animation settled }
    procedure EndRun(AWin: Boolean);
    procedure Reseed(ASeed: Cardinal);
    function Refills: Boolean;              // survival rules (refill, iron, bonus)
    class function AttackIron(ACount: Integer): Integer;
    procedure ShowTitle;
    procedure Update(dt: Single);
    procedure SetMouseCell(x, y: Integer);
    procedure Click;
    procedure Undo;
    function Cell(x, y: Integer): Integer;
    function Spec(x, y: Integer): Integer;
    function Fx(x, y: Integer): PCellFx;
    function BeadsLeft: Integer;
    function HasMoves: Boolean;
    function HoverCount: Integer;
    function HoverPoints: Integer;
    { size of the move at (x, y): beads it would pop, 0 = no move }
    function GroupSize(x, y: Integer): Integer;
    function Animating: Boolean;
    function SpecialsOnBoard: Integer;   // bit set of the special kinds present
    function ChainMult: Single;
    function IronCount: Integer;
    { iron / bonus beads a pop of ACount beads brings in survival }
    class procedure SurvivalRefill(ACount: Integer; out AIron, ABonus: Integer);
    { VS BOT: where the iron of a pop of ACount beads goes (VsLead, VsIronOn
      and the rules): ASend to the other board, AOwn onto this one }
    procedure MoveIron(ACount: Integer; out ASend, AOwn: Integer);
    { VS BOT: runs the iron flow (uIronFlow) for an event of this side; ADry
      only tells the iron (hover), else points, messages and traces apply }
    procedure FlowApply(AEvent: TFlowEvent; ACount: Integer; ADry: Boolean; out ASend, AOwn: Integer);
    { best score of the current mode (survival has its own) }
    property Best: Integer read GetBest write SetBest;
    property BestNormal: Integer index Ord(gmClassic) read GetBestOf write SetBestOf;
    property BestSurvival: Integer index Ord(gmSurvival) read GetBestOf write SetBestOf;
    property BestVersus: Integer index Ord(gmVersus) read GetBestOf write SetBestOf;
  end;

function SpecialName(AKind: Integer): string;
function ModeName(AMode: TGameMode): string;

implementation

function ModeName(AMode: TGameMode): string;
begin
  case AMode of
    gmTime: Result := 'TIME ATTACK';
    gmSurvival: Result := 'SURVIVAL';
    gmVersus: Result := 'VS BOT';
  else
    Result := 'CLASSIC';
  end;
end;

function SpecialName(AKind: Integer): string;
begin
  case AKind of
    SpBomb: Result := 'BOMB';
    SpLine: Result := 'LINE';
    SpDouble: Result := 'x2';
    SpRainbow: Result := 'RAINBOW';
    SpStone: Result := 'STONE';
    SpIron: Result := 'IRON';
  else
    Result := '';
  end;
end;

{ TBeadGame }

constructor TBeadGame.Create;
begin
  inherited Create;
  FRng := Cardinal(GetTickCount64) or 1;
  MaxLevel := 1;
  FMouseX := -1;
  FMouseY := -1;
  ShowTitle;
end;

function TBeadGame.Rand: Single;
begin
  FRng := FRng xor (FRng shl 13);
  FRng := FRng xor (FRng shr 17);
  FRng := FRng xor (FRng shl 5);
  Result := (FRng and $FFFFFF) / 16777216;
end;

function TBeadGame.Idx(x, y: Integer): Integer;
begin
  Result := x * H + y;
end;

procedure TBeadGame.Sound(S: TGameSound; AParam: Integer);
begin
  if Assigned(OnSound) and (State <> gsTitle) then OnSound(S, AParam);
end;

procedure TBeadGame.AddFx(AKind: TFxKind; x, y: Single; R, G, B: Byte; AN: Integer);
var
  n: Integer;
begin
  n := Length(FxEvents);
  if n > 600 then Exit;
  SetLength(FxEvents, n + 1);
  FxEvents[n].Kind := AKind;
  FxEvents[n].X := x;
  FxEvents[n].Y := y;
  FxEvents[n].R := R;
  FxEvents[n].G := G;
  FxEvents[n].B := B;
  FxEvents[n].N := AN;
end;

procedure TBeadGame.AddPopup(x, y: Single; const AText: string; AColour: Integer);
var
  n: Integer;
begin
  n := Length(Popups);
  SetLength(Popups, n + 1);
  Popups[n].X := x;
  Popups[n].Y := y;
  Popups[n].Age := 0;
  Popups[n].Text := AText;
  Popups[n].Colour := AColour;
end;

procedure TBeadGame.CellRGBBytes(i: Integer; out R, G, B: Byte);
begin
  if FSpec[i] = SpStone then
  begin
    R := StoneRGB[0]; G := StoneRGB[1]; B := StoneRGB[2];
  end
  else if FSpec[i] = SpIron then
  begin
    R := IronRGB[0]; G := IronRGB[1]; B := IronRGB[2];
  end
  else if FSpec[i] = SpRainbow then
  begin
    R := 255; G := 255; B := 255;
  end
  else if FBoard[i] >= 0 then
  begin
    R := BeadRGB[FBoard[i], 0]; G := BeadRGB[FBoard[i], 1]; B := BeadRGB[FBoard[i], 2];
  end
  else
  begin
    R := 255; G := 255; B := 255;
  end;
end;

class function TBeadGame.LevelInfo(ALevel: Integer): TLevelInfo;
const
  T: array[1..7, 0..5] of Integer = (
    { W, H, colours, goal, specials, stones }
    (10, 12, 3, 7, 0, 0), (11, 14, 3, 6, 0, 0), (12, 15, 4, 18, 2, 0), (12, 16, 4, 15, 3, 0),
    (13, 17, 5, 37, 3, 4), (14, 18, 5, 36, 4, 6), (14, 18, 6, 59, 4, 8));
begin
  if ALevel < 1 then ALevel := 1;
  if ALevel <= 7 then
  begin
    Result.W := T[ALevel, 0]; Result.H := T[ALevel, 1];
    Result.Colours := T[ALevel, 2]; Result.Goal := T[ALevel, 3];
    Result.Specials := T[ALevel, 4]; Result.Stones := T[ALevel, 5];
  end
  else
  begin
    Result.W := 14; Result.H := 18; Result.Colours := 6;
    Result.Goal := Max(40, 59 - (ALevel - 7) * 3);
    Result.Specials := Min(7, 2 + ALevel div 2);
    Result.Stones := Min(14, 4 + ALevel);
  end;
  case ALevel of
    1, 2: Result.Twist := '';
    3, 4: Result.Twist := 'special beads';
    5: Result.Twist := 'stones';
  else
    if ALevel mod 3 = 0 then Result.Twist := 'bomb party'
    else Result.Twist := 'stones + specials';
  end;
end;

{ ACount specials (kind by level) and AStones stones on random cells }
procedure TBeadGame.PlaceSpecials(ACount, AStones: Integer);
var
  k, i, tries, kind: Integer;
  r: Single;
begin
  for k := 1 to ACount + AStones do
    for tries := 1 to 50 do
    begin
      i := Trunc(Rand * W * H) mod (W * H);
      if (FBoard[i] < 0) or (FSpec[i] <> SpNone) then Continue;
      if k > ACount then
      begin
        { stones stay out of the bottom rows so the board does not lock up }
        if (i mod H) >= H - 2 then Continue;
        kind := SpStone;
      end
      else
      begin
        r := Rand;
        if Twist = 'bomb party' then
        begin
          if r < 0.6 then kind := SpBomb else if r < 0.85 then kind := SpLine else kind := SpRainbow;
        end
        else if r < 0.3 then kind := SpBomb
        else if r < 0.55 then kind := SpLine
        else if r < 0.8 then kind := SpDouble
        else kind := SpRainbow;
      end;
      FSpec[i] := kind;
      Break;
    end;
end;

procedure TBeadGame.NewBoard(ALevel: Integer);
var
  li: TLevelInfo;
  x, y, i: Integer;
begin
  li := LevelInfo(ALevel);
  if Mode = gmTime then
  begin
    li.W := 12; li.H := 15;
    li.Colours := Min(5, 4 + Boards div 3);
    li.Specials := 3;
    li.Stones := 0;
    li.Twist := '';
  end
  else if Mode in [gmSurvival, gmVersus] then
  begin
    if Mode = gmVersus then
    begin
      li.W := VRI(vrBoardW); li.H := VRI(vrBoardH);
      li.Colours := VRI(vrColours);
    end
    else
    begin
      li.W := 12; li.H := 15;
      li.Colours := 5;
    end;
    li.Goal := 0;
    li.Specials := 0;
    li.Stones := 0;    // no iron at the start
    li.Twist := '';
  end;
  W := li.W; H := li.H; Colours := li.Colours; Goal := li.Goal;
  Twist := li.Twist;
  SetLength(FBoard, W * H);
  SetLength(FSpec, W * H);
  SetLength(FFx, W * H);
  SetLength(FMark, W * H);
  FillChar(FMark[0], Length(FMark) * SizeOf(Integer), 0);
  FillChar(FSpec[0], Length(FSpec), 0);
  FStamp := 0;
  for x := 0 to W - 1 do
    for y := 0 to H - 1 do
    begin
      i := Idx(x, y);
      FBoard[i] := Trunc(Rand * Colours) mod Colours;
      FillChar(FFx[i], SizeOf(TCellFx), 0);
      FFx[i].Presence := 1;
      { drop-in intro: every bead starts above the board }
      FFx[i].OffY := H + 1 + Rand * 3 + x * 0.35;
    end;
  PlaceSpecials(li.Specials, li.Stones);
  SetLength(FHover, 0);
  SetLength(FPopped, 0);
  SetLength(Popups, 0);
end;

procedure TBeadGame.StartLevel(ALevel: Integer; AKeepScore: Boolean);
begin
  Mode := gmClassic;
  Level := Max(1, ALevel);
  if not AKeepScore then
  begin
    { a new game }
    Score := 0;
    Pops := 0; MaxGroup := 0; BombsUsed := 0; LinesUsed := 0; MaxSpecialsInMove := 0;
    RainbowGroups := 0; StonesBroken := 0; BoardsCleared := 0; NoUndoClears := 0;
    MaxChain := 0; LevelsPassed := 0;
  end;
  LevelStartScore := Score;
  LevelScore := 0;
  Bonus := 0;
  Stars := 0;
  UsedUndo := False;
  UndoLeft := UndosPerLevel;
  SetLength(FUndo, 0);
  NewBoard(Level);
  MaxLevel := Max(MaxLevel, Level);
  State := gsSettling;
  Sound(gsndStart);
end;

procedure TBeadGame.StartTimeAttack;
begin
  Mode := gmTime;
  Level := 1;
  Score := 0;
  LevelStartScore := 0;
  LevelScore := 0;
  Bonus := 0;
  Boards := 0;
  Chain := 0;
  ChainTimer := 0;
  TimeLeft := TimeAttackSecs;
  Pops := 0; MaxGroup := 0; BombsUsed := 0; LinesUsed := 0; MaxSpecialsInMove := 0;
  RainbowGroups := 0; StonesBroken := 0; BoardsCleared := 0; NoUndoClears := 0;
  MaxChain := 0; LevelsPassed := 0;
  UndoLeft := 0;
  SetLength(FUndo, 0);
  NewBoard(3);
  State := gsSettling;
  Sound(gsndStart);
end;

procedure TBeadGame.StartSurvival;
begin
  StartRun(gmSurvival);
end;

procedure TBeadGame.StartRun(AMode: TGameMode);
begin
  Mode := AMode;
  Level := 1;
  Score := 0;
  LevelStartScore := 0;
  LevelScore := 0;
  Bonus := 0;
  Boards := 0;
  Chain := 0;
  ChainTimer := 0;
  TimeLeft := 0;
  Pops := 0; MaxGroup := 0; BombsUsed := 0; LinesUsed := 0; MaxSpecialsInMove := 0;
  RainbowGroups := 0; StonesBroken := 0; BoardsCleared := 0; NoUndoClears := 0;
  MaxChain := 0; LevelsPassed := 0;
  UndoLeft := 0;
  FRefillIron := 0;
  FRefillBonus := 0;
  IronGained := 0; IronReceived := 0; IronSent := 0; BonusGained := 0; MaxPopCount := 0;
  MaxAttack := 0; OutIron := 0; PendingIron := 0; VsResult := 0; VsWon := False;
  IdleT := 0;
  VsLead := 0;
  VsTime := 0;
  FTickT := 0;
  FFlowRnd := 20240611;
  FEndPending := False;
  SetLength(FUndo, 0);
  NewBoard(1);
  State := gsSettling;
  Sound(gsndStart);
end;

function TBeadGame.GetBest: Integer;
begin
  Result := GetBestOf(Ord(Mode));
end;

procedure TBeadGame.SetBest(AValue: Integer);
begin
  SetBestOf(Ord(Mode), AValue);
end;

function TBeadGame.GetBestOf(AIndex: Integer): Integer;
begin
  if AIndex = Ord(gmTime) then AIndex := Ord(gmClassic);
  Result := FBestOf[TGameMode(AIndex)];
end;

procedure TBeadGame.SetBestOf(AIndex: Integer; AValue: Integer);
begin
  if AIndex = Ord(gmTime) then AIndex := Ord(gmClassic);
  FBestOf[TGameMode(AIndex)] := AValue;
end;

function TBeadGame.Refills: Boolean;
begin
  Result := Mode in [gmSurvival, gmVersus];
end;

class function TBeadGame.AttackIron(ACount: Integer): Integer;
var
  k: Integer;
begin
  Result := 0;
  for k := vrAttack1 to vrAttack4 do
    if (VRI(k) > 0) and (ACount >= VRI(k)) then Inc(Result);
end;

procedure TBeadGame.MoveIron(ACount: Integer; out ASend, AOwn: Integer);
var
  rbonus, d: Integer;
  ahead: Boolean;
begin
  ASend := 0;
  AOwn := 0;
  if Mode <> gmVersus then Exit;
  if FlowOn then
  begin
    FlowApply(feOnPop, ACount, True, ASend, AOwn);   // the flowchart decides
    Exit;
  end;
  { the gap with the score as it is now (this pop's points count), the
    same as the flowchart sees it }
  d := Score - VsOtherScore;
  if (VsIronGap > 0) and (Abs(d) <= VsIronGap) then Exit;   // within the gap: no iron at all
  SurvivalRefill(ACount, AOwn, rbonus);
  ahead := d > VsIronGap;
  if ahead or (VRI(vrTrailerIron) = 1) then ASend := AttackIron(ACount);
  if ahead then
  begin
    { the leader's small pops: their iron to the other board, or its own }
    if VRI(vrLeaderRefill) = 1 then
    begin
      ASend += AOwn;
      AOwn := 0;
    end;
  end
  else if VRI(vrTrailerIron) <> 1 then
    AOwn := 0;   // the side behind makes no iron
end;

procedure TBeadGame.Reseed(ASeed: Cardinal);
begin
  FRng := ASeed or 1;
end;

procedure TBeadGame.EndRun(AWin: Boolean);
begin
  if State in [gsTitle, gsGameOver] then Exit;
  FEndWin := AWin;
  FEndPending := True;
  if State = gsPlaying then ApplyEnd;
end;

procedure TBeadGame.ApplyEnd;
begin
  FEndPending := False;
  SetLength(FHover, 0);
  FHoverPts := 0;
  Best := Max(Best, Score);
  State := gsGameOver;
  if FEndWin then Sound(gsndLevel);
end;

{ VS BOT: the iron sent by the other side turns random plain beads into iron }
procedure TBeadGame.ApplyIncoming;
var
  k: Integer;
begin
  k := PendingIron;
  PendingIron := 0;
  DropIron(k, False);
end;

{ ACount random plain beads become iron (sent by the other side, or the
  idle penalty) }
procedure TBeadGame.DropIron(ACount: Integer; AIdle: Boolean);
var
  cand: array of Integer;
  i, k, n, j: Integer;
begin
  SetLength(cand, 0);
  for i := 0 to High(FBoard) do
    if (FBoard[i] >= 0) and (FSpec[i] = SpNone) then
    begin
      SetLength(cand, Length(cand) + 1);
      cand[High(cand)] := i;
    end;
  n := Length(cand);
  k := 0;
  while (k < ACount) and (n > 0) do
  begin
    j := Trunc(Rand * n) mod n;
    i := cand[j];
    cand[j] := cand[n - 1];
    Dec(n);
    FSpec[i] := SpIron;
    FBoard[i] := 0;
    FFx[i].Flash := 1;
    AddFx(fxStone, i div H, i mod H, IronRGB[0], IronRGB[1], IronRGB[2]);
    Inc(k);
  end;
  if k > 0 then
  begin
    IronGained += k;
    if AIdle then
      AddPopup(W / 2, H / 2, Format('TOO SLOW!  +%d IRON', [k]), -2)
    else
    begin
      IronReceived += k;
      AddPopup(W / 2, H / 2, Format('INCOMING +%d IRON', [k]), -2);
    end;
    Sound(gsndCrash);
  end;
  if HasMoves then UpdateHover else FinishBoard;
end;

procedure TBeadGame.FlowApply(AEvent: TFlowEvent; ACount: Integer; ADry: Boolean; out ASend, AOwn: Integer);
var
  c: TFlowCtx;
  o: TFlowOut;
  ref, bon, i: Integer;
begin
  c := Default(TFlowCtx);
  c.V[fvPopSize] := ACount;
  c.V[fvMyScore] := Score;
  c.V[fvOtherScore] := VsOtherScore;
  c.V[fvGap] := Score - VsOtherScore;
  c.V[fvGapSize] := Abs(Score - VsOtherScore);
  c.V[fvMyIron] := IronCount;
  c.V[fvOtherIron] := VsOtherIron;
  if ACount > 0 then
  begin
    c.V[fvAttackIron] := AttackIron(ACount);
    SurvivalRefill(ACount, ref, bon);
    c.V[fvRefillIron] := ref;
  end;
  c.V[fvSeconds] := VsTime;
  c.V[fvMySent] := IronSent;
  c.V[fvMyReceived] := IronReceived;
  if ADry then c.V[fvRandom] := 50
  else
  begin
    FFlowRnd := FFlowRnd * 1664525 + 1013904223;
    c.V[fvRandom] := (FFlowRnd shr 16) mod 100;
  end;
  c.V[fvRuleGap] := VR[vrIronGap];
  c.V[fvRuleLeaderRefill] := VR[vrLeaderRefill];
  c.V[fvRuleTrailerIron] := VR[vrTrailerIron];
  c.V[fvRuleStallPoints] := VR[vrIdlePenalty];
  c.V[fvRuleStallIron] := VR[vrIdleIron];
  c.V[fvIdleSecs] := IdleT;
  o := Default(TFlowOut);
  IronFlow.Run(AEvent, c, o);
  ASend := Max(0, o.Send);
  AOwn := Max(0, o.Own);
  if ADry then Exit;
  if o.Points <> 0 then
  begin
    Score := Max(0, Score + o.Points);
    if o.Points < 0 then Sound(gsndInvalid);
  end;
  for i := 0 to High(o.Msgs) do AddPopup(W / 2, H / 2 - 1 - i * 0.9, o.Msgs[i], -2);
  if Assigned(FlowTrace) then
    for i := 0 to High(o.Fired) do FlowTrace(VsSide, o.Fired[i], o.FiredAmt[i]);
end;

class procedure TBeadGame.SurvivalRefill(ACount: Integer; out AIron, ABonus: Integer);
var
  k: Integer;
begin
  case ACount of
    2: AIron := SRI(srIronPair);
    3: AIron := SRI(srIronTriple);
  else
    AIron := 0;
  end;
  ABonus := 0;
  for k := srBonus1 to srBonus5 do
    if (SRI(k) > 0) and (ACount >= SRI(k)) then Inc(ABonus);
end;

function TBeadGame.IronCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FBoard) do
    if (FBoard[i] >= 0) and (FSpec[i] = SpIron) then Inc(Result);
end;

procedure TBeadGame.ShowTitle;
begin
  { a demo board behind the title panel; the last game's score goes to its best }
  Best := Max(Best, Score);
  Score := 0;
  Mode := gmClassic;
  Level := Max(1, MaxLevel);
  State := gsTitle;
  NewBoard(Min(Level, 7));
end;

function TBeadGame.Cell(x, y: Integer): Integer;
begin
  if (x < 0) or (y < 0) or (x >= W) or (y >= H) then Exit(-1);
  Result := FBoard[Idx(x, y)];
end;

function TBeadGame.Spec(x, y: Integer): Integer;
begin
  if (x < 0) or (y < 0) or (x >= W) or (y >= H) then Exit(SpNone);
  Result := FSpec[Idx(x, y)];
end;

function TBeadGame.Fx(x, y: Integer): PCellFx;
begin
  Result := @FFx[Idx(x, y)];
end;

{ does cell j belong to a group of colour c (rainbows match all colours) }
function TBeadGame.Matches(j, c: Integer): Boolean;
begin
  if (FBoard[j] < 0) or (FSpec[j] in [SpStone, SpIron]) then Exit(False);
  Result := (FSpec[j] = SpRainbow) or (FBoard[j] = c);
end;

procedure TBeadGame.FindGroup(x, y, c: Integer; var AList: array of Integer; out ACount: Integer);
var
  stack: array of Integer;
  sp, i, cx, cy: Integer;

  procedure Push(px, py: Integer);
  var
    j: Integer;
  begin
    if (px < 0) or (py < 0) or (px >= W) or (py >= H) then Exit;
    j := Idx(px, py);
    if (FMark[j] = FStamp) or not Matches(j, c) then Exit;
    FMark[j] := FStamp;
    stack[sp] := j;
    Inc(sp);
  end;

begin
  ACount := 0;
  Inc(FStamp);
  SetLength(stack, W * H);
  sp := 0;
  Push(x, y);
  while sp > 0 do
  begin
    Dec(sp);
    i := stack[sp];
    AList[ACount] := i;
    Inc(ACount);
    cx := i div H;
    cy := i mod H;
    Push(cx + 1, cy); Push(cx - 1, cy); Push(cx, cy + 1); Push(cx, cy - 1);
  end;
end;

{ everything the click at (x, y) would pop: the colour group plus the blasts
  of the bombs / lines in it (chain reactions included) }
function TBeadGame.PopSet(x, y: Integer; var AList: array of Integer; out ACount, AGroup, APts,
  ASpecials: Integer): Boolean;
var
  i, j, k, n, c, bestN, bestC, qh, bx, by, gx, gy, blast, stones: Integer;
  inSet: array of Boolean;
  dbl, sameX, sameY: Boolean;
  arr, pf: Single;

  procedure Take(px, py: Integer);
  var
    t: Integer;
  begin
    if (px < 0) or (py < 0) or (px >= W) or (py >= H) then Exit;
    t := Idx(px, py);
    if (FBoard[t] < 0) or inSet[t] or (FSpec[t] = SpIron) then Exit;   // iron survives blasts
    inSet[t] := True;
    AList[ACount] := t;
    Inc(ACount);
  end;

begin
  ACount := 0;
  AGroup := 0;
  APts := 0;
  ASpecials := 0;
  Result := False;
  if (x < 0) or (y < 0) or (x >= W) or (y >= H) then Exit;
  i := Idx(x, y);
  if (FBoard[i] < 0) or (FSpec[i] in [SpStone, SpIron]) then Exit;
  { the colour group; a rainbow takes the colour giving the biggest group }
  if FSpec[i] = SpRainbow then
  begin
    bestN := 0;
    bestC := -1;
    for c := 0 to Colours - 1 do
    begin
      FindGroup(x, y, c, AList, n);
      if n > bestN then
      begin
        bestN := n;
        bestC := c;
      end;
    end;
    if bestC < 0 then Exit;
    FindGroup(x, y, bestC, AList, n);
  end
  else
    FindGroup(x, y, FBoard[i], AList, n);
  if n < 2 then
  begin
    { a lone bomb or line can be set off on its own }
    if not (FSpec[i] in [SpBomb, SpLine]) then Exit;
    AList[0] := i;
    n := 1;
  end
  else
    AGroup := n;
  ACount := n;
  SetLength(inSet, W * H);
  for k := 0 to n - 1 do inSet[AList[k]] := True;
  { arrangement bonuses of the colour group (uBeadRules) }
  arr := 0;
  if AGroup >= 2 then
  begin
    gx := AList[0] div H;
    gy := AList[0] mod H;
    sameX := True;
    sameY := True;
    for k := 1 to n - 1 do
    begin
      if AList[k] div H <> gx then sameX := False;
      if AList[k] mod H <> gy then sameY := False;
    end;
    if (sameX or sameY) and (n >= SRI(srStraightMin)) then arr += SR[srStraightBonus] * n;
    if SR[srBlockBonus] > 0 then
      for k := 0 to n - 1 do
      begin
        bx := AList[k] div H;
        by := AList[k] mod H;
        if (bx + 1 < W) and (by + 1 < H) and inSet[Idx(bx + 1, by)] and inSet[Idx(bx, by + 1)] and
          inSet[Idx(bx + 1, by + 1)] then arr += SR[srBlockBonus];
      end;
    if n >= SRI(srBigSize) then arr += SR[srBigBonus];
  end;
  { blasts (the list grows while it is scanned: chain reactions) }
  qh := 0;
  while qh < ACount do
  begin
    j := AList[qh];
    Inc(qh);
    bx := j div H;
    by := j mod H;
    case FSpec[j] of
      SpBomb:
        begin
          Inc(ASpecials);
          for gx := bx - 1 to bx + 1 do
            for gy := by - 1 to by + 1 do Take(gx, gy);
        end;
      SpLine:
        begin
          Inc(ASpecials);
          for gx := 0 to W - 1 do Take(gx, by);
        end;
    end;
  end;
  { points }
  blast := ACount - n;
  stones := 0;
  dbl := False;
  for k := 0 to ACount - 1 do
  begin
    if FSpec[AList[k]] = SpStone then Inc(stones);
    if FSpec[AList[k]] = SpDouble then dbl := True;
  end;
  arr += Max(0, ASpecials - 1) * SR[srMultiBlast];
  pf := n * (n - 1) * SR[srPerPair] + n * SR[srPerBead] + (blast - stones) * SR[srBlastBead] +
    stones * SR[srStoneBead] + arr;
  if dbl then pf := pf * SR[srDoubleMult];
  APts := Round(pf);
  Result := True;
end;

function TBeadGame.HasMoves: Boolean;
var
  x, y, i, c: Integer;

  function Joins(px, py: Integer): Boolean;
  var
    j: Integer;
  begin
    if (px < 0) or (py < 0) or (px >= W) or (py >= H) then Exit(False);
    j := Idx(px, py);
    if (FBoard[j] < 0) or (FSpec[j] in [SpStone, SpIron]) then Exit(False);
    Result := (FSpec[j] = SpRainbow) or (FSpec[i] = SpRainbow) or (FBoard[j] = c);
  end;

begin
  Moves := 0;
  Result := False;
  for x := 0 to W - 1 do
    for y := 0 to H - 1 do
    begin
      i := Idx(x, y);
      c := FBoard[i];
      if (c < 0) or (FSpec[i] in [SpStone, SpIron]) then Continue;
      if (FSpec[i] in [SpBomb, SpLine]) or Joins(x + 1, y) or Joins(x, y + 1) then
        Exit(True);
    end;
end;

function TBeadGame.BeadsLeft: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FBoard) do
    if (FBoard[i] >= 0) and not (FSpec[i] in [SpStone, SpIron]) then Inc(Result);
end;

function TBeadGame.ChainMult: Single;
begin
  Result := 1 + SR[srChainStep] * (Min(Max(Chain, 1), MaxChainMult) - 1);
end;

function TBeadGame.SpecialsOnBoard: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FBoard) do
    if (FBoard[i] >= 0) and (FSpec[i] <> SpNone) then Result := Result or (1 shl FSpec[i]);
end;

function TBeadGame.GroupSize(x, y: Integer): Integer;
var
  list: array of Integer;
  g, p, s: Integer;
begin
  Result := 0;
  if Cell(x, y) < 0 then Exit;
  SetLength(list, W * H);
  if not PopSet(x, y, list, Result, g, p, s) then Result := 0;
end;

function TBeadGame.HoverCount: Integer;
begin
  Result := Length(FHover);
end;

function TBeadGame.HoverPoints: Integer;
begin
  Result := FHoverPts;
end;

function TBeadGame.Animating: Boolean;
begin
  Result := State in [gsPopping, gsSettling];
end;

procedure TBeadGame.SetMouseCell(x, y: Integer);
begin
  if (x = FMouseX) and (y = FMouseY) then Exit;
  FMouseX := x;
  FMouseY := y;
  UpdateHover;
end;

procedure TBeadGame.UpdateHover;
var
  list: array of Integer;
  n, g, s: Integer;
begin
  SetLength(FHover, 0);
  FHoverPts := 0;
  if State <> gsPlaying then Exit;
  if Cell(FMouseX, FMouseY) < 0 then Exit;
  SetLength(list, W * H);
  if not PopSet(FMouseX, FMouseY, list, n, g, FHoverPts, s) then Exit;
  FHoverGroup := g;
  FHover := Copy(list, 0, n);
end;

procedure TBeadGame.Click;
var
  i, j, n, pts, grp, specs, sx, sy, rainbow, atk: Integer;
  snap: TBoardSnap;
  list: array of Integer;
  r, g, b: Byte;
  bonusT, mult: Single;
begin
  if State <> gsPlaying then Exit;
  SetLength(list, W * H);
  if not PopSet(FMouseX, FMouseY, list, n, grp, pts, specs) then
  begin
    if Cell(FMouseX, FMouseY) >= 0 then Sound(gsndInvalid);
    Exit;
  end;
  { undo snapshot }
  if Mode = gmClassic then
  begin
    snap.Cells := Copy(FBoard);
    snap.Spec := Copy(FSpec);
    snap.Score := Score;
    snap.LevelScore := LevelScore;
    SetLength(FUndo, Length(FUndo) + 1);
    FUndo[High(FUndo)] := snap;
  end;
  FPopped := Copy(list, 0, n);
  SetLength(FHover, 0);
  FHoverPts := 0;
  IdleT := 0;

  { time attack: chain multiplier and extra time }
  if Mode = gmTime then
  begin
    if ChainTimer > 0 then Inc(Chain) else Chain := 1;
    MaxChain := Max(MaxChain, Chain);
    mult := ChainMult;
    pts := Round(pts * mult);
    { extra time: big groups and blasts }
    if grp >= SRI(srTime3Size) then bonusT := 3
    else if grp >= SRI(srTime2Size) then bonusT := 2
    else if grp >= SRI(srTime1Size) then bonusT := 1
    else bonusT := 0;
    bonusT += specs * SR[srTimePerSpecial];
    if bonusT > 0 then
    begin
      TimeLeft += bonusT;
      AddFx(fxTime, FMouseX, FMouseY, 120, 255, 160, Round(bonusT * 10));
    end;
  end;
  Score += pts;
  LevelScore += pts;

  { statistics }
  Inc(Pops);
  MaxGroup := Max(MaxGroup, grp);
  LastGroup := grp;
  Inc(PopCount);
  MaxSpecialsInMove := Max(MaxSpecialsInMove, specs);
  rainbow := 0;
  sx := 0;
  sy := 0;
  for i := 0 to n - 1 do
  begin
    j := FPopped[i];
    FFx[j].Flash := 1;
    sx += j div H;
    sy += j mod H;
    case FSpec[j] of
      SpBomb:
        begin
          Inc(BombsUsed);
          AddFx(fxBomb, j div H, j mod H, 255, 170, 60);
        end;
      SpLine:
        begin
          Inc(LinesUsed);
          AddFx(fxLine, j div H, j mod H, 120, 230, 255, W);
        end;
      SpStone:
        begin
          Inc(StonesBroken);
          AddFx(fxStone, j div H, j mod H, StoneRGB[0], StoneRGB[1], StoneRGB[2]);
        end;
      SpRainbow: Inc(rainbow);
    end;
    CellRGBBytes(j, r, g, b);
    AddFx(fxPop, j div H, j mod H, r, g, b, i);
  end;
  if (rainbow > 0) and (grp >= 2) then Inc(RainbowGroups);
  if grp >= 10 then
  begin
    CellRGBBytes(FPopped[0], r, g, b);
    AddFx(fxBigPop, sx / n, sy / n, r, g, b, grp);
  end;
  if Refills then
  begin
    SurvivalRefill(n, FRefillIron, FRefillBonus);
    MaxPopCount := Max(MaxPopCount, n);
  end;
  if Mode = gmVersus then
  begin
    { the score gap decides: within VsIronGap no iron, the leader's iron
      lands on the other board, the side behind makes none (uBeadRules) }
    if FlowOn then FlowApply(feOnPop, n, False, atk, FRefillIron)
    else MoveIron(n, atk, FRefillIron);
    if atk > 0 then
    begin
      OutIron += atk;
      IronSent += atk;
      MaxAttack := Max(MaxAttack, atk);
      AddPopup(sx / n, sy / n + 1.2, Format('ATTACK  %d IRON >>', [atk]), -2);
    end;
  end;
  if (Mode = gmTime) and (Chain >= 2) then
    AddPopup(sx / n, sy / n, Format('+%d  CHAIN x%d', [pts, Chain]), FBoard[FPopped[0]])
  else if specs > 0 then
    AddPopup(sx / n, sy / n, Format('+%d  BLAST!', [pts]), -1)
  else
    AddPopup(sx / n, sy / n, '+' + IntToStr(pts), FBoard[FPopped[0]]);

  { a big group leaves a special bead behind (survival: bonus beads in the refill) }
  FReward := SpNone;
  if Refills then
  else if (SRI(srRewardRainbow) > 0) and (grp >= SRI(srRewardRainbow)) then FReward := SpRainbow
  else if (SRI(srRewardLine) > 0) and (grp >= SRI(srRewardLine)) then FReward := SpLine
  else if (SRI(srRewardBomb) > 0) and (grp >= SRI(srRewardBomb)) then FReward := SpBomb;
  FRewardX := sx / n;
  FRewardY := sy / n;

  FTimer := PopTime;
  State := gsPopping;
  Sound(gsndPop, Min(n, 30));
  if specs > 0 then Sound(gsndCrash);
end;

procedure TBeadGame.RemovePopped;
var
  i, x, y, nx, ny, src, bestN: Integer;
  oldBoard, oldSpec: array of ShortInt;
  oldFx: array of TCellFx;
  colX: array of Integer;   // new column of each old column (-1 = empty column)
  d, bestD: Single;
begin
  for i := 0 to High(FPopped) do
  begin
    FBoard[FPopped[i]] := -1;
    FSpec[FPopped[i]] := SpNone;
    FillChar(FFx[FPopped[i]], SizeOf(TCellFx), 0);
  end;
  SetLength(FPopped, 0);
  if Refills then
  begin
    Refill;
    Exit;
  end;
  oldBoard := Copy(FBoard);
  oldSpec := Copy(FSpec);
  oldFx := Copy(FFx);
  { columns that still hold beads slide to the left }
  SetLength(colX, W);
  nx := 0;
  for x := 0 to W - 1 do
  begin
    colX[x] := -1;
    for y := 0 to H - 1 do
      if oldBoard[x * H + y] >= 0 then
      begin
        colX[x] := nx;
        Inc(nx);
        Break;
      end;
  end;
  for i := 0 to High(FBoard) do
  begin
    FBoard[i] := -1;
    FSpec[i] := SpNone;
    FillChar(FFx[i], SizeOf(TCellFx), 0);
  end;
  for x := 0 to W - 1 do
  begin
    if colX[x] < 0 then Continue;
    { beads fall to the bottom of their column, keeping their order }
    ny := H - 1;
    for y := H - 1 downto 0 do
    begin
      src := x * H + y;
      if oldBoard[src] < 0 then Continue;
      i := Idx(colX[x], ny);
      FBoard[i] := oldBoard[src];
      FSpec[i] := oldSpec[src];
      FFx[i] := oldFx[src];
      FFx[i].Presence := 1;
      FFx[i].Flash := 0;
      FFx[i].OffY := oldFx[src].OffY + (ny - y);
      FFx[i].OffX := oldFx[src].OffX + (x - colX[x]);
      Dec(ny);
    end;
  end;
  { the reward special: the plain bead that lands nearest the group's centre }
  if FReward <> SpNone then
  begin
    bestN := -1;
    bestD := 1e9;
    for i := 0 to High(FBoard) do
      if (FBoard[i] >= 0) and (FSpec[i] = SpNone) then
      begin
        d := Sqr(i div H - FRewardX) + Sqr(i mod H - FRewardY);
        if d < bestD then
        begin
          bestD := d;
          bestN := i;
        end;
      end;
    if bestN >= 0 then
    begin
      FSpec[bestN] := FReward;
      if FReward = SpRainbow then FBoard[bestN] := 0;
      FFx[bestN].Flash := 1;
      AddFx(fxSpawn, bestN div H, bestN mod H, 255, 255, 255);
      AddPopup(bestN div H, bestN mod H, SpecialName(FReward) + '!', -1);
      Sound(gsndPower);
    end;
    FReward := SpNone;
  end;
end;

{ survival: the beads of every column fall down (columns never slide) and new
  beads drop in from above into the empty top cells; FRefillIron of them are
  iron, FRefillBonus carry a bonus special }
procedure TBeadGame.Refill;
var
  x, y, ny, src, i, k, n, kind: Integer;
  oldBoard, oldSpec: array of ShortInt;
  oldFx: array of TCellFx;
  fresh: array of Integer;
  r: Single;
begin
  oldBoard := Copy(FBoard);
  oldSpec := Copy(FSpec);
  oldFx := Copy(FFx);
  SetLength(fresh, 0);
  for x := 0 to W - 1 do
  begin
    ny := H - 1;
    for y := H - 1 downto 0 do
    begin
      src := Idx(x, y);
      if oldBoard[src] < 0 then Continue;
      i := Idx(x, ny);
      FBoard[i] := oldBoard[src];
      FSpec[i] := oldSpec[src];
      FFx[i] := oldFx[src];
      FFx[i].Presence := 1;
      FFx[i].Flash := 0;
      FFx[i].OffY := oldFx[src].OffY + (ny - y);
      Dec(ny);
    end;
    { ny + 1 empty cells on top: new beads fall in as a block from above }
    for y := ny downto 0 do
    begin
      i := Idx(x, y);
      FBoard[i] := Trunc(Rand * Colours) mod Colours;
      FSpec[i] := SpNone;
      FillChar(FFx[i], SizeOf(TCellFx), 0);
      FFx[i].Presence := 1;
      FFx[i].OffY := ny + 1.6 + x * 0.04;
      SetLength(fresh, Length(fresh) + 1);
      fresh[High(fresh)] := i;
    end;
  end;
  { iron first, then the bonus beads, on random new cells }
  n := Length(fresh);
  for k := 1 to FRefillIron + FRefillBonus do
  begin
    if n = 0 then Break;
    i := Trunc(Rand * n) mod n;
    src := fresh[i];
    fresh[i] := fresh[n - 1];
    Dec(n);
    if k <= FRefillIron then
    begin
      FSpec[src] := SpIron;
      FBoard[src] := 0;
    end
    else
    begin
      r := Rand;
      if r < 0.3 then kind := SpBomb
      else if r < 0.55 then kind := SpLine
      else if r < 0.75 then kind := SpDouble
      else kind := SpRainbow;
      FSpec[src] := kind;
      if kind = SpRainbow then FBoard[src] := 0;
      FFx[src].Flash := 1;
    end;
  end;
  if FRefillIron > 0 then
  begin
    AddPopup(W / 2, 1, Format('+%d IRON', [FRefillIron]), -2);
    AddFx(fxIron, W / 2, 0, IronRGB[0], IronRGB[1], IronRGB[2], FRefillIron);
    Sound(gsndCrash);
  end;
  if FRefillBonus > 0 then
  begin
    AddPopup(W / 2, 2, Format('+%d BONUS', [FRefillBonus]), -1);
    AddFx(fxSpawn, W / 2, 0, 255, 255, 255);
    Sound(gsndPower);
  end;
  IronGained += FRefillIron;
  BonusGained += FRefillBonus;
  FRefillIron := 0;
  FRefillBonus := 0;
end;

procedure TBeadGame.FinishBoard;
var
  left: Integer;
begin
  left := BeadsLeft;
  if Refills then
  begin
    { no pair left: the run is over }
    Stars := 0;
    SetLength(FHover, 0);
    Best := Max(Best, Score);
    State := gsGameOver;
    Sound(gsndGameOver);
    Exit;
  end;
  if Mode = gmTime then
  begin
    { a fresh board drops in; the clock keeps running }
    if left = 0 then
    begin
      Bonus := Round(SR[srBoardClear]);
      Inc(BoardsCleared);
      AddFx(fxClear, W / 2, H / 2, 255, 255, 255);
    end
    else
    begin
      Bonus := Round(Max(0, SRI(srBoardLeftBase) - left) * SR[srBoardLeftPts]);
      AddFx(fxLevel, W / 2, H / 2, 255, 255, 255);
    end;
    Score += Bonus;
    Inc(Boards);
    Sound(gsndLevel);
    NewBoard(3);
    if Bonus > 0 then AddPopup(W / 2, H / 2, Format('BOARD BONUS +%d', [Bonus]), -1);
    State := gsSettling;
    Best := Max(Best, Score);
    Exit;
  end;
  if left <= Goal then
  begin
    Bonus := Round((Goal - left) * SR[srGoalBead]);
    if left = 0 then
    begin
      Bonus += Round(SR[srClearBonus]);
      Inc(BoardsCleared);
    end;
    if left <= Floor(Goal * SR[srStar3]) then Stars := 3
    else if left <= Floor(Goal * SR[srStar2]) then Stars := 2
    else Stars := 1;
    Score += Bonus;
    LevelScore += Bonus;
    MaxLevel := Max(MaxLevel, Level + 1);
    Inc(LevelsPassed);
    if not UsedUndo then Inc(NoUndoClears);
    State := gsLevelDone;
    if left = 0 then AddFx(fxClear, W / 2, H / 2, 255, 255, 255)
    else AddFx(fxLevel, W / 2, H / 2, 255, 255, 255, Stars);
    Sound(gsndLevel);
  end
  else
  begin
    Stars := 0;
    State := gsGameOver;
    Sound(gsndGameOver);
  end;
  Best := Max(Best, Score);
end;

procedure TBeadGame.Undo;
var
  s: TBoardSnap;
  i: Integer;
begin
  if (Mode <> gmClassic) or not (State in [gsPlaying, gsGameOver]) or (UndoLeft <= 0) or
    (Length(FUndo) = 0) then Exit;
  s := FUndo[High(FUndo)];
  SetLength(FUndo, Length(FUndo) - 1);
  Dec(UndoLeft);
  UsedUndo := True;
  FBoard := Copy(s.Cells);
  FSpec := Copy(s.Spec);
  Score := s.Score;
  LevelScore := s.LevelScore;
  for i := 0 to High(FFx) do
  begin
    FillChar(FFx[i], SizeOf(TCellFx), 0);
    if FBoard[i] >= 0 then
    begin
      FFx[i].Presence := 1;
      FFx[i].Flash := 0.6;  // restored beads glow briefly
    end;
  end;
  SetLength(FPopped, 0);
  State := gsPlaying;
  UpdateHover;
  Sound(gsndUndo);
end;

procedure TBeadGame.Update(dt: Single);
var
  i, j, fs, fo: Integer;
  moving, landed: Boolean;
  target: Single;
  hov: array of Boolean;
begin
  dt := Min(dt, 0.05);

  { time attack clock }
  if (Mode = gmTime) and (State in [gsPlaying, gsPopping, gsSettling]) then
  begin
    TimeLeft -= dt;
    if State = gsPlaying then ChainTimer -= dt;
    if TimeLeft <= 0 then
    begin
      TimeLeft := 0;
      SetLength(FHover, 0);
      Best := Max(Best, Score);
      State := gsGameOver;
      Sound(gsndGameOver);
    end;
  end;

  { VS BOT: no stalling - an idle side gets iron }
  if (Mode = gmVersus) and (State = gsPlaying) and not FEndPending and (VsResult = 0) then
  begin
    IdleT += dt;
    VsTime += dt;
    { the flowchart: every second, stalling (uIronFlow) }
    if FlowOn then
    begin
      FTickT += dt;
      if FTickT >= 1 then
      begin
        FTickT -= 1;
        FlowApply(feEverySecond, 0, False, fs, fo);
        if fs > 0 then
        begin
          OutIron += fs;
          IronSent += fs;
        end;
        if fo > 0 then DropIron(fo, False);
      end;
    end;
    if (VsIdleSecs > 0) and (IdleT >= VsIdleSecs) and FlowOn then
    begin
      IdleT := 0;
      FlowApply(feOnStall, 0, False, fs, fo);
      if fs > 0 then
      begin
        OutIron += fs;
        IronSent += fs;
      end;
      if fo > 0 then DropIron(fo, True);
    end
    else if (VsIdleSecs > 0) and (IdleT >= VsIdleSecs) then
    begin
      { stalling costs points and / or iron on the own board (uBeadRules) }
      IdleT := 0;
      if VsIdlePenalty > 0 then
      begin
        Score := Max(0, Score - VsIdlePenalty);
        AddPopup(W / 2, H / 2 - 1, Format('TOO SLOW!  -%d', [VsIdlePenalty]), -2);
        Sound(gsndInvalid);
      end;
      if VRI(vrIdleIron) > 0 then DropIron(VRI(vrIdleIron), True);
    end;
  end;

  { VS BOT: the end of the match, iron from the other side }
  if State = gsPlaying then
  begin
    if FEndPending then ApplyEnd
    else if PendingIron > 0 then ApplyIncoming;
  end;

  { hover glow follows the hovered move }
  SetLength(hov, Length(FFx));
  for i := 0 to High(FHover) do hov[FHover[i]] := True;
  for i := 0 to High(FFx) do
  begin
    if hov[i] then target := 1 else target := 0;
    FFx[i].Hover += (target - FFx[i].Hover) * Min(1, dt * 14);
    if (State <> gsPopping) and (FFx[i].Flash > 0) then
      FFx[i].Flash := Max(0, FFx[i].Flash - dt * 2.5);
  end;

  case State of
    gsPopping:
      begin
        FTimer -= dt;
        for i := 0 to High(FPopped) do
        begin
          j := FPopped[i];
          FFx[j].Presence := Max(0, FTimer / PopTime);
          FFx[j].Flash := 1;
        end;
        if FTimer <= 0 then
        begin
          RemovePopped;
          State := gsSettling;
        end;
      end;
    gsSettling, gsTitle:
      begin
        moving := False;
        landed := False;
        for i := 0 to High(FFx) do
          with FFx[i] do
          begin
            if OffY > 0 then
            begin
              VelY += Gravity * dt;
              OffY -= VelY * dt;
              if OffY <= 0 then
              begin
                OffY := 0;
                if VelY > 6 then landed := True;
                VelY := 0;
              end
              else
                moving := True;
            end;
            if OffX > 0 then
            begin
              OffX := Max(0, OffX - SlideSpeed * dt);
              if OffX > 0 then moving := True;
            end;
          end;
        if landed and (State = gsSettling) then Sound(gsndLand);
        if (State = gsSettling) and not moving then
        begin
          State := gsPlaying;
          ChainTimer := ChainWindow;
          if FEndPending then
            ApplyEnd
          else if PendingIron > 0 then
            ApplyIncoming
          else if HasMoves then
            UpdateHover
          else
            FinishBoard;
        end;
      end;
  end;

  { floating score popups }
  j := 0;
  for i := 0 to High(Popups) do
  begin
    Popups[i].Age += dt;
    if Popups[i].Age < PopupFx.Life then
    begin
      Popups[j] := Popups[i];
      Inc(j);
    end;
  end;
  SetLength(Popups, j);
end;

end.
