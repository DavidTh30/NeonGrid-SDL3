unit uIronFlowEditor;

{ Neon Iron Flow - the VS BOT iron rules of Neon Beads as a flowchart
  (NeonBeads.ironflow, see uIronFlow).

  Canvas: Start (green), Condition (yellow diamond: Yes below, No right),
  Action (blue / orange / violet / grey / red), End (red). Drag a node to
  move it; drag from a port (the small circle) to a node to connect it;
  right-click a port to cut its arrow; Del deletes the selected node. The
  panel on the right edits the selected node.
  Toolbar: New (the built-in rules as a flow), Open..., Save, Save As...,
  "use this flow in the game", add Start / Condition / Action / End,
  Delete, Check.
  Simulate:
    GPU window  Neon Beads plays VS BOT bot against bot in its own window
                (--vssim, the real game and shaders) with this flow; every
                change here reaches it at once (a temp copy of the flow);
                the nodes that fire light up (cyan = left, pink = right) and
                are listed in the log; keys there: 1-4 speed, R new match.
    Quick test  N matches without a window (uBeadSim): wins, scores, iron,
                and how often every node fired (the badges). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Spin, Dialogs,
  LCLType, LCLIntf, Process, StrUtils, uIronFlow, uBeadRules, uBeadGame, uBeadSim;

type
  TFlowForm = class(TForm)
  private
    FFile, FSimFile: string;
    FDirty, FUpdating: Boolean;
    FSel: Integer;              // selected node id (0 none)
    FDragNode: Integer;
    FDragDX, FDragDY: Single;
    FLinkFrom, FLinkPort: Integer;   // link drag: node id, 0 next/yes, 1 no
    FMouse: TPoint;
    FFlash: array of Double;    // by node id: clock of the last fire
    FFlashSide: array of Integer;
    FCount: array of Integer;   // by node id: quick test fires
    FTracePos: Int64;
    FMatch: Integer;
    FSim: TProcess;
    sb: TScrollBox;
    pb: TPaintBox;
    lblFile, lblStatus, lblCap: TLabel;
    chkEnabled: TCheckBox;
    cbLeftBot, cbRightBot: TComboBox;
    seMatches: TSpinEdit;
    mLog: TMemo;
    pStart, pIf, pAct: TPanel;
    cbEvent, cbLeft, cbOp, cbRightVar, cbAct, cbAmount: TComboBox;
    seRight, seMul, seAdd: TFloatSpinEdit;
    edText: TEdit;
    Timer: TTimer;
    function Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer; AClick: TNotifyEvent): TButton;
    function Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
    function Combo(AParent: TWinControl; AX, AY, AW: Integer): TComboBox;
    function FSpin(AParent: TWinControl; AX, AY: Integer; AMin, AMax: Double): TFloatSpinEdit;
    procedure BuildUI;
    procedure SetFileName(const AFile: string);
    procedure Changed;
    procedure ShowProps;
    function NodeRect(const N: TFlowNode): TRect;
    function PortPos(const N: TFlowNode; APort: Integer): TPoint;
    function NodeAt(X, Y: Integer): Integer;
    function PortAt(X, Y: Integer; out APort: Integer): Integer;
    procedure Paint(Sender: TObject);
    procedure MouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure KeyDownForm(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PropChange(Sender: TObject);
    procedure EnabledClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure CheckClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure GpuClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure QuickClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure ReadTrace;
    procedure WriteSimFile;
    function SimRunning: Boolean;
    function AskSave: Boolean;
    procedure Log(const S: string);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  FlowForm: TFlowForm;

implementation

const
  GameDir = '..\NeonGrid SDL3 GPU Game\';
  NodeW = 210;
  NodeH = 54;
  IfW = 236;
  IfH = 84;
  CanvasW = 2200;
  CanvasH = 1600;

type
  TIntegerArray = array of Integer;

var
  QuickCounts: ^TIntegerArray = nil;

function DefaultFile: string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + GameDir + 'NeonBeads.ironflow');
end;

function Clock: Double;
begin
  Result := GetTickCount64 / 1000;
end;

{ quick test: count the nodes that fire (uIronFlow.FlowTrace) }
procedure CountFire(ASide, ANode, AAmount: Integer);
begin
  if (QuickCounts = nil) or (ANode < 0) then Exit;
  if ANode >= Length(QuickCounts^) then SetLength(QuickCounts^, ANode + 16);
  Inc(QuickCounts^[ANode]);
end;

{ TFlowForm }

constructor TFlowForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner, 0);
  Caption := 'Neon Iron Flow';
  Width := 1440;
  Height := 920;
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @KeyDownForm;
  OnCloseQuery := @FormCloseQuery;
  FSimFile := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'NeonBeads-flowsim.ironflow';
  DeleteFile(FSimFile + '.trace');   // an old simulation's trace
  BuildUI;
  { the rules of the VS BOT editor too: the flow reads their numbers }
  LoadRulesFile(rkVersus, ExpandFileName(ExtractFilePath(ParamStr(0)) + GameDir + 'NeonBeads.versus'));
  LoadRulesFile(rkScoring, ExpandFileName(ExtractFilePath(ParamStr(0)) + GameDir + 'NeonBeads.scoring'));
  FFile := DefaultFile;
  if IronFlow.LoadFromFile(FFile) then
    lblStatus.Caption := 'Loaded ' + FFile
  else
  begin
    DefaultFlow(IronFlow);
    lblStatus.Caption := 'No flow file yet: the built-in rules as a flow. Save writes ' + FFile;
  end;
  SetFileName(FFile);
  FUpdating := True;
  chkEnabled.Checked := IronFlow.Enabled;
  FUpdating := False;
  FDirty := False;
  ShowProps;
  Timer.Enabled := True;
