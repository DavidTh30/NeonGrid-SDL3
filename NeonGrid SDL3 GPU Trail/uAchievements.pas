unit uAchievements;

{ Neon Trail achievements and the top-10 high-score table.

  TAchievements.Check looks at the game's statistics (uTrailGame) and
  unlocks what was reached; new unlocks are queued as toasts for the HUD.
  Both lists are stored in NeonTrail.ini ([Achievements], [HighScores]). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, IniFiles, Math, uTrailGame;

type
  TAchId = (achFirstSpark, achCombo5, achCombo10, achGolden, achGoldRush, achLong30, achLong60,
    achLevel3, achLevel6, achLevel10, achGhost, achFlawless, achShield, achPowers, achHighRoller);

  TAchInfo = record
    Name, Desc: string;
  end;

  TToast = record
    Id: TAchId;
    Age: Single;
  end;

  TScoreRow = record
    Name: string;
    Score, Level: Integer;
    Date: string;
  end;

const
  MaxScores = 10;
  MaxNameLen = 12;
  AchInfo: array[TAchId] of TAchInfo = (
    (Name: 'FIRST SPARK'; Desc: 'eat your first sparkle'),
    (Name: 'COMBO STARTER'; Desc: 'reach a x5 combo'),
    (Name: 'COMBO MASTER'; Desc: 'reach a x10 combo'),
    (Name: 'GOLDEN TOUCH'; Desc: 'catch a golden bead'),
    (Name: 'GOLD RUSH'; Desc: '5 golden beads in one game'),
    (Name: 'LONG TRAIL'; Desc: 'grow a trail of 30 beads'),
    (Name: 'NEON SERPENT'; Desc: 'grow a trail of 60 beads'),
    (Name: 'GETTING SERIOUS'; Desc: 'reach level 3'),
    (Name: 'MAZE RUNNER'; Desc: 'reach level 6'),
    (Name: 'LEGEND'; Desc: 'reach level 10'),
    (Name: 'GHOST WALKER'; Desc: 'ghost through your own trail'),
    (Name: 'FLAWLESS'; Desc: 'clear a level with no crash'),
    (Name: 'SAVED BY THE SHIELD'; Desc: 'a shield absorbs a crash'),
    (Name: 'POWER COLLECTOR'; Desc: 'all 6 power-ups in one game'),
    (Name: 'HIGH ROLLER'; Desc: '5,000 points in one game'));

type
  TAchievements = class
  private
    FFile: string;
    procedure Save;
  public
    Unlocked: array[TAchId] of Boolean;
    Toasts: array of TToast;
    Scores: array of TScoreRow;
    constructor Create(const AIniFile: string);
    { unlocks what the game reached; returns True when something new }
    function Check(G: TTrailGame): Boolean;
    procedure UpdateToasts(dt: Single);
    function UnlockedCount: Integer;
    { the place (0..9) the score would take in the table, or -1 }
    function ScoreRank(AScore: Integer): Integer;
    { inserts a row, saves, returns its place (or -1) }
    function AddScore(const AName: string; AScore, ALevel: Integer): Integer;
  end;

implementation

constructor TAchievements.Create(const AIniFile: string);
var
  ini: TIniFile;
  a: TAchId;
  i, n: Integer;
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
    n := 0;
    SetLength(Scores, MaxScores);
    for i := 1 to MaxScores do
    begin
      parts.Delimiter := '|';
      parts.StrictDelimiter := True;
      parts.DelimitedText := ini.ReadString('HighScores', 'Row' + IntToStr(i), '');
      if parts.Count < 4 then Continue;
      Scores[n].Score := StrToIntDef(parts[0], 0);
      Scores[n].Level := StrToIntDef(parts[1], 1);
      Scores[n].Date := parts[2];
      Scores[n].Name := Copy(parts[3], 1, MaxNameLen);
      if Scores[n].Score > 0 then Inc(n);
    end;
    SetLength(Scores, n);
  finally
    parts.Free;
    ini.Free;
  end;
end;

procedure TAchievements.Save;
var
  ini: TIniFile;
  a: TAchId;
  i: Integer;
begin
  try
    ini := TIniFile.Create(FFile);
    try
      for a := Low(TAchId) to High(TAchId) do
        ini.WriteBool('Achievements', AchInfo[a].Name, Unlocked[a]);
      ini.EraseSection('HighScores');
      for i := 0 to High(Scores) do
        ini.WriteString('HighScores', 'Row' + IntToStr(i + 1), Format('%d|%d|%s|%s',
          [Scores[i].Score, Scores[i].Level, Scores[i].Date, StringReplace(Scores[i].Name, '|', ' ', [rfReplaceAll])]));
    finally
      ini.Free;
    end;
  except
    { a read-only folder only costs the saving }
  end;
end;

function TAchievements.Check(G: TTrailGame): Boolean;
var
  changed: Boolean;

  procedure Test(A: TAchId; ACond: Boolean);
  var
    n: Integer;
  begin
    if Unlocked[A] or not ACond then Exit;
    Unlocked[A] := True;
    n := Length(Toasts);
    SetLength(Toasts, n + 1);
    Toasts[n].Id := A;
    Toasts[n].Age := -0.4 * n;    // several at once: one after the other
    changed := True;
  end;

begin
  Result := False;
  changed := False;
  if G.Demo or (G.State = gsTitle) then Exit;
  Test(achFirstSpark, G.GameSparks >= 1);
  Test(achCombo5, G.MaxCombo >= 5);
  Test(achCombo10, G.MaxCombo >= 10);
  Test(achGolden, G.GameGold >= 1);
  Test(achGoldRush, G.GameGold >= 5);
  Test(achLong30, G.MaxLength >= 30);
  Test(achLong60, G.MaxLength >= 60);
  Test(achLevel3, G.Level >= 3);
  Test(achLevel6, G.Level >= 6);
  Test(achLevel10, G.Level >= 10);
  Test(achGhost, G.GhostPasses >= 1);
  Test(achFlawless, G.FlawlessClears >= 1);
  Test(achShield, G.ShieldSaves >= 1);
  Test(achPowers, G.PowersGot >= [pwSlow, pwGhost, pwMagnet, pwDouble, pwShrink, pwShield]);
  Test(achHighRoller, G.Score >= 5000);
  if changed then Save;
  Result := changed;
end;

procedure TAchievements.UpdateToasts(dt: Single);
var
  i, j: Integer;
begin
  j := 0;
  for i := 0 to High(Toasts) do
  begin
    Toasts[i].Age += dt;
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

function TAchievements.ScoreRank(AScore: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  if AScore <= 0 then Exit;
  for i := 0 to High(Scores) do
    if AScore > Scores[i].Score then Exit(i);
  if Length(Scores) < MaxScores then Result := Length(Scores);
end;

function TAchievements.AddScore(const AName: string; AScore, ALevel: Integer): Integer;
var
  i, n: Integer;
begin
  Result := ScoreRank(AScore);
  if Result < 0 then Exit;
  n := Min(MaxScores, Length(Scores) + 1);
  SetLength(Scores, n);
  for i := n - 1 downto Result + 1 do Scores[i] := Scores[i - 1];
  Scores[Result].Name := Trim(Copy(AName, 1, MaxNameLen));
  if Scores[Result].Name = '' then Scores[Result].Name := 'PLAYER';
  Scores[Result].Score := AScore;
  Scores[Result].Level := ALevel;
  Scores[Result].Date := FormatDateTime('yyyy-mm-dd', Now);
  Save;
end;

end.
