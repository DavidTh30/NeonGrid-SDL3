unit uParticles;

{ Spark particles for Neon Trail. Simulated on the CPU (a few thousand at
  most), drawn on the GPU: the live particles are uploaded to a storage
  buffer every frame and particles_vs/ps.hlsl draw each one as a glowing
  additive quad (uGameGPU). Positions and sizes are in window pixels. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Math;

const
  MaxParticles = 4096;

type
  { layout shared with particles_vs.hlsl (32 bytes) }
  TParticleGPU = packed record
    X, Y, Size, Pad: Single;
    R, G, B, A: Single;
  end;

  TParticle = record
    X, Y, VX, VY, Life, MaxLife, Size, Delay: Single;
    R, G, B: Single;
  end;

  TParticles = class
  private
    FP: array of TParticle;
    FCount: Integer;
    FRng: Cardinal;
    function Rand: Single;
  public
    Gravity, Drag: Single;
    GPU: array of TParticleGPU;
    constructor Create;
    { a burst of ACount sparks around (X, Y); ASpeed in px/s; colour 0..1 }
    procedure Burst(X, Y: Single; ACount: Integer; R, G, B, ASpeed, ASize, ALife: Single;
      ADelay: Single = 0);
    { an expanding ring of sparks }
    procedure Ring(X, Y: Single; ACount: Integer; R, G, B, ASpeed, ASize, ALife: Single;
      ADelay: Single = 0);
    procedure Update(dt: Single);
    { fills GPU[0..Result-1] with the visible particles }
    function Build: Integer;
    procedure Clear;
    property Count: Integer read FCount;
  end;

implementation

constructor TParticles.Create;
begin
  inherited Create;
  SetLength(FP, MaxParticles);
  SetLength(GPU, MaxParticles);
  FRng := 2463534242;
  Gravity := 90;
  Drag := 2.2;
end;

function TParticles.Rand: Single;
begin
  FRng := FRng xor (FRng shl 13);
  FRng := FRng xor (FRng shr 17);
  FRng := FRng xor (FRng shl 5);
  Result := (FRng and $FFFFFF) / 16777216;
end;

procedure TParticles.Clear;
begin
  FCount := 0;
end;

procedure TParticles.Burst(X, Y: Single; ACount: Integer; R, G, B, ASpeed, ASize, ALife: Single;
  ADelay: Single);
var
  i: Integer;
  a, s: Single;
  p: ^TParticle;
begin
  for i := 1 to ACount do
  begin
    if FCount >= MaxParticles then Exit;
    a := Rand * 2 * Pi;
    s := ASpeed * (0.25 + 0.75 * Sqrt(Rand));
    p := @FP[FCount];
    p^.X := X;
    p^.Y := Y;
    p^.VX := Cos(a) * s;
    p^.VY := Sin(a) * s;
    p^.MaxLife := ALife * (0.6 + 0.4 * Rand);
    p^.Life := p^.MaxLife;
    p^.Size := ASize * (0.6 + 0.6 * Rand);
    p^.Delay := ADelay;
    { slight colour variation towards white }
    p^.R := Min(1, R + 0.25 * Rand);
    p^.G := Min(1, G + 0.25 * Rand);
    p^.B := Min(1, B + 0.25 * Rand);
    Inc(FCount);
  end;
end;

procedure TParticles.Ring(X, Y: Single; ACount: Integer; R, G, B, ASpeed, ASize, ALife: Single;
  ADelay: Single);
var
  i: Integer;
  a: Single;
begin
  for i := 0 to ACount - 1 do
  begin
    if FCount >= MaxParticles then Exit;
    a := i / ACount * 2 * Pi;
    FP[FCount].X := X;
    FP[FCount].Y := Y;
    FP[FCount].VX := Cos(a) * ASpeed;
    FP[FCount].VY := Sin(a) * ASpeed;
    FP[FCount].MaxLife := ALife;
    FP[FCount].Life := ALife;
    FP[FCount].Size := ASize;
    FP[FCount].Delay := ADelay;
    FP[FCount].R := R;
    FP[FCount].G := G;
    FP[FCount].B := B;
    Inc(FCount);
  end;
end;

procedure TParticles.Update(dt: Single);
var
  i, j: Integer;
  k: Single;
begin
  k := Exp(-Drag * dt);
  j := 0;
  for i := 0 to FCount - 1 do
  begin
    with FP[i] do
    begin
      if Delay > 0 then
        Delay -= dt
      else
      begin
        Life -= dt;
        VX *= k;
        VY := VY * k + Gravity * dt;
        X += VX * dt;
        Y += VY * dt;
      end;
      if Life <= 0 then Continue;
    end;
    if j <> i then FP[j] := FP[i];
    Inc(j);
  end;
  FCount := j;
end;

function TParticles.Build: Integer;
var
  i: Integer;
  f, w: Single;
begin
  Result := 0;
  for i := 0 to FCount - 1 do
    with FP[i] do
    begin
      if Delay > 0 then Continue;
      f := Life / MaxLife;
      w := Max(0, f - 0.7) / 0.3;   // white-hot at birth
      GPU[Result].X := X;
      GPU[Result].Y := Y;
      GPU[Result].Size := Size * (0.35 + 0.65 * f);
      GPU[Result].Pad := 0;
      GPU[Result].R := R + (1 - R) * w;
      GPU[Result].G := G + (1 - G) * w;
      GPU[Result].B := B + (1 - B) * w;
      GPU[Result].A := Min(1, f * 1.6);
      Inc(Result);
    end;
end;

end.