end;

destructor TFlowForm.Destroy;
begin
  Timer.Enabled := False;
  if SimRunning then FSim.Terminate(0);
  FSim.Free;
  inherited Destroy;
end;

function TFlowForm.Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AW, 26);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function TFlowForm.Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := AX;
  Result.Top := AY;
  Result.Caption := ACaption;
end;

function TFlowForm.Combo(AParent: TWinControl; AX, AY, AW: Integer): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AW, 24);
  Result.Style := csDropDownList;
  Result.DropDownCount := 20;
  Result.OnChange := @PropChange;
end;

function TFlowForm.FSpin(AParent: TWinControl; AX, AY: Integer; AMin, AMax: Double): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, 100, 24);
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.DecimalPlaces := 2;
  Result.OnChange := @PropChange;
end;

procedure TFlowForm.BuildUI;
var
  pTop, pSim, pRight: TPanel;
  i: Integer;
  e: TFlowEvent;
  b: TButton;
begin
  pTop := TPanel.Create(Self);
  pTop.Parent := Self;
  pTop.Align := alTop;
  pTop.Height := 40;
  pTop.BevelOuter := bvNone;
  Btn(pTop, 'New (rules)', 8, 7, 90, @NewClick).Hint := 'the built-in VS BOT rules as a flow';
  Btn(pTop, 'Open...', 102, 7, 66, @OpenClick);
  Btn(pTop, 'Save', 172, 7, 56, @SaveClick);
  Btn(pTop, 'Save As...', 232, 7, 78, @SaveAsClick);
  chkEnabled := TCheckBox.Create(Self);
  chkEnabled.Parent := pTop;
  chkEnabled.SetBounds(322, 10, 190, 22);
  chkEnabled.Caption := 'use this flow in the game';
  chkEnabled.Hint := 'off: the game uses the built-in rules (NeonVsEditor) and ignores the flow';
  chkEnabled.ShowHint := True;
  chkEnabled.OnClick := @EnabledClick;
  Lbl(pTop, 'Add:', 520, 12);
  b := Btn(pTop, 'Start', 556, 7, 56, @AddClick); b.Tag := Ord(fkStart);
  b := Btn(pTop, 'Condition', 616, 7, 74, @AddClick); b.Tag := Ord(fkIf);
  b := Btn(pTop, 'Action', 694, 7, 60, @AddClick); b.Tag := Ord(fkAction);
  b := Btn(pTop, 'End', 758, 7, 46, @AddClick); b.Tag := Ord(fkEnd);
  Btn(pTop, 'Delete', 816, 7, 60, @DeleteClick);
  Btn(pTop, 'Check', 880, 7, 60, @CheckClick).Hint := 'nodes without a way on, unreachable nodes';
  lblFile := Lbl(pTop, '', 952, 12);
  lblFile.Font.Color := clGrayText;

  pSim := TPanel.Create(Self);
  pSim.Parent := Self;
  pSim.Align := alTop;
  pSim.Height := 38;
  pSim.BevelOuter := bvNone;
  pSim.Top := 50;
  Lbl(pSim, 'Simulate:  left bot', 8, 11);
  cbLeftBot := TComboBox.Create(Self);
  cbLeftBot.Parent := pSim;
  cbLeftBot.SetBounds(118, 7, 90, 24);
  cbLeftBot.Style := csDropDownList;
  Lbl(pSim, 'vs  right bot', 216, 11);
  cbRightBot := TComboBox.Create(Self);
  cbRightBot.Parent := pSim;
  cbRightBot.SetBounds(290, 7, 90, 24);
  cbRightBot.Style := csDropDownList;
  for i := 0 to BotLevels - 1 do
  begin
    cbLeftBot.Items.Add(BotNames[i]);
    cbRightBot.Items.Add(BotNames[i]);
  end;
  cbLeftBot.ItemIndex := 1;
  cbRightBot.ItemIndex := 1;
  Btn(pSim, 'GPU window', 392, 5, 96, @GpuClick).Hint :=
    'Neon Beads plays bot against bot with this flow (changes reach it at once)';
  Btn(pSim, 'Close it', 492, 5, 70, @StopClick);
  Lbl(pSim, 'Quick test:', 584, 11);
  seMatches := TSpinEdit.Create(Self);
  seMatches.Parent := pSim;
  seMatches.SetBounds(652, 7, 60, 24);
  seMatches.MinValue := 1;
  seMatches.MaxValue := 200;
  seMatches.Value := 10;
  Lbl(pSim, 'matches', 716, 11);
  Btn(pSim, 'Run', 772, 5, 60, @QuickClick).Hint := 'matches without a window: results in the log, fires as badges';

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := Self;
  lblStatus.Align := alBottom;
  lblStatus.BorderSpacing.Around := 4;

  pRight := TPanel.Create(Self);
  pRight.Parent := Self;
  pRight.Align := alRight;
  pRight.Width := 360;
  pRight.BevelOuter := bvNone;
  lblCap := Lbl(pRight, '', 8, 6);
  lblCap.Font.Style := [fsBold];
  lblCap.AutoSize := False;
  lblCap.SetBounds(8, 6, 344, 40);
  lblCap.WordWrap := True;

  pStart := TPanel.Create(Self);
  pStart.Parent := pRight;
  pStart.SetBounds(0, 50, 360, 40);
  pStart.BevelOuter := bvNone;
  Lbl(pStart, 'Event', 8, 10);
  cbEvent := Combo(pStart, 90, 6, 260);
  for e := Low(TFlowEvent) to High(TFlowEvent) do cbEvent.Items.Add(FlowEventNames[e]);

  pIf := TPanel.Create(Self);
  pIf.Parent := pRight;
  pIf.SetBounds(0, 50, 360, 130);
  pIf.BevelOuter := bvNone;
  Lbl(pIf, 'If', 8, 10);
  cbLeft := Combo(pIf, 90, 6, 260);
  for i := 0 to FlowVarCount - 1 do cbLeft.Items.Add(FlowVarNames[i]);
  Lbl(pIf, 'is', 8, 42);
  cbOp := Combo(pIf, 90, 38, 60);
  for i := 0 to FlowOpCount - 1 do cbOp.Items.Add(FlowOpNames[i]);
  Lbl(pIf, 'than / to', 8, 74);
  cbRightVar := Combo(pIf, 90, 70, 260);
  cbRightVar.Items.Add('(the number below)');
  for i := 0 to FlowVarCount - 1 do cbRightVar.Items.Add(FlowVarNames[i]);
  Lbl(pIf, 'number', 8, 104);
  seRight := FSpin(pIf, 90, 100, -100000, 100000);

  pAct := TPanel.Create(Self);
  pAct.Parent := pRight;
  pAct.SetBounds(0, 50, 360, 170);
  pAct.BevelOuter := bvNone;
  Lbl(pAct, 'Do', 8, 10);
  cbAct := Combo(pAct, 90, 6, 260);
  for i := 0 to FlowActCount - 1 do cbAct.Items.Add(FlowActNames[i]);
  Lbl(pAct, 'Amount', 8, 42);
  cbAmount := Combo(pAct, 90, 38, 260);
  cbAmount.Items.Add('(only the number to add)');
  for i := 0 to FlowVarCount - 1 do cbAmount.Items.Add(FlowVarNames[i]);
  Lbl(pAct, 'x', 8, 74);
  seMul := FSpin(pAct, 90, 70, -1000, 1000);
  Lbl(pAct, '+', 200, 74);
  seAdd := FSpin(pAct, 220, 70, -100000, 100000);
  Lbl(pAct, 'Message', 8, 106);
  edText := TEdit.Create(Self);
  edText.Parent := pAct;
  edText.SetBounds(90, 102, 260, 24);
  edText.OnChange := @PropChange;
  Lbl(pAct, '{n} = the last amount', 90, 132).Font.Color := clGrayText;

  mLog := TMemo.Create(Self);
  mLog.Parent := pRight;
  mLog.SetBounds(8, 230, 344, 560);
  mLog.Anchors := [akLeft, akTop, akRight, akBottom];
  mLog.ReadOnly := True;
  mLog.ScrollBars := ssVertical;
  mLog.Font.Name := 'Consolas';
  mLog.Font.Size := 9;

  sb := TScrollBox.Create(Self);
  sb.Parent := Self;
  sb.Align := alClient;
  sb.HorzScrollBar.Tracking := True;
  sb.VertScrollBar.Tracking := True;
  sb.DoubleBuffered := True;
  pb := TPaintBox.Create(Self);
  pb.Parent := sb;
  pb.SetBounds(0, 0, CanvasW, CanvasH);
  pb.OnPaint := @Paint;
  pb.OnMouseDown := @MouseDown;
  pb.OnMouseMove := @MouseMove;
  pb.OnMouseUp := @MouseUp;

  Timer := TTimer.Create(Self);
  Timer.Interval := 80;
  Timer.Enabled := False;
  Timer.OnTimer := @Tick;
  pTop.Top := 0;
  lblStatus.Top := 6000;
