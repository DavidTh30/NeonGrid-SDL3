unit uMenuFxEditor;

{ Neon Menu Effect Editor - tunes the animated menus of Neon Beads and Neon
  Trail (NeonBeads.menufx / NeonTrail.menufx, see uMenuFx).

  Left: a live preview drawn by the game's own HUD code (uGameHud of Neon
  Beads, the same effect code as Neon Trail; title, menus and texts follow
  the chosen game) for the chosen screen: main
  menu, options, high scores, cheat code, pause, level complete, game over.
  Right: one slider per effect (multipliers: 1 = the original look, 0 = off)
  and an optional custom palette. The bead colours of the preview (title,
  headings, comets, selection, the dot backdrop) come from the game's
  .visuals file (NeonVisualEditor): the Neon Beads theme in use or the Neon
  Trail bead colours; a saved change there shows up here within 0.5 s.
  The dot backdrop is animated like the games' background: the colour field
  (blobs, ambient, boundary, shadow) and the background motion of the
  .visuals file (Background > Motion), drawn on the CPU each frame with the
  formulas of dots_ps.hlsl (FieldColor, MoveField). Save writes the game's file; with "live"
  every change is saved at once, so a running game follows the sliders.
  Level / Score / Best (bottom of the list): the top bar while playing, each
  with its own style, reaction to a change, colour, strength, speed, size,
  glow and reaction time. Touching them switches the preview to "In game",
  where the score runs by itself (simulate) and Test changes that value now.
  Menu items (own page): the items that are not selected - size, colour,
  art style, idle motion, the reaction when the selector leaves and the
  trail it leaves behind; "Move selector" moves it at once.
  Frames (own page): the frames of the top bar, the status bar and the
  message boxes (border style, colour, glow, fill, intro) and the status
  bar extras (progress bar style, key hints); Show picks a preview screen
  with that frame, Replay intro shows the intro again. The Status text has
  its own effects on the Level / Score / Best / Status page. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Dialogs,
  IniFiles, SDL3, SDL3_ttf, BGRABitmap, BGRABitmapTypes, uParams, uMenuFx, uBeadGame, uAchievements, uGameHud;

type
  TFxForm = class(TForm)
  private
    FHud: TGameHud;
    FGame: TBeadGame;
    FBack, FFrame: TBGRABitmap;
    FFile: string;
    FDirty, FUpdating, FTtfOk: Boolean;
    FT0, FLastT, FSelT: Double;
    FMenuTime, FItemTime: Single;
    FSel: Integer;
    FVisAge: LongInt;          // file time of the .visuals file the colours came from
    FVisT: Double;
    FColourInfo: string;
    cbGame, cbScreen: TComboBox;
    chkLive, chkAutoSel, chkPal: TCheckBox;
    lblStatus: TLabel;
    pbPreview: TPaintBox;
    sbParams, sbStats: TScrollBox;
    pcRight: TPageControl;
    tsMenu, tsStats: TTabSheet;
    tb: array[0..FxParamCount - 1] of TTrackBar;
    lv: array[0..FxParamCount - 1] of TLabel;
    cbtn: array[0..3] of TColorButton;
    { Level / Score / Best: combos (style, reaction, colour mode), sliders, colours }
    scb: array[0..StatCount - 1, spStyle..spColourMode] of TComboBox;
    stb: array[0..StatCount - 1, spStrength..spReactTime] of TTrackBar;
    slv: array[0..StatCount - 1, spStrength..spReactTime] of TLabel;
    scol: array[0..StatCount - 1, 0..1] of TColorButton;
    chkSim: TCheckBox;
    { menu items that are not selected }
    icb: array[0..ItemParamCount - 1] of TComboBox;
    itb: array[0..ItemParamCount - 1] of TTrackBar;
    ilv: array[0..ItemParamCount - 1] of TLabel;
    icol: array[0..1] of TColorButton;
    sbItems: TScrollBox;
    tsItems: TTabSheet;
    { frames and status bar extras }
    fcb: array[0..FrameCount - 1, 0..FrameParamCount - 1] of TComboBox;
    ftb: array[0..FrameCount - 1, 0..FrameParamCount - 1] of TTrackBar;
    flv: array[0..FrameCount - 1, 0..FrameParamCount - 1] of TLabel;
    fcol: array[0..FrameCount - 1, 0..2] of TColorButton;
    xcb: array[0..StatusXCount - 1] of TComboBox;
    xtb: array[0..StatusXCount - 1] of TTrackBar;
    xlv: array[0..StatusXCount - 1] of TLabel;
    sbFrames: TScrollBox;
    tsFrames: TTabSheet;
    FSimT: Double;
    Timer, SaveTimer: TTimer;
    procedure BuildUI;
    procedure LoadFile(const AFile: string);
    procedure ShowValues;
    procedure ParamChange(Sender: TObject);
    procedure PaletteChange(Sender: TObject);
    procedure StatChange(Sender: TObject);
    procedure StatTestClick(Sender: TObject);
    procedure ShowInGame;
    procedure PageChange(Sender: TObject);
    procedure ItemChange(Sender: TObject);
    procedure MoveSelClick(Sender: TObject);
    procedure BuildItemsPage;
    procedure BuildFramesPage;
    procedure FrameChange(Sender: TObject);
    procedure FrameShowClick(Sender: TObject);
    procedure ShowFrame(AKind: Integer);
    procedure PopOne;
    procedure SimStep(AKind: Integer);
    procedure Changed;
    procedure GameChange(Sender: TObject);
    procedure ScreenChange(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveBothClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure DefaultsClick(Sender: TObject);
    procedure IntroClick(Sender: TObject);
    procedure LiveSave(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure PreviewPaint(Sender: TObject);
    procedure BuildBackground(AW, AH: Integer);
    procedure RenderBackground(T: Double);
    procedure LoadVisualColours;
    function VisualsFile: string;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    function Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer; AClick: TNotifyEvent): TButton;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  FxForm: TFxForm;

implementation

const
  PW = 470;   // preview size (portrait, like the games)
  PH = 720;

function GameFile(AIndex: Integer): string;
begin
  if AIndex = 2 then
    Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Shooter\NeonShooter.menufx')
  else if AIndex = 1 then
    Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Trail\NeonTrail.menufx')
  else
    Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Game\NeonBeads.menufx');
end;

function Now_s: Double;
begin
  Result := GetTickCount64 / 1000;
end;

{ trackbar position (0..1000) <-> parameter value }
function ToPos(AIndex: Integer; AValue: Single): Integer;
begin
  with FxParams[AIndex] do
    Result := Round((AValue - Min) / Math.Max(1e-6, Max - Min) * 1000);
end;

function FromPos(AIndex, APos: Integer): Single;
begin
  with FxParams[AIndex] do
  begin
    Result := Min + (Max - Min) * APos / 1000;
    if IsInt then Result := Round(Result);
  end;
end;

function RGBToCard(C: TColor): Cardinal;
begin
  C := ColorToRGB(C);
  Result := (Cardinal(Red(C)) shl 16) or (Cardinal(Green(C)) shl 8) or Cardinal(Blue(C));
end;

function CardToColor(C: Cardinal): TColor;
begin
  Result := RGBToColor((C shr 16) and 255, (C shr 8) and 255, C and 255);
end;

{ TFxForm }

constructor TFxForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner, 0);
  Caption := 'Neon Menu Effect Editor';
  Width := 1180;
  Height := 860;
  Position := poScreenCenter;
  OnCloseQuery := @FormCloseQuery;
  FTtfOk := TTF_Init;
  FGame := TBeadGame.Create;
  FHud := TGameHud.Create;
  FHud.StartLevel := 3;
  FFrame := TBGRABitmap.Create(PW, PH);
  BuildBackground(PW, PH);   // replaced by LoadVisualColours (LoadFile) with the game's colours
  BuildUI;
  cbGame.ItemIndex := 0;
  LoadFile(GameFile(0));
  FT0 := Now_s;
  FLastT := FT0;
  Timer.Enabled := True;
  if not FTtfOk then lblStatus.Caption := 'SDL3_ttf could not start: the preview has no text.';
