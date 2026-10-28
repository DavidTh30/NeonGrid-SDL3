unit uGameHud;

{ HUD of Neon Trail: drawn on the CPU into a transparent TBGRABitmap the size
  of the window (BGRABitmap panels + SDL3_ttf text), uploaded to the GPU only
  when it changes and alpha-blended over the frame by overlay_ps.hlsl. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, SDL3, SDL3_ttf, BGRABitmap, BGRABitmapTypes, BGRAGradientScanner, uShooterGame, uAchievements, uMenuFx, uGameFx;

type
  TLayout = record
    W, H: Integer;            // window pixels
    Cell: Single;             // bead spacing in pixels
    BoardX0, BoardY0: Single; // pixel centre of board cell (0, 0)
    TopH, BottomH: Integer;   // HUD bars
  end;

  THudFont = (hfSmall, hfMid, hfBig, hfTitle);

  TMenuItem = record
    Caption, Value: string;   // Value = '' for plain actions
  end;

  { filled in by the program every frame while the menu is shown }
  TMenuModel = record
    Active: Boolean;          // drawn on the title screen and while paused
    Title: string;            // animated heading ('NEON TRAIL' / 'PAUSED')
    NowPlaying: string;       // current music track
    Screen: Integer;          // 0 = main menu, 1 = options, 2 = pause, 3 = high scores, 4 = achievements
    Items: array of TMenuItem;
    Sel: Integer;
    Time: Single;             // seconds since the menu appeared (title intro)
    ItemTime: Single;         // seconds since this screen appeared (items slide in)
    Clock: Single;            // running time for the loops
  end;

  { a heading drawn animated every frame (see HeadTxt / DrawHeads) }
  THudHead = record
    F: THudFont;
    S: string;
    X, Y: Single;
    C: TBGRAPixel;
  end;

  TGameHud = class
  private
    FFonts: array[THudFont] of PTTF_Font;
    FFontSize: Integer;
    FFontFile, FFontFileBold: string;
    FCache: TStringList;
    FSignature, FBaseSig: string;
    FBase: TBGRABitmap;       // bars + panels + text, redrawn only when they change
    FHadPopups: Boolean;
    FTarget: TBGRABitmap;
    FGlow: TStringList;       // blurred title glyphs
    FTitleY, FItemY0, FItemStep, FPanelL, FPanelR: Single;
    FPanelT, FPanelB: Single;     // menu panel top / bottom (lights run along it)
    FHeads: array of THudHead;    // headings of the current base, animated per frame
    FHeadKey: string;
    FHeadT0: Double;              // when these headings appeared
    FStats: array of THudStat;    // Level / Score / Best of the base, drawn every frame
    FStatSt: array[0..StatCount - 1] of THudStatState;
    { menu items that are not selected (hudmenuitems.inc) }
    FItSt: array of TMenuItemState;
    FItSel, FItScreen: Integer;
    FMParts: array of TMenuPart;  // selector trail particles
    FPartT: Double;
    FArtCache: TStringList;       // pixel art / neon tube / LED letters
    { frames and status bar extras (hudframes.inc) }
    FFrames, FFramesPrev: array of THudFrame;
    FHintsL: array of THudHint;
    FBarOn: Boolean;
    FBarX1, FBarY1, FBarX2, FBarY2, FBarFrac: Single;
    FBarC: TBGRAPixel;
    procedure DrawBorder(const F: THudFrame);
    procedure DrawFrames;
    function FramesBusy: Boolean;
    procedure BarFill(X1, Y1, X2, Y2, AFrac: Single; const C: TBGRAPixel);
    procedure HintTxt(AFont: THudFont; const S: string; X, Y: Single; const C: TBGRAPixel; AAlign: Integer);
    procedure DrawStatusX;
    procedure StatTxtS(AKind: Integer; AFont: THudFont; const AText: string; AValue: Int64;
      X, Y: Single; const C: TBGRAPixel; AAlign: Integer);
    function ArtBmp(AFont: THudFont; const S: string; AArt, APix: Integer): TBGRABitmap;
    procedure BlendRows(ASrc: TBGRABitmap; CX, CY, SX, SY: Single; const ARows: array of TBGRAPixel;
      AOpacity: Single);
    procedure ItemGeom(AIndex: Integer; X, Y, W, H: Single);
    function ItemColour(AIndex: Integer; T: Single): TBGRAPixel;
    procedure SpawnTrail(AIndex: Integer);
    procedure ItemsTrack;
    procedure DrawIdleItem(AIndex: Integer; const S: string; X, Y, AOpacity, T: Single);
    procedure DrawMenuParts;
    procedure StatTxt(AKind: Integer; AFont: THudFont; const APrefix: string; AValue: Int64;
      X, Y: Single; const C: TBGRAPixel; AAlign: Integer);
    procedure DrawStats;
    function StatsBusy: Boolean;
    function TextAdvance(AFont: THudFont; const S: string): Single;
    procedure BlendXf(ASrc: TBGRABitmap; CX, CY, SX, SY: Single; const C: TBGRAPixel; AOpacity: Single);
    function GlowBmp(const ACh: string): TBGRABitmap;
    procedure Blend(ASrc: TBGRABitmap; X, Y: Integer; const C: TBGRAPixel; AOpacity: Single);
    procedure DrawTitle(const L: TLayout);
    procedure DrawMenuItems(const L: TLayout);
    function GlowText(AFont: THudFont; const S: string): TBGRABitmap;
    procedure BlendShine(ASrc: TBGRABitmap; X, Y: Integer; const C: TBGRAPixel; AOpacity, ACx, AW: Single);
    procedure TxtTint(AFont: THudFont; const S: string; X, Y: Single; const C: TBGRAPixel;
      AAlignX: Integer; AOpacity, AGlow: Single);
    procedure HeadTxt(AFont: THudFont; const S: string; X, Y: Single; const C: TBGRAPixel);
    procedure DrawHeads(const L: TLayout);
    procedure DrawPanelLights(const L: TLayout);
    procedure DrawTitleLights(const L: TLayout; AW, T: Single);
    procedure DrawBase(G: TShooterGame; const L: TLayout);
    procedure DrawAim(G: TShooterGame; const L: TLayout);
    procedure DrawToasts(const L: TLayout);
    function TextBmp(AFont: THudFont; const S: string; const C: TBGRAPixel): TBGRABitmap;
    procedure Txt(AFont: THudFont; const S: string; X, Y: Single; const C: TBGRAPixel;
      AAlignX: Integer = -1; AOpacity: Byte = 255);
    procedure Panel(X1, Y1, X2, Y2: Single; AAlpha: Byte = 190; AKind: Integer = frBox);
    procedure OpenFonts(AH: Integer);
  public
    Bmp: TBGRABitmap;
    StartLevel: Integer;
    Muted: Boolean;
    Menu: TMenuModel;
    ItemRects: array of TRect;   // menu items in window pixels (mouse hit test)
    Ach: TAchievements;          // owned by the program
    NameEntry: Boolean;          // typing a name for the high-score table
    NameText: string;
    CodeText: string;            // CHEAT CODE screen: the letters typed / pasted
    CodeMsg: string;             // CHEAT CODE screen: error message ('' = none)
    LevelCode: string;           // the code of the completed level ('' = none)
    CodeCopied: Boolean;         // the level code went to the clipboard
    NewRank: Integer;            // row to highlight in the high scores (-1 none)
    ScoreRank: Integer;          // place the game-over score would take (-1 none)
    constructor Create;
    destructor Destroy; override;
    { redraws when anything visible changed; returns True if it did }
    function Update(G: TShooterGame; const L: TLayout): Boolean;
  end;

function BeadColour(AIndex: Integer): TBGRAPixel;

implementation

const
  Cyan: TBGRAPixel = (blue: 240; green: 220; red: 70; alpha: 255);
  White: TBGRAPixel = (blue: 245; green: 240; red: 240; alpha: 255);
  Grey: TBGRAPixel = (blue: 200; green: 175; red: 160; alpha: 255);
  Green: TBGRAPixel = (blue: 110; green: 235; red: 120; alpha: 255);
  Pink: TBGRAPixel = (blue: 170; green: 70; red: 245; alpha: 255);

function BeadColour(AIndex: Integer): TBGRAPixel;
begin
  if (AIndex < 0) or (AIndex >= MaxColours) then Exit(White);
  Result := BGRA(BeadRGB[AIndex, 0], BeadRGB[AIndex, 1], BeadRGB[AIndex, 2]);
end;

function FontPath(const AName: string): string;
var
  dir: string;
begin
  dir := GetEnvironmentVariable('WINDIR');
  if dir = '' then dir := 'C:\Windows';
  Result := IncludeTrailingPathDelimiter(dir) + 'Fonts\' + AName;
end;

{ TGameHud }

constructor TGameHud.Create;
begin
  inherited Create;
  FCache := TStringList.Create;
  FCache.OwnsObjects := True;
  FCache.Sorted := True;
  FGlow := TStringList.Create;
  FGlow.OwnsObjects := True;
  FGlow.Sorted := True;
  FArtCache := TStringList.Create;
  FArtCache.OwnsObjects := True;
  FArtCache.Sorted := True;
  FItScreen := -1;
  FFontFile := FontPath('bahnschrift.ttf');
  if not FileExists(FFontFile) then FFontFile := FontPath('segoeui.ttf');
  FFontFileBold := FFontFile;
  if FileExists(FontPath('segoeuib.ttf')) and not FileExists(FontPath('bahnschrift.ttf')) then
    FFontFileBold := FontPath('segoeuib.ttf');
  StartLevel := 1;
  NewRank := -1;
  ScoreRank := -1;
  Bmp := TBGRABitmap.Create(1, 1, BGRAPixelTransparent);
  FBase := TBGRABitmap.Create(1, 1, BGRAPixelTransparent);
  FTarget := Bmp;
end;

destructor TGameHud.Destroy;
var
  f: THudFont;
begin
  for f := Low(THudFont) to High(THudFont) do
    if FFonts[f] <> nil then TTF_CloseFont(FFonts[f]);
  FCache.Free;
  FGlow.Free;
  FArtCache.Free;
  Bmp.Free;
  FBase.Free;
  inherited Destroy;
end;

procedure TGameHud.OpenFonts(AH: Integer);
const
  Rel: array[THudFont] of Single = (0.019, 0.026, 0.040, 0.064);
var
  f: THudFont;
begin
  if AH = FFontSize then Exit;
  FFontSize := AH;
  FCache.Clear;
  FGlow.Clear;
  FArtCache.Clear;
  for f := Low(THudFont) to High(THudFont) do
  begin
    if FFonts[f] <> nil then TTF_CloseFont(FFonts[f]);
    if f in [hfBig, hfTitle] then
      FFonts[f] := TTF_OpenFont(PAnsiChar(FFontFileBold), Max(8, AH * Rel[f]))
    else
      FFonts[f] := TTF_OpenFont(PAnsiChar(FFontFile), Max(8, AH * Rel[f]));
    if (FFonts[f] <> nil) and (f in [hfBig, hfTitle]) then
      TTF_SetFontStyle(FFonts[f], TTF_STYLE_BOLD);
  end;
end;

function TGameHud.TextBmp(AFont: THudFont; const S: string; const C: TBGRAPixel): TBGRABitmap;
var
  key: string;
  i, y: Integer;
  surf, conv: PSDL_Surface;
  col: TSDL_Color;
begin
  Result := nil;
  if (S = '') or (FFonts[AFont] = nil) then Exit;
  key := Format('%d|%.2x%.2x%.2x|%s', [Ord(AFont), C.red, C.green, C.blue, S]);
  i := FCache.IndexOf(key);
  if i >= 0 then Exit(TBGRABitmap(FCache.Objects[i]));
  col.r := C.red; col.g := C.green; col.b := C.blue; col.a := 255;
  surf := TTF_RenderText_Blended(FFonts[AFont], PAnsiChar(S), 0, col);
  if surf = nil then Exit;
  conv := SDL_ConvertSurface(surf, SDL_PIXELFORMAT_ARGB8888);  // = TBGRAPixel bytes
  SDL_DestroySurface(surf);
  if conv = nil then Exit;
  Result := TBGRABitmap.Create(conv^.w, conv^.h);
  for y := 0 to conv^.h - 1 do
    Move((PByte(conv^.pixels) + y * conv^.pitch)^, Result.ScanLine[y]^, conv^.w * 4);
  Result.InvalidateBitmap;
  SDL_DestroySurface(conv);
  if FCache.Count > 400 then FCache.Clear;
  FCache.AddObject(key, Result);
end;

procedure TGameHud.Txt(AFont: THudFont; const S: string; X, Y: Single; const C: TBGRAPixel;
  AAlignX: Integer; AOpacity: Byte);
var
  t: TBGRABitmap;
  px: Integer;
begin
  t := TextBmp(AFont, S, C);
  if t = nil then Exit;
  case AAlignX of
    0: px := Round(X - t.Width / 2);
    1: px := Round(X - t.Width);
  else
    px := Round(X);
  end;
  FTarget.PutImage(px, Round(Y - t.Height / 2), t, dmDrawWithTransparency, AOpacity);
end;



{ ---------------------------------------------------------- animated title }

function Clamp01(x: Single): Single; inline;
begin
  if x < 0 then Result := 0 else if x > 1 then Result := 1 else Result := x;
end;

function EaseOut(t: Single): Single;
begin
  t := Clamp01(t);
  Result := 1 - (1 - t) * (1 - t) * (1 - t);
end;

function EaseOutBack(t: Single): Single;
const
  c1 = 1.70158;
  c3 = c1 + 1;
begin
  t := Clamp01(t);
  Result := 1 + c3 * Power(t - 1, 3) + c1 * Sqr(t - 1);
end;

function Mix(const A, B: TBGRAPixel; t: Single): TBGRAPixel;
begin
  t := Clamp01(t);
  Result := BGRA(Round(A.red + (B.red - A.red) * t), Round(A.green + (B.green - A.green) * t),
    Round(A.blue + (B.blue - A.blue) * t));
end;

{ smooth loop through the bead colours cyan -> magenta -> amber -> violet }
function CycleColour(p: Single): TBGRAPixel;
const
  Order: array[0..3] of Integer = (1, 2, 0, 4);
var
  k: Integer;
  f: Single;

  { the menu palette: the bead colours or the custom one of uMenuFx }
  function PalColour(AIndex: Integer): TBGRAPixel;
  var
    c: Cardinal;
  begin
    if MenuFx.CustomPalette then
    begin
      c := MenuFx.Palette[AIndex];
      Result := BGRA((c shr 16) and 255, (c shr 8) and 255, c and 255);
    end
    else
      Result := BeadColour(Order[AIndex]);
  end;

begin
  p := p - Floor(p / 4) * 4;
  k := Trunc(p);
  f := p - k;
  f := f * f * (3 - 2 * f);
  Result := Mix(PalColour(k mod 4), PalColour((k + 1) mod 4), f);
end;

function TGameHud.GlowBmp(const ACh: string): TBGRABitmap;
var
  i, m: Integer;
  glyph, g: TBGRABitmap;
begin
  i := FGlow.IndexOf(ACh);
  if i >= 0 then Exit(TBGRABitmap(FGlow.Objects[i]));
  Result := nil;
  glyph := TextBmp(hfTitle, ACh, White);
  if glyph = nil then Exit;
  m := Max(6, Round(FFontSize * 0.036));
  g := TBGRABitmap.Create(glyph.Width + 2 * m, glyph.Height + 2 * m, BGRAPixelTransparent);
  g.PutImage(m, m, glyph, dmSet);
  BGRAReplace(g, g.FilterBlurRadial(m * 0.85, rbNormal));
  FGlow.AddObject(ACh, g);
  Result := g;
end;

{ draws the alpha of ASrc (white glyph / glow) in colour C over the HUD
  (straight alpha "over" compositing) }
procedure TGameHud.Blend(ASrc: TBGRABitmap; X, Y: Integer; const C: TBGRAPixel; AOpacity: Single);
var
  sx, sy, dx, dy, x0, x1: Integer;
  ps, pd: PBGRAPixel;
  a, da, oa, f1, f2: Single;
begin
  if (ASrc = nil) or (AOpacity <= 0.004) then Exit;
  x0 := Max(0, -X);
  x1 := Min(ASrc.Width, FTarget.Width - X);
  if x0 >= x1 then Exit;
  for sy := 0 to ASrc.Height - 1 do
  begin
    dy := Y + sy;
    if (dy < 0) or (dy >= FTarget.Height) then Continue;
    ps := ASrc.ScanLine[sy] + x0;
    pd := FTarget.ScanLine[dy] + X + x0;
    for sx := x0 to x1 - 1 do
    begin
      a := ps^.alpha * AOpacity / 255;
      if a > 0.004 then
      begin
        da := pd^.alpha / 255;
        oa := a + da * (1 - a);
        f1 := a / oa;
        f2 := 1 - f1;
        pd^.red := Round(C.red * f1 + pd^.red * f2);
        pd^.green := Round(C.green * f1 + pd^.green * f2);
        pd^.blue := Round(C.blue * f1 + pd^.blue * f2);
        pd^.alpha := Round(oa * 255);
      end;
      Inc(ps);
      Inc(pd);
    end;
  end;
end;

procedure TGameHud.DrawTitle(const L: TLayout);
var
  Title: string;
  i, m, gap: Integer;
  total, x, y, t, intro, op, dy, sweep, flash, glowOp: Single;
  glyph, glow: TBGRABitmap;
  col, Magenta, CyanC: TBGRAPixel;
  widths: array of Integer;
begin
  Title := Menu.Title;
  SetLength(widths, Length(Title) + 1);
  t := Menu.Clock * MenuFx.V[fxMenuSpeed];
  m := Max(6, Round(FFontSize * 0.036));
  gap := Round(FFontSize * 0.004);
  total := 0;
  for i := 1 to Length(Title) do
  begin
    glyph := TextBmp(hfTitle, Title[i], White);
    if (Title[i] = ' ') or (glyph = nil) then widths[i] := Round(FFontSize * 0.022)
    else widths[i] := glyph.Width;
    total += widths[i] + gap;
  end;
  x := L.W / 2 - total / 2;
  Magenta := BeadColour(2);
  CyanC := BeadColour(1);
  DrawTitleLights(L, total, t);
  { a white-hot flash sweeps across the letters every 3.4 s }
  sweep := (t - Floor(t / 3.4) * 3.4 - 0.4) * 9;
  for i := 1 to Length(Title) do
  begin
    if Title[i] <> ' ' then
    begin
      glyph := TextBmp(hfTitle, Title[i], White);
      glow := GlowBmp(Title[i]);
      { intro: letters drop in one after another with a little overshoot }
      intro := (Menu.Time * MenuFx.V[fxTitleIntro] - (i - 1) * 0.07) / 0.6;
      op := Clamp01(intro * 1.8);
      dy := -(1 - EaseOutBack(intro)) * L.H * 0.22;
      { idle: a wave runs through the word }
      dy += Sin(t * 2.4 - i * 0.6) * L.H * 0.006 * MenuFx.V[fxTitleWave];
      flash := Exp(-Sqr(sweep - i) * 0.5) * MenuFx.V[fxTitleFlash];
      col := CycleColour(t * MenuFx.V[fxColourSpeed] * 0.22 + i * 0.09);
      col := Mix(col, White, flash * 0.7);
      glowOp := (0.75 + 0.25 * Sin(t * 3.2 + i * 0.8) + flash * 0.6) * op * MenuFx.V[fxTitleGlow];
      y := FTitleY + dy - glyph.Height / 2;
      Blend(glow, Round(x) - m, Round(y) - m, col, Min(1, glowOp));
      Blend(glow, Round(x) - m, Round(y) - m, col, Min(1, glowOp * 0.8));
      Blend(glow, Round(x) - m, Round(y) - m, col, Min(1, glowOp * 0.5));
      { slight colour split on the edges }
      Blend(glyph, Round(x) - 2, Round(y), Magenta, 0.35 * op);
      Blend(glyph, Round(x) + 2, Round(y), CyanC, 0.35 * op);
      Blend(glyph, Round(x), Round(y), Mix(col, White, 0.22 + 0.7 * flash), op);
    end;
    x += widths[i] + gap;
  end;
end;

{ ---------------------------------------------- menu lights and headings }

function HudClock: Double;
begin
  Result := SDL_GetTicksNS / 1e9;
end;

{ the blurred halo of a whole string (cached like the title glyph glows) }
function TGameHud.GlowText(AFont: THudFont; const S: string): TBGRABitmap;
var
  key: string;
  i, m: Integer;
  glyph, g: TBGRABitmap;
begin
  key := #1 + IntToStr(Ord(AFont)) + '|' + S;
  i := FGlow.IndexOf(key);
  if i >= 0 then Exit(TBGRABitmap(FGlow.Objects[i]));
  Result := nil;
  glyph := TextBmp(AFont, S, White);
  if glyph = nil then Exit;
  m := Max(4, Round(glyph.Height * 0.35));
  g := TBGRABitmap.Create(glyph.Width + 2 * m, glyph.Height + 2 * m, BGRAPixelTransparent);
  g.PutImage(m, m, glyph, dmSet);
  BGRAReplace(g, g.FilterBlurRadial(m * 0.8, rbFast));
  if FGlow.Count > 240 then FGlow.Clear;
  FGlow.AddObject(key, g);
  Result := g;
end;

{ like Blend, but only inside a soft vertical band around ACx (a light sweep) }
procedure TGameHud.BlendShine(ASrc: TBGRABitmap; X, Y: Integer; const C: TBGRAPixel; AOpacity, ACx, AW: Single);
var
  sx, sy, dy, x0, x1: Integer;
  ps, pd: PBGRAPixel;
  a, da, oa, f1, f2: Single;
  w: array of Single;
begin
  if (ASrc = nil) or (AOpacity <= 0.004) or (AW <= 0) then Exit;
  x0 := Max(Max(0, -X), Floor(ACx - 3 * AW) - X);
  x1 := Min(Min(ASrc.Width, FTarget.Width - X), Ceil(ACx + 3 * AW) - X);
  if x0 >= x1 then Exit;
  SetLength(w, x1 - x0);
  for sx := x0 to x1 - 1 do w[sx - x0] := AOpacity * Exp(-Sqr((X + sx - ACx) / AW));
  for sy := 0 to ASrc.Height - 1 do
  begin
    dy := Y + sy;
    if (dy < 0) or (dy >= FTarget.Height) then Continue;
    ps := ASrc.ScanLine[sy] + x0;
    pd := FTarget.ScanLine[dy] + X + x0;
    for sx := x0 to x1 - 1 do
    begin
      a := ps^.alpha * w[sx - x0] / 255;
      if a > 0.004 then
      begin
        da := pd^.alpha / 255;
        oa := a + da * (1 - a);
        f1 := a / oa;
        f2 := 1 - f1;
        pd^.red := Round(C.red * f1 + pd^.red * f2);
        pd^.green := Round(C.green * f1 + pd^.green * f2);
        pd^.blue := Round(C.blue * f1 + pd^.blue * f2);
        pd^.alpha := Round(oa * 255);
      end;
      Inc(ps);
      Inc(pd);
    end;
  end;
end;

{ text in any colour without filling the text cache: the white glyph tinted
  by Blend, optionally with a halo }
procedure TGameHud.TxtTint(AFont: THudFont; const S: string; X, Y: Single; const C: TBGRAPixel;
  AAlignX: Integer; AOpacity, AGlow: Single);
var
  t, g: TBGRABitmap;
  px, py, m: Integer;
begin
  t := TextBmp(AFont, S, White);
  if t = nil then Exit;
  case AAlignX of
    0: px := Round(X - t.Width / 2);
    1: px := Round(X - t.Width);
  else
    px := Round(X);
  end;
  py := Round(Y - t.Height / 2);
  if AGlow > 0 then
  begin
    g := GlowText(AFont, S);
    if g <> nil then
    begin
      m := (g.Width - t.Width) div 2;
      Blend(g, px - m, py - m, C, Min(1, AGlow * AOpacity));
    end;
  end;
  Blend(t, px, py, C, AOpacity);
end;

{ DrawBase records the headings; DrawHeads animates them every frame }
procedure TGameHud.HeadTxt(AFont: THudFont; const S: string; X, Y: Single; const C: TBGRAPixel);
var
  n: Integer;
begin
  n := Length(FHeads);
  SetLength(FHeads, n + 1);
  FHeads[n].F := AFont;
  FHeads[n].S := S;
  FHeads[n].X := X;
  FHeads[n].Y := Y;
  FHeads[n].C := C;
end;

procedure TGameHud.DrawHeads(const L: TLayout);
var
  i, j, k, m, px, py: Integer;
  key: string;
  t, age, e, op, dy, pulse, ph, sx, len, x0, fs, a, ly: Single;
  tb, g: TBGRABitmap;
  c: TBGRAPixel;
begin
  if Length(FHeads) = 0 then Exit;
  key := '';
  for i := 0 to High(FHeads) do key += FHeads[i].S + '|';
  t := HudClock;
  if key <> FHeadKey then
  begin
    FHeadKey := key;
    FHeadT0 := t;
  end;
  age := t - FHeadT0;
  t := t * MenuFx.V[fxMenuSpeed];
  FTarget := Bmp;
  for i := 0 to High(FHeads) do
  begin
    tb := TextBmp(FHeads[i].F, FHeads[i].S, White);
    if tb = nil then Continue;
    { the heading rises into place with a little overshoot }
    e := EaseOutBack((age - i * 0.08) / 0.5);
    op := Clamp01((age - i * 0.08) / 0.25);
    dy := (1 - e) * tb.Height * 0.9 * MenuFx.V[fxHeadIntro];
    px := Round(FHeads[i].X - tb.Width / 2);
    py := Round(FHeads[i].Y - tb.Height / 2 + dy);
    c := Mix(FHeads[i].C, CycleColour(t * MenuFx.V[fxColourSpeed] * 0.3 + i * 0.7), 0.22 + 0.18 * Sin(t * 1.6 + i));
    { light lines grow out of both sides, a spark runs along each }
    len := Min(L.W * 0.16, tb.Width * 0.55) * EaseOut((age - 0.15) / 0.5) * MenuFx.V[fxHeadLines];
    ly := py + tb.Height / 2;
    if len > 4 then
      for j := 0 to 1 do
      begin
        if j = 0 then
        begin
          x0 := px - tb.Height * 0.4;
          fs := -1;
        end
        else
        begin
          x0 := px + tb.Width + tb.Height * 0.4;
          fs := 1;
        end;
        for k := 0 to 5 do
          FTarget.DrawLineAntialias(x0 + fs * len * k / 6, ly, x0 + fs * len * (k + 1) / 6, ly,
            BGRA(c.red, c.green, c.blue, Round(op * 200 * (1 - k / 6))), 1.6);
        a := Frac(t * 0.7 + j * 0.5);
        sx := x0 + fs * len * a;
        FTarget.FillEllipseAntialias(sx, ly, 5, 5, BGRA(c.red, c.green, c.blue, Round(op * 80 * (1 - a))));
        FTarget.FillEllipseAntialias(sx, ly, 2.2, 2.2, BGRA(255, 255, 255, Round(op * 230 * (1 - a))));
      end;
    { a pulsing halo in the shifting colour }
    g := GlowText(FHeads[i].F, FHeads[i].S);
    pulse := (0.55 + 0.35 * Sin(t * 3.0 + i * 1.3)) * MenuFx.V[fxHeadGlow];
    if g <> nil then
    begin
      m := (g.Width - tb.Width) div 2;
      Blend(g, px - m, py - m, c, Min(1, pulse * op));
      Blend(g, px - m, py - m, c, Min(1, pulse * op * 0.55));
    end;
    { colour split on the edges, the letters, then a light sweep }
    Blend(tb, px - 2, py, BeadColour(2), Min(1, 0.3 * op * MenuFx.V[fxHeadSplit]));
    Blend(tb, px + 2, py, BeadColour(1), Min(1, 0.3 * op * MenuFx.V[fxHeadSplit]));
    Blend(tb, px, py, Mix(c, White, 0.3), op);
    ph := Frac((t + i * 0.9) / 2.6);
    BlendShine(tb, px, py, White, Min(1, 0.95 * op * MenuFx.V[fxHeadSweep]), px - tb.Width * 0.25 + ph * tb.Width * 1.5, tb.Height * 0.55);
  end;
end;

{ the menu panel: a border breathing in the bead colours and two comets of
  light running around it }
procedure TGameHud.DrawPanelLights(const L: TLayout);
var
  w, h, r, per, d, px, py, t, f, sz: Single;
  k, j: Integer;
  c, cc: TBGRAPixel;

  procedure PerimPoint(ADist: Single; out AX, AY: Single);
  var
    a, seg: Single;
  begin
    ADist := ADist - Floor(ADist / per) * per;
    seg := w - 2 * r;                       // top edge, left to right
    if ADist < seg then begin AX := FPanelL + r + ADist; AY := FPanelT; Exit; end;
    ADist -= seg; seg := Pi * r / 2;        // top-right corner
    if ADist < seg then
    begin
      a := -Pi / 2 + ADist / r; AX := FPanelR - r + r * Cos(a); AY := FPanelT + r + r * Sin(a); Exit;
    end;
    ADist -= seg; seg := h - 2 * r;         // right edge, down
    if ADist < seg then begin AX := FPanelR; AY := FPanelT + r + ADist; Exit; end;
    ADist -= seg; seg := Pi * r / 2;        // bottom-right corner
    if ADist < seg then
    begin
      a := ADist / r; AX := FPanelR - r + r * Cos(a); AY := FPanelB - r + r * Sin(a); Exit;
    end;
    ADist -= seg; seg := w - 2 * r;         // bottom edge, right to left
    if ADist < seg then begin AX := FPanelR - r - ADist; AY := FPanelB; Exit; end;
    ADist -= seg; seg := Pi * r / 2;        // bottom-left corner
    if ADist < seg then
    begin
      a := Pi / 2 + ADist / r; AX := FPanelL + r + r * Cos(a); AY := FPanelB - r + r * Sin(a); Exit;
    end;
    ADist -= seg; seg := h - 2 * r;         // left edge, up
    if ADist < seg then begin AX := FPanelL; AY := FPanelB - r - ADist; Exit; end;
    ADist -= seg;                           // top-left corner
    a := Pi + ADist / r; AX := FPanelL + r + r * Cos(a); AY := FPanelT + r + r * Sin(a);
  end;

begin
  w := FPanelR - FPanelL;
  h := FPanelB - FPanelT;
  if (w < 40) or (h < 40) then Exit;
  FTarget := Bmp;
  r := Min(18, h / 4);
  per := 2 * (w - 2 * r) + 2 * (h - 2 * r) + 2 * Pi * r;
  t := HudClock * MenuFx.V[fxMenuSpeed];
  f := Clamp01(Menu.ItemTime / 0.6);
  c := CycleColour(t * MenuFx.V[fxColourSpeed] * 0.25);
  { (the 4 straight edges only: a stroked round rect scans the whole panel) }
  cc := BGRA(c.red, c.green, c.blue, Round((50 + 45 * Sin(t * 2.2)) * f * MenuFx.V[fxPanelBorder]));
  FTarget.DrawLineAntialias(FPanelL + r, FPanelT, FPanelR - r, FPanelT, cc, 2.2);
  FTarget.DrawLineAntialias(FPanelL + r, FPanelB, FPanelR - r, FPanelB, cc, 2.2);
  FTarget.DrawLineAntialias(FPanelL, FPanelT + r, FPanelL, FPanelB - r, cc, 2.2);
  FTarget.DrawLineAntialias(FPanelR, FPanelT + r, FPanelR, FPanelB - r, cc, 2.2);
  for k := 0 to FxI(fxPanelComets) - 1 do
  begin
    c := CycleColour(t * MenuFx.V[fxColourSpeed] * 0.4 + k * 2);
    d := (t * 0.16 * MenuFx.V[fxCometSpeed] + k / Max(1, FxI(fxPanelComets))) * per;
    for j := 0 to FxI(fxCometTail) - 1 do
    begin
      PerimPoint(d - j * per * 0.0045, px, py);
      sz := 3.4 * MenuFx.V[fxCometSize] * (1 - j / (FxI(fxCometTail) + 2));
      FTarget.FillEllipseAntialias(px, py, sz * 2.2, sz * 2.2,
        BGRA(c.red, c.green, c.blue, Round(45 * (1 - j / Max(1, FxI(fxCometTail))) * f)));
      cc := Mix(c, White, Max(0, 0.6 - j * 0.04));
      FTarget.FillEllipseAntialias(px, py, sz, sz,
        BGRA(cc.red, cc.green, cc.blue, Round(235 * (1 - j / Max(1, FxI(fxCometTail))) * f)));
    end;
  end;
end;

{ behind the title: a breathing spotlight and twinkling glints }
procedure TGameHud.DrawTitleLights(const L: TLayout; AW, T: Single);
var
  cx, cy, r, a, tw, sx, sy, band: Single;
  c: TBGRAPixel;
  i: Integer;
begin
  cx := L.W / 2;
  cy := FTitleY;
  band := FFontSize * 0.07;
  c := CycleColour(T * MenuFx.V[fxColourSpeed] * 0.22);
  r := AW * (0.55 + 0.04 * Sin(T * 1.3));
  a := Clamp01(Menu.Time / 0.8) * (0.30 + 0.10 * Sin(T * 2.1)) * MenuFx.V[fxTitleSpotlight];
  { stacked faint ellipses: a soft elliptical glow without hard edges }
  if a > 0.002 then
  for i := 0 to 6 do
    FTarget.FillEllipseAntialias(cx, cy, r * (1 - i * 0.12), band * (1.1 - i * 0.12),
      BGRA(c.red, c.green, c.blue, Round(255 * a * 0.16)));
  for i := 0 to FxI(fxTitleSparkles) - 1 do
  begin
    tw := Sin(T * (1.6 + i * 0.23) + i * 2.1);
    if tw <= 0.55 then Continue;
    tw := (tw - 0.55) / 0.45;
    sx := cx + AW * (-0.55 + 1.1 * Frac(i * 0.618 + 0.13));
    sy := cy + FFontSize * 0.054 * (Frac(i * 0.382 + 0.5) * 2 - 1);
    r := FFontSize * 0.010 * tw + 1;
    c := Mix(White, CycleColour(T * MenuFx.V[fxColourSpeed] * 0.3 + i), 0.35);
    a := tw * Clamp01(Menu.Time / 1.2);
    FTarget.DrawLineAntialias(sx - r * 2.2, sy, sx + r * 2.2, sy, BGRA(c.red, c.green, c.blue, Round(220 * a)),
      Max(1, r * 0.25));
    FTarget.DrawLineAntialias(sx, sy - r * 2.2, sx, sy + r * 2.2, BGRA(c.red, c.green, c.blue, Round(220 * a)),
      Max(1, r * 0.25));
    FTarget.FillEllipseAntialias(sx, sy, r * 0.7, r * 0.7, BGRA(255, 255, 255, Round(240 * a)));
  end;
end;

procedure TGameHud.DrawMenuItems(const L: TLayout);
var
  k, j: Integer;
  y, e, op, xoff, pulse, bw, tw, ax, r, t, bl, br, sx, sy, ph, a: Single;
  s: string;
  col, bar: TBGRAPixel;
  f: THudFont;
  tb: TBGRABitmap;
begin
  t := Menu.Clock * MenuFx.V[fxMenuSpeed];
  ItemsTrack;   // the selector moved: reaction + trail of the item it left
  for k := 0 to High(Menu.Items) do
  begin
    y := FItemY0 + k * FItemStep;
    { items slide in from alternating sides, one after another }
    e := EaseOut((Menu.ItemTime - 0.25 - k * 0.08) / 0.4);
    op := e;
    if k mod 2 = 0 then xoff := -(1 - e) * L.W * 0.25 * MenuFx.V[fxItemSlide]
    else xoff := (1 - e) * L.W * 0.25 * MenuFx.V[fxItemSlide];
    s := Menu.Items[k].Caption;
    if Menu.Items[k].Value <> '' then s := s + '    <  ' + Menu.Items[k].Value + '  >';
    if k = Menu.Sel then
    begin
      pulse := 0.5 + 0.5 * Sin(t * 5 * MenuFx.V[fxSelPulse]);
      col := Mix(White, CycleColour(t * MenuFx.V[fxColourSpeed] * 0.5), 0.3 + 0.3 * pulse);
      f := hfBig;
      { glowing selection bar with an outer light ring }
      bw := (FPanelR - FPanelL) * 0.84;
      r := FItemStep * 0.3;
      bar := CycleColour(t * MenuFx.V[fxColourSpeed] * 0.5);
      bl := L.W / 2 - bw / 2 + xoff;
      br := L.W / 2 + bw / 2 + xoff;
      FTarget.FillRoundRectAntialias(bl, y - FItemStep * 0.42, br, y + FItemStep * 0.42, r, r,
        BGRA(bar.red, bar.green, bar.blue, Round((28 + 30 * pulse) * op)));
      FTarget.RoundRectAntialias(bl - 3, y - FItemStep * 0.42 - 3, br + 3, y + FItemStep * 0.42 + 3, r + 3, r + 3,
        BGRA(bar.red, bar.green, bar.blue, Round((25 + 35 * pulse) * op * MenuFx.V[fxSelRing])), 3);
      FTarget.RoundRectAntialias(bl, y - FItemStep * 0.42, br, y + FItemStep * 0.42, r, r,
        BGRA(bar.red, bar.green, bar.blue, Round(170 * op)), 1.6);
      { a light sweep crosses the bar }
      ph := Frac(t * 0.45);
      sx := bl + (ph * 1.4 - 0.2) * bw;
      if (sx > bl + r * 2) and (sx < br - r * 2) then
        for j := 1 to 4 do   // a soft sheen: stacked faint ellipses
          FTarget.FillEllipseAntialias(sx, y, FItemStep * 0.25 * j, FItemStep * 0.08 * j,
            BGRA(255, 255, 255, Round(9 * op * Sin(ph * Pi) * MenuFx.V[fxSelSweep])));
      { sparks travel along the top and bottom edges }
      for j := 0 to FxI(fxSelSparks) - 1 do
      begin
        a := Frac(t * 0.3 + j / Max(1, FxI(fxSelSparks)));
        sx := bl + r + a * (bw - 2 * r);
        if j mod 2 = 0 then sy := y - FItemStep * 0.42 else sy := y + FItemStep * 0.42;
        FTarget.FillEllipseAntialias(sx, sy, 2.4, 2.4, BGRA(255, 255, 255, Round(200 * op * Sin(a * Pi))));
      end;
      { long items (option values) use the smaller font so they fit the bar }
      tb := TextBmp(f, s, White);
      if (tb <> nil) and (tb.Width > bw - FItemStep * 1.8) then
      begin
        f := hfMid;
        tb := TextBmp(f, s, White);
      end;
      if tb <> nil then ItemGeom(k, L.W / 2 + xoff, y, tb.Width, tb.Height);
      { chevrons that bounce towards the item }
      if tb <> nil then tw := tb.Width else tw := 0;
      ax := tw / 2 + FItemStep * (0.55 + 0.12 * Sin(t * 7) * MenuFx.V[fxChevronBounce]);
      TxtTint(hfMid, '>', L.W / 2 - ax + xoff, y, bar, 0, op, 0.6);
      TxtTint(hfMid, '<', L.W / 2 + ax + xoff, y, bar, 0, op, 0.6);
      { the glowing text and its light sweep }
      TxtTint(f, s, L.W / 2 + xoff, y, col, 0, op, (0.45 + 0.3 * pulse) * MenuFx.V[fxSelGlow]);
      if tb <> nil then
        BlendShine(tb, Round(L.W / 2 + xoff - tb.Width / 2), Round(y - tb.Height / 2), White, Min(1, 0.8 * op * MenuFx.V[fxSelSweep]),
          L.W / 2 + xoff - tb.Width * 0.7 + ph * tb.Width * 1.4, tb.Height * 0.5);
    end
    else
      { the other items: size, colour, art, idle motion, leave reaction (MenuFx.Item) }
      DrawIdleItem(k, s, L.W / 2 + xoff, y, op, t);
  end;
  DrawMenuParts;   // dust, drips, sparks ... left by the selector
end;

{ Level / Score / Best effects (shared with the other game) }
{$I '..\NeonGrid SDL3 GPU Shared\hudstats.inc'}
{ menu items that are not selected: art, motion, reactions, selector trail }
{$I '..\NeonGrid SDL3 GPU Shared\hudmenuitems.inc'}
{ frames (panels) and the status bar extras }
{$I '..\NeonGrid SDL3 GPU Shared\hudframes.inc'}

{ the aim line: dots along the path of the shot (with the bounces), in the
  colour of the bead, fading towards the end }
procedure TGameHud.DrawAim(G: TShooterGame; const L: TLayout);
var
  path: TList;
  i, lx, ly, k, n: Integer;
  a, b: PPointF;
  len, d, t, x, y, fade, total: Single;
  c: TBGRAPixel;
begin
  if (G.State <> gsPlaying) or G.Flying or G.Demo then Exit;
  FTarget := Bmp;
  path := TList.Create;
  try
    G.AimPath(path, lx, ly);
    if G.Cur.Spec = SpNone then
      c := BGRA(BeadRGB[G.Cur.Colour, 0], BeadRGB[G.Cur.Colour, 1], BeadRGB[G.Cur.Colour, 2])
    else
      c := BGRA(255, 245, 220);
    total := 0;
    for i := 1 to path.Count - 1 do
    begin
      a := PPointF(path[i - 1]);
      b := PPointF(path[i]);
      total += Sqrt(Sqr(b^.X - a^.X) + Sqr(b^.Y - a^.Y));
    end;
    d := 0.6;   // start a little away from the launcher
    len := 0;
    k := 0;
    for i := 1 to path.Count - 1 do
    begin
      a := PPointF(path[i - 1]);
      b := PPointF(path[i]);
      t := Sqrt(Sqr(b^.X - a^.X) + Sqr(b^.Y - a^.Y));
      while (d <= len + t) and (k < 400) do
      begin
        x := a^.X + (b^.X - a^.X) * (d - len) / Max(1e-6, t);
        y := a^.Y + (b^.Y - a^.Y) * (d - len) / Max(1e-6, t);
        fade := 1 - 0.7 * d / Max(1, total);
        FTarget.FillEllipseAntialias(L.BoardX0 + x * L.Cell, L.BoardY0 + y * L.Cell, L.Cell * 0.07,
          L.Cell * 0.07, BGRA(c.red, c.green, c.blue, Round(230 * fade)));
        d += 0.45;
        Inc(k);
      end;
      len += t;
    end;
    n := path.Count;
    for i := 0 to n - 1 do Dispose(PPointF(path[i]));
  finally
    path.Free;
  end;
end;

procedure TGameHud.DrawBase(G: TShooterGame; const L: TLayout);
var
  s: string;
  i, n, cx, cy, pw, ph, lineH: Integer;
  m, x, y, bw, frac: Single;
  c: TBGRAPixel;
  r, gg, b: Byte;
  rowH: Single;
  rows: Integer;
  a: TAchId;
begin
  OpenFonts(L.H);
  if (FBase.Width <> L.W) or (FBase.Height <> L.H) then FBase.SetSize(L.W, L.H);
  FBase.FillTransparent;
  FTarget := FBase;
  SetLength(FHeads, 0);
  SetLength(FStats, 0);
  FFramesPrev := Copy(FFrames);   // a frame seen before keeps its intro time
  SetLength(FFrames, 0);
  SetLength(FHintsL, 0);
  FBarOn := False;
  m := Round(Min(L.W, L.H) * 0.02);
  cx := L.W div 2;
  cy := L.H div 2;

  if G.State <> gsTitle then
  begin
    { top bar: level (colours), score, best }
    Panel(m, m * 0.6, L.W - m, L.TopH - m * 0.4, 190, frTop);
    y := (m * 0.6 + L.TopH - m * 0.4) / 2;
    StatTxt(stLevel, hfBig, 'LEVEL ', G.Level, m * 2, y - L.H * 0.012, Cyan, -1);
    Txt(hfSmall, Format('%d colours', [G.Colours]), m * 2, y + L.H * 0.02, Grey);
    Txt(hfSmall, 'SCORE', cx, y - L.H * 0.019, Grey, 0);
    StatTxt(stScore, hfBig, '', G.Score, cx, y + L.H * 0.010, White, 0);
    Txt(hfSmall, 'BEST', L.W - m * 2, y - L.H * 0.019, Grey, 1);
    StatTxt(stBest, hfMid, '', Max(G.Best, G.Score), L.W - m * 2, y + L.H * 0.010, White, 1);

    { bottom bar: beads left, shots to the next ceiling row, combo / keys }
    Panel(m, L.H - L.BottomH + m * 0.4, L.W - m, L.H - m * 0.6, 190, frStatus);
    y := (L.H - L.BottomH + m * 0.4 + L.H - m * 0.6) / 2;
    StatTxtS(stStatus, hfMid, Format('BEADS %d', [G.BeadCount]), -G.BeadCount, m * 2,
      y - L.H * 0.011, White, -1);
    bw := L.W * 0.22;
    frac := EnsureRange(G.ShotsToRow / Max(1, G.RowEvery), 0, 1);
    FTarget.FillRoundRectAntialias(m * 2, y + L.H * 0.010, m * 2 + bw, y + L.H * 0.020, 4, 4, BGRA(50, 55, 75));
    if G.ShotsToRow <= 1 then c := Pink else c := Green;
    BarFill(m * 2, y + L.H * 0.010, m * 2 + bw, y + L.H * 0.020, frac, c);
    if G.ShotsToRow = 1 then s := 'new row next miss!' else s := Format('new row: %d misses', [G.ShotsToRow]);
    Txt(hfSmall, s, m * 3 + bw, y + L.H * 0.015, Grey);
    { right side: the combo, otherwise the key hints }
    if G.Combo >= 2 then
      Txt(hfMid, Format('COMBO x%d', [G.Combo]), L.W - m * 2, y, Pink, 1)
    else
    begin
      HintTxt(hfSmall, 'mouse aim   click shoot', L.W - m * 2, y - L.H * 0.010, Grey, 1);
      if Muted then s := 'M off' else s := 'M sound';
      HintTxt(hfSmall, 'X swap   P pause   ' + s, L.W - m * 2, y + L.H * 0.014, Grey, 1);
    end;
  end;

  { screens }
  lineH := Round(L.H * 0.045);
  pw := Round(Min(L.W * 0.9, L.H * 0.62));
  if Menu.Active then
  begin
    { static parts of the menu; the heading and the items are animated on top }
    if G.State <> gsTitle then
      FTarget.FillRect(0, 0, L.W, L.H, BGRA(2, 4, 14, 150), dmDrawWithTransparency);  // pause veil
    n := Length(Menu.Items);
    case Menu.Screen of
      3: begin rowH := lineH * 0.72; rows := MaxScores + 1; end;
      5: begin rowH := lineH; rows := 3; end;
      4: begin rowH := lineH * 0.6; rows := Ord(High(TAchId)) + 1; end;
    else
      begin rowH := 0; rows := 0; end;
    end;
    ph := Round(lineH * (4.4 + n * 1.3 + 3.6) + rows * rowH + Ord(rows > 0) * lineH * 0.4);
    if rows > 0 then pw := Round(Min(L.W * 0.96, L.H * 0.7))
    else pw := Round(Min(L.W * 0.92, L.H * 0.64));
    y := cy - ph / 2;
    Panel(cx - pw / 2, y, cx + pw / 2, y + ph, 205);
    FPanelL := cx - pw / 2;
    FPanelR := cx + pw / 2;
    FPanelT := y;
    FPanelB := y + ph;
    FTitleY := y + lineH * 1.45;
    y := FTitleY + lineH * 1.45;
    case Menu.Screen of
      0: Txt(hfSmall, 'aim, shoot, pop 3 or more of one colour - the rest drops', cx, y, Grey, 0);
      1: HeadTxt(hfMid, 'OPTIONS', cx, y, Pink);
      5: HeadTxt(hfMid, 'CHEAT CODE', cx, y, Pink);
      3: HeadTxt(hfMid, 'HIGH SCORES', cx, y, Pink);
      4: if Ach <> nil then
           HeadTxt(hfMid, Format('ACHIEVEMENTS   %d / %d', [Ach.UnlockedCount, Ord(High(TAchId)) + 1]), cx, y, Pink);
    else
      Txt(hfMid, Format('level %d   ·   score %s   ·   beads %d',
        [G.Level, FormatFloat('#,##0', G.Score), G.BeadCount]), cx, y, Pink, 0);
    end;
    if (rows > 0) and (Ach <> nil) then
    begin
      y += lineH * 0.9;
      x := cx - pw / 2 + lineH * 0.8;       // left column
      if Menu.Screen = 5 then
      begin
        { the code being typed (a dash after the fifth letter) }
        y += lineH * 0.45;
        FTarget.FillRoundRectAntialias(cx - pw * 0.35, y - lineH * 0.5, cx + pw * 0.35, y + lineH * 0.5, 8, 8,
          BGRA(20, 24, 44, 230));
        FTarget.RoundRectAntialias(cx - pw * 0.35, y - lineH * 0.5, cx + pw * 0.35, y + lineH * 0.5, 8, 8, Cyan, 2);
        s := Copy(CodeText, 1, 5);
        if Length(CodeText) > 5 then s += '-' + Copy(CodeText, 6, 5);
        Txt(hfBig, s + '_', cx, y, White, 0);
        y += lineH * 1.15;
        if CodeMsg <> '' then
          Txt(hfMid, CodeMsg, cx, y, Pink, 0)
        else
          Txt(hfSmall, 'every completed level shows its code (score, level)', cx, y, Grey, 0);
        y += lineH * 0.8;
        Txt(hfSmall, 'type the code or paste it: Ctrl+P / Ctrl+V', cx, y, Cyan, 0);
        y += lineH * 0.6;
      end
      else if Menu.Screen = 3 then
      begin
        { high-score table }
        Txt(hfSmall, '#', x, y, Grey);
        Txt(hfSmall, 'NAME', x + pw * 0.08, y, Grey);
        Txt(hfSmall, 'LEVEL', cx + pw * 0.12, y, Grey, 0);
        Txt(hfSmall, 'SCORE', cx + pw * 0.42, y, Grey, 1);
        for i := 0 to MaxScores - 1 do
        begin
          y += rowH;
          if i = NewRank then
          begin
            FTarget.FillRoundRectAntialias(x - lineH * 0.3, y - rowH * 0.48, cx + pw / 2 - lineH * 0.5,
              y + rowH * 0.48, 6, 6, BGRA(245, 70, 170, 70));
            c := Cyan;
          end
          else if i = 0 then c := BGRA(255, 215, 90)
          else c := White;
          Txt(hfMid, IntToStr(i + 1), x, y, c);
          if i <= High(Ach.Scores) then
          begin
            Txt(hfMid, Ach.Scores[i].Name, x + pw * 0.08, y, c);
            Txt(hfMid, IntToStr(Ach.Scores[i].Level), cx + pw * 0.12, y, c, 0);
            Txt(hfMid, FormatFloat('#,##0', Ach.Scores[i].Score), cx + pw * 0.42, y, c, 1);
          end
          else
            Txt(hfMid, '- - -', x + pw * 0.08, y, BGRA(90, 90, 110));
        end;
      end
      else
      begin
        { achievements: name + what to do, lit when unlocked }
        for a := Low(TAchId) to High(TAchId) do
        begin
          if a > Low(TAchId) then y += rowH;
          if Ach.Unlocked[a] then
          begin
            FTarget.FillEllipseAntialias(x, y, rowH * 0.18, rowH * 0.18, BGRA(255, 215, 90));
            Txt(hfMid, AchInfo[a].Name, x + rowH * 0.5, y, BGRA(255, 215, 90));
            Txt(hfSmall, AchInfo[a].Desc, cx + pw / 2 - lineH * 0.8, y, White, 1);
          end
          else
          begin
            FTarget.EllipseAntialias(x, y, rowH * 0.18, rowH * 0.18, BGRA(90, 90, 110), 1.5);
            Txt(hfMid, AchInfo[a].Name, x + rowH * 0.5, y, BGRA(110, 110, 130));
            Txt(hfSmall, AchInfo[a].Desc, cx + pw / 2 - lineH * 0.8, y, BGRA(110, 110, 130), 1);
          end;
        end;
      end;
      y += lineH * 0.4;
    end;
    FItemStep := lineH * 1.3;
    FItemY0 := y + lineH * 1.45;
    SetLength(ItemRects, n);
    for i := 0 to n - 1 do
      ItemRects[i] := Rect(Round(FPanelL), Round(FItemY0 + i * FItemStep - FItemStep / 2),
        Round(FPanelR), Round(FItemY0 + i * FItemStep + FItemStep / 2));
    y := FItemY0 + (n - 0.2) * FItemStep;
    if Menu.Screen in [0, 3, 4] then
      Txt(hfMid, Format('best score  %s     levels unlocked  %d',
        [FormatFloat('#,##0', G.Best), G.MaxLevel]), cx, y, White, 0)
    else
      Txt(hfMid, 'now playing:  ' + Menu.NowPlaying, cx, y, White, 0);
    y += lineH * 0.95;
    if Menu.Screen in [3, 4] then
      Txt(hfSmall, 'Enter, Esc or click: back', cx, y, Grey, 0)
    else
      Txt(hfSmall, 'Up / Down select     Left / Right change', cx, y, Grey, 0);
    y += lineH * 0.55;
    if Menu.Screen = 5 then
      Txt(hfSmall, 'Enter: start     Esc: back', cx, y, Grey, 0)
    else if Menu.Screen = 2 then
      Txt(hfSmall, 'Enter or click choose     Esc / P resume     M mute', cx, y, Grey, 0)
    else if Menu.Screen in [3, 4] then
    else
      Txt(hfSmall, 'Enter or click choose     Esc back     M mute', cx, y, Grey, 0);
  end
  else
  case G.State of
    gsReady:
      begin
        ph := Round(lineH * 2.6);
        y := L.TopH + lineH * 0.6;   // top of the board: the trail starts at the bottom
        Panel(cx - pw / 2, y, cx + pw / 2, y + ph, 190);
        Txt(hfMid, 'aim and shoot to start', cx, y + ph * 0.36, White, 0);
        Txt(hfSmall, 'clear the board to finish the level', cx, y + ph * 0.72, Grey, 0);
      end;
    gsCrashed:
      begin
        ph := lineH * 5;
        Panel(cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2, 215);
        y := cy - ph / 2 + lineH * 1.1;
        HeadTxt(hfBig, 'CRASH!', cx, y, Pink);
        y += lineH * 1.2;
        Txt(hfMid, Format('beads %d', [G.BeadCount]), cx, y, White, 0);
        y += lineH * 1.2;
        Txt(hfMid, 'click or Enter: continue', cx, y, Cyan, 0);
      end;
    gsLevelDone:
      begin
        ph := lineH * 7;
        Panel(cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2, 215);
        y := cy - ph / 2 + lineH * 1.1;
        HeadTxt(hfBig, Format('LEVEL %d COMPLETE', [G.Level]), cx, y, Green);
        y += lineH * 1.2;
        Txt(hfMid, Format('biggest pop %d   ·   biggest drop %d   ·   best combo x%d', [G.MaxGroup, G.MaxDrop,
          G.MaxCombo]), cx, y, White, 0);
        y += lineH;
        Txt(hfMid, Format('bonus +%d     score %s', [G.Bonus, FormatFloat('#,##0', G.Score)]), cx, y, Pink, 0);
        y += lineH * 1.2;
        if LevelCode <> '' then
        begin
          { the continue code of this level: Ctrl+C copies it }
          if CodeCopied then s := 'CODE  ' + LevelCode + '   ·   copied!'
          else s := 'CODE  ' + LevelCode + '   ·   Ctrl+C copy';
          Txt(hfMid, s, cx, y, BGRA(255, 215, 90), 0);
          y += lineH * 1.1;
        end;
        Txt(hfMid, 'click or Enter: next level', cx, y, Cyan, 0);
      end;
    gsGameOver:
      begin
        if NameEntry then ph := lineH * 8 else ph := Round(lineH * 6.5);
        Panel(cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2, 215);
        y := cy - ph / 2 + lineH * 1.1;
        HeadTxt(hfBig, 'GAME OVER', cx, y, Pink);
        y += lineH * 1.2;
        Txt(hfMid, Format('level %d   ·   biggest pop %d   ·   best combo x%d', [G.Level, G.MaxGroup, G.MaxCombo]),
          cx, y, White, 0);
        y += lineH;
        Txt(hfMid, 'score ' + FormatFloat('#,##0', G.Score), cx, y, White, 0);
        y += lineH * 1.2;
        if NameEntry then
        begin
          Txt(hfMid, Format('NEW HIGH SCORE!   place #%d', [ScoreRank + 1]), cx, y, BGRA(255, 215, 90), 0);
          y += lineH * 1.1;
          bw := pw * 0.6;
          FTarget.FillRoundRectAntialias(cx - bw / 2, y - lineH * 0.45, cx + bw / 2, y + lineH * 0.45, 8, 8,
            BGRA(20, 24, 44, 230));
          FTarget.RoundRectAntialias(cx - bw / 2, y - lineH * 0.45, cx + bw / 2, y + lineH * 0.45, 8, 8, Cyan, 2);
          Txt(hfBig, NameText + '_', cx, y, White, 0);
          y += lineH * 0.95;
          Txt(hfSmall, 'type your name, then Enter', cx, y, Cyan, 0);
        end
        else
        begin
          Txt(hfSmall, 'click / Enter: retry level (score from level start)', cx, y, Cyan, 0);
          y += lineH * 0.6;
          Txt(hfSmall, 'H: high scores     Esc: menu', cx, y, Cyan, 0);
        end;
      end;
  end;
  FTarget := Bmp;
end;

{ "ACHIEVEMENT UNLOCKED" cards: slide in under the top bar, then fade }
procedure TGameHud.DrawToasts(const L: TLayout);
var
  i, k: Integer;
  t, e, op, y, pw, ph, cx: Single;
begin
  if Ach = nil then Exit;
  FTarget := Bmp;
  cx := L.W / 2;
  pw := Min(L.W * 0.8, L.H * 0.5);
  ph := L.H * 0.075;
  k := 0;
  for i := 0 to High(Ach.Toasts) do
  begin
    t := Ach.Toasts[i].Age;
    if t < 0 then Continue;
    e := EaseOutBack(t / 0.45);
    op := Clamp01(t / 0.2) * Clamp01((4 - t) / 0.6);
    y := L.TopH + L.H * 0.012 + k * (ph + L.H * 0.01) - (1 - e) * ph * 1.5;
    FTarget.FillRoundRectAntialias(cx - pw / 2, y, cx + pw / 2, y + ph, 12, 12, BGRA(14, 12, 30, Round(225 * op)));
    FTarget.RoundRectAntialias(cx - pw / 2, y, cx + pw / 2, y + ph, 12, 12,
      BGRA(255, 215, 90, Round(255 * op)), 2);
    { a medal }
    FTarget.FillEllipseAntialias(cx - pw / 2 + ph * 0.55, y + ph / 2, ph * 0.26, ph * 0.26,
      BGRA(255, 215, 90, Round(255 * op)));
    FTarget.FillEllipseAntialias(cx - pw / 2 + ph * 0.55, y + ph / 2, ph * 0.12, ph * 0.12,
      BGRA(255, 250, 220, Round(255 * op)));
    Txt(hfSmall, 'ACHIEVEMENT UNLOCKED', cx + ph * 0.3, y + ph * 0.3, BGRA(255, 215, 90), 0, Round(255 * op));
    Txt(hfMid, AchInfo[Ach.Toasts[i].Id].Name, cx + ph * 0.3, y + ph * 0.68, White, 0, Round(255 * op));
    Inc(k);
  end;
end;

function TGameHud.Update(G: TShooterGame; const L: TLayout): Boolean;
var
  sig: string;
  i: Integer;
  pop: TPopup;
  x, y, a: Single;
  c: TBGRAPixel;
begin
  sig := Format('%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%.1f', [L.W, L.H, Ord(G.State),
    G.Level, G.Score, G.Best, G.BeadCount, G.ShotsToRow, G.RowEvery, G.Colours, G.MaxLevel, StartLevel, G.Bonus,
    Ord(Muted), L.Cell]);
  sig += '|c' + IntToStr(G.Combo);
  sig += Format('|%d|%s|%d|%d', [Ord(NameEntry), NameText, NewRank, ScoreRank]);
  sig += '|' + CodeText + '|' + CodeMsg + '|' + LevelCode + IntToStr(Ord(CodeCopied));
  if Ach <> nil then sig += Format('|%d|%d', [Ach.UnlockedCount, Length(Ach.Scores)]);
  if Menu.Active then
  begin
    sig += '|menu' + IntToStr(Menu.Screen) + Menu.Title + '|' + Menu.NowPlaying;
    for i := 0 to High(Menu.Items) do sig += '|' + Menu.Items[i].Caption + Menu.Items[i].Value;
  end;
  sig += '|fx' + IntToStr(MenuFxStamp);   // new effect settings: the base again
  if (sig <> FBaseSig) or (FBase.Width <> L.W) or (FBase.Height <> L.H) then
  begin
    FBaseSig := sig;
    DrawBase(G, L);
    FSignature := '';
  end;
  for i := 0 to High(G.Popups) do
    sig += Format('|%.2f', [G.Popups[i].Age]);
  { the aim line moves with the mouse / keys }
  if (G.State = gsPlaying) and not G.Flying and not G.Demo then
    sig += Format('|a%.4f', [G.Angle]);
  if Ach <> nil then
    for i := 0 to High(Ach.Toasts) do
      sig += Format('|t%.2f', [Ach.Toasts[i].Age]);
  if (sig = FSignature) and not Menu.Active and (Length(FHeads) = 0) and not StatsBusy and not FramesBusy then Exit(False);
  FSignature := sig;
  Result := True;

  { the frame's HUD = cached base + the floating score popups }
  if (Bmp.Width <> L.W) or (Bmp.Height <> L.H) then Bmp.SetSize(L.W, L.H);
  Move(FBase.Data^, Bmp.Data^, L.W * L.H * SizeOf(TBGRAPixel));
  DrawFrames;  // animated frame borders
  DrawStatusX; // progress bar and key hints of the status bar
  DrawStats;   // Level / Score / Best / Status with their effects
  if not Menu.Active then DrawAim(G, L);
  if not Menu.Active then   // no popups on top of the pause menu
  for i := 0 to High(G.Popups) do
  begin
    pop := G.Popups[i];
    x := L.BoardX0 + pop.X * L.Cell;
    y := L.BoardY0 + pop.Y * L.Cell - pop.Age * L.Cell * PopupFx.Rise;
    x := EnsureRange(x, L.W * 0.18, L.W * 0.82);
    a := 1 - Max(0, (pop.Age - PopupFx.FadeStart) / Max(0.01, PopupFx.FadeTime));
    c := Mix(BGRA(pop.R, pop.G, pop.B), White, PopupFx.WhiteMix);
    Txt(THudFont(EnsureRange(PopupFx.Font, 0, 2)), pop.Text, x, y, c, 0, Round(255 * EnsureRange(a, 0, 1)));
  end;
  if Menu.Active then
  begin
    FTarget := Bmp;
    DrawPanelLights(L);
    DrawTitle(L);
    DrawMenuItems(L);
  end;
  DrawHeads(L);
  DrawToasts(L);
  Bmp.InvalidateBitmap;
end;


end.
