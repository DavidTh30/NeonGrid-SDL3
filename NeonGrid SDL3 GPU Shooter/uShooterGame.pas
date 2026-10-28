unit uShooterGame;

{ Neon Shooter rules: a bead shooter on the NeonGrid dot board.

  The launcher at the bottom shoots the current bead (the next one waits
  beside it; Swap changes them). A bead flies straight, bounces off the side
  walls and sticks where it touches the ceiling or another bead. Rows are
  packed like a honeycomb: every other row is shifted by half a bead
  (RowShift). A group of MinMatch (3) or more touching beads of one colour
  pops; beads that no longer hang from the ceiling drop (bonus points).
  Shots in a row that pop build a combo (points x1.25, x1.5 ... at most x3).
  A shot that pops nothing counts down to a new ceiling row: the whole board
  moves down one row and a fresh row comes in at the top. A bead at the
  danger line (DangerRow) ends the game; an empty board ends the level
  (clear bonus). Specials (from level 2) come as the next bead: a BOMB
  blasts every bead around where it lands, a RAINBOW takes the colour that
  gives it the biggest group.
  Levels: more colours (3 .. 6), more starting rows, fewer shots between new
  rows. Coordinates: x = column (0 left), y = row (0 top); cell centres are
  at (x + RowShift(y), y). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, uGameFx;

const
  BoardW = 13;
  BoardH = 21;
  DangerRow = 17;         // a bead here ends the game
  LaunchRow = 19;
  MinMatch = 3;
  MaxColours = 6;
  ShotSpeed = 26;         // cells per second
  StickDist = 0.88;       // a flying bead sticks this close to a bead centre
  SpNone = 0;
  SpBomb = 1;
  SpRainbow = 2;

var
  { colours: defaults here, the values come from NeonShooter.visuals }
  BeadRGB: array[0..MaxColours - 1, 0..2] of Byte = (
    (245, 150, 35), (35, 215, 240), (230, 40, 145),
    (150, 230, 55), (150, 75, 240), (245, 55, 55));

type
  TGameState = (gsTitle, gsReady, gsPlaying, gsCrashed, gsLevelDone, gsGameOver);
  TGameSound = (gsndPop, gsndInvalid, gsndLand, gsndUndo, gsndLevel, gsndGameOver, gsndStart,
    gsndMenuMove, gsndMenuSelect, gsndCrash, gsndGold, gsndPower);
  TSoundEvent = procedure(ASound: TGameSound; AParam: Integer) of object;
  TFxKind = (fxPop, fxDrop, fxCombo, fxBomb, fxRow, fxLand, fxLevel, fxGameOver);

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
    N: Integer;
  end;

  { what the renderer draws for one board cell }
  TCellView = record
    R, G, B, Presence, Hover, Flash, OffX, OffY: Single;
  end;

  TShot = record
    Colour, Spec: Integer;
  end;

  TShooterGame = class
  private
    FCol, FSpec: array of ShortInt;     // colour (-1 empty), special
    FFlash: array of Single;
    FParity: Integer;                   // which rows are shifted (flips on a new row)
    FRng: Cardinal;
    FAiT: Single;
    FBounced: Boolean;                  // the flying bead hit a wall
    FLandX, FLandY: Integer;            // where the aimed shot lands (-1 none)
    FAimStamp: Single;
    function Rand: Single;
    function Idx(x, y: Integer): Integer; inline;
    function NewColour: Integer;
    function NewShot: TShot;
    procedure FillRow(y: Integer);
    procedure Stick(px, py: Single);
    function Group(x, y, AColour: Integer; var AList: array of Integer): Integer;
    procedure DropLoose;
    procedure PushRow;
    procedure CheckEnd;
    function Trace(AAngle: Single; out ALandX, ALandY: Integer; APath: TList): Boolean;
    procedure Fire;
    procedure AddPopup(x, y: Single; const AText: string; R, G, B: Byte);
    procedure AddFx(AKind: TFxKind; x, y: Single; R, G, B: Byte; AN: Integer = 0);
    procedure Sound(S: TGameSound; AParam: Integer = 0);
    procedure AIShot;
  public
    State: TGameState;
    Level, Score, LevelStartScore, Best, MaxLevel, Bonus: Integer;
    Combo, ShotsToRow, RowEvery, Colours, Shots: Integer;
    Angle: Single;                      // radians, Pi/2 = straight up
    AimLeft, AimRight: Boolean;         // keys held
    Cur, Next: TShot;
    Flying: Boolean;
    PX, PY, VX, VY: Single;             // the flying bead (cell units)
    Clock: Single;
    Demo, AutoPilot: Boolean;
    Popups: array of TPopup;
    Fx: array of TFxEvent;              // consumed (cleared) by the program
    OnSound: TSoundEvent;
    { statistics for the achievements (per game, i.e. since PLAY) }
    GamePops, MaxGroup, MaxDrop, MaxCombo, BombsUsed, RainbowsUsed, BankPops, Clears, RowsSurvived: Integer;
    constructor Create;
    procedure ShowTitle;
    procedure StartLevel(ALevel: Integer; AKeepScore: Boolean);
    procedure Update(dt: Single);
    { aim at a point of the board (cell units) }
    procedure AimAt(ATX, ATY: Single);
    procedure Shoot;
    procedure Swap;
    { the aim line (cell units) and the landing cell, for the HUD }
    procedure AimPath(APath: TList; out ALandX, ALandY: Integer);
    function View(x, y: Integer): TCellView;
    function Cell(x, y: Integer): Integer;
    function RowShift(y: Integer): Single;
    function RowCap(y: Integer): Integer;
    function BeadCount: Integer;
    function W: Integer;
    function H: Integer;
    function LauncherX: Single;
    function LauncherY: Single;
  end;

  PPointF = ^TPointFRec;
  TPointFRec = record
    X, Y: Single;
  end;

implementation

const
  MinAngle = 0.13 * Pi;
  MaxAngle = 0.87 * Pi;

constructor TShooterGame.Create;
begin
  inherited Create;
  FRng := 12345;
  SetLength(FCol, BoardW * BoardH);
  SetLength(FSpec, BoardW * BoardH);
  SetLength(FFlash, BoardW * BoardH);
  MaxLevel := 1;
  Angle := Pi / 2;
  FLandX := -1;
  ShowTitle;
end;

function TShooterGame.Rand: Single;
begin
  FRng := FRng * 1664525 + 1013904223;
  Result := (FRng shr 8) / 16777216;
end;

function TShooterGame.Idx(x, y: Integer): Integer;
begin
  Result := y * BoardW + x;
end;

function TShooterGame.W: Integer;
begin
  Result := BoardW;
end;

function TShooterGame.H: Integer;
begin
  Result := BoardH;
end;

function TShooterGame.LauncherX: Single;
begin
  Result := BoardW div 2;
end;

function TShooterGame.LauncherY: Single;
begin
  Result := LaunchRow;
end;

function TShooterGame.RowShift(y: Integer): Single;
begin
  if ((y + FParity) and 1) = 1 then Result := 0.5 else Result := 0;
end;

function TShooterGame.RowCap(y: Integer): Integer;
begin
  if RowShift(y) > 0 then Result := BoardW - 1 else Result := BoardW;
end;

function TShooterGame.Cell(x, y: Integer): Integer;
begin
  if (x < 0) or (y < 0) or (x >= RowCap(y)) or (y >= BoardH) then Exit(-1);
  Result := FCol[Idx(x, y)];
end;

function TShooterGame.BeadCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FCol) do
    if FCol[i] >= 0 then Inc(Result);
