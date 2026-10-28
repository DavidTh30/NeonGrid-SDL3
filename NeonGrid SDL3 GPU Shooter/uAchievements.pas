unit uAchievements;

{ Neon Shooter achievements and the top-10 high-score table.

  TAchievements.Check looks at the game's statistics (uShooterGame) and
  unlocks what was reached; new unlocks are queued as toasts for the HUD.
  Both lists are stored in NeonShooter.ini ([Achievements], [HighScores]). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, IniFiles, Math, uShooterGame;

type
  TAchId = (achFirstPop, achBigPop, achMegaPop, achDrop5, achDrop15, achCombo3, achCombo6, achBank,
    achBank10, achBomb, achRainbow, achLevel3, achLevel6, achLevel10, achSurvivor, achHighRoller);

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
    (Name: 'FIRST POP'; Desc: 'pop your first group'),
    (Name: 'BIG POP'; Desc: 'pop 8 beads with one shot'),
    (Name: 'MEGA POP'; Desc: 'pop 15 beads with one shot'),
    (Name: 'AVALANCHE'; Desc: 'drop 5 beads at once'),
    (Name: 'LANDSLIDE'; Desc: 'drop 15 beads at once'),
    (Name: 'COMBO'; Desc: 'pop with 3 shots in a row'),
    (Name: 'COMBO KING'; Desc: 'pop with 6 shots in a row'),
    (Name: 'BANK SHOT'; Desc: 'pop after a bounce off the wall'),
    (Name: 'TRICK SHOOTER'; Desc: '10 bank-shot pops in one game'),
    (Name: 'DEMOLITION'; Desc: 'set off a bomb bead'),
    (Name: 'OVER THE RAINBOW'; Desc: 'shoot a rainbow bead'),
    (Name: 'GETTING SERIOUS'; Desc: 'reach level 3'),
    (Name: 'SHARPSHOOTER'; Desc: 'reach level 6'),
    (Name: 'LEGEND'; Desc: 'reach level 10'),
    (Name: 'UNDER PRESSURE'; Desc: 'survive 10 new rows in one game'),
    (Name: 'HIGH ROLLER'; Desc: '10,000 points in one game'));

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
    function Check(G: TShooterGame): Boolean;
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

function TAchievements.Check(G: TShooterGame): Boolean;
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
  Test(achFirstPop, G.GamePops >= MinMatch);
  Test(achBigPop, G.MaxGroup >= 8);
  Test(achMegaPop, G.MaxGroup >= 15);
  Test(achDrop5, G.MaxDrop >= 5);
  Test(achDrop15, G.MaxDrop >= 15);
  Test(achCombo3, G.MaxCombo >= 3);
  Test(achCombo6, G.MaxCombo >= 6);
  Test(achBank, G.BankPops >= 1);
  Test(achBank10, G.BankPops >= 10);
  Test(achBomb, G.BombsUsed >= 1);
  Test(achRainbow, G.RainbowsUsed >= 1);
  Test(achLevel3, G.Level >= 3);
  Test(achLevel6, G.Level >= 6);
  Test(achLevel10, G.Level >= 10);
  Test(achSurvivor, G.RowsSurvived >= 10);
  Test(achHighRoller, G.Score >= 10000);
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