end;

procedure TFlowForm.SetFileName(const AFile: string);
begin
  FFile := AFile;
  lblFile.Caption := AFile;
  Caption := 'Neon Iron Flow - ' + ExtractFileName(AFile);
end;

procedure TFlowForm.Log(const S: string);
begin
  mLog.Lines.Add(S);
  while mLog.Lines.Count > 400 do mLog.Lines.Delete(0);
  mLog.SelStart := Length(mLog.Text);
end;

procedure TFlowForm.Changed;
begin
  FDirty := True;
  Inc(FlowStamp);
  lblStatus.Caption := 'Changed (not saved yet)';
  if SimRunning then WriteSimFile;
  pb.Invalidate;
end;

{ ---- geometry }

function TFlowForm.NodeRect(const N: TFlowNode): TRect;
begin
  if N.Kind = fkIf then
    Result := Rect(Round(N.X - IfW / 2), Round(N.Y - IfH / 2), Round(N.X + IfW / 2), Round(N.Y + IfH / 2))
  else if N.Kind = fkEnd then
    Result := Rect(Round(N.X - 50), Round(N.Y - 22), Round(N.X + 50), Round(N.Y + 22))
  else
    Result := Rect(Round(N.X - NodeW / 2), Round(N.Y - NodeH / 2), Round(N.X + NodeW / 2), Round(N.Y + NodeH / 2));
end;

{ port 0: next / yes (bottom), port 1: no (right) }
function TFlowForm.PortPos(const N: TFlowNode; APort: Integer): TPoint;
var
  r: TRect;
begin
  r := NodeRect(N);
  if APort = 1 then Result := Point(r.Right, (r.Top + r.Bottom) div 2)
  else Result := Point((r.Left + r.Right) div 2, r.Bottom);