end;

procedure TShooterGame.Sound(S: TGameSound; AParam: Integer);
begin
  if Assigned(OnSound) and not Demo and (State <> gsTitle) then OnSound(S, AParam);
end;

procedure TShooterGame.AddPopup(x, y: Single; const AText: string; R, G, B: Byte);
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

procedure TShooterGame.AddFx(AKind: TFxKind; x, y: Single; R, G, B: Byte; AN: Integer);
var
  n: Integer;
begin
  n := Length(Fx);
  if n > 600 then Exit;
  SetLength(Fx, n + 1);
  Fx[n].Kind := AKind;
  Fx[n].X := x;
  Fx[n].Y := y;
  Fx[n].R := R;
  Fx[n].G := G;
  Fx[n].B := B;
  Fx[n].N := AN;
end;

{ a colour that is on the board (so every shot can match), else any }
function TShooterGame.NewColour: Integer;
var
  have: array[0..MaxColours - 1] of Boolean;
  i, n, k: Integer;
begin
  FillChar(have, SizeOf(have), 0);
  n := 0;
  for i := 0 to High(FCol) do
    if (FCol[i] >= 0) and (FCol[i] < Colours) and not have[FCol[i]] then
    begin
      have[FCol[i]] := True;
      Inc(n);
    end;
  if n = 0 then Exit(Trunc(Rand * Colours) mod Colours);
  k := Trunc(Rand * n) mod n;
  for i := 0 to Colours - 1 do
    if have[i] then
    begin
      if k = 0 then Exit(i);
      Dec(k);
    end;
  Result := 0;
