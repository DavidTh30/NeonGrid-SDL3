unit uGameHud;

{ HUD of Neon Beads: drawn on the CPU into a transparent TBGRABitmap the size
  of the window (BGRABitmap panels + SDL3_ttf text), uploaded to the GPU only
  when it changes and alpha-blended over the frame by overlay_ps.hlsl. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, SDL3, SDL3_ttf, BGRABitmap, BGRABitmapTypes, BGRAGradientScanner, uBeadGame, uAchievements, uMenuFx, uGameFx, uBeadRules;

type
  TLayout = record
    W, H: Integer;            // window pixels
    Cell: Single;             // bead spacing in pixels
    BoardX0, BoardY0: Single; // pixel centre of board cell (0, 0)
    TopH, BottomH: Integer;   // HUD bars
    Versus: Boolean;          // VS BOT: a second (bot) board on the right
    Board2X0: Single;         // pixel x of the bot board's cell (0, 0)
  end;

  THudFont = (hfSmall, hfMid, hfBig, hfTitle);

  TMenuItem = record
    Caption, Value: string;   // Value = '' for plain actions
  end;

  { filled in by the program every frame while the menu is shown }
  TMenuModel = record
    Active: Boolean;          // drawn on the title screen and while paused
    Title: string;            // animated heading ('NEON BEADS' / 'PAUSED')
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
    procedure DrawBase(G: TBeadGame; const L: TLayout);
    procedure DrawSpecials(G: TBeadGame; const L: TLayout; AX0: Single);
    procedure DrawPopups(G: TBeadGame; const L: TLayout; AX0: Single);
    procedure DrawVersusBars(G: TBeadGame; const L: TLayout; m: Single);
    procedure Star(X, Y, R: Single; AFilled: Boolean; AOpacity: Byte);
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
    NewRankMode: TGameMode;      // table of NewRank
    ScoreMode: TGameMode;        // table shown on the high-score screen
    StarTime: Single;            // seconds since the level-done panel appeared
    NewStarBest: Boolean;        // the level beat its old stars
    Bot: TBeadGame;              // VS BOT: the bot's game (owned by the program), else nil
    AchPage: Integer;            // achievement group shown (0 general, 1 survival, 2 VS BOT)
    Subtitle: string;            // main menu line under the title ('' = the Neon Beads rules)
    constructor Create;
    destructor Destroy; override;
    { redraws when anything visible changed; returns True if it did }
    function Update(G: TBeadGame; const L: TLayout): Boolean;
  end;

function BeadColour(AIndex: Integer): TBGRAPixel;

implementation

const
  Cyan: TBGRAPixel = (blue: 240; green: 220; red: 70; alpha: 255);
  White: TBGRAPixel = (blue: 245; green: 240; red: 240; alpha: 255);
  Grey: TBGRAPixel = (blue: 200; green: 175; red: 160; alpha: 255);
  Green: TBGRAPixel = (blue: 110; green: 235; red: 120; alpha: 255);
  Pink: TBGRAPixel = (blue: 170; green: 70; red: 245; alpha: 255);
  IronCol: TBGRAPixel = (blue: 220; green: 200; red: 185; alpha: 255);

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

{ a five-pointed star (filled or outlined) }
procedure TGameHud.Star(X, Y, R: Single; AFilled: Boolean; AOpacity: Byte);
var
  pts: array of TPointF;
  k: Integer;
  a, rr: Single;
begin
  SetLength(pts, 10);
  for k := 0 to 9 do
  begin
    a := -Pi / 2 + k * Pi / 5;
    if k mod 2 = 0 then rr := R else rr := R * 0.45;
    pts[k] := PointF(X + Cos(a) * rr, Y + Sin(a) * rr);
  end;
  if AFilled then
  begin
    FTarget.FillPolyAntialias(pts, BGRA(255, 215, 90, AOpacity));
    FTarget.DrawPolygonAntialias(pts, BGRA(255, 250, 220, AOpacity), Max(1, R * 0.08));
  end
  else
    FTarget.DrawPolygonAntialias(pts, BGRA(110, 110, 135, AOpacity), Max(1, R * 0.08));
end;

{ the icons of the special beads, drawn over the GPU beads (they follow the
  falling / sliding animation) }
procedure TGameHud.DrawSpecials(G: TBeadGame; const L: TLayout; AX0: Single);
var
  x, y, sp, k: Integer;
  f: PCellFx;
  px, py, c, s: Single;
  op: Byte;
  pts: array of TPointF;
begin
  if G.W * G.H = 0 then Exit;
  FTarget := Bmp;
  c := L.Cell;
  for x := 0 to G.W - 1 do
    for y := 0 to G.H - 1 do
    begin
      sp := G.Spec(x, y);
      if (sp = SpNone) or (sp = SpRainbow) or (G.Cell(x, y) < 0) then Continue;
      f := G.Fx(x, y);
      if f^.Presence <= 0.05 then Continue;
      px := AX0 + (x + f^.OffX) * c;
      py := L.BoardY0 + (y - f^.OffY) * c;
      if (py < L.TopH - c) then Continue;
      s := c * 1.25 * (0.75 + 0.25 * f^.Presence) * (1 + 0.12 * f^.Hover);
      op := Round(255 * EnsureRange(f^.Presence * 1.5, 0, 1));
      case sp of
        SpBomb:
          begin
            FTarget.FillEllipseAntialias(px, py, s * 0.2, s * 0.2, BGRA(12, 10, 22, op));
            FTarget.EllipseAntialias(px, py, s * 0.2, s * 0.2, BGRA(255, 255, 255, op), Max(1, s * 0.04));
            FTarget.DrawLineAntialias(px + s * 0.12, py - s * 0.12, px + s * 0.22, py - s * 0.24,
              BGRA(255, 240, 200, op), Max(1, s * 0.04));
            FTarget.FillEllipseAntialias(px + s * 0.24, py - s * 0.26, s * 0.06, s * 0.06, BGRA(255, 220, 80, op));
          end;
        SpLine:
          begin
            FTarget.DrawLineAntialias(px - s * 0.22, py, px + s * 0.22, py, BGRA(255, 255, 255, op), Max(1.5, s * 0.07));
            SetLength(pts, 3);
            pts[0] := PointF(px - s * 0.34, py);
            pts[1] := PointF(px - s * 0.2, py - s * 0.12);
            pts[2] := PointF(px - s * 0.2, py + s * 0.12);
            FTarget.FillPolyAntialias(pts, BGRA(255, 255, 255, op));
            pts[0] := PointF(px + s * 0.34, py);
            pts[1] := PointF(px + s * 0.2, py - s * 0.12);
            pts[2] := PointF(px + s * 0.2, py + s * 0.12);
            FTarget.FillPolyAntialias(pts, BGRA(255, 255, 255, op));
          end;
        SpDouble:
          begin
            FTarget.FillEllipseAntialias(px, py, s * 0.23, s * 0.23, BGRA(12, 10, 22, Round(op * 0.8)));
            Txt(hfSmall, 'x2', px, py, BGRA(255, 230, 120), 0, op);
          end;
        SpIron:
          begin
            { a hex nut: nothing breaks it }
            SetLength(pts, 6);
            for k := 0 to 5 do
              pts[k] := PointF(px + s * 0.24 * Cos(k * Pi / 3), py + s * 0.24 * Sin(k * Pi / 3));
            FTarget.FillPolyAntialias(pts, BGRA(70, 78, 96, op));
            FTarget.DrawPolygonAntialias(pts, BGRA(235, 240, 250, op), Max(1, s * 0.035));
            FTarget.FillEllipseAntialias(px, py, s * 0.09, s * 0.09, BGRA(20, 22, 32, op));
          end;
        SpStone:
          begin
            { cracks }
            FTarget.DrawLineAntialias(px - s * 0.18, py - s * 0.1, px + s * 0.02, py + s * 0.04,
              BGRA(40, 40, 52, op), Max(1, s * 0.05));
            FTarget.DrawLineAntialias(px + s * 0.02, py + s * 0.04, px + s * 0.16, py - s * 0.14,
              BGRA(40, 40, 52, op), Max(1, s * 0.05));
            FTarget.DrawLineAntialias(px + s * 0.02, py + s * 0.04, px - s * 0.02, py + s * 0.22,
              BGRA(40, 40, 52, op), Max(1, s * 0.05));
          end;
      end;
    end;
end;

{ VS BOT bars: player (left) and bot (right) scores and iron }
procedure TGameHud.DrawVersusBars(G: TBeadGame; const L: TLayout; m: Single);
var
  y, cx: Single;
  n, atk, iron, bonus: Integer;
  s: string;
begin
  cx := L.W / 2;
  Panel(m, m * 0.6, L.W - m, L.TopH - m * 0.4, 190, frTop);
  y := (m * 0.6 + L.TopH - m * 0.4) / 2;
  Txt(hfSmall, 'YOU', m * 2, y - L.H * 0.019, Grey);
  StatTxt(stScore, hfBig, '', G.Score, m * 2, y + L.H * 0.010, Cyan, -1);
  Txt(hfBig, 'VS BOT', cx, y - L.H * 0.012, Pink, 0);
  Txt(hfSmall, Format('%s bot  ·  best %s', [BotNames[EnsureRange(G.VsBotLevel, 0, BotLevels - 1)],
    FormatFloat('#,##0', Max(G.Best, G.Score))]), cx, y + L.H * 0.019, Grey, 0);
  Txt(hfSmall, 'BOT', L.W - m * 2, y - L.H * 0.019, Grey, 1);
  Txt(hfBig, FormatFloat('#,##0', Bot.Score), L.W - m * 2, y + L.H * 0.010, Pink, 1);

  Panel(m, L.H - L.BottomH + m * 0.4, L.W - m, L.H - m * 0.6, 190, frStatus);
  y := (L.H - L.BottomH + m * 0.4 + L.H - m * 0.6) / 2;
  StatTxtS(stStatus, hfMid, Format('IRON %d', [G.IronCount]), G.IronCount, m * 2, y - L.H * 0.010, IronCol, -1);
  if (G.State = gsPlaying) and (VsIdleSecs > 0) and (VsIdleSecs - G.IdleT < 3.5) then
  begin
    if VsIdlePenalty > 0 then s := Format('lose %d', [VsIdlePenalty]) else s := 'get iron';
    Txt(hfSmall, Format('pop within %d s or %s!', [Ceil(VsIdleSecs - G.IdleT), s]), m * 2,
      y + L.H * 0.014, Pink);
  end
  else if not G.VsIronOn then
    Txt(hfSmall, Format('iron off: scores within %d  ·  sent %d  ·  got %d', [VsIronGap, G.IronSent,
      G.IronReceived]), m * 2, y + L.H * 0.014, Grey)
  else if G.VsLead > 0 then
    Txt(hfSmall, Format('you lead by %d+: your iron hits the bot  ·  sent %d', [VsIronGap, G.IronSent]),
      m * 2, y + L.H * 0.014, BGRA(255, 215, 90))
  else if G.VsLead < 0 then
    Txt(hfSmall, Format('behind by %d+: the bot''s iron hits you  ·  got %d', [VsIronGap, G.IronReceived]),
      m * 2, y + L.H * 0.014, Pink)
  else
    Txt(hfSmall, Format('iron off: scores within %d  ·  sent %d  ·  got %d', [VsIronGap, G.IronSent,
      G.IronReceived]), m * 2, y + L.H * 0.014, Grey);
  n := G.HoverCount;
  if (n >= 1) and (G.State = gsPlaying) then
  begin
    Txt(hfMid, Format('%d beads  +%d', [n, G.HoverPoints]), cx, y - L.H * 0.008, Pink, 0);
    { what this move brings: iron only when ahead by more than VsIronGap,
      and then all of it goes to the bot }
    TBeadGame.SurvivalRefill(n, iron, bonus);
    G.MoveIron(n, atk, iron);
    s := '';
    if atk > 0 then s := Format('attack %d iron', [atk]);
    if iron > 0 then
    begin
      if s <> '' then s += '  ·  ';
      s += Format('+%d iron for you', [iron]);
    end;
    if bonus > 0 then
    begin
      if s <> '' then s += '  ·  ';
      s += Format('+%d bonus', [bonus]);
    end;
    if s <> '' then Txt(hfSmall, s, cx, y + L.H * 0.018, BGRA(255, 215, 90), 0);
  end;
  Txt(hfMid, Format('BOT IRON %d', [Bot.IronCount]), L.W - m * 2, y - L.H * 0.010, IronCol, 1);
  if Muted then s := 'M sound off' else s := 'M sound on';
  HintTxt(hfSmall, 'Esc menu   R restart   ' + s, L.W - m * 2, y + L.H * 0.014, Grey, 1);
end;

{ the floating score popups of one board }
procedure TGameHud.DrawPopups(G: TBeadGame; const L: TLayout; AX0: Single);
var
  i: Integer;
  pop: TPopup;
  px, py, a: Single;
  c: TBGRAPixel;
begin
  FTarget := Bmp;
  for i := 0 to High(G.Popups) do
  begin
    pop := G.Popups[i];
    px := AX0 + pop.X * L.Cell;
    py := L.BoardY0 + pop.Y * L.Cell - pop.Age * L.Cell * PopupFx.Rise;
    if L.Versus then
      px := EnsureRange(px, AX0 + L.Cell * 2.5, AX0 + (G.W - 3.5) * L.Cell)
    else
      px := EnsureRange(px, L.W * 0.2, L.W * 0.8);
    a := 1 - Max(0, (pop.Age - PopupFx.FadeStart) / Max(0.01, PopupFx.FadeTime));
    if pop.Colour = -2 then c := IronCol
    else if pop.Colour < 0 then c := BGRA(255, 215, 90)
    else
    begin
      c := Mix(BeadColour(pop.Colour), White, PopupFx.WhiteMix);
    end;
    { the font size comes from the .visuals file (one size smaller in VS BOT) }
    if L.Versus then
      Txt(THudFont(EnsureRange(PopupFx.Font - 1, 0, 2)), pop.Text, px, py, c, 0, Round(255 * EnsureRange(a, 0, 1)))
    else
      Txt(THudFont(EnsureRange(PopupFx.Font, 0, 2)), pop.Text, px, py, c, 0, Round(255 * EnsureRange(a, 0, 1)));
  end;
end;

{ Level / Score / Best effects (shared with the other game) }
{$I '..\NeonGrid SDL3 GPU Shared\hudstats.inc'}
{ menu items that are not selected: art, motion, reactions, selector trail }
{$I '..\NeonGrid SDL3 GPU Shared\hudmenuitems.inc'}
{ frames (panels) and the status bar extras }
{$I '..\NeonGrid SDL3 GPU Shared\hudframes.inc'}

procedure TGameHud.DrawBase(G: TBeadGame; const L: TLayout);
var
  s: string;
  i, left, pts, n, cx, cy, pw, ph, lineH, k: Integer;
  m, x, y, bw, frac, rowH, t: Single;
  c: TBGRAPixel;
  rows: Integer;
  a: TAchId;
  mode: TGameMode;
  iron, bonus: Integer;
begin
  left := G.BeadsLeft;
  n := G.HoverCount;
  pts := G.HoverPoints;

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

  if (G.State <> gsTitle) and (G.Mode = gmVersus) and (Bot <> nil) then
    DrawVersusBars(G, L, m)
  else if G.State <> gsTitle then
  begin
    { top bar: level (classic) or the clock (time attack), score, best }
    Panel(m, m * 0.6, L.W - m, L.TopH - m * 0.4, 190, frTop);
    y := (m * 0.6 + L.TopH - m * 0.4) / 2;
    if G.Mode = gmTime then
    begin
      t := Max(0, G.TimeLeft);
      if t < 10 then c := Pink else c := Cyan;
      Txt(hfBig, Format('%d:%.2d', [Trunc(t) div 60, Trunc(t) mod 60]), m * 2, y - L.H * 0.012, c);
      Txt(hfSmall, Format('TIME ATTACK  ·  board %d', [G.Boards + 1]), m * 2, y + L.H * 0.019, Grey);
    end
    else if G.Mode = gmSurvival then
    begin
      Txt(hfBig, 'SURVIVAL', m * 2, y - L.H * 0.012, Cyan);
      Txt(hfSmall, Format('%d colours  ·  %d x %d  ·  %d pops', [G.Colours, G.W, G.H, G.Pops]),
        m * 2, y + L.H * 0.019, Grey);
    end
    else
    begin
      StatTxt(stLevel, hfBig, 'LEVEL ', G.Level, m * 2, y - L.H * 0.012, Cyan, -1);
      s := Format('%d colours  ·  %d x %d', [G.Colours, G.W, G.H]);
      if G.Twist <> '' then s += '  ·  ' + G.Twist;
      Txt(hfSmall, s, m * 2, y + L.H * 0.019, Grey);
    end;
    Txt(hfSmall, 'SCORE', cx, y - L.H * 0.019, Grey, 0);
    StatTxt(stScore, hfBig, '', G.Score, cx, y + L.H * 0.010, White, 0);
    Txt(hfSmall, 'BEST', L.W - m * 2, y - L.H * 0.019, Grey, 1);
    StatTxt(stBest, hfMid, '', Max(G.Best, G.Score), L.W - m * 2, y + L.H * 0.010, White, 1);

    { bottom bar: beads vs goal (classic) / chain (time), hovered move, keys }
    Panel(m, L.H - L.BottomH + m * 0.4, L.W - m, L.H - m * 0.6, 190, frStatus);
    y := (L.H - L.BottomH + m * 0.4 + L.H - m * 0.6) / 2;
    if G.Mode = gmTime then
    begin
      { fewer beads = a bigger value: a pop makes the status react }
      StatTxtS(stStatus, hfMid, Format('BEADS %d', [left]), -left, m * 2, y - L.H * 0.010, White, -1);
      if (G.Chain >= 2) and (G.ChainTimer > 0) then
        Txt(hfSmall, Format('CHAIN x%d  (points x%.1f)', [G.Chain, G.ChainMult]), m * 2, y + L.H * 0.014, Pink)
      else
        HintTxt(hfSmall, 'pop fast for a chain', m * 2, y + L.H * 0.014, Grey, -1);
    end
    else if G.Mode = gmSurvival then
    begin
      StatTxtS(stStatus, hfMid, Format('IRON %d', [G.IronCount]), G.IronCount, m * 2, y - L.H * 0.010, IronCol, -1);
      HintTxt(hfSmall, '2-3 bring iron  ·  7+ bonus', m * 2, y + L.H * 0.014, Grey, -1);
    end
    else
    begin
      if left <= G.Goal then c := Green else c := White;
      StatTxtS(stStatus, hfMid, Format('BEADS %d', [left]), -left, m * 2, y - L.H * 0.010, c, -1);
      HintTxt(hfSmall, Format('goal: %d or fewer', [G.Goal]), m * 2, y + L.H * 0.014, Grey, -1);
    end;
    if (n >= 1) and (G.State = gsPlaying) then
    begin
      Txt(hfMid, Format('%d beads  +%d', [n, pts]), cx, y, Pink, 0);
      if G.Mode = gmSurvival then
      begin
        { what the refill of this move brings }
        TBeadGame.SurvivalRefill(n, iron, bonus);
        if iron > 0 then Txt(hfSmall, Format('+%d iron', [iron]), cx, y + L.H * 0.022, IronCol, 0)
        else if bonus > 0 then Txt(hfSmall, Format('+%d bonus', [bonus]), cx, y + L.H * 0.022, BGRA(255, 215, 90), 0);
      end;
    end;
    if G.Mode <> gmClassic then
      s := 'R restart'
    else
      s := Format('U undo (%d)   R restart', [G.UndoLeft]);
    HintTxt(hfSmall, s, L.W - m * 2, y - L.H * 0.010, Grey, 1);
    if Muted then s := 'M sound off' else s := 'M sound on';
    HintTxt(hfSmall, 'Esc menu   ' + s, L.W - m * 2, y + L.H * 0.014, Grey, 1);
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
      4: begin rowH := lineH * 0.56; if Ach <> nil then rows := Ach.CountIn(AchPage) else rows := 0; end;
    else
      begin rowH := 0; rows := 0; end;
    end;
    ph := Round(lineH * (4.4 + n * 1.3 + 3.6) + rows * rowH + Ord(rows > 0) * lineH * 0.4);
    if Menu.Screen = 0 then ph += Round(lineH * 1.1);   // rank bar
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
      0: if Subtitle <> '' then Txt(hfSmall, Subtitle, cx, y, Grey, 0)
         else Txt(hfSmall, 'pop groups of 2+ touching beads of one colour  ·  n x (n - 1) x 5', cx, y, Grey, 0);
      1: HeadTxt(hfMid, 'OPTIONS', cx, y, Pink);
      5: HeadTxt(hfMid, 'CHEAT CODE', cx, y, Pink);
      3:
        begin
          s := ModeName(ScoreMode);
          HeadTxt(hfMid, 'HIGH SCORES  ·  <  ' + s + '  >', cx, y, Pink);
        end;
      4: if Ach <> nil then
           HeadTxt(hfMid, Format('ACHIEVEMENTS  ·  <  %s  >   %d / %d', [AchGroupNames[AchPage],
             Ach.UnlockedIn(AchPage), Ach.CountIn(AchPage)]), cx, y, Pink);
    else
      if G.Mode = gmTime then
        Txt(hfMid, Format('time attack   ·   score %s   ·   %d s left',
          [FormatFloat('#,##0', G.Score), Ceil(G.TimeLeft)]), cx, y, Pink, 0)
      else if G.Mode = gmSurvival then
        Txt(hfMid, Format('survival   ·   score %s   ·   %d iron',
          [FormatFloat('#,##0', G.Score), G.IronCount]), cx, y, Pink, 0)
      else if (G.Mode = gmVersus) and (Bot <> nil) then
        Txt(hfMid, Format('vs %s bot   ·   you %s   ·   bot %s',
          [BotNames[EnsureRange(G.VsBotLevel, 0, BotLevels - 1)], FormatFloat('#,##0', G.Score),
           FormatFloat('#,##0', Bot.Score)]), cx, y, Pink, 0)
      else
        Txt(hfMid, Format('level %d   ·   score %s   ·   %d beads left',
          [G.Level, FormatFloat('#,##0', G.Score), left]), cx, y, Pink, 0);
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
          Txt(hfSmall, 'every completed level shows its code (score, lives, level)', cx, y, Grey, 0);
        y += lineH * 0.8;
        Txt(hfSmall, 'type the code or paste it: Ctrl+P / Ctrl+V', cx, y, Cyan, 0);
        y += lineH * 0.6;
      end
      else if Menu.Screen = 3 then
      begin
        { high-score table of the chosen mode }
        mode := ScoreMode;
        Txt(hfSmall, '#', x, y, Grey);
        Txt(hfSmall, 'NAME', x + pw * 0.08, y, Grey);
        case mode of
          gmTime: s := 'BOARDS';
          gmSurvival: s := 'POPS';
          gmVersus: s := 'BOT';
        else
          s := 'LEVEL';
        end;
        Txt(hfSmall, s, cx + pw * 0.12, y, Grey, 0);
        Txt(hfSmall, 'SCORE', cx + pw * 0.42, y, Grey, 1);
        for i := 0 to MaxScores - 1 do
        begin
          y += rowH;
          if (i = NewRank) and (mode = NewRankMode) then
          begin
            FTarget.FillRoundRectAntialias(x - lineH * 0.3, y - rowH * 0.48, cx + pw / 2 - lineH * 0.5,
              y + rowH * 0.48, 6, 6, BGRA(245, 70, 170, 70));
            c := Cyan;
          end
          else if i = 0 then c := BGRA(255, 215, 90)
          else c := White;
          Txt(hfMid, IntToStr(i + 1), x, y, c);
          if i <= High(Ach.Scores[mode]) then
          begin
            Txt(hfMid, Ach.Scores[mode][i].Name, x + pw * 0.08, y, c);
            if mode = gmVersus then
              Txt(hfMid, BotNames[EnsureRange(Ach.Scores[mode][i].Level, 0, BotLevels - 1)], cx + pw * 0.12, y, c, 0)
            else
              Txt(hfMid, IntToStr(Ach.Scores[mode][i].Level), cx + pw * 0.12, y, c, 0);
            Txt(hfMid, FormatFloat('#,##0', Ach.Scores[mode][i].Score), cx + pw * 0.42, y, c, 1);
          end
          else
            Txt(hfMid, '- - -', x + pw * 0.08, y, BGRA(90, 90, 110));
        end;
      end
      else
      begin
        { achievements: name + what to do, lit when unlocked }
        k := 0;
        for a := Low(TAchId) to High(TAchId) do
        begin
          if AchGroup(a) <> AchPage then Continue;
          if k > 0 then y += rowH;
          Inc(k);
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
    if (Menu.Screen = 0) and (Ach <> nil) then
    begin
      { rank, XP bar, stars of the chosen start level }
      k := Ach.Rank;
      Txt(hfMid, Format('RANK %d  ·  %s', [k + 1, RankNames[k]]), cx - pw * 0.42, y, Cyan);
      bw := pw * 0.4;
      x := cx + pw * 0.42 - bw;
      if k < RankCount - 1 then
        frac := EnsureRange((Ach.XP - Ach.RankXP(k)) / Max(1, Ach.RankXP(k + 1) - Ach.RankXP(k)), 0, 1)
      else
        frac := 1;
      FTarget.FillRoundRectAntialias(x, y - lineH * 0.12, x + bw, y + lineH * 0.12, 5, 5, BGRA(50, 55, 75));
      if frac > 0 then
        FTarget.FillRoundRectAntialias(x, y - lineH * 0.12, x + bw * frac, y + lineH * 0.12, 5, 5, Cyan);
      if k < RankCount - 1 then
        Txt(hfSmall, Format('%s / %s XP', [FormatFloat('#,##0', Ach.XP), FormatFloat('#,##0', Ach.RankXP(k + 1))]),
          x + bw / 2, y + lineH * 0.36, Grey, 0);
      y += lineH * 1.0;
      Txt(hfMid, Format('best %s', [FormatFloat('#,##0', G.Best)]), cx - pw * 0.42, y, White);
      Txt(hfMid, Format('stars %d', [Ach.TotalStars]), cx + pw * 0.05, y, BGRA(255, 215, 90), 0);
      { the start level's stars }
      for i := 1 to 3 do
        Star(cx + pw * 0.42 - (3 - i) * lineH * 0.55 - lineH * 0.25, y, lineH * 0.24,
          i <= Ach.StarsOf(StartLevel), 255);
      Txt(hfSmall, Format('level %d', [StartLevel]), cx + pw * 0.42 - lineH * 1.9, y, Grey, 1);
    end
    else if Menu.Screen in [3, 4] then
      Txt(hfMid, Format('best score  %s', [FormatFloat('#,##0', G.Best)]), cx, y, White, 0)
    else
      Txt(hfMid, 'now playing:  ' + Menu.NowPlaying, cx, y, White, 0);
    y += lineH * 0.95;
    if Menu.Screen = 4 then
      Txt(hfSmall, 'Left / Right: group     Enter, Esc or click: back', cx, y, Grey, 0)
    else if Menu.Screen = 3 then
      Txt(hfSmall, 'Left / Right: mode     Enter, Esc or click: back', cx, y, Grey, 0)
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
    gsLevelDone:
      begin
        ph := lineH * 9;
        Panel(cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2, 215);
        y := cy - ph / 2 + lineH * 1.1;
        if left = 0 then s := 'BOARD CLEARED!' else s := Format('LEVEL %d COMPLETE', [G.Level]);
        HeadTxt(hfBig, s, cx, y, Green);
        { the stars pop in one after the other }
        y += lineH * 1.5;
        for i := 1 to 3 do
        begin
          t := EnsureRange((StarTime - 0.3 - (i - 1) * 0.35) / 0.3, 0, 1);
          if (i <= G.Stars) and (t > 0) then
            Star(cx + (i - 2) * lineH * 1.5, y, lineH * (0.55 + 0.25 * Sin(t * Pi)), True, 255)
          else
            Star(cx + (i - 2) * lineH * 1.5, y, lineH * 0.55, False, 255);
        end;
        y += lineH * 1.2;
        if NewStarBest then
          Txt(hfMid, Format('new best!   total stars %d', [Ach.TotalStars]), cx, y, BGRA(255, 215, 90), 0)
        else
          Txt(hfMid, Format('%d beads left  (goal %d or fewer)', [left, G.Goal]), cx, y, White, 0);
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
        if G.Mode = gmTime then
        begin
          HeadTxt(hfBig, 'TIME''S UP!', cx, y, Pink);
          y += lineH * 1.2;
          Txt(hfMid, Format('boards %d   ·   cleared %d   ·   best chain x%d',
            [G.Boards, G.BoardsCleared, G.MaxChain]), cx, y, White, 0);
        end
        else if (G.Mode = gmVersus) and (Bot <> nil) then
        begin
          case G.VsResult of
            1: HeadTxt(hfBig, 'YOU WIN!', cx, y, Green);
            3: HeadTxt(hfBig, 'DRAW', cx, y, Cyan);
          else
            HeadTxt(hfBig, BotNames[EnsureRange(G.VsBotLevel, 0, BotLevels - 1)] + ' BOT WINS', cx, y, Pink);
          end;
          y += lineH * 1.2;
          Txt(hfMid, Format('iron sent %d   ·   received %d   ·   bot score %s',
            [G.IronSent, G.IronReceived, FormatFloat('#,##0', Bot.Score)]), cx, y, White, 0);
        end
        else if G.Mode = gmSurvival then
        begin
          HeadTxt(hfBig, 'NO MORE PAIRS', cx, y, Pink);
          y += lineH * 1.2;
          Txt(hfMid, Format('survived %d pops   ·   biggest group %d   ·   %d iron',
            [G.Pops, G.MaxGroup, G.IronCount]), cx, y, White, 0);
        end
        else
        begin
          HeadTxt(hfBig, 'NO MORE MOVES', cx, y, Pink);
          y += lineH * 1.2;
          Txt(hfMid, Format('%d beads left, goal was %d or fewer', [left, G.Goal]), cx, y, White, 0);
        end;
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
          if G.Mode <> gmClassic then s := 'click / Enter: play again'
          else if G.UndoLeft > 0 then s := Format('click / Enter: retry level     U: undo (%d)', [G.UndoLeft])
          else s := 'click / Enter: retry level (score from level start)';
          Txt(hfSmall, s, cx, y, Cyan, 0);
          y += lineH * 0.6;
          Txt(hfSmall, 'H: high scores     Esc: menu', cx, y, Cyan, 0);
        end;
      end;
  end;
  FTarget := Bmp;
end;

{ toast cards (achievements, rank ups, themes, hints): slide in under the
  top bar, then fade }
procedure TGameHud.DrawToasts(const L: TLayout);
var
  i, k: Integer;
  t, e, op, y, pw, ph, cx: Single;
  c: TBGRAPixel;
begin
  if Ach = nil then Exit;
  FTarget := Bmp;
  cx := L.W / 2;
  pw := Min(L.W * 0.86, L.H * 0.56);
  ph := L.H * 0.075;
  k := 0;
  for i := 0 to High(Ach.Toasts) do
  begin
    t := Ach.Toasts[i].Age;
    if (t <= 0) or (k >= 3) then Continue;
    e := EaseOutBack(t / 0.45);
    op := Clamp01(t / 0.2) * Clamp01((4 - t) / 0.6);
    c := BGRA(Ach.Toasts[i].R, Ach.Toasts[i].G, Ach.Toasts[i].B);
    y := L.TopH + L.H * 0.012 + k * (ph + L.H * 0.01) - (1 - e) * ph * 1.5;
    FTarget.FillRoundRectAntialias(cx - pw / 2, y, cx + pw / 2, y + ph, 12, 12, BGRA(14, 12, 30, Round(225 * op)));
    FTarget.RoundRectAntialias(cx - pw / 2, y, cx + pw / 2, y + ph, 12, 12,
      BGRA(c.red, c.green, c.blue, Round(255 * op)), 2);
    { a medal }
    FTarget.FillEllipseAntialias(cx - pw / 2 + ph * 0.55, y + ph / 2, ph * 0.26, ph * 0.26,
      BGRA(c.red, c.green, c.blue, Round(255 * op)));
    FTarget.FillEllipseAntialias(cx - pw / 2 + ph * 0.55, y + ph / 2, ph * 0.12, ph * 0.12,
      BGRA(255, 250, 220, Round(255 * op)));
    Txt(hfSmall, Ach.Toasts[i].Title, cx + ph * 0.3, y + ph * 0.3, c, 0, Round(255 * op));
    Txt(hfMid, Ach.Toasts[i].Text, cx + ph * 0.3, y + ph * 0.68, White, 0, Round(255 * op));
    Inc(k);
  end;
end;

function TGameHud.Update(G: TBeadGame; const L: TLayout): Boolean;
var
  sig, ssig: string;
  i, n, x, y: Integer;
  pop: TPopup;
  px, py, a: Single;
  c: TBGRAPixel;
  f: PCellFx;
begin
  n := G.HoverCount;
  sig := Format('%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%.1f|%d|%d', [L.W, L.H, Ord(G.State),
    G.Level, G.Score, G.Best, G.BeadsLeft, G.UndoLeft, n, G.MaxLevel, StartLevel, G.Bonus,
    Ord(Muted), L.Cell, Ord(G.Mode), G.HoverPoints]);
  if G.Mode = gmTime then
    sig += Format('|t%d|%d|%d|%d', [Ceil(G.TimeLeft), G.Boards, G.Chain, Ord(G.ChainTimer > 0)]);
  if G.Mode = gmSurvival then
    sig += Format('|v%d|%d|%d', [G.Pops, G.IronCount, G.MaxGroup]);
  if (G.Mode = gmVersus) and (Bot <> nil) then
    sig += Format('|vs%d|%d|%d|%d|%d|%d|%d|%d', [G.IronCount, G.IronSent, G.IronReceived, G.VsResult,
      Bot.Score, Bot.IronCount, G.VsBotLevel, Ord(L.Versus)]) + Format('|ld%d%d|r%d', [G.VsLead, Ord(G.VsIronOn), RulesStamp]) +
      Format('|i%d', [Ord(G.State = gsPlaying) * Ceil(Max(0, VsIdleSecs - G.IdleT - 0.001))]);
  sig += '|a' + IntToStr(AchPage) + '|' + CodeText + '|' + CodeMsg + '|' + LevelCode +
    IntToStr(Ord(CodeCopied));
  sig += Format('|%d|%s|%d|%d|%d|%d', [Ord(NameEntry), NameText, NewRank, ScoreRank, Ord(ScoreMode),
    Ord(NewStarBest)]);
  if G.State = gsLevelDone then sig += Format('|s%d|%d', [G.Stars, Min(20, Trunc(StarTime * 20))]);
  if Ach <> nil then sig += Format('|%d|%d|%d|%d|%d|%d|%d', [Ach.UnlockedCount, Length(Ach.Scores[gmClassic]),
    Length(Ach.Scores[gmTime]), Length(Ach.Scores[gmSurvival]), Length(Ach.Scores[gmVersus]),
    Ach.TotalStars, Ach.Rank]);
  if Menu.Active then
  begin
    sig += '|menu' + IntToStr(Menu.Screen) + Menu.Title + '|' + Menu.NowPlaying;
    for i := 0 to High(Menu.Items) do sig += '|' + Menu.Items[i].Caption + Menu.Items[i].Value;
    if Ach <> nil then sig += '|' + IntToStr(Ach.XP);
    sig += '|' + Subtitle;
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
  if L.Versus and (Bot <> nil) then
    for i := 0 to High(Bot.Popups) do
      sig += Format('|b%.2f', [Bot.Popups[i].Age]);
  if Ach <> nil then
    for i := 0 to High(Ach.Toasts) do
      sig += Format('|t%.2f', [Ach.Toasts[i].Age]);
  { special bead icons move with their beads }
  ssig := '';
  if not Menu.Active then
    for x := 0 to G.W - 1 do
      for y := 0 to G.H - 1 do
        if (G.Spec(x, y) <> SpNone) and (G.Cell(x, y) >= 0) then
        begin
          f := G.Fx(x, y);
          ssig += Format('%d,%d,%d,%.2f,%.2f,%.2f,%.1f;', [x, y, G.Spec(x, y), f^.OffX, f^.OffY, f^.Presence, f^.Hover]);
        end;
  if not Menu.Active and L.Versus and (Bot <> nil) then
    for x := 0 to Bot.W - 1 do
      for y := 0 to Bot.H - 1 do
        if (Bot.Spec(x, y) <> SpNone) and (Bot.Cell(x, y) >= 0) then
        begin
          f := Bot.Fx(x, y);
          ssig += Format('b%d,%d,%d,%.2f,%.2f,%.2f,%.1f;', [x, y, Bot.Spec(x, y), f^.OffX, f^.OffY, f^.Presence, f^.Hover]);
        end;
  sig += ssig;
  if (sig = FSignature) and not Menu.Active and (Length(FHeads) = 0) and not StatsBusy and not FramesBusy then Exit(False);
  FSignature := sig;
  Result := True;

  { the frame's HUD = cached base + special icons + the floating score popups }
  if (Bmp.Width <> L.W) or (Bmp.Height <> L.H) then Bmp.SetSize(L.W, L.H);
  Move(FBase.Data^, Bmp.Data^, L.W * L.H * SizeOf(TBGRAPixel));
  DrawFrames;  // animated frame borders
  DrawStatusX; // progress bar and key hints of the status bar
  DrawStats;   // Level / Score / Best / Status with their effects
  if not Menu.Active then   // no popups / icons on top of the menus
  begin
    if not (G.State in [gsLevelDone, gsGameOver]) then
    begin
      DrawSpecials(G, L, L.BoardX0);
      if L.Versus and (Bot <> nil) then DrawSpecials(Bot, L, L.Board2X0);
    end;
    DrawPopups(G, L, L.BoardX0);
    if L.Versus and (Bot <> nil) then DrawPopups(Bot, L, L.Board2X0);
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
