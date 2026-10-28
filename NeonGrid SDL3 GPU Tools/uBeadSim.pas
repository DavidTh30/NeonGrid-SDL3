unit uBeadSim;

{ Headless Neon Beads games for the rule editors (NeonScoreEditor,
  NeonVsEditor): the real game logic (uBeadGame) with the rules in memory
  (uBeadRules, edited but maybe not saved), played by a simple player
  (SimSingle) or by two bots against each other (SimVersus, uBeadBot).
  Time runs in steps of SimDt seconds, nothing is drawn or heard. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, uBeadGame, uBeadBot, uBeadRules;

const
  SimDt = 0.05;
  PolicyNames: array[0..3] of string = ('Biggest group first', 'Smallest group first', 'Random move',
    'Like the NORMAL bot');
  ModeNames: array[0..2] of string = ('Classic (one level)', 'Time attack', 'Survival');

type
  TSimGame = record
    Score, Pops, MaxGroup, Stars, Bonus, Specials, Iron, Boards: Integer;
    AvgGroup, Seconds: Single;
    Passed: Boolean;
  end;

  TVsPoint = record
    T, A, B: Single;
  end;

  TVsSim = record
    Winner: Integer;           // 1 left, 2 right, 3 both out, 0 time limit
    ScoreA, ScoreB, SentA, SentB, MovesA, MovesB: Integer;
    Seconds, IronOnSecs, LeadASecs, LeadBSecs: Single;
    Timeline: array of TVsPoint;
  end;

{ one game: AMode 0 classic level ALevel, 1 time attack, 2 survival; APolicy
  see PolicyNames; AMoveSecs = the player's time per move }
function SimSingle(AMode, ALevel, APolicy: Integer; AMoveSecs: Single; ASeed: Cardinal): TSimGame;
{ one VS BOT match of two bots (levels 0..2), at most AMaxSecs }
function SimVersus(ALevelA, ALevelB: Integer; ASeed: Cardinal; AMaxSecs: Single; ATimeline: Boolean): TVsSim;

implementation

function PickMove(G: TBeadGame; APolicy: Integer; out X, Y: Integer): Boolean;
var
  xx, yy, n, cnt, k, best: Integer;
  xs, ys, ns, good: array of Integer;
begin
  Result := False;
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
  if cnt = 0 then Exit;
  k := 0;
  case APolicy of
    0, 1:
      begin
        best := ns[0];
        for n := 1 to cnt - 1 do
          if ((APolicy = 0) and (ns[n] > best)) or ((APolicy = 1) and (ns[n] < best)) then
          begin
            best := ns[n];
            k := n;
          end;
      end;
    3:
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
    k := Random(cnt);
  end;
  X := xs[k];
  Y := ys[k];
  Result := True;
end;

function SimSingle(AMode, ALevel, APolicy: Integer; AMoveSecs: Single; ASeed: Cardinal): TSimGame;
var
  G: TBeadGame;
  t, wait: Double;
  x, y, sumGroup: Integer;
  steps: Integer;
begin
  Result := Default(TSimGame);
  RandSeed := ASeed;
  G := TBeadGame.Create;
  try
    G.Reseed(ASeed);
    case AMode of
      1: G.StartTimeAttack;
      2: G.StartSurvival;
    else
      G.StartLevel(Max(1, ALevel), False);
    end;
    t := 0;
    wait := AMoveSecs;
    sumGroup := 0;
    steps := 0;
    while (G.State <> gsGameOver) and (G.State <> gsLevelDone) and (t < 3600) and (steps < 200000) do
    begin
      Inc(steps);
      G.Update(SimDt);
      t += SimDt;
      SetLength(G.FxEvents, 0);
      SetLength(G.Popups, 0);
      if G.State <> gsPlaying then Continue;
      wait -= SimDt;
      if wait > 0 then Continue;
      if PickMove(G, APolicy, x, y) then
      begin
        sumGroup += G.GroupSize(x, y);
        G.SetMouseCell(x, y);
        G.Click;
        G.SetMouseCell(-1, -1);
        Inc(Result.Pops);
      end;
      wait := AMoveSecs;
    end;
    Result.Score := G.Score;
    Result.MaxGroup := G.MaxGroup;
    Result.Stars := G.Stars;
    Result.Bonus := G.Bonus;
    Result.Specials := G.BombsUsed + G.LinesUsed;
    Result.Iron := G.IronGained;
    Result.Boards := G.Boards;
    Result.Passed := G.State = gsLevelDone;
    Result.Seconds := t;
    if Result.Pops > 0 then Result.AvgGroup := sumGroup / Result.Pops;
  finally
    G.Free;
  end;
end;

function SimVersus(ALevelA, ALevelB: Integer; ASeed: Cardinal; AMaxSecs: Single; ATimeline: Boolean): TVsSim;
var
  A, B: TBeadGame;
  ba, bb: TBeadBot;
  t, nextS: Double;
  n: Integer;
begin
  Result := Default(TVsSim);
  RandSeed := ASeed;
  A := TBeadGame.Create;
  B := TBeadGame.Create;
  ba := TBeadBot.Create(ALevelA);
  bb := TBeadBot.Create(ALevelB);
  try
    A.Reseed(ASeed);
    A.StartRun(gmVersus);
    B.Reseed(ASeed * 7919 + 13);
    B.StartRun(gmVersus);
    ba.Reset(1.2);
    bb.Reset(1.2);
    t := 0;
    nextS := 0;
    while (A.VsResult = 0) and (t < AMaxSecs) do
    begin
      A.Update(SimDt);
      B.Update(SimDt);
      ba.Step(A, SimDt);
      bb.Step(B, SimDt);
      VersusExchange(A, B);
      SetLength(A.FxEvents, 0);
      SetLength(B.FxEvents, 0);
      SetLength(A.Popups, 0);
      SetLength(B.Popups, 0);
      t += SimDt;
      if A.VsIronOn then Result.IronOnSecs += SimDt;
      if A.VsLead > 0 then Result.LeadASecs += SimDt;
      if A.VsLead < 0 then Result.LeadBSecs += SimDt;
      if ATimeline and (t >= nextS) then
      begin
        n := Length(Result.Timeline);
        SetLength(Result.Timeline, n + 1);
        Result.Timeline[n].T := t;
        Result.Timeline[n].A := A.Score;
        Result.Timeline[n].B := B.Score;
        nextS := t + 0.5;
      end;
    end;
    Result.Winner := A.VsResult;
    Result.ScoreA := A.Score;
    Result.ScoreB := B.Score;
    Result.SentA := A.IronSent;
    Result.SentB := B.IronSent;
    Result.MovesA := ba.Moves;
    Result.MovesB := bb.Moves;
    Result.Seconds := t;
  finally
    ba.Free;
    bb.Free;
    A.Free;
    B.Free;
  end;
end;

end.