end;

function TShooterGame.NewShot: TShot;
var
  r: Single;
begin
  Result.Colour := NewColour;
  Result.Spec := SpNone;
  if Level >= 2 then
  begin
    r := Rand;
    if r < 0.05 then Result.Spec := SpBomb
    else if r < 0.10 then Result.Spec := SpRainbow;
  end;
end;

procedure TShooterGame.FillRow(y: Integer);
var
  x: Integer;
begin
  for x := 0 to BoardW - 1 do
  begin
    FSpec[Idx(x, y)] := SpNone;
    if x < RowCap(y) then FCol[Idx(x, y)] := Trunc(Rand * Colours) mod Colours
    else FCol[Idx(x, y)] := -1;
    FFlash[Idx(x, y)] := 0.6;
  end;
end;

procedure TShooterGame.ShowTitle;
begin
  StartLevel(1, False);
  State := gsTitle;
  Demo := True;
end;

procedure TShooterGame.StartLevel(ALevel: Integer; AKeepScore: Boolean);
var
  i, rows: Integer;
begin
  Demo := False;
  Level := Max(1, ALevel);
  if not AKeepScore then
  begin
    Score := 0;
    GamePops := 0; MaxGroup := 0; MaxDrop := 0; MaxCombo := 0; BombsUsed := 0; RainbowsUsed := 0;
    BankPops := 0; Clears := 0; RowsSurvived := 0;
  end;
  LevelStartScore := Score;
  Colours := Min(MaxColours, 3 + (Level - 1) div 2);
  rows := Min(10, 4 + Level);
  RowEvery := Max(3, 8 - Level div 2);
  ShotsToRow := RowEvery;
  FParity := 0;
  for i := 0 to High(FCol) do
  begin
    FCol[i] := -1;
    FSpec[i] := SpNone;
    FFlash[i] := 0;
  end;
  for i := 0 to rows - 1 do FillRow(i);
  Combo := 0;
  Shots := 0;
  Bonus := 0;
  Flying := False;
  Cur := NewShot;
  Next := NewShot;
  Cur.Spec := SpNone;
  SetLength(Popups, 0);
  State := gsPlaying;
  AddPopup(BoardW / 2, DangerRow - 3, Format('LEVEL %d', [Level]), 255, 255, 255);
  Sound(gsndStart);
end;

procedure TShooterGame.AimAt(ATX, ATY: Single);
var
  dx, dy: Single;
begin
  dx := ATX - LauncherX;
  dy := LauncherY - ATY;
  if dy < 0.2 then dy := 0.2;
  Angle := EnsureRange(ArcTan2(dy, dx), MinAngle, MaxAngle);
end;

procedure TShooterGame.Swap;
var
  t: TShot;
begin
  if (State <> gsPlaying) or Flying then Exit;
  t := Cur;
  Cur := Next;
  Next := t;
  Sound(gsndMenuMove);
end;

procedure TShooterGame.Shoot;
begin
  if (State <> gsPlaying) or Flying then Exit;
  Fire;