end;

function TFlowForm.NodeAt(X, Y: Integer): Integer;
var
  i: Integer;
begin
  for i := High(IronFlow.Nodes) downto 0 do
    if PtInRect(NodeRect(IronFlow.Nodes[i]), Point(X, Y)) then Exit(IronFlow.Nodes[i].Id);
  Result := 0;
end;

function TFlowForm.PortAt(X, Y: Integer; out APort: Integer): Integer;
var
  i, p: Integer;
  q: TPoint;
begin
  for i := High(IronFlow.Nodes) downto 0 do
    with IronFlow.Nodes[i] do
    begin
      if Kind = fkEnd then Continue;
      for p := 0 to Ord(Kind = fkIf) do
      begin
        q := PortPos(IronFlow.Nodes[i], p);
        if Sqr(q.X - X) + Sqr(q.Y - Y) <= 64 then
        begin
          APort := p;
          Exit(Id);
        end;
      end;
    end;
  APort := 0;
  Result := 0;
end;

{ ---- drawing }

function KindColour(const N: TFlowNode): TColor;
begin
  case N.Kind of
    fkStart: Result := RGBToColor(60, 200, 110);
    fkIf: Result := RGBToColor(235, 200, 60);
    fkEnd: Result := RGBToColor(220, 70, 80);
  else
    case N.Act of
      faSend: Result := RGBToColor(50, 190, 235);
      faOwn: Result := RGBToColor(240, 150, 50);
      faPoints: Result := RGBToColor(170, 110, 240);
      faMessage: Result := RGBToColor(160, 165, 180);
    else
      Result := RGBToColor(220, 70, 80);
    end;
  end;
end;

procedure TFlowForm.Paint(Sender: TObject);
var
  c: TCanvas;
  i, k, p, t: Integer;
  n, m: TFlowNode;
  r: TRect;
  a, b, q: TPoint;
  col: TColor;
  pts: array[0..3] of TPoint;
  fl: Double;
  s: string;

  procedure Arrow(const AFrom, ATo: TPoint; AColour: TColor; const ALabel: string);
  var
    mid: Integer;
  begin
    c.Pen.Color := AColour;
    c.Pen.Width := 2;
    { elbow: down, across, down into the top of the target }
    mid := AFrom.Y + 16;
    if ATo.Y < mid + 10 then mid := ATo.Y - 18;
    if ALabel = 'No' then
    begin
      { out to the right, along the side, across above the target }
      c.MoveTo(AFrom.X, AFrom.Y);
      c.LineTo(AFrom.X + 22, AFrom.Y);
      c.LineTo(AFrom.X + 22, ATo.Y - 18);
      c.LineTo(ATo.X, ATo.Y - 18);
    end
    else
    begin
      c.MoveTo(AFrom.X, AFrom.Y);
      c.LineTo(AFrom.X, mid);
      c.LineTo(ATo.X, mid);
    end;
    c.LineTo(ATo.X, ATo.Y);
    c.Brush.Color := AColour;
    c.Polygon([Point(ATo.X, ATo.Y), Point(ATo.X - 6, ATo.Y - 10), Point(ATo.X + 6, ATo.Y - 10)]);
    if ALabel <> '' then
    begin
      c.Brush.Style := bsClear;
      c.Font.Color := AColour;
      if ALabel = 'No' then c.TextOut(AFrom.X + 4, AFrom.Y - 16, ALabel)
      else c.TextOut(AFrom.X + 5, AFrom.Y + 1, ALabel);
      c.Brush.Style := bsSolid;
    end;
  end;

