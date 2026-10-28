unit uGameAudio;

{ Synthesized audio, plus the announcer voice clips (uVoice: "Combo!" ...).
  Sound effects (uGameSfx, defined in the .sfx file) are rendered once into
  float buffers when triggered; the
  background music (uGameMusic) is synthesized live. Both are mixed by the
  SDL3 audio stream callback (44.1 kHz, stereo 16 bit) with separate music and
  effect volumes. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, SDL3, uTrailGame, uGameMusic, uGameSfx, uVoice;

type
  TSingleArray = array of Single;

  TVoice = record
    Data: array of Single;
    Pos: Integer;
    Gain, Pan: Single;
    Speech: Boolean;           // an announcer clip (a new one cuts the old one)
  end;

  TGameAudio = class
  private
    FStream: PSDL_AudioStream;
    FLock: TRTLCriticalSection;
    FVoices: array of TVoice;
    FMix: array of SmallInt;
    FMixL, FMixR: array of Single;
    FMusic: TGameMusic;
    FNoise: Cardinal;
    function Noise: Single;
    procedure AddVoice(const AData: array of Single; AGain, APan: Single);
  public
    VoiceVolume: Single;     // announcer, 0 = off
    Sfx: TSfxBank;           // the sound definitions (main thread only)
    Muted: Boolean;
    Volume: Single;          // master
    MusicVolume: Single;     // 0..1
    SfxVolume: Single;       // 0..1
    { 0 = calm menu music, 1 = full groove in game }
    procedure SetMusicIntensity(AValue: Single);
    { pause: muffled, quieter music }
    procedure SetMuffle(AOn: Boolean);
    procedure SelectSong(AIndex: Integer);
    function CurrentSong: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Play(ASound: TGameSound; AParam: Integer);
    { the announcer says a clip of uVoice ("combo3", "great" ...) }
    procedure Say(const AClip: string);
    { the song definitions changed: fade the current song out and in again }
    procedure ReloadMusic;
    procedure Render(AOut: PSmallInt; AFrames: Integer);
    function Ok: Boolean;
  end;

implementation

const
  SR = SfxSR;

procedure AudioCallback(userdata: pointer; stream: PSDL_AudioStream;
  additional_amount: longint; total_amount: longint); cdecl;
var
  A: TGameAudio;
  frames: Integer;
begin
  A := TGameAudio(userdata);
  frames := additional_amount div 4;
  if frames <= 0 then Exit;
  if Length(A.FMix) < frames * 2 then SetLength(A.FMix, frames * 2);
  A.Render(@A.FMix[0], frames);
  SDL_PutAudioStreamData(stream, @A.FMix[0], frames * 4);
end;

{ TGameAudio }

constructor TGameAudio.Create;
var
  spec: TSDL_AudioSpec;
begin
  inherited Create;
  InitCriticalSection(FLock);
  FNoise := 22695477;
  Volume := 1;
  MusicVolume := 0.6;
  SfxVolume := 0.8;
  Sfx := DefaultSfxBank;
  FMusic := TGameMusic.Create(SR);
  VoiceVolume := 1;
  LoadVoices([ExtractFilePath(ParamStr(0)) + 'voice', ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Shared\Voice'], SR);
  spec.format := SDL_AUDIO_S16;
  spec.channels := 2;
  spec.freq := SR;
  FStream := SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, @spec, @AudioCallback, Self);
  if FStream <> nil then SDL_ResumeAudioStreamDevice(FStream);
end;

destructor TGameAudio.Destroy;
begin
  if FStream <> nil then SDL_DestroyAudioStream(FStream);
  FMusic.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TGameAudio.SetMusicIntensity(AValue: Single);
begin
  FMusic.TargetIntensity := AValue;
end;

procedure TGameAudio.SetMuffle(AOn: Boolean);
begin
  if AOn then FMusic.MuffleTarget := 1 else FMusic.MuffleTarget := 0;
end;

procedure TGameAudio.SelectSong(AIndex: Integer);
begin
  FMusic.SelectSong(AIndex);
end;

function TGameAudio.CurrentSong: Integer;
begin
  Result := FMusic.CurrentSong;
end;

function TGameAudio.Ok: Boolean;
begin
  Result := FStream <> nil;
end;

function TGameAudio.Noise: Single;
begin
  FNoise := FNoise * 1664525 + 1013904223;
  Result := ((FNoise shr 8) and $FFFF) / 32768 - 1;
end;

procedure TGameAudio.AddVoice(const AData: array of Single; AGain, APan: Single);
var
  v: TVoice;
  i: Integer;
begin
  if Muted or (FStream = nil) or (Length(AData) = 0) then Exit;
  SetLength(v.Data, Length(AData));
  for i := 0 to High(AData) do v.Data[i] := AData[i];
  v.Pos := 0;
  v.Gain := AGain;
  v.Pan := APan;
  v.Speech := False;
  EnterCriticalSection(FLock);
  try
    if Length(FVoices) < 24 then
    begin
      SetLength(FVoices, Length(FVoices) + 1);
      FVoices[High(FVoices)] := v;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TGameAudio.Play(ASound: TGameSound; AParam: Integer);
var
  k: Integer;
begin
  if Muted then Exit;
  { the sound definitions come from the .sfx file (uGameSfx) }
  k := Ord(ASound);
  if (k >= 0) and (k < SfxCount) then SfxRender(Sfx[k], AParam, @AddVoice, FNoise);
end;

procedure TGameAudio.Say(const AClip: string);
var
  c: TVoiceClip;
  v: TVoice;
  k: Integer;
begin
  if Muted or (FStream = nil) or (VoiceVolume <= 0) then Exit;
  c := VoiceClip(AClip);
  if Length(c) = 0 then Exit;
  v.Data := c;
  v.Pos := 0;
  v.Gain := 1.25 * VoiceVolume;
  v.Pan := 0;
  v.Speech := True;
  EnterCriticalSection(FLock);
  try
    { a new phrase cuts the one still speaking }
    for k := 0 to High(FVoices) do
      if FVoices[k].Speech then FVoices[k].Pos := Length(FVoices[k].Data);
    SetLength(FVoices, Length(FVoices) + 1);
    FVoices[High(FVoices)] := v;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TGameAudio.ReloadMusic;
begin
  FMusic.Restart(False);
end;

procedure TGameAudio.Render(AOut: PSmallInt; AFrames: Integer);
var
  i, k, j: Integer;
  l, r, s, gl, gr: Single;
begin
  if Length(FMixL) < AFrames then
  begin
    SetLength(FMixL, AFrames);
    SetLength(FMixR, AFrames);
  end;
  FillChar(FMixL[0], AFrames * SizeOf(Single), 0);
  FillChar(FMixR[0], AFrames * SizeOf(Single), 0);
  { the music keeps running while muted, so it continues in time }
  FMusic.Render(@FMixL[0], @FMixR[0], AFrames);
  EnterCriticalSection(FLock);
  try
    for i := 0 to AFrames - 1 do
    begin
      l := FMixL[i] * MusicVolume;
      r := FMixR[i] * MusicVolume;
      for k := 0 to High(FVoices) do
        with FVoices[k] do
          if Pos < Length(Data) then
          begin
            s := Data[Pos] * Gain * SfxVolume;
            gl := 1 - Max(0, Pan);
            gr := 1 + Min(0, Pan);
            l += s * gl;
            r += s * gr;
            Inc(Pos);
          end;
      if Muted then
      begin
        l := 0;
        r := 0;
      end;
      l := l * Volume;
      r := r * Volume;
      l := l / (1 + Abs(l));   // soft clip
      r := r / (1 + Abs(r));
      AOut[i * 2] := Round(l * 32000);
      AOut[i * 2 + 1] := Round(r * 32000);
    end;
    { drop finished voices }
    j := 0;
    for k := 0 to High(FVoices) do
      if FVoices[k].Pos < Length(FVoices[k].Data) then
      begin
        FVoices[j] := FVoices[k];
        Inc(j);
      end;
    SetLength(FVoices, j);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

end.