end;

destructor TFxForm.Destroy;
begin
  Timer.Enabled := False;
  FHud.Free;
  FGame.Free;
  FBack.Free;
  FFrame.Free;
  inherited Destroy;
end;

function TFxForm.Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AW, 26);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

procedure TFxForm.BuildUI;
var
  pTop, pLeft: TPanel;
  i, j, k, y: Integer;
  g: string;
  l: TLabel;

  function Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := AParent;
    Result.Left := AX;
    Result.Top := AY;
    Result.Caption := ACaption;
  end;

begin
  pTop := TPanel.Create(Self);
  pTop.Parent := Self;
  pTop.Align := alTop;
  pTop.Height := 40;
  pTop.BevelOuter := bvNone;
  Lbl(pTop, 'Game', 8, 12);
  cbGame := TComboBox.Create(Self);
  cbGame.Parent := pTop;
  cbGame.SetBounds(48, 8, 120, 24);
  cbGame.Style := csDropDownList;
  cbGame.Items.Add('Neon Beads');
  cbGame.Items.Add('Neon Trail');
  cbGame.Items.Add('Neon Shooter');
  cbGame.OnChange := @GameChange;
  Btn(pTop, 'Save', 176, 7, 60, @SaveClick);
  Btn(pTop, 'Save to all games', 240, 7, 130, @SaveBothClick);
  Btn(pTop, 'Reload', 374, 7, 64, @ReloadClick);
  Btn(pTop, 'Defaults', 442, 7, 70, @DefaultsClick);
  chkLive := TCheckBox.Create(Self);
  chkLive.Parent := pTop;
  chkLive.SetBounds(524, 10, 250, 22);
  chkLive.Caption := 'live: save every change (running game follows)';
  Lbl(pTop, 'Preview', 790, 12);
  cbScreen := TComboBox.Create(Self);
  cbScreen.Parent := pTop;
  cbScreen.SetBounds(844, 8, 140, 24);
  cbScreen.ItemWidth := 230;
  cbScreen.Style := csDropDownList;
  cbScreen.Items.CommaText := '"Main menu","Options","High scores","Cheat code","Pause","Level complete","Game over","In game (Level / Score / Best)"';
  cbScreen.DropDownCount := 10;
  cbScreen.ItemIndex := 0;
  cbScreen.OnChange := @ScreenChange;
  Btn(pTop, 'Replay intro', 990, 7, 90, @IntroClick);
  chkAutoSel := TCheckBox.Create(Self);
  chkAutoSel.Parent := pTop;
  chkAutoSel.SetBounds(1086, 10, 90, 22);
  chkAutoSel.Caption := 'auto select';
  chkAutoSel.Checked := True;

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := Self;
  lblStatus.Align := alBottom;
  lblStatus.BorderSpacing.Around := 4;
  lblStatus.Caption := '';

  pLeft := TPanel.Create(Self);
  pLeft.Parent := Self;
  pLeft.Align := alLeft;
  pLeft.Width := PW + 16;
  pLeft.BevelOuter := bvNone;
  pbPreview := TPaintBox.Create(Self);
  pbPreview.Parent := pLeft;
  pbPreview.SetBounds(8, 4, PW, PH);
  pbPreview.OnPaint := @PreviewPaint;

  { right: the menu effects and, on their own page, Level / Score / Best }
  pcRight := TPageControl.Create(Self);
  pcRight.Parent := Self;
  pcRight.Align := alClient;
  pcRight.OnChange := @PageChange;
  tsMenu := pcRight.AddTabSheet;
  tsMenu.Caption := 'Menu effects';
  tsItems := pcRight.AddTabSheet;
  tsItems.Caption := 'Menu items (not selected)';
  tsStats := pcRight.AddTabSheet;
  tsStats.Caption := 'Level / Score / Best / Status';
  tsFrames := pcRight.AddTabSheet;
  tsFrames.Caption := 'Frames';
  sbParams := TScrollBox.Create(Self);
  sbParams.Parent := tsMenu;
  sbParams.Align := alClient;
  sbParams.VertScrollBar.Tracking := True;
  y := 6;
  g := '';
  for i := 0 to FxParamCount - 1 do
  begin
    if FxParams[i].Group <> g then
    begin
      g := FxParams[i].Group;
      l := Lbl(sbParams, g, 8, y + 4);
      l.Font.Style := [fsBold];
      Inc(y, 26);
    end;
    l := Lbl(sbParams, FxParams[i].Caption, 16, y + 6);
    l.Hint := FxParams[i].Hint;
    l.ShowHint := True;
    tb[i] := TTrackBar.Create(Self);
    tb[i].Parent := sbParams;
    tb[i].SetBounds(190, y, 330, 28);
    tb[i].Max := 1000;
    tb[i].TickStyle := tsNone;
    tb[i].Tag := i;
    tb[i].Hint := FxParams[i].Hint;
    tb[i].ShowHint := True;
    tb[i].OnChange := @ParamChange;
    lv[i] := Lbl(sbParams, '', 528, y + 6);
    Inc(y, 30);
  end;
  l := Lbl(sbParams, 'Palette', 8, y + 4);
  l.Font.Style := [fsBold];
  Inc(y, 26);
  chkPal := TCheckBox.Create(Self);
  chkPal.Parent := sbParams;
  chkPal.SetBounds(16, y, 300, 22);
  chkPal.Caption := 'custom palette (instead of the bead colours)';
  chkPal.OnClick := @PaletteChange;
  Inc(y, 28);
  for i := 0 to 3 do
  begin
    cbtn[i] := TColorButton.Create(Self);
    cbtn[i].Parent := sbParams;
    cbtn[i].SetBounds(16 + i * 92, y, 86, 28);
    cbtn[i].OnColorChanged := @PaletteChange;
  end;
  sbStats := TScrollBox.Create(Self);
  sbStats.Parent := tsStats;
  sbStats.Align := alClient;
  sbStats.VertScrollBar.Tracking := True;
  y := 6;
  { Level / Score / Best of the in-game top bar, each on its own }
  l := Lbl(sbStats, 'In game: Level / Score / Best and the Status text (each has its own effects)', 8, y + 4);
  l.Font.Style := [fsBold];
  Inc(y, 24);
  chkSim := TCheckBox.Create(Self);
  chkSim.Parent := sbStats;
  chkSim.SetBounds(16, y, 420, 22);
  chkSim.Caption := 'preview "In game": the score runs by itself (a new level now and then)';
  chkSim.Checked := True;
  Inc(y, 28);
  for k := 0 to StatCount - 1 do
  begin
    l := Lbl(sbStats, UpperCase(StatNames[k]), 8, y + 6);
    l.Font.Style := [fsBold];
    with Btn(sbStats, 'Test', 190, y + 1, 70, @StatTestClick) do
    begin
      Tag := k;
      Hint := 'change the ' + StatNames[k] + ' value now (preview "In game")';
      ShowHint := True;
    end;
    Inc(y, 32);
    for i := spStyle to spColourMode do
    begin
      l := Lbl(sbStats, StatParams[i].Caption, 16, y + 4);
      l.Hint := StatParams[i].Hint;
      l.ShowHint := True;
      scb[k, i] := TComboBox.Create(Self);
      scb[k, i].Parent := sbStats;
      scb[k, i].SetBounds(190, y, 200, 24);
      scb[k, i].Style := csDropDownList;
      scb[k, i].DropDownCount := 12;
      case i of
        spStyle: for j := 0 to StatStyleCount - 1 do scb[k, i].Items.Add(StatStyleNames[j]);
        spReact: for j := 0 to StatReactCount - 1 do scb[k, i].Items.Add(StatReactNames[j]);
      else
        for j := 0 to StatColourCount - 1 do scb[k, i].Items.Add(StatColourNames[j]);
      end;
      scb[k, i].Tag := k * 16 + i;
      scb[k, i].OnChange := @StatChange;
      if i = spColourMode then
        for j := 0 to 1 do
        begin
          scol[k, j] := TColorButton.Create(Self);
          scol[k, j].Parent := sbStats;
          scol[k, j].SetBounds(398 + j * 76, y - 2, 72, 28);
          scol[k, j].Tag := k * 16 + 8 + j;
          scol[k, j].Hint := BoolToStr(j = 0, 'own colour (and gradient start)', 'gradient end');
          scol[k, j].ShowHint := True;
          scol[k, j].OnColorChanged := @StatChange;
        end;
      Inc(y, 30);
    end;
    for i := spStrength to spReactTime do
    begin
      l := Lbl(sbStats, StatParams[i].Caption, 16, y + 6);
      l.Hint := StatParams[i].Hint;
      l.ShowHint := True;
      stb[k, i] := TTrackBar.Create(Self);
      stb[k, i].Parent := sbStats;
      stb[k, i].SetBounds(190, y, 330, 28);
      stb[k, i].Max := 1000;
      stb[k, i].TickStyle := tsNone;
      stb[k, i].Tag := k * 16 + i;
      stb[k, i].Hint := StatParams[i].Hint;
      stb[k, i].ShowHint := True;
      stb[k, i].OnChange := @StatChange;
      slv[k, i] := Lbl(sbStats, '', 528, y + 6);
      Inc(y, 30);
    end;
    Inc(y, 8);
  end;

  BuildItemsPage;
  BuildFramesPage;

  Timer := TTimer.Create(Self);
  Timer.Interval := 33;
  Timer.Enabled := False;
  Timer.OnTimer := @Tick;
  SaveTimer := TTimer.Create(Self);
  SaveTimer.Interval := 350;
  SaveTimer.Enabled := False;
  SaveTimer.OnTimer := @LiveSave;

  pTop.Top := 0;
  lblStatus.Top := 6000;
