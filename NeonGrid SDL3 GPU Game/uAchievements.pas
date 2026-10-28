unit uAchievements;

{ Neon Beads progression: achievements, high scores, stars, ranks, themes.

  - Achievements in 3 separate groups, unlocked from the game's statistics
    (uBeadGame): GENERAL (18, classic + time attack), SURVIVAL (9) and
    VS BOT (9); each group only counts games of its own mode.
  - Top-10 high-score tables, one per mode (CLASSIC, TIME ATTACK, SURVIVAL,
    VS BOT).
  - VS BOT wins (total and current streak).
  - Stars: the best result (1 - 3 stars) of every classic level.
  - XP: every point scored counts; XP raises the player rank
    (ROOKIE .. LEGEND).
  - Bead themes (colour palettes) unlock with the total number of stars.
  - The special beads seen so far (a hint card the first time).
  New unlocks are queued as toasts for the HUD. Everything is stored in
  NeonBeads.ini ([Achievements], [HighScores], [HighScoresTime], [Stars],
  [Progress]). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, IniFiles, Math, uBeadGame;

type
  TAchId = (achFirstPop, achBig10, achMega20, achSweep, achNoUndo, achBomb, achChainReaction,
    achRainbow, achStones, achLevel3, achLevel6, achLevel10, achStar3, achStars30, achSpeed,
    achChain5, achHighRoller, achTheme,
    { survival }
    achSvSurvivor, achSvEndurance, achSvMarathon, achSvIronFree, achSvIronWill, achSvBonus,
    achSvJackpot, achSv10k, achSv30k,
    { VS BOT }
    achVsEasy, achVsNormal, achVsHard, achVsIronMail, achVsHeavyMetal, achVsAvalanche,
    achVsUntouchable, achVsStreak, achVsVeteran);

  TAchInfo = record
    Name, Desc: string;
  end;

  TToast = record
    Title, Text: string;
    R, G, B: Byte;
    Age: Single;
  end;

  TScoreRow = record
    Name: string;
    Score, Level: Integer;     // classic: level reached, time attack: boards, survival: pops, VS: bot level
    Date: string;
  end;

const
  MaxScores = 10;
  MaxNameLen = 12;
  RankCount = 11;
  RankNames: array[0..RankCount - 1] of string = ('ROOKIE', 'SPARK', 'GLOW', 'SHINE', 'FLARE',
    'BLAZE', 'NEON', 'PRISM', 'NOVA', 'SUPERNOVA', 'LEGEND');
  AchGroups = 3;
  AchGroupNames: array[0..AchGroups - 1] of string = ('GENERAL', 'SURVIVAL', 'VS BOT');
  ThemeCount = 5;
  ThemeNames: array[0..ThemeCount - 1] of string = ('NEON', 'PASTEL', 'FIRE', 'OCEAN', 'CANDY');
  ThemeStars: array[0..ThemeCount - 1] of Integer = (0, 8, 18, 30, 45);

var
  { bead colours of the themes (defaults; the values come from NeonBeads.visuals) }
  ThemeRGB: array[0..ThemeCount - 1, 0..MaxColours - 1, 0..2] of Byte = (
    ((245, 150, 35), (35, 215, 240), (230, 40, 145), (150, 230, 55), (150, 75, 240), (245, 55, 55)),
    ((255, 185, 120), (130, 215, 255), (255, 150, 205), (175, 240, 150), (195, 165, 255), (255, 125, 125)),
    ((255, 210, 40), (255, 120, 20), (225, 30, 30), (255, 80, 150), (170, 35, 95), (255, 245, 170)),
    ((25, 195, 255), (40, 105, 255), (0, 225, 170), (140, 255, 235), (135, 85, 255), (235, 250, 255)),
    ((255, 85, 180), (255, 220, 60), (90, 230, 255), (135, 255, 115), (200, 115, 255), (255, 140, 55)));

const
  AchInfo: array[TAchId] of TAchInfo = (
    (Name: 'FIRST POP'; Desc: 'pop your first group'),
    (Name: 'BIG GROUP'; Desc: 'pop 10 beads in one group'),
    (Name: 'MEGA GROUP'; Desc: 'pop 20 beads in one group'),
    (Name: 'CLEAN SWEEP'; Desc: 'clear a whole board'),
    (Name: 'NO TAKE-BACKS'; Desc: 'pass a level without undo'),
    (Name: 'BOMB SQUAD'; Desc: 'set off a bomb bead'),
    (Name: 'CHAIN REACTION'; Desc: '2 specials go off in one move'),
    (Name: 'RAINBOW BRIDGE'; Desc: 'pop a group with a rainbow'),
    (Name: 'STONE BREAKER'; Desc: 'break 10 stones in one game'),
    (Name: 'GETTING SERIOUS'; Desc: 'reach level 3'),
    (Name: 'BEAD MASTER'; Desc: 'reach level 6'),
    (Name: 'LEGEND'; Desc: 'reach level 10'),
    (Name: 'STAR STUDENT'; Desc: 'earn 3 stars on a level'),
    (Name: 'STAR COLLECTOR'; Desc: 'collect 30 stars'),
    (Name: 'SPEED DEMON'; Desc: '5,000 points in time attack'),
    (Name: 'CHAIN GANG'; Desc: 'a x5 chain in time attack'),
    (Name: 'HIGH ROLLER'; Desc: '20,000 points in one game'),
    (Name: 'NEW LOOK'; Desc: 'unlock a bead theme'),
    { survival }
    (Name: 'SURVIVOR'; Desc: 'survive 25 pops'),
    (Name: 'ENDURANCE'; Desc: 'survive 100 pops'),
    (Name: 'MARATHON'; Desc: 'survive 250 pops'),
    (Name: 'IRON-FREE'; Desc: '50 pops without any iron'),
    (Name: 'IRON WILL'; Desc: 'play on with 60 iron beads'),
    (Name: 'BONUS HUNTER'; Desc: 'earn 5 bonus beads in one run'),
    (Name: 'JACKPOT'; Desc: 'pop 25 beads in one move'),
    (Name: 'SURVIVAL 10K'; Desc: '10,000 points in survival'),
    (Name: 'SURVIVAL 30K'; Desc: '30,000 points in survival'),
    { VS BOT }
    (Name: 'BOT TAMER'; Desc: 'beat the EASY bot'),
    (Name: 'BOT BREAKER'; Desc: 'beat the NORMAL bot'),
    (Name: 'BOT DESTROYER'; Desc: 'beat the HARD bot'),
    (Name: 'IRON MAIL'; Desc: 'send iron to the bot'),
    (Name: 'HEAVY METAL'; Desc: 'send 10 iron in one match'),
    (Name: 'AVALANCHE'; Desc: 'send 4 iron in one move (23+)'),
    (Name: 'UNTOUCHABLE'; Desc: 'win without getting sent iron'),
    (Name: 'ON A ROLL'; Desc: 'win 3 matches in a row'),
    (Name: 'VETERAN'; Desc: 'win 10 matches'));

{ the group (0 general, 1 survival, 2 VS BOT) of an achievement }
function AchGroup(A: TAchId): Integer;

type
  TAchievements = class
  private
    FFile: string;
    FLastScore: Integer;
    FLastRank: Integer;
    procedure SaveAll;
    function SectionOf(AMode: TGameMode): string;
  public
    Unlocked: array[TAchId] of Boolean;
    Toasts: array of TToast;
    Scores: array[TGameMode] of array of TScoreRow;
    LevelStars: array of Integer;      // [level] = best stars (0 = not passed)
    XP: Int64;
    Theme: Integer;
    Seen: Integer;                     // bit set of special kinds already explained
    VsWins, VsStreak: Integer;         // VS BOT wins: total, in a row
    constructor Create(const AIniFile: string);
    procedure AddToast(const ATitle, AText: string; R, G, B: Byte);
    { unlocks what the game reached, adds the XP of new points; True = something new }
    function Check(G: TBeadGame): Boolean;
    procedure UpdateToasts(dt: Single);
    function UnlockedCount: Integer;
    function UnlockedIn(AGroup: Integer): Integer;
    function CountIn(AGroup: Integer): Integer;
    { a finished VS BOT match (wins, streak) }
    procedure RecordVersus(AWon: Boolean);
    function TotalStars: Integer;
    function StarsOf(ALevel: Integer): Integer;
    { stores a passed classic level; True when it beat the old stars }
    function RecordLevel(ALevel, AStars: Integer): Boolean;
    function Rank: Integer;
    function RankXP(ARank: Integer): Int64;   // XP needed for a rank
    function ThemeUnlocked(AIndex: Integer): Boolean;
    procedure ApplyTheme(AIndex: Integer);
    procedure ResetScoreWatch(AScore: Integer);
    { the place (0..9) the score would take in the table, or -1 }
    function ScoreRank(AMode: TGameMode; AScore: Integer): Integer;
    { inserts a row, saves, returns its place (or -1) }
    function AddScore(AMode: TGameMode; const AName: string; AScore, ALevel: Integer): Integer;
    procedure Save;
  end;

implementation

function AchGroup(A: TAchId): Integer;
begin
  if A >= achVsEasy then Result := 2
  else if A >= achSvSurvivor then Result := 1
  else Result := 0;
end;

constructor TAchievements.Create(const AIniFile: string);
var
  ini: TIniFile;
  a: TAchId;
  i, n: Integer;
  m: TGameMode;
  parts: TStringList;
begin
  inherited Create;
  FFile := AIniFile;
  ini := TIniFile.Create(FFile);
  parts := TStringList.Create;
  try
    for a := Low(TAchId) to High(TAchId) do
      Unlocked[a] := ini.ReadBool('Achievements', AchInfo[a].Name, False);
    { rows: "score|level|date|name" }
    parts.Delimiter := '|';
    parts.StrictDelimiter := True;
    for m := Low(TGameMode) to High(TGameMode) do
    begin
      n := 0;
      SetLength(Scores[m], MaxScores);
      for i := 1 to MaxScores do
      begin
        parts.DelimitedText := ini.ReadString(SectionOf(m), 'Row' + IntToStr(i), '');
        if parts.Count < 4 then Continue;
        Scores[m][n].Score := StrToIntDef(parts[0], 0);
        Scores[m][n].Level := StrToIntDef(parts[1], 1);
        Scores[m][n].Date := parts[2];
        Scores[m][n].Name := Copy(parts[3], 1, MaxNameLen);
        if Scores[m][n].Score > 0 then Inc(n);
      end;
      SetLength(Scores[m], n);
    end;
    SetLength(LevelStars, 1);
    for i := 1 to 200 do
    begin
      n := ini.ReadInteger('Stars', 'L' + IntToStr(i), 0);
      if n > 0 then
      begin
        if Length(LevelStars) <= i then SetLength(LevelStars, i + 1);
        LevelStars[i] := EnsureRange(n, 0, 3);
      end;
    end;
    XP := ini.ReadInt64('Progress', 'XP', 0);
    Seen := ini.ReadInteger('Progress', 'SeenSpecials', 0);
    VsWins := ini.ReadInteger('Progress', 'VsWins', 0);
    VsStreak := ini.ReadInteger('Progress', 'VsStreak', 0);
    Theme := EnsureRange(ini.ReadInteger('Progress', 'Theme', 0), 0, ThemeCount - 1);
  finally
    parts.Free;
    ini.Free;
  end;
  if not ThemeUnlocked(Theme) then Theme := 0;
  ApplyTheme(Theme);
  FLastRank := Rank;
end;

function TAchievements.SectionOf(AMode: TGameMode): string;
begin
  case AMode of
    gmTime: Result := 'HighScoresTime';
    gmSurvival: Result := 'HighScoresSurvival';
    gmVersus: Result := 'HighScoresVersus';
  else
    Result := 'HighScores';
  end;
end;

procedure TAchievements.SaveAll;
var
  ini: TIniFile;
  a: TAchId;
  i: Integer;
  m: TGameMode;
begin
  try
    ini := TIniFile.Create(FFile);
    try
      for a := Low(TAchId) to High(TAchId) do
        ini.WriteBool('Achievements', AchInfo[a].Name, Unlocked[a]);
      for m := Low(TGameMode) to High(TGameMode) do
      begin
        ini.EraseSection(SectionOf(m));
        for i := 0 to High(Scores[m]) do
          ini.WriteString(SectionOf(m), 'Row' + IntToStr(i + 1), Format('%d|%d|%s|%s',
            [Scores[m][i].Score, Scores[m][i].Level, Scores[m][i].Date,
             StringReplace(Scores[m][i].Name, '|', ' ', [rfReplaceAll])]));
      end;
      for i := 1 to High(LevelStars) do
        if LevelStars[i] > 0 then ini.WriteInteger('Stars', 'L' + IntToStr(i), LevelStars[i]);
      ini.WriteInt64('Progress', 'XP', XP);
      ini.WriteInteger('Progress', 'SeenSpecials', Seen);
      ini.WriteInteger('Progress', 'VsWins', VsWins);
      ini.WriteInteger('Progress', 'VsStreak', VsStreak);
      ini.WriteInteger('Progress', 'Theme', Theme);
    finally
      ini.Free;
    end;
  except
    { a read-only folder only costs the saving }
  end;
end;

procedure TAchievements.Save;
begin
  SaveAll;
end;

procedure TAchievements.AddToast(const ATitle, AText: string; R, G, B: Byte);
var
  n: Integer;
begin
  n := Length(Toasts);
  SetLength(Toasts, n + 1);
  Toasts[n].Title := ATitle;
  Toasts[n].Text := AText;
  Toasts[n].R := R;
  Toasts[n].G := G;
  Toasts[n].B := B;
  { several at once: one after the other }
  if n > 0 then Toasts[n].Age := Min(0, Toasts[n - 1].Age - 0.5) else Toasts[n].Age := 0;
end;

function TAchievements.UnlockedIn(AGroup: Integer): Integer;
var
  a: TAchId;
begin
  Result := 0;
  for a := Low(TAchId) to High(TAchId) do
    if (AchGroup(a) = AGroup) and Unlocked[a] then Inc(Result);
end;

function TAchievements.CountIn(AGroup: Integer): Integer;
var
  a: TAchId;
begin
  Result := 0;
  for a := Low(TAchId) to High(TAchId) do
    if AchGroup(a) = AGroup then Inc(Result);
end;

procedure TAchievements.RecordVersus(AWon: Boolean);
begin
  if AWon then
  begin
    Inc(VsWins);
    Inc(VsStreak);
  end
  else
    VsStreak := 0;
  SaveAll;
end;

procedure TAchievements.ResetScoreWatch(AScore: Integer);
begin
  FLastScore := AScore;
end;

function TAchievements.Check(G: TBeadGame): Boolean;
var
  changed, achNew, gen, sv, vs: Boolean;
  k, best3: Integer;

  procedure Test(A: TAchId; ACond: Boolean);
  begin
    if Unlocked[A] or not ACond then Exit;
    Unlocked[A] := True;
    case AchGroup(A) of
      1: AddToast('SURVIVAL ACHIEVEMENT', AchInfo[A].Name, 255, 215, 90);
      2: AddToast('VS BOT ACHIEVEMENT', AchInfo[A].Name, 255, 215, 90);
    else
      AddToast('ACHIEVEMENT UNLOCKED', AchInfo[A].Name, 255, 215, 90);
    end;
    changed := True;
    achNew := True;
  end;

begin
  Result := False;
  changed := False;
  achNew := False;
  if G.State = gsTitle then
  begin
    FLastScore := 0;
    Exit;
  end;
  { XP: every new point }
  if G.Score > FLastScore then
  begin
    XP += G.Score - FLastScore;
    k := Rank;
    if k > FLastRank then
    begin
      AddToast('RANK UP!', Format('RANK %d  ·  %s', [k + 1, RankNames[k]]), 70, 220, 240);
      changed := True;
    end;
    FLastRank := k;
  end;
  FLastScore := G.Score;

  best3 := 0;
  for k := 1 to High(LevelStars) do
    if LevelStars[k] = 3 then Inc(best3);
  { every group of achievements only counts the games of its own mode }
  gen := G.Mode in [gmClassic, gmTime];
  sv := G.Mode = gmSurvival;
  vs := G.Mode = gmVersus;
  Test(achFirstPop, gen and (G.Pops >= 1));
  Test(achBig10, gen and (G.MaxGroup >= 10));
  Test(achMega20, gen and (G.MaxGroup >= 20));
  Test(achSweep, gen and (G.BoardsCleared >= 1));
  Test(achNoUndo, gen and (G.NoUndoClears >= 1));
  Test(achBomb, gen and (G.BombsUsed >= 1));
  Test(achChainReaction, gen and (G.MaxSpecialsInMove >= 2));
  Test(achRainbow, gen and (G.RainbowGroups >= 1));
  Test(achStones, gen and (G.StonesBroken >= 10));
  Test(achLevel3, (G.Mode = gmClassic) and (G.Level >= 3));
  Test(achLevel6, (G.Mode = gmClassic) and (G.Level >= 6));
  Test(achLevel10, (G.Mode = gmClassic) and (G.Level >= 10));
  Test(achStar3, best3 >= 1);
  Test(achStars30, TotalStars >= 30);
  Test(achSpeed, (G.Mode = gmTime) and (G.Score >= 5000));
  Test(achChain5, gen and (G.MaxChain >= 5));
  Test(achHighRoller, (G.Mode = gmClassic) and (G.Score >= 20000));
  Test(achTheme, TotalStars >= ThemeStars[1]);
  { survival }
  Test(achSvSurvivor, sv and (G.Pops >= 25));
  Test(achSvEndurance, sv and (G.Pops >= 100));
  Test(achSvMarathon, sv and (G.Pops >= 250));
  Test(achSvIronFree, sv and (G.Pops >= 50) and (G.IronGained = 0));
  Test(achSvIronWill, sv and (G.State <> gsGameOver) and (G.IronCount >= 60));
  Test(achSvBonus, sv and (G.BonusGained >= 5));
  Test(achSvJackpot, sv and (G.MaxPopCount >= 25));
  Test(achSv10k, sv and (G.Score >= 10000));
  Test(achSv30k, sv and (G.Score >= 30000));
  { VS BOT }
  Test(achVsEasy, vs and G.VsWon and (G.VsBotLevel >= 0));
  Test(achVsNormal, vs and G.VsWon and (G.VsBotLevel >= 1));
  Test(achVsHard, vs and G.VsWon and (G.VsBotLevel >= 2));
  Test(achVsIronMail, vs and (G.IronSent >= 1));
  Test(achVsHeavyMetal, vs and (G.IronSent >= 10));
  Test(achVsAvalanche, vs and (G.MaxAttack >= 4));
  Test(achVsUntouchable, vs and G.VsWon and (G.IronReceived = 0));
  Test(achVsStreak, vs and (VsStreak >= 3));
  Test(achVsVeteran, vs and (VsWins >= 10));
  if achNew then SaveAll;
  Result := changed;
end;

procedure TAchievements.UpdateToasts(dt: Single);
const
  MaxShown = 3;    // the rest wait their turn
var
  i, j: Integer;
begin
  j := 0;
  for i := 0 to High(Toasts) do
  begin
    if (i < MaxShown) or (Toasts[i].Age < 0) then Toasts[i].Age += dt;
    if (i >= MaxShown) and (Toasts[i].Age > 0) then Toasts[i].Age := 0;
    if Toasts[i].Age < 4 then
    begin
      Toasts[j] := Toasts[i];
      Inc(j);
    end;
  end;
  SetLength(Toasts, j);
end;

function TAchievements.UnlockedCount: Integer;
var
  a: TAchId;
begin
  Result := 0;
  for a := Low(TAchId) to High(TAchId) do
    if Unlocked[a] then Inc(Result);
end;

function TAchievements.TotalStars: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to High(LevelStars) do Result += LevelStars[i];
end;

function TAchievements.StarsOf(ALevel: Integer): Integer;
begin
  if (ALevel < 1) or (ALevel > High(LevelStars)) then Exit(0);
  Result := LevelStars[ALevel];
end;

function TAchievements.RecordLevel(ALevel, AStars: Integer): Boolean;
var
  before, i: Integer;
begin
  Result := AStars > StarsOf(ALevel);
  if not Result then Exit;
  before := TotalStars;
  if Length(LevelStars) <= ALevel then SetLength(LevelStars, ALevel + 1);
  LevelStars[ALevel] := AStars;
  { themes unlocked by the new stars }
  for i := 1 to ThemeCount - 1 do
    if (before < ThemeStars[i]) and (TotalStars >= ThemeStars[i]) then
      AddToast('NEW BEAD THEME', ThemeNames[i] + '  (choose it in OPTIONS)', 245, 90, 190);
  SaveAll;
end;

function TAchievements.RankXP(ARank: Integer): Int64;
begin
  { 4000, 12000, 24000, 40000, ... 220000 for LEGEND }
  Result := Int64(4000) * ARank * (ARank + 1) div 2;
end;

function TAchievements.Rank: Integer;
begin
  Result := 0;
  while (Result < RankCount - 1) and (XP >= RankXP(Result + 1)) do Inc(Result);
end;

function TAchievements.ThemeUnlocked(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < ThemeCount) and (TotalStars >= ThemeStars[AIndex]);
end;

procedure TAchievements.ApplyTheme(AIndex: Integer);
var
  c, k: Integer;
begin
  Theme := EnsureRange(AIndex, 0, ThemeCount - 1);
  for c := 0 to MaxColours - 1 do
    for k := 0 to 2 do BeadRGB[c, k] := ThemeRGB[Theme, c, k];
end;

function TAchievements.ScoreRank(AMode: TGameMode; AScore: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  if AScore <= 0 then Exit;
  for i := 0 to High(Scores[AMode]) do
    if AScore > Scores[AMode][i].Score then Exit(i);
  if Length(Scores[AMode]) < MaxScores then Result := Length(Scores[AMode]);
end;

function TAchievements.AddScore(AMode: TGameMode; const AName: string; AScore, ALevel: Integer): Integer;
var
  i, n: Integer;
begin
  Result := ScoreRank(AMode, AScore);
  if Result < 0 then Exit;
  n := Min(MaxScores, Length(Scores[AMode]) + 1);
  SetLength(Scores[AMode], n);
  for i := n - 1 downto Result + 1 do Scores[AMode][i] := Scores[AMode][i - 1];
  Scores[AMode][Result].Name := Trim(Copy(AName, 1, MaxNameLen));
  if Scores[AMode][Result].Name = '' then Scores[AMode][Result].Name := 'PLAYER';
  Scores[AMode][Result].Score := AScore;
  Scores[AMode][Result].Level := ALevel;
  Scores[AMode][Result].Date := FormatDateTime('yyyy-mm-dd', Now);
  SaveAll;
end;

end.