begin
  c := pb.Canvas;
  c.Brush.Color := RGBToColor(18, 20, 30);
  c.FillRect(0, 0, pb.Width, pb.Height);
  { grid }
  c.Pen.Width := 1;
  c.Pen.Color := RGBToColor(28, 31, 44);
  for i := 0 to pb.Width div 40 do
  begin
    c.MoveTo(i * 40, 0);
    c.LineTo(i * 40, pb.Height);
  end;
  for i := 0 to pb.Height div 40 do
  begin
    c.MoveTo(0, i * 40);
    c.LineTo(pb.Width, i * 40);
  end;
  c.Font.Name := 'Segoe UI';
  c.Font.Size := 9;

  { arrows first }
  for i := 0 to High(IronFlow.Nodes) do
  begin
    n := IronFlow.Nodes[i];
    for p := 0 to 1 do
    begin
      if p = 0 then t := n.Next else t := n.No;
      if (t = 0) or ((p = 1) and (n.Kind <> fkIf)) or (n.Kind = fkEnd) then Continue;
      k := IronFlow.IndexOf(t);
      if k < 0 then Continue;
      m := IronFlow.Nodes[k];
      r := NodeRect(m);
      b := Point((r.Left + r.Right) div 2, r.Top);
      if n.Kind = fkIf then
      begin
        if p = 0 then Arrow(PortPos(n, 0), b, RGBToColor(110, 220, 120), 'Yes')
        else Arrow(PortPos(n, 1), b, RGBToColor(235, 110, 110), 'No');
      end
      else
        Arrow(PortPos(n, 0), b, RGBToColor(150, 160, 185), '');
    end;
  end;

  { nodes }
  for i := 0 to High(IronFlow.Nodes) do
  begin
    n := IronFlow.Nodes[i];
    r := NodeRect(n);
    col := KindColour(n);
    { a fire lights the node up (cyan left side, pink right side) }
    fl := 0;
    if n.Id < Length(FFlash) then fl := Max(0, 1 - (Clock - FFlash[n.Id]) / 0.9);
    if fl > 0 then
    begin
      if FFlashSide[n.Id] = 0 then c.Pen.Color := RGBToColor(40, 230, 255) else c.Pen.Color := RGBToColor(255, 60, 170);
      c.Pen.Width := 2 + Round(6 * fl);
      c.Brush.Style := bsClear;
      if n.Kind = fkIf then
        c.Polygon([Point((r.Left + r.Right) div 2, r.Top - 6), Point(r.Right + 8, (r.Top + r.Bottom) div 2),
          Point((r.Left + r.Right) div 2, r.Bottom + 6), Point(r.Left - 8, (r.Top + r.Bottom) div 2)])
      else
        c.RoundRect(r.Left - 5, r.Top - 5, r.Right + 5, r.Bottom + 5, 18, 18);
      c.Brush.Style := bsSolid;
    end;
    c.Pen.Width := 2;
    if n.Id = FSel then c.Pen.Color := clWhite else c.Pen.Color := col;
    c.Brush.Color := RGBToColor(Red(col) div 5, Green(col) div 5, Blue(col) div 5);
    case n.Kind of
      fkIf:
        begin
          pts[0] := Point((r.Left + r.Right) div 2, r.Top);
          pts[1] := Point(r.Right, (r.Top + r.Bottom) div 2);
          pts[2] := Point((r.Left + r.Right) div 2, r.Bottom);
          pts[3] := Point(r.Left, (r.Top + r.Bottom) div 2);
          c.Polygon(pts);
        end;
      fkEnd: c.Ellipse(r);
      fkStart: c.RoundRect(r, 30, 30);
    else
      c.Rectangle(r);
    end;
    { the text }
    c.Font.Color := RGBToColor(235, 238, 245);
    c.Brush.Style := bsClear;
    s := IronFlow.Caption(i);
    if n.Kind = fkIf then InflateRect(r, -38, -14) else InflateRect(r, -8, -5);
    DrawText(c.Handle, PChar(s), Length(s), r, DT_CENTER or DT_WORDBREAK or DT_NOPREFIX);
    c.Font.Color := clGrayText;
    c.TextOut(NodeRect(n).Left + 2, NodeRect(n).Top - 15, '#' + IntToStr(n.Id));
    { quick test fires }
    if (n.Id < Length(FCount)) and (FCount[n.Id] > 0) then
    begin
      c.Font.Color := RGBToColor(255, 220, 90);
      c.TextOut(NodeRect(n).Right - 50, NodeRect(n).Top - 15, 'x' + IntToStr(FCount[n.Id]));
    end;
    c.Brush.Style := bsSolid;
    { ports }
    if n.Kind <> fkEnd then
      for p := 0 to Ord(n.Kind = fkIf) do
      begin
        q := PortPos(n, p);
        if p = 1 then c.Brush.Color := RGBToColor(235, 110, 110)
        else if n.Kind = fkIf then c.Brush.Color := RGBToColor(110, 220, 120)
        else c.Brush.Color := RGBToColor(150, 160, 185);
        c.Pen.Color := RGBToColor(20, 20, 20);
        c.Pen.Width := 1;
        c.Ellipse(q.X - 6, q.Y - 6, q.X + 6, q.Y + 6);
      end;
  end;

  { a link being dragged }
  if FLinkFrom > 0 then
  begin
    k := IronFlow.IndexOf(FLinkFrom);
    if k >= 0 then
    begin
      a := PortPos(IronFlow.Nodes[k], FLinkPort);
      c.Pen.Color := clWhite;
      c.Pen.Width := 2;
      c.Pen.Style := psDash;
      c.MoveTo(a.X, a.Y);
      c.LineTo(FMouse.X, FMouse.Y);
      c.Pen.Style := psSolid;
    end;
  end;
end;

{ ---- mouse }

procedure TFlowForm.MouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  id, port, k: Integer;
begin
  id := PortAt(X, Y, port);
  if id > 0 then
  begin
    k := IronFlow.IndexOf(id);
    if Button = mbRight then
    begin
      { cut this arrow }
      if port = 1 then IronFlow.Nodes[k].No := 0 else IronFlow.Nodes[k].Next := 0;
      Changed;
      Exit;
    end;
    FLinkFrom := id;
    FLinkPort := port;
    FMouse := Point(X, Y);
    Exit;
  end;
  id := NodeAt(X, Y);
  FSel := id;
  if id > 0 then
  begin
    k := IronFlow.IndexOf(id);
    FDragNode := id;
    FDragDX := IronFlow.Nodes[k].X - X;
    FDragDY := IronFlow.Nodes[k].Y - Y;
  end;
  ShowProps;
  pb.Invalidate;
end;

procedure TFlowForm.MouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  k: Integer;
begin
  if FDragNode > 0 then
  begin
    k := IronFlow.IndexOf(FDragNode);
    if k >= 0 then
    begin
      { a 10 px grid keeps the chart tidy }
      IronFlow.Nodes[k].X := EnsureRange(Round((X + FDragDX) / 10) * 10, 60, CanvasW - 60);
      IronFlow.Nodes[k].Y := EnsureRange(Round((Y + FDragDY) / 10) * 10, 40, CanvasH - 40);
      FDirty := True;
      pb.Invalidate;
    end;
  end
  else if FLinkFrom > 0 then
  begin
    FMouse := Point(X, Y);
    pb.Invalidate;
  end;
end;