end;

{ the dot-grid backdrop of the games (static, a little dimmed) }
procedure TFxForm.BuildBackground(AW, AH: Integer);
var
  x, y, cell, k: Integer;
  c: TBGRAPixel;
begin
  FBack.Free;
  FBack := TBGRABitmap.Create(AW, AH, BGRA(4, 6, 14));
  cell := 30;
  for y := 0 to AH div cell + 1 do
    for x := 0 to AW div cell + 1 do
    begin
      k := (x * 7 + y * 3 + (x * y) mod 5) mod 6;
      c := BGRA(BeadRGB[k, 0], BeadRGB[k, 1], BeadRGB[k, 2]);   // the colours of the .visuals file
      FBack.FillEllipseAntialias(x * cell + cell / 2, y * cell + cell / 2, cell * 0.42, cell * 0.42,
        BGRA(c.red div 4, c.green div 4, c.blue div 4));
      FBack.EllipseAntialias(x * cell + cell / 2, y * cell + cell / 2, cell * 0.42, cell * 0.42,
        BGRA(c.red div 2, c.green div 2, c.blue div 2), 1.5);
    end;
end;

{ ---- animated backdrop: CPU port of the games' dots_ps.hlsl (FieldColor,
  MoveField) with the background values of the .visuals file (uParams P) }

function SStep(e0, e1, x: Single): Single;
var
  t: Single;
begin
  if e1 = e0 then
  begin
    if x >= e0 then Exit(1) else Exit(0);
  end;
  t := EnsureRange((x - e0) / (e1 - e0), 0, 1);
  Result := t * t * (3 - 2 * t);
end;

function MirrorF(x: Single): Single;
var
  f: Single;
begin
  f := Frac(Frac(x * 0.5) + 1) * 2;
  if f < 1 then Result := f else Result := 2 - f;
end;

procedure MoveField(var u, v: Single; t, aspect: Single);
var
  mode: Integer;
  px, py, dx, dy, a, sn, cs, r, nx: Single;
begin
  mode := P.MotionMode;
  if mode <= 0 then Exit;
  dx := Cos(P.MotionAngle * Pi / 180);
  dy := Sin(P.MotionAngle * Pi / 180);
  px := (u - P.MotionCX) * aspect;
  py := v - P.MotionCY;
  case mode of
    1: begin px += dx * t * P.MotionSpeed * 0.05; py += dy * t * P.MotionSpeed * 0.05; end;
    2: begin a := P.MotionAmount * 0.25 * Sin(t * P.MotionSpeed); px += dx * a; py += dy * a; end;
    3: begin px += P.MotionAmount * 0.25 * Cos(t * P.MotionSpeed); py += P.MotionAmount * 0.25 * Sin(t * P.MotionSpeed); end;
    4:
      begin
        a := t * P.MotionSpeed * 0.2;
        sn := Sin(a); cs := Cos(a);
        nx := px * cs - py * sn; py := px * sn + py * cs; px := nx;
      end;
    5:
      begin
        a := 1 + P.MotionAmount * 0.5 * Sin(t * P.MotionSpeed);
        px *= a; py *= a;
      end;
    6:
      begin
        px += P.MotionAmount * 0.06 * Sin(py * P.MotionFreq * 2 * Pi + t * P.MotionSpeed);
        py += P.MotionAmount * 0.06 * Sin(px * P.MotionFreq * 2 * Pi + t * P.MotionSpeed * 0.8);
      end;
    7:
      begin
        r := Sqrt(px * px + py * py);
        a := P.MotionAmount * 2 * Sin(t * P.MotionSpeed * 0.5) * Exp(-r * r * 4 / Max(0.05, P.MotionFreq));
        sn := Sin(a); cs := Cos(a);
        nx := px * cs - py * sn; py := px * sn + py * cs; px := nx;
      end;
  end;
  u := MirrorF(px / aspect + P.MotionCX);
  v := MirrorF(py + P.MotionCY);
end;

procedure FieldRGB(u, v, t, aspect: Single; out cr, cg, cb: Single);
var
  i: Integer;
  sw, w, bx, by, ddx, ddy, gray, side, d, k: Single;
