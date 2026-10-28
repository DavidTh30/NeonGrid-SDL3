unit uVoice;

{ Announcer voice clips of the games ("Combo!", "Super combo!", "Great!" ...),
  shared unit. The clips are WAV files (PCM 16 bit, mono or stereo, any
  rate) in a "voice" folder next to the game (or ..\NeonGrid SDL3 GPU
  Shared\Voice); they were made with the Windows speech voice (Microsoft
  David) and can be replaced by recordings with the same names:

    combo2 combo3 combo4 combo5 combo6 combo8 combo10   combos (see ComboClipName)
    great excellent                                     big pops (Neon Beads)

  LoadVoices reads them once: mono, resampled to the mixer rate, silence at
  both ends cut off, peak normalized, short fades. A missing file is just
  silent. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math;

type
  TVoiceClip = array of Single;

{ loads every *.wav of the first folder of ADirs that exists }
procedure LoadVoices(const ADirs: array of string; ASampleRate: Integer);
{ the clip (empty when there is none) }
function VoiceClip(const AName: string): TVoiceClip;
{ the clip for a combo of ACombo (2 and up) }
function ComboClipName(ACombo: Integer): string;

implementation

var
  Names: TStringList;
  Clips: array of TVoiceClip;

function ReadWav(const AFile: string; ARate: Integer; out AClip: TVoiceClip): Boolean;
var
  fs: TFileStream;
  id: array[0..3] of AnsiChar;
  size, fmtCh, fmtRate, fmtBits, fmtTag: LongWord;
  w16: Word;
  raw: array of SmallInt;
  mono: array of Single;
  n, i, k, a, b, ch: Integer;
  pos, frac, peak, f: Double;
  gotFmt: Boolean;
begin
  Result := False;
  SetLength(AClip, 0);
  fmtCh := 1; fmtRate := 22050; fmtBits := 16; fmtTag := 1;
  gotFmt := False;
  try
    fs := TFileStream.Create(AFile, fmOpenRead or fmShareDenyWrite);
  except
    Exit;
  end;
  try
    fs.ReadBuffer(id, 4);
    if id <> 'RIFF' then Exit;
    fs.ReadBuffer(size, 4);
    fs.ReadBuffer(id, 4);
    if id <> 'WAVE' then Exit;
    while fs.Position + 8 <= fs.Size do
    begin
      fs.ReadBuffer(id, 4);
      fs.ReadBuffer(size, 4);
      if id = 'fmt ' then
      begin
        fs.ReadBuffer(w16, 2); fmtTag := w16;
        fs.ReadBuffer(w16, 2); fmtCh := w16;
        fs.ReadBuffer(fmtRate, 4);
        fs.Seek(6, soCurrent);   // byte rate, block align
        fs.ReadBuffer(w16, 2); fmtBits := w16;
        fs.Seek(Int64(size) - 16, soCurrent);
        gotFmt := True;
      end
      else if id = 'data' then
      begin
        if not gotFmt or (fmtTag <> 1) or (fmtBits <> 16) or (fmtCh < 1) then Exit;
        n := size div 2;
        SetLength(raw, n);
        if n > 0 then fs.ReadBuffer(raw[0], n * 2);
        Break;
      end
      else
        fs.Seek(Int64(size) + (size and 1), soCurrent);
    end;
  finally
    fs.Free;
  end;
  if Length(raw) = 0 then Exit;
  { mono }
  ch := fmtCh;
  n := Length(raw) div ch;
  SetLength(mono, n);
  for i := 0 to n - 1 do
  begin
    f := 0;
    for k := 0 to ch - 1 do f += raw[i * ch + k];
    mono[i] := f / ch / 32768;
  end;
  { cut the silence at both ends (keep 15 ms) }
  a := 0;
  while (a < n) and (Abs(mono[a]) < 0.02) do Inc(a);
  b := n - 1;
  while (b > a) and (Abs(mono[b]) < 0.02) do Dec(b);
  a := Max(0, a - Round(fmtRate * 0.015));
  b := Min(n - 1, b + Round(fmtRate * 0.015));
  if b <= a then Exit;
  { resample to the mixer rate (linear) }
  k := Round((b - a + 1) * ARate / fmtRate);
  SetLength(AClip, k);
  peak := 1e-6;
  for i := 0 to k - 1 do
  begin
    pos := a + i * fmtRate / ARate;
    n := Trunc(pos);
    frac := pos - n;
    if n + 1 <= b then AClip[i] := mono[n] * (1 - frac) + mono[n + 1] * frac
    else AClip[i] := mono[Min(n, b)];
    peak := Max(peak, Abs(AClip[i]));
  end;
  { peak 0.9, 5 ms fades }
  for i := 0 to k - 1 do
  begin
    f := 0.9 / peak;
    if i < ARate div 200 then f *= i / (ARate div 200);
    if k - 1 - i < ARate div 200 then f *= (k - 1 - i) / (ARate div 200);
    AClip[i] := AClip[i] * f;
  end;
  Result := True;
end;

procedure LoadVoices(const ADirs: array of string; ASampleRate: Integer);
var
  d, dir: string;
  sr: TSearchRec;
  c: TVoiceClip;
begin
  Names.Clear;
  SetLength(Clips, 0);
  dir := '';
  for d in ADirs do
    if DirectoryExists(d) then
    begin
      dir := IncludeTrailingPathDelimiter(d);
      Break;
    end;
  if dir = '' then Exit;
  if FindFirst(dir + '*.wav', faAnyFile, sr) = 0 then
  begin
    repeat
      if ReadWav(dir + sr.Name, ASampleRate, c) then
      begin
        Names.Add(LowerCase(ChangeFileExt(sr.Name, '')));
        SetLength(Clips, Length(Clips) + 1);
        Clips[High(Clips)] := c;
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
end;

function VoiceClip(const AName: string): TVoiceClip;
var
  i: Integer;
begin
  i := Names.IndexOf(LowerCase(AName));
  if i >= 0 then Result := Clips[i] else SetLength(Result, 0);
end;

function ComboClipName(ACombo: Integer): string;
begin
  if ACombo >= 10 then Result := 'combo10'
  else if ACombo >= 8 then Result := 'combo8'
  else if ACombo >= 6 then Result := 'combo6'
  else Result := 'combo' + IntToStr(Max(2, ACombo));
end;

initialization
  Names := TStringList.Create;

finalization
  Names.Free;

end.