procedure TFlowForm.MouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  t, k: Integer;
begin
  if FDragNode > 0 then
  begin
    FDragNode := 0;
    if FDirty then Changed;
  end;
  if FLinkFrom > 0 then
  begin
    t := NodeAt(X, Y);
    k := IronFlow.IndexOf(FLinkFrom);
    if (t > 0) and (t <> FLinkFrom) and (k >= 0) then
    begin
      if FLinkPort = 1 then IronFlow.Nodes[k].No := t else IronFlow.Nodes[k].Next := t;
      FLinkFrom := 0;
      Changed;
    end;
    FLinkFrom := 0;
    pb.Invalidate;
  end;
end;

procedure TFlowForm.KeyDownForm(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DELETE) and (ActiveControl = nil) or ((Key = VK_DELETE) and (ActiveControl = sb)) then
  begin
    DeleteClick(nil);
    Key := 0;
  end;
end;

{ ---- properties }

procedure TFlowForm.ShowProps;
var
  k: Integer;
  n: TFlowNode;
begin
  k := IronFlow.IndexOf(FSel);
  pStart.Visible := False;
  pIf.Visible := False;
  pAct.Visible := False;
  if k < 0 then
  begin
    lblCap.Caption := 'Click a node to edit it.' + LineEnding + 'Drag from a port to connect.';
    Exit;
  end;
  n := IronFlow.Nodes[k];
  lblCap.Caption := Format('#%d  %s', [n.Id, IronFlow.Caption(k)]);
  FUpdating := True;
  try
    case n.Kind of
      fkStart:
        begin
          pStart.Visible := True;
          cbEvent.ItemIndex := Ord(n.Event);
        end;
      fkIf:
        begin
          pIf.Visible := True;
          cbLeft.ItemIndex := n.LeftVar;
          cbOp.ItemIndex := n.Op;
          cbRightVar.ItemIndex := n.RightVar + 1;
          seRight.Value := n.Right;
          seRight.Enabled := n.RightVar < 0;
        end;
      fkAction:
        begin
          pAct.Visible := True;
          cbAct.ItemIndex := n.Act;
          cbAmount.ItemIndex := n.AmountVar + 1;
          seMul.Value := n.Mul;
          seAdd.Value := n.Add;
          seMul.Enabled := n.AmountVar >= 0;
          edText.Text := n.Text;
        end;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TFlowForm.PropChange(Sender: TObject);
var
  k: Integer;
begin
  if FUpdating then Exit;
  k := IronFlow.IndexOf(FSel);
  if k < 0 then Exit;
  with IronFlow.Nodes[k] do
    case Kind of
      fkStart: Event := TFlowEvent(Max(0, cbEvent.ItemIndex));
      fkIf:
        begin
          LeftVar := Max(0, cbLeft.ItemIndex);
          Op := Max(0, cbOp.ItemIndex);
          RightVar := cbRightVar.ItemIndex - 1;
          Right := seRight.Value;
          seRight.Enabled := RightVar < 0;
        end;
      fkAction:
        begin
          Act := Max(0, cbAct.ItemIndex);
          AmountVar := cbAmount.ItemIndex - 1;
          Mul := seMul.Value;
          Add := seAdd.Value;
          Text := edText.Text;
          seMul.Enabled := AmountVar >= 0;
        end;
    end;
  lblCap.Caption := Format('#%d  %s', [IronFlow.Nodes[k].Id, IronFlow.Caption(k)]);
  Changed;
end;

{ ---- toolbar }

procedure TFlowForm.EnabledClick(Sender: TObject);
begin
  if FUpdating then Exit;
  IronFlow.Enabled := chkEnabled.Checked;
  Changed;
end;

procedure TFlowForm.AddClick(Sender: TObject);
var
  k: Integer;
  x, y: Single;
begin
  { below the selected node, else in the visible part }
  k := IronFlow.IndexOf(FSel);
  if k >= 0 then
  begin
    x := IronFlow.Nodes[k].X;
    y := IronFlow.Nodes[k].Y + 110;
  end
  else
  begin
    x := sb.HorzScrollBar.Position + 200;
    y := sb.VertScrollBar.Position + 100;
  end;
  k := IronFlow.Add(TFlowKind(TComponent(Sender).Tag), x, Min(y, CanvasH - 60));
  FSel := IronFlow.Nodes[k].Id;
  ShowProps;
  Changed;
end;

procedure TFlowForm.DeleteClick(Sender: TObject);
begin
  if FSel = 0 then Exit;
  IronFlow.Delete(FSel);
  FSel := 0;
  ShowProps;
  Changed;
end;

procedure TFlowForm.CheckClick(Sender: TObject);
var
  i, k, n, cur: Integer;
  seen: array of Boolean;
  stack: array of Integer;
  problems: Integer;
  nd: TFlowNode;
