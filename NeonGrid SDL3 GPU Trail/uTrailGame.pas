unit uTrailGame;

{ Neon Trail - rules of the light-trail snake on the neon dot grid.

  Steer a trail of glowing beads cell by cell. Eating a sparkle adds its
  colour to the trail (the body is a chain of the beads collected) and makes
  it longer and a bit faster. Quick eating builds a combo. Golden beads give
  big points for a few seconds.
  Power-ups: SLOW-MO, GHOST (pass through yourself), MAGNET (nearby sparkles
  drift towards the head), DOUBLE (x2 points), SHRINK (the trail loses half
  its length) and SHIELD (absorbs one crash).
  From level 3, red hazard drones wander the board.
  Hitting a wall, the edge, a drone or the own trail costs a life; the level
  progress is kept. Eat the level's goal number of sparkles to go on.

  Board coordinates: x = column (0 = left), y = row (0 = top). The trail and
  the drones are drawn between cells (smooth movement): View() interpolates
  between the previous and the current cell.

  The game reports effects (Fx: particle bursts) and keeps per-game
  statistics for the achievements. Demo mode: an AI (shortest path to the
  nearest sparkle, otherwise the move with the most free room) plays behind
  the title menu; AutoPilot uses the same AI with the normal rules. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, uGameFx;

const
  BoardW = 18;
  BoardH = 26;
  MaxColours = 6;
  StartLength = 4;
  ComboWindow = 3.0;

var
  { colours: defaults here, the values come from NeonTrail.visuals }
  BeadRGB: array[0..MaxColours - 1, 0..2] of Byte = (
    (245, 150, 35), (35, 215, 240), (230, 40, 145),
    (150, 230, 55), (150, 75, 240), (245, 55, 55));

type
  TGameState = (gsTitle, gsReady, gsPlaying, gsCrashed, gsLevelDone, gsGameOver);
  TGameSound = (gsndPop, gsndInvalid, gsndLand, gsndUndo, gsndLevel, gsndGameOver, gsndStart,
    gsndMenuMove, gsndMenuSelect, gsndCrash, gsndGold, gsndPower);
  TSoundEvent = procedure(ASound: TGameSound; AParam: Integer) of object;
  TPower = (pwNone, pwSlow, pwGhost, pwMagnet, pwDouble, pwShrink, pwShield);
  TPowers = set of TPower;
  TItemKind = (ikFood, ikGold, ikPower);
  TFxKind = (fxEat, fxCombo, fxGold, fxPower, fxCrash, fxShield, fxShrink, fxLevel);

  TItem = record
    Kind: TItemKind;
    X, Y, Colour: Integer;
    Power: TPower;
    Life, Age: Single;      // Life < 0 = never expires
  end;

  TSeg = record
    X, Y, PX, PY, Colour: Integer;
  end;

  THazard = record
    X, Y, PX, PY, DX, DY: Integer;
  end;

  TPopup = record
    X, Y, Age: Single;
    Text: string;
    R, G, B: Byte;
  end;

  { a particle effect request for the program (board cell coordinates) }
  TFxEvent = record
    Kind: TFxKind;
    X, Y: Single;
    R, G, B: Byte;
    N: Integer;             // e.g. segment index for a staggered crash
  end;

  { what the renderer draws for one board cell }
  TCellView = record
    R, G, B, Presence, Hover, Flash, OffX, OffY: Single;
  end;

  TTrailGame = class
  private
    FWall: array of Boolean;
    FDirQ: array[0..2] of TPoint;
    FDirN: Integer;
    FGrow: Integer;
    FRng: Cardinal;
    FColourIdx: Integer;
    FHazT: Single;
    function Rand: Single;
    function Idx(x, y: Integer): Integer; inline;
    procedure BuildWalls;
    procedure Respawn;
    procedure SpawnItem(AKind: TItemKind);
    procedure SpawnHazards;
    procedure MoveHazards;
    function HazardAt(x, y: Integer): Integer;
    function ItemAt(x, y: Integer): Integer;
    function BodyAt(x, y: Integer; AIgnoreTail: Boolean): Boolean;
    function IsFree(x, y: Integer): Boolean;
    function Blocked(x, y: Integer): Boolean;
    procedure StepSnake;
    procedure Eat(AIndex: Integer);
    procedure Crash;
    function UseShield(x, y: Integer): Boolean;
    procedure AddPopup(x, y: Single; const AText: string; R, G, B: Byte);
    procedure AddFx(AKind: TFxKind; x, y: Single; R, G, B: Byte; AN: Integer = 0);
    procedure Sound(S: TGameSound; AParam: Integer = 0);
    function AIDir: TPoint;
    function SafeDir: TPoint;
    function FreeRoom(x, y: Integer): Integer;
  public
    State: TGameState;
    Level, Score, LevelStartScore, Best, MaxLevel, Lives, Eaten, Goal, Combo, Bonus: Integer;
    ComboTimer, StepT, Speed, PowerTime, CrashFlash, Clock, HazStep: Single;
    Dir: TPoint;
    Snake: array of TSeg;     // 0 = head
    Items: array of TItem;
    Hazards: array of THazard;
    Power: TPower;            // the timed power (slow, ghost, magnet, double)
    Shield: Boolean;
    Boost, Demo, AutoPilot: Boolean;
    Popups: array of TPopup;
    Fx: array of TFxEvent;    // consumed (cleared) by the program
    OnSound: TSoundEvent;
    { statistics for the achievements (per game, i.e. since PLAY) }
    GameSparks, GameGold, MaxCombo, MaxLength, GhostPasses, LevelCrashes,
    FlawlessClears, ShieldSaves: Integer;
    PowersGot: TPowers;
    BoostTime: Single;
    constructor Create;
    procedure ShowTitle;
    procedure StartLevel(ALevel: Integer; AKeepScore: Boolean);
    procedure Revive;         // continue after a crash
    procedure Turn(dx, dy: Integer);
    procedure Update(dt: Single);
    function Wall(x, y: Integer): Boolean;
    function View(x, y: Integer): TCellView;
    function W: Integer;
    function H: Integer;
  end;

function PowerName(P: TPower): string;
procedure PowerRGB(P: TPower; out R, G, B: Byte);

var
  { power-up colours (defaults; the values come from NeonTrail.visuals) }
  PowerCol: array[TPower] of array[0..2] of Byte = ((60, 255, 225), (110, 175, 255), (215, 210, 255),
    (255, 110, 25), (255, 90, 210), (120, 255, 140), (60, 255, 225));

implementation

function PowerName(P: TPower): string;
begin
  case P of
    pwSlow: Result := 'SLOW-MO';
    pwGhost: Result := 'GHOST';
    pwMagnet: Result := 'MAGNET';
    pwDouble: Result := 'DOUBLE';
    pwShrink: Result := 'SHRINK';
    pwShield: Result := 'SHIELD';
  else
    Result := '';
  end;
end;

procedure PowerRGB(P: TPower; out R, G, B: Byte);
begin
  R := PowerCol[P, 0];
  G := PowerCol[P, 1];
  B := PowerCol[P, 2];
end;

{ TTrailGame }

constructor TTrailGame.Create;
begin
  inherited Create;
  FRng := Cardinal(GetTickCount64) or 1;
  MaxLevel := 1;
  Lives := 3;
  SetLength(FWall, BoardW * BoardH);
  ShowTitle;
end;

function TTrailGame.W: Integer;
begin
  Result := BoardW;
end;

function TTrailGame.H: Integer;
begin
  Result := BoardH;
end;

function TTrailGame.Rand: Single;
begin
  FRng := FRng xor (FRng shl 13);
  FRng := FRng xor (FRng shr 17);
  FRng := FRng xor (FRng shl 5);
  Result := (FRng and $FFFFFF) / 16777216;
end;

function TTrailGame.Idx(x, y: Integer): Integer;
begin
  Result := y * BoardW + x;
end;

procedure TTrailGame.Sound(S: TGameSound; AParam: Integer);
begin
  if Assigned(OnSound) and not Demo then OnSound(S, AParam);
end;

procedure TTrailGame.AddFx(AKind: TFxKind; x, y: Single; R, G, B: Byte; AN: Integer);
var
  n: Integer;
begin
  n := Length(Fx);
  if n > 400 then Exit;
  SetLength(Fx, n + 1);
  Fx[n].Kind := AKind;
  Fx[n].X := x;
  Fx[n].Y := y;
  Fx[n].R := R;
  Fx[n].G := G;
  Fx[n].B := B;
  Fx[n].N := AN;
end;

function TTrailGame.Wall(x, y: Integer): Boolean;
begin
  if (x < 0) or (y < 0) or (x >= BoardW) or (y >= BoardH) then Exit(True);
  Result := FWall[Idx(x, y)];
end;

{ wall patterns: one more idea per level, random pillars from level 6 }
procedure TTrailGame.BuildWalls;
var
  x, y, i, n, px, py, cx, cy: Integer;
  r: Cardinal;

  procedure Put(ax, ay: Integer);
  begin
    if (ax >= 0) and (ay >= 0) and (ax < BoardW) and (ay < BoardH) then FWall[Idx(ax, ay)] := True;
  end;

begin
  FillChar(FWall[0], Length(FWall) * SizeOf(Boolean), 0);
  cx := BoardW div 2;
  cy := BoardH div 2;
  case Level of
    1: ;
    2:
      for x := 4 to BoardW - 5 do
      begin
        Put(x, BoardH div 3);
        Put(x, 2 * BoardH div 3);
      end;
    3:
      for y := 5 to BoardH - 6 do
      begin
        Put(BoardW div 3, y);
        Put(2 * BoardW div 3, y);
      end;
    4:
      begin
        for x := 2 to BoardW - 3 do
          if Abs(x - cx) > 1 then Put(x, cy);
        for y := 4 to BoardH - 5 do
          if Abs(y - cy) > 1 then Put(cx, y);
      end;
    5:
      begin
        for x := 3 to BoardW - 4 do
          if Abs(x - cx) > 1 then
          begin
            Put(x, 4);
            Put(x, BoardH - 5);
          end;
        for y := 4 to BoardH - 5 do
          if Abs(y - cy) > 1 then
          begin
            Put(3, y);
            Put(BoardW - 4, y);
          end;
      end;
  else
    begin
      { seeded random 2x2 pillars }
      r := Cardinal(Level) * 2654435761;
      n := Min(18, 5 + Level);
      for i := 1 to n do
      begin
        r := r xor (r shl 13); r := r xor (r shr 17); r := r xor (r shl 5);
        px := 1 + Integer(r mod Cardinal(BoardW - 3));
        r := r xor (r shl 13); r := r xor (r shr 17); r := r xor (r shl 5);
        py := 1 + Integer(r mod Cardinal(BoardH - 3));
        Put(px, py); Put(px + 1, py); Put(px, py + 1); Put(px + 1, py + 1);
      end;
    end;
  end;
  { keep the start lane free }
  for y := BoardH - 9 to BoardH - 1 do
    for x := cx - 1 to cx + 1 do
      if (x >= 0) and (y >= 0) then FWall[Idx(x, y)] := False;
end;

procedure TTrailGame.Respawn;
var
  i: Integer;
begin
  SetLength(Snake, StartLength);
  for i := 0 to StartLength - 1 do
  begin
    Snake[i].X := BoardW div 2;
    Snake[i].Y := Min(BoardH - 1, BoardH - 4 + i);
    Snake[i].PX := Snake[i].X;
    Snake[i].PY := Snake[i].Y;
    Snake[i].Colour := (FColourIdx + i) mod MaxColours;
  end;
  Dir := Point(0, -1);
  FDirN := 0;
  FGrow := 0;
  StepT := 0;
  Power := pwNone;
  PowerTime := 0;
  Combo := 0;
  ComboTimer := 0;
  Boost := False;
  SetLength(Items, 0);
  SpawnItem(ikFood);
  SpawnHazards;
  if Demo then State := gsPlaying else State := gsReady;
end;

procedure TTrailGame.ShowTitle;
begin
  Demo := True;
  AutoPilot := False;
  Level := Max(1, Min(MaxLevel, 5));
  Lives := 3;
  Score := 0;
  Eaten := 0;
  Goal := 999;
  Shield := False;
  BuildWalls;
  Respawn;
  SetLength(Popups, 0);
  State := gsTitle;
end;

procedure TTrailGame.StartLevel(ALevel: Integer; AKeepScore: Boolean);
begin
  Demo := False;
  Level := Max(1, ALevel);
  if not AKeepScore then
  begin
    { a new game }
    Score := 0;
    Lives := 3;
    Shield := False;
    GameSparks := 0;
    GameGold := 0;
    MaxCombo := 0;
    MaxLength := StartLength;
    GhostPasses := 0;
    FlawlessClears := 0;
    ShieldSaves := 0;
    PowersGot := [];
  end;
  if Lives <= 0 then Lives := 3;   // retry after game over
  LevelStartScore := Score;
  LevelCrashes := 0;
  BoostTime := 0;
  Eaten := 0;
  Goal := 8 + 2 * Level;
  Bonus := 0;
  MaxLevel := Max(MaxLevel, Level);
  FColourIdx := Trunc(Rand * MaxColours);
  BuildWalls;
  Respawn;
  SetLength(Popups, 0);
  Sound(gsndStart);
end;

procedure TTrailGame.Revive;
begin
  if State <> gsCrashed then Exit;
  Respawn;
end;

function TTrailGame.ItemAt(x, y: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Items) do
    if (Items[i].X = x) and (Items[i].Y = y) then Exit(i);
  Result := -1;
end;

function TTrailGame.HazardAt(x, y: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Hazards) do
    if (Hazards[i].X = x) and (Hazards[i].Y = y) then Exit(i);
  Result := -1;
end;

function TTrailGame.BodyAt(x, y: Integer; AIgnoreTail: Boolean): Boolean;
var
  i, last: Integer;
begin
  last := High(Snake);
  if AIgnoreTail and (FGrow = 0) then Dec(last);   // the tail moves away this step
  for i := 0 to last do
    if (Snake[i].X = x) and (Snake[i].Y = y) then Exit(True);
  Result := False;
end;

function TTrailGame.IsFree(x, y: Integer): Boolean;
begin
  Result := not Wall(x, y) and not BodyAt(x, y, False) and (ItemAt(x, y) < 0) and (HazardAt(x, y) < 0);
end;

{ for the AI: walls, the own trail, drones and the cells drones move into }
function TTrailGame.Blocked(x, y: Integer): Boolean;
var
  i: Integer;
begin
  if Wall(x, y) or BodyAt(x, y, True) then Exit(True);
  for i := 0 to High(Hazards) do
    if (Abs(Hazards[i].X - x) + Abs(Hazards[i].Y - y) <= 1) then Exit(True);
  Result := False;
end;

procedure TTrailGame.SpawnItem(AKind: TItemKind);
var
  tries, x, y, n: Integer;
  it: TItem;
  r: Single;
begin
  for tries := 1 to 400 do
  begin
    x := Trunc(Rand * BoardW);
    y := Trunc(Rand * BoardH);
    if not IsFree(x, y) then Continue;
    if (Length(Snake) > 0) and (Abs(x - Snake[0].X) + Abs(y - Snake[0].Y) < 4) then Continue;
    it.Kind := AKind;
    it.X := x;
    it.Y := y;
    it.Colour := Trunc(Rand * MaxColours) mod MaxColours;
    { with drones about, red belongs to them alone }
    if (Level >= 3) and (it.Colour = 5) then it.Colour := Trunc(Rand * (MaxColours - 1)) mod (MaxColours - 1);
    it.Power := pwNone;
    it.Life := -1;
    it.Age := 0;
    case AKind of
      ikGold: it.Life := 6;
      ikPower:
        begin
          it.Life := 8;
          { shrink only for long trails, shield only when none is held }
          repeat
            r := Rand * 6;
            it.Power := TPower(1 + Trunc(r) mod 6);
          until not (((it.Power = pwShrink) and (Length(Snake) < 12)) or
            ((it.Power = pwShield) and Shield));
        end;
    end;
    n := Length(Items);
    SetLength(Items, n + 1);
    Items[n] := it;
    Exit;
  end;
end;

procedure TTrailGame.SpawnHazards;
var
  n, i, tries, x, y: Integer;
begin
  SetLength(Hazards, 0);
  if Level < 3 then Exit;
  n := Min(5, Level - 2);
  HazStep := Max(0.18, 0.42 - 0.02 * Level);
  FHazT := 0;
  for i := 1 to n do
    for tries := 1 to 200 do
    begin
      x := Trunc(Rand * BoardW);
      y := Trunc(Rand * BoardH);
      if not IsFree(x, y) then Continue;
      if Abs(x - Snake[0].X) + Abs(y - Snake[0].Y) < 8 then Continue;
      SetLength(Hazards, Length(Hazards) + 1);
      { no "with" here: the fields X / Y would hide the locals x / y }
      Hazards[High(Hazards)].X := x;
      Hazards[High(Hazards)].Y := y;
      Hazards[High(Hazards)].PX := x;
      Hazards[High(Hazards)].PY := y;
      if Rand < 0.5 then
      begin
        Hazards[High(Hazards)].DX := 1 - 2 * Ord(Rand < 0.5);
        Hazards[High(Hazards)].DY := 0;
      end
      else
      begin
        Hazards[High(Hazards)].DX := 0;
        Hazards[High(Hazards)].DY := 1 - 2 * Ord(Rand < 0.5);
      end;
      Break;
    end;
end;

{ drones fly straight and turn when blocked; flying into the head hits it }
procedure TTrailGame.MoveHazards;
const
  DX4: array[0..3] of Integer = (1, -1, 0, 0);
  DY4: array[0..3] of Integer = (0, 0, 1, -1);
var
  i, k, nx, ny, tries: Integer;
  moved: Boolean;
  dr: THazard;
begin
  i := 0;
  while i <= High(Hazards) do
  begin
    dr := Hazards[i];
    dr.PX := dr.X;
    dr.PY := dr.Y;
    moved := False;
    for tries := 0 to 4 do
    begin
      if tries > 0 then
      begin
        k := Trunc(Rand * 4) mod 4;
        dr.DX := DX4[k];
        dr.DY := DY4[k];
      end;
      nx := dr.X + dr.DX;
      ny := dr.Y + dr.DY;
      if (Length(Snake) > 0) and (nx = Snake[0].X) and (ny = Snake[0].Y) then
      begin
        dr.X := nx;
        dr.Y := ny;
        moved := True;
        Break;
      end;
      if Wall(nx, ny) or BodyAt(nx, ny, False) or (ItemAt(nx, ny) >= 0) or (HazardAt(nx, ny) >= 0) then Continue;
      dr.X := nx;
      dr.Y := ny;
      moved := True;
      Break;
    end;
    if not moved then
    begin
      dr.X := dr.PX;
      dr.Y := dr.PY;
    end;
    Hazards[i] := dr;
    { a drone that reaches the head }
    if (Length(Snake) > 0) and (dr.X = Snake[0].X) and (dr.Y = Snake[0].Y) and (State in [gsPlaying, gsTitle]) then
    begin
      if UseShield(dr.X, dr.Y) then
      begin
        for k := i to High(Hazards) - 1 do Hazards[k] := Hazards[k + 1];
        SetLength(Hazards, Length(Hazards) - 1);
        Continue;
      end;
      Crash;
      Exit;
    end;
    Inc(i);
  end;
end;

procedure TTrailGame.AddPopup(x, y: Single; const AText: string; R, G, B: Byte);
var
  n: Integer;
begin
  if Demo then Exit;
  n := Length(Popups);
  SetLength(Popups, n + 1);
  Popups[n].X := x;
  Popups[n].Y := y;
  Popups[n].Age := 0;
  Popups[n].Text := AText;
  Popups[n].R := R;
  Popups[n].G := G;
  Popups[n].B := B;
end;

procedure TTrailGame.Turn(dx, dy: Integer);
var
  last: TPoint;
begin
  if Demo then Exit;
  if State = gsReady then
  begin
    { first key: start moving (any direction but straight into the trail) }
    if (dx = 0) and (dy = 1) then Exit;
    Dir := Point(dx, dy);
    FDirN := 0;
    State := gsPlaying;
    Exit;
  end;
  if State <> gsPlaying then Exit;
  if FDirN > 0 then last := FDirQ[FDirN - 1] else last := Dir;
  if (dx = last.X) and (dy = last.Y) then Exit;      // same direction
  if (dx = -last.X) and (dy = -last.Y) then Exit;    // no reversing
  if FDirN <= High(FDirQ) then
  begin
    FDirQ[FDirN] := Point(dx, dy);
    Inc(FDirN);
  end;
end;

procedure TTrailGame.Eat(AIndex: Integer);
var
  it: TItem;
  pts, i, keep: Integer;
  r, g, b: Byte;
  hasPower: Boolean;
  oldScore, oldBest: Integer;
begin
  oldScore := Score;
  oldBest := Best;
  it := Items[AIndex];
  for i := AIndex to High(Items) - 1 do Items[i] := Items[i + 1];
  SetLength(Items, Length(Items) - 1);
  case it.Kind of
    ikFood:
      begin
        if ComboTimer > 0 then Inc(Combo) else Combo := 1;
        ComboTimer := ComboWindow;
        MaxCombo := Max(MaxCombo, Combo);
        pts := 10 * Level + (Combo - 1) * 5 * Level;
        if Power = pwDouble then pts := pts * 2;
        Score += pts;
        Inc(Eaten);
        Inc(GameSparks);
        Inc(FGrow, 2);
        FColourIdx := it.Colour;
        Snake[0].Colour := it.Colour;
        r := BeadRGB[it.Colour, 0]; g := BeadRGB[it.Colour, 1]; b := BeadRGB[it.Colour, 2];
        if Combo >= 2 then
          AddPopup(it.X, it.Y, Format('+%d  COMBO x%d', [pts, Combo]), r, g, b)
        else
          AddPopup(it.X, it.Y, '+' + IntToStr(pts), r, g, b);
        if Combo >= 3 then AddFx(fxCombo, it.X, it.Y, r, g, b, Combo)
        else AddFx(fxEat, it.X, it.Y, r, g, b);
        Sound(gsndPop, 2 + Combo * 2);
        SpawnItem(ikFood);
        { extra items appear now and then }
        if (Level >= 2) and (Rand < 0.18) then SpawnItem(ikGold);
        hasPower := False;
        for i := 0 to High(Items) do
          if Items[i].Kind = ikPower then hasPower := True;
        if (Power = pwNone) and not hasPower and (Rand < 0.16) then SpawnItem(ikPower);
        if Eaten >= Goal then
        begin
          Bonus := 100 * Lives + 50 * Level;
          if LevelCrashes = 0 then
          begin
            Inc(FlawlessClears);
            Bonus += 200;
          end;
          Score += Bonus;
          MaxLevel := Max(MaxLevel, Level + 1);
          Best := Max(Best, Score);
          State := gsLevelDone;
          AddFx(fxLevel, BoardW / 2, BoardH / 2, 255, 255, 255);
          Sound(gsndLevel);
        end;
      end;
    ikGold:
      begin
        pts := 50 * Level;
        if Power = pwDouble then pts := pts * 2;
        Score += pts;
        Inc(GameGold);
        Inc(FGrow, 1);
        AddPopup(it.X, it.Y, '+' + IntToStr(pts) + '  GOLD', 255, 215, 90);
        AddFx(fxGold, it.X, it.Y, 255, 215, 90);
        Sound(gsndGold);
      end;
    ikPower:
      begin
        Include(PowersGot, it.Power);
        PowerRGB(it.Power, r, g, b);
        AddPopup(it.X, it.Y, PowerName(it.Power) + '!', r, g, b);
        AddFx(fxPower, it.X, it.Y, r, g, b);
        Sound(gsndPower);
        case it.Power of
          pwShrink:
            begin
              { the trail loses half its length: the cut beads burst }
              keep := Max(StartLength, Length(Snake) div 2);
              for i := keep to High(Snake) do
                AddFx(fxShrink, Snake[i].X, Snake[i].Y, BeadRGB[Snake[i].Colour, 0],
                  BeadRGB[Snake[i].Colour, 1], BeadRGB[Snake[i].Colour, 2], i - keep);
              SetLength(Snake, keep);
              FGrow := 0;
            end;
          pwShield:
            Shield := True;
        else
          begin
            Power := it.Power;
            case Power of
              pwMagnet: PowerTime := 8;
              pwDouble: PowerTime := 10;
            else
              PowerTime := 6;
            end;
          end;
        end;
      end;
  end;
  if Demo then
  begin
    { the title-screen demo never scores }
    Score := oldScore;
    Best := oldBest;
  end;
  Best := Max(Best, Score);
end;

{ a shield absorbs one crash at (x, y) }
function TTrailGame.UseShield(x, y: Integer): Boolean;
begin
  Result := Shield;
  if not Result then Exit;
  Shield := False;
  Inc(ShieldSaves);
  CrashFlash := 0.6;
  AddPopup(x, y, 'SHIELD!', 60, 255, 225);
  AddFx(fxShield, Snake[0].X, Snake[0].Y, 60, 255, 225);
  Sound(gsndPower);
end;

procedure TTrailGame.Crash;
var
  i: Integer;
begin
  CrashFlash := 1;
  { the whole trail bursts, head first }
  for i := 0 to High(Snake) do
    AddFx(fxCrash, Snake[i].X, Snake[i].Y, BeadRGB[Snake[i].Colour, 0],
      BeadRGB[Snake[i].Colour, 1], BeadRGB[Snake[i].Colour, 2], i);
  if Demo then
  begin
    Respawn;
    Exit;
  end;
  Dec(Lives);
  Inc(LevelCrashes);
  Power := pwNone;
  PowerTime := 0;
  Best := Max(Best, Score);
  Sound(gsndCrash);
  if Lives <= 0 then
  begin
    State := gsGameOver;
    Sound(gsndGameOver);
  end
  else
    State := gsCrashed;
end;

procedure TTrailGame.StepSnake;
var
  nd: TPoint;
  nx, ny, i, k, bestD, bx, by, d, hz: Integer;
  tail: TSeg;
begin
  { direction: AI in demo / autopilot, else the next queued turn }
  if Demo or AutoPilot then
    Dir := AIDir
  else if FDirN > 0 then
  begin
    nd := FDirQ[0];
    for i := 0 to FDirN - 2 do FDirQ[i] := FDirQ[i + 1];
    Dec(FDirN);
    if not ((nd.X = -Dir.X) and (nd.Y = -Dir.Y)) then Dir := nd;
  end;
  nx := Snake[0].X + Dir.X;
  ny := Snake[0].Y + Dir.Y;
  hz := HazardAt(nx, ny);
  if Wall(nx, ny) or ((Power <> pwGhost) and BodyAt(nx, ny, True)) or (hz >= 0) then
  begin
    if UseShield(nx, ny) then
    begin
      { saved: a drone is destroyed, otherwise turn away and wait a step }
      if hz >= 0 then
      begin
        for i := hz to High(Hazards) - 1 do Hazards[i] := Hazards[i + 1];
        SetLength(Hazards, Length(Hazards) - 1);
      end
      else
      begin
        Dir := SafeDir;
        FDirN := 0;
        for i := 0 to High(Snake) do
        begin
          Snake[i].PX := Snake[i].X;
          Snake[i].PY := Snake[i].Y;
        end;
        Exit;
      end;
    end
    else
    begin
      Crash;
      Exit;
    end;
  end;
  if (Power = pwGhost) and BodyAt(nx, ny, True) then Inc(GhostPasses);
  { move: every segment takes the place of the one before it }
  tail := Snake[High(Snake)];
  for i := High(Snake) downto 1 do
  begin
    Snake[i].PX := Snake[i].X;
    Snake[i].PY := Snake[i].Y;
    Snake[i].X := Snake[i - 1].X;
    Snake[i].Y := Snake[i - 1].Y;
  end;
  Snake[0].PX := Snake[0].X;
  Snake[0].PY := Snake[0].Y;
  Snake[0].X := nx;
  Snake[0].Y := ny;
  if FGrow > 0 then
  begin
    { the new tail bead appears where the old tail was }
    tail.PX := tail.X;
    tail.PY := tail.Y;
    k := Length(Snake);
    SetLength(Snake, k + 1);
    Snake[k] := tail;
    for i := k downto 2 do Snake[i].Colour := Snake[i - 1].Colour;
    Snake[1].Colour := Snake[0].Colour;
    Dec(FGrow);
    MaxLength := Max(MaxLength, Length(Snake));
  end;
  i := ItemAt(nx, ny);
  if i >= 0 then Eat(i);

  { magnet: sparkles within 5 cells drift one cell towards the head }
  if (Power = pwMagnet) and (State in [gsPlaying, gsTitle]) then
    for i := 0 to High(Items) do
      if (Items[i].Kind <> ikPower) and (Abs(Items[i].X - nx) + Abs(Items[i].Y - ny) <= 5) then
      begin
        bestD := MaxInt;
        bx := Items[i].X;
        by := Items[i].Y;
        for k := 0 to 3 do
        begin
          case k of
            0: nd := Point(1, 0);
            1: nd := Point(-1, 0);
            2: nd := Point(0, 1);
          else
            nd := Point(0, -1);
          end;
          d := Abs(Items[i].X + nd.X - nx) + Abs(Items[i].Y + nd.Y - ny);
          if (d < bestD) and (((Items[i].X + nd.X = nx) and (Items[i].Y + nd.Y = ny)) or
            IsFree(Items[i].X + nd.X, Items[i].Y + nd.Y)) then
          begin
            bestD := d;
            bx := Items[i].X + nd.X;
            by := Items[i].Y + nd.Y;
          end;
        end;
        Items[i].X := bx;
        Items[i].Y := by;
      end;
  i := ItemAt(nx, ny);
  if (i >= 0) and (State in [gsPlaying, gsTitle]) then Eat(i);
end;

function TTrailGame.FreeRoom(x, y: Integer): Integer;
var
  seen: array of Boolean;
  stack: array of Integer;
  sp, c, cx, cy: Integer;

  procedure Push(px, py: Integer);
  begin
    if Wall(px, py) or BodyAt(px, py, True) then Exit;
    if seen[Idx(px, py)] then Exit;
    seen[Idx(px, py)] := True;
    stack[sp] := Idx(px, py);
    Inc(sp);
  end;

begin
  SetLength(seen, BoardW * BoardH);
  SetLength(stack, BoardW * BoardH);
  sp := 0;
  Result := 0;
  Push(x, y);
  while (sp > 0) and (Result < 120) do
  begin
    Dec(sp);
    c := stack[sp];
    Inc(Result);
    cx := c mod BoardW;
    cy := c div BoardW;
    Push(cx + 1, cy); Push(cx - 1, cy); Push(cx, cy + 1); Push(cx, cy - 1);
  end;
end;

{ the safe neighbour with the most free room (or keep going) }
function TTrailGame.SafeDir: TPoint;
const
  DX: array[0..3] of Integer = (1, -1, 0, 0);
  DY: array[0..3] of Integer = (0, 0, 1, -1);
var
  k, nx, ny, room, bestRoom: Integer;
begin
  Result := Dir;
  bestRoom := -1;
  for k := 0 to 3 do
  begin
    nx := Snake[0].X + DX[k];
    ny := Snake[0].Y + DY[k];
    if (DX[k] = -Dir.X) and (DY[k] = -Dir.Y) then Continue;
    if Blocked(nx, ny) then Continue;
    room := FreeRoom(nx, ny);
    if room > bestRoom then
    begin
      bestRoom := room;
      Result := Point(DX[k], DY[k]);
    end;
  end;
end;

{ demo AI: breadth-first search to the nearest item, else most room }
function TTrailGame.AIDir: TPoint;
const
  DX: array[0..3] of Integer = (1, -1, 0, 0);
  DY: array[0..3] of Integer = (0, 0, 1, -1);
var
  prev: array of Integer;
  queue: array of Integer;
  qh, qt, c, cx, cy, k, nx, ny, n, target: Integer;
  hx, hy: Integer;
begin
  hx := Snake[0].X;
  hy := Snake[0].Y;
  SetLength(prev, BoardW * BoardH);
  for c := 0 to High(prev) do prev[c] := -2;
  SetLength(queue, BoardW * BoardH);
  qh := 0;
  qt := 0;
  prev[Idx(hx, hy)] := -1;
  queue[qt] := Idx(hx, hy);
  Inc(qt);
  target := -1;
  while qh < qt do
  begin
    c := queue[qh];
    Inc(qh);
    cx := c mod BoardW;
    cy := c div BoardW;
    if (c <> Idx(hx, hy)) and (ItemAt(cx, cy) >= 0) then
    begin
      target := c;
      Break;
    end;
    for k := 0 to 3 do
    begin
      nx := cx + DX[k];
      ny := cy + DY[k];
      if Blocked(nx, ny) then Continue;
      n := Idx(nx, ny);
      if prev[n] <> -2 then Continue;
      prev[n] := c;
      queue[qt] := n;
      Inc(qt);
    end;
  end;
  if target >= 0 then
  begin
    { walk back to the first step, but only take it if there is room after it }
    c := target;
    while prev[c] <> Idx(hx, hy) do c := prev[c];
    nx := c mod BoardW;
    ny := c div BoardW;
    if FreeRoom(nx, ny) > Length(Snake) then Exit(Point(nx - hx, ny - hy));
  end;
  Result := SafeDir;
end;

procedure TTrailGame.Update(dt: Single);
var
  i, j: Integer;
  sp: Single;
begin
  dt := Min(dt, 0.05);
  Clock += dt;
  CrashFlash := Max(0, CrashFlash - dt * 2);
  { popups }
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
  if not (State in [gsPlaying, gsTitle]) then Exit;

  { timed items }
  j := 0;
  for i := 0 to High(Items) do
  begin
    Items[i].Age += dt;
    if Items[i].Life >= 0 then Items[i].Life -= dt;
    if (Items[i].Life < 0) and (Items[i].Kind <> ikFood) then Continue;
    Items[j] := Items[i];
    Inc(j);
  end;
  SetLength(Items, j);
  if PowerTime > 0 then
  begin
    PowerTime -= dt;
    if PowerTime <= 0 then Power := pwNone;
  end;
  if ComboTimer > 0 then ComboTimer -= dt;
  if Boost then BoostTime += dt;

  { drones }
  if Length(Hazards) > 0 then
  begin
    FHazT += dt;
    while (FHazT >= HazStep) and (State in [gsPlaying, gsTitle]) do
    begin
      FHazT -= HazStep;
      MoveHazards;
    end;
  end;

  { speed: grows with the level and with every sparkle eaten }
  Speed := Min(15, 5.5 + 0.6 * (Level - 1) + 0.15 * Eaten);
  if Demo then Speed := 9;
  sp := Speed;
  if Power = pwSlow then sp := sp * 0.6;
  if Boost then sp := sp * 1.7;
  StepT += dt * sp;
  while (StepT >= 1) and (State in [gsPlaying, gsTitle]) do
  begin
    StepT -= 1;
    StepSnake;
  end;
  if not (State in [gsPlaying, gsTitle]) then StepT := 0;
end;

function TTrailGame.View(x, y: Integer): TCellView;
var
  i: Integer;
  t, f, pulse: Single;
  r, g, b: Byte;
  it: TItem;
begin
  Result := Default(TCellView);
  if Wall(x, y) then
  begin
    Result.R := 0.43; Result.G := 0.18; Result.B := 0.55;
    Result.Presence := 0.85;
    Exit;
  end;
  pulse := 0.5 + 0.5 * Sin(Clock * 6 + x + y);
  { items }
  i := ItemAt(x, y);
  if i >= 0 then
  begin
    it := Items[i];
    case it.Kind of
      ikFood:
        begin
          Result.R := BeadRGB[it.Colour, 0] / 255;
          Result.G := BeadRGB[it.Colour, 1] / 255;
          Result.B := BeadRGB[it.Colour, 2] / 255;
          Result.Flash := 0.2 + 0.3 * pulse;
          Result.Hover := 0.6;
        end;
      ikGold:
        begin
          Result.R := 1; Result.G := 0.84; Result.B := 0.35;
          Result.Flash := 0.4 + 0.5 * pulse;
          Result.Hover := 1;
        end;
    else
      begin
        PowerRGB(it.Power, r, g, b);
        Result.R := r / 255; Result.G := g / 255; Result.B := b / 255;
        Result.Flash := 0.25 + 0.35 * pulse;
        Result.Hover := 1;
      end;
    end;
    Result.Presence := 1;
    { timed items blink before they vanish }
    if (it.Life >= 0) and (it.Life < 2) and (Frac(Clock * 4) < 0.5) then Result.Presence := 0.25;
    { pop-in }
    Result.Presence := Result.Presence * Min(1, it.Age * 5);
  end;
  { drones: red, pulsing, moving smoothly }
  t := 1 - Min(1, FHazT / Max(0.01, HazStep));
  for i := 0 to High(Hazards) do
    if (Hazards[i].X = x) and (Hazards[i].Y = y) then
    begin
      { a hard red / white strobe: clearly not a sparkle }
      if Frac(Clock * 3 + i * 0.37) < 0.5 then
      begin
        Result.R := 1; Result.G := 0.1; Result.B := 0.12;
        Result.Flash := 0.15;
      end
      else
      begin
        Result.R := 1; Result.G := 0.45; Result.B := 0.4;
        Result.Flash := 0.75;
      end;
      Result.Presence := 1;
      Result.Hover := 1;
      Result.OffX := (Hazards[i].PX - Hazards[i].X) * t;
      Result.OffY := -(Hazards[i].PY - Hazards[i].Y) * t;
    end;
  { trail: head drawn last so it wins }
  t := 1 - StepT;
  for i := High(Snake) downto 0 do
    if (Snake[i].X = x) and (Snake[i].Y = y) then
    begin
      if i = 0 then
      begin
        if Shield then
        begin
          Result.R := 0.3; Result.G := 1; Result.B := 0.9;
        end
        else
        begin
          Result.R := 0.85; Result.G := 0.98; Result.B := 1;
        end;
        Result.Hover := 0.8;
      end
      else
      begin
        f := Max(0.55, 1 - i * 0.012);
        Result.R := BeadRGB[Snake[i].Colour, 0] / 255 * f;
        Result.G := BeadRGB[Snake[i].Colour, 1] / 255 * f;
        Result.B := BeadRGB[Snake[i].Colour, 2] / 255 * f;
        Result.Hover := 0;
        if Power = pwDouble then Result.Hover := 0.35 + 0.25 * pulse;
      end;
      Result.Presence := 1;
      if Power = pwGhost then Result.Presence := 0.55;
      Result.Flash := CrashFlash;
      Result.OffX := (Snake[i].PX - Snake[i].X) * t;
      Result.OffY := -(Snake[i].PY - Snake[i].Y) * t;
    end;
end;

end.
