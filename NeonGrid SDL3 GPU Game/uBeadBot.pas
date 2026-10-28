unit uBeadBot;

{ The VS BOT opponent of Neon Beads and the exchange between the two boards,
  shared by the game (NeonBeads.lpr) and the simulators of the rule editors
  (uBeadSim). The bot thinks, shows its move (aim) and clicks; its timings
  and taste come from the VS rules (uBeadRules):
    EASY    any move, pairs (iron) included
    NORMAL  mostly groups of NormalMin+, sometimes careless
    HARD    the biggest move
  VersusExchange sets who leads (the score gap), passes the iron sent and
  decides the match (the side that runs out of pairs first loses). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, uBeadGame, uBeadRules;

type
  TBeadBot = class
  public
    Level: Integer;            // 0 EASY, 1 NORMAL, 2 HARD
    ThinkT, AimT: Double;
    Pending: Boolean;          // a move is shown, the click follows
    X, Y: Integer;
    Moves: Integer;
    constructor Create(ALevel: Integer);
    procedure Reset(AFirstThink: Double = 1.2);
    { one step of the bot on its game (call every frame while playing) }
    procedure Step(G: TBeadGame; dt: Double);
  end;

{ the score gap, the iron in flight and the end of a match (A = left side) }
procedure VersusExchange(A, B: TBeadGame);

implementation

constructor TBeadBot.Create(ALevel: Integer);
begin
  inherited Create;
  Level := EnsureRange(ALevel, 0, BotLevels - 1);
  Reset;
end;

procedure TBeadBot.Reset(AFirstThink: Double);
begin
  ThinkT := AFirstThink;
  AimT := 0;
  Pending := False;
  Moves := 0;
end;

procedure TBeadBot.Step(G: TBeadGame; dt: Double);
var
  xx, yy, n, cnt, k, best: Integer;
  xs, ys, ns, good: array of Integer;
begin
  if G.State <> gsPlaying then Exit;
  if Pending then
  begin
    AimT -= dt;
    if AimT > 0 then Exit;
    Pending := False;
    G.SetMouseCell(X, Y);
    G.Click;
    G.SetMouseCell(-1, -1);
    Inc(Moves);
    ThinkT := VR[vrThink0 + Level] * (0.75 + 0.5 * Random);
    Exit;
  end;
  ThinkT -= dt;
  if ThinkT > 0 then Exit;
  cnt := 0;
  SetLength(xs, G.W * G.H);
  SetLength(ys, G.W * G.H);
  SetLength(ns, G.W * G.H);
  for xx := 0 to G.W - 1 do
    for yy := 0 to G.H - 1 do
    begin
      n := G.GroupSize(xx, yy);
      if n <= 0 then Continue;
      xs[cnt] := xx;
      ys[cnt] := yy;
      ns[cnt] := n;
      Inc(cnt);
    end;
  if cnt = 0 then Exit;   // the board ends itself (no move left)
  case Level of
    0:
      k := Random(cnt);
    1:
      begin
        SetLength(good, 0);
        for n := 0 to cnt - 1 do
          if ns[n] >= VRI(vrNormalMin) then
          begin
            SetLength(good, Length(good) + 1);
            good[High(good)] := n;
          end;
        if (Length(good) > 0) and (Random >= VR[vrNormalCareless]) then k := good[Random(Length(good))]
        else k := Random(cnt);
      end;
  else
    begin
      best := 0;
      k := 0;
      for n := 0 to cnt - 1 do
        if (ns[n] > best) or ((ns[n] = best) and (Random < 0.3)) then
        begin
          best := ns[n];
          k := n;
        end;
    end;
  end;
  X := xs[k];
  Y := ys[k];
  G.SetMouseCell(X, Y);
  Pending := True;
  AimT := VR[vrAim0 + Level];
end;

procedure VersusExchange(A, B: TBeadGame);
var
  d: Integer;
  aOver, bOver: Boolean;
begin
  { the score gap: iron works above VsIronGap (always at 0), the leader is
    the side ahead }
  d := A.Score - B.Score;
  A.VsIronOn := (VsIronGap = 0) or (Abs(d) > VsIronGap);
  B.VsIronOn := A.VsIronOn;
  if d > VsIronGap then A.VsLead := 1
  else if -d > VsIronGap then A.VsLead := -1
  else A.VsLead := 0;
  B.VsLead := -A.VsLead;
  { what each side sees of the other (the iron flowchart, uIronFlow) }
  A.VsOtherScore := B.Score;
  B.VsOtherScore := A.Score;
  A.VsOtherIron := B.IronCount;
  B.VsOtherIron := A.IronCount;
  A.VsSide := 0;
  B.VsSide := 1;
  if A.VsResult = 0 then
  begin
    B.PendingIron += A.OutIron;
    A.PendingIron += B.OutIron;
  end;
  A.OutIron := 0;
  B.OutIron := 0;
  if A.VsResult <> 0 then Exit;
  aOver := A.State = gsGameOver;
  bOver := B.State = gsGameOver;
  if aOver and bOver then
    A.VsResult := 3
  else if bOver then
  begin
    A.VsResult := 1;
    A.VsWon := True;
    A.EndRun(True);
  end
  else if aOver then
  begin
    A.VsResult := 2;
    B.EndRun(False);
  end;
end;

end.