begin
  Log('---- check');
  problems := 0;
  SetLength(seen, Length(IronFlow.Nodes));
  SetLength(stack, 0);
  for i := 0 to High(IronFlow.Nodes) do
    if IronFlow.Nodes[i].Kind = fkStart then
    begin
      SetLength(stack, Length(stack) + 1);
      stack[High(stack)] := IronFlow.Nodes[i].Id;
    end;
  if Length(stack) = 0 then
  begin
    Log('no Start: the flow never runs');
    Inc(problems);
  end;
  while Length(stack) > 0 do
  begin
    cur := stack[High(stack)];
    SetLength(stack, Length(stack) - 1);
    k := IronFlow.IndexOf(cur);
    if (k < 0) or seen[k] then Continue;
    seen[k] := True;
    nd := IronFlow.Nodes[k];
    if nd.Next > 0 then
    begin
      SetLength(stack, Length(stack) + 1);
      stack[High(stack)] := nd.Next;
    end;
    if (nd.Kind = fkIf) and (nd.No > 0) then
    begin
      SetLength(stack, Length(stack) + 1);
      stack[High(stack)] := nd.No;
    end;
  end;
  for i := 0 to High(IronFlow.Nodes) do
  begin
    nd := IronFlow.Nodes[i];
    if not seen[i] then
    begin
      Log(Format('#%d is never reached', [nd.Id]));
      Inc(problems);
    end;
    if (nd.Kind in [fkStart, fkIf]) and (nd.Next = 0) then
    begin
      Log(Format('#%d has no %s arrow (the path just ends)', [nd.Id, IfThen(nd.Kind = fkIf, 'Yes', 'next')]));
      Inc(problems);
    end;
    if (nd.Kind = fkIf) and (nd.No = 0) then
    begin
      Log(Format('#%d has no No arrow (the path just ends)', [nd.Id]));
      Inc(problems);
    end;
    if (nd.Kind = fkAction) and (nd.Act = faMessage) and (Trim(nd.Text) = '') then
    begin
      Log(Format('#%d shows an empty message', [nd.Id]));
      Inc(problems);
    end;
  end;
  n := Length(IronFlow.Nodes);
  if problems = 0 then Log(Format('%d nodes, all fine', [n]))
  else Log(Format('%d nodes, %d remarks (a path that just ends is allowed)', [n, problems]));
end;