end;

procedure TShooterGame.Fire;
begin
  Flying := True;
  FBounced := False;
  PX := LauncherX;
  PY := LauncherY;
  VX := Cos(Angle) * ShotSpeed;
  VY := -Sin(Angle) * ShotSpeed;
  Inc(Shots);
  Sound(gsndStart);
end;

{ the flight of a bead at AAngle until it sticks (no change to the board);
  APath gets the bounce points (cell units) }
function TShooterGame.Trace(AAngle: Single; out ALandX, ALandY: Integer; APath: TList): Boolean;
var
  tx, ty, tvx, tvy, d, bd, cx: Single;
  x, y, steps, gx, gy: Integer;
  hit: Boolean;
  p: PPointF;

  procedure AddPt(AX, AY: Single);
  begin
    if APath = nil then Exit;
    New(p);
    p^.X := AX;
    p^.Y := AY;
    APath.Add(p);
  end;

begin
  Result := False;
  ALandX := -1;
  ALandY := -1;
  tx := LauncherX;
  ty := LauncherY;
  tvx := Cos(AAngle) * 0.05;
  tvy := -Sin(AAngle) * 0.05;
  AddPt(tx, ty);
  hit := False;
  steps := 0;
  while (steps < 4000) and not hit do
  begin
    Inc(steps);
    tx += tvx;
    ty += tvy;
    if tx < 0 then
    begin
      tx := -tx;
      tvx := -tvx;
      AddPt(tx, ty);
    end
    else if tx > BoardW - 1 then
    begin
      tx := 2 * (BoardW - 1) - tx;
      tvx := -tvx;
      AddPt(tx, ty);
    end;
    if ty <= 0 then hit := True
    else
      for y := Max(0, Floor(ty) - 1) to Min(BoardH - 1, Ceil(ty) + 1) do
      begin
        for x := 0 to RowCap(y) - 1 do
          if FCol[Idx(x, y)] >= 0 then
          begin
            cx := x + RowShift(y);
            if Sqr(cx - tx) + Sqr(y - ty) < StickDist * StickDist then
            begin
              hit := True;
              Break;
            end;
          end;
        if hit then Break;
      end;
  end;
  AddPt(tx, Max(0, ty));
  if not hit then Exit;
  { the empty cell nearest to where it stopped }
  bd := 1e9;
  for gy := Max(0, Round(ty) - 1) to Min(BoardH - 1, Round(ty) + 1) do
    for gx := 0 to RowCap(gy) - 1 do
      if FCol[Idx(gx, gy)] < 0 then
      begin
        d := Sqr(gx + RowShift(gy) - tx) + Sqr(gy - ty);
        if d < bd then
        begin
          bd := d;
          ALandX := gx;
          ALandY := gy;
        end;
      end;
  Result := ALandX >= 0;
end;

procedure TShooterGame.AimPath(APath: TList; out ALandX, ALandY: Integer);
begin
  Trace(Angle, ALandX, ALandY, APath);
end;

{ the cells of colour AColour connected to (x, y) (8 cells around in the
  honeycomb: same row +-1, the rows above / below at half a cell) }
function TShooterGame.Group(x, y, AColour: Integer; var AList: array of Integer): Integer;
var
  seen: array of Boolean;
  head, i, cx, cy, nx, ny: Integer;
  ccx: Single;
begin
  SetLength(seen, BoardW * BoardH);
  Result := 0;
  AList[0] := Idx(x, y);
  seen[Idx(x, y)] := True;
  Result := 1;
  head := 0;
  while head < Result do
  begin
    cx := AList[head] mod BoardW;
    cy := AList[head] div BoardW;
    Inc(head);
    ccx := cx + RowShift(cy);
    for ny := cy - 1 to cy + 1 do
      for nx := cx - 1 to cx + 1 do
      begin
        if (ny < 0) or (ny >= BoardH) or (nx < 0) or (nx >= RowCap(ny)) then Continue;
        if (nx = cx) and (ny = cy) then Continue;
        if (ny = cy) then
        begin
          if Abs(nx - cx) <> 1 then Continue;
        end
        else if Abs(nx + RowShift(ny) - ccx) > 0.6 then Continue;
        i := Idx(nx, ny);
        if seen[i] or (FCol[i] < 0) then Continue;
        if (AColour >= 0) and (FCol[i] <> AColour) then Continue;
        seen[i] := True;
        AList[Result] := i;
        Inc(Result);
      end;
  end;