begin
  sw := Max(P.AmbientWeight, 1e-4);
  cr := P.AmbientColor.red * sw;
  cg := P.AmbientColor.green * sw;
  cb := P.AmbientColor.blue * sw;
  for i := 0 to MaxBlobs - 1 do
    with P.Blobs[i] do
      if Enabled then
      begin
        bx := X + DriftAmp * Sin(t * DriftSpeed + i * 1.7);
        by := Y + DriftAmp * Cos(t * DriftSpeed * 0.83 + i * 2.9);
        ddx := (u - bx) * aspect;
        ddy := v - by;
        w := Weight * Exp(-(ddx * ddx + ddy * ddy) / Max(1e-4, Radius * Radius));
        cr += Color.red * w;
        cg += Color.green * w;
        cb += Color.blue * w;
        sw += w;
      end;
  cr /= sw; cg /= sw; cb /= sw;
  gray := (cr + cg + cb) / 3;
  cr := (gray + (cr - gray) * P.FieldSaturation) * P.FieldBrightness;
  cg := (gray + (cg - gray) * P.FieldSaturation) * P.FieldBrightness;
  cb := (gray + (cb - gray) * P.FieldSaturation) * P.FieldBrightness;
  if P.BoundaryOn then
  begin
    side := u - (P.BoundaryTopX + (P.BoundaryBottomX - P.BoundaryTopX) * v +
      P.BoundaryWaveAmp * Sin(v * P.BoundaryWaveFreq * 2 * Pi + t * P.BoundaryWaveSpeed));
    side := SStep(-P.BoundarySoftness, P.BoundarySoftness, side) * P.BoundaryStrength;
    cr += (P.BoundaryColor.red - cr) * side;
    cg += (P.BoundaryColor.green - cg) * side;
    cb += (P.BoundaryColor.blue - cb) * side;
  end;
  if P.ShadowOn and (P.ShadowStrength > 0) then
  begin
    d := Sqrt(Sqr((u - P.ShadowX) * aspect) + Sqr(v - P.ShadowY)) / Max(P.ShadowRadius, 1e-3);
    k := 1 - P.ShadowStrength * (1 - SStep(0, 1, d));
    cr *= k; cg *= k; cb *= k;
  end;
end;

procedure TFxForm.RenderBackground(T: Double);
const
  Cell = 30;
var
  x, y: Integer;
  u, v, cr, cg, cb, aspect, cx, cy: Single;
