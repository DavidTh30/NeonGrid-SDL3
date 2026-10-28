unit uToolAudio;

{ Audio output of the Neon game tools: the game's music engine (uGameMusic)
  and one-shot sound previews (uGameSfx renders), mixed in an SDL3 audio
  stream callback (44.1 kHz, stereo, 16 bit) like the games do. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, SDL3, uGameMusic, uGameSfx;

type
  TToolVoice = record
    L, R: TSfxData;
    Pos: Integer;
  end;

  TToolAudio = class
  private
    FStream: PSDL_AudioStream;
    FLock: TRTLCriticalSection;
    FVoices: array of TToolVoice;
    FMix: array of SmallInt;
    FMixL, FMixR: array of Single;
    FPeak: Single;
  public
    Music: TGameMusic;
    MusicVolume, SfxVolume: Single;
    constructor Create;
    destructor Destroy; override;
    function Ok: Boolean;
    procedure PlayStereo(const L, R: TSfxData);
    procedure StopSounds;
    function Playing: Boolean;     // a sound preview is still running
    function Peak: Single;         // recent output level 0..1 (meter)
    procedure Render(AOut: PSmallInt; AFrames: Integer);
  end;

implementation

procedure AudioCallback(userdata: pointer; stream: PSDL_AudioStream;
  additional_amount: longint; total_amount: longint); cdecl;
var
  A: TToolAudio;
  frames: Integer;
begin
  A := TToolAudio(userdata);
  frames := additional_amount div 4;
  if frames <= 0 then Exit;
  if Length(A.FMix) < frames * 2 then SetLength(A.FMix, frames * 2);
  A.Render(@A.FMix[0], frames);
  SDL_PutAudioStreamData(stream, @A.FMix[0], frames * 4);
end;

constructor TToolAudio.Create;
var
  spec: TSDL_AudioSpec;
begin
  inherited Create;
  InitCriticalSection(FLock);
  MusicVolume := 0.8;
  SfxVolume := 1;
  Music := TGameMusic.Create(SfxSR);
  Music.TargetIntensity := 1;
  if SDL_Init(SDL_INIT_AUDIO) then
  begin
    spec.format := SDL_AUDIO_S16;
    spec.channels := 2;
    spec.freq := SfxSR;
    FStream := SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, @spec, @AudioCallback, Self);
    if FStream <> nil then SDL_ResumeAudioStreamDevice(FStream);
  end;
end;

destructor TToolAudio.Destroy;
begin
  if FStream <> nil then SDL_DestroyAudioStream(FStream);
  Music.Free;
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

function TToolAudio.Ok: Boolean;
begin
  Result := FStream <> nil;
end;

procedure TToolAudio.PlayStereo(const L, R: TSfxData);
var
  v: TToolVoice;
begin
  if (FStream = nil) or (Length(L) = 0) then Exit;
  v.L := Copy(L);
  v.R := Copy(R);
  v.Pos := 0;
  EnterCriticalSection(FLock);
  try
    if Length(FVoices) < 16 then
    begin
      SetLength(FVoices, Length(FVoices) + 1);
      FVoices[High(FVoices)] := v;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TToolAudio.StopSounds;
begin
  EnterCriticalSection(FLock);
  SetLength(FVoices, 0);
  LeaveCriticalSection(FLock);
end;

function TToolAudio.Playing: Boolean;
begin
  EnterCriticalSection(FLock);
  Result := Length(FVoices) > 0;
  LeaveCriticalSection(FLock);
end;

function TToolAudio.Peak: Single;
begin
  Result := FPeak;
end;

procedure TToolAudio.Render(AOut: PSmallInt; AFrames: Integer);
var
  i, k, j: Integer;
  ml, mr, pk: Single;
begin
  if Length(FMixL) < AFrames then
  begin
    SetLength(FMixL, AFrames);
    SetLength(FMixR, AFrames);
  end;
  FillChar(FMixL[0], AFrames * SizeOf(Single), 0);
  FillChar(FMixR[0], AFrames * SizeOf(Single), 0);
  Music.Render(@FMixL[0], @FMixR[0], AFrames);
  pk := 0;
  EnterCriticalSection(FLock);
  try
    for i := 0 to AFrames - 1 do
    begin
      ml := FMixL[i] * MusicVolume;
      mr := FMixR[i] * MusicVolume;
      for k := 0 to High(FVoices) do
        if FVoices[k].Pos < Length(FVoices[k].L) then
        begin
          ml += FVoices[k].L[FVoices[k].Pos] * SfxVolume;
          mr += FVoices[k].R[FVoices[k].Pos] * SfxVolume;
          Inc(FVoices[k].Pos);
        end;
      ml := ml / (1 + Abs(ml));   // soft clip, as in the games
      mr := mr / (1 + Abs(mr));
      pk := Max(pk, Max(Abs(ml), Abs(mr)));
      AOut[i * 2] := Round(ml * 32000);
      AOut[i * 2 + 1] := Round(mr * 32000);
    end;
    j := 0;
    for k := 0 to High(FVoices) do
      if FVoices[k].Pos < Length(FVoices[k].L) then
      begin
        FVoices[j] := FVoices[k];
        Inc(j);
      end;
    SetLength(FVoices, j);
  finally
    LeaveCriticalSection(FLock);
  end;
  FPeak := Max(pk, FPeak * 0.85);
end;

end.
