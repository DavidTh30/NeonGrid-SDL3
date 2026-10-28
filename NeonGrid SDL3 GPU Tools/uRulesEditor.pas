unit uRulesEditor;

{ The rule editors of Neon Beads (one form, two programs):
    NeonScoreEditor  the scoring rules  (NeonBeads.scoring)
    NeonVsEditor     the VS BOT rules   (NeonBeads.versus)
  see uBeadRules. Left: every value with a slider, a number and a reset to
  the original rule. Top: New (the original rules), Open..., Save,
  Save As..., Reload, and "live" (save every change, a running game takes it
  within half a second). Right: Simulate - real games with the values as
  they are now (saved or not, uBeadSim), optionally next to the original
  rules on the same boards:
    scoring: a mode (classic level / time attack / survival), a player
             style, N games -> scores, pops, groups, stars ..., a histogram,
             and a points table that follows every change;
    versus:  two bots (left / right level), N matches -> wins, scores, iron,
             time the iron is on, and the score lines of the first match. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Spin, Dialogs,
  StrUtils, uBeadRules, uBeadGame, uBeadSim;

type
  TRulesForm = class(TForm)
  private
    FKind: TRuleKind;
    FFile: string;
    FDirty, FUpdating, FRunning, FCancel: Boolean;
    tb: array of TTrackBar;
    se: array of TFloatSpinEdit;
    sbRules: TScrollBox;
    lblFile, lblStatus, lblProgress: TLabel;
    chkLive, chkCompare: TCheckBox;
    cbMode, cbPolicy, cbLeft, cbRight: TComboBox;
    seLevel, seCount: TSpinEdit;
    seMoveSecs, seMaxSecs: TFloatSpinEdit;
    btnRun: TButton;
    mResult, mTable: TMemo;
    pbChart: TPaintBox;
    SaveTimer: TTimer;
    { chart data }
    FHistCur, FHistOrg: array of Integer;
    FHistLo, FHistHi: Integer;
    FLine: array of TVsPoint;
    FLineGap: Single;
    function Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer; AClick: TNotifyEvent): TButton;
    function Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
    procedure BuildUI;
    procedure BuildRules;
    procedure BuildSim(AParent: TWinControl);
    procedure ShowValues;
    procedure Changed;
    procedure UpdateTable;
    procedure SetFileName(const AFile: string);
    procedure TrackChange(Sender: TObject);
    procedure SpinChange(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure LiveSave(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure RunScoring;
    procedure RunVersus;
    procedure ChartPaint(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    function AskSave: Boolean;
  public
    constructor CreateKind(TheOwner: TComponent; AKind: TRuleKind);
    { for Application.CreateForm: the kind is RulesKind }
    constructor Create(TheOwner: TComponent); override;
  end;

var
  RulesForm: TRulesForm;
  RulesKind: TRuleKind = rkScoring;   // set by the program before CreateForm

implementation

var
  FS: TFormatSettings;

const
  GameDir = '..\NeonGrid SDL3 GPU Game\';

function DefaultFile(AKind: TRuleKind): string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + GameDir + 'NeonBeads' + RulesExt(AKind));
end;

function Fmt(V: Single; AInt: Boolean): string;
begin
  if AInt then Result := IntToStr(Round(V)) else Result := FormatFloat('0.###', V, FS);
end;

{ TRulesForm }

constructor TRulesForm.CreateKind(TheOwner: TComponent; AKind: TRuleKind);
begin
  inherited CreateNew(TheOwner, 0);
  FKind := AKind;
  Width := 1360;
  Height := 860;
  Position := poScreenCenter;
  OnCloseQuery := @FormCloseQuery;
  BuildUI;
  FFile := DefaultFile(FKind);
  if LoadRulesFile(FKind, FFile) then
    lblStatus.Caption := 'Loaded ' + FFile
  else
  begin
    DefaultRules(FKind);
    lblStatus.Caption := 'No file yet: the original rules. Save writes ' + FFile;
  end;
  SetFileName(FFile);
  ShowValues;
  FDirty := False;
end;

constructor TRulesForm.Create(TheOwner: TComponent);
begin
  CreateKind(TheOwner, RulesKind);
end;

function TRulesForm.Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AW, 26);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function TRulesForm.Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := AX;
  Result.Top := AY;
  Result.Caption := ACaption;
end;

procedure TRulesForm.SetFileName(const AFile: string);
begin
  FFile := AFile;
  lblFile.Caption := AFile;
  if FKind = rkScoring then Caption := 'Neon Beads Scoring Rules - ' + ExtractFileName(AFile)
  else Caption := 'Neon Beads VS BOT Rules - ' + ExtractFileName(AFile);
end;

procedure TRulesForm.BuildUI;
var
  pTop, pSim: TPanel;
begin
  pTop := TPanel.Create(Self);
  pTop.Parent := Self;
  pTop.Align := alTop;
  pTop.Height := 40;
  pTop.BevelOuter := bvNone;
  Btn(pTop, 'New (original)', 8, 7, 104, @NewClick).Hint := 'all values back to the original rules';
  Btn(pTop, 'Open...', 116, 7, 70, @OpenClick);
  Btn(pTop, 'Save', 190, 7, 60, @SaveClick);
  Btn(pTop, 'Save As...', 254, 7, 80, @SaveAsClick);
  Btn(pTop, 'Reload', 338, 7, 64, @ReloadClick);
  chkLive := TCheckBox.Create(Self);
  chkLive.Parent := pTop;
  chkLive.SetBounds(412, 10, 270, 22);
  chkLive.Caption := 'live: save every change (running game follows)';
  lblFile := Lbl(pTop, '', 690, 12);
  lblFile.Font.Color := clGrayText;

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := Self;
  lblStatus.Align := alBottom;
  lblStatus.BorderSpacing.Around := 4;

  sbRules := TScrollBox.Create(Self);
  sbRules.Parent := Self;
  sbRules.Align := alLeft;
  sbRules.Width := 600;
  sbRules.VertScrollBar.Tracking := True;
  BuildRules;

  pSim := TPanel.Create(Self);
  pSim.Parent := Self;
  pSim.Align := alClient;
  pSim.BevelOuter := bvNone;
  BuildSim(pSim);

  SaveTimer := TTimer.Create(Self);
  SaveTimer.Interval := 300;
  SaveTimer.Enabled := False;
  SaveTimer.OnTimer := @LiveSave;
  pTop.Top := 0;
  lblStatus.Top := 6000;
end;

procedure TRulesForm.BuildRules;
var
  i, y, n: Integer;
  g: string;
  ri: TRuleInfo;
  l: TLabel;
  b: TButton;
begin
  n := RuleCount(FKind);
  SetLength(tb, n);
  SetLength(se, n);
  y := 6;
  g := '';
  for i := 0 to n - 1 do
  begin
    ri := RuleInfo(FKind, i);
    if ri.Group <> g then
    begin
      g := ri.Group;
      l := Lbl(sbRules, g, 8, y + 6);
      l.Font.Style := [fsBold];
      Inc(y, 28);
    end;
    l := Lbl(sbRules, ri.Caption, 16, y + 5);
    l.Hint := ri.Hint;
    l.ShowHint := True;
    tb[i] := TTrackBar.Create(Self);
    tb[i].Parent := sbRules;
    tb[i].SetBounds(236, y, 200, 26);
    tb[i].Max := 1000;
    tb[i].TickStyle := tsNone;
    tb[i].Tag := i;
    tb[i].Hint := ri.Hint;
    tb[i].ShowHint := True;
    tb[i].OnChange := @TrackChange;
    se[i] := TFloatSpinEdit.Create(Self);
    se[i].Parent := sbRules;
    se[i].SetBounds(442, y + 1, 90, 24);
    se[i].MinValue := ri.Min;
    se[i].MaxValue := ri.Max;
    if ri.IsInt then
    begin
      se[i].DecimalPlaces := 0;
      se[i].Increment := 1;
    end
    else
    begin
      se[i].DecimalPlaces := 3;
      se[i].Increment := Max(0.001, (ri.Max - ri.Min) / 100);
    end;
    se[i].Tag := i;
    se[i].OnChange := @SpinChange;
    b := Btn(sbRules, '<>', 538, y, 30, @ResetClick);
    b.Tag := i;
    b.Hint := 'back to the original: ' + Fmt(ri.Def, ri.IsInt);
    b.ShowHint := True;
    Inc(y, 30);
  end;
end;

procedure TRulesForm.BuildSim(AParent: TWinControl);
var
  p: TPanel;
  i: Integer;
  l: TLabel;
begin
  p := TPanel.Create(Self);
  p.Parent := AParent;
  p.Align := alTop;
  p.Height := 112;
  p.BevelOuter := bvNone;
  l := Lbl(p, 'Simulate (the values as they are now, saved or not)', 8, 8);
  l.Font.Style := [fsBold];
  if FKind = rkScoring then
  begin
    Lbl(p, 'Mode', 8, 38);
    cbMode := TComboBox.Create(Self);
    cbMode.Parent := p;
    cbMode.SetBounds(60, 34, 170, 24);
    cbMode.Style := csDropDownList;
    for i := 0 to High(ModeNames) do cbMode.Items.Add(ModeNames[i]);
    cbMode.ItemIndex := 0;
    Lbl(p, 'Level', 240, 38);
    seLevel := TSpinEdit.Create(Self);
    seLevel.Parent := p;
    seLevel.SetBounds(284, 34, 60, 24);
    seLevel.MinValue := 1;
    seLevel.MaxValue := 30;
    seLevel.Value := 3;
    Lbl(p, 'Player', 356, 38);
    cbPolicy := TComboBox.Create(Self);
    cbPolicy.Parent := p;
    cbPolicy.SetBounds(404, 34, 170, 24);
    cbPolicy.Style := csDropDownList;
    for i := 0 to High(PolicyNames) do cbPolicy.Items.Add(PolicyNames[i]);
    cbPolicy.ItemIndex := 0;
    Lbl(p, 'Games', 8, 72);
    seCount := TSpinEdit.Create(Self);
    seCount.Parent := p;
    seCount.SetBounds(60, 68, 70, 24);
    seCount.MinValue := 1;
    seCount.MaxValue := 2000;
    seCount.Value := 40;
    Lbl(p, 'Seconds per move', 140, 72);
    seMoveSecs := TFloatSpinEdit.Create(Self);
    seMoveSecs.Parent := p;
    seMoveSecs.SetBounds(250, 68, 70, 24);
    seMoveSecs.MinValue := 0.1;
    seMoveSecs.MaxValue := 10;
    seMoveSecs.DecimalPlaces := 2;
    seMoveSecs.Increment := 0.1;
    seMoveSecs.Value := 0.8;
    seMoveSecs.Hint := 'how long the player takes per move (time attack, chains)';
    seMoveSecs.ShowHint := True;
  end
  else
  begin
    Lbl(p, 'Left bot', 8, 38);
    cbLeft := TComboBox.Create(Self);
    cbLeft.Parent := p;
    cbLeft.SetBounds(70, 34, 100, 24);
    cbLeft.Style := csDropDownList;
    Lbl(p, 'vs  right bot', 180, 38);
    cbRight := TComboBox.Create(Self);
    cbRight.Parent := p;
    cbRight.SetBounds(262, 34, 100, 24);
    cbRight.Style := csDropDownList;
    for i := 0 to BotLevels - 1 do
    begin
      cbLeft.Items.Add(BotNames[i]);
      cbRight.Items.Add(BotNames[i]);
    end;
    cbLeft.ItemIndex := 1;
    cbRight.ItemIndex := 1;
    Lbl(p, 'Matches', 8, 72);
    seCount := TSpinEdit.Create(Self);
    seCount.Parent := p;
    seCount.SetBounds(70, 68, 70, 24);
    seCount.MinValue := 1;
    seCount.MaxValue := 500;
    seCount.Value := 20;
    Lbl(p, 'Max seconds', 150, 72);
    seMaxSecs := TFloatSpinEdit.Create(Self);
    seMaxSecs.Parent := p;
    seMaxSecs.SetBounds(232, 68, 80, 24);
    seMaxSecs.MinValue := 30;
    seMaxSecs.MaxValue := 3600;
    seMaxSecs.DecimalPlaces := 0;
    seMaxSecs.Increment := 30;
    seMaxSecs.Value := 900;
  end;
  chkCompare := TCheckBox.Create(Self);
  chkCompare.Parent := p;
  chkCompare.SetBounds(340, 70, 210, 22);
  chkCompare.Caption := 'also with the original rules';
  chkCompare.Checked := True;
  btnRun := Btn(p, 'Simulate', 560, 66, 100, @RunClick);
  lblProgress := Lbl(p, '', 668, 72);

  pbChart := TPaintBox.Create(Self);
  pbChart.Parent := AParent;
  pbChart.Align := alBottom;
  pbChart.Height := 230;
  pbChart.OnPaint := @ChartPaint;

  if FKind = rkScoring then
  begin
    mTable := TMemo.Create(Self);
    mTable.Parent := AParent;
    mTable.Align := alRight;
    mTable.Width := 230;
    mTable.ReadOnly := True;
    mTable.ScrollBars := ssVertical;
    mTable.Font.Name := 'Consolas';
    mTable.Font.Size := 9;
  end;
  mResult := TMemo.Create(Self);
  mResult.Parent := AParent;
  mResult.Align := alClient;
  mResult.ReadOnly := True;
  mResult.ScrollBars := ssBoth;
  mResult.WordWrap := False;
  mResult.Font.Name := 'Consolas';
  mResult.Font.Size := 9;
  mResult.Lines.Add('Press Simulate: the games are played with the real game logic.');
end;

{ ---- values }

procedure TRulesForm.ShowValues;
var
  i: Integer;
  ri: TRuleInfo;
  v: Single;
begin
  FUpdating := True;
  try
    for i := 0 to High(tb) do
    begin
      ri := RuleInfo(FKind, i);
      v := GetRule(FKind, i);
      tb[i].Position := Round((v - ri.Min) / Max(1e-6, ri.Max - ri.Min) * 1000);
      se[i].Value := v;
    end;
  finally
    FUpdating := False;
  end;
  UpdateTable;
end;

procedure TRulesForm.Changed;
begin
  FDirty := True;
  Inc(RulesStamp);
  lblStatus.Caption := 'Changed (not saved yet) - Simulate uses the new values already';
  UpdateTable;
  if chkLive.Checked then
  begin
    SaveTimer.Enabled := False;
    SaveTimer.Enabled := True;
  end;
end;

procedure TRulesForm.TrackChange(Sender: TObject);
var
  i: Integer;
  ri: TRuleInfo;
begin
  if FUpdating then Exit;
  i := TTrackBar(Sender).Tag;
  ri := RuleInfo(FKind, i);
  SetRule(FKind, i, ri.Min + (ri.Max - ri.Min) * TTrackBar(Sender).Position / 1000);
  FUpdating := True;
  se[i].Value := GetRule(FKind, i);
  FUpdating := False;
  Changed;
end;

procedure TRulesForm.SpinChange(Sender: TObject);
var
  i: Integer;
  ri: TRuleInfo;
begin
  if FUpdating then Exit;
  i := TFloatSpinEdit(Sender).Tag;
  ri := RuleInfo(FKind, i);
  SetRule(FKind, i, TFloatSpinEdit(Sender).Value);
  FUpdating := True;
  tb[i].Position := Round((GetRule(FKind, i) - ri.Min) / Max(1e-6, ri.Max - ri.Min) * 1000);
  FUpdating := False;
  Changed;
end;

procedure TRulesForm.ResetClick(Sender: TObject);
var
  i: Integer;
begin
  i := TButton(Sender).Tag;
  SetRule(FKind, i, RuleInfo(FKind, i).Def);
  ShowValues;
  Changed;
end;

{ points of plain groups and what else a move brings, for the current values }
procedure TRulesForm.UpdateTable;
var
  n, iron, bonus, k: Integer;
  p: Single;
  s: string;
begin
  if mTable = nil then Exit;
  mTable.Lines.BeginUpdate;
  try
    mTable.Clear;
    mTable.Lines.Add('Points of a plain group');
    mTable.Lines.Add('(no blasts, no arrangement)');
    mTable.Lines.Add('');
    mTable.Lines.Add('  n   points  reward  surv.');
    for n := 2 to 30 do
    begin
      p := n * (n - 1) * SR[srPerPair] + n * SR[srPerBead];
      if (SR[srBigBonus] > 0) and (n >= SRI(srBigSize)) then p += SR[srBigBonus];
      s := '';
      if (SRI(srRewardRainbow) > 0) and (n >= SRI(srRewardRainbow)) then s := 'rainb'
      else if (SRI(srRewardLine) > 0) and (n >= SRI(srRewardLine)) then s := 'line'
      else if (SRI(srRewardBomb) > 0) and (n >= SRI(srRewardBomb)) then s := 'bomb';
      TBeadGame.SurvivalRefill(n, iron, bonus);
      mTable.Lines.Add(Format('%3d %8d  %-6s %s', [n, Round(p), s,
        IfThen(iron > 0, IntToStr(iron) + 'Fe', IfThen(bonus > 0, '+' + IntToStr(bonus) + 'B', ''))]));
    end;
    mTable.Lines.Add('');
    mTable.Lines.Add('Time attack: +1/+2/+3 s at');
    mTable.Lines.Add(Format('  %d / %d / %d beads', [SRI(srTime1Size), SRI(srTime2Size), SRI(srTime3Size)]));
    mTable.Lines.Add('Chain multiplier:');
    s := '';
    for k := 1 to 6 do s += Format(' x%s', [FormatFloat('0.0#', 1 + SR[srChainStep] * (Min(k, SRI(srChainMax)) - 1), FS)]);
    mTable.Lines.Add(' ' + s + ' ...');
    mTable.Lines.Add('Level end: ' + Fmt(SR[srGoalBead], False) + ' / bead under goal');
    mTable.Lines.Add('  cleared +' + Fmt(SR[srClearBonus], False));
  finally
    mTable.Lines.EndUpdate;
  end;
end;

{ ---- files }

function TRulesForm.AskSave: Boolean;
begin
  Result := True;
  if not FDirty then Exit;
  case MessageDlg('Save changes?', 'The rules changed. Save them first?', mtConfirmation,
    [mbYes, mbNo, mbCancel], 0) of
    mrYes: SaveClick(nil);
    mrCancel: Result := False;
  end;
end;

procedure TRulesForm.NewClick(Sender: TObject);
begin
  if not AskSave then Exit;
  DefaultRules(FKind);
  ShowValues;
  Changed;
  lblStatus.Caption := 'The original rules (not saved yet).';
end;

procedure TRulesForm.OpenClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  if not AskSave then Exit;
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := Format('Neon Beads rules (*%s)|*%s|All files|*.*', [RulesExt(FKind), RulesExt(FKind)]);
    dlg.InitialDir := ExtractFilePath(FFile);
    if dlg.Execute then
    begin
      if LoadRulesFile(FKind, dlg.FileName) then
      begin
        SetFileName(dlg.FileName);
        ShowValues;
        FDirty := False;
        lblStatus.Caption := 'Opened ' + dlg.FileName;
      end
      else
        MessageDlg('Open', 'Could not read ' + dlg.FileName, mtError, [mbOK], 0);
    end;
  finally
    dlg.Free;
  end;
end;

procedure TRulesForm.SaveClick(Sender: TObject);
begin
  try
    SaveRulesFile(FKind, FFile);
    FDirty := False;
    lblStatus.Caption := 'Saved ' + FFile + '  (a running Neon Beads takes it within half a second)';
  except
    on E: Exception do MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TRulesForm.SaveAsClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := Format('Neon Beads rules (*%s)|*%s|All files|*.*', [RulesExt(FKind), RulesExt(FKind)]);
    dlg.DefaultExt := Copy(RulesExt(FKind), 2, 20);
    dlg.InitialDir := ExtractFilePath(FFile);
    dlg.FileName := ExtractFileName(FFile);
    dlg.Options := dlg.Options + [ofOverwritePrompt];
    if dlg.Execute then
    begin
      SetFileName(dlg.FileName);
      SaveClick(nil);
      if not SameFileName(ExpandFileName(dlg.FileName), DefaultFile(FKind)) then
        lblStatus.Caption := lblStatus.Caption + '  - the game reads ' + ExtractFileName(DefaultFile(FKind)) +
          ' only (Save As there, or copy the file)';
    end;
  finally
    dlg.Free;
  end;
end;

procedure TRulesForm.ReloadClick(Sender: TObject);
begin
  if FDirty and (MessageDlg('Reload', 'Discard the changes that are not saved?', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes) then Exit;
  SaveTimer.Enabled := False;
  if LoadRulesFile(FKind, FFile) then lblStatus.Caption := 'Reloaded ' + FFile + ' at ' + TimeToStr(Now)
  else
  begin
    DefaultRules(FKind);
    lblStatus.Caption := 'No file ' + FFile + ': the original rules.';
  end;
  ShowValues;
  FDirty := False;
end;

procedure TRulesForm.LiveSave(Sender: TObject);
begin
  SaveTimer.Enabled := False;
  SaveClick(nil);
end;

procedure TRulesForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FRunning then
  begin
    FCancel := True;
    CanClose := False;
    Exit;
  end;
  CanClose := AskSave;
end;

{ ---- simulation }

procedure TRulesForm.RunClick(Sender: TObject);
begin
  if FRunning then
  begin
    FCancel := True;
    Exit;
  end;
  FRunning := True;
  FCancel := False;
  btnRun.Caption := 'Stop';
  try
    if FKind = rkScoring then RunScoring else RunVersus;
  finally
    FRunning := False;
    btnRun.Caption := 'Simulate';
    lblProgress.Caption := '';
  end;
end;

type
  TScoreStats = record
    N, Passed, Stars3, Stars2, Stars1: Integer;
    Scores: array of Integer;
    SumScore, SumPops, SumGroup, SumBonus, SumSecs, SumIron, SumBoards, SumSpecials: Double;
    MaxGroup: Integer;
  end;

procedure AddGame(var S: TScoreStats; const G: TSimGame);
begin
  Inc(S.N);
  SetLength(S.Scores, S.N);
  S.Scores[S.N - 1] := G.Score;
  S.SumScore += G.Score;
  S.SumPops += G.Pops;
  S.SumGroup += G.AvgGroup;
  S.SumBonus += G.Bonus;
  S.SumSecs += G.Seconds;
  S.SumIron += G.Iron;
  S.SumBoards += G.Boards;
  S.SumSpecials += G.Specials;
  S.MaxGroup := Max(S.MaxGroup, G.MaxGroup);
  if G.Passed then Inc(S.Passed);
  case G.Stars of
    3: Inc(S.Stars3);
    2: Inc(S.Stars2);
    1: Inc(S.Stars1);
  end;
end;

function NumFmt(ADec: Integer): string;
begin
  Result := '#,##0';
  if ADec > 0 then Result += '.' + StringOfChar('0', ADec);
end;

{ a difference with its sign: +12 / -3 / 0 }
function DiffFmt(ADec: Integer): string;
begin
  Result := '+' + NumFmt(ADec) + ';-' + NumFmt(ADec) + ';0';
end;

function Median(const A: array of Integer): Integer;
var
  b: array of Integer;
  i, j, t: Integer;
begin
  if Length(A) = 0 then Exit(0);
  SetLength(b, Length(A));
  for i := 0 to High(A) do b[i] := A[i];
  for i := 1 to High(b) do
  begin
    t := b[i];
    j := i - 1;
    while (j >= 0) and (b[j] > t) do
    begin
      b[j + 1] := b[j];
      Dec(j);
    end;
    b[j + 1] := t;
  end;
  Result := b[Length(b) div 2];
end;

function MinOf(const A: array of Integer): Integer;
var
  i: Integer;
begin
  if Length(A) = 0 then Exit(0);
  Result := A[0];
  for i := 1 to High(A) do Result := Min(Result, A[i]);
end;

function MaxOf(const A: array of Integer): Integer;
var
  i: Integer;
begin
  if Length(A) = 0 then Exit(0);
  Result := A[0];
  for i := 1 to High(A) do Result := Max(Result, A[i]);
end;

procedure TRulesForm.RunScoring;
var
  cur, org: TScoreStats;
  i, n, mode, lvl, pol, k: Integer;
  keep: array[0..ScoreRuleCount - 1] of Single;
  secs: Single;
  cmp: Boolean;

  procedure Line(const ACap: string; A, B: Double; ADec: Integer = 0);
  begin
    if cmp then
      mResult.Lines.Add(Format('%-20s %10s %10s %8s', [ACap, FormatFloat(NumFmt(ADec), A, FS),
        FormatFloat(NumFmt(ADec), B, FS), FormatFloat(DiffFmt(ADec), A - B, FS)]))
    else
      mResult.Lines.Add(Format('%-20s %10s', [ACap, FormatFloat(NumFmt(ADec), A, FS)]));
  end;

  function Avg(V: Double; const S: TScoreStats): Double;
  begin
    if S.N > 0 then Result := V / S.N else Result := 0;
  end;

begin
  n := seCount.Value;
  mode := cbMode.ItemIndex;
  lvl := seLevel.Value;
  pol := cbPolicy.ItemIndex;
  secs := seMoveSecs.Value;
  cmp := chkCompare.Checked;
  cur := Default(TScoreStats);
  org := Default(TScoreStats);
  for i := 0 to ScoreRuleCount - 1 do keep[i] := SR[i];
  try
    for i := 1 to n do
    begin
      if FCancel then Break;
      { the same board (seed) for both rule sets }
      for k := 0 to ScoreRuleCount - 1 do SR[k] := keep[k];
      AddGame(cur, SimSingle(mode, lvl, pol, secs, 1000 + i * 7));
      if cmp then
      begin
        for k := 0 to ScoreRuleCount - 1 do SR[k] := ScoreRules[k].Def;
        AddGame(org, SimSingle(mode, lvl, pol, secs, 1000 + i * 7));
      end;
      lblProgress.Caption := Format('game %d / %d', [i, n]);
      Application.ProcessMessages;
    end;
  finally
    for i := 0 to ScoreRuleCount - 1 do SR[i] := keep[i];
  end;

  mResult.Lines.BeginUpdate;
  try
    mResult.Clear;
    mResult.Lines.Add(Format('%s, %s, %d games%s', [ModeNames[mode], PolicyNames[pol], cur.N,
      IfThen(mode = 0, ', level ' + IntToStr(lvl), '')]));
    mResult.Lines.Add('');
    if cmp then mResult.Lines.Add(Format('%-20s %10s %10s %8s', ['', 'these rules', 'original', 'diff']))
    else mResult.Lines.Add(Format('%-20s %10s', ['', 'these rules']));
    Line('average score', Avg(cur.SumScore, cur), Avg(org.SumScore, org));
    Line('median score', Median(cur.Scores), Median(org.Scores));
    Line('lowest score', MinOf(cur.Scores), MinOf(org.Scores));
    Line('highest score', MaxOf(cur.Scores), MaxOf(org.Scores));
    Line('moves per game', Avg(cur.SumPops, cur), Avg(org.SumPops, org), 1);
    Line('average group', Avg(cur.SumGroup, cur), Avg(org.SumGroup, org), 2);
    Line('biggest group', cur.MaxGroup, org.MaxGroup);
    Line('specials set off', Avg(cur.SumSpecials, cur), Avg(org.SumSpecials, org), 1);
    case mode of
      0:
        begin
          Line('level passed %', 100 * Avg(cur.Passed, cur), 100 * Avg(org.Passed, org), 1);
          Line('3 stars %', 100 * Avg(cur.Stars3, cur), 100 * Avg(org.Stars3, org), 1);
          Line('2 stars %', 100 * Avg(cur.Stars2, cur), 100 * Avg(org.Stars2, org), 1);
          Line('1 star %', 100 * Avg(cur.Stars1, cur), 100 * Avg(org.Stars1, org), 1);
          Line('level bonus', Avg(cur.SumBonus, cur), Avg(org.SumBonus, org));
        end;
      1:
        begin
          Line('boards per game', Avg(cur.SumBoards, cur), Avg(org.SumBoards, org), 1);
          Line('game length (s)', Avg(cur.SumSecs, cur), Avg(org.SumSecs, org), 1);
        end;
      2:
        begin
          Line('game length (s)', Avg(cur.SumSecs, cur), Avg(org.SumSecs, org), 1);
          Line('iron per game', Avg(cur.SumIron, cur), Avg(org.SumIron, org), 1);
        end;
    end;
    if FCancel then mResult.Lines.Add('(stopped)');
  finally
    mResult.Lines.EndUpdate;
  end;

  { histogram of the scores (both rule sets on the same bins) }
  FHistLo := Min(MinOf(cur.Scores), IfThen(cmp, MinOf(org.Scores), MaxInt));
  FHistHi := Max(MaxOf(cur.Scores), IfThen(cmp, MaxOf(org.Scores), 0));
  if FHistHi <= FHistLo then FHistHi := FHistLo + 1;
  SetLength(FHistCur, 20);
  SetLength(FHistOrg, 20);
  for i := 0 to 19 do
  begin
    FHistCur[i] := 0;
    FHistOrg[i] := 0;
  end;
  for i := 0 to High(cur.Scores) do
    Inc(FHistCur[Min(19, Trunc((cur.Scores[i] - FHistLo) / (FHistHi - FHistLo) * 20))]);
  if cmp then
    for i := 0 to High(org.Scores) do
      Inc(FHistOrg[Min(19, Trunc((org.Scores[i] - FHistLo) / (FHistHi - FHistLo) * 20))]);
  SetLength(FLine, 0);
  pbChart.Invalidate;
end;

procedure TRulesForm.RunVersus;
type
  TVsStats = record
    N, WinA, WinB, Draw, TimeOut: Integer;
    SA, SB, Gap, IronA, IronB, Secs, IronOn, LeadA, LeadB: Double;
  end;
var
  cur, org: TVsStats;
  i, k, n, la, lb: Integer;
  keep: array[0..VsRuleCount - 1] of Single;
  maxs: Single;
  cmp: Boolean;
  r: TVsSim;

  procedure Add(var S: TVsStats; const M: TVsSim);
  begin
    Inc(S.N);
    case M.Winner of
      1: Inc(S.WinA);
      2: Inc(S.WinB);
      3: Inc(S.Draw);
    else
      Inc(S.TimeOut);
    end;
    S.SA += M.ScoreA;
    S.SB += M.ScoreB;
    S.Gap += Abs(M.ScoreA - M.ScoreB);
    S.IronA += M.SentA;
    S.IronB += M.SentB;
    S.Secs += M.Seconds;
    S.IronOn += M.IronOnSecs;
    S.LeadA += M.LeadASecs;
    S.LeadB += M.LeadBSecs;
  end;

  function Av(V: Double; const S: TVsStats): Double;
  begin
    if S.N > 0 then Result := V / S.N else Result := 0;
  end;

  procedure Line(const ACap: string; A, B: Double; ADec: Integer = 0);
  begin
    if cmp then
      mResult.Lines.Add(Format('%-27s %9s %9s %8s', [ACap, FormatFloat(NumFmt(ADec), A, FS),
        FormatFloat(NumFmt(ADec), B, FS), FormatFloat(DiffFmt(ADec), A - B, FS)]))
    else
      mResult.Lines.Add(Format('%-27s %9s', [ACap, FormatFloat(NumFmt(ADec), A, FS)]));
  end;

begin
  n := seCount.Value;
  la := cbLeft.ItemIndex;
  lb := cbRight.ItemIndex;
  maxs := seMaxSecs.Value;
  cmp := chkCompare.Checked;
  cur := Default(TVsStats);
  org := Default(TVsStats);
  for i := 0 to VsRuleCount - 1 do keep[i] := VR[i];
  try
    for i := 1 to n do
    begin
      if FCancel then Break;
      for k := 0 to VsRuleCount - 1 do VR[k] := keep[k];
      r := SimVersus(la, lb, 5000 + i * 13, maxs, i = 1);
      Add(cur, r);
      if i = 1 then
      begin
        FLine := Copy(r.Timeline);
        FLineGap := VR[vrIronGap];
      end;
      if cmp then
      begin
        for k := 0 to VsRuleCount - 1 do VR[k] := VsRules[k].Def;
        Add(org, SimVersus(la, lb, 5000 + i * 13, maxs, False));
      end;
      lblProgress.Caption := Format('match %d / %d', [i, n]);
      Application.ProcessMessages;
    end;
  finally
    for i := 0 to VsRuleCount - 1 do VR[i] := keep[i];
  end;

  mResult.Lines.BeginUpdate;
  try
    mResult.Clear;
    mResult.Lines.Add(Format('%s (left) vs %s (right), %d matches', [BotNames[la], BotNames[lb], cur.N]));
    mResult.Lines.Add('');
    if cmp then mResult.Lines.Add(Format('%-27s %9s %9s %8s', ['', 'these rules', 'original', 'diff']))
    else mResult.Lines.Add(Format('%-27s %9s', ['', 'these rules']));
    Line('left wins %', 100 * Av(cur.WinA, cur), 100 * Av(org.WinA, org), 1);
    Line('right wins %', 100 * Av(cur.WinB, cur), 100 * Av(org.WinB, org), 1);
    Line('both out / time limit %', 100 * Av(cur.Draw + cur.TimeOut, cur), 100 * Av(org.Draw + org.TimeOut, org), 1);
    Line('left score', Av(cur.SA, cur), Av(org.SA, org));
    Line('right score', Av(cur.SB, cur), Av(org.SB, org));
    Line('final score gap', Av(cur.Gap, cur), Av(org.Gap, org));
    Line('iron sent by left', Av(cur.IronA, cur), Av(org.IronA, org), 1);
    Line('iron sent by right', Av(cur.IronB, cur), Av(org.IronB, org), 1);
    Line('match length (s)', Av(cur.Secs, cur), Av(org.Secs, org), 1);
    Line('time iron is on %', 100 * cur.IronOn / Max(1e-6, cur.Secs), 100 * org.IronOn / Max(1e-6, org.Secs), 1);
    Line('time left leads by gap+ %', 100 * cur.LeadA / Max(1e-6, cur.Secs), 100 * org.LeadA / Max(1e-6, org.Secs), 1);
    Line('time right leads by gap+ %', 100 * cur.LeadB / Max(1e-6, cur.Secs), 100 * org.LeadB / Max(1e-6, org.Secs), 1);
    mResult.Lines.Add('');
    mResult.Lines.Add('Chart: the scores of the first match (cyan left, pink right);');
    mResult.Lines.Add('yellow where the gap is over ' + IntToStr(Round(FLineGap)) + ' (iron on).');
    if FCancel then mResult.Lines.Add('(stopped)');
  finally
    mResult.Lines.EndUpdate;
  end;
  SetLength(FHistCur, 0);
  pbChart.Invalidate;
end;

procedure TRulesForm.ChartPaint(Sender: TObject);
var
  c: TCanvas;
  w, h, i, x0, x1, mx, n: Integer;
  bw, ymax, tmax, sx, sy: Double;

  function PX(T: Double): Integer;
  begin
    Result := 40 + Round(T * sx);
  end;

  function PY(V: Double): Integer;
  begin
    Result := h - 24 - Round(V * sy);
  end;

begin
  c := pbChart.Canvas;
  w := pbChart.Width;
  h := pbChart.Height;
  c.Brush.Color := RGBToColor(14, 16, 28);
  c.FillRect(0, 0, w, h);
  c.Font.Color := RGBToColor(190, 195, 210);
  c.Font.Size := 8;
  if Length(FHistCur) > 0 then
  begin
    { score histogram: these rules (cyan) and the original (grey) }
    mx := 1;
    for i := 0 to High(FHistCur) do mx := Max(mx, Max(FHistCur[i], FHistOrg[i]));
    bw := (w - 60) / Length(FHistCur);
    for i := 0 to High(FHistCur) do
    begin
      x0 := 40 + Round(i * bw);
      x1 := 40 + Round((i + 1) * bw) - 2;
      c.Brush.Color := RGBToColor(110, 110, 130);
      c.FillRect(x0, h - 24 - Round(FHistOrg[i] / mx * (h - 50)), (x0 + x1) div 2, h - 24);
      c.Brush.Color := RGBToColor(40, 210, 235);
      c.FillRect((x0 + x1) div 2, h - 24 - Round(FHistCur[i] / mx * (h - 50)), x1, h - 24);
    end;
    c.Brush.Style := bsClear;
    c.TextOut(40, 4, 'score histogram  (cyan: these rules, grey: original)');
    c.TextOut(40, h - 20, FormatFloat('#,##0', FHistLo));
    c.TextOut(w - 80, h - 20, FormatFloat('#,##0', FHistHi));
    c.Brush.Style := bsSolid;
  end
  else if Length(FLine) > 1 then
  begin
    { the first match: score lines, yellow where the iron is on }
    n := Length(FLine);
    tmax := Max(1, FLine[n - 1].T);
    ymax := 1;
    for i := 0 to n - 1 do ymax := Max(ymax, Max(FLine[i].A, FLine[i].B));
    sx := (w - 60) / tmax;
    sy := (h - 50) / ymax;
    for i := 0 to n - 2 do
      if (FLineGap = 0) or (Abs(FLine[i].A - FLine[i].B) > FLineGap) then
      begin
        c.Brush.Color := RGBToColor(70, 62, 20);
        c.FillRect(PX(FLine[i].T), 20, PX(FLine[i + 1].T) + 1, h - 24);
      end;
    c.Pen.Width := 2;
    c.Pen.Color := RGBToColor(40, 210, 235);
    c.MoveTo(PX(FLine[0].T), PY(FLine[0].A));
    for i := 1 to n - 1 do c.LineTo(PX(FLine[i].T), PY(FLine[i].A));
    c.Pen.Color := RGBToColor(235, 50, 150);
    c.MoveTo(PX(FLine[0].T), PY(FLine[0].B));
    for i := 1 to n - 1 do c.LineTo(PX(FLine[i].T), PY(FLine[i].B));
    c.Pen.Width := 1;
    c.Brush.Style := bsClear;
    c.TextOut(40, 4, 'first match: left (cyan) and right (pink) score; yellow = iron on');
    c.TextOut(4, PY(ymax) - 6, FormatFloat('#,##0', ymax));
    c.TextOut(w - 70, h - 20, FormatFloat('0', tmax) + ' s');
    c.Brush.Style := bsSolid;
  end
  else
  begin
    c.Brush.Style := bsClear;
    c.TextOut(40, 8, 'the chart of the simulation shows here');
    c.Brush.Style := bsSolid;
  end;
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := ',';

end.