function TFlowForm.AskSave: Boolean;
begin
  Result := True;
  if not FDirty then Exit;
  case MessageDlg('Save changes?', 'The flow changed. Save it first?', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: SaveClick(nil);
    mrCancel: Result := False;
  end;
end;

procedure TFlowForm.NewClick(Sender: TObject);
begin
  if not AskSave then Exit;
  DefaultFlow(IronFlow);
  FUpdating := True;
  chkEnabled.Checked := IronFlow.Enabled;
  FUpdating := False;
  FSel := 0;
  SetLength(FCount, 0);
  ShowProps;
  Changed;
  lblStatus.Caption := 'The built-in rules as a flow (not saved yet).';
end;

procedure TFlowForm.OpenClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  if not AskSave then Exit;
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := 'Neon Beads iron flow (*.ironflow)|*.ironflow|All files|*.*';
    dlg.InitialDir := ExtractFilePath(FFile);
    if dlg.Execute then
    begin
      if IronFlow.LoadFromFile(dlg.FileName) then
      begin
        SetFileName(dlg.FileName);
        FUpdating := True;
        chkEnabled.Checked := IronFlow.Enabled;
        FUpdating := False;
        FSel := 0;
        SetLength(FCount, 0);
        ShowProps;
        FDirty := False;
        if SimRunning then WriteSimFile;
        pb.Invalidate;
        lblStatus.Caption := 'Opened ' + dlg.FileName;
      end
      else
        MessageDlg('Open', 'No flow in ' + dlg.FileName, mtError, [mbOK], 0);
    end;
  finally
    dlg.Free;
  end;
end;

procedure TFlowForm.SaveClick(Sender: TObject);
begin
  try
    IronFlow.SaveToFile(FFile);
    FDirty := False;
    lblStatus.Caption := 'Saved ' + FFile + '  (a running Neon Beads takes it within half a second)';
  except
    on E: Exception do MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TFlowForm.SaveAsClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := 'Neon Beads iron flow (*.ironflow)|*.ironflow|All files|*.*';
    dlg.DefaultExt := 'ironflow';
    dlg.InitialDir := ExtractFilePath(FFile);
    dlg.FileName := ExtractFileName(FFile);
    dlg.Options := dlg.Options + [ofOverwritePrompt];
    if dlg.Execute then
    begin
      SetFileName(dlg.FileName);
      SaveClick(nil);
      if not SameFileName(ExpandFileName(dlg.FileName), DefaultFile) then
        lblStatus.Caption := lblStatus.Caption + '  - the game reads NeonBeads.ironflow only';
    end;
  finally
    dlg.Free;
  end;
end;

{ ---- simulation }

function TFlowForm.SimRunning: Boolean;
begin
  Result := (FSim <> nil) and FSim.Running;
end;

procedure TFlowForm.WriteSimFile;
begin
  try
    IronFlow.SaveToFile(FSimFile);
  except
    { the game is reading it: the next change writes it again }
  end;
end;

procedure TFlowForm.GpuClick(Sender: TObject);
var
  exe: string;
begin
  if SimRunning then
  begin
    WriteSimFile;
    lblStatus.Caption := 'The GPU window is open already (it follows every change).';
    Exit;
  end;
  exe := ExpandFileName(ExtractFilePath(ParamStr(0)) + GameDir + 'NeonBeads.exe');
  if not FileExists(exe) then
  begin
    MessageDlg('GPU window', 'Not found: ' + exe, mtError, [mbOK], 0);
    Exit;
  end;
  WriteSimFile;
  DeleteFile(FSimFile + '.trace');
  FTracePos := 0;
  FMatch := 0;
  FreeAndNil(FSim);
  FSim := TProcess.Create(nil);
  FSim.Executable := exe;
  FSim.Parameters.Add('--vssim=' + FSimFile);
  FSim.Parameters.Add('--left=' + IntToStr(cbLeftBot.ItemIndex));
  FSim.Parameters.Add('--right=' + IntToStr(cbRightBot.ItemIndex));
  FSim.CurrentDirectory := ExtractFilePath(exe);
  try
    FSim.Execute;
    Log('---- GPU window: ' + cbLeftBot.Text + ' (left) vs ' + cbRightBot.Text + ' (right)');
    lblStatus.Caption := 'GPU window open: the nodes that fire light up (cyan left, pink right). ' +
      'Keys there: 1-4 speed, R new match, Esc close.';
  except
    on E: Exception do
    begin
      FreeAndNil(FSim);
      MessageDlg('GPU window', E.Message, mtError, [mbOK], 0);
    end;
  end;
end;

procedure TFlowForm.StopClick(Sender: TObject);
begin
  if SimRunning then FSim.Terminate(0);
end;

{ the nodes the GPU window reports: "match time side node" }
procedure TFlowForm.ReadTrace;
var
  fs: TFileStream;
  buf: string;
  lines: TStringList;
  i, k, m, side, id, amt: Integer;
  parts: TStringArray;
  side0, what: string;
begin
  if not FileExists(FSimFile + '.trace') then Exit;
  try
    fs := TFileStream.Create(FSimFile + '.trace', fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  lines := TStringList.Create;
  try
    if fs.Size <= FTracePos then Exit;
    fs.Position := FTracePos;
    SetLength(buf, fs.Size - FTracePos);
    fs.ReadBuffer(buf[1], Length(buf));
    { only whole lines; the rest next time }
    k := LastDelimiter(#10, buf);
    if k = 0 then Exit;
    SetLength(buf, k);
    FTracePos += k;
    lines.Text := buf;
    for i := 0 to lines.Count - 1 do
    begin
      parts := Trim(lines[i]).Split([' ']);
      if Length(parts) < 4 then Continue;
      m := StrToIntDef(parts[0], 0);
      side := StrToIntDef(parts[2], 0);
      id := StrToIntDef(parts[3], 0);
      if Length(parts) > 4 then amt := StrToIntDef(parts[4], 0) else amt := 0;
      if m <> FMatch then
      begin
        FMatch := m;
        Log(Format('---- match %d', [m]));
      end;
      if id >= Length(FFlash) then
      begin
        SetLength(FFlash, id + 16);
        SetLength(FFlashSide, id + 16);
      end;
      FFlash[id] := Clock;
      FFlashSide[id] := side;
      k := IronFlow.IndexOf(id);
      if side = 0 then side0 := 'L' else side0 := 'R';
      { the log keeps what happened: actions with an amount, messages, stops
        (conditions and empty actions only light up) }
      if (k >= 0) and (IronFlow.Nodes[k].Kind = fkAction) then
      begin
        case IronFlow.Nodes[k].Act of
          faSend: what := Format('sends %d iron', [amt]);
          faOwn: what := Format('%d iron on own board', [amt]);
          faPoints: what := Format('points %+d', [amt]);
          faMessage: what := 'message "' + IronFlow.Nodes[k].Text + '"';
        else
          what := 'stop';
        end;
        if (amt <> 0) or (IronFlow.Nodes[k].Act in [faMessage, faStop]) then
          Log(Format('%7s s %s #%-3d %s', [parts[1], side0, id, what]));
      end;
    end;
  finally
    lines.Free;
    fs.Free;
  end;
end;

procedure TFlowForm.Tick(Sender: TObject);
begin
  if SimRunning or FileExists(FSimFile + '.trace') then ReadTrace;
  pb.Invalidate;
end;

procedure TFlowForm.QuickClick(Sender: TObject);
var
  i, n, wa, wb, sa, sb2, ia, ib: Integer;
  r: TVsSim;
  counts: TIntegerArray;
  secs: Double;
begin
  n := seMatches.Value;
  wa := 0; wb := 0; sa := 0; sb2 := 0; ia := 0; ib := 0;
  secs := 0;
  SetLength(counts, 0);
  QuickCounts := @counts;
  FlowTrace := @CountFire;
  Screen.Cursor := crHourGlass;
  try
    for i := 1 to n do
    begin
      r := SimVersus(cbLeftBot.ItemIndex, cbRightBot.ItemIndex, 7000 + i * 31, 900, False);
      if r.Winner = 1 then Inc(wa) else if r.Winner = 2 then Inc(wb);
      sa += r.ScoreA;
      sb2 += r.ScoreB;
      ia += r.SentA;
      ib += r.SentB;
      secs += r.Seconds;
      lblStatus.Caption := Format('quick test: match %d / %d', [i, n]);
      Application.ProcessMessages;
    end;
  finally
    FlowTrace := nil;
    QuickCounts := nil;
    Screen.Cursor := crDefault;
  end;
  FCount := counts;
  Log(Format('---- quick test: %s vs %s, %d matches%s', [cbLeftBot.Text, cbRightBot.Text, n,
    IfThen(FlowOn, '', ' (flow OFF: built-in rules)')]));
  Log(Format('wins      left %d  right %d  other %d', [wa, wb, n - wa - wb]));
  Log(Format('score     left %d  right %d (average)', [sa div n, sb2 div n]));
  Log(Format('iron sent left %.1f  right %.1f (average)', [ia / n, ib / n]));
  Log(Format('length    %.0f s (average)', [secs / n]));
  Log('the yellow xN on the nodes: how often each one ran');
  lblStatus.Caption := 'Quick test done.';
  pb.Invalidate;
end;

procedure TFlowForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := AskSave;
end;

end.
