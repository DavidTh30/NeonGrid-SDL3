unit uGameFx;

{ Particle effects, score popups and particle physics of Neon Beads and
  Neon Trail as data (shared unit). Every value is registered in the uParams
  registry, so it is part of the game's .visuals file and editable in
  NeonVisualEditor.

  An effect (TFxDef) is one or more bursts; each burst fires up to two
  emitters (A, B). An emitter is a spark burst or an expanding ring:
    Count (+ Count per N, N capped at Count N max)   number of sparks
    Speed, Size (x cell), Life (s)                    motion and look
    Delay (+ Delay per N, capped)                     start time (s)
    Colour mode  0 = the event's colour, 1 = Colour, 2 = the bead colours
  N is the game's number for the event (group size, combo, iron count...).
  Where the bursts happen (Position):
    0 at the event     1 random spots in the Area (fractions of the board)
    2 along the row    (one burst per column, Burst delay per column away)
    3 along the top edge (random columns)
  Bursts (+ Bursts per N) and Burst delay (s between bursts) repeat it. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, BGRABitmapTypes, uParams, uParticles;

type
  TFxEmitter = record
    On, IsRing: Boolean;
    Count, CountNMax, DelayNMax, ColourMode: Integer;
    CountPerN, Speed, Size, Life, Delay, DelayPerN: Single;
    Colour: TBGRAPixel;
  end;

  TFxDef = record
    Name: string;
    Bursts, BurstsPerN, BurstsMax, Position: Integer;
    BurstDelay, AreaX0, AreaX1, AreaY0, AreaY1: Single;
    E: array[0..1] of TFxEmitter;
  end;

  { where the board is, for the positions of an effect }
  TFxBoard = record
    X0, Y0, Cell: Single;    // pixel centre of cell (0, 0), cell size
    W, H: Integer;           // board size in cells
    EventX: Single;          // the event's column (for row effects)
  end;

  TPopupFx = record
    Rise, Life, FadeStart, FadeTime, WhiteMix: Single;
    Font: Integer;           // 0 small, 1 middle, 2 big
  end;

  TFxColourFunc = function(AIndex: Integer): TBGRAPixel;

const
  MaxFxDefs = 32;

var
  FxDefs: array[0..MaxFxDefs - 1] of TFxDef;   // fixed: the registry points into it
  FxCount: Integer = 0;
  PopupFx: TPopupFx = (Rise: 1.4; Life: 1.1; FadeStart: 0.5; FadeTime: 0.6; WhiteMix: 0.5; Font: 2);
  ParticleGravity: Single = 3;     // x cell per s^2
  ParticleDrag: Single = 2.2;
  FxBeadColour: TFxColourFunc = nil;   // colour mode 2

{ emitter / effect builders for the defaults }
function FxBurst(ACount: Integer; ASpeed, ASize, ALife: Single): TFxEmitter;
function FxRing(ACount: Integer; ASpeed, ASize, ALife: Single): TFxEmitter;
function FxFixed(const E: TFxEmitter; R, G, B: Byte): TFxEmitter;
function FxDef(const AName: string; const A: TFxEmitter): TFxDef; overload;
function FxDef(const AName: string; const A, B: TFxEmitter): TFxDef; overload;
{ registers an effect (group "Effect: <name>") and returns its index }
function RegisterFx(const D: TFxDef; const AHint: string): Integer;
{ popups and particle physics (group "Popups", "Particles") }
procedure RegisterPopupFx(ALife: Single);
{ fires effect AIndex at (APX, APY) (window pixels) }
procedure SpawnFxDef(AParts: TParticles; AIndex: Integer; APX, APY: Single; AR, AG, AB: Byte; AN: Integer;
  const ABoard: TFxBoard);

implementation

function FxBurst(ACount: Integer; ASpeed, ASize, ALife: Single): TFxEmitter;
begin
  Result := Default(TFxEmitter);
  Result.On := True;
  Result.IsRing := False;
  Result.Count := ACount;
  Result.CountNMax := 40;
  Result.DelayNMax := 60;
  Result.Speed := ASpeed;
  Result.Size := ASize;
  Result.Life := ALife;
  Result.Colour := BGRA(255, 255, 255);
end;

function FxRing(ACount: Integer; ASpeed, ASize, ALife: Single): TFxEmitter;
begin
  Result := FxBurst(ACount, ASpeed, ASize, ALife);
  Result.IsRing := True;
end;

function FxFixed(const E: TFxEmitter; R, G, B: Byte): TFxEmitter;
begin
  Result := E;
  Result.ColourMode := 1;
  Result.Colour := BGRA(R, G, B);
end;

function FxDef(const AName: string; const A: TFxEmitter): TFxDef;
var
  off: TFxEmitter;
begin
  off := FxBurst(20, 6, 0.3, 0.6);
  off.On := False;
  Result := FxDef(AName, A, off);
end;

function FxDef(const AName: string; const A, B: TFxEmitter): TFxDef;
begin
  Result := Default(TFxDef);
  Result.Name := AName;
  Result.Bursts := 1;
  Result.BurstsMax := 64;
  Result.AreaX0 := 0.1;
  Result.AreaX1 := 0.9;
  Result.AreaY0 := 0.1;
  Result.AreaY1 := 0.7;
  Result.E[0] := A;
  Result.E[1] := B;
end;

function RegisterFx(const D: TFxDef; const AHint: string): Integer;
var
  g: string;
  k: Integer;
  ab: string;
begin
  Result := FxCount;
  if FxCount >= MaxFxDefs then Exit(MaxFxDefs - 1);
  FxDefs[Result] := D;
  Inc(FxCount);
  g := 'Effect: ' + D.Name;
  with FxDefs[Result] do
  begin
    AddI(g, 'Position', AHint + ' Where: 0 at the event, 1 random spots in the area, 2 along the row, 3 along the top edge.',
      Position, 0, 3, D.Position);
    AddI(g, 'Bursts', 'How many times the emitters fire.', Bursts, 0, 64, D.Bursts);
    AddI(g, 'Bursts per N', 'Extra bursts per unit of the event number N.', BurstsPerN, 0, 16, D.BurstsPerN);
    AddI(g, 'Bursts max', 'Cap of all bursts.', BurstsMax, 1, 200, D.BurstsMax);
    AddF(g, 'Burst delay', 'Seconds between bursts (row effects: per column away from the event).',
      BurstDelay, 0, 2, D.BurstDelay);
    AddF(g, 'Area x0', 'Random spots: left edge (fraction of the board width).', AreaX0, -0.5, 1.5, D.AreaX0);
    AddF(g, 'Area x1', 'Random spots: right edge.', AreaX1, -0.5, 1.5, D.AreaX1);
    AddF(g, 'Area y0', 'Random spots: top edge (fraction of the board height).', AreaY0, -0.5, 1.5, D.AreaY0);
    AddF(g, 'Area y1', 'Random spots: bottom edge.', AreaY1, -0.5, 1.5, D.AreaY1);
    for k := 0 to 1 do
    begin
      if k = 0 then ab := 'A ' else ab := 'B ';
      AddB(g, ab + 'on', 'Emitter ' + ab + 'fires.', E[k].On, D.E[k].On);
      AddB(g, ab + 'ring', 'An expanding ring of sparks instead of a random burst.', E[k].IsRing, D.E[k].IsRing);
      AddI(g, ab + 'count', 'Number of sparks.', E[k].Count, 0, 400, D.E[k].Count);
      AddF(g, ab + 'count per N', 'Extra sparks per unit of N.', E[k].CountPerN, 0, 20, D.E[k].CountPerN);
      AddI(g, ab + 'count N max', 'N is capped at this for the extra sparks.', E[k].CountNMax, 0, 200, D.E[k].CountNMax);
      AddF(g, ab + 'speed', 'Spark speed in cells per second.', E[k].Speed, 0, 40, D.E[k].Speed);
      AddF(g, ab + 'size', 'Spark size in cells.', E[k].Size, 0.02, 2, D.E[k].Size);
      AddF(g, ab + 'life', 'Spark life in seconds.', E[k].Life, 0.05, 5, D.E[k].Life);
      AddF(g, ab + 'delay', 'Start delay in seconds.', E[k].Delay, 0, 3, D.E[k].Delay);
      AddF(g, ab + 'delay per N', 'Extra delay per unit of N (staggered sparks).', E[k].DelayPerN, 0, 0.2, D.E[k].DelayPerN);
      AddI(g, ab + 'delay N max', 'N is capped at this for the delay.', E[k].DelayNMax, 0, 200, D.E[k].DelayNMax);
      AddI(g, ab + 'colour mode', '0 = the event colour, 1 = the colour below, 2 = the bead colours in turn.',
        E[k].ColourMode, 0, 2, D.E[k].ColourMode);
      AddC(g, ab + 'colour', 'Colour for colour mode 1.', E[k].Colour, D.E[k].Colour);
    end;
  end;
end;

procedure RegisterPopupFx(ALife: Single);
begin
  PopupFx.Life := ALife;
  AddF('Popups', 'Rise', 'Upward speed of the floating score texts in cells per second.', PopupFx.Rise, 0, 6, 1.4);
  AddF('Popups', 'Life', 'Seconds a popup stays.', PopupFx.Life, 0.2, 5, ALife);
  AddF('Popups', 'Fade start', 'Age in seconds when the popup starts to fade.', PopupFx.FadeStart, 0, 5, 0.5);
  AddF('Popups', 'Fade time', 'Seconds of the fade out.', PopupFx.FadeTime, 0.05, 5, 0.6);
  AddF('Popups', 'White mix', 'How much the bead colour of a popup is mixed with white.', PopupFx.WhiteMix, 0, 1, 0.5);
  AddI('Popups', 'Font', 'Popup text size: 0 small, 1 middle, 2 big.', PopupFx.Font, 0, 2, 2);
  AddF('Particles', 'Gravity', 'Downward pull on sparks in cells per second squared.', ParticleGravity, -10, 20, 3);
  AddF('Particles', 'Drag', 'Air drag of sparks (higher = they stop sooner).', ParticleDrag, 0, 10, 2.2);
end;

procedure SpawnFxDef(AParts: TParticles; AIndex: Integer; APX, APY: Single; AR, AG, AB: Byte; AN: Integer;
  const ABoard: TFxBoard);
var
  D: TFxDef;
  k, e, n, cnt, nb: Integer;
  x, y, dl, r, g, b: Single;
  c: TBGRAPixel;
begin
  if (AParts = nil) or (AIndex < 0) or (AIndex >= FxCount) then Exit;
  D := FxDefs[AIndex];
  if D.Position = 2 then nb := ABoard.W
  else nb := D.Bursts + D.BurstsPerN * Max(0, AN);
  nb := Min(nb, D.BurstsMax);
  for k := 0 to nb - 1 do
  begin
    { where and when this burst happens }
    case D.Position of
      1:
        begin
          x := ABoard.X0 + (D.AreaX0 + (D.AreaX1 - D.AreaX0) * Random) * ABoard.W * ABoard.Cell;
          y := ABoard.Y0 + (D.AreaY0 + (D.AreaY1 - D.AreaY0) * Random) * ABoard.H * ABoard.Cell;
          dl := k * D.BurstDelay;
        end;
      2:
        begin
          x := ABoard.X0 + k * ABoard.Cell;
          y := APY;
          dl := Abs(k - ABoard.EventX) * D.BurstDelay;
        end;
      3:
        begin
          x := ABoard.X0 + Random * Max(0, ABoard.W - 1) * ABoard.Cell;
          y := APY;
          dl := k * D.BurstDelay;
        end;
    else
      begin
        x := APX;
        y := APY;
        dl := k * D.BurstDelay;
      end;
    end;
    for e := 0 to 1 do
      with D.E[e] do
      begin
        if not On then Continue;
        n := Max(0, AN);
        cnt := Count + Round(Min(n, CountNMax) * CountPerN);
        if cnt <= 0 then Continue;
        case ColourMode of
          1: c := Colour;
          2: if Assigned(FxBeadColour) then c := FxBeadColour(k) else c := BGRA(AR, AG, AB);
        else
          c := BGRA(AR, AG, AB);
        end;
        r := c.red / 255;
        g := c.green / 255;
        b := c.blue / 255;
        if IsRing then
          AParts.Ring(x, y, cnt, r, g, b, Speed * ABoard.Cell, Size * ABoard.Cell, Life,
            dl + Delay + Min(n, DelayNMax) * DelayPerN)
        else
          AParts.Burst(x, y, cnt, r, g, b, Speed * ABoard.Cell, Size * ABoard.Cell, Life,
            dl + Delay + Min(n, DelayNMax) * DelayPerN);
      end;
  end;
end;

end.