end;

procedure TShooterGame.Stick(px, py: Single);
var
  lx, ly, i, k, n, c, bestN, pts, bx, by, x, y: Integer;
  list: array of Integer;
  mult: Single;
  r, g, b: Byte;
  spec: Integer;
begin
  Flying := False;
  { the empty cell nearest to where it stopped }
  lx := -1;
  ly := -1;
  mult := 1e9;
  for y := Max(0, Round(py) - 1) to Min(BoardH - 1, Round(py) + 1) do
    for x := 0 to RowCap(y) - 1 do
      if FCol[Idx(x, y)] < 0 then
        if Sqr(x + RowShift(y) - px) + Sqr(y - py) < mult then
        begin
          mult := Sqr(x + RowShift(y) - px) + Sqr(y - py);
          lx := x;
          ly := y;
        end;
  if lx < 0 then
  begin
    CheckEnd;
    Exit;
  end;
  i := Idx(lx, ly);
  spec := Cur.Spec;
  FCol[i] := Cur.Colour;
  FSpec[i] := SpNone;
  FFlash[i] := 1;
  SetLength(list, BoardW * BoardH);
  { a rainbow takes the colour of its biggest group }
  if spec = SpRainbow then
  begin
    bestN := 0;
    for c := 0 to Colours - 1 do
    begin
      FCol[i] := c;
      n := Group(lx, ly, c, list);
      if n > bestN then
      begin
        bestN := n;
        k := c;
      end;
    end;
    FCol[i] := k;
    Inc(RainbowsUsed);
  end;
  n := 0;
  if spec = SpBomb then
  begin
    { a bomb: every bead within 1.6 cells }
    Inc(BombsUsed);
    for y := Max(0, ly - 2) to Min(BoardH - 1, ly + 2) do
      for x := 0 to RowCap(y) - 1 do
        if (FCol[Idx(x, y)] >= 0) and (Sqr(x + RowShift(y) - (lx + RowShift(ly))) + Sqr(y - ly) <= 2.6) then
        begin
          list[n] := Idx(x, y);
          Inc(n);
        end;
    AddFx(fxBomb, lx + RowShift(ly), ly, 255, 200, 90);
    Sound(gsndCrash);
  end
  else
  begin
    n := Group(lx, ly, FCol[i], list);
    if n < MinMatch then n := 0;
  end;
  if n > 0 then
  begin
    { pop }
    Inc(Combo);
    MaxCombo := Max(MaxCombo, Combo);
    mult := Min(3, 1 + 0.25 * (Combo - 1));
    pts := Round((n * 10 + Max(0, n - MinMatch) * n * 5) * mult);
    Score += pts;
    GamePops += n;
    MaxGroup := Max(MaxGroup, n);
    if FBounced then Inc(BankPops);
    bx := 0;
    by := 0;
    for k := 0 to n - 1 do
    begin
      x := list[k] mod BoardW;
      y := list[k] div BoardW;
      c := FCol[list[k]];
      if c >= 0 then
      begin
        r := BeadRGB[c, 0]; g := BeadRGB[c, 1]; b := BeadRGB[c, 2];
      end
      else
      begin
        r := 255; g := 255; b := 255;
      end;
      AddFx(fxPop, x + RowShift(y), y, r, g, b, k);
      FCol[list[k]] := -1;
      FSpec[list[k]] := SpNone;
      bx += x;
      by += y;
    end;
    if Combo >= 2 then
    begin
      AddPopup(bx / n, by / n, Format('+%d  COMBO x%d', [pts, Combo]), 255, 215, 90);
      AddFx(fxCombo, bx / n, by / n, 255, 215, 90, Combo);
    end
    else
      AddPopup(bx / n, by / n, '+' + IntToStr(pts), BeadRGB[EnsureRange(Cur.Colour, 0, MaxColours - 1), 0],
        BeadRGB[EnsureRange(Cur.Colour, 0, MaxColours - 1), 1], BeadRGB[EnsureRange(Cur.Colour, 0, MaxColours - 1), 2]);
    Sound(gsndPop, n);
    DropLoose;
  end
  else
  begin
    { no pop: the ceiling comes closer }
    Combo := 0;
    AddFx(fxLand, lx + RowShift(ly), ly, BeadRGB[FCol[i], 0], BeadRGB[FCol[i], 1], BeadRGB[FCol[i], 2]);
    Sound(gsndLand);
    Dec(ShotsToRow);
    if ShotsToRow <= 0 then PushRow;
  end;
  Cur := Next;
  Next := NewShot;
  CheckEnd;
