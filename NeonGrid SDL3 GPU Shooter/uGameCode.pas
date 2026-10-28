unit uGameCode;

{ Continue codes ("cheat codes") of Neon Beads, Neon Trail and Neon Shooter.

  A code holds the level just completed, the score and the lives left (Neon
  Beads has no lives: 0) plus a game id and a checksum, scrambled into 10
  characters of a 32-letter alphabet without look-alikes (no 0 O 1 I):
  'K7QM2-XR9TD'. A code of the other game or a mistyped one is rejected.

  Bits: game 2, level 8 (1..255), lives 4 (0..15), score 28 (0..268,435,455),
  checksum 8 = 50 bits = 10 x 5-bit letters. }

{$mode objfpc}{$H+}
{$Q-}{$R-}

interface

const
  GameIdBeads = 1;
  GameIdTrail = 2;
  GameIdShooter = 3;
  GameCodeLen = 10;      // letters (shown with a dash after the fifth)

{ the code of a completed level }
function MakeGameCode(AGame, ALevel, AScore, ALives: Integer): string;
{ True for a valid code of game AGame; dashes, spaces and case are ignored }
function ReadGameCode(const ACode: string; AGame: Integer; out ALevel, AScore, ALives: Integer): Boolean;
{ only the code letters of S, upper case (for typing / pasting) }
function CleanGameCode(const S: string): string;

implementation

uses
  SysUtils, Math;

const
  Alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  Mask50 = (QWord(1) shl 50) - 1;
  Mul = QWord($2F6A3C5D9B1);          // odd: invertible modulo 2^50
  XorKey = QWord($15A3C96E2B7D) and Mask50;

function Check8(P: QWord): QWord;
begin
  Result := ((P + 77) * QWord($9E3779B97F4A7C15)) shr 56;
end;

function MulInverse: QWord;
var
  i: Integer;
begin
  { Newton: inverse of Mul modulo 2^64 (and so modulo 2^50) }
  Result := Mul;
  for i := 1 to 6 do Result := Result * (2 - Mul * Result);
end;

function CleanGameCode(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := UpCase(S[i]);
    if Pos(c, Alphabet) > 0 then Result += c;
  end;
end;

function MakeGameCode(AGame, ALevel, AScore, ALives: Integer): string;
var
  p, v: QWord;
  i: Integer;
begin
  p := QWord(AGame and 3) or (QWord(EnsureRange(ALevel, 1, 255)) shl 2) or
    (QWord(EnsureRange(ALives, 0, 15)) shl 10) or (QWord(EnsureRange(AScore, 0, $FFFFFFF)) shl 14);
  v := p or (Check8(p) shl 42);
  v := ((v * Mul) and Mask50) xor XorKey;
  Result := '';
  for i := GameCodeLen - 1 downto 0 do
  begin
    Result += Alphabet[((v shr (i * 5)) and 31) + 1];
    if i = 5 then Result += '-';
  end;
end;

function ReadGameCode(const ACode: string; AGame: Integer; out ALevel, AScore, ALives: Integer): Boolean;
var
  s: string;
  v, p: QWord;
  i: Integer;
begin
  ALevel := 0;
  AScore := 0;
  ALives := 0;
  Result := False;
  s := CleanGameCode(ACode);
  if Length(s) <> GameCodeLen then Exit;
  v := 0;
  for i := 1 to GameCodeLen do v := (v shl 5) or QWord(Pos(s[i], Alphabet) - 1);
  v := ((v xor XorKey) * MulInverse) and Mask50;
  p := v and ((QWord(1) shl 42) - 1);
  if (v shr 42) <> Check8(p) then Exit;
  if Integer(p and 3) <> AGame then Exit;
  ALevel := (p shr 2) and 255;
  ALives := (p shr 10) and 15;
  AScore := (p shr 14) and $FFFFFFF;
  Result := ALevel >= 1;
end;

end.
