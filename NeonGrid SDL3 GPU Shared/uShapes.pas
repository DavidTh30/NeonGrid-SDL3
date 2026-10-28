unit uShapes;

{ The geometry shapes of the dots and beads of Neon Beads and Neon Trail
  (shared unit). A shape is a closed outline of points around the centre,
  in units of the dot radius (x right, y down; a point should stay within
  ShapeReach so the glow fits the sprite), optionally smoothed into a curve
  (Catmull-Rom). No points = an exact circle.

  The shapes live in NeonBeads.shapes / NeonTrail.shapes next to the games
  (INI text, [Shape N] with Name, Smooth, Points="x,y x,y ..."); the
  defaults (DefaultShapes) are the 8 original shapes (0 circle, 1 square,
  2 diamond, 3 triangle, 4 hexagon, 5 star, 6 flower, 7 heart - the numbers
  the .visuals files use) and a few more. The games reload the file while
  they run; the editor is NeonShapeEditor (NeonGrid SDL3 GPU Tools). The
  dot shape and the bead shape of the .visuals files pick a shape by number. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, IniFiles, BGRABitmapTypes;

const
  ShapeReach = 1.35;     // the sprite has room for points this far out
  MaxShapes = 64;

type
  TShapeDef = record
    Name: string;
    Smooth: Boolean;
    Pts: array of TPointF;     // empty = circle
  end;
  TShapeList = array of TShapeDef;

var
  Shapes: TShapeList;
  ShapesStamp: Integer = 0;    // changes when the shapes change (sprites are rebuilt)

procedure DefaultShapes;
function DefaultShapeList: TShapeList;
function LoadShapesFile(const AFile: string): Boolean;
procedure SaveShapesFile(const AFile: string);
function ShapeCount: Integer;
function ShapeIsCircle(AIndex: Integer): Boolean;
{ the outline of shape AIndex at (ACx, ACy), radius AR (smoothed if asked) }
function ShapeOutline(AIndex: Integer; ACx, ACy, AR: Single): ArrayOfTPointF;
{ the points of a smoothed outline (Catmull-Rom, ASteps per segment) }
function SmoothPts(const APts: array of TPointF; ASteps: Integer): ArrayOfTPointF;

implementation

var
  FS: TFormatSettings;

function ShapeCount: Integer;
begin
  Result := Length(Shapes);
end;

function ShapeIsCircle(AIndex: Integer): Boolean;
begin
  Result := (AIndex < 0) or (AIndex >= Length(Shapes)) or (Length(Shapes[AIndex].Pts) < 3);
end;

function SmoothPts(const APts: array of TPointF; ASteps: Integer): ArrayOfTPointF;
var
  n, i, s, k: Integer;
  p0, p1, p2, p3: TPointF;
  t, t2, t3: Single;
begin
  n := Length(APts);
  SetLength(Result, n * ASteps);
  k := 0;
  for i := 0 to n - 1 do
  begin
    p0 := APts[(i - 1 + n) mod n];
    p1 := APts[i];
    p2 := APts[(i + 1) mod n];
    p3 := APts[(i + 2) mod n];
    for s := 0 to ASteps - 1 do
    begin
      t := s / ASteps;
      t2 := t * t;
      t3 := t2 * t;
      Result[k].x := 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
        (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);
      Result[k].y := 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
        (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
      Inc(k);
    end;
  end;
end;

function ShapeOutline(AIndex: Integer; ACx, ACy, AR: Single): ArrayOfTPointF;
var
  src: ArrayOfTPointF;
  i: Integer;
begin
  if ShapeIsCircle(AIndex) then
  begin
    SetLength(Result, 72);
    for i := 0 to 71 do Result[i] := PointF(ACx + Cos(i / 72 * 2 * Pi) * AR, ACy + Sin(i / 72 * 2 * Pi) * AR);
    Exit;
  end;
  if Shapes[AIndex].Smooth then src := SmoothPts(Shapes[AIndex].Pts, 8)
  else src := Copy(Shapes[AIndex].Pts);
  SetLength(Result, Length(src));
  for i := 0 to High(src) do Result[i] := PointF(ACx + src[i].x * AR, ACy + src[i].y * AR);
end;

{ ---- the default shapes (the original formulas of the renderers) }

function MakeShape(const AName: string; ASmooth: Boolean; const APts: array of TPointF): TShapeDef;
var
  i: Integer;
begin
  Result.Name := AName;
  Result.Smooth := ASmooth;
  SetLength(Result.Pts, Length(APts));
  for i := 0 to High(APts) do Result.Pts[i] := APts[i];
end;

function Original(AKind: Integer): TShapeDef;
const
  Names: array[0..7] of string = ('Circle', 'Square', 'Diamond', 'Triangle', 'Hexagon', 'Star', 'Flower', 'Heart');
var
  i, n: Integer;
  a, rr, hx, hy: Single;
  p: array of TPointF;
begin
  case AKind of
    1, 2: n := 4;
    3: n := 3;
    4: n := 6;
    5: n := 10;
  else
    n := 72;
  end;
  if AKind = 0 then n := 0;
  SetLength(p, n);
  for i := 0 to n - 1 do
  begin
    a := i / n * 2 * Pi;
    case AKind of
      1: begin a := a + Pi / 4; rr := 1.2; end;
      2: rr := 1.15;
      3: begin a := a - Pi / 2; rr := 1.3; end;
      4: rr := 1.05;
      5: begin a := a - Pi / 2; if i mod 2 = 0 then rr := 1.3 else rr := 0.55; end;
      6: rr := 0.78 + 0.27 * Cos(5 * a);
    else
      rr := 1;
    end;
    if AKind = 7 then
    begin
      hx := 16 * Power(Sin(a), 3);
      hy := -(13 * Cos(a) - 5 * Cos(2 * a) - 2 * Cos(3 * a) - Cos(4 * a));
      p[i] := PointF(hx / 15, (hy + 2) / 15);
    end
    else if AKind = 3 then
      p[i] := PointF(Cos(a) * rr, Sin(a) * rr + 0.15)
    else
      p[i] := PointF(Cos(a) * rr, Sin(a) * rr);
  end;
  Result := MakeShape(Names[AKind], False, p);
end;

function Regular(const AName: string; ASides: Integer; AR, ARot: Single): TShapeDef;
var
  i: Integer;
  p: array of TPointF;
begin
  SetLength(p, ASides);
  for i := 0 to ASides - 1 do
    p[i] := PointF(Cos(ARot + i / ASides * 2 * Pi) * AR, Sin(ARot + i / ASides * 2 * Pi) * AR);
  Result := MakeShape(AName, False, p);
end;

function DefaultShapeList: TShapeList;
var
  k: Integer;
begin
  SetLength(Result, 13);
  for k := 0 to 7 do Result[k] := Original(k);
  Result[8] := Regular('Pentagon', 5, 1.12, -Pi / 2);
  Result[9] := Regular('Octagon', 8, 1.04, Pi / 8);
  Result[10] := MakeShape('Cross', False, [PointF(-0.35, -1.1), PointF(0.35, -1.1), PointF(0.35, -0.35),
    PointF(1.1, -0.35), PointF(1.1, 0.35), PointF(0.35, 0.35), PointF(0.35, 1.1), PointF(-0.35, 1.1),
    PointF(-0.35, 0.35), PointF(-1.1, 0.35), PointF(-1.1, -0.35), PointF(-0.35, -0.35)]);
  Result[11] := MakeShape('Drop', True, [PointF(0, -1.3), PointF(0.55, -0.35), PointF(0.85, 0.35),
    PointF(0.5, 0.92), PointF(0, 1.05), PointF(-0.5, 0.92), PointF(-0.85, 0.35), PointF(-0.55, -0.35)]);
  Result[12] := MakeShape('Moon', True, [PointF(0.2, -1.1), PointF(-0.55, -0.85), PointF(-1, 0),
    PointF(-0.55, 0.85), PointF(0.2, 1.1), PointF(-0.1, 0.55), PointF(-0.25, 0), PointF(-0.1, -0.55)]);
end;

procedure DefaultShapes;
begin
  Shapes := DefaultShapeList;
  Inc(ShapesStamp);
end;

function LoadShapesFile(const AFile: string): Boolean;
var
  ini: TMemIniFile;
  i, k, n: Integer;
  sec, s: string;
  parts, xy: TStringArray;
  list: TShapeList;
begin
  Result := False;
  if not FileExists(AFile) then Exit;
  SetLength(list, 0);
  try
    ini := TMemIniFile.Create(AFile);
    try
      for i := 0 to MaxShapes - 1 do
      begin
        sec := 'Shape ' + IntToStr(i);
        if not ini.SectionExists(sec) then Break;
        n := Length(list);
        SetLength(list, n + 1);
        list[n].Name := ini.ReadString(sec, 'Name', 'Shape ' + IntToStr(i));
        list[n].Smooth := ini.ReadBool(sec, 'Smooth', False);
        SetLength(list[n].Pts, 0);
        s := Trim(ini.ReadString(sec, 'Points', ''));
        if s = '' then Continue;
        parts := s.Split([' '], TStringSplitOptions.ExcludeEmpty);
        for k := 0 to High(parts) do
        begin
          xy := parts[k].Split([',']);
          if Length(xy) <> 2 then Continue;
          SetLength(list[n].Pts, Length(list[n].Pts) + 1);
          list[n].Pts[High(list[n].Pts)] := PointF(
            EnsureRange(StrToFloatDef(xy[0], 0, FS), -ShapeReach, ShapeReach),
            EnsureRange(StrToFloatDef(xy[1], 0, FS), -ShapeReach, ShapeReach));
        end;
      end;
    finally
      ini.Free;
    end;
    if Length(list) > 0 then
    begin
      Shapes := list;
      Result := True;
    end;
  except
    Result := False;
  end;
  Inc(ShapesStamp);
end;

procedure SaveShapesFile(const AFile: string);
var
  sl: TStringList;
  i, k: Integer;
  s: string;
begin
  sl := TStringList.Create;
  try
    sl.Add('; Neon shapes of the dots and beads - edit with NeonShapeEditor (NeonGrid SDL3 GPU Tools).');
    sl.Add('; [Shape N] = shape number N of the .visuals files (Dot shape, Bead shape).');
    sl.Add('; Points: x,y pairs in dot radii around the centre (y down), keep them within ' +
      FormatFloat('0.##', ShapeReach, FS) + '; none = a circle.');
    sl.Add('; Smooth=1 draws a curve through the points. The games reload this file while they run.');
    for i := 0 to High(Shapes) do
    begin
      sl.Add('');
      sl.Add('[Shape ' + IntToStr(i) + ']');
      sl.Add('Name=' + Shapes[i].Name);
      sl.Add('Smooth=' + IntToStr(Ord(Shapes[i].Smooth)));
      s := '';
      for k := 0 to High(Shapes[i].Pts) do
      begin
        if k > 0 then s += ' ';
        s += FormatFloat('0.####', Shapes[i].Pts[k].x, FS) + ',' + FormatFloat('0.####', Shapes[i].Pts[k].y, FS);
      end;
      sl.Add('Points=' + s);
    end;
    sl.SaveToFile(AFile);
  finally
    sl.Free;
  end;
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  DefaultShapes;

end.