end;

{ beads that no longer hang from the ceiling drop }
procedure TShooterGame.DropLoose;
var
  seen: array of Boolean;
  queue: array of Integer;
  qh, qn, i, x, y, nx, ny, n, pts, c: Integer;
  ccx: Single;
begin
  SetLength(seen, BoardW * BoardH);
  SetLength(queue, BoardW * BoardH);
  qn := 0;
  for x := 0 to RowCap(0) - 1 do
    if FCol[Idx(x, 0)] >= 0 then
    begin
      seen[Idx(x, 0)] := True;
      queue[qn] := Idx(x, 0);
      Inc(qn);
    end;
  qh := 0;
  while qh < qn do
  begin
    x := queue[qh] mod BoardW;
    y := queue[qh] div BoardW;
    Inc(qh);
    ccx := x + RowShift(y);
    for ny := y - 1 to y + 1 do
      for nx := x - 1 to x + 1 do
      begin
        if (ny < 0) or (ny >= BoardH) or (nx < 0) or (nx >= RowCap(ny)) then Continue;
        if ny = y then
        begin
          if Abs(nx - x) <> 1 then Continue;
        end
        else if Abs(nx + RowShift(ny) - ccx) > 0.6 then Continue;
        i := Idx(nx, ny);
        if seen[i] or (FCol[i] < 0) then Continue;
        seen[i] := True;
        queue[qn] := i;
        Inc(qn);
      end;
  end;
  n := 0;
  for i := 0 to High(FCol) do
    if (FCol[i] >= 0) and not seen[i] then
    begin
      x := i mod BoardW;
      y := i div BoardW;
      c := FCol[i];
      AddFx(fxDrop, x + RowShift(y), y, BeadRGB[c, 0], BeadRGB[c, 1], BeadRGB[c, 2], n);
      FCol[i] := -1;
      FSpec[i] := SpNone;
      Inc(n);
    end;
  if n > 0 then
  begin
    pts := n * 25 * (1 + n div 5);
    Score += pts;
    MaxDrop := Max(MaxDrop, n);
    AddPopup(BoardW / 2, DangerRow - 2, Format('DROP %d  +%d', [n, pts]), 120, 255, 160);
    Sound(gsndGold);
  end;
end;

{ a new ceiling row: everything moves down one row }
procedure TShooterGame.PushRow;
var
  x, y: Integer;
begin
  ShotsToRow := RowEvery;
  for y := BoardH - 1 downto 1 do
    for x := 0 to BoardW - 1 do
    begin
      FCol[Idx(x, y)] := FCol[Idx(x, y - 1)];
      FSpec[Idx(x, y)] := FSpec[Idx(x, y - 1)];
      FFlash[Idx(x, y)] := FFlash[Idx(x, y - 1)];
    end;
  FParity := 1 - FParity;   // the shifted rows move down with the beads
  FillRow(0);
  Inc(RowsSurvived);
  AddFx(fxRow, BoardW / 2, 0, 255, 90, 90);
  Sound(gsndCrash);
end;

procedure TShooterGame.CheckEnd;
var
  x, y: Integer;
  danger: Boolean;
