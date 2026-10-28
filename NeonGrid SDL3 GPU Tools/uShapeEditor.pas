unit uShapeEditor;

{ Neon Shape Editor - the geometry shapes of the dots and beads of Neon Beads
  and Neon Trail (NeonBeads.shapes / NeonTrail.shapes, see uShapes).

  Left: the shapes with their numbers (the numbers the .visuals use for
  Dot shape and Bead shape). Middle: the outline of the chosen shape -
  drag a point; click on an edge to add a point there; right-click a point
  to delete it; "mirror" moves the mirrored point too (symmetric shapes);
  "snap" keeps points on a 0.05 grid. Tools: a regular polygon / star
  generator, rotate, scale, flip, circle. Right: the shape in neon colours
  (still or spinning), and "use as background / bead shape" (writes the
  game's .visuals).
  Files: Open..., Save, Save As..., Save to both games, Reload; shapes: Add,
  Duplicate, Delete, Up / Down (numbers after a deleted / moved shape
  change: the .visuals keep their numbers).
  GPU preview: the game in its own window (--preview, real shaders) with the
  chosen shape as background and bead shape; every change reaches it at once
  (a temp copy of the shapes). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Spin, Dialogs,
  LCLType, Process, FileUtil, BGRABitmap, BGRABitmapTypes, uShapes;

type
  TShapeForm = class(TForm)
  private
    FFile: string;
    FDirty, FUpdating: Boolean;
    FCur: Integer;             // shape shown
    FDrag, FMirror: Integer;   // dragged point, its mirror partner (-1 none)
    FSelPt: Integer;
    FT0: Double;
    FPrev: TProcess;
    cbGame: TComboBox;
    lbShapes: TListBox;
    pbEdit, pbLook: TPaintBox;
    edName: TEdit;
    chkSmooth, chkMirror, chkSnap, chkSpin: TCheckBox;
    seSides: TSpinEdit;
    seInner, seRot: TFloatSpinEdit;
    lblInfo, lblStatus, lblFile: TLabel;
    Timer: TTimer;
    function Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer; AClick: TNotifyEvent): TButton;
    function Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
    procedure BuildUI;
    function GameFile(AIndex: Integer; const AExt: string): string;
    procedure LoadGame;
    procedure FillList;
    procedure ShowShape;
    procedure Changed;
    procedure SetFileName(const AFile: string);
    { editor geometry }
    function Scale: Single;
    function ToScreen(const P: TPointF): TPoint;
    function ToShape(X, Y: Integer): TPointF;
    function PointAt(X, Y: Integer): Integer;
    function EdgeAt(X, Y: Integer): Integer;
    procedure EditPaint(Sender: TObject);
    procedure LookPaint(Sender: TObject);
    procedure ListDraw(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure ListClick(Sender: TObject);
    procedure EditDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure EditMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure EditUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PropChange(Sender: TObject);
    procedure GameChange(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure SaveBothClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure DupClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure MakeClick(Sender: TObject);
    procedure RotLeftClick(Sender: TObject);
    procedure RotRightClick(Sender: TObject);
    procedure BiggerClick(Sender: TObject);
    procedure SmallerClick(Sender: TObject);
    procedure FlipHClick(Sender: TObject);
    procedure FlipVClick(Sender: TObject);
    procedure CircleClick(Sender: TObject);
    procedure UseBgClick(Sender: TObject);
    procedure UseBeadClick(Sender: TObject);
    procedure GpuClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Transform(AM00, AM01, AM10, AM11: Single);
    function PreviewRunning: Boolean;
    procedure WritePreview;
    procedure SetVisualsShape(const AFile: string; ABackground, ABead: Boolean);
    function AskSave: Boolean;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  ShapeForm: TShapeForm;

implementation

const
  Games: array[0..2] of string = ('..\NeonGrid SDL3 GPU Game\NeonBeads', '..\NeonGrid SDL3 GPU Trail\NeonTrail',
    '..\NeonGrid SDL3 GPU Shooter\NeonShooter');
  EditSize = 560;
  ViewRange = 1.5;     // the editor shows -1.5 .. 1.5 dot radii

function Clock: Double;
begin
  Result := GetTickCount64 / 1000;
end;

function TempName(const AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + AName;
end;

{ TShapeForm }

constructor TShapeForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner, 0);
  Caption := 'Neon Shape Editor';
  Width := 1360;
  Height := 820;
  Position := poScreenCenter;
  OnCloseQuery := @FormCloseQuery;
  FDrag := -1;
  FMirror := -1;
  FSelPt := -1;
  FT0 := Clock;
  BuildUI;
  cbGame.ItemIndex := 0;
  LoadGame;
  Timer.Enabled := True;
end;

destructor TShapeForm.Destroy;
begin
  Timer.Enabled := False;
  if PreviewRunning then FPrev.Terminate(0);
  FPrev.Free;
  inherited Destroy;
end;

function TShapeForm.Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AW, 26);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function TShapeForm.Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := AX;
  Result.Top := AY;
  Result.Caption := ACaption;
end;

procedure TShapeForm.BuildUI;
var
  pTop, pLeft, pMid, pTools, pRight, pList: TPanel;
begin
  pTop := TPanel.Create(Self);
  pTop.Parent := Self;
  pTop.Align := alTop;
  pTop.Height := 40;
  pTop.BevelOuter := bvNone;
  Lbl(pTop, 'Game', 8, 12);
  cbGame := TComboBox.Create(Self);
  cbGame.Parent := pTop;
  cbGame.SetBounds(48, 8, 110, 24);
  cbGame.Style := csDropDownList;
  cbGame.Items.Add('Neon Beads');
  cbGame.Items.Add('Neon Trail');
  cbGame.Items.Add('Neon Shooter');
  cbGame.OnChange := @GameChange;
  Btn(pTop, 'Open...', 166, 7, 66, @OpenClick);
  Btn(pTop, 'Save', 236, 7, 56, @SaveClick);
  Btn(pTop, 'Save As...', 296, 7, 78, @SaveAsClick);
  Btn(pTop, 'Save to all games', 378, 7, 130, @SaveBothClick);
  Btn(pTop, 'Reload', 512, 7, 60, @ReloadClick);
  Btn(pTop, 'GPU preview', 584, 7, 96, @GpuClick).Hint :=
    'the game in its own window with this shape as background and bead shape (follows every change)';
  lblFile := Lbl(pTop, '', 692, 12);
  lblFile.Font.Color := clGrayText;

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := Self;
  lblStatus.Align := alBottom;
  lblStatus.BorderSpacing.Around := 4;

  { the list of shapes }
  pLeft := TPanel.Create(Self);
  pLeft.Parent := Self;
  pLeft.Align := alLeft;
  pLeft.Width := 230;
  pLeft.BevelOuter := bvNone;
  pList := TPanel.Create(Self);
  pList.Parent := pLeft;
  pList.Align := alBottom;
  pList.Height := 66;
  pList.BevelOuter := bvNone;
  Btn(pList, 'Add', 6, 4, 52, @AddClick);
  Btn(pList, 'Duplicate', 60, 4, 74, @DupClick);
  Btn(pList, 'Delete', 136, 4, 60, @DeleteClick);
  Btn(pList, 'Up', 6, 34, 52, @UpClick);
  Btn(pList, 'Down', 60, 34, 52, @DownClick);
  lbShapes := TListBox.Create(Self);
  lbShapes.Parent := pLeft;
  lbShapes.Align := alClient;
  lbShapes.BorderSpacing.Around := 4;
  lbShapes.Style := lbOwnerDrawFixed;
  lbShapes.ItemHeight := 48;
  lbShapes.OnDrawItem := @ListDraw;
  lbShapes.OnClick := @ListClick;

  { the neon look on the right }
  pRight := TPanel.Create(Self);
  pRight.Parent := Self;
  pRight.Align := alRight;
  pRight.Width := 330;
  pRight.BevelOuter := bvNone;
  pbLook := TPaintBox.Create(Self);
  pbLook.Parent := pRight;
  pbLook.SetBounds(6, 4, 318, 470);
  pbLook.OnPaint := @LookPaint;
  chkSpin := TCheckBox.Create(Self);
  chkSpin.Parent := pRight;
  chkSpin.SetBounds(10, 482, 200, 22);
  chkSpin.Caption := 'spin the preview';
  chkSpin.Checked := True;
  Btn(pRight, 'Use as background shape', 10, 514, 180, @UseBgClick).Hint :=
    'Dot shape of the game''s .visuals = this shape';
  Btn(pRight, 'Use as bead shape', 10, 546, 180, @UseBeadClick).Hint :=
    'Bead shape (game play) of the game''s .visuals = this shape (own shape on)';
  lblInfo := Lbl(pRight, '', 10, 584);
  lblInfo.Font.Color := clGrayText;

  { the outline editor in the middle }
  pMid := TPanel.Create(Self);
  pMid.Parent := Self;
  pMid.Align := alClient;
  pMid.BevelOuter := bvNone;
  pTools := TPanel.Create(Self);
  pTools.Parent := pMid;
  pTools.Align := alTop;
  pTools.Height := 104;
  pTools.BevelOuter := bvNone;
  Lbl(pTools, 'Name', 8, 10);
  edName := TEdit.Create(Self);
  edName.Parent := pTools;
  edName.SetBounds(50, 6, 170, 24);
  edName.OnChange := @PropChange;
  chkSmooth := TCheckBox.Create(Self);
  chkSmooth.Parent := pTools;
  chkSmooth.SetBounds(232, 8, 80, 22);
  chkSmooth.Caption := 'smooth';
  chkSmooth.OnClick := @PropChange;
  chkMirror := TCheckBox.Create(Self);
  chkMirror.Parent := pTools;
  chkMirror.SetBounds(316, 8, 80, 22);
  chkMirror.Caption := 'mirror';
  chkMirror.Hint := 'moving a point moves its mirror image (left / right) too';
  chkMirror.ShowHint := True;
  chkMirror.Checked := True;
  chkSnap := TCheckBox.Create(Self);
  chkSnap.Parent := pTools;
  chkSnap.SetBounds(400, 8, 70, 22);
  chkSnap.Caption := 'snap';
  Lbl(pTools, 'Make: corners', 8, 44);
  seSides := TSpinEdit.Create(Self);
  seSides.Parent := pTools;
  seSides.SetBounds(98, 40, 50, 24);
  seSides.MinValue := 3;
  seSides.MaxValue := 24;
  seSides.Value := 5;
  Lbl(pTools, 'inner', 156, 44);
  seInner := TFloatSpinEdit.Create(Self);
  seInner.Parent := pTools;
  seInner.SetBounds(190, 40, 60, 24);
  seInner.MinValue := 0.1;
  seInner.MaxValue := 1;
  seInner.Increment := 0.05;
  seInner.Value := 1;
  seInner.Hint := '1 = a polygon, less = a star with this inner radius';
  seInner.ShowHint := True;
  Lbl(pTools, 'turn', 258, 44);
  seRot := TFloatSpinEdit.Create(Self);
  seRot.Parent := pTools;
  seRot.SetBounds(290, 40, 60, 24);
  seRot.MinValue := -180;
  seRot.MaxValue := 180;
  seRot.DecimalPlaces := 0;
  seRot.Increment := 15;
  seRot.Value := -90;
  Btn(pTools, 'Make', 358, 39, 56, @MakeClick).Hint := 'replace the outline by this polygon / star';
  Btn(pTools, 'Circle', 418, 39, 56, @CircleClick).Hint := 'an exact circle (no points)';
  Btn(pTools, 'Turn -15', 8, 72, 70, @RotLeftClick);
  Btn(pTools, 'Turn +15', 80, 72, 70, @RotRightClick);
  Btn(pTools, 'Bigger', 156, 72, 60, @BiggerClick);
  Btn(pTools, 'Smaller', 218, 72, 60, @SmallerClick);
  Btn(pTools, 'Flip H', 284, 72, 56, @FlipHClick);
  Btn(pTools, 'Flip V', 342, 72, 56, @FlipVClick);
  pbEdit := TPaintBox.Create(Self);
  pbEdit.Parent := pMid;
  pbEdit.SetBounds(8, 108, EditSize, EditSize);
  pbEdit.OnPaint := @EditPaint;
  pbEdit.OnMouseDown := @EditDown;
  pbEdit.OnMouseMove := @EditMove;
  pbEdit.OnMouseUp := @EditUp;

  Timer := TTimer.Create(Self);
  Timer.Interval := 40;
  Timer.Enabled := False;
  Timer.OnTimer := @Tick;
  pTop.Top := 0;
  lblStatus.Top := 6000;
end;

function TShapeForm.GameFile(AIndex: Integer; const AExt: string): string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + Games[AIndex] + AExt);
end;

procedure TShapeForm.SetFileName(const AFile: string);
begin
  FFile := AFile;
  lblFile.Caption := AFile;
  Caption := 'Neon Shape Editor - ' + ExtractFileName(AFile);
end;

procedure TShapeForm.LoadGame;
begin
  SetFileName(GameFile(cbGame.ItemIndex, '.shapes'));
  if LoadShapesFile(FFile) then lblStatus.Caption := Format('Loaded %d shapes from %s', [ShapeCount, FFile])
  else
  begin
    DefaultShapes;
    lblStatus.Caption := 'No shapes file yet: the default shapes. Save writes ' + FFile;
  end;
  FDirty := False;
  FCur := 0;
  FillList;
  ShowShape;
end;

procedure TShapeForm.FillList;
var
  i: Integer;
begin
  lbShapes.Items.BeginUpdate;
  try
    lbShapes.Items.Clear;
    for i := 0 to ShapeCount - 1 do lbShapes.Items.Add(Shapes[i].Name);
  finally
    lbShapes.Items.EndUpdate;
  end;
  FCur := EnsureRange(FCur, 0, ShapeCount - 1);
  lbShapes.ItemIndex := FCur;
end;

procedure TShapeForm.ShowShape;
begin
  FUpdating := True;
  try
    edName.Text := Shapes[FCur].Name;
    chkSmooth.Checked := Shapes[FCur].Smooth;
  finally
    FUpdating := False;
  end;
  FSelPt := -1;
  if ShapeIsCircle(FCur) then
    lblInfo.Caption := Format('shape %d: a circle', [FCur])
  else
    lblInfo.Caption := Format('shape %d: %d points', [FCur, Length(Shapes[FCur].Pts)]);
  if PreviewRunning then WritePreview;
  pbEdit.Invalidate;
  pbLook.Invalidate;
end;

procedure TShapeForm.Changed;
begin
  FDirty := True;
  Inc(ShapesStamp);
  lblStatus.Caption := 'Changed (not saved yet)';
  if ShapeIsCircle(FCur) then
    lblInfo.Caption := Format('shape %d: a circle', [FCur])
  else
    lblInfo.Caption := Format('shape %d: %d points', [FCur, Length(Shapes[FCur].Pts)]);
  if PreviewRunning then WritePreview;
  lbShapes.Invalidate;
  pbEdit.Invalidate;
  pbLook.Invalidate;
end;

{ ---- editor geometry }

function TShapeForm.Scale: Single;
begin
  Result := EditSize / (2 * ViewRange);
end;

function TShapeForm.ToScreen(const P: TPointF): TPoint;
begin
  Result := Point(Round(EditSize / 2 + P.x * Scale), Round(EditSize / 2 + P.y * Scale));
end;

function TShapeForm.ToShape(X, Y: Integer): TPointF;
var
  p: TPointF;
  d: Single;
begin
  p := PointF((X - EditSize / 2) / Scale, (Y - EditSize / 2) / Scale);
  if chkSnap.Checked then p := PointF(Round(p.x * 20) / 20, Round(p.y * 20) / 20);
  { stay where the sprite has room }
  d := Sqrt(p.x * p.x + p.y * p.y);
  if d > ShapeReach then p := PointF(p.x / d * ShapeReach, p.y / d * ShapeReach);
  Result := p;
end;

function TShapeForm.PointAt(X, Y: Integer): Integer;
var
  i: Integer;
  q: TPoint;
begin
  for i := High(Shapes[FCur].Pts) downto 0 do
  begin
    q := ToScreen(Shapes[FCur].Pts[i]);
    if Sqr(q.X - X) + Sqr(q.Y - Y) <= 49 then Exit(i);
  end;
  Result := -1;
end;

{ the edge (i -> i + 1) under the mouse, -1 none }
function TShapeForm.EdgeAt(X, Y: Integer): Integer;
var
  i, n: Integer;
  a, b: TPoint;
  t, d, lx, ly: Single;
begin
  n := Length(Shapes[FCur].Pts);
  for i := 0 to n - 1 do
  begin
    a := ToScreen(Shapes[FCur].Pts[i]);
    b := ToScreen(Shapes[FCur].Pts[(i + 1) mod n]);
    lx := b.X - a.X;
    ly := b.Y - a.Y;
    if lx * lx + ly * ly < 1 then Continue;
    t := EnsureRange(((X - a.X) * lx + (Y - a.Y) * ly) / (lx * lx + ly * ly), 0, 1);
    d := Sqrt(Sqr(a.X + t * lx - X) + Sqr(a.Y + t * ly - Y));
    if d <= 7 then Exit(i);
  end;
  Result := -1;
end;

procedure TShapeForm.EditPaint(Sender: TObject);
var
  bmp: TBGRABitmap;
  i, n: Integer;
  c, q: TPoint;
  outl: ArrayOfTPointF;
  v: Single;
begin
  bmp := TBGRABitmap.Create(EditSize, EditSize, BGRA(16, 18, 28));
  bmp.FontHeight := 14;
  try
    c := Point(EditSize div 2, EditSize div 2);
    { grid every 0.25 radius }
    for i := -6 to 6 do
    begin
      v := EditSize / 2 + i * 0.25 * Scale;
      if i = 0 then
      begin
        bmp.DrawLineAntialias(v, 0, v, EditSize, BGRA(70, 75, 95), 1);
        bmp.DrawLineAntialias(0, v, EditSize, v, BGRA(70, 75, 95), 1);
      end
      else
      begin
        bmp.DrawLineAntialias(v, 0, v, EditSize, BGRA(32, 35, 50), 1);
        bmp.DrawLineAntialias(0, v, EditSize, v, BGRA(32, 35, 50), 1);
      end;
    end;
    { the dot radius (1) and the room of the sprite (ShapeReach) }
    bmp.EllipseAntialias(c.X, c.Y, Scale, Scale, BGRA(90, 160, 200, 160), 1);
    bmp.EllipseAntialias(c.X, c.Y, ShapeReach * Scale, ShapeReach * Scale, BGRA(220, 80, 90, 160), 1);
    { the outline as the games draw it }
    outl := ShapeOutline(FCur, c.X, c.Y, Scale);
    bmp.FillPolyAntialias(outl, BGRA(40, 200, 235, 60));
    bmp.DrawPolygonAntialias(outl, BGRA(60, 220, 245), 2);
    { the points: the first one larger, the selected one white }
    n := Length(Shapes[FCur].Pts);
    if (n >= 3) and Shapes[FCur].Smooth then
      for i := 0 to n - 1 do
      begin
        q := ToScreen(Shapes[FCur].Pts[i]);
        bmp.DrawLineAntialias(q.X, q.Y, ToScreen(Shapes[FCur].Pts[(i + 1) mod n]).X,
          ToScreen(Shapes[FCur].Pts[(i + 1) mod n]).Y, BGRA(120, 125, 150, 120), 1);
      end;
    for i := 0 to n - 1 do
    begin
      q := ToScreen(Shapes[FCur].Pts[i]);
      if i = FSelPt then
        bmp.FillRectAntialias(q.X - 5, q.Y - 5, q.X + 5, q.Y + 5, BGRAWhite)
      else if i = 0 then
        bmp.FillRectAntialias(q.X - 5, q.Y - 5, q.X + 5, q.Y + 5, BGRA(255, 200, 60))
      else
        bmp.FillRectAntialias(q.X - 4, q.Y - 4, q.X + 4, q.Y + 4, BGRA(240, 120, 200));
    end;
    if n < 3 then
      bmp.TextOut(10, 10, 'a circle - "Make" or "Add" gives it points', BGRA(200, 200, 210));
    bmp.TextOut(10, EditSize - 22, 'drag a point - click an edge to add one - right-click a point to delete it',
      BGRA(140, 145, 165));
    bmp.Draw(pbEdit.Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

{ the shape as a neon dot: fill, glow and ring, in a few colours and sizes }
procedure TShapeForm.LookPaint(Sender: TObject);
const
  Cols: array[0..3] of TBGRAPixel = ((blue: 240; green: 215; red: 35; alpha: 255),
    (blue: 145; green: 40; red: 230; alpha: 255), (blue: 35; green: 150; red: 245; alpha: 255),
    (blue: 240; green: 75; red: 150; alpha: 255));
var
  bmp, glow: TBGRABitmap;
  w, h, i, k: Integer;
  a, cx, cy, ca, sa: Single;

  procedure Dot(X, Y, R: Single; const C: TBGRAPixel);
  var
    j: Integer;
    p: ArrayOfTPointF;
  begin
    p := ShapeOutline(FCur, 0, 0, R);
    for j := 0 to High(p) do
      p[j] := PointF(X + p[j].x * ca - p[j].y * sa, Y + p[j].x * sa + p[j].y * ca);
    glow.DrawPolygonAntialias(p, C, Max(2, R * 0.22));
    bmp.FillPolyAntialias(p, BGRA(C.red, C.green, C.blue, 70));
    bmp.DrawPolygonAntialias(p, BGRA(Min(255, C.red + 70), Min(255, C.green + 70), Min(255, C.blue + 70)),
      Max(1.5, R * 0.09));
  end;

begin
  w := pbLook.Width;
  h := pbLook.Height;
  bmp := TBGRABitmap.Create(w, h, BGRA(6, 8, 16));
  glow := TBGRABitmap.Create(w, h, BGRABlack);
  bmp.FontHeight := 15;
  try
    if chkSpin.Checked then a := (Clock - FT0) * 1.2 else a := 0;
    ca := Cos(a);
    sa := Sin(a);
    { a big one and a grid of small ones like the game board }
    Dot(w / 2, 120, 80, Cols[0]);
    k := 0;
    for i := 0 to 11 do
    begin
      cx := 36 + (i mod 4) * 82;
      cy := 260 + (i div 4) * 72;
      Dot(cx, cy, 26, Cols[k mod 4]);
      Inc(k);
    end;
    BGRAReplace(glow, glow.FilterBlurRadial(10, rbFast));
    bmp.BlendImage(0, 0, glow, boAdditive);
    bmp.TextOut(8, h - 22, Shapes[FCur].Name, BGRA(200, 205, 220));
    bmp.Draw(pbLook.Canvas, 0, 0, True);
  finally
    glow.Free;
    bmp.Free;
  end;
end;

procedure TShapeForm.ListDraw(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
var
  c: TCanvas;
  bmp: TBGRABitmap;
  outl: ArrayOfTPointF;
begin
  c := lbShapes.Canvas;
  if odSelected in State then c.Brush.Color := RGBToColor(40, 70, 110) else c.Brush.Color := RGBToColor(22, 24, 34);
  c.FillRect(ARect);
  bmp := TBGRABitmap.Create(44, 44, BGRAPixelTransparent);
  try
    outl := ShapeOutline(Index, 22, 22, 15);
    bmp.FillPolyAntialias(outl, BGRA(40, 200, 235, 90));
    bmp.DrawPolygonAntialias(outl, BGRA(70, 225, 250), 1.5);
    bmp.Draw(c, ARect.Left + 4, ARect.Top + 2, False);
  finally
    bmp.Free;
  end;
  c.Font.Color := RGBToColor(225, 230, 240);
  c.Brush.Style := bsClear;
  c.TextOut(ARect.Left + 54, ARect.Top + 15, Format('%d   %s', [Index, Shapes[Index].Name]));
  c.Brush.Style := bsSolid;
end;

procedure TShapeForm.ListClick(Sender: TObject);
begin
  if lbShapes.ItemIndex < 0 then Exit;
  FCur := lbShapes.ItemIndex;
  ShowShape;
end;

{ ---- editing the outline }

procedure TShapeForm.EditDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i, k, e, n: Integer;
  p: TPointF;
  best, d: Single;
begin
  i := PointAt(X, Y);
  if Button = mbRight then
  begin
    if (i >= 0) and (Length(Shapes[FCur].Pts) > 3) then
    begin
      for k := i to High(Shapes[FCur].Pts) - 1 do Shapes[FCur].Pts[k] := Shapes[FCur].Pts[k + 1];
      SetLength(Shapes[FCur].Pts, Length(Shapes[FCur].Pts) - 1);
      FSelPt := -1;
      Changed;
    end;
    Exit;
  end;
  if i < 0 then
  begin
    { a click on an edge adds a point there }
    e := EdgeAt(X, Y);
    if e < 0 then Exit;
    n := Length(Shapes[FCur].Pts);
    SetLength(Shapes[FCur].Pts, n + 1);
    for k := n downto e + 2 do Shapes[FCur].Pts[k] := Shapes[FCur].Pts[k - 1];
    Shapes[FCur].Pts[e + 1] := ToShape(X, Y);
    i := e + 1;
    Changed;
  end;
  FDrag := i;
  FSelPt := i;
  { the mirror partner: the point nearest to (-x, y) }
  FMirror := -1;
  if chkMirror.Checked then
  begin
    p := Shapes[FCur].Pts[i];
    best := 0.08;
    for k := 0 to High(Shapes[FCur].Pts) do
    begin
      if k = i then Continue;
      d := Sqrt(Sqr(Shapes[FCur].Pts[k].x + p.x) + Sqr(Shapes[FCur].Pts[k].y - p.y));
      if d < best then
      begin
        best := d;
        FMirror := k;
      end;
    end;
  end;
  pbEdit.Invalidate;
end;

procedure TShapeForm.EditMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  p: TPointF;
begin
  if FDrag < 0 then Exit;
  p := ToShape(X, Y);
  Shapes[FCur].Pts[FDrag] := p;
  if FMirror >= 0 then Shapes[FCur].Pts[FMirror] := PointF(-p.x, p.y);
  Changed;
end;

procedure TShapeForm.EditUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDrag := -1;
  FMirror := -1;
end;

procedure TShapeForm.PropChange(Sender: TObject);
begin
  if FUpdating then Exit;
  Shapes[FCur].Name := edName.Text;
  Shapes[FCur].Smooth := chkSmooth.Checked;
  Changed;
end;

procedure TShapeForm.Transform(AM00, AM01, AM10, AM11: Single);
var
  i: Integer;
  p: TPointF;
  d: Single;
begin
  for i := 0 to High(Shapes[FCur].Pts) do
  begin
    p := Shapes[FCur].Pts[i];
    p := PointF(AM00 * p.x + AM01 * p.y, AM10 * p.x + AM11 * p.y);
    d := Sqrt(p.x * p.x + p.y * p.y);
    if d > ShapeReach then p := PointF(p.x / d * ShapeReach, p.y / d * ShapeReach);
    Shapes[FCur].Pts[i] := p;
  end;
  Changed;
end;

procedure TShapeForm.RotLeftClick(Sender: TObject);
begin
  Transform(Cos(-Pi / 12), -Sin(-Pi / 12), Sin(-Pi / 12), Cos(-Pi / 12));
end;

procedure TShapeForm.RotRightClick(Sender: TObject);
begin
  Transform(Cos(Pi / 12), -Sin(Pi / 12), Sin(Pi / 12), Cos(Pi / 12));
end;

procedure TShapeForm.BiggerClick(Sender: TObject);
begin
  Transform(1.1, 0, 0, 1.1);
end;

procedure TShapeForm.SmallerClick(Sender: TObject);
begin
  Transform(1 / 1.1, 0, 0, 1 / 1.1);
end;

procedure TShapeForm.FlipHClick(Sender: TObject);
begin
  Transform(-1, 0, 0, 1);
end;

procedure TShapeForm.FlipVClick(Sender: TObject);
begin
  Transform(1, 0, 0, -1);
end;

procedure TShapeForm.CircleClick(Sender: TObject);
begin
  SetLength(Shapes[FCur].Pts, 0);
  Changed;
end;

procedure TShapeForm.MakeClick(Sender: TObject);
var
  n, i, m: Integer;
  a, r, rot: Single;
begin
  n := seSides.Value;
  rot := seRot.Value * Pi / 180;
  if seInner.Value < 0.999 then m := 2 * n else m := n;
  SetLength(Shapes[FCur].Pts, m);
  for i := 0 to m - 1 do
  begin
    a := rot + i / m * 2 * Pi;
    { about the area of the dot: polygons a bit bigger than 1, stars reach out }
    if (m = 2 * n) and (i mod 2 = 1) then r := 1.25 * seInner.Value
    else if m = 2 * n then r := 1.25
    else r := 1 / Sqrt(n * Sin(2 * Pi / n) / (2 * Pi));
    r := Min(r, ShapeReach);
    Shapes[FCur].Pts[i] := PointF(Cos(a) * r, Sin(a) * r);
  end;
  Shapes[FCur].Smooth := False;
  ShowShape;
  Changed;
end;

{ ---- the list }

procedure TShapeForm.AddClick(Sender: TObject);
var
  n: Integer;
begin
  n := ShapeCount;
  if n >= MaxShapes then Exit;
  SetLength(Shapes, n + 1);
  Shapes[n].Name := 'Shape ' + IntToStr(n);
  Shapes[n].Smooth := False;
  SetLength(Shapes[n].Pts, 0);
  FCur := n;
  FillList;
  { a pentagon to start from }
  seSides.Value := 5;
  seInner.Value := 1;
  seRot.Value := -90;
  MakeClick(nil);
  lblStatus.Caption := Format('Added shape %d - edit it, then Save', [n]);
end;

procedure TShapeForm.DupClick(Sender: TObject);
var
  n: Integer;
begin
  n := ShapeCount;
  if n >= MaxShapes then Exit;
  SetLength(Shapes, n + 1);
  Shapes[n].Name := Shapes[FCur].Name + ' 2';
  Shapes[n].Smooth := Shapes[FCur].Smooth;
  Shapes[n].Pts := Copy(Shapes[FCur].Pts);
  FCur := n;
  FillList;
  ShowShape;
  Changed;
end;

procedure TShapeForm.DeleteClick(Sender: TObject);
var
  i: Integer;
begin
  if ShapeCount <= 1 then Exit;
  if MessageDlg('Delete', Format('Delete shape %d "%s"? The shapes after it move up one number ' +
    '(a .visuals that uses them then shows the next shape).', [FCur, Shapes[FCur].Name]), mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then Exit;
  for i := FCur to ShapeCount - 2 do Shapes[i] := Shapes[i + 1];
  SetLength(Shapes, ShapeCount - 1);
  FillList;
  ShowShape;
  Changed;
end;

procedure TShapeForm.UpClick(Sender: TObject);
var
  t: TShapeDef;
begin
  if FCur <= 0 then Exit;
  t := Shapes[FCur - 1];
  Shapes[FCur - 1] := Shapes[FCur];
  Shapes[FCur] := t;
  Dec(FCur);
  FillList;
  ShowShape;
  Changed;
end;

procedure TShapeForm.DownClick(Sender: TObject);
var
  t: TShapeDef;
begin
  if FCur >= ShapeCount - 1 then Exit;
  t := Shapes[FCur + 1];
  Shapes[FCur + 1] := Shapes[FCur];
  Shapes[FCur] := t;
  Inc(FCur);
  FillList;
  ShowShape;
  Changed;
end;

{ ---- files }

function TShapeForm.AskSave: Boolean;
begin
  Result := True;
  if not FDirty then Exit;
  case MessageDlg('Save changes?', 'The shapes changed. Save them first?', mtConfirmation,
    [mbYes, mbNo, mbCancel], 0) of
    mrYes: SaveClick(nil);
    mrCancel: Result := False;
  end;
end;

procedure TShapeForm.GameChange(Sender: TObject);
begin
  if not AskSave then Exit;
  LoadGame;
end;

procedure TShapeForm.OpenClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  if not AskSave then Exit;
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := 'Neon shapes (*.shapes)|*.shapes|All files|*.*';
    dlg.InitialDir := ExtractFilePath(FFile);
    if dlg.Execute then
    begin
      if LoadShapesFile(dlg.FileName) then
      begin
        SetFileName(dlg.FileName);
        FDirty := False;
        FCur := 0;
        FillList;
        ShowShape;
        lblStatus.Caption := Format('Opened %d shapes from %s', [ShapeCount, dlg.FileName]);
      end
      else
        MessageDlg('Open', 'No shapes in ' + dlg.FileName, mtError, [mbOK], 0);
    end;
  finally
    dlg.Free;
  end;
end;

procedure TShapeForm.SaveClick(Sender: TObject);
begin
  try
    SaveShapesFile(FFile);
    FDirty := False;
    lblStatus.Caption := 'Saved ' + FFile + '  (a running game takes it within half a second)';
  except
    on E: Exception do MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TShapeForm.SaveAsClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := 'Neon shapes (*.shapes)|*.shapes|All files|*.*';
    dlg.DefaultExt := 'shapes';
    dlg.InitialDir := ExtractFilePath(FFile);
    dlg.FileName := ExtractFileName(FFile);
    dlg.Options := dlg.Options + [ofOverwritePrompt];
    if dlg.Execute then
    begin
      SetFileName(dlg.FileName);
      SaveClick(nil);
    end;
  finally
    dlg.Free;
  end;
end;

procedure TShapeForm.SaveBothClick(Sender: TObject);
begin
  try
    SaveShapesFile(GameFile(0, '.shapes'));
    SaveShapesFile(GameFile(1, '.shapes'));
    SaveShapesFile(GameFile(2, '.shapes'));
    FDirty := False;
    lblStatus.Caption := 'Saved to Neon Beads, Neon Trail and Neon Shooter.';
  except
    on E: Exception do MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TShapeForm.ReloadClick(Sender: TObject);
begin
  if FDirty and (MessageDlg('Reload', 'Discard the changes that are not saved?', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes) then Exit;
  if LoadShapesFile(FFile) then lblStatus.Caption := 'Reloaded ' + FFile + ' at ' + TimeToStr(Now)
  else
  begin
    DefaultShapes;
    lblStatus.Caption := 'No file ' + FFile + ': the default shapes.';
  end;
  FDirty := False;
  FillList;
  ShowShape;
end;

{ ---- the game's .visuals: Dot shape / Bead shape }

{ sets "Key=Value" inside [Section] of a .visuals text (the lines stay) }
function SetIniLine(SL: TStringList; const ASection, AKey, AValue: string): Boolean;
var
  i: Integer;
  inSec: Boolean;
  t: string;
begin
  Result := False;
  inSec := False;
  for i := 0 to SL.Count - 1 do
  begin
    t := Trim(SL[i]);
    if (t <> '') and (t[1] = '[') then
    begin
      inSec := SameText(t, '[' + ASection + ']');
      Continue;
    end;
    if inSec and SameText(Copy(t, 1, Length(AKey) + 1), AKey + '=') then
    begin
      SL[i] := AKey + '=' + AValue;
      Exit(True);
    end;
  end;
end;

procedure TShapeForm.SetVisualsShape(const AFile: string; ABackground, ABead: Boolean);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    if FileExists(AFile) then sl.LoadFromFile(AFile);
    if ABackground then SetIniLine(sl, 'Dot shape', 'Shape', IntToStr(FCur));
    if ABead then
    begin
      SetIniLine(sl, 'Bead shape (game play)', 'Own shape', '1');
      SetIniLine(sl, 'Bead shape (game play)', 'Shape', IntToStr(FCur));
    end;
    sl.SaveToFile(AFile);
  finally
    sl.Free;
  end;
end;

procedure TShapeForm.UseBgClick(Sender: TObject);
var
  f: string;
begin
  f := GameFile(cbGame.ItemIndex, '.visuals');
  if not FileExists(f) then
  begin
    MessageDlg('Use', 'No ' + f + ' yet - run the game once.', mtError, [mbOK], 0);
    Exit;
  end;
  if FDirty then SaveClick(nil);
  SetVisualsShape(f, True, False);
  lblStatus.Caption := Format('%s: the background dots are shape %d now (a running game takes it)',
    [ExtractFileName(f), FCur]);
end;

procedure TShapeForm.UseBeadClick(Sender: TObject);
var
  f: string;
begin
  f := GameFile(cbGame.ItemIndex, '.visuals');
  if not FileExists(f) then
  begin
    MessageDlg('Use', 'No ' + f + ' yet - run the game once.', mtError, [mbOK], 0);
    Exit;
  end;
  if FDirty then SaveClick(nil);
  SetVisualsShape(f, False, True);
  lblStatus.Caption := Format('%s: the game beads are shape %d now (a running game takes it)',
    [ExtractFileName(f), FCur]);
end;

{ ---- GPU preview: the game with --preview (a copy of its visuals with this
  shape) and --shapes (a copy of the shapes as they are now) }

function TShapeForm.PreviewRunning: Boolean;
begin
  Result := (FPrev <> nil) and FPrev.Running;
end;

procedure TShapeForm.WritePreview;
var
  vis: string;
begin
  try
    SaveShapesFile(TempName('NeonShapes-preview.shapes'));
    vis := TempName('NeonShapes-preview.visuals');
    if FileExists(GameFile(cbGame.ItemIndex, '.visuals')) then
    begin
      CopyFile(GameFile(cbGame.ItemIndex, '.visuals'), vis);
      SetVisualsShape(vis, True, True);
    end;
  except
    { the game is reading: the next change writes again }
  end;
end;

procedure TShapeForm.GpuClick(Sender: TObject);
var
  exe: string;
begin
  if PreviewRunning then
  begin
    WritePreview;
    lblStatus.Caption := 'The GPU preview is open already (it follows every change).';
    Exit;
  end;
  exe := GameFile(cbGame.ItemIndex, '.exe');
  if not FileExists(exe) then
  begin
    MessageDlg('GPU preview', 'Not found: ' + exe, mtError, [mbOK], 0);
    Exit;
  end;
  WritePreview;
  FreeAndNil(FPrev);
  FPrev := TProcess.Create(nil);
  FPrev.Executable := exe;
  FPrev.Parameters.Add('--preview=' + TempName('NeonShapes-preview.visuals'));
  FPrev.Parameters.Add('--shapes=' + TempName('NeonShapes-preview.shapes'));
  FPrev.CurrentDirectory := ExtractFilePath(exe);
  try
    FPrev.Execute;
    lblStatus.Caption := 'GPU preview: the chosen shape as background and bead shape; every change shows at once. ' +
      'Keys there: 1 game, 3 background, Esc close.';
  except
    on E: Exception do
    begin
      FreeAndNil(FPrev);
      MessageDlg('GPU preview', E.Message, mtError, [mbOK], 0);
    end;
  end;
end;

procedure TShapeForm.Tick(Sender: TObject);
begin
  if chkSpin.Checked then pbLook.Invalidate;
end;

procedure TShapeForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := AskSave;
end;

end.