begin
  if FBack = nil then FBack := TBGRABitmap.Create(PW, PH);
  FBack.Fill(BGRA(4, 6, 14));
  aspect := PW / PH;
  for y := 0 to PH div Cell do
    for x := 0 to PW div Cell do
    begin
      cx := x * Cell + Cell / 2;
      cy := y * Cell + Cell / 2;
      u := cx / PW;
      v := cy / PH;
      MoveField(u, v, T, aspect);
      FieldRGB(u, v, T, aspect, cr, cg, cb);
      { like the games' menu backdrop: a dim disc and a brighter ring }
      FBack.FillEllipseAntialias(cx, cy, Cell * 0.42, Cell * 0.42,
        BGRA(EnsureRange(Round(cr * 0.3), 0, 255), EnsureRange(Round(cg * 0.3), 0, 255), EnsureRange(Round(cb * 0.3), 0, 255)));
      FBack.EllipseAntialias(cx, cy, Cell * 0.42, Cell * 0.42,
        BGRA(EnsureRange(Round(cr * 0.75), 0, 255), EnsureRange(Round(cg * 0.75), 0, 255), EnsureRange(Round(cb * 0.75), 0, 255)), 1.5);
    end;
end;

{ ---- colours of the game's .visuals file (NeonVisualEditor) }

function TFxForm.VisualsFile: string;
begin
  Result := ChangeFileExt(GameFile(cbGame.ItemIndex), '.visuals');
end;

procedure TFxForm.LoadVisualColours;
const
  Neon: array[0..5, 0..2] of Byte = ((245, 150, 35), (35, 215, 240), (230, 40, 145), (150, 230, 55),
    (150, 75, 240), (245, 55, 55));
var
  ini: TMemIniFile;
  prog: TIniFile;
  f, sec, v: string;
  theme, i, c, missing: Integer;
begin
  f := VisualsFile;
  { defaults: the NEON colours (both games start with them) }
  for i := 0 to 5 do
  begin
    BeadRGB[i, 0] := Neon[i, 0];
    BeadRGB[i, 1] := Neon[i, 1];
    BeadRGB[i, 2] := Neon[i, 2];
  end;
  if cbGame.ItemIndex >= 1 then   // Neon Trail, Neon Shooter: [Bead colours]
    sec := 'Bead colours'
  else
  begin
    { Neon Beads: the theme in use (NeonBeads.ini) }
    theme := 0;
    try
      prog := TIniFile.Create(ChangeFileExt(f, '.ini'));
      try
        theme := EnsureRange(prog.ReadInteger('Progress', 'Theme', 0), 0, ThemeCount - 1);
      finally
        prog.Free;
      end;
    except
      theme := 0;
    end;
    sec := 'Theme ' + ThemeNames[theme];
  end;
  FColourInfo := 'colours: defaults (no ' + ExtractFileName(f) + ' yet - run the game once)';
  if FileExists(f) then
  try
    ini := TMemIniFile.Create(f);
    try
      for i := 0 to 5 do
      begin
        v := Trim(ini.ReadString(sec, 'Colour ' + IntToStr(i + 1), ''));
        if (v <> '') and (v[1] = '#') then Delete(v, 1, 1);
        if (Length(v) = 6) and TryStrToInt('$' + v, c) then
        begin
          BeadRGB[i, 0] := (c shr 16) and 255;
          BeadRGB[i, 1] := (c shr 8) and 255;
          BeadRGB[i, 2] := c and 255;
        end;
      end;
      FColourInfo := 'colours: [' + sec + '] of ' + ExtractFileName(f);
    finally
      ini.Free;
    end;
  except
    FColourInfo := 'colours: could not read ' + ExtractFileName(f);
  end;
  { the background values (colour field, motion) for the animated backdrop }
  ResetDefaults;
  LoadParamsFile(f, missing);
  FVisAge := FileAge(f);
end;

{ ---- file / values }

procedure TFxForm.LoadFile(const AFile: string);
var
  fx: TMenuFx;
begin
  FFile := AFile;
  fx := DefaultMenuFx;
  LoadVisualColours;
  if LoadMenuFxFile(AFile, fx) then lblStatus.Caption := 'Loaded ' + AFile + '   (' + FColourInfo + ')'
  else lblStatus.Caption := 'No effect file yet - defaults shown. Save writes ' + AFile + '   (' + FColourInfo + ')';
  MenuFx := fx;
  FDirty := False;
  ShowValues;
end;

procedure TFxForm.ShowValues;
var
  i, k: Integer;
begin
  FUpdating := True;
  try
    for i := 0 to FxParamCount - 1 do
    begin
      tb[i].Position := ToPos(i, MenuFx.V[i]);
      if FxParams[i].IsInt then lv[i].Caption := IntToStr(Round(MenuFx.V[i]))
      else lv[i].Caption := FormatFloat('0.00', MenuFx.V[i]);
    end;
    chkPal.Checked := MenuFx.CustomPalette;
    for i := 0 to 3 do cbtn[i].ButtonColor := CardToColor(MenuFx.Palette[i]);
    for k := 0 to StatCount - 1 do
    begin
      for i := spStyle to spColourMode do scb[k, i].ItemIndex := Round(MenuFx.Stat[k].V[i]);
      for i := spStrength to spReactTime do
      begin
        with StatParams[i] do stb[k, i].Position := Round((MenuFx.Stat[k].V[i] - Min) / Math.Max(1e-6, Max - Min) * 1000);
        slv[k, i].Caption := FormatFloat('0.00', MenuFx.Stat[k].V[i]);
      end;
      scol[k, 0].ButtonColor := CardToColor(MenuFx.Stat[k].Colour);
      scol[k, 1].ButtonColor := CardToColor(MenuFx.Stat[k].Colour2);
    end;
    for i := 0 to ItemParamCount - 1 do
      if icb[i] <> nil then
        icb[i].ItemIndex := Round(MenuFx.Item.V[i])
      else if itb[i] <> nil then
      begin
        with ItemParams[i] do itb[i].Position := Round((MenuFx.Item.V[i] - Min) / Math.Max(1e-6, Max - Min) * 1000);
        if ItemParams[i].IsInt then ilv[i].Caption := IntToStr(Round(MenuFx.Item.V[i]))
        else ilv[i].Caption := FormatFloat('0.00', MenuFx.Item.V[i]);
      end;
    icol[0].ButtonColor := CardToColor(MenuFx.Item.Colour);
    icol[1].ButtonColor := CardToColor(MenuFx.Item.Colour2);
    for k := 0 to FrameCount - 1 do
    begin
      for i := 0 to FrameParamCount - 1 do
        if fcb[k, i] <> nil then
          fcb[k, i].ItemIndex := Round(MenuFx.Frame[k].V[i])
        else if ftb[k, i] <> nil then
        begin
          with FrameParams[i] do
            ftb[k, i].Position := Round((MenuFx.Frame[k].V[i] - Min) / Math.Max(1e-6, Max - Min) * 1000);
          if FrameParams[i].IsInt then flv[k, i].Caption := IntToStr(Round(MenuFx.Frame[k].V[i]))
          else flv[k, i].Caption := FormatFloat('0.00', MenuFx.Frame[k].V[i]);
        end;
      fcol[k, 0].ButtonColor := CardToColor(MenuFx.Frame[k].Colour);
      fcol[k, 1].ButtonColor := CardToColor(MenuFx.Frame[k].Colour2);
      fcol[k, 2].ButtonColor := CardToColor(MenuFx.Frame[k].FillColour);
    end;
    for i := 0 to StatusXCount - 1 do
      if xcb[i] <> nil then
        xcb[i].ItemIndex := Round(MenuFx.StatusX[i])
      else
      begin
        with StatusXParams[i] do xtb[i].Position := Round((MenuFx.StatusX[i] - Min) / Math.Max(1e-6, Max - Min) * 1000);
        xlv[i].Caption := FormatFloat('0.00', MenuFx.StatusX[i]);
      end;
  finally
    FUpdating := False;
  end;
end;

procedure TFxForm.Changed;
begin
  FDirty := True;
  Inc(MenuFxStamp);   // the preview HUD redraws its cached base
  if chkLive.Checked then
  begin
    SaveTimer.Enabled := False;
    SaveTimer.Enabled := True;
  end;
end;

procedure TFxForm.ParamChange(Sender: TObject);
var
  i: Integer;
begin
  if FUpdating then Exit;
  i := TTrackBar(Sender).Tag;
  MenuFx.V[i] := FromPos(i, TTrackBar(Sender).Position);
  if FxParams[i].IsInt then lv[i].Caption := IntToStr(Round(MenuFx.V[i]))
  else lv[i].Caption := FormatFloat('0.00', MenuFx.V[i]);
  Changed;
end;

procedure TFxForm.PaletteChange(Sender: TObject);
var
  i: Integer;
begin
  if FUpdating then Exit;
  MenuFx.CustomPalette := chkPal.Checked;
  for i := 0 to 3 do MenuFx.Palette[i] := RGBToCard(cbtn[i].ButtonColor);
  Changed;
end;

{ ---- Level / Score / Best }

procedure TFxForm.StatChange(Sender: TObject);
var
  k, i: Integer;
begin
  if FUpdating then Exit;
  k := TComponent(Sender).Tag div 16;
  i := TComponent(Sender).Tag mod 16;
  if Sender is TComboBox then
    MenuFx.Stat[k].V[i] := Math.Max(0, TComboBox(Sender).ItemIndex)
  else if Sender is TTrackBar then
  begin
    with StatParams[i] do MenuFx.Stat[k].V[i] := Min + (Max - Min) * TTrackBar(Sender).Position / 1000;
    slv[k, i].Caption := FormatFloat('0.00', MenuFx.Stat[k].V[i]);
  end
  else if Sender is TColorButton then
  begin
    if i = 8 then MenuFx.Stat[k].Colour := RGBToCard(TColorButton(Sender).ButtonColor)
    else MenuFx.Stat[k].Colour2 := RGBToCard(TColorButton(Sender).ButtonColor);
  end;
  ShowInGame;
  Changed;
end;

procedure TFxForm.PageChange(Sender: TObject);
begin
  if (pcRight.ActivePage = tsStats) or (pcRight.ActivePage = tsFrames) then ShowInGame;
  { the menu items need a menu in the preview }
  if (pcRight.ActivePage = tsItems) and (cbScreen.ItemIndex in [5, 6, 7]) then
  begin
    cbScreen.ItemIndex := 0;
    ScreenChange(nil);
  end;
end;

{ ---- frames and status bar extras }

procedure TFxForm.BuildFramesPage;
const
  Combos = [fpStyle, fpColourMode, fpFillStyle, fpIntro];
  Order: array[0..FrameParamCount - 1] of Integer = (fpStyle, fpColourMode, fpBright, fpWidth, fpRadius,
    fpGlow, fpSpeed, fpCount, fpFillStyle, fpFill, fpIntro, fpIntroTime);
  ColCaps: array[0..2] of string = ('own colour', 'gradient end', 'fill colour');
var
  k, n, i, j, y: Integer;
  l: TLabel;

  function Lbl(const ACaption: string; AX, AY: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := sbFrames;
    Result.Left := AX;
    Result.Top := AY;
    Result.Caption := ACaption;
  end;

  function Track(ATag, AY: Integer; const AHint: string; var ALabel: TLabel): TTrackBar;
  begin
    Result := TTrackBar.Create(Self);
    Result.Parent := sbFrames;
    Result.SetBounds(190, AY, 330, 28);
    Result.Max := 1000;
    Result.TickStyle := tsNone;
    Result.Tag := ATag;
    Result.Hint := AHint;
    Result.ShowHint := True;
    Result.OnChange := @FrameChange;
    ALabel := Lbl('', 528, AY + 6);
  end;

  function Combo(ATag, AY: Integer; const AHint: string; const ANames: array of string): TComboBox;
  var
    q: Integer;
  begin
    Result := TComboBox.Create(Self);
    Result.Parent := sbFrames;
    Result.SetBounds(190, AY + 2, 220, 24);
    Result.Style := csDropDownList;
    Result.DropDownCount := 12;
    for q := 0 to High(ANames) do Result.Items.Add(ANames[q]);
    Result.Tag := ATag;
    Result.Hint := AHint;
    Result.ShowHint := True;
    Result.OnChange := @FrameChange;
  end;

begin
  sbFrames := TScrollBox.Create(Self);
  sbFrames.Parent := tsFrames;
  sbFrames.Align := alClient;
  sbFrames.VertScrollBar.Tracking := True;
  y := 6;
  for k := 0 to FrameCount - 1 do
  begin
    l := Lbl('Frame: ' + FrameNames[k], 8, y + 6);
    l.Font.Style := [fsBold];
    with Btn(sbFrames, 'Show', 190, y + 1, 60, @FrameShowClick) do
    begin
      Tag := k;
      Hint := 'show a preview screen with this frame';
      ShowHint := True;
    end;
    Btn(sbFrames, 'Replay intro', 256, y + 1, 96, @IntroClick);
    Inc(y, 34);
    for n := 0 to FrameParamCount - 1 do
    begin
      i := Order[n];
      l := Lbl(FrameParams[i].Caption, 16, y + 6);
      l.Hint := FrameParams[i].Hint;
      l.ShowHint := True;
      if i in Combos then
      begin
        case i of
          fpStyle: fcb[k, i] := Combo(2000 + k * 32 + i, y, FrameParams[i].Hint, FrameStyleNames);
          fpColourMode: fcb[k, i] := Combo(2000 + k * 32 + i, y, FrameParams[i].Hint, FrameColourNames);
          fpFillStyle: fcb[k, i] := Combo(2000 + k * 32 + i, y, FrameParams[i].Hint, FrameFillNames);
        else
          fcb[k, i] := Combo(2000 + k * 32 + i, y, FrameParams[i].Hint, FrameIntroNames);
        end;
        if i in [fpColourMode, fpFillStyle] then
          for j := 0 to 2 do
            if (i = fpColourMode) = (j < 2) then
            begin
              fcol[k, j] := TColorButton.Create(Self);
              fcol[k, j].Parent := sbFrames;
              if j < 2 then fcol[k, j].SetBounds(418 + j * 76, y, 72, 28)
              else fcol[k, j].SetBounds(418, y, 72, 28);
              fcol[k, j].Tag := 2000 + k * 32 + 20 + j;
              fcol[k, j].Hint := ColCaps[j];
              fcol[k, j].ShowHint := True;
              fcol[k, j].OnColorChanged := @FrameChange;
            end;
      end
      else
        ftb[k, i] := Track(2000 + k * 32 + i, y, FrameParams[i].Hint, flv[k, i]);
      Inc(y, 32);
    end;
    Inc(y, 10);
  end;
  l := Lbl('Status bar extras', 8, y + 6);
  l.Font.Style := [fsBold];
  with Btn(sbFrames, 'Show', 190, y + 1, 60, @FrameShowClick) do
  begin
    Tag := frStatus;
    Hint := 'show the status bar';
    ShowHint := True;
  end;
  Inc(y, 34);
  for i := 0 to StatusXCount - 1 do
  begin
    l := Lbl(StatusXParams[i].Caption, 16, y + 6);
    l.Hint := StatusXParams[i].Hint;
    l.ShowHint := True;
    case i of
      sxBar: xcb[i] := Combo(3000 + i, y, StatusXParams[i].Hint, BarStyleNames);
      sxHints: xcb[i] := Combo(3000 + i, y, StatusXParams[i].Hint, HintStyleNames);
    else
      xtb[i] := Track(3000 + i, y, StatusXParams[i].Hint, xlv[i]);
    end;
    Inc(y, 32);
  end;
end;

{ a preview screen that has the frame: the bars while playing, a message box }
procedure TFxForm.ShowFrame(AKind: Integer);
begin
  if AKind = frBox then
  begin
    if cbScreen.ItemIndex = 7 then
    begin
      cbScreen.ItemIndex := 5;
      ScreenChange(nil);
    end;
  end
  else
    ShowInGame;
end;

procedure TFxForm.FrameShowClick(Sender: TObject);
begin
  if TComponent(Sender).Tag = frBox then
  begin
    { cycle through screens with message boxes }
    case cbScreen.ItemIndex of
      5: cbScreen.ItemIndex := 6;
      6: cbScreen.ItemIndex := 0;
    else
      cbScreen.ItemIndex := 5;
    end;
    ScreenChange(nil);
  end
  else
    ShowInGame;
end;

procedure TFxForm.FrameChange(Sender: TObject);
var
  tg, k, i: Integer;
  v: Single;
begin
  if FUpdating then Exit;
  tg := TComponent(Sender).Tag;
  if tg >= 3000 then
  begin
    i := tg - 3000;
    if Sender is TComboBox then MenuFx.StatusX[i] := Math.Max(0, TComboBox(Sender).ItemIndex)
    else
    begin
      with StatusXParams[i] do v := Min + (Max - Min) * TTrackBar(Sender).Position / 1000;
      MenuFx.StatusX[i] := v;
      xlv[i].Caption := FormatFloat('0.00', v);
    end;
    ShowInGame;
    Changed;
    Exit;
  end;
  k := (tg - 2000) div 32;
  i := (tg - 2000) mod 32;
  if Sender is TComboBox then
    MenuFx.Frame[k].V[i] := Math.Max(0, TComboBox(Sender).ItemIndex)
  else if Sender is TTrackBar then
  begin
    with FrameParams[i] do
    begin
      v := Min + (Max - Min) * TTrackBar(Sender).Position / 1000;
      if IsInt then v := Round(v);
    end;
    MenuFx.Frame[k].V[i] := v;
    if FrameParams[i].IsInt then flv[k, i].Caption := IntToStr(Round(v))
    else flv[k, i].Caption := FormatFloat('0.00', v);
  end
  else if Sender is TColorButton then
    case i of
      20: MenuFx.Frame[k].Colour := RGBToCard(TColorButton(Sender).ButtonColor);
      21: MenuFx.Frame[k].Colour2 := RGBToCard(TColorButton(Sender).ButtonColor);
    else
      MenuFx.Frame[k].FillColour := RGBToCard(TColorButton(Sender).ButtonColor);
    end;
  ShowFrame(k);
  Changed;
end;

{ ---- menu items that are not selected }

procedure TFxForm.BuildItemsPage;
const
  Order: array[0..ItemParamCount - 1] of Integer = (ipSize, ipColourMode, ipArt, ipPixel, ipGlow, ipIdle,
    ipIdleAmount, ipLeave, ipLeaveStrength, ipLeaveTime, ipTrail, ipTrailAmount, ipTrailTime);
var
  n, i, j, y: Integer;
  g: string;
  l: TLabel;

  function Lbl(const ACaption: string; AX, AY: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := sbItems;
    Result.Left := AX;
    Result.Top := AY;
    Result.Caption := ACaption;
  end;

begin
  sbItems := TScrollBox.Create(Self);
  sbItems.Parent := tsItems;
  sbItems.Align := alClient;
  sbItems.VertScrollBar.Tracking := True;
  y := 6;
  l := Lbl('Menu items that are not selected', 8, y + 4);
  l.Font.Style := [fsBold];
  with Btn(sbItems, 'Move selector', 300, y, 110, @MoveSelClick) do
  begin
    Hint := 'move the selection to the next item now (see the reaction and the trail)';
    ShowHint := True;
  end;
  Inc(y, 34);
  g := '';
  for n := 0 to ItemParamCount - 1 do
  begin
    i := Order[n];
    if ItemParams[i].Group <> g then
    begin
      g := ItemParams[i].Group;
      l := Lbl(g, 8, y + 4);
      l.Font.Style := [fsBold];
      Inc(y, 26);
    end;
    l := Lbl(ItemParams[i].Caption, 16, y + 6);
    l.Hint := ItemParams[i].Hint;
    l.ShowHint := True;
    if i in [ipColourMode, ipArt, ipIdle, ipLeave, ipTrail] then
    begin
      icb[i] := TComboBox.Create(Self);
      icb[i].Parent := sbItems;
      icb[i].SetBounds(190, y + 2, 220, 24);
      icb[i].Style := csDropDownList;
      icb[i].DropDownCount := 12;
      case i of
        ipColourMode: for j := 0 to ItemColourCount - 1 do icb[i].Items.Add(ItemColourNames[j]);
        ipArt: for j := 0 to ItemArtCount - 1 do icb[i].Items.Add(ItemArtNames[j]);
        ipIdle: for j := 0 to ItemIdleCount - 1 do icb[i].Items.Add(ItemIdleNames[j]);
        ipLeave: for j := 0 to ItemLeaveCount - 1 do icb[i].Items.Add(ItemLeaveNames[j]);
      else
        for j := 0 to ItemTrailCount - 1 do icb[i].Items.Add(ItemTrailNames[j]);
      end;
      icb[i].Tag := i;
      icb[i].Hint := ItemParams[i].Hint;
      icb[i].ShowHint := True;
      icb[i].OnChange := @ItemChange;
      if i = ipColourMode then
        for j := 0 to 1 do
        begin
          icol[j] := TColorButton.Create(Self);
          icol[j].Parent := sbItems;
          icol[j].SetBounds(418 + j * 76, y, 72, 28);
          icol[j].Tag := 100 + j;
          icol[j].Hint := BoolToStr(j = 0, 'own colour (and gradient start)', 'gradient end');
          icol[j].ShowHint := True;
          icol[j].OnColorChanged := @ItemChange;
        end;
    end
    else
    begin
      itb[i] := TTrackBar.Create(Self);
      itb[i].Parent := sbItems;
      itb[i].SetBounds(190, y, 330, 28);
      itb[i].Max := 1000;
      itb[i].TickStyle := tsNone;
      itb[i].Tag := i;
      itb[i].Hint := ItemParams[i].Hint;
      itb[i].ShowHint := True;
      itb[i].OnChange := @ItemChange;
      ilv[i] := Lbl('', 528, y + 6);
    end;
    Inc(y, 32);
  end;
end;

procedure TFxForm.ItemChange(Sender: TObject);
var
  i: Integer;
begin
  if FUpdating then Exit;
  i := TComponent(Sender).Tag;
  if Sender is TComboBox then
    MenuFx.Item.V[i] := Math.Max(0, TComboBox(Sender).ItemIndex)
  else if Sender is TTrackBar then
  begin
    with ItemParams[i] do
    begin
      MenuFx.Item.V[i] := Min + (Max - Min) * TTrackBar(Sender).Position / 1000;
      if IsInt then MenuFx.Item.V[i] := Round(MenuFx.Item.V[i]);
    end;
    if ItemParams[i].IsInt then ilv[i].Caption := IntToStr(Round(MenuFx.Item.V[i]))
    else ilv[i].Caption := FormatFloat('0.00', MenuFx.Item.V[i]);
  end
  else if Sender is TColorButton then
  begin
    if i = 100 then MenuFx.Item.Colour := RGBToCard(TColorButton(Sender).ButtonColor)
    else MenuFx.Item.Colour2 := RGBToCard(TColorButton(Sender).ButtonColor);
  end;
  if cbScreen.ItemIndex in [5, 6, 7] then
  begin
    cbScreen.ItemIndex := 0;
    ScreenChange(nil);
  end;
  Changed;
end;

procedure TFxForm.MoveSelClick(Sender: TObject);
begin
  if cbScreen.ItemIndex in [5, 6, 7] then
  begin
    cbScreen.ItemIndex := 0;
    ScreenChange(nil);
  end;
  Inc(FSel);
  FSelT := Now_s;   // the automatic selection waits
end;

{ the preview shows the top bar while playing }
procedure TFxForm.ShowInGame;
begin
  if cbScreen.ItemIndex <> 7 then
  begin
    cbScreen.ItemIndex := 7;
    ScreenChange(nil);
  end;
end;

{ a change of one value of the simulated game (AKind = stLevel .. stBest) }
procedure TFxForm.SimStep(AKind: Integer);
begin
  case AKind of
    stLevel:
      FGame.Level := FGame.Level + 1;
    stBest:
      FGame.Score := Math.Max(FGame.Score, FGame.Best) + 50 * (2 + Random(8));
    stStatus:
      PopOne;
  else
    FGame.Score := FGame.Score + 10 * (3 + Random(30));
  end;
  { a long run starts again (a smaller value: no reaction, like a new game) }
  if FGame.Score > 60000 then
  begin
    FGame.Best := Math.Max(FGame.Best, FGame.Score);
    FGame.Score := 0;
    FGame.Level := 1;
  end;
end;

{ a move on the preview board: fewer beads (the Status text changes) }
procedure TFxForm.PopOne;
var
  x, y, i: Integer;
begin
  FGame.State := gsPlaying;
  for y := 0 to FGame.H - 1 do
    for x := 0 to FGame.W - 1 do
      if FGame.GroupSize(x, y) >= 2 then
      begin
        FGame.SetMouseCell(x, y);
        FGame.Click;
        FGame.SetMouseCell(-1, -1);
        { let the pop finish (the beads leave the board) }
        for i := 1 to 40 do FGame.Update(0.05);
        FGame.State := gsPlaying;
        SetLength(FGame.Popups, 0);   // the preview does not run the game: no popups piling up
        Exit;
      end;
  { no moves left: a new board (more beads, the status resets quietly) }
  FGame.StartLevel(FGame.Level, True);
end;

procedure TFxForm.StatTestClick(Sender: TObject);
begin
  ShowInGame;
  SimStep(TComponent(Sender).Tag);
  FSimT := Now_s;   // the next automatic change waits
end;

procedure TFxForm.GameChange(Sender: TObject);
begin
  if FDirty and (MessageDlg('Save changes?', 'Save the changed effects before switching?', mtConfirmation,
    [mbYes, mbNo], 0) = mrYes) then SaveClick(nil);
  LoadFile(GameFile(cbGame.ItemIndex));
  IntroClick(nil);
end;

procedure TFxForm.SaveClick(Sender: TObject);
begin
  try
    SaveMenuFxFile(FFile, MenuFx);
    FDirty := False;
    lblStatus.Caption := 'Saved ' + FFile + '  (a running game reloads it)';
  except
    on E: Exception do MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TFxForm.SaveBothClick(Sender: TObject);
begin
  try
    SaveMenuFxFile(GameFile(0), MenuFx);
    SaveMenuFxFile(GameFile(1), MenuFx);
    SaveMenuFxFile(GameFile(2), MenuFx);
    FDirty := False;
    lblStatus.Caption := 'Saved to Neon Beads and Neon Trail.';
  except
    on E: Exception do MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TFxForm.ReloadClick(Sender: TObject);
var
  old: TMenuFx;
  i, k, n: Integer;
begin
  { unsaved changes are discarded: ask first }
  if FDirty and (MessageDlg('Reload', 'Discard the changes that are not saved and load the file again?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;
  SaveTimer.Enabled := False;   // a pending live save must not write the old values back
  old := MenuFx;
  LoadFile(FFile);
  IntroClick(nil);              // the preview starts again with the loaded values
  if not FileExists(FFile) then Exit;
  n := 0;
  for i := 0 to FxParamCount - 1 do
    if Abs(old.V[i] - MenuFx.V[i]) > 1e-6 then Inc(n);
  if old.CustomPalette <> MenuFx.CustomPalette then Inc(n);
  for k := 0 to StatCount - 1 do
  begin
    for i := 0 to StatParamCount - 1 do
      if Abs(old.Stat[k].V[i] - MenuFx.Stat[k].V[i]) > 1e-6 then Inc(n);
    if old.Stat[k].Colour <> MenuFx.Stat[k].Colour then Inc(n);
    if old.Stat[k].Colour2 <> MenuFx.Stat[k].Colour2 then Inc(n);
  end;
  for i := 0 to ItemParamCount - 1 do
    if Abs(old.Item.V[i] - MenuFx.Item.V[i]) > 1e-6 then Inc(n);
  if old.Item.Colour <> MenuFx.Item.Colour then Inc(n);
  if old.Item.Colour2 <> MenuFx.Item.Colour2 then Inc(n);
  for k := 0 to FrameCount - 1 do
  begin
    for i := 0 to FrameParamCount - 1 do
      if Abs(old.Frame[k].V[i] - MenuFx.Frame[k].V[i]) > 1e-6 then Inc(n);
    if old.Frame[k].Colour <> MenuFx.Frame[k].Colour then Inc(n);
    if old.Frame[k].Colour2 <> MenuFx.Frame[k].Colour2 then Inc(n);
    if old.Frame[k].FillColour <> MenuFx.Frame[k].FillColour then Inc(n);
  end;
  for i := 0 to StatusXCount - 1 do
    if Abs(old.StatusX[i] - MenuFx.StatusX[i]) > 1e-6 then Inc(n);
  for i := 0 to 3 do
    if old.Palette[i] <> MenuFx.Palette[i] then Inc(n);
  { tell what happened: an unchanged file looks like a dead button otherwise }
  if n > 0 then
    lblStatus.Caption := Format('Reloaded %s at %s: %d %s changed.', [FFile, TimeToStr(Now), n,
      BoolToStr(n = 1, 'value', 'values')])
  else if chkLive.Checked then
    lblStatus.Caption := Format('Reloaded %s at %s: the file already has these values (live saves every change).',
      [FFile, TimeToStr(Now)])
  else
    lblStatus.Caption := Format('Reloaded %s at %s: no differences to the file.', [FFile, TimeToStr(Now)]);
end;

procedure TFxForm.DefaultsClick(Sender: TObject);
begin
  MenuFx := DefaultMenuFx;
  ShowValues;
  Changed;
end;

procedure TFxForm.LiveSave(Sender: TObject);
begin
  SaveTimer.Enabled := False;
  SaveClick(nil);
end;

procedure TFxForm.IntroClick(Sender: TObject);
begin
  { a new HUD replays the heading intro too }
  FHud.Free;
  FHud := TGameHud.Create;
  FHud.StartLevel := 3;
  FMenuTime := 0;
  FItemTime := 0;
end;

procedure TFxForm.ScreenChange(Sender: TObject);
begin
  FItemTime := 0;
  FSel := 0;
  if cbScreen.ItemIndex in [0, 4] then FMenuTime := 0;
  if cbScreen.ItemIndex = 7 then
  begin
    { a game in progress whose score passes the best after a while }
    FGame.Mode := gmClassic;
    FGame.StartLevel(3, False);
    FGame.Level := 3;
    FGame.Score := 1240;
    FGame.Best := 2500;
    FSimT := Now_s;
  end;
end;

{ ---- preview }

procedure TFxForm.Tick(Sender: TObject);
var
  t, dt: Double;
  L: TLayout;
  trail: Boolean;

  procedure Add(const C, V: string);
  var
    n: Integer;
  begin
    n := Length(FHud.Menu.Items);
    SetLength(FHud.Menu.Items, n + 1);
    FHud.Menu.Items[n].Caption := C;
    FHud.Menu.Items[n].Value := V;
  end;

begin
  t := Now_s;
  dt := Min(0.1, t - FLastT);
  FLastT := t;
  { NeonVisualEditor saved new colours: take them over }
  if t - FVisT > 0.5 then
  begin
    FVisT := t;
    if FileAge(VisualsFile) <> FVisAge then
    begin
      LoadVisualColours;
      lblStatus.Caption := 'Colours reloaded at ' + TimeToStr(Now) + '   (' + FColourInfo + ')';
    end;
  end;
  FMenuTime += dt;
  FItemTime += dt;
  if chkAutoSel.Checked and (t - FSelT > 1.6) then
  begin
    FSelT := t;
    Inc(FSel);
  end;
  L := Default(TLayout);
  L.W := PW;
  L.H := PH;
  L.TopH := Round(PH * 0.095);
  L.BottomH := Round(PH * 0.075);
  L.Cell := 30;
  L.BoardX0 := 30;
  L.BoardY0 := L.TopH + 30;
  SetLength(FHud.Menu.Items, 0);
  FHud.Menu.Active := True;
  { the preview shows the chosen game: its title, subtitle, menus and song }
  trail := cbGame.ItemIndex >= 1;   // Neon Shooter has the menus of Neon Trail
  if cbGame.ItemIndex = 2 then
  begin
    FHud.Menu.Title := 'NEON SHOOTER';
    FHud.Subtitle := 'aim, shoot, pop 3 or more of one colour - the rest drops';
    FHud.Menu.NowPlaying := 'Sunny Side';
  end
  else if trail then
  begin
    FHud.Menu.Title := 'NEON TRAIL';
    FHud.Subtitle := 'steer the light trail, eat the sparkles, never hit your tail';
    FHud.Menu.NowPlaying := 'Light Cycle';
  end
  else
  begin
    FHud.Menu.Title := 'NEON BEADS';
    FHud.Subtitle := '';
    FHud.Menu.NowPlaying := 'Sunny Side';
  end;
  FGame.State := gsTitle;
  case cbScreen.ItemIndex of
    1:
      begin
        FHud.Menu.Screen := 1;
        Add('MUSIC', 'SHUFFLE'); Add('MUSIC VOLUME', '60%'); Add('SOUND VOLUME', '80%');
        if not trail then Add('THEME', 'NEON  (1 / 5)');
        Add('FULLSCREEN', 'OFF'); Add('VSYNC', 'ON'); Add('BACK', '');
      end;
    2:
      begin
        FHud.Menu.Screen := 3;
        Add('BACK', '');
      end;
    3:
      begin
        FHud.Menu.Screen := 5;
        FHud.CodeText := 'K7QM2XR9';
        Add('START', ''); Add('BACK', '');
      end;
    4:
      begin
        FHud.Menu.Screen := 2;
        FHud.Menu.Title := 'PAUSED';
        FGame.State := gsPlaying;
        Add('RESUME', ''); Add('RESTART LEVEL', ''); Add('OPTIONS', ''); Add('MAIN MENU', ''); Add('EXIT', '');
      end;
    5, 6:
      begin
        FHud.Menu.Active := False;
        if cbScreen.ItemIndex = 5 then FGame.State := gsLevelDone else FGame.State := gsGameOver;
      end;
    7:
      begin
        { the top bar while playing: Level / Score / Best with their effects }
        FHud.Menu.Active := False;
        FGame.State := gsPlaying;
        if chkSim.Checked and (t - FSimT > 1.4) then
        begin
          FSimT := t;
          case Random(6) of
            0: SimStep(stLevel);
            1, 2: SimStep(stStatus);
          else
            SimStep(stScore);
          end;
        end;
      end;
  else
    begin
      FHud.Menu.Screen := 0;
      Add('PLAY', '');
      if not trail then Add('MODE', 'CLASSIC');
      Add('LEVEL', '3'); Add('HIGH SCORES', '');
      Add('ACHIEVEMENTS', ''); Add('OPTIONS', ''); Add('CHEAT CODE', ''); Add('EXIT', '');
    end;
  end;
  if Length(FHud.Menu.Items) > 0 then FHud.Menu.Sel := FSel mod Length(FHud.Menu.Items) else FHud.Menu.Sel := 0;
  FHud.Menu.Time := FMenuTime;
  FHud.Menu.ItemTime := FItemTime;
  FHud.Menu.Clock := t - FT0;
  FHud.StarTime := FItemTime;
  RenderBackground(t - FT0);
  if FTtfOk then FHud.Update(FGame, L);
  pbPreview.Invalidate;
end;

procedure TFxForm.PreviewPaint(Sender: TObject);
begin
  FFrame.PutImage(0, 0, FBack, dmSet);
  if (FHud.Bmp.Width = PW) and (FHud.Bmp.Height = PH) then
    FFrame.PutImage(0, 0, FHud.Bmp, dmDrawWithTransparency);
  FFrame.Draw(pbPreview.Canvas, 0, 0, True);
end;

procedure TFxForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if not FDirty then Exit;
  case MessageDlg('Save changes?', 'The effects changed. Save them before closing?', mtConfirmation,
    [mbYes, mbNo, mbCancel], 0) of
    mrYes: SaveClick(nil);
    mrCancel: CanClose := False;
  end;
end;

end.