begin
  danger := False;
  for y := DangerRow to BoardH - 1 do
    for x := 0 to RowCap(y) - 1 do
      if FCol[Idx(x, y)] >= 0 then danger := True;
  { the demo behind the title menu just starts again }
  if State = gsTitle then
  begin
    if danger or (BeadCount = 0) then ShowTitle;
    Exit;
  end;
  if State <> gsPlaying then Exit;
  for y := DangerRow to BoardH - 1 do
    for x := 0 to RowCap(y) - 1 do
      if FCol[Idx(x, y)] >= 0 then
      begin
        State := gsGameOver;
        Best := Max(Best, Score);
        AddFx(fxGameOver, BoardW / 2, DangerRow, 255, 60, 60);
        Sound(gsndGameOver);
        Exit;
      end;
  if BeadCount = 0 then
  begin
    Bonus := 1000 + 200 * Level;
    Score += Bonus;
    Inc(Clears);
    MaxLevel := Max(MaxLevel, Level + 1);
    Best := Max(Best, Score);
    State := gsLevelDone;
    AddFx(fxLevel, BoardW / 2, BoardH / 3, 255, 255, 255);
    Sound(gsndLevel);
  end;
end;

{ the AI: tries many angles, takes the shot with the biggest pop (or the
  landing highest up when nothing pops); swaps when the next bead is better }
procedure TShooterGame.AIShot;
var
  k, lx, ly, n, ci: Integer;
  a, bestA, bestV, v: Single;
  list: array of Integer;
  swapIt: Boolean;
  shot: TShot;
begin
  SetLength(list, BoardW * BoardH);
  bestV := -1e9;
  bestA := Pi / 2;
  swapIt := False;
  for ci := 0 to 1 do
  begin
    if ci = 0 then shot := Cur else shot := Next;
    for k := 0 to 60 do
    begin
      a := MinAngle + (MaxAngle - MinAngle) * k / 60;
      if not Trace(a, lx, ly, nil) then Continue;
      if ly >= DangerRow then Continue;
      if shot.Spec <> SpNone then
        v := 30
      else
      begin
        FCol[Idx(lx, ly)] := shot.Colour;
        n := Group(lx, ly, shot.Colour, list);
        FCol[Idx(lx, ly)] := -1;
        if n >= MinMatch then v := 100 + n * 10 else v := n * 3 - ly * 0.5;
      end;
      v += Rand * 2;
      if ci = 1 then v -= 4;   // swapping costs a little
      if v > bestV then
      begin
        bestV := v;
        bestA := a;
        swapIt := ci = 1;
      end;
    end;
  end;
  if swapIt then Swap;
  Angle := bestA;
  Fire;
end;

procedure TShooterGame.Update(dt: Single);
var
  i, j, steps: Integer;
  sub, cx: Single;
  hit: Boolean;
  x, y: Integer;
begin
  dt := Min(dt, 0.05);
  Clock += dt;
  for i := 0 to High(FFlash) do
    if FFlash[i] > 0 then FFlash[i] := Max(0, FFlash[i] - dt * 2.5);
  j := 0;
  for i := 0 to High(Popups) do
  begin
    Popups[i].Age += dt;
    if Popups[i].Age < 1.4 then
    begin
      Popups[j] := Popups[i];
      Inc(j);
    end;
  end;
  SetLength(Popups, j);
  if not (State in [gsPlaying, gsTitle]) then Exit;

  { aiming with the keys }
  if AimLeft then Angle := Min(MaxAngle, Angle + 1.6 * dt);
  if AimRight then Angle := Max(MinAngle, Angle - 1.6 * dt);

  if Flying then
  begin
    { small steps: no bead is jumped over }
    steps := Max(1, Ceil(dt * ShotSpeed / 0.2));
    sub := dt / steps;
    hit := False;
    for i := 1 to steps do
    begin
      PX += VX * sub;
      PY += VY * sub;
      if PX < 0 then
      begin
        PX := -PX;
        VX := -VX;
        FBounced := True;
        Sound(gsndMenuMove);
      end
      else if PX > BoardW - 1 then
      begin
        PX := 2 * (BoardW - 1) - PX;
        VX := -VX;
        FBounced := True;
        Sound(gsndMenuMove);
      end;
      if PY <= 0 then hit := True
      else
        for y := Max(0, Floor(PY) - 1) to Min(BoardH - 1, Ceil(PY) + 1) do
        begin
          for x := 0 to RowCap(y) - 1 do
            if FCol[Idx(x, y)] >= 0 then
            begin
              cx := x + RowShift(y);
              if Sqr(cx - PX) + Sqr(y - PY) < StickDist * StickDist then
              begin
                hit := True;
                Break;
              end;
            end;
          if hit then Break;
        end;
      if hit then
      begin
        Stick(PX, Max(0, PY));
        Break;
      end;
    end;
    Exit;
  end;

  { the demo behind the title menu and --autoplay shoot by themselves }
  if Demo or AutoPilot then
  begin
    FAiT += dt;
    if FAiT > IfThen(Demo, 0.9, 0.55) then
    begin
      FAiT := 0;
      AIShot;
    end;
  end;
  { where the aimed shot will land (the ghost bead) }
  if (State = gsPlaying) and not Flying and not Demo then Trace(Angle, FLandX, FLandY, nil)
  else FLandX := -1;
