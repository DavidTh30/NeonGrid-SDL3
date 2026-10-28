unit uGameSfx;

{ Sound effects of Neon Beads and Neon Trail as data (shared unit).

  Every game sound (pop, crash, level, menu move ...) is a list of layers.
  A layer is one synthesized tone or noise burst:
    shape        sine, soft (sine + odd harmonics), bell, square, saw,
                 triangle or noise
    F0 -> F1     pitch at the start / end (exponential glide, Hz)
    Dur, Attack  length and linear fade-in (s); after the attack the level
                 falls as exp(-(t - Attack) * Decay / Dur)
    Delay        start time (s), Gain, Pan (-1 left .. 1 right)
    Noise        a noise click mixed in over NoiseDur seconds
    Count, Every repeats (arpeggios, echoes) Every seconds apart; Steps /
                 StepsEnd give the semitone offset of each repeat ('0 4 7 12'),
                 PanSpread / PanAlt spread them in stereo
    Param...     the game's parameter (the group size of a pop) can raise the
                 pitch, lengthen the sound and add repeats
  The sets live in NeonBeads.sfx / NeonTrail.sfx (INI text); the defaults
  (DefaultSfxBank) are written when a file is missing. The sound designer
  (NeonGrid SDL3 GPU Tools\NeonSfxEditor) edits these files. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, IniFiles;

const
  SfxSR = 44100;
  SfxCount = 12;
  { the same order as TGameSound in uBeadGame / uTrailGame }
  SfxNames: array[0..SfxCount - 1] of string = ('pop', 'invalid', 'land', 'undo', 'level',
    'gameover', 'start', 'menumove', 'menuselect', 'crash', 'gold', 'power');
  SfxInfo: array[0..SfxCount - 1] of string = (
    'Beads: a group pops (param = group size) / Trail: a sparkle is eaten (param = combo)',
    'a click that does nothing',
    'beads land after falling',
    'undo',
    'level complete',
    'game over',
    'a level starts',
    'menu: selection moves',
    'menu: item chosen',
    'crash / blast / iron arrives',
    'gold bead / achievement',
    'power-up / special bead');
  MaxSfxLayers = 8;

type
  TSfxShape = (shSine, shSoft, shBell, shSquare, shSaw, shTriangle, shNoise);

  TSfxLayer = record
    Shape: TSfxShape;
    F0, F1: Single;
    Dur, Attack, Decay, Delay: Single;
    Gain, Pan: Single;
    Noise, NoiseDur: Single;
    Count: Integer;
    Every: Single;
    Steps, StepsEnd: string;
    PanSpread: Single;
    PanAlt: Boolean;
    ParamBase: Integer;
    ParamSemis, ParamSemisMax: Single;
    ParamDur, ParamDurMax: Single;
    ParamCountDiv, ParamCountMax: Integer;
  end;

  TSfxDef = record
    Layers: array of TSfxLayer;
  end;
  TSfxBank = array[0..SfxCount - 1] of TSfxDef;
  TSfxData = array of Single;
  { receives one rendered voice (mono samples at SfxSR, gain, pan) }
  TSfxEmit = procedure(const AData: array of Single; AGain, APan: Single) of object;

const
  ShapeNames: array[TSfxShape] of string = ('sine', 'soft', 'bell', 'square', 'saw', 'triangle', 'noise');

function DefaultSfxLayer: TSfxLayer;
function DefaultSfxBank: TSfxBank;
function ShapeByName(const S: string): TSfxShape;
function LoadSfxFile(const AFile: string; var ABank: TSfxBank): Boolean;
procedure SaveSfxFile(const AFile: string; const ABank: TSfxBank);
{ renders the voices of one sound; ANoise is the caller's noise state }
procedure SfxRender(const ADef: TSfxDef; AParam: Integer; AEmit: TSfxEmit; var ANoise: Cardinal);
{ the whole sound mixed to stereo (for previews and waveform views) }
procedure SfxMixStereo(const ADef: TSfxDef; AParam: Integer; out L, R: TSfxData);

implementation

var
  FS: TFormatSettings;

type
  { collects emitted voices into a stereo mix }
  TSfxMixer = class
    L, R: TSfxData;
    procedure Emit(const AData: array of Single; AGain, APan: Single);
  end;

procedure TSfxMixer.Emit(const AData: array of Single; AGain, APan: Single);
var
  i: Integer;
  gl, gr: Single;
begin
  if Length(AData) > Length(L) then
  begin
    SetLength(L, Length(AData));
    SetLength(R, Length(AData));
  end;
  gl := AGain * (1 - Max(0, APan));
  gr := AGain * (1 + Min(0, APan));
  for i := 0 to High(AData) do
  begin
    L[i] += AData[i] * gl;
    R[i] += AData[i] * gr;
  end;
end;

function DefaultSfxLayer: TSfxLayer;
begin
  Result := Default(TSfxLayer);
  Result.Shape := shSine;
  Result.F0 := 440;
  Result.F1 := 440;
  Result.Dur := 0.2;
  Result.Attack := 0.005;
  Result.Decay := 5;
  Result.Gain := 0.2;
  Result.Count := 1;
  Result.ParamBase := 2;
end;

function ShapeByName(const S: string): TSfxShape;
var
  sh: TSfxShape;
begin
  for sh := Low(TSfxShape) to High(TSfxShape) do
    if SameText(ShapeNames[sh], Trim(S)) then Exit(sh);
  Result := shSine;
end;

function DefaultSfxBank: TSfxBank;
var
  k: Integer;

  function L(AShape: TSfxShape; AF0, AF1, ADur, AAttack, AGain: Single; APan: Single = 0;
    ADelay: Single = 0): TSfxLayer;
  begin
    Result := DefaultSfxLayer;
    Result.Shape := AShape;
    Result.F0 := AF0;
    Result.F1 := AF1;
    Result.Dur := ADur;
    Result.Attack := AAttack;
    Result.Gain := AGain;
    Result.Pan := APan;
    Result.Delay := ADelay;
  end;

  procedure Put(AIndex: Integer; const ALayers: array of TSfxLayer);
  var
    i: Integer;
  begin
    SetLength(Result[AIndex].Layers, Length(ALayers));
    for i := 0 to High(ALayers) do Result[AIndex].Layers[i] := ALayers[i];
  end;

var
  a, b: TSfxLayer;
begin
  for k := 0 to SfxCount - 1 do Result[k].Layers := nil;
  { pop: a bell bloop that rises with the group size, plus a sparkle per 4 beads }
  a := L(shBell, 528, 330, 0.24, 0.004, 0.45);
  a.Noise := 0.35; a.NoiseDur := 0.009;
  a.ParamSemis := 2; a.ParamSemisMax := 24; a.ParamDur := 0.01; a.ParamDurMax := 0.23;
  b := L(shBell, 660, 693, 0.18, 0.002, 0.12);
  b.Count := 0; b.ParamCountDiv := 4; b.ParamCountMax := 5;
  b.Steps := '3 5 7 10 12'; b.StepsEnd := '0 0 0 0 0'; b.PanAlt := True;
  b.ParamSemis := 2; b.ParamSemisMax := 24;
  Put(0, [a, b]);
  Put(1, [L(shSoft, 150, 120, 0.09, 0.003, 0.25)]);
  { land: a short noise tick and a low thump }
  a := L(shNoise, 0, 0, 0.05, 0, 0.108); a.Decay := 6.25;
  b := L(shSine, 90, 90, 0.05, 0, 0.18); b.Decay := 2.5;
  Put(2, [a, b]);
  Put(3, [L(shSine, 500, 900, 0.16, 0.01, 0.25)]);
  { level: a rising major arpeggio }
  a := L(shBell, 440, 440, 0.6, 0.005, 0.25);
  a.Count := 5; a.Every := 0.11; a.Steps := '0 4 7 12 16'; a.PanSpread := 0.3;
  Put(4, [a]);
  { game over: three falling soft tones }
  a := L(shSoft, 392, 392, 0.5, 0.01, 0.22);
  a.Count := 3; a.Every := 0.2; a.Steps := '0 -3 -7'; a.StepsEnd := '0 -3 -8';
  Put(5, [a]);
  Put(6, [L(shSine, 180, 720, 0.45, 0.05, 0.18)]);
  Put(7, [L(shBell, 880, 990, 0.07, 0.002, 0.10)]);
  Put(8, [L(shBell, 660, 660, 0.18, 0.003, 0.16, -0.3), L(shBell, 990, 990, 0.25, 0.003, 0.16, 0.3, 0.06)]);
  { crash: a noise burst and a falling buzz }
  a := L(shNoise, 0, 0, 0.45, 0, 0.28); a.Decay := 7.5;
  b := L(shSine, 220, 60, 0.45, 0, 0.175); b.Decay := 2.25;
  Put(9, [a, b]);
  { gold: three quick bell notes }
  a := L(shBell, 880, 880, 0.35, 0.002, 0.18);
  a.Count := 3; a.Every := 0.06; a.Steps := '4 7 12'; a.PanSpread := 0.4;
  Put(10, [a]);
  Put(11, [L(shSoft, 300, 1200, 0.35, 0.01, 0.16, -0.2), L(shSine, 450, 1800, 0.35, 0.01, 0.12, 0.2)]);
end;

function StepOf(const ASteps: string; AIndex: Integer; ADefault: Single): Single;
var
  parts: TStringArray;
begin
  Result := ADefault;
  if Trim(ASteps) = '' then Exit;
  parts := Trim(ASteps).Split([' ', ','], TStringSplitOptions.ExcludeEmpty);
  if Length(parts) = 0 then Exit;
  Result := StrToFloatDef(parts[AIndex mod Length(parts)], ADefault, FS);
end;

procedure SfxRender(const ADef: TSfxDef; AParam: Integer; AEmit: TSfxEmit; var ANoise: Cardinal);
var
  li, k, n, i, cnt, pre: Integer;
  ly: TSfxLayer;
  d: TSfxData;
  semis, dur, f0, f1, t, f, ph, env, s, pan, st0, st1, nz: Single;

  function Noise: Single;
  begin
    ANoise := ANoise * 1664525 + 1013904223;
    Result := ((ANoise shr 8) and $FFFF) / 32768 - 1;
  end;

begin
  for li := 0 to High(ADef.Layers) do
  begin
    ly := ADef.Layers[li];
    semis := Min(ly.ParamSemisMax, Max(0, AParam - ly.ParamBase) * ly.ParamSemis);
    if ly.ParamSemisMax <= 0 then semis := Max(0, AParam - ly.ParamBase) * ly.ParamSemis;
    if ly.ParamSemis = 0 then semis := 0;
    dur := ly.Dur;
    if ly.ParamDur > 0 then dur += Min(ly.ParamDurMax, Max(0, AParam - ly.ParamBase) * ly.ParamDur);
    dur := EnsureRange(dur, 0.005, 5);
    cnt := ly.Count;
    if ly.ParamCountDiv > 0 then cnt += Min(ly.ParamCountMax, Max(0, AParam) div ly.ParamCountDiv);
    cnt := Min(cnt, 32);
    for k := 0 to cnt - 1 do
    begin
      st0 := StepOf(ly.Steps, k, 0);
      st1 := StepOf(ly.StepsEnd, k, st0);
      f0 := Max(1, ly.F0) * Power(2, (semis + st0) / 12);
      f1 := Max(1, ly.F1) * Power(2, (semis + st1) / 12);
      n := Round(dur * SfxSR);
      pre := Round(Max(0, ly.Delay + k * ly.Every) * SfxSR);
      SetLength(d, pre + n);
      for i := 0 to pre - 1 do d[i] := 0;   // the delay (d is reused)
      ph := 0;
      for i := 0 to n - 1 do
      begin
        t := i / SfxSR;
        f := f0 * Power(f1 / f0, t / dur);
        ph += 2 * Pi * f / SfxSR;
        if (ly.Attack > 0) and (t < ly.Attack) then env := t / ly.Attack
        else env := Exp(-(t - Max(0, ly.Attack)) * ly.Decay / dur);
        case ly.Shape of
          shSoft: s := Sin(ph) + 0.3 * Sin(3 * ph) + 0.12 * Sin(5 * ph);
          shBell: s := Sin(ph) + 0.45 * Sin(2.76 * ph) * Exp(-t * 18);
          shSquare: if Sin(ph) >= 0 then s := 0.6 else s := -0.6;
          shSaw: s := (Frac(ph / (2 * Pi)) * 2 - 1) * 0.7;
          shTriangle: s := 1 - 4 * Abs(Frac(ph / (2 * Pi)) - 0.5);
          shNoise: s := Noise;
        else
          s := Sin(ph);
        end;
        s := s * env;
        if (ly.Noise > 0) and (ly.NoiseDur > 0) and (t < ly.NoiseDur) then
        begin
          nz := Noise;
          s += nz * ly.Noise * (1 - t / ly.NoiseDur);
        end;
        d[pre + i] := s;
      end;
      pan := ly.Pan;
      if cnt > 1 then pan += (k - (cnt - 1) / 2) * ly.PanSpread;
      if ly.PanAlt then
      begin
        if k mod 2 = 0 then pan += 1 else pan -= 1;
      end;
      AEmit(d, ly.Gain, EnsureRange(pan, -1, 1));
    end;
  end;
end;

procedure SfxMixStereo(const ADef: TSfxDef; AParam: Integer; out L, R: TSfxData);
var
  m: TSfxMixer;
  nz: Cardinal;
begin
  m := TSfxMixer.Create;
  try
    nz := 22695477;
    SfxRender(ADef, AParam, @m.Emit, nz);
    L := m.L;
    R := m.R;
  finally
    m.Free;
  end;
end;

{ ------------------------------------------------------------------ files }

function F2S(V: Single): string;
begin
  Result := FormatFloat('0.#####', V, FS);
end;

function LoadSfxFile(const AFile: string; var ABank: TSfxBank): Boolean;
var
  ini: TMemIniFile;
  k, i, n: Integer;
  sec: string;
  ly: TSfxLayer;

  function F(const AKey: string; ADefault: Single): Single;
  begin
    Result := StrToFloatDef(Trim(ini.ReadString(sec, AKey, '')), ADefault, FS);
  end;

begin
  Result := False;
  if not FileExists(AFile) then Exit;
  try
    ini := TMemIniFile.Create(AFile);
    try
      for k := 0 to SfxCount - 1 do
      begin
        n := ini.ReadInteger(SfxNames[k], 'Layers', -1);
        if n < 0 then Continue;          // missing sound: keep the default
        n := Min(n, MaxSfxLayers);
        SetLength(ABank[k].Layers, n);
        for i := 0 to n - 1 do
        begin
          sec := SfxNames[k] + '.' + IntToStr(i + 1);
          ly := DefaultSfxLayer;
          ly.Shape := ShapeByName(ini.ReadString(sec, 'Shape', 'sine'));
          ly.F0 := F('F0', 440);
          ly.F1 := F('F1', ly.F0);
          ly.Dur := EnsureRange(F('Dur', 0.2), 0.005, 5);
          ly.Attack := Max(0, F('Attack', 0.005));
          ly.Decay := Max(0, F('Decay', 5));
          ly.Delay := Max(0, F('Delay', 0));
          ly.Gain := EnsureRange(F('Gain', 0.2), 0, 2);
          ly.Pan := EnsureRange(F('Pan', 0), -1, 1);
          ly.Noise := Max(0, F('Noise', 0));
          ly.NoiseDur := Max(0, F('NoiseDur', 0));
          ly.Count := EnsureRange(ini.ReadInteger(sec, 'Count', 1), 0, 32);
          ly.Every := Max(0, F('Every', 0));
          ly.Steps := ini.ReadString(sec, 'Steps', '');
          ly.StepsEnd := ini.ReadString(sec, 'StepsEnd', '');
          ly.PanSpread := F('PanSpread', 0);
          ly.PanAlt := ini.ReadBool(sec, 'PanAlt', False);
          ly.ParamBase := ini.ReadInteger(sec, 'ParamBase', 2);
          ly.ParamSemis := F('ParamSemis', 0);
          ly.ParamSemisMax := F('ParamSemisMax', 0);
          ly.ParamDur := F('ParamDur', 0);
          ly.ParamDurMax := F('ParamDurMax', 0);
          ly.ParamCountDiv := Max(0, ini.ReadInteger(sec, 'ParamCountDiv', 0));
          ly.ParamCountMax := Max(0, ini.ReadInteger(sec, 'ParamCountMax', 0));
          ABank[k].Layers[i] := ly;
        end;
      end;
    finally
      ini.Free;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

procedure SaveSfxFile(const AFile: string; const ABank: TSfxBank);
var
  sl: TStringList;
  k, i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Add('; Neon game sound effects - edit with NeonSfxEditor (NeonGrid SDL3 GPU Tools) or by hand.');
    sl.Add('; [name] Layers=n, then [name.1] .. [name.n]: Shape (sine soft bell square saw triangle');
    sl.Add('; noise), F0/F1 Hz, Dur/Attack/Delay s, Decay, Gain, Pan, Noise/NoiseDur, Count/Every,');
    sl.Add('; Steps/StepsEnd (semitones per repeat), PanSpread, PanAlt, Param* (game parameter).');
    for k := 0 to SfxCount - 1 do
    begin
      sl.Add('');
      sl.Add('; ' + SfxInfo[k]);
      sl.Add('[' + SfxNames[k] + ']');
      sl.Add('Layers=' + IntToStr(Length(ABank[k].Layers)));
      for i := 0 to High(ABank[k].Layers) do
        with ABank[k].Layers[i] do
        begin
          sl.Add('[' + SfxNames[k] + '.' + IntToStr(i + 1) + ']');
          sl.Add('Shape=' + ShapeNames[Shape]);
          sl.Add('F0=' + F2S(F0));
          sl.Add('F1=' + F2S(F1));
          sl.Add('Dur=' + F2S(Dur));
          sl.Add('Attack=' + F2S(Attack));
          sl.Add('Decay=' + F2S(Decay));
          sl.Add('Delay=' + F2S(Delay));
          sl.Add('Gain=' + F2S(Gain));
          sl.Add('Pan=' + F2S(Pan));
          sl.Add('Noise=' + F2S(Noise));
          sl.Add('NoiseDur=' + F2S(NoiseDur));
          sl.Add('Count=' + IntToStr(Count));
          sl.Add('Every=' + F2S(Every));
          sl.Add('Steps=' + Steps);
          sl.Add('StepsEnd=' + StepsEnd);
          sl.Add('PanSpread=' + F2S(PanSpread));
          sl.Add('PanAlt=' + IntToStr(Ord(PanAlt)));
          sl.Add('ParamBase=' + IntToStr(ParamBase));
          sl.Add('ParamSemis=' + F2S(ParamSemis));
          sl.Add('ParamSemisMax=' + F2S(ParamSemisMax));
          sl.Add('ParamDur=' + F2S(ParamDur));
          sl.Add('ParamDurMax=' + F2S(ParamDurMax));
          sl.Add('ParamCountDiv=' + IntToStr(ParamCountDiv));
          sl.Add('ParamCountMax=' + IntToStr(ParamCountMax));
        end;
    end;
    sl.SaveToFile(AFile);
  finally
    sl.Free;
  end;
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

end.
