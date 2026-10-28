unit uBeadRules;

{ Neon Beads rules that can be edited: the scoring of a move (group size,
  blasts, stones, x2, arrangement bonuses), the rewards, the level / board
  bonuses and stars, time attack, survival (NeonBeads.scoring) and the
  VS BOT rules (iron attacks, the score gap, stalling, the board, the bot;
  NeonBeads.versus). Both are INI text next to the game; the defaults are the
  original rules. The game reloads them while it runs; the editors are
  NeonScoreEditor and NeonVsEditor (NeonGrid SDL3 GPU Tools), which can
  also simulate games with them (uBeadSim).

  Every value is a Single in SR[] (scoring) or VR[] (versus), described by
  ScoreRules / VsRules (key, caption, group, hint, range, default, integer).
  The old constants of uBeadGame (TimeAttackSecs, ChainWindow, ...) are
  functions here that read the current values. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, IniFiles;

type
  TRuleInfo = record
    Key, Caption, Group, Hint: string;
    Min, Max, Def: Single;
    IsInt: Boolean;
  end;
  TRuleKind = (rkScoring, rkVersus);

const
  { ---- scoring (SR) }
  srPerPair = 0;
  srPerBead = 1;
  srBlastBead = 2;
  srStoneBead = 3;
  srDoubleMult = 4;
  srStraightMin = 5;
  srStraightBonus = 6;
  srBlockBonus = 7;
  srBigSize = 8;
  srBigBonus = 9;
  srMultiBlast = 10;
  srRewardBomb = 11;
  srRewardLine = 12;
  srRewardRainbow = 13;
  srGoalBead = 14;
  srClearBonus = 15;
  srStar3 = 16;
  srStar2 = 17;
  srTimeSecs = 18;
  srChainStep = 19;
  srChainMax = 20;
  srChainWindow = 21;
  srTime1Size = 22;
  srTime2Size = 23;
  srTime3Size = 24;
  srTimePerSpecial = 25;
  srBoardClear = 26;
  srBoardLeftBase = 27;
  srBoardLeftPts = 28;
  srIronPair = 29;
  srIronTriple = 30;
  srBonus1 = 31;
  srBonus2 = 32;
  srBonus3 = 33;
  srBonus4 = 34;
  srBonus5 = 35;
  ScoreRuleCount = 36;

  ScoreRules: array[0..ScoreRuleCount - 1] of TRuleInfo = (
    (Key: 'PointsPerPair'; Caption: 'Points x n(n-1)'; Group: 'Group points';
      Hint: 'a group of n beads scores n x (n - 1) x this'; Min: 0; Max: 50; Def: 5; IsInt: False),
    (Key: 'PointsPerBead'; Caption: 'Points per bead'; Group: 'Group points';
      Hint: 'plus this for every bead of the group'; Min: 0; Max: 200; Def: 0; IsInt: False),
    (Key: 'BlastBead'; Caption: 'Blast bead'; Group: 'Group points';
      Hint: 'points for every bead a bomb / line takes with it'; Min: 0; Max: 300; Def: 20; IsInt: False),
    (Key: 'StoneBead'; Caption: 'Stone broken'; Group: 'Group points';
      Hint: 'points for every stone a blast breaks'; Min: 0; Max: 300; Def: 30; IsInt: False),
    (Key: 'DoubleMult'; Caption: 'x2 bead multiplier'; Group: 'Group points';
      Hint: 'a move with an x2 bead in it scores this many times'; Min: 1; Max: 5; Def: 2; IsInt: False),
    (Key: 'StraightMin'; Caption: 'Straight line: length'; Group: 'Arrangement bonus';
      Hint: 'a group lying in one row or one column with at least this many beads'; Min: 2; Max: 18; Def: 4; IsInt: True),
    (Key: 'StraightBonus'; Caption: 'Straight line: per bead'; Group: 'Arrangement bonus';
      Hint: 'bonus per bead of a straight-line group (0 = off)'; Min: 0; Max: 300; Def: 0; IsInt: False),
    (Key: 'BlockBonus'; Caption: '2x2 block'; Group: 'Arrangement bonus';
      Hint: 'bonus for every full 2 x 2 square inside the group (0 = off)'; Min: 0; Max: 300; Def: 0; IsInt: False),
    (Key: 'BigSize'; Caption: 'Big group: size'; Group: 'Arrangement bonus';
      Hint: 'a group of at least this many beads gets the big bonus'; Min: 3; Max: 60; Def: 20; IsInt: True),
    (Key: 'BigBonus'; Caption: 'Big group: bonus'; Group: 'Arrangement bonus';
      Hint: 'flat bonus for a big group (0 = off)'; Min: 0; Max: 5000; Def: 0; IsInt: False),
    (Key: 'MultiBlast'; Caption: 'Chain blast'; Group: 'Arrangement bonus';
      Hint: 'bonus for every special set off after the first in one move (0 = off)'; Min: 0; Max: 2000; Def: 0; IsInt: False),
    (Key: 'RewardBomb'; Caption: 'Bomb from a group of'; Group: 'Rewards (classic)';
      Hint: 'a group this big leaves a bomb (0 = never)'; Min: 0; Max: 60; Def: 8; IsInt: True),
    (Key: 'RewardLine'; Caption: 'Line from a group of'; Group: 'Rewards (classic)';
      Hint: 'a group this big leaves a line bead (0 = never)'; Min: 0; Max: 60; Def: 11; IsInt: True),
    (Key: 'RewardRainbow'; Caption: 'Rainbow from a group of'; Group: 'Rewards (classic)';
      Hint: 'a group this big leaves a rainbow (0 = never)'; Min: 0; Max: 60; Def: 15; IsInt: True),
    (Key: 'GoalBead'; Caption: 'Per bead under the goal'; Group: 'Level end (classic)';
      Hint: 'bonus for every bead fewer than the goal'; Min: 0; Max: 500; Def: 50; IsInt: False),
    (Key: 'ClearBonus'; Caption: 'Board cleared'; Group: 'Level end (classic)';
      Hint: 'bonus for an empty board'; Min: 0; Max: 10000; Def: 1000; IsInt: False),
    (Key: 'Star3'; Caption: '3 stars: beads left <= goal x'; Group: 'Level end (classic)';
      Hint: 'three stars when the beads left are at most this part of the goal'; Min: 0; Max: 1; Def: 0.334; IsInt: False),
    (Key: 'Star2'; Caption: '2 stars: beads left <= goal x'; Group: 'Level end (classic)';
      Hint: 'two stars when the beads left are at most this part of the goal'; Min: 0; Max: 1; Def: 0.667; IsInt: False),
    (Key: 'Seconds'; Caption: 'Clock (seconds)'; Group: 'Time attack';
      Hint: 'length of a time attack game'; Min: 10; Max: 600; Def: 90; IsInt: True),
    (Key: 'ChainStep'; Caption: 'Chain step'; Group: 'Time attack';
      Hint: 'the points multiplier grows this much per chain step'; Min: 0; Max: 1; Def: 0.1; IsInt: False),
    (Key: 'ChainMax'; Caption: 'Chain stops at'; Group: 'Time attack';
      Hint: 'the multiplier stops growing at this chain'; Min: 1; Max: 50; Def: 11; IsInt: True),
    (Key: 'ChainWindow'; Caption: 'Chain window (s)'; Group: 'Time attack';
      Hint: 'seconds after a board settles to keep a chain going'; Min: 0.2; Max: 5; Def: 1.2; IsInt: False),
    (Key: 'Time1Size'; Caption: '+1 s from a group of'; Group: 'Time attack';
      Hint: 'a group this big adds 1 second'; Min: 2; Max: 60; Def: 8; IsInt: True),
    (Key: 'Time2Size'; Caption: '+2 s from a group of'; Group: 'Time attack';
      Hint: 'a group this big adds 2 seconds'; Min: 2; Max: 60; Def: 12; IsInt: True),
    (Key: 'Time3Size'; Caption: '+3 s from a group of'; Group: 'Time attack';
      Hint: 'a group this big adds 3 seconds'; Min: 2; Max: 60; Def: 16; IsInt: True),
    (Key: 'TimePerSpecial'; Caption: 'Seconds per special'; Group: 'Time attack';
      Hint: 'extra seconds for every special set off'; Min: 0; Max: 10; Def: 1; IsInt: False),
    (Key: 'BoardClear'; Caption: 'Board cleared'; Group: 'Time attack';
      Hint: 'board bonus for an empty board'; Min: 0; Max: 10000; Def: 1000; IsInt: False),
    (Key: 'BoardLeftBase'; Caption: 'Board bonus: beads under'; Group: 'Time attack';
      Hint: 'a board ending with fewer beads than this gets points per bead under it'; Min: 0; Max: 200; Def: 30; IsInt: True),
    (Key: 'BoardLeftPts'; Caption: 'Board bonus: per bead'; Group: 'Time attack';
      Hint: 'points per bead under the line above'; Min: 0; Max: 500; Def: 20; IsInt: False),
    (Key: 'IronPair'; Caption: 'Iron from a pop of 2'; Group: 'Survival';
      Hint: 'iron beads the refill brings after a pop of 2'; Min: 0; Max: 5; Def: 2; IsInt: True),
    (Key: 'IronTriple'; Caption: 'Iron from a pop of 3'; Group: 'Survival';
      Hint: 'iron beads the refill brings after a pop of 3'; Min: 0; Max: 5; Def: 1; IsInt: True),
    (Key: 'Bonus1'; Caption: 'Bonus bead at'; Group: 'Survival';
      Hint: 'a pop this big brings a bonus special (0 = off)'; Min: 0; Max: 80; Def: 7; IsInt: True),
    (Key: 'Bonus2'; Caption: '2nd bonus at'; Group: 'Survival';
      Hint: 'a pop this big brings one more (0 = off)'; Min: 0; Max: 80; Def: 10; IsInt: True),
    (Key: 'Bonus3'; Caption: '3rd bonus at'; Group: 'Survival';
      Hint: 'a pop this big brings one more (0 = off)'; Min: 0; Max: 80; Def: 14; IsInt: True),
    (Key: 'Bonus4'; Caption: '4th bonus at'; Group: 'Survival';
      Hint: 'a pop this big brings one more (0 = off)'; Min: 0; Max: 80; Def: 19; IsInt: True),
    (Key: 'Bonus5'; Caption: '5th bonus at'; Group: 'Survival';
      Hint: 'a pop this big brings one more (0 = off)'; Min: 0; Max: 80; Def: 25; IsInt: True));

  { ---- VS BOT (VR) }
  vrAttack1 = 0;
  vrAttack2 = 1;
  vrAttack3 = 2;
  vrAttack4 = 3;
  vrIronGap = 4;
  vrLeaderRefill = 5;
  vrTrailerIron = 6;
  vrIdleSecs = 7;
  vrIdlePenalty = 8;
  vrIdleIron = 9;
  vrBoardW = 10;
  vrBoardH = 11;
  vrColours = 12;
  vrThink0 = 13;
  vrThink1 = 14;
  vrThink2 = 15;
  vrAim0 = 16;
  vrAim1 = 17;
  vrAim2 = 18;
  vrNormalMin = 19;
  vrNormalCareless = 20;
  VsRuleCount = 21;

  VsRules: array[0..VsRuleCount - 1] of TRuleInfo = (
    (Key: 'Attack1'; Caption: '1 iron from a pop of'; Group: 'Iron attacks';
      Hint: 'a pop this big sends 1 iron to the other board (0 = off)'; Min: 0; Max: 80; Def: 9; IsInt: True),
    (Key: 'Attack2'; Caption: '2 iron from a pop of'; Group: 'Iron attacks';
      Hint: 'one more iron (0 = off)'; Min: 0; Max: 80; Def: 12; IsInt: True),
    (Key: 'Attack3'; Caption: '3 iron from a pop of'; Group: 'Iron attacks';
      Hint: 'one more iron (0 = off)'; Min: 0; Max: 80; Def: 17; IsInt: True),
    (Key: 'Attack4'; Caption: '4 iron from a pop of'; Group: 'Iron attacks';
      Hint: 'one more iron (0 = off)'; Min: 0; Max: 80; Def: 23; IsInt: True),
    (Key: 'IronGap'; Caption: 'Iron works above a gap of'; Group: 'Score gap';
      Hint: 'iron only works while the scores differ by more than this (0 = always)'; Min: 0; Max: 10000; Def: 600; IsInt: True),
    (Key: 'LeaderRefill'; Caption: 'Leader''s 2-3 pops: iron to the other'; Group: 'Score gap';
      Hint: '1 = the iron of the leader''s small pops lands on the other board, 0 = none'; Min: 0; Max: 1; Def: 1; IsInt: True),
    (Key: 'TrailerIron'; Caption: 'Side behind makes iron'; Group: 'Score gap';
      Hint: '1 = the side behind may attack too, 0 = only the leader makes iron'; Min: 0; Max: 1; Def: 0; IsInt: True),
    (Key: 'IdleSecs'; Caption: 'Stalling after (s)'; Group: 'Stalling';
      Hint: 'seconds without a pop before the penalty (0 = off)'; Min: 0; Max: 60; Def: 6; IsInt: False),
    (Key: 'IdlePenalty'; Caption: 'Points lost'; Group: 'Stalling';
      Hint: 'points a stalling side loses'; Min: 0; Max: 2000; Def: 100; IsInt: True),
    (Key: 'IdleIron'; Caption: 'Iron on own board'; Group: 'Stalling';
      Hint: 'iron a stalling side gets on its own board (0 = none, the old rule was 1)'; Min: 0; Max: 5; Def: 0; IsInt: True),
    (Key: 'BoardW'; Caption: 'Board width'; Group: 'Board';
      Hint: 'columns of each VS board'; Min: 6; Max: 14; Def: 10; IsInt: True),
    (Key: 'BoardH'; Caption: 'Board height'; Group: 'Board';
      Hint: 'rows of each VS board'; Min: 8; Max: 18; Def: 14; IsInt: True),
    (Key: 'Colours'; Caption: 'Colours'; Group: 'Board';
      Hint: 'bead colours on the VS boards'; Min: 3; Max: 6; Def: 5; IsInt: True),
    (Key: 'ThinkEasy'; Caption: 'EASY: think (s)'; Group: 'Bot';
      Hint: 'average seconds the EASY bot thinks before a move'; Min: 0.1; Max: 6; Def: 1.8; IsInt: False),
    (Key: 'ThinkNormal'; Caption: 'NORMAL: think (s)'; Group: 'Bot';
      Hint: 'average seconds the NORMAL bot thinks'; Min: 0.1; Max: 6; Def: 1.15; IsInt: False),
    (Key: 'ThinkHard'; Caption: 'HARD: think (s)'; Group: 'Bot';
      Hint: 'average seconds the HARD bot thinks'; Min: 0.1; Max: 6; Def: 0.7; IsInt: False),
    (Key: 'AimEasy'; Caption: 'EASY: aim (s)'; Group: 'Bot';
      Hint: 'seconds the EASY bot shows its move before the click'; Min: 0; Max: 3; Def: 0.45; IsInt: False),
    (Key: 'AimNormal'; Caption: 'NORMAL: aim (s)'; Group: 'Bot';
      Hint: 'seconds the NORMAL bot shows its move'; Min: 0; Max: 3; Def: 0.3; IsInt: False),
    (Key: 'AimHard'; Caption: 'HARD: aim (s)'; Group: 'Bot';
      Hint: 'seconds the HARD bot shows its move'; Min: 0; Max: 3; Def: 0.18; IsInt: False),
    (Key: 'NormalMin'; Caption: 'NORMAL: prefers groups of'; Group: 'Bot';
      Hint: 'the NORMAL bot mostly takes groups at least this big'; Min: 2; Max: 20; Def: 4; IsInt: True),
    (Key: 'NormalCareless'; Caption: 'NORMAL: careless'; Group: 'Bot';
      Hint: 'how often the NORMAL bot takes any move (0..1)'; Min: 0; Max: 1; Def: 0.2; IsInt: False));

var
  SR: array[0..ScoreRuleCount - 1] of Single;
  VR: array[0..VsRuleCount - 1] of Single;
  RulesStamp: Integer = 0;   // changes when rules are loaded

function RuleCount(AKind: TRuleKind): Integer;
function RuleInfo(AKind: TRuleKind; AIndex: Integer): TRuleInfo;
function GetRule(AKind: TRuleKind; AIndex: Integer): Single;
procedure SetRule(AKind: TRuleKind; AIndex: Integer; AValue: Single);
procedure DefaultRules(AKind: TRuleKind);
function LoadRulesFile(AKind: TRuleKind; const AFile: string): Boolean;
procedure SaveRulesFile(AKind: TRuleKind; const AFile: string);
function RulesExt(AKind: TRuleKind): string;   // '.scoring' / '.versus'

{ the former constants of uBeadGame }
function TimeAttackSecs: Integer;
function ChainWindow: Single;
function MaxChainMult: Integer;
function VsIdleSecs: Single;
function VsIdlePenalty: Integer;
function VsIronGap: Integer;
function SRI(AIndex: Integer): Integer;
function VRI(AIndex: Integer): Integer;

implementation

var
  FS: TFormatSettings;

const
  Sections: array[TRuleKind] of string = ('Scoring', 'Versus');

function RuleCount(AKind: TRuleKind): Integer;
begin
  if AKind = rkScoring then Result := ScoreRuleCount else Result := VsRuleCount;
end;

function RuleInfo(AKind: TRuleKind; AIndex: Integer): TRuleInfo;
begin
  if AKind = rkScoring then Result := ScoreRules[AIndex] else Result := VsRules[AIndex];
end;

function GetRule(AKind: TRuleKind; AIndex: Integer): Single;
begin
  if AKind = rkScoring then Result := SR[AIndex] else Result := VR[AIndex];
end;

procedure SetRule(AKind: TRuleKind; AIndex: Integer; AValue: Single);
var
  ri: TRuleInfo;
begin
  ri := RuleInfo(AKind, AIndex);
  AValue := EnsureRange(AValue, ri.Min, ri.Max);
  if ri.IsInt then AValue := Round(AValue);
  if AKind = rkScoring then SR[AIndex] := AValue else VR[AIndex] := AValue;
end;

procedure DefaultRules(AKind: TRuleKind);
var
  i: Integer;
begin
  for i := 0 to RuleCount(AKind) - 1 do SetRule(AKind, i, RuleInfo(AKind, i).Def);
  Inc(RulesStamp);
end;

function RulesExt(AKind: TRuleKind): string;
begin
  if AKind = rkScoring then Result := '.scoring' else Result := '.versus';
end;

function LoadRulesFile(AKind: TRuleKind; const AFile: string): Boolean;
var
  ini: TMemIniFile;
  i: Integer;
  ri: TRuleInfo;
begin
  Result := False;
  if not FileExists(AFile) then Exit;
  try
    ini := TMemIniFile.Create(AFile);
    try
      for i := 0 to RuleCount(AKind) - 1 do
      begin
        ri := RuleInfo(AKind, i);
        SetRule(AKind, i, StrToFloatDef(Trim(ini.ReadString(ri.Group, ri.Key, '')), ri.Def, FS));
      end;
    finally
      ini.Free;
    end;
    Result := True;
  except
    Result := False;
  end;
  Inc(RulesStamp);
end;

procedure SaveRulesFile(AKind: TRuleKind; const AFile: string);
var
  sl: TStringList;
  i: Integer;
  g: string;
  ri: TRuleInfo;
begin
  sl := TStringList.Create;
  try
    if AKind = rkScoring then
    begin
      sl.Add('; Neon Beads scoring rules - edit with NeonScoreEditor (NeonGrid SDL3 GPU Tools) or by hand.');
      sl.Add('; The game reloads this file while it runs. Missing values take the original rules.');
    end
    else
    begin
      sl.Add('; Neon Beads VS BOT rules - edit with NeonVsEditor (NeonGrid SDL3 GPU Tools) or by hand.');
      sl.Add('; The game reloads this file while it runs. Missing values take the original rules.');
    end;
    g := '';
    for i := 0 to RuleCount(AKind) - 1 do
    begin
      ri := RuleInfo(AKind, i);
      if ri.Group <> g then
      begin
        g := ri.Group;
        sl.Add('');
        sl.Add('[' + g + ']');
      end;
      sl.Add('; ' + ri.Caption + ': ' + ri.Hint + Format(' (%s .. %s, original %s)',
        [FormatFloat('0.###', ri.Min, FS), FormatFloat('0.###', ri.Max, FS), FormatFloat('0.###', ri.Def, FS)]));
      sl.Add(ri.Key + '=' + FormatFloat('0.###', GetRule(AKind, i), FS));
    end;
    sl.SaveToFile(AFile);
  finally
    sl.Free;
  end;
end;

function SRI(AIndex: Integer): Integer;
begin
  Result := Round(SR[AIndex]);
end;

function VRI(AIndex: Integer): Integer;
begin
  Result := Round(VR[AIndex]);
end;

function TimeAttackSecs: Integer;
begin
  Result := SRI(srTimeSecs);
end;

function ChainWindow: Single;
begin
  Result := SR[srChainWindow];
end;

function MaxChainMult: Integer;
begin
  Result := SRI(srChainMax);
end;

function VsIdleSecs: Single;
begin
  Result := VR[vrIdleSecs];
end;

function VsIdlePenalty: Integer;
begin
  Result := VRI(vrIdlePenalty);
end;

function VsIronGap: Integer;
begin
  Result := VRI(vrIronGap);
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  DefaultRules(rkScoring);
  DefaultRules(rkVersus);

end.