end;

function TShooterGame.View(x, y: Integer): TCellView;
var
  i, c, k: Integer;
  hue, t: Single;

  procedure SetCol(AC: Integer);
  begin
    Result.R := BeadRGB[EnsureRange(AC, 0, MaxColours - 1), 0] / 255;
    Result.G := BeadRGB[EnsureRange(AC, 0, MaxColours - 1), 1] / 255;
    Result.B := BeadRGB[EnsureRange(AC, 0, MaxColours - 1), 2] / 255;
  end;

  procedure ShotLook(const S: TShot);
  begin
    if S.Spec = SpBomb then
    begin
      Result.R := 1; Result.G := 0.95; Result.B := 0.85;
      Result.Flash := 0.5 + 0.5 * Sin(Clock * 10);
    end
    else if S.Spec = SpRainbow then
    begin
      hue := Frac(Clock * 0.6);
      k := Trunc(hue * Colours) mod Max(1, Colours);
      SetCol(k);
      Result.Flash := 0.3;
    end
    else
      SetCol(S.Colour);
  end;

begin
  Result := Default(TCellView);
  if (x < 0) or (y < 0) or (x >= BoardW) or (y >= BoardH) then Exit;
  { the launcher row: the current bead (big glow) and the next one }
  if y = LaunchRow then
  begin
    if (x = Round(LauncherX)) and not Flying and (State in [gsPlaying, gsTitle]) then
    begin
      ShotLook(Cur);
      Result.Presence := 1;
      Result.Hover := 0.6 + 0.4 * Sin(Clock * 4);
    end
    else if x = Round(LauncherX) - 3 then
    begin
      ShotLook(Next);
      Result.Presence := 0.75;
    end;
    Exit;
  end;
  { the flying bead, drawn from the cell it is over }
  if Flying and (x = Round(PX)) and (y = Round(PY)) then
  begin
    ShotLook(Cur);
    Result.Presence := 1;
    Result.OffX := PX - x;
    Result.OffY := -(PY - y);
    Result.Hover := 0.5;
    Exit;
  end;
  i := Idx(x, y);
  if x >= RowCap(y) then Exit;
  c := FCol[i];
  if c >= 0 then
  begin
    SetCol(c);
    Result.Presence := 1;
    Result.Flash := FFlash[i];
    Result.OffX := RowShift(y);
  end
  else
  begin
    Result.OffX := RowShift(y);
    { the danger line glows faintly }
    if y = DangerRow then Result.Hover := 0.35;
    { where the aimed shot will land: a faint ghost of the bead }
    if (x = FLandX) and (y = FLandY) and not Flying and (State = gsPlaying) and not Demo then
    begin
      t := 0.45 + 0.2 * Sin(Clock * 6);
      ShotLook(Cur);
      Result.Presence := t;
      Result.Hover := 0.6;
    end;
  end;
end;

end.
