unit uGameMusic;

{ Background music of Neon Beads, Neon Trail and Neon Shooter (shared unit), synthesized
  live in the audio callback. A small step sequencer plays song definitions:

    lead      melody written in scale degrees (8 bars)
    arp       chord arpeggio pattern
    bass      root / octave / fifth pattern
    comp      chord stabs
    pad       sustained chord
    drums     kick, snare, clap, closed / open hat, shaker (3 kits)

  Instruments are simple synth voices (band-limited square / pulse / saw,
  FM bell, music box, marimba, pluck, flute, electric piano, bass ...).
  Chords come from the song key (diatonic triads), so melodies and patterns
  stay in tune for every song.

  Intensity (0 = menu, 1 = in game) lowers the drums and bass in the menu,
  Muffle (pause) closes a low-pass filter and lowers the level, and a new
  song fades the old one out and the new one in.

  Songs live in a text file next to the game (NeonBeads.music,
  NeonTrail.music, INI format: [Music] Count, [Song1] .. [SongN]); the
  built-in sets (DefaultSongs) are written when the file is missing. The
  composer (NeonGrid SDL3 GPU Tools\NeonMusicEditor) edits these files;
  TrackMute and Position serve its preview. }

{$mode objfpc}{$H+}
{$COPERATORS ON}
{$modeswitch typehelpers}

interface

uses
  Math, SysUtils, Classes, IniFiles;

const
  MusicGameBeads = 1;
  MusicGameTrail = 2;
  MusicGameShooter = 3;
  { tracks for TGameMusic.TrackMute }
  TrackCount = 11;
  TrackNames: array[0..TrackCount - 1] of string = ('Lead', 'Arp', 'Bass', 'Comp', 'Pad',
    'Kick', 'Snare', 'Clap', 'Hat', 'Open hat', 'Shaker');

type
  TWave = (wvSine, wvTriangle, wvSquare, wvPulse25, wvSaw, wvSuperSaw, wvPad, wvBell,
    wvMusicBox, wvMarimba, wvPluck, wvFlute, wvRhodes, wvBass, wvBassPluck);
  TKit = (kitSynth, kitChip, kitLight);

const
  WaveNames: array[TWave] of string = ('sine', 'triangle', 'square', 'pulse25', 'saw', 'supersaw',
    'pad', 'bell', 'musicbox', 'marimba', 'pluck', 'flute', 'rhodes', 'bass', 'basspluck');
  KitNames: array[TKit] of string = ('synth', 'chip', 'light');

type
  TSongDef = record
    Name: string;
    BPM, StepsPerBar: Integer;
    Swing: Single;
    Key: Integer;              // MIDI note of scale degree 1
    Minor: Boolean;
    Chords: string;            // chord root degree per bar, e.g. '1564'
    Melody: string;            // tokens per step, bars separated by '|'
    Lead, Arp, Bass, Comp: TWave;
    PadOn: Boolean;
    LeadOct, ArpOct, BassOct, CompOct: Integer;   // semitones
    ArpPat, BassPat, CompPat: string;
    KickPat, SnarePat, ClapPat, HatPat, OpenPat, ShakerPat: string;
    Kit: TKit;
    LeadGain, ArpGain, BassGain, CompGain, PadGain, DrumGain, DelayMix: Single;
  end;
  TSongArray = array of TSongDef;

  TVoice = record
    Active: Boolean;
    Wave: TWave;
    Role, Stage: Integer;      // role 0 lead, 1 arp, 2 bass, 3 comp, 4 pad
    Freq, Ph, Ph2, Ph3: Double;
    Env, Atk, Dec, Sus, Rel: Double;
    Age, Gain, Pan, LP: Double;
  end;

  TDrum = record
    T, Gain, Ph, LP: Double;
  end;

  TGameMusic = class
  private
    FSR: Integer;
    FSong: TSongDef;
    FCur, FReq: Integer;
    FFade: Double;
    FSpb, FStep, FStepLeft, FBaseStep: Integer;
    FMel: array of Integer;    // per step: MIDI note, -1 rest, -2 hold
    FMelBars: Integer;
    FVoices: array[0..23] of TVoice;
    FKick, FSnare, FClap, FHat, FOpen, FShaker: TDrum;
    FDelL, FDelR: array of Single;
    FDelPos, FDelLen: Integer;
    FNoise: Cardinal;
    FInt, FMuf, FMufL, FMufR, FHatLP: Double;
    FRefresh: Boolean;
    function Noise: Double; inline;
    function ScaleNote(ADegree: Integer): Integer;
    function ChordTone(ADegree, AIndex: Integer): Integer;
    procedure LoadSong(AIndex: Integer);
    procedure NoteOn(ARole: Integer; AWave: TWave; ANote: Integer; AGain, APan: Double);
    procedure ReleaseRole(ARole: Integer);
    procedure DoStep;
    function VoiceSample(var V: TVoice): Double;
  public
    TargetIntensity: Single;   // 0 = menu, 1 = in game
    MuffleTarget: Single;      // 1 = paused
    TrackMute: array[0..TrackCount - 1] of Boolean;   // composer: silent tracks
    constructor Create(ASampleRate: Integer);
    procedure SelectSong(AIndex: Integer);   // -1 = stop (fade out)
    function CurrentSong: Integer;
    { reload the current song (its definition changed); AAtOnce skips the fade }
    procedure Restart(AAtOnce: Boolean);
    { the current song's definition changed: apply it, keep the play position }
    procedure Refresh;
    { the step being played (from the song start), -1 = none }
    function Position: Integer;
    function StepsPerBar: Integer;
    { adds AFrames stereo samples into L and R }
    procedure Render(L, R: PSingle; AFrames: Integer);
  end;

function SongCount: Integer;
function SongName(AIndex: Integer): string;
{ the song list used by every TGameMusic (thread safe copies) }
function GetSongs: TSongArray;
function GetSong(AIndex: Integer): TSongDef;
procedure SetSongs(const ASongs: TSongArray);
procedure SetSong(AIndex: Integer; const ASong: TSongDef);
{ the built-in songs of a game (MusicGameBeads / MusicGameTrail / MusicGameShooter) }
function DefaultSongs(AGame: Integer): TSongArray;
function BlankSong: TSongDef;
{ a longer song made of its own melody: A (as written), B (the first half up
  a fourth, then up a fifth, the last two bars as written), A' (the first
  half an octave up when it fits), B' (the first half on the sixth, the
  second half as written); the chords move with the melody, so every note
  stays in tune. Only for melodies of 4 .. 8 bars (4 x as long). }
function LongVersion(const ASong: TSongDef): TSongDef;
{ song files (INI text) }
function LoadSongsFile(const AFile: string; out ASongs: TSongArray): Boolean;
procedure SaveSongsFile(const AFile: string; const ASongs: TSongArray);
function WaveByName(const S: string; ADefault: TWave): TWave;
function KitByName(const S: string): TKit;

implementation

const
  MajorScale: array[0..6] of Integer = (0, 2, 4, 5, 7, 9, 11);
  MinorScale: array[0..6] of Integer = (0, 2, 3, 5, 7, 8, 10);
  TwoPi = 2 * Pi;

var
  Songs: TSongArray;
  SongLock: TRTLCriticalSection;

function SongCount: Integer;
begin
  EnterCriticalSection(SongLock);
  Result := Length(Songs);
  LeaveCriticalSection(SongLock);
end;

function SongName(AIndex: Integer): string;
begin
  EnterCriticalSection(SongLock);
  if (AIndex >= 0) and (AIndex < Length(Songs)) then Result := Songs[AIndex].Name else Result := '';
  LeaveCriticalSection(SongLock);
end;

function GetSongs: TSongArray;
begin
  EnterCriticalSection(SongLock);
  Result := Copy(Songs);
  LeaveCriticalSection(SongLock);
end;

function GetSong(AIndex: Integer): TSongDef;
begin
  EnterCriticalSection(SongLock);
  if (AIndex >= 0) and (AIndex < Length(Songs)) then Result := Songs[AIndex] else Result := BlankSong;
  LeaveCriticalSection(SongLock);
end;

procedure SetSongs(const ASongs: TSongArray);
begin
  EnterCriticalSection(SongLock);
  Songs := Copy(ASongs);
  LeaveCriticalSection(SongLock);
end;

procedure SetSong(AIndex: Integer; const ASong: TSongDef);
begin
  EnterCriticalSection(SongLock);
  if (AIndex >= 0) and (AIndex < Length(Songs)) then Songs[AIndex] := ASong;
  LeaveCriticalSection(SongLock);
end;

function WaveByName(const S: string; ADefault: TWave): TWave;
var
  w: TWave;
begin
  for w := Low(TWave) to High(TWave) do
    if SameText(WaveNames[w], Trim(S)) then Exit(w);
  Result := ADefault;
end;

function KitByName(const S: string): TKit;
var
  k: TKit;
begin
  for k := Low(TKit) to High(TKit) do
    if SameText(KitNames[k], Trim(S)) then Exit(k);
  Result := kitSynth;
end;

{ ------------------------------------------------------------------ songs }

function BlankSong: TSongDef;
begin
  Result := Default(TSongDef);
  Result.Name := 'New Song';
  Result.BPM := 120;
  Result.Key := 60;
  Result.Chords := '1564';
  Result.StepsPerBar := 16;
  Result.LeadOct := 12;
  Result.ArpOct := 12;
  Result.BassOct := -24;
  Result.Kit := kitSynth;
  Result.Lead := wvSquare;
  Result.Arp := wvPluck;
  Result.Bass := wvBass;
  Result.Comp := wvRhodes;
  Result.LeadGain := 0.12; Result.ArpGain := 0.05; Result.BassGain := 0.2; Result.CompGain := 0.05;
  Result.PadGain := 0.04; Result.DrumGain := 0.55; Result.DelayMix := 0.3;
end;

function LongVersion(const ASong: TSongDef): TSongDef;
type
  TTok = record
    Note: Boolean;
    V: Integer;          // (degree - 1) + 7 x octave
    Acc, Raw: string;
  end;
  TBar = array of TTok;
var
  bars: array of TBar;
  parts, toks: TStringArray;
  n, L, h, b, i, k: Integer;
  mel, chd: string;

  function Parse(const T: string): TTok;
  var
    j: Integer;
  begin
    Result := Default(TTok);
    Result.Raw := T;
    if (T = '') or not (T[1] in ['1'..'7']) then Exit;
    Result.Note := True;
    Result.V := Ord(T[1]) - Ord('1');
    for j := 2 to Length(T) do
      case T[j] of
        '''': Result.V += 7;
        ',': Result.V -= 7;
        '#', 'b': Result.Acc += T[j];
      end;
  end;

  function Fmt(const T: TTok): string;
  var
    d, o: Integer;
  begin
    if not T.Note then Exit(T.Raw);
    d := ((T.V mod 7) + 7) mod 7;
    o := (T.V - d) div 7;
    Result := IntToStr(d + 1);
    if o > 0 then Result += StringOfChar('''', o) else if o < 0 then Result += StringOfChar(',', -o);
    Result += T.Acc;
  end;

  { the bar moved AK scale steps, kept between 1, and 7' }
  function Shift(const ABar: TBar; AK: Integer): TBar;
  var
    j, mx, mn: Integer;
  begin
    Result := Copy(ABar);
    mx := -999;
    mn := 999;
    for j := 0 to High(Result) do
      if Result[j].Note then
      begin
        Result[j].V += AK;
        mx := Max(mx, Result[j].V);
        mn := Min(mn, Result[j].V);
      end;
    if mx > 13 then
    begin
      for j := 0 to High(Result) do if Result[j].Note then Result[j].V -= 7;
    end
    else if (mn <> 999) and (mn < -7) then
      for j := 0 to High(Result) do if Result[j].Note then Result[j].V += 7;
  end;

  function Lift(const ABar: TBar): TBar;
  var
    j, mx: Integer;
  begin
    mx := -999;
    for j := 0 to High(ABar) do if ABar[j].Note then mx := Max(mx, ABar[j].V);
    if (mx <> -999) and (mx + 7 <= 13) then Result := Shift(ABar, 7) else Result := Copy(ABar);
  end;

  function Chord(C: Char; AK: Integer): Char;
  begin
    Result := Chr(Ord('1') + ((Ord(C) - Ord('1') + AK) mod 7 + 7) mod 7);
  end;

  procedure Put(const ABar: TBar; C: Char);
  var
    j: Integer;
    t: string;
  begin
    t := '';
    for j := 0 to High(ABar) do
    begin
      if j > 0 then t += ' ';
      t += Fmt(ABar[j]);
    end;
    if mel <> '' then mel += '|';
    mel += t;
    chd += C;
  end;

begin
  Result := ASong;
  parts := ASong.Melody.Split(['|']);
  n := Length(parts);
  L := Length(ASong.Chords);
  if (n < 4) or (n > 8) or (L = 0) then Exit;
  SetLength(bars, n);
  for b := 0 to n - 1 do
  begin
    toks := Trim(parts[b]).Split([' '], TStringSplitOptions.ExcludeEmpty);
    SetLength(bars[b], Length(toks));
    for i := 0 to High(toks) do bars[b][i] := Parse(toks[i]);
  end;
  h := n div 2;
  mel := '';
  chd := '';
  { A }
  for b := 0 to n - 1 do Put(bars[b], ASong.Chords[b mod L + 1]);
  { B }
  for b := 0 to n - 1 do
    if b < h then Put(Shift(bars[b], 3), Chord(ASong.Chords[b mod L + 1], 3))
    else if b < n - 2 then Put(Shift(bars[b], 4), Chord(ASong.Chords[b mod L + 1], 4))
    else Put(bars[b], ASong.Chords[b mod L + 1]);
  { A' }
  for b := 0 to n - 1 do
    if b < h then Put(Lift(bars[b]), ASong.Chords[b mod L + 1])
    else Put(bars[b], ASong.Chords[b mod L + 1]);
  { B' }
  for b := 0 to n - 1 do
    if b < h then Put(Shift(bars[b], 5), Chord(ASong.Chords[b mod L + 1], 5))
    else Put(bars[b], ASong.Chords[b mod L + 1]);
  k := 0;
  Result.Melody := mel;
  Result.Chords := chd;
end;

function DefaultSongs(AGame: Integer): TSongArray;
var
  s: TSongDef;

  procedure Blank;
  begin
    s := Default(TSongDef);
    s.StepsPerBar := 16;
    s.LeadOct := 12;
    s.ArpOct := 12;
    s.BassOct := -24;
    s.Kit := kitSynth;
    s.LeadGain := 0.12; s.ArpGain := 0.05; s.BassGain := 0.2; s.CompGain := 0.05;
    s.PadGain := 0.04; s.DrumGain := 0.55; s.DelayMix := 0.3;
  end;

  procedure Add;
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LongVersion(s);   // the 8 bars become an A B A' B' song
  end;

begin
  Result := nil;
  if AGame = MusicGameShooter then
  begin
    { ---- Neon Shooter: bouncy, poppy tracks (marimba, music box, plucks, chip) }
    { 1. Bubble Pop }
    Blank;
    s.Name := 'Bubble Pop'; s.BPM := 118; s.Key := 60; s.Minor := False; s.Chords := '1564';
    s.Swing := 0.1;
    s.Melody :=
      '5 . 5 . 6 . 5 . 3 . 1 . 3 - 5 -|4 . 4 . 5 . 4 . 2 . 7, . 2 - 4 -|' +
      '3 . 3 . 4 . 3 . 1 . 6, . 1 - 3 -|2 - - - 5, - 7, - 2 - - - . . . .|' +
      '1'' . 7 . 6 . 5 . 6 . 5 . 3 . 5 .|4 . 5 . 6 . 4 . 5 - - - 3 - - -|' +
      '6 . 5 . 4 . 3 . 4 . 3 . 2 . 4 .|1 - - - 3 - 5 - 1'' - - - . . . .';
    s.Lead := wvMarimba; s.Arp := wvMusicBox; s.Bass := wvBassPluck; s.PadOn := True;
    s.LeadOct := 12; s.ArpOct := 24; s.BassOct := -24;
    s.ArpPat := '0.2.1.2.0.2.1.3.';
    s.BassPat := 'R...O...R.5.O...';
    s.KickPat := 'x.....x.x.......';
    s.SnarePat := '....x.......x...';
    s.HatPat := '..x...x...x...x.';
    s.ShakerPat := '.x.x.x.x.x.x.x.x';
    s.Kit := kitLight;
    s.LeadGain := 0.14; s.ArpGain := 0.04; s.BassGain := 0.2; s.CompGain := 0.05; s.PadGain := 0.035; s.DrumGain := 0.45; s.DelayMix := 0.3;
    Add;

    { 2. Ricochet }
    Blank;
    s.Name := 'Ricochet'; s.BPM := 136; s.Key := 57; s.Minor := True; s.Chords := '1674';
    s.Melody :=
      '1 . 1 . 3 . 5 . 1'' . 7 . 5 . 3 .|6, . 6, . 1 . 3 . 6 . 5 . 3 . 1 .|' +
      '7, . 7, . 2 . 4 . 7 . 6 . 4 . 2 .|5 - - - 4 - - - 2 - - - . . . .|' +
      '3'' . 2'' . 1'' . 7 . 1'' . 7 . 5 . 3 .|1'' . 7 . 6 . 5 . 6 - - - 3 - - -|' +
      '4 . 5 . 6 . 7 . 2'' . 1'' . 7 . 6 .|5 - - - 7 - - - 1'' - - - . . . .';
    s.Lead := wvPulse25; s.Arp := wvSquare; s.Bass := wvTriangle; s.PadOn := False;
    s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -12;
    s.ArpPat := '0120012001200123';
    s.BassPat := 'R.R.O.R.R.O.R.O.';
    s.KickPat := 'x...x...x...x.x.';
    s.SnarePat := '....x.......x...';
    s.HatPat := 'x.x.x.x.x.x.x.x.';
    s.Kit := kitChip;
    s.LeadGain := 0.085; s.ArpGain := 0.03; s.BassGain := 0.24; s.CompGain := 0.05; s.PadGain := 0.03; s.DrumGain := 0.5; s.DelayMix := 0.15;
    Add;

    { 3. Candy Lasers }
    Blank;
    s.Name := 'Candy Lasers'; s.BPM := 124; s.Key := 62; s.Minor := False; s.Chords := '1625';
    s.Melody :=
      '3 - 5 - 1'' - 5 - 6 - 5 - 3 - 2 -|1 - - - 6, - 1 - 3 - - - 2 - - -|' +
      '2 - 4 - 6 - 4 - 5 - 4 - 2 - 7, -|1 - - - - - - - . . . . 5 - 6 -|' +
      '7 - 1'' - 2'' - 1'' - 7 - 5 - 6 - 7 -|1'' - - - 6 - 5 - 6 - - - 1'' - - -|' +
      '2'' - 1'' - 7 - 6 - 5 - 4 - 3 - 2 -|1 - - - 5, - - - 1 - - - . . . .';
    s.Lead := wvFlute; s.Arp := wvPluck; s.Bass := wvBass; s.Comp := wvRhodes; s.PadOn := True;
    s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -12;
    s.ArpPat := '0123012301230123';
    s.BassPat := 'R...R.O.R...R.O.';
    s.CompPat := '..x...x...x...x.';
    s.KickPat := 'x...x...x...x...';
    s.ClapPat := '....x.......x...';
    s.OpenPat := '..x...x...x...x.';
    s.Kit := kitSynth;
    s.LeadGain := 0.12; s.ArpGain := 0.04; s.BassGain := 0.2; s.CompGain := 0.04; s.PadGain := 0.03; s.DrumGain := 0.5; s.DelayMix := 0.35;
    Add;

    { 4. Chain Reaction }
    Blank;
    s.Name := 'Chain Reaction'; s.BPM := 148; s.Key := 52; s.Minor := True; s.Chords := '1474';
    s.Melody :=
      '1 . 2 . 3 . 5 . 3 . 2 . 1 . 5, .|4 . 5 . 6 . 1'' . 6 . 5 . 4 . 1 .|' +
      '7, . 1 . 2 . 4 . 2 . 1 . 7, . 5, .|4 . 5 . 6 . 7 . 1'' - - - . . . .|' +
      '5 . 5 . 6 . 5 . 3 . 3 . 5 . 3 .|6 . 6 . 1'' . 6 . 4 . 4 . 6 . 4 .|' +
      '7 . 7 . 2'' . 7 . 5 . 4 . 2 . 7, .|1 - - - 3 - - - 5 - - - . . . .';
    s.Lead := wvSquare; s.Arp := wvMarimba; s.Bass := wvBass; s.PadOn := True;
    s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -12;
    s.ArpPat := '0.1.2.1.0.1.2.1.';
    s.BassPat := 'R.R.O.R.R.R.O.R.';
    s.KickPat := 'x...x...x...x...';
    s.SnarePat := '....x.......x...';
    s.HatPat := 'xxxxxxxxxxxxxxxx';
    s.Kit := kitSynth;
    s.LeadGain := 0.08; s.ArpGain := 0.05; s.BassGain := 0.2; s.CompGain := 0.05; s.PadGain := 0.03; s.DrumGain := 0.55; s.DelayMix := 0.25;
    Add;

    { 5. Soap Stars }
    Blank;
    s.Name := 'Soap Stars'; s.BPM := 92; s.Key := 65; s.Minor := False; s.Chords := '1436';
    s.Swing := 0.15;
    s.Melody :=
      '5 - - - 3 - 4 - 5 - - - 1'' - - -|6 - - - 4 - 5 - 6 - - - 1'' - - -|' +
      '7 - - - 5 - 6 - 7 - - - 2'' - - -|1'' - - - 7 - 6 - 5 - - - . . . .|' +
      '3'' - - - 2'' - 1'' - 7 - - - 5 - - -|6 - - - 5 - 4 - 3 - - - 1 - - -|' +
      '4 - - - 3 - 4 - 6 - - - 5 - - -|1 - - - - - - - . . . . . . . .';
    s.Lead := wvMusicBox; s.Arp := wvBell; s.Bass := wvBass; s.Comp := wvRhodes; s.PadOn := True;
    s.LeadOct := 12; s.ArpOct := 24; s.BassOct := -12;
    s.ArpPat := '0...2...1...2...';
    s.BassPat := 'R.......5.......';
    s.CompPat := 'x.......x.......';
    s.KickPat := 'x.......x.......';
    s.ClapPat := '....x.......x...';
    s.ShakerPat := '.xx..xx..xx..xx.';
    s.Kit := kitLight;
    s.LeadGain := 0.14; s.ArpGain := 0.03; s.BassGain := 0.2; s.CompGain := 0.05; s.PadGain := 0.04; s.DrumGain := 0.35; s.DelayMix := 0.45;
    Add;

    { 6. Fizz Circuit }
    Blank;
    s.Name := 'Fizz Circuit'; s.BPM := 128; s.Key := 55; s.Minor := False; s.Chords := '1546';
    s.Swing := 0.08;
    s.Melody :=
      '1'' . 6 . 5 . 6 . 3 . 5 . 2 . . .|1'' . 6 . 5 . 6 . 4 . 3 . 1 . . .|' +
      '3'' . 2'' . 1'' . 2'' . 6 . 1'' . 5 . . .|4 . 5 . 6 . 7 . 1'' . 2'' . 1'' . . .|' +
      '6 . 5 . 6 . 4 . 2 . 4 . 6, . . .|5 . 4 . 5 . 3 . 1 . 3 . 5, . . .|' +
      '4 . 3 . 4 . 2 . 7, . 2 . 4 . 5 .|1 . . . 5 . . . 1'' . . . . . . .';
    s.Lead := wvPluck; s.Arp := wvMusicBox; s.Bass := wvBassPluck; s.PadOn := False;
    s.LeadOct := 12; s.ArpOct := 24; s.BassOct := -24;
    s.ArpPat := '0.1.2.0.1.2.0.1.';
    s.BassPat := 'R.O.R.O.R.O.R.O.';
    s.KickPat := 'x...x...x...x...';
    s.SnarePat := '....x.......x...';
    s.HatPat := '..x...x...x...x.';
    s.ShakerPat := 'x.x.x.x.x.x.x.x.';
    s.Kit := kitSynth;
    s.LeadGain := 0.13; s.ArpGain := 0.035; s.BassGain := 0.18; s.CompGain := 0.05; s.PadGain := 0.03; s.DrumGain := 0.5; s.DelayMix := 0.3;
    Add;

    { 7. Final Volley }
    Blank;
    s.Name := 'Final Volley'; s.BPM := 160; s.Key := 50; s.Minor := True; s.Chords := '1647';
    s.Melody :=
      '1 - 5 - 1'' - 5 - 6 - 5 - 3 - 5 -|6, - 3 - 6 - 3 - 4 - 3 - 1 - 3 -|' +
      '4, - 1 - 4 - 1 - 5 - 4 - 2 - 4 -|5 - 7 - 2'' - 7 - 5 - - - . . . .|' +
      '1'' - 1'' - 7 - 1'' - 3'' - 2'' - 1'' - 7 -|6 - 6 - 5 - 6 - 1'' - 7 - 6 - 5 -|' +
      '4 - 4 - 5 - 6 - 7 - 1'' - 2'' - 7 -|1'' - - - 5 - - - 1 - - - . . . .';
    s.Lead := wvSuperSaw; s.Arp := wvPluck; s.Bass := wvSquare; s.PadOn := True;
    s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -12;
    s.ArpPat := '0120120120120123';
    s.BassPat := 'R.O.R.O.R.O.R.O.';
    s.KickPat := 'x...x...x...x...';
    s.ClapPat := '....x.......x...';
    s.HatPat := 'xxxxxxxxxxxxxxxx';
    s.OpenPat := '..x...x...x...x.';
    s.Kit := kitSynth;
    s.LeadGain := 0.08; s.ArpGain := 0.04; s.BassGain := 0.13; s.CompGain := 0.05; s.PadGain := 0.025; s.DrumGain := 0.6; s.DelayMix := 0.25;
    Add;

    Exit;
  end;
  if AGame = MusicGameTrail then
  begin
    { ---- Neon Trail: driving minor-key arcade tracks }
    { 1. Light Cycle }
    Blank;
    s.Name := 'Light Cycle'; s.BPM := 126; s.Key := 52; s.Minor := True; s.Chords := '1674';
    s.Melody :=
      '1 - 3 - 5 - 3 - 7 - 5 - 3 - 2 -|1 - - - 6, - 1 - 3 - 4 - 3 - 1 -|' +
      '7, - 2 - 4 - 2 - 6 - 4 - 2 - 1 -|7, - - - 4 - 6 - 1'' - 7 - . . . .|' +
      '5 - 5 - 3 - 5 - 1'' - 7 - 5 - 3 -|6 - - - 1'' - 6 - 4 - 3 - 4 - 6 -|' +
      '7 - 2'' - 4'' - 2'' - 7 - 5 - 4 - 2 -|1'' - - - 7 - - - 1'' - - - . . . .';
    s.Lead := wvSaw; s.Arp := wvPluck; s.Bass := wvBassPluck; s.PadOn := True;
    s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -24;
    s.ArpPat := '0.1.2.1.0.1.2.3.';
    s.BassPat := 'RRORRRORRRORRROR';
    s.KickPat := 'x...x...x...x...';
    s.SnarePat := '....x.......x...';
    s.HatPat := '..x...x...x...x.';
    s.ShakerPat := '.x.x.x.x.x.x.x.x';
    s.LeadGain := 0.08; s.ArpGain := 0.05; s.BassGain := 0.16; s.PadGain := 0.035; s.DrumGain := 0.55; s.DelayMix := 0.35;
    Add;

    { 2. Pulse Runner }
    Blank;
    s.Name := 'Pulse Runner'; s.BPM := 150; s.Key := 57; s.Minor := True; s.Chords := '1647';
    s.Melody :=
      '1'' - 7 - 1'' - 5 - 6 - 5 - 3 - 5 -|6 - 5 - 3 - 1 - 2 - 3 - 4 - 5 -|' +
      '4 - 6 - 1'' - 6 - 4 - 6 - 1'' - 2'' -|7 - 5 - 2 - 5 - 7 - - - . . . .|' +
      '1'' - 3'' - 5'' - 3'' - 1'' - 7 - 6 - 7 -|1'' - 6 - 3 - 6 - 1'' - 3'' - 2'' - 1'' -|' +
      '6 - 4 - 1 - 4 - 6 - 1'' - 4'' - 3'' -|2'' - 1'' - 7 - 5 - 1'' - - - . . . .';
    s.Lead := wvPulse25; s.Arp := wvSquare; s.Bass := wvTriangle; s.PadOn := False;
    s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -12;
    s.ArpPat := '0120012001200123';
    s.BassPat := 'R.R.O.R.R.O.R.O.';
    s.KickPat := 'x...x.x...x.x...';
    s.SnarePat := '....x.......x...';
    s.HatPat := 'x.x.x.x.x.x.x.x.';
    s.Kit := kitChip;
    s.LeadGain := 0.085; s.ArpGain := 0.03; s.BassGain := 0.24; s.DrumGain := 0.5; s.DelayMix := 0.15;
    Add;

    { 3. Neon Highway }
    Blank;
    s.Name := 'Neon Highway'; s.BPM := 112; s.Key := 54; s.Minor := True; s.Chords := '1674';
    s.Melody :=
      '5 - - - 4 - 3 - 4 - - - 1 - - -|3 - - - 2 - 1 - 7, - - - 5, - - -|' +
      '6, - - - 1 - 3 - 4 - - - 3 - 2 -|1 - - - - - - - . . . . . . . .|' +
      '5 - - - 4 - 5 - 7 - - - 1'' - - -|7 - - - 6 - 5 - 6 - - - 4 - - -|' +
      '4 - 5 - 6 - 7 - 1'' - - - 7 - 6 -|5 - - - - - - - 7 - - - . . . .';
    s.Lead := wvSaw; s.Arp := wvPluck; s.Bass := wvBassPluck; s.PadOn := True;
    s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -24;
    s.ArpPat := '0123012301230123';
    s.BassPat := 'RORORORORORORORO';
    s.KickPat := 'x...x...x...x...';
    s.SnarePat := '....x.......x...';
    s.OpenPat := '..x...x...x...x.';
    s.LeadGain := 0.09; s.ArpGain := 0.045; s.BassGain := 0.17; s.PadGain := 0.045; s.DrumGain := 0.5; s.DelayMix := 0.45;
    Add;

    { 4. Laser Garden }
    Blank;
    s.Name := 'Laser Garden'; s.BPM := 96; s.Key := 50; s.Minor := True; s.Chords := '1645';
    s.Swing := 0.12;
    s.Melody :=
      '1 . 3 . 5 . 1'' . 7 . 5 . 3 . 5 .|6 . 1'' . 3'' . 1'' . 6 . 4 . . . . .|' +
      '4 . 6 . 1'' . 6 . 5 . 4 . 2 . 4 .|5 . 7 . 2'' . 7 . 5 . . . . . . .|' +
      '3'' . 2'' . 1'' . 7 . 1'' . 5 . 3 . 1 .|6, . 1 . 3 . 6 . 1'' . 3'' . . . . .|' +
      '4 . 2 . 4 . 6 . 2'' . 1'' . 6 . 4 .|5 . 7 . 2'' . 5'' . 3'' . . . . . . .';
    s.Lead := wvBell; s.Bass := wvBass; s.Comp := wvRhodes; s.PadOn := True;
    s.LeadOct := 12; s.BassOct := -12; s.CompOct := 0;
    s.BassPat := 'R...5...R...O...';
    s.CompPat := 'x.....x...x.....';
    s.KickPat := 'x.......x.......';
    s.ClapPat := '....x.......x...';
    s.ShakerPat := '.xx..xx..xx..xx.';
    s.Kit := kitLight;
    s.LeadGain := 0.13; s.BassGain := 0.22; s.CompGain := 0.05; s.PadGain := 0.03; s.DrumGain := 0.4; s.DelayMix := 0.4;
    Add;

    { 5. Turbo Tail }
    Blank;
    s.Name := 'Turbo Tail'; s.BPM := 140; s.Key := 48; s.Minor := True; s.Chords := '1674';
    s.Melody :=
      '1'' - 1'' - 7 - 1'' - 3'' - 1'' - 7 - 5 -|6 - 6 - 5 - 6 - 1'' - 6 - 5 - 3 -|' +
      '7 - 7 - 6 - 7 - 2'' - 7 - 6 - 4 -|5 - - - 7 - - - 2'' - - - . . . .|' +
      '3'' - 2'' - 1'' - 2'' - 3'' - 4'' - 5'' - 3'' -|1'' - 6 - 3 - 6 - 1'' - 3'' - 6'' - 5'' -|' +
      '4'' - 2'' - 7 - 2'' - 4'' - 5'' - 4'' - 2'' -|1'' - - - 5 - - - 1'' - - - . . . .';
    s.Lead := wvSuperSaw; s.Arp := wvPluck; s.Bass := wvSquare; s.PadOn := True;
    s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -12;
    s.ArpPat := '0120120120120123';
    s.BassPat := 'R.O.R.O.R.O.R.O.';
    s.KickPat := 'x...x...x...x...';
    s.ClapPat := '....x.......x...';
    s.HatPat := 'xxxxxxxxxxxxxxxx';
    s.OpenPat := '..x...x...x...x.';
    s.LeadGain := 0.08; s.ArpGain := 0.04; s.BassGain := 0.13; s.PadGain := 0.025; s.DrumGain := 0.6; s.DelayMix := 0.25;
    Add;

    { 6. Starlight Drift }
    Blank;
    s.Name := 'Starlight Drift'; s.BPM := 88; s.Key := 55; s.Minor := False; s.Chords := '1463';
    s.Melody :=
      '3 - - - 5 - - - 6 - 5 - 3 - - -|4 - - - 6 - - - 1'' - 7 - 6 - - -|' +
      '6 - - - 1'' - - - 3'' - 2'' - 1'' - - -|7 - - - 5 - - - 3 - - - . . . .|' +
      '3 - - - 5 - - - 1'' - - - 7 - 6 -|4 - - - 6 - - - 2'' - - - 1'' - 6 -|' +
      '6 - - - 5 - - - 3 - - - 2 - 3 -|3 - - - - - - - . . . . . . . .';
    s.Lead := wvMusicBox; s.Arp := wvPluck; s.Bass := wvBass; s.PadOn := True;
    s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -12;
    s.ArpPat := '0.2.1.2.0.2.1.2.';
    s.BassPat := 'R.......R.......';
    s.KickPat := 'x.......x.......';
    s.HatPat := '....x.......x...';
    s.Kit := kitLight;
    s.LeadGain := 0.15; s.ArpGain := 0.05; s.BassGain := 0.2; s.PadGain := 0.06; s.DrumGain := 0.3; s.DelayMix := 0.5;
    Add;

    { 7. Grid Boss }
    Blank;
    s.Name := 'Grid Boss'; s.BPM := 136; s.Key := 47; s.Minor := True; s.Chords := '1617';
    s.Melody :=
      '1 - 1 - 2 - 3 - 1 - 1 - 7, - 6, -|1 - 1 - 2 - 3 - 5 - 4 - 3 - 2 -|' +
      '1 - 1 - 2 - 3 - 1 - 1 - 7, - 6, -|5, - - - 6, - - - 7, - - - . . . .|' +
      '5 - 5 - 4 - 5 - 6 - 5 - 4 - 3 -|4 - 4 - 3 - 4 - 5 - 4 - 3 - 2 -|' +
      '3 - 3 - 2 - 3 - 4 - 3 - 2 - 1 -|7, - - - 1 - - - 2 - - - . . . .';
    s.Lead := wvSquare; s.Arp := wvPluck; s.Bass := wvBassPluck; s.PadOn := False;
    s.LeadOct := 12; s.ArpOct := 24; s.BassOct := -12;
    s.ArpPat := '0.0.0.0.1.1.2.2.';
    s.BassPat := 'RRRRRRRRRRRROO55';
    s.KickPat := 'x..x..x.x..x..x.';
    s.SnarePat := '....x.......x..x';
    s.HatPat := 'x.x.x.x.x.x.x.x.';
    s.LeadGain := 0.1; s.ArpGain := 0.04; s.BassGain := 0.2; s.DrumGain := 0.6; s.DelayMix := 0.2;
    Add;
    Exit;
  end;
  { ---- Neon Beads }
  { 1. Sunny Side - bright pop, C major, I V vi IV }
  Blank;
  s.Name := 'Sunny Side'; s.BPM := 124; s.Key := 60; s.Chords := '1564';
  s.Melody :=
    '3 - 5 - 1'' - 7 - 6 - 5 - 3 - 5 -|2 - 5 - 7 - 5 - 4 - 2 - . . 5, -|' +
    '6 - 1'' - 3'' - 1'' - 7 - 6 - 5 - 3 -|4 - 6 - 1'' - 6 - 5 - 4 - 3 - 2 -|' +
    '3 - 5 - 1'' - 7 - 6 - 5 - 3 - 5 -|2 - 5 - 7 - 2'' - 1'' - 7 - 5 - - -|' +
    '6 - - 5 - - 3 - 1'' - - 7 - - 6 -|4 - 3 - 2 - - - 1 - - - . . . .';
  s.Lead := wvSquare; s.Arp := wvPluck; s.Bass := wvBassPluck; s.PadOn := True;
  s.ArpPat := '0.2.1.2.0.2.1.2.';
  s.BassPat := 'R.O.R.O.R.O.R.O.';
  s.KickPat := 'x...x...x...x...'; s.ClapPat := '....x.......x...';
  s.HatPat := '..x...x...x...x.'; s.ShakerPat := '.x.x.x.x.x.x.x.x';
  s.LeadGain := 0.11; s.ArpGain := 0.06; s.PadGain := 0.035;
  Add;

  { 2. Pixel Picnic - 8-bit chiptune, G major, I vi IV V }
  Blank;
  s.Name := 'Pixel Picnic'; s.BPM := 144; s.Key := 55; s.Chords := '1645';
  s.Melody :=
    '1'' - 7 - 1'' - 5 - 3 - 5 - 1'' - 2'' -|1'' - 7 - 6 - 5 - 3 - - - 5 - 6 -|' +
    '1'' - - 6 - - 4 - 6 - 1'' - 2'' - 1''|7 - - 5 - - 7 - 2'' - - - . . . .|' +
    '3'' - 2'' - 1'' - 5 - 3 - 5 - 1'' - 3'' -|2'' - 1'' - 7 - 6 - 3 - 6 - 7 - 1'' -|' +
    '6 - 1'' - 4'' - 3'' - 2'' - 1'' - 6 - 4 -|5 - 7 - 2'' - 4'' - 5'' - - - . . . .';
  s.Lead := wvPulse25; s.Arp := wvSquare; s.Bass := wvTriangle; s.PadOn := False;
  s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -12;
  s.ArpPat := '0121012101210123';
  s.BassPat := 'R.R.O.R.R.R.O.R.';
  s.KickPat := 'x.......x.x.....'; s.SnarePat := '....x.......x...';
  s.HatPat := 'x.x.x.x.x.x.x.x.';
  s.Kit := kitChip;
  s.LeadGain := 0.09; s.ArpGain := 0.035; s.BassGain := 0.24; s.DrumGain := 0.5; s.DelayMix := 0.15;
  Add;

  { 3. Island Hop - marimba calypso, F major, swing }
  Blank;
  s.Name := 'Island Hop'; s.BPM := 108; s.Swing := 0.16; s.Key := 53; s.Chords := '14511625';
  s.Melody :=
    '5 . 6 . 5 3 . 1 3 . 5 . 6 5 3 .|4 . 6 . 1'' . 6 . 4 . 6 . 5 . . .|' +
    '5 . 7 . 2'' . 7 . 5 . 4 . 3 . 2 .|1 . 3 . 5 . . . 1'' . . . . . . .|' +
    '5 . 6 . 5 3 . 1 3 . 5 . 6 5 3 .|6 . 1'' . 6 . 5 . 3 . 5 . 6 . . .|' +
    '2'' . 1'' . 6 . 4 . 2 . 4 . 6 . 5 .|5 . 7 . 2'' . . . 1'' . 7 . 5 . . .';
  s.Lead := wvMarimba; s.Comp := wvMarimba; s.Bass := wvBass; s.PadOn := False;
  s.LeadOct := 12; s.CompOct := 0; s.BassOct := -12;
  s.CompPat := '..x...x...x...x.';
  s.BassPat := 'R..5R.5.R..5R.5.';
  s.KickPat := 'x.....x.x.......'; s.ClapPat := '....x.......x...';
  s.ShakerPat := '.xxx.xxx.xxx.xxx';
  s.Kit := kitLight;
  s.LeadGain := 0.2; s.CompGain := 0.06; s.BassGain := 0.24; s.DrumGain := 0.45; s.DelayMix := 0.25;
  Add;

  { 4. Disco Bubbles - funky disco, D major, flute lead + electric piano }
  Blank;
  s.Name := 'Disco Bubbles'; s.BPM := 118; s.Key := 62; s.Chords := '1625';
  s.Melody :=
    '5 - - 3 5 - 6 - 5 - 3 - 1 - 3 -|6 - - 5 6 - 1'' - 6 - 5 - 3 - - -|' +
    '4 - - 2 4 - 6 - 1'' - 6 - 4 - - -|5 - 7 - 2'' - 7 - 5 - 4 - 3 - 2 -|' +
    '5 - - 3 5 - 6 - 5 - 3 - 1 - 3 -|6 - - 5 6 - 1'' - 3'' - 2'' - 1'' - - -|' +
    '2'' - 1'' - 6 - 4 - 6 - 1'' - 2'' - 4'' -|2'' - - - 7 - - - 5 - - - . . . .';
  s.Lead := wvFlute; s.Comp := wvRhodes; s.Bass := wvBassPluck; s.PadOn := True;
  s.LeadOct := 12; s.CompOct := 0; s.BassOct := -24;
  s.CompPat := '..x..x....x..x..';
  s.BassPat := 'RORORORORORORORO';
  s.KickPat := 'x...x...x...x...'; s.ClapPat := '....x.......x...';
  s.OpenPat := '..x...x...x...x.'; s.ShakerPat := '.x.x.x.x.x.x.x.x';
  s.LeadGain := 0.15; s.CompGain := 0.05; s.BassGain := 0.18; s.PadGain := 0.03;
  Add;

  { 5. Merry-Go-Round - music-box waltz in 3/4, C major }
  Blank;
  s.Name := 'Merry-Go-Round'; s.BPM := 150; s.StepsPerBar := 12; s.Key := 72; s.Chords := '14511625';
  s.Melody :=
    '5 - - 3 - - 1'' - - 5 - -|6 - - 4 - - 1'' - - 6 - -|' +
    '7 - - 5 - - 2'' - - 7 - -|1'' - - - - - 5 - 3 - 1 -|' +
    '3 - 5 - 1'' - 3'' - - 2'' - -|1'' - - 6 - - 3 - - 6 - -|' +
    '4'' - - 2'' - - 6 - - 1'' - -|7 - - 2'' - - 5 - - . . .';
  s.Lead := wvMusicBox; s.Comp := wvPluck; s.Bass := wvBass; s.PadOn := False;
  s.LeadOct := 0; s.CompOct := -12; s.BassOct := -24;
  s.CompPat := '....x...x...';
  s.BassPat := 'R...........';
  s.KickPat := 'x...........'; s.HatPat := '....x...x...';
  s.Kit := kitLight;
  s.LeadGain := 0.17; s.CompGain := 0.06; s.BassGain := 0.22; s.DrumGain := 0.3; s.DelayMix := 0.3;
  Add;

  { 6. Happy Hustle - energetic dance, A major, supersaw lead }
  Blank;
  s.Name := 'Happy Hustle'; s.BPM := 132; s.Key := 57; s.Chords := '4156';
  s.Melody :=
    '6 - 6 - 1'' - 6 - 4 - 6 - 1'' - 2'' -|3'' - - - 1'' - - - 5 - 6 - 5 - 3 -|' +
    '2'' - 2'' - 7 - 2'' - 5 - 7 - 2'' - 4'' -|3'' - - - 1'' - - - 6 - - - . . . .|' +
    '6 - 1'' - 2'' - 1'' - 6 - 1'' - 4'' - 3'' -|3'' - 1'' - 5 - 1'' - 3'' - 5'' - 3'' - 1'' -|' +
    '7 - 2'' - 5'' - 4'' - 2'' - 7 - 5 - 7 -|1'' - - - 6 - - - 3'' - - - . . . .';
  s.Lead := wvSuperSaw; s.Arp := wvPluck; s.Bass := wvSquare; s.PadOn := True;
  s.LeadOct := 12; s.ArpOct := 12; s.BassOct := -24;
  s.ArpPat := '0120120120120123';
  s.BassPat := 'R.O.R.O.R.O.R.O.';
  s.KickPat := 'x...x...x...x...'; s.ClapPat := '....x.......x...';
  s.HatPat := 'xxxxxxxxxxxxxxxx'; s.OpenPat := '..x...x...x...x.';
  s.LeadGain := 0.09; s.ArpGain := 0.045; s.BassGain := 0.15; s.PadGain := 0.025; s.DrumGain := 0.6;
  Add;

  { 7. Neon Night - the calm synthwave piece, A minor }
  Blank;
  s.Name := 'Neon Night'; s.BPM := 100; s.Key := 57; s.Minor := True; s.Chords := '1637';
  s.Melody := '';
  s.Arp := wvPluck; s.Bass := wvBass; s.PadOn := True;
  s.ArpOct := 12; s.BassOct := -12;
  s.ArpPat := '0123210101232101';
  s.BassPat := 'R.R.R.O.R.R.R.O.';
  s.KickPat := 'x...x...x...x...'; s.SnarePat := '....x.......x...';
  s.HatPat := '..x...x...x...x.';
  s.ArpGain := 0.09; s.BassGain := 0.22; s.PadGain := 0.07; s.DrumGain := 0.5; s.DelayMix := 0.5;
  Add;
end;

{ ------------------------------------------------------------- song files }

var
  FS: TFormatSettings;

function F2S(V: Single): string;
begin
  Result := FormatFloat('0.####', V, FS);
end;

function S2F(const S: string; ADefault: Single): Single;
begin
  Result := StrToFloatDef(Trim(S), ADefault, FS);
end;

function LoadSongsFile(const AFile: string; out ASongs: TSongArray): Boolean;
var
  ini: TMemIniFile;
  i, n: Integer;
  sec: string;
  s, b: TSongDef;
begin
  ASongs := nil;
  Result := False;
  if not FileExists(AFile) then Exit;
  try
    ini := TMemIniFile.Create(AFile);
    try
      n := ini.ReadInteger('Music', 'Count', 0);
      b := BlankSong;
      for i := 1 to n do
      begin
        sec := 'Song' + IntToStr(i);
        if not ini.SectionExists(sec) then Continue;
        s := Default(TSongDef);
        s.Name := ini.ReadString(sec, 'Name', 'Song ' + IntToStr(i));
        s.BPM := EnsureRange(ini.ReadInteger(sec, 'BPM', 120), 30, 300);
        s.StepsPerBar := EnsureRange(ini.ReadInteger(sec, 'StepsPerBar', 16), 4, 32);
        s.Swing := EnsureRange(S2F(ini.ReadString(sec, 'Swing', '0'), 0), 0, 0.45);
        s.Key := EnsureRange(ini.ReadInteger(sec, 'Key', 60), 24, 96);
        s.Minor := ini.ReadBool(sec, 'Minor', False);
        s.Chords := ini.ReadString(sec, 'Chords', '1');
        if s.Chords = '' then s.Chords := '1';
        s.Melody := ini.ReadString(sec, 'Melody', '');
        s.Lead := WaveByName(ini.ReadString(sec, 'Lead', ''), b.Lead);
        s.Arp := WaveByName(ini.ReadString(sec, 'Arp', ''), b.Arp);
        s.Bass := WaveByName(ini.ReadString(sec, 'Bass', ''), b.Bass);
        s.Comp := WaveByName(ini.ReadString(sec, 'Comp', ''), b.Comp);
        s.PadOn := ini.ReadBool(sec, 'Pad', False);
        s.LeadOct := ini.ReadInteger(sec, 'LeadOct', 12);
        s.ArpOct := ini.ReadInteger(sec, 'ArpOct', 12);
        s.BassOct := ini.ReadInteger(sec, 'BassOct', -24);
        s.CompOct := ini.ReadInteger(sec, 'CompOct', 0);
        s.ArpPat := ini.ReadString(sec, 'ArpPat', '');
        s.BassPat := ini.ReadString(sec, 'BassPat', '');
        s.CompPat := ini.ReadString(sec, 'CompPat', '');
        s.KickPat := ini.ReadString(sec, 'Kick', '');
        s.SnarePat := ini.ReadString(sec, 'Snare', '');
        s.ClapPat := ini.ReadString(sec, 'Clap', '');
        s.HatPat := ini.ReadString(sec, 'Hat', '');
        s.OpenPat := ini.ReadString(sec, 'OpenHat', '');
        s.ShakerPat := ini.ReadString(sec, 'Shaker', '');
        s.Kit := KitByName(ini.ReadString(sec, 'Kit', 'synth'));
        s.LeadGain := S2F(ini.ReadString(sec, 'LeadGain', ''), b.LeadGain);
        s.ArpGain := S2F(ini.ReadString(sec, 'ArpGain', ''), b.ArpGain);
        s.BassGain := S2F(ini.ReadString(sec, 'BassGain', ''), b.BassGain);
        s.CompGain := S2F(ini.ReadString(sec, 'CompGain', ''), b.CompGain);
        s.PadGain := S2F(ini.ReadString(sec, 'PadGain', ''), b.PadGain);
        s.DrumGain := S2F(ini.ReadString(sec, 'DrumGain', ''), b.DrumGain);
        s.DelayMix := S2F(ini.ReadString(sec, 'DelayMix', ''), b.DelayMix);
        SetLength(ASongs, Length(ASongs) + 1);
        ASongs[High(ASongs)] := s;
      end;
    finally
      ini.Free;
    end;
    Result := Length(ASongs) > 0;
  except
    Result := False;
  end;
end;

procedure SaveSongsFile(const AFile: string; const ASongs: TSongArray);
var
  sl: TStringList;
  i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Add('; Neon game music - edit with NeonMusicEditor (NeonGrid SDL3 GPU Tools) or by hand.');
    sl.Add('; Melody: one token per step, bars separated by |. Tokens: scale degree 1-7,');
    sl.Add(';   '' octave up, , octave down, # sharp, b flat; - hold, . rest.');
    sl.Add('; Patterns (one char per step): Arp 0-3 chord tone / . rest; Bass R root, O octave,');
    sl.Add(';   5 fifth, . release; Comp and drums x hit / . rest.');
    sl.Add('; Waves: sine triangle square pulse25 saw supersaw pad bell musicbox marimba pluck');
    sl.Add(';   flute rhodes bass basspluck. Kits: synth chip light.');
    sl.Add('');
    sl.Add('[Music]');
    sl.Add('Count=' + IntToStr(Length(ASongs)));
    for i := 0 to High(ASongs) do
      with ASongs[i] do
      begin
        sl.Add('');
        sl.Add('[Song' + IntToStr(i + 1) + ']');
        sl.Add('Name=' + Name);
        sl.Add('BPM=' + IntToStr(BPM));
        sl.Add('StepsPerBar=' + IntToStr(StepsPerBar));
        sl.Add('Swing=' + F2S(Swing));
        sl.Add('Key=' + IntToStr(Key));
        sl.Add('Minor=' + IntToStr(Ord(Minor)));
        sl.Add('Chords=' + Chords);
        sl.Add('Melody=' + Melody);
        sl.Add('Lead=' + WaveNames[Lead]);
        sl.Add('Arp=' + WaveNames[Arp]);
        sl.Add('Bass=' + WaveNames[Bass]);
        sl.Add('Comp=' + WaveNames[Comp]);
        sl.Add('Pad=' + IntToStr(Ord(PadOn)));
        sl.Add('LeadOct=' + IntToStr(LeadOct));
        sl.Add('ArpOct=' + IntToStr(ArpOct));
        sl.Add('BassOct=' + IntToStr(BassOct));
        sl.Add('CompOct=' + IntToStr(CompOct));
        sl.Add('ArpPat=' + ArpPat);
        sl.Add('BassPat=' + BassPat);
        sl.Add('CompPat=' + CompPat);
        sl.Add('Kick=' + KickPat);
        sl.Add('Snare=' + SnarePat);
        sl.Add('Clap=' + ClapPat);
        sl.Add('Hat=' + HatPat);
        sl.Add('OpenHat=' + OpenPat);
        sl.Add('Shaker=' + ShakerPat);
        sl.Add('Kit=' + KitNames[Kit]);
        sl.Add('LeadGain=' + F2S(LeadGain));
        sl.Add('ArpGain=' + F2S(ArpGain));
        sl.Add('BassGain=' + F2S(BassGain));
        sl.Add('CompGain=' + F2S(CompGain));
        sl.Add('PadGain=' + F2S(PadGain));
        sl.Add('DrumGain=' + F2S(DrumGain));
        sl.Add('DelayMix=' + F2S(DelayMix));
      end;
    sl.SaveToFile(AFile);
  finally
    sl.Free;
  end;
end;

{ ------------------------------------------------------------------ engine }

function MidiHz(ANote: Double): Double;
begin
  Result := 440 * Power(2, (ANote - 69) / 12);
end;

function PolyBlep(t, dt: Double): Double; inline;
begin
  if t < dt then
  begin
    t := t / dt;
    Result := t + t - t * t - 1;
  end
  else if t > 1 - dt then
  begin
    t := (t - 1) / dt;
    Result := t * t + t + t + 1;
  end
  else
    Result := 0;
end;

function Frac1(x: Double): Double; inline;
begin
  Result := x - Floor(x);
end;

constructor TGameMusic.Create(ASampleRate: Integer);
begin
  inherited Create;
  FSR := ASampleRate;
  FNoise := 2463534242;
  SetLength(FDelL, FSR * 2);
  SetLength(FDelR, FSR * 2);
  FCur := -1;
  FReq := -1;
  FKick.T := 99; FSnare.T := 99; FClap.T := 99; FHat.T := 99; FOpen.T := 99; FShaker.T := 99;
end;

procedure TGameMusic.SelectSong(AIndex: Integer);
var
  n: Integer;
begin
  n := SongCount;
  if (AIndex < 0) or (n = 0) then FReq := -1 else FReq := EnsureRange(AIndex, 0, n - 1);
end;

function TGameMusic.CurrentSong: Integer;
begin
  Result := FReq;
end;

procedure TGameMusic.Restart(AAtOnce: Boolean);
begin
  if FReq < 0 then Exit;
  if AAtOnce then FFade := 0;
  FCur := -2;   // differs from FReq: the render loop (re)loads the song
end;

procedure TGameMusic.Refresh;
begin
  FRefresh := True;
end;

function TGameMusic.Position: Integer;
begin
  if FCur < 0 then Result := -1 else Result := FStep;
end;

function TGameMusic.StepsPerBar: Integer;
begin
  Result := Max(1, FSpb);
end;

function TGameMusic.Noise: Double;
begin
  FNoise := FNoise xor (FNoise shl 13);
  FNoise := FNoise xor (FNoise shr 17);
  FNoise := FNoise xor (FNoise shl 5);
  Result := (FNoise and $FFFF) / 32768 - 1;
end;

function TGameMusic.ScaleNote(ADegree: Integer): Integer;
var
  d, oct: Integer;
begin
  d := ADegree - 1;
  oct := Floor(d / 7);
  d := d - oct * 7;
  if FSong.Minor then Result := FSong.Key + MinorScale[d] + 12 * oct
  else Result := FSong.Key + MajorScale[d] + 12 * oct;
end;

function TGameMusic.ChordTone(ADegree, AIndex: Integer): Integer;
begin
  Result := ScaleNote(ADegree + 2 * AIndex);
end;

procedure TGameMusic.LoadSong(AIndex: Integer);
var
  bars: TStringArray;
  toks: TStringArray;
  b, i, k, deg, n: Integer;
  t: string;
begin
  FSong := GetSong(AIndex);
  FSpb := Max(1, FSong.StepsPerBar);
  FBaseStep := Round(FSR * 60 / FSong.BPM / 4);
  FDelLen := Min(Length(FDelL), FBaseStep * 3);
  FillChar(FDelL[0], Length(FDelL) * SizeOf(Single), 0);
  FillChar(FDelR[0], Length(FDelR) * SizeOf(Single), 0);
  FDelPos := 0;
  for i := 0 to High(FVoices) do FVoices[i].Active := False;
  { melody: one token per step, bars separated by '|' }
  SetLength(FMel, 0);
  FMelBars := 0;
  if FSong.Melody <> '' then
  begin
    bars := FSong.Melody.Split(['|']);
    FMelBars := Length(bars);
    SetLength(FMel, FMelBars * FSpb);
    for b := 0 to FMelBars - 1 do
    begin
      toks := Trim(bars[b]).Split([' '], TStringSplitOptions.ExcludeEmpty);
      for i := 0 to FSpb - 1 do
      begin
        if i < Length(toks) then t := toks[i] else t := '.';
        if t = '-' then n := -2
        else if (t = '.') or (t = '') then n := -1
        else
        begin
          deg := EnsureRange(Ord(t[1]) - Ord('0'), 1, 7);
          n := ScaleNote(deg);
          for k := 2 to Length(t) do
            case t[k] of
              '''': n += 12;
              ',': n -= 12;
              '#': n += 1;
              'b': n -= 1;
            end;
        end;
        FMel[b * FSpb + i] := n;
      end;
    end;
  end;
  FStep := -1;
  FStepLeft := 0;
end;

procedure TGameMusic.ReleaseRole(ARole: Integer);
var
  i: Integer;
begin
  for i := 0 to High(FVoices) do
    if FVoices[i].Active and (FVoices[i].Role = ARole) then FVoices[i].Stage := 2;
end;

procedure TGameMusic.NoteOn(ARole: Integer; AWave: TWave; ANote: Integer; AGain, APan: Double);
var
  i, best: Integer;
  a, d, su, r, oldest: Double;

  function C(ASec: Double): Double;
  begin
    Result := 1 - Exp(-1 / (Max(0.0005, ASec) * FSR));
  end;

begin
  if AGain <= 0 then Exit;
  if ARole in [0, 2] then ReleaseRole(ARole);   // lead and bass are monophonic
  best := -1;
  oldest := -1;
  for i := 0 to High(FVoices) do
    if not FVoices[i].Active then
    begin
      best := i;
      Break;
    end
    else if FVoices[i].Age > oldest then
    begin
      oldest := FVoices[i].Age;
      best := i;
    end;
  case AWave of
    wvPad: begin a := 0.5; d := 0.5; su := 0.9; r := 0.8; end;
    wvBell: begin a := 0.002; d := 0.9; su := 0; r := 0.3; end;
    wvMusicBox: begin a := 0.001; d := 0.7; su := 0; r := 0.3; end;
    wvMarimba: begin a := 0.001; d := 0.35; su := 0; r := 0.1; end;
    wvPluck: begin a := 0.002; d := 0.25; su := 0; r := 0.1; end;
    wvFlute: begin a := 0.05; d := 0.2; su := 0.8; r := 0.12; end;
    wvRhodes: begin a := 0.003; d := 0.6; su := 0.15; r := 0.2; end;
    wvBass: begin a := 0.004; d := 0.25; su := 0.55; r := 0.06; end;
    wvBassPluck: begin a := 0.002; d := 0.18; su := 0.3; r := 0.05; end;
  else
    begin a := 0.004; d := 0.15; su := 0.65; r := 0.07; end;
  end;
  with FVoices[best] do
  begin
    Active := True;
    Wave := AWave;
    Role := ARole;
    Freq := MidiHz(ANote);
    Ph := 0; Ph2 := 0.33; Ph3 := 0.66;
    Env := 0; Stage := 0;
    Atk := C(a); Dec := C(d); Sus := su; Rel := C(r);
    Age := 0; Gain := AGain; Pan := APan; LP := 0;
  end;
end;

function TGameMusic.VoiceSample(var V: TVoice): Double;
var
  inc, s, raw: Double;
begin
  inc := V.Freq / FSR;
  if V.Wave = wvFlute then
    inc := inc * (1 + 0.004 * Sin(TwoPi * 5.2 * V.Age) * Min(1, V.Age * 4));
  V.Ph += inc;
  if V.Ph >= 1 then V.Ph -= 1;
  case V.Wave of
    wvSine: s := Sin(TwoPi * V.Ph);
    wvTriangle: s := 1 - 4 * Abs(V.Ph - 0.5);
    wvSquare:
      begin
        if V.Ph < 0.5 then s := 1 else s := -1;
        s := s + PolyBlep(V.Ph, inc) - PolyBlep(Frac1(V.Ph + 0.5), inc);
        s := s * 0.7;
      end;
    wvPulse25:
      begin
        if V.Ph < 0.25 then s := 1 else s := -1;
        s := s + PolyBlep(V.Ph, inc) - PolyBlep(Frac1(V.Ph + 0.75), inc);
        s := s * 0.7;
      end;
    wvSaw:
      s := (2 * V.Ph - 1 - PolyBlep(V.Ph, inc)) * 0.7;
    wvSuperSaw:
      begin
        V.Ph2 += inc * 1.007;
        if V.Ph2 >= 1 then V.Ph2 -= 1;
        V.Ph3 += inc * 0.993;
        if V.Ph3 >= 1 then V.Ph3 -= 1;
        raw := (2 * V.Ph - 1 - PolyBlep(V.Ph, inc)) + (2 * V.Ph2 - 1 - PolyBlep(V.Ph2, inc * 1.007)) +
          (2 * V.Ph3 - 1 - PolyBlep(V.Ph3, inc * 0.993));
        V.LP += (raw - V.LP) * 0.35;
        s := V.LP * 0.35;
      end;
    wvPad:
      begin
        raw := Sin(TwoPi * V.Ph) + 0.5 * Sin(2 * TwoPi * V.Ph) + 0.3 * Sin(3 * TwoPi * V.Ph);
        V.LP += (raw - V.LP) * 0.12;
        s := V.LP;
      end;
    wvBell:
      begin
        V.Ph2 += inc * 3.5;
        if V.Ph2 >= 1 then V.Ph2 -= 1;
        s := Sin(TwoPi * V.Ph + 2.2 * Exp(-V.Age * 5) * Sin(TwoPi * V.Ph2));
      end;
    wvMusicBox:
      s := Sin(TwoPi * V.Ph) + 0.35 * Sin(4 * TwoPi * V.Ph) * Exp(-V.Age * 10);
    wvMarimba:
      s := Sin(TwoPi * V.Ph) + 0.3 * Sin(4 * TwoPi * V.Ph) * Exp(-V.Age * 30);
    wvPluck:
      begin
        raw := 2 * V.Ph - 1 - PolyBlep(V.Ph, inc);
        V.LP += (raw - V.LP) * (0.04 + 0.6 * Exp(-V.Age * 14));
        s := V.LP * 1.3;
      end;
    wvFlute:
      s := Sin(TwoPi * V.Ph) + 0.12 * Sin(2 * TwoPi * V.Ph) + Noise * 0.04;
    wvRhodes:
      s := Sin(TwoPi * V.Ph + 0.9 * Exp(-V.Age * 4) * Sin(TwoPi * V.Ph)) +
        0.15 * Sin(2 * TwoPi * V.Ph) * Exp(-V.Age * 6);
    wvBass:
      s := Sin(TwoPi * V.Ph) + 0.25 * Sin(2 * TwoPi * V.Ph) + 0.1 * Sin(3 * TwoPi * V.Ph);
    wvBassPluck:
      begin
        raw := 2 * V.Ph - 1 - PolyBlep(V.Ph, inc);
        V.LP += (raw - V.LP) * (0.03 + 0.3 * Exp(-V.Age * 10));
        s := V.LP * 1.6;
      end;
  else
    s := 0;
  end;
  { envelope }
  case V.Stage of
    0:
      begin
        V.Env += (1.25 - V.Env) * V.Atk;
        if V.Env >= 1 then
        begin
          V.Env := 1;
          V.Stage := 1;
        end;
      end;
    1:
      begin
        V.Env += (V.Sus - V.Env) * V.Dec;
        if (V.Sus = 0) and (V.Env < 0.0005) then V.Active := False;
      end;
  else
    begin
      V.Env -= V.Env * V.Rel;
      if V.Env < 0.0005 then V.Active := False;
    end;
  end;
  V.Age += 1 / FSR;
  Result := s * V.Env * V.Gain;
end;

procedure TGameMusic.DoStep;
var
  bar, st, deg, i, note: Integer;
  ch: Char;
  tones: array[0..2] of Integer;
  lead, bass, drums: Double;
begin
  Inc(FStep);
  bar := FStep div FSpb;
  st := FStep mod FSpb;
  deg := EnsureRange(Ord(FSong.Chords[bar mod Length(FSong.Chords) + 1]) - Ord('0'), 1, 7);
  for i := 0 to 2 do tones[i] := ChordTone(deg, i);
  lead := 0.85 + 0.15 * FInt;
  bass := 0.7 + 0.3 * FInt;
  drums := 0.3 + 0.7 * FInt;

  { pad: new chord every bar }
  if (st = 0) and FSong.PadOn and not TrackMute[4] then
  begin
    ReleaseRole(4);
    for i := 0 to 2 do NoteOn(4, wvPad, tones[i], FSong.PadGain, (i - 1) * 0.4);
  end;
  { melody }
  if (FMelBars > 0) and not TrackMute[0] then
  begin
    note := FMel[(bar mod FMelBars) * FSpb + st];
    if note >= 0 then NoteOn(0, FSong.Lead, note + FSong.LeadOct, FSong.LeadGain * lead, 0)
    else if note = -1 then ReleaseRole(0);
  end;
  { arpeggio }
  if (st < Length(FSong.ArpPat)) and not TrackMute[1] then
  begin
    ch := FSong.ArpPat[st + 1];
    if ch in ['0'..'3'] then
    begin
      if ch = '3' then note := tones[0] + 12 else note := tones[Ord(ch) - Ord('0')];
      NoteOn(1, FSong.Arp, note + FSong.ArpOct, FSong.ArpGain, 0.3);
    end;
  end;
  { bass }
  if (st < Length(FSong.BassPat)) and not TrackMute[2] then
  begin
    ch := FSong.BassPat[st + 1];
    case ch of
      'R': NoteOn(2, FSong.Bass, ScaleNote(deg) + FSong.BassOct, FSong.BassGain * bass, 0);
      'O': NoteOn(2, FSong.Bass, ScaleNote(deg) + 12 + FSong.BassOct, FSong.BassGain * bass, 0);
      '5': NoteOn(2, FSong.Bass, ScaleNote(deg + 4) + FSong.BassOct, FSong.BassGain * bass, 0);
      '.': ReleaseRole(2);
    end;
  end;
  { chord stabs }
  if (st < Length(FSong.CompPat)) and (FSong.CompPat[st + 1] = 'x') and not TrackMute[3] then
    for i := 0 to 2 do NoteOn(3, FSong.Comp, tones[i] + FSong.CompOct, FSong.CompGain, -0.25);
  { drums }
  if (st < Length(FSong.KickPat)) and (FSong.KickPat[st + 1] = 'x') and not TrackMute[5] then
  begin
    FKick.T := 0; FKick.Ph := 0; FKick.Gain := drums;
  end;
  if (st < Length(FSong.SnarePat)) and (FSong.SnarePat[st + 1] = 'x') and not TrackMute[6] then
  begin
    FSnare.T := 0; FSnare.Gain := drums;
  end;
  if (st < Length(FSong.ClapPat)) and (FSong.ClapPat[st + 1] = 'x') and not TrackMute[7] then
  begin
    FClap.T := 0; FClap.Gain := drums;
  end;
  if (st < Length(FSong.HatPat)) and (FSong.HatPat[st + 1] = 'x') and not TrackMute[8] then
  begin
    FHat.T := 0;
    if st mod 4 = 2 then FHat.Gain := drums else FHat.Gain := drums * 0.6;
  end;
  if (st < Length(FSong.OpenPat)) and (FSong.OpenPat[st + 1] = 'x') and not TrackMute[9] then
  begin
    FOpen.T := 0; FOpen.Gain := drums;
  end;
  if (st < Length(FSong.ShakerPat)) and (FSong.ShakerPat[st + 1] = 'x') and not TrackMute[10] then
  begin
    FShaker.T := 0; FShaker.Gain := drums;
  end;
  { a small snare fill at the end of every 8 bars in game }
  if (FSong.Kit <> kitLight) and (FInt > 0.5) and (bar mod 8 = 7) and (st >= FSpb - 4) and not TrackMute[6] then
  begin
    FSnare.T := 0;
    FSnare.Gain := drums * (0.5 + 0.15 * (st - FSpb + 4));
  end;
end;

procedure TGameMusic.Render(L, R: PSingle; AFrames: Integer);
var
  n, i: Integer;
  dt, ml, mr, v, send, nz, f, kick, sn, cl, hat, op, sh, dl, dr, outL, outR, c, g, dg: Double;
begin
  dt := 1 / FSR;
  for n := 0 to AFrames - 1 do
  begin
    { song change: fade out, load, fade in }
    if FReq <> FCur then
    begin
      FFade -= 1 / (0.5 * FSR);
      if FFade <= 0 then
      begin
        FFade := 0;
        FCur := FReq;
        if FCur >= 0 then
        begin
          if FCur < SongCount then LoadSong(FCur) else FCur := -1;
        end;
      end;
    end
    else if FFade < 1 then
      FFade := Min(1, FFade + 1 / (0.4 * FSR));
    if FCur < 0 then Continue;
    if FRefresh then
    begin
      { re-read the song, continue at the same step }
      FRefresh := False;
      i := FStep;
      LoadSong(FCur);
      FStep := i;
    end;

    { sequencer with swing }
    if FStepLeft <= 0 then
    begin
      DoStep;
      if FStep mod 2 = 0 then FStepLeft := Round(FBaseStep * (1 + FSong.Swing))
      else FStepLeft := Round(FBaseStep * (1 - FSong.Swing));
    end;
    Dec(FStepLeft);
    FInt += (TargetIntensity - FInt) * 0.00003;

    { voices }
    ml := 0; mr := 0; send := 0;
    for i := 0 to High(FVoices) do
      if FVoices[i].Active then
      begin
        v := VoiceSample(FVoices[i]);
        ml += v * (1 - Max(0, FVoices[i].Pan));
        mr += v * (1 + Min(0, FVoices[i].Pan));
        case FVoices[i].Role of
          0: send += v * 0.4;
          1: send += v * 0.8;
          3: send += v * 0.3;
        end;
      end;

    { drums }
    dg := FSong.DrumGain;
    kick := 0;
    if FKick.T < 0.4 then
    begin
      case FSong.Kit of
        kitChip:
          begin
            f := 60 + 180 * Exp(-FKick.T * 40);
            FKick.Ph := Frac1(FKick.Ph + f * dt);
            if FKick.Ph < 0.5 then kick := 0.5 else kick := -0.5;
            kick := kick * Exp(-FKick.T * 22);
          end;
        kitLight:
          begin
            f := 50 + 60 * Exp(-FKick.T * 30);
            FKick.Ph := Frac1(FKick.Ph + f * dt);
            kick := Sin(TwoPi * FKick.Ph) * Exp(-FKick.T * 12) * 0.6;
          end;
      else
        begin
          f := 48 + 110 * Exp(-FKick.T * 30);
          FKick.Ph := Frac1(FKick.Ph + f * dt);
          kick := Sin(TwoPi * FKick.Ph) * Exp(-FKick.T * 9);
        end;
      end;
      kick *= FKick.Gain;
      FKick.T += dt;
    end;
    nz := Noise;
    sn := 0;
    if FSnare.T < 0.25 then
    begin
      if FSong.Kit = kitChip then
        sn := nz * Exp(-FSnare.T * 25) * 0.5
      else
        sn := (nz * 0.6 + Sin(TwoPi * 185 * FSnare.T) * 0.35) * Exp(-FSnare.T * 17) * 0.55;
      sn *= FSnare.Gain;
      FSnare.T += dt;
    end;
    cl := 0;
    if FClap.T < 0.2 then
    begin
      { three quick bursts and a short tail }
      if FClap.T < 0.03 then g := Exp(-Frac1(FClap.T / 0.01) * 4) else g := Exp(-(FClap.T - 0.03) * 22);
      FClap.LP += (nz - FClap.LP) * 0.4;
      cl := (nz - FClap.LP) * g * 0.6 * FClap.Gain;
      if FSong.Kit = kitLight then cl *= 0.5;
      FClap.T += dt;
    end;
    FHatLP += (nz - FHatLP) * 0.5;
    hat := 0;
    if FHat.T < 0.06 then
    begin
      hat := (nz - FHatLP) * Exp(-FHat.T * 60) * 0.3 * FHat.Gain;
      FHat.T += dt;
    end;
    op := 0;
    if FOpen.T < 0.3 then
    begin
      op := (nz - FHatLP) * Exp(-FOpen.T * 11) * 0.22 * FOpen.Gain;
      FOpen.T += dt;
    end;
    sh := 0;
    if FShaker.T < 0.08 then
    begin
      sh := (nz - FHatLP) * Min(1, FShaker.T * 200) * Exp(-FShaker.T * 45) * 0.14 * FShaker.Gain;
      FShaker.T += dt;
    end;

    { ping-pong delay on lead / arp / comp }
    dl := FDelL[FDelPos];
    dr := FDelR[FDelPos];
    FDelL[FDelPos] := send + dr * 0.35;
    FDelR[FDelPos] := dl * 0.35;
    Inc(FDelPos);
    if FDelPos >= FDelLen then FDelPos := 0;

    outL := ml + (kick + sn + cl) * dg + (hat * 0.8 + op + sh * 1.2) * dg + dl * FSong.DelayMix;
    outR := mr + (kick + sn + cl) * dg + (hat * 1.1 + op + sh * 0.8) * dg + dr * FSong.DelayMix;

    { pause: muffled and quieter }
    FMuf += (MuffleTarget - FMuf) * 0.0002;
    c := 1 - 0.94 * FMuf;
    FMufL += (outL - FMufL) * c;
    FMufR += (outR - FMufR) * c;
    g := FFade * (1 - 0.45 * FMuf) * 0.85;
    L[n] += FMufL * g;
    R[n] += FMufR * g;
  end;
end;

initialization
  InitCriticalSection(SongLock);
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Songs := DefaultSongs(MusicGameBeads);

finalization
  DoneCriticalSection(SongLock);

end.
