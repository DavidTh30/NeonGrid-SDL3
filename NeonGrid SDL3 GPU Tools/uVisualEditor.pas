unit uVisualEditor;

{ Neon Visual Editor - edits the .visuals files of Neon Beads and Neon Trail
  (background, board look, bead colours, animation, particle effects, score
  popups). The editor knows nothing about the games: it builds itself from
  the file, where every value is described by the line above it
  (";@kind|min|max|default|hint", see uParams), so values a game adds later
  show up here without changes.

  Left: categories and groups. Right: the values of the chosen group (or
  of every group matching the search) with a slider / number, a check box
  or a colour button, and a reset to the default. Save writes only the value
  lines back (comments and order stay). With "live" every change is saved at
  once and a running game shows it immediately.
  Example + Apply: copies the values of a ready-made file from
  NeonGrid SDL3 GPU Shared\Background Examples (moving backgrounds) into the
  open file - every key the example has, matched by group and key.
  GPU preview: starts the chosen game in its own window in preview mode
  ("--preview=FILE", see uPreview): it plays by itself with the real GPU
  shaders, and every change made here (not saved yet) reaches it within
  0.1 s through a copy of the values in the temp folder - the game's own
  .visuals is written only by Save / live. Keys in that window: 1 game,
  2 menu, 3 background only, Tab next, M sound, Esc close. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Spin, Dialogs,
  LCLIntf, LCLType, Process;

type
  TVKind = (vkFloat, vkInt, vkBool, vkColor);

  TVEntry = record
    Category, Group, Key, Hint, Value, Def: string;
    Kind: TVKind;
    MinV, MaxV: Double;
    Line: Integer;            // line of "Key=value" in the file
  end;

  TVisualForm = class(TForm)
  private
    FLines: TStringList;
    FE: array of TVEntry;
    FFile: string;
    FDirty, FUpdating: Boolean;
    FGroup: string;           // shown group ('' = search results)
    cbGame, cbExample: TComboBox;
    lblExample: TLabel;
    edSearch: TEdit;
    chkLive: TCheckBox;
    tvGroups: TTreeView;
    sbRows: TScrollBox;
    lblStatus, lblTitle: TLabel;
    SaveTimer, PrevTimer: TTimer;
    FPrev: array[0..2] of TProcess;   // GPU preview windows (one per game)
    FRowCtrls: TList;         // controls of the shown rows (freed on change)
    function Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer; AClick: TNotifyEvent): TButton;
    procedure BuildUI;
    procedure LoadFile(const AFile: string);
    procedure FillTree;
    procedure ShowRows;
    procedure ClearRows;
    procedure AddRow(AIndex: Integer; var Y: Integer);
    function FmtValue(AIndex: Integer; V: Double): string;
    function NumOf(const S: string; ADef: Double): Double;
    procedure SetValue(AIndex: Integer; const S: string);
    procedure Changed;
    procedure GameChange(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure GroupDefaultsClick(Sender: TObject);
    procedure AllDefaultsClick(Sender: TObject);
    procedure RunGameClick(Sender: TObject);
    procedure ApplyExampleClick(Sender: TObject);
    procedure PreviewClick(Sender: TObject);
    procedure PreviewTick(Sender: TObject);
    function PreviewRunning(AIndex: Integer): Boolean;
    procedure WritePreview;
    procedure ExampleChange(Sender: TObject);
    procedure FillExamples;
    function ExampleDir: string;
    procedure SearchChange(Sender: TObject);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure TrackChange(Sender: TObject);
    procedure SpinChange(Sender: TObject);
    procedure CheckChange(Sender: TObject);
    procedure ColorChange(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure LiveSave(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  VisualForm: TVisualForm;

implementation

var
  FS: TFormatSettings;

const
  Games: array[0..2] of string = ('..\NeonGrid SDL3 GPU Game\NeonBeads', '..\NeonGrid SDL3 GPU Trail\NeonTrail',
    '..\NeonGrid SDL3 GPU Shooter\NeonShooter');
  { control tags: entry index * 8 + part }
  tgTrack = 0;
  tgSpin = 1;
  tgCheck = 2;
  tgColor = 3;
  tgReset = 4;

function GameFile(AIndex: Integer): string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + Games[AIndex] + '.visuals');
end;

function GameExe(AIndex: Integer): string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + Games[AIndex] + '.exe');
end;

function HexToTColor(const S: string; ADef: TColor): TColor;
var
  t: string;
  v: Integer;
begin
  t := Trim(S);
  if (t <> '') and (t[1] = '#') then Delete(t, 1, 1);
  if (Length(t) = 6) and TryStrToInt('$' + t, v) then
    Result := RGBToColor((v shr 16) and 255, (v shr 8) and 255, v and 255)
  else
    Result := ADef;
end;

function TColorToHex(C: TColor): string;
begin
  C := ColorToRGB(C);
  Result := Format('#%.2X%.2X%.2X', [Red(C), Green(C), Blue(C)]);
end;

{ TVisualForm }

constructor TVisualForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner, 0);
  Caption := 'Neon Visual Editor';
  Width := 1130;
  Height := 820;
  Position := poScreenCenter;
  OnCloseQuery := @FormCloseQuery;
  FLines := TStringList.Create;
  FRowCtrls := TList.Create;
  BuildUI;
  cbGame.ItemIndex := 0;
  LoadFile(GameFile(0));
  FillExamples;
end;

destructor TVisualForm.Destroy;
var
  i: Integer;
begin
  { the preview windows belong to the editor }
  for i := 0 to High(FPrev) do
    if FPrev[i] <> nil then
    begin
      if FPrev[i].Running then FPrev[i].Terminate(0);
      FPrev[i].Free;
    end;
  FRowCtrls.Free;
  FLines.Free;
  inherited Destroy;
end;

function TVisualForm.Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AW, 26);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

procedure TVisualForm.BuildUI;
var
  pTop, pRight: TPanel;
  l: TLabel;
begin
  pTop := TPanel.Create(Self);
  pTop.Parent := Self;
  pTop.Align := alTop;
  pTop.Height := 72;
  pTop.BevelOuter := bvNone;
  l := TLabel.Create(Self);
  l.Parent := pTop;
  l.SetBounds(8, 12, 40, 20);
  l.Caption := 'Game';
  { second row: ready-made moving backgrounds }
  l := TLabel.Create(Self);
  l.Parent := pTop;
  l.SetBounds(8, 44, 60, 20);
  l.Caption := 'Example';
  cbExample := TComboBox.Create(Self);
  cbExample.Parent := pTop;
  cbExample.SetBounds(70, 40, 170, 24);
  cbExample.Style := csDropDownList;
  cbExample.OnChange := @ExampleChange;
  Btn(pTop, 'Apply example', 246, 39, 104, @ApplyExampleClick);
  lblExample := TLabel.Create(Self);
  lblExample.Parent := pTop;
  lblExample.SetBounds(360, 44, 700, 20);
  lblExample.Font.Color := clGrayText;
  cbGame := TComboBox.Create(Self);
  cbGame.Parent := pTop;
  cbGame.SetBounds(48, 8, 120, 24);
  cbGame.Style := csDropDownList;
  cbGame.Items.Add('Neon Beads');
  cbGame.Items.Add('Neon Trail');
  cbGame.Items.Add('Neon Shooter');
  cbGame.OnChange := @GameChange;
  Btn(pTop, 'Open...', 176, 7, 66, @OpenClick);
  Btn(pTop, 'Save', 246, 7, 56, @SaveClick);
  Btn(pTop, 'Reload', 306, 7, 60, @ReloadClick);
  Btn(pTop, 'Group defaults', 370, 7, 104, @GroupDefaultsClick);
  Btn(pTop, 'All defaults', 478, 7, 84, @AllDefaultsClick);
  Btn(pTop, 'Run game', 566, 7, 76, @RunGameClick);
  with Btn(pTop, 'GPU preview', 646, 7, 96, @PreviewClick) do
  begin
    Hint := 'The game in its own window, playing by itself: every change shows at once (no Save needed).';
    ShowHint := True;
  end;
  chkLive := TCheckBox.Create(Self);
  chkLive.Parent := pTop;
  chkLive.SetBounds(752, 10, 180, 22);
  chkLive.Caption := 'live (save every change)';
  chkLive.Hint := 'A running game reloads the file within half a second.';
  chkLive.ShowHint := True;
  l := TLabel.Create(Self);
  l.Parent := pTop;
  l.SetBounds(938, 12, 44, 20);
  l.Caption := 'Search';
  edSearch := TEdit.Create(Self);
  edSearch.Parent := pTop;
  edSearch.SetBounds(984, 8, 136, 24);
  edSearch.OnChange := @SearchChange;

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := Self;
  lblStatus.Align := alBottom;
  lblStatus.BorderSpacing.Around := 4;

  tvGroups := TTreeView.Create(Self);
  tvGroups.Parent := Self;
  tvGroups.Align := alLeft;
  tvGroups.Width := 250;
  tvGroups.ReadOnly := True;
  tvGroups.HideSelection := False;
  tvGroups.OnChange := @TreeChange;

  pRight := TPanel.Create(Self);
  pRight.Parent := Self;
  pRight.Align := alClient;
  pRight.BevelOuter := bvNone;
  lblTitle := TLabel.Create(Self);
  lblTitle.Parent := pRight;
  lblTitle.Align := alTop;
  lblTitle.BorderSpacing.Around := 6;
  lblTitle.Font.Style := [fsBold];
  lblTitle.Font.Height := -16;
  sbRows := TScrollBox.Create(Self);
  sbRows.Parent := pRight;
  sbRows.Align := alClient;
  sbRows.VertScrollBar.Tracking := True;

  SaveTimer := TTimer.Create(Self);
  SaveTimer.Interval := 300;
  SaveTimer.Enabled := False;
  SaveTimer.OnTimer := @LiveSave;
  PrevTimer := TTimer.Create(Self);
  PrevTimer.Interval := 40;
  PrevTimer.Enabled := False;
  PrevTimer.OnTimer := @PreviewTick;

  pTop.Top := 0;
  lblStatus.Top := 6000;
end;

{ ---- file }

procedure TVisualForm.LoadFile(const AFile: string);
var
  i, p, n: Integer;
  ln, cat, grp, meta: string;
  parts: TStringArray;
  e: TVEntry;
begin
  FFile := AFile;
  FLines.Clear;
  SetLength(FE, 0);
  if FileExists(AFile) then FLines.LoadFromFile(AFile);
  cat := '';
  grp := '';
  meta := '';
  for i := 0 to FLines.Count - 1 do
  begin
    ln := Trim(FLines[i]);
    if ln = '' then Continue;
    if Copy(ln, 1, 10) = ';@category' then
      cat := Trim(Copy(ln, 11, MaxInt))
    else if Copy(ln, 1, 2) = ';@' then
      meta := Copy(ln, 3, MaxInt)
    else if ln[1] = ';' then
      Continue
    else if (ln[1] = '[') and (ln[Length(ln)] = ']') then
    begin
      grp := Copy(ln, 2, Length(ln) - 2);
      meta := '';
    end
    else
    begin
      p := Pos('=', ln);
      if (p <= 1) or (meta = '') then Continue;
      parts := meta.Split(['|']);
      if Length(parts) < 5 then Continue;
      e := Default(TVEntry);
      e.Category := cat;
      e.Group := grp;
      e.Key := Trim(Copy(ln, 1, p - 1));
      e.Value := Trim(Copy(ln, p + 1, MaxInt));
      case LowerCase(parts[0]) of
        'int': e.Kind := vkInt;
        'bool': e.Kind := vkBool;
        'color': e.Kind := vkColor;
      else
        e.Kind := vkFloat;
      end;
      e.MinV := StrToFloatDef(parts[1], 0, FS);
      e.MaxV := StrToFloatDef(parts[2], 1, FS);
      e.Def := parts[3];
      e.Hint := parts[4];
      e.Line := i;
      n := Length(FE);
      SetLength(FE, n + 1);
      FE[n] := e;
      meta := '';
    end;
  end;
  FDirty := False;
  Caption := 'Neon Visual Editor - ' + AFile;
  if (cbGame <> nil) and PreviewRunning(cbGame.ItemIndex) then WritePreview;
  if Length(FE) = 0 then
    lblStatus.Caption := 'No values in ' + AFile + ' - run the game once: it writes the file.'
  else
    lblStatus.Caption := Format('%d values in %s', [Length(FE), AFile]);
  FillTree;
end;

procedure TVisualForm.FillTree;
var
  i: Integer;
  cat, grp: string;
  nCat, first: TTreeNode;
begin
  tvGroups.Items.BeginUpdate;
  try
    tvGroups.Items.Clear;
    cat := #0;
    grp := #0;
    nCat := nil;
    first := nil;
    for i := 0 to High(FE) do
    begin
      if FE[i].Category <> cat then
      begin
        cat := FE[i].Category;
        nCat := tvGroups.Items.Add(nil, cat);
      end;
      if FE[i].Group <> grp then
      begin
        grp := FE[i].Group;
        if first = nil then first := tvGroups.Items.AddChild(nCat, grp)
        else tvGroups.Items.AddChild(nCat, grp);
      end;
    end;
    tvGroups.FullExpand;
  finally
    tvGroups.Items.EndUpdate;
  end;
  if first <> nil then tvGroups.Selected := first;
end;

procedure TVisualForm.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if (Node = nil) or (Node.Level = 0) then Exit;
  FGroup := Node.Text;
  if edSearch.Text <> '' then
  begin
    FUpdating := True;
    edSearch.Text := '';
    FUpdating := False;
  end;
  ShowRows;
end;

procedure TVisualForm.SearchChange(Sender: TObject);
begin
  if FUpdating then Exit;
  if Trim(edSearch.Text) = '' then
  begin
    if tvGroups.Selected <> nil then TreeChange(nil, tvGroups.Selected);
    Exit;
  end;
  FGroup := '';
  ShowRows;
end;

{ ---- rows }

procedure TVisualForm.ClearRows;
var
  i: Integer;
begin
  for i := FRowCtrls.Count - 1 downto 0 do TControl(FRowCtrls[i]).Free;
  FRowCtrls.Clear;
end;

function TVisualForm.NumOf(const S: string; ADef: Double): Double;
begin
  if SameText(S, 'on') or SameText(S, 'true') then Exit(1);
  if SameText(S, 'off') or SameText(S, 'false') then Exit(0);
  Result := StrToFloatDef(Trim(S), ADef, FS);
end;

function TVisualForm.FmtValue(AIndex: Integer; V: Double): string;
begin
  case FE[AIndex].Kind of
    vkInt, vkBool: Result := IntToStr(Round(V));
  else
    Result := FormatFloat('0.####', V, FS);
  end;
end;

procedure TVisualForm.AddRow(AIndex: Integer; var Y: Integer);
var
  e: TVEntry;
  l: TLabel;
  tb: TTrackBar;
  fs: TFloatSpinEdit;
  si: TSpinEdit;
  ck: TCheckBox;
  cb: TColorButton;
  rb: TButton;
  v: Double;
  x: Integer;

  procedure Keep(C: TControl);
  begin
    FRowCtrls.Add(C);
  end;

begin
  e := FE[AIndex];
  x := 8;
  l := TLabel.Create(Self);
  l.Parent := sbRows;
  l.SetBounds(x, Y + 6, 200, 20);
  if FGroup = '' then l.Caption := e.Group + ': ' + e.Key else l.Caption := e.Key;
  l.Hint := e.Hint;
  l.ShowHint := True;
  Keep(l);
  v := NumOf(e.Value, NumOf(e.Def, 0));
  case e.Kind of
    vkBool:
      begin
        ck := TCheckBox.Create(Self);
        ck.Parent := sbRows;
        ck.SetBounds(x + 210, Y + 4, 300, 22);
        ck.Checked := v >= 0.5;
        ck.Caption := e.Hint;
        ck.Tag := AIndex * 8 + tgCheck;
        ck.OnClick := @CheckChange;
        Keep(ck);
      end;
    vkColor:
      begin
        cb := TColorButton.Create(Self);
        cb.Parent := sbRows;
        cb.SetBounds(x + 210, Y + 1, 110, 28);
        cb.ButtonColor := HexToTColor(e.Value, clBlack);
        cb.Tag := AIndex * 8 + tgColor;
        cb.OnColorChanged := @ColorChange;
        cb.Hint := e.Hint;
        cb.ShowHint := True;
        Keep(cb);
        l := TLabel.Create(Self);
        l.Parent := sbRows;
        l.SetBounds(x + 330, Y + 6, 320, 20);
        l.Caption := e.Value + '   ' + e.Hint;
        l.Font.Color := clGrayText;
        Keep(l);
      end;
  else
    begin
      tb := TTrackBar.Create(Self);
      tb.Parent := sbRows;
      tb.SetBounds(x + 210, Y, 300, 28);
      tb.Max := 1000;
      tb.TickStyle := tsNone;
      if e.MaxV > e.MinV then tb.Position := Round((EnsureRange(v, e.MinV, e.MaxV) - e.MinV) / (e.MaxV - e.MinV) * 1000);
      tb.Tag := AIndex * 8 + tgTrack;
      tb.Hint := e.Hint;
      tb.ShowHint := True;
      tb.OnChange := @TrackChange;
      Keep(tb);
      if e.Kind = vkInt then
      begin
        si := TSpinEdit.Create(Self);
        si.Parent := sbRows;
        si.SetBounds(x + 516, Y + 2, 90, 24);
        si.MinValue := Round(e.MinV);
        si.MaxValue := Round(e.MaxV);
        si.Value := Round(v);
        si.Tag := AIndex * 8 + tgSpin;
        si.OnChange := @SpinChange;
        Keep(si);
      end
      else
      begin
        fs := TFloatSpinEdit.Create(Self);
        fs.Parent := sbRows;
        fs.SetBounds(x + 516, Y + 2, 90, 24);
        fs.DecimalPlaces := 4;
        fs.MinValue := e.MinV;
        fs.MaxValue := e.MaxV;
        fs.Increment := Max(0.0001, (e.MaxV - e.MinV) / 200);
        fs.Value := v;
        fs.Tag := AIndex * 8 + tgSpin;
        fs.OnChange := @SpinChange;
        Keep(fs);
      end;
    end;
  end;
  rb := TButton.Create(Self);
  rb.Parent := sbRows;
  rb.SetBounds(x + 612, Y + 2, 30, 24);
  rb.Caption := '<>';
  rb.Hint := 'Back to the default: ' + e.Def;
  rb.ShowHint := True;
  rb.Tag := AIndex * 8 + tgReset;
  rb.OnClick := @ResetClick;
  Keep(rb);
  if (e.Kind <> vkBool) and (e.Kind <> vkColor) then
  begin
    l := TLabel.Create(Self);
    l.Parent := sbRows;
    l.SetBounds(x + 650, Y + 6, 400, 20);
    l.Caption := e.Hint;
    l.Font.Color := clGrayText;
    Keep(l);
  end;
  Inc(Y, 32);
end;

procedure TVisualForm.ShowRows;
var
  i, y, n: Integer;
  q: string;
begin
  sbRows.DisableAutoSizing;
  try
    ClearRows;
    sbRows.VertScrollBar.Position := 0;
    y := 6;
    n := 0;
    q := LowerCase(Trim(edSearch.Text));
    FUpdating := True;
    for i := 0 to High(FE) do
      if ((FGroup <> '') and (FE[i].Group = FGroup)) or
        ((FGroup = '') and (q <> '') and ((Pos(q, LowerCase(FE[i].Key)) > 0) or (Pos(q, LowerCase(FE[i].Group)) > 0)
         or (Pos(q, LowerCase(FE[i].Hint)) > 0))) then
      begin
        AddRow(i, y);
        Inc(n);
        if n >= 200 then Break;
      end;
    FUpdating := False;
  finally
    sbRows.EnableAutoSizing;
  end;
  if FGroup <> '' then lblTitle.Caption := FGroup
  else lblTitle.Caption := Format('Search "%s": %d values', [edSearch.Text, n]);
end;

{ ---- edits }

procedure TVisualForm.SetValue(AIndex: Integer; const S: string);
begin
  if FE[AIndex].Value = S then Exit;
  FE[AIndex].Value := S;
  FLines[FE[AIndex].Line] := FE[AIndex].Key + '=' + S;
  Changed;
end;

procedure TVisualForm.Changed;
begin
  FDirty := True;
  lblStatus.Caption := 'Changed (not saved yet)';
  { the GPU preview follows every change (a few per second while dragging) }
  if PreviewRunning(cbGame.ItemIndex) then PrevTimer.Enabled := True;
  if chkLive.Checked then
  begin
    SaveTimer.Enabled := False;
    SaveTimer.Enabled := True;
  end;
end;

function FindTagged(AList: TList; ATag: Integer): TControl;
var
  i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if TControl(AList[i]).Tag = ATag then Exit(TControl(AList[i]));
  Result := nil;
end;

procedure TVisualForm.TrackChange(Sender: TObject);
var
  k: Integer;
  v: Double;
  c: TControl;
begin
  if FUpdating then Exit;
  k := TTrackBar(Sender).Tag div 8;
  with FE[k] do v := MinV + (MaxV - MinV) * TTrackBar(Sender).Position / 1000;
  if FE[k].Kind = vkInt then v := Round(v);
  SetValue(k, FmtValue(k, v));
  c := FindTagged(FRowCtrls, k * 8 + tgSpin);
  FUpdating := True;
  if c is TSpinEdit then TSpinEdit(c).Value := Round(v)
  else if c is TFloatSpinEdit then TFloatSpinEdit(c).Value := v;
  FUpdating := False;
end;

procedure TVisualForm.SpinChange(Sender: TObject);
var
  k: Integer;
  v: Double;
  c: TControl;
begin
  if FUpdating then Exit;
  k := TControl(Sender).Tag div 8;
  if Sender is TSpinEdit then v := TSpinEdit(Sender).Value else v := TFloatSpinEdit(Sender).Value;
  SetValue(k, FmtValue(k, v));
  c := FindTagged(FRowCtrls, k * 8 + tgTrack);
  FUpdating := True;
  if (c is TTrackBar) and (FE[k].MaxV > FE[k].MinV) then
    TTrackBar(c).Position := Round((EnsureRange(v, FE[k].MinV, FE[k].MaxV) - FE[k].MinV) / (FE[k].MaxV - FE[k].MinV) * 1000);
  FUpdating := False;
end;

procedure TVisualForm.CheckChange(Sender: TObject);
begin
  if FUpdating then Exit;
  SetValue(TCheckBox(Sender).Tag div 8, IntToStr(Ord(TCheckBox(Sender).Checked)));
end;

procedure TVisualForm.ColorChange(Sender: TObject);
begin
  if FUpdating then Exit;
  SetValue(TColorButton(Sender).Tag div 8, TColorToHex(TColorButton(Sender).ButtonColor));
end;

procedure TVisualForm.ResetClick(Sender: TObject);
var
  k: Integer;
begin
  k := TButton(Sender).Tag div 8;
  SetValue(k, FE[k].Def);
  ShowRows;
end;

procedure TVisualForm.GroupDefaultsClick(Sender: TObject);
var
  i: Integer;
begin
  if FGroup = '' then Exit;
  for i := 0 to High(FE) do
    if FE[i].Group = FGroup then SetValue(i, FE[i].Def);
  ShowRows;
end;

procedure TVisualForm.AllDefaultsClick(Sender: TObject);
var
  i: Integer;
begin
  if MessageDlg('Defaults', 'Set every value of this file back to its default?', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then Exit;
  for i := 0 to High(FE) do SetValue(i, FE[i].Def);
  ShowRows;
end;

{ ---- file actions }

procedure TVisualForm.SaveClick(Sender: TObject);
begin
  try
    FLines.SaveToFile(FFile);
    FDirty := False;
    lblStatus.Caption := 'Saved ' + FFile + '  (a running game reloads it)';
  except
    on E: Exception do MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TVisualForm.LiveSave(Sender: TObject);
begin
  SaveTimer.Enabled := False;
  SaveClick(nil);
end;

procedure TVisualForm.ReloadClick(Sender: TObject);
begin
  LoadFile(FFile);
end;

procedure TVisualForm.GameChange(Sender: TObject);
begin
  if FDirty and (MessageDlg('Save changes?', 'Save the changed values before switching?', mtConfirmation,
    [mbYes, mbNo], 0) = mrYes) then SaveClick(nil);
  LoadFile(GameFile(cbGame.ItemIndex));
end;

procedure TVisualForm.OpenClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := 'Neon visuals (*.visuals)|*.visuals|All files|*.*';
    dlg.InitialDir := ExtractFilePath(FFile);
    if dlg.Execute then LoadFile(dlg.FileName);
  finally
    dlg.Free;
  end;
end;

procedure TVisualForm.RunGameClick(Sender: TObject);
var
  exe: string;
begin
  exe := GameExe(cbGame.ItemIndex);
  if FDirty then SaveClick(nil);
  if FileExists(exe) then OpenDocument(exe)
  else MessageDlg('Run game', 'Not found: ' + exe, mtError, [mbOK], 0);
end;

{ ---- GPU preview: the game in --preview mode (uPreview) }

function PreviewFile(AIndex: Integer): string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    ChangeFileExt(ExtractFileName(GameFile(AIndex)), '') + '-editor.visuals';
end;

function TVisualForm.PreviewRunning(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FPrev)) and (FPrev[AIndex] <> nil) and FPrev[AIndex].Running;
end;

procedure TVisualForm.WritePreview;
begin
  try
    FLines.SaveToFile(PreviewFile(cbGame.ItemIndex));
  except
    { the game is reading it: the next change writes it again }
    PrevTimer.Enabled := True;
  end;
end;

procedure TVisualForm.PreviewTick(Sender: TObject);
begin
  PrevTimer.Enabled := False;
  if PreviewRunning(cbGame.ItemIndex) then WritePreview;
end;

procedure TVisualForm.PreviewClick(Sender: TObject);
var
  k: Integer;
  exe: string;
begin
  k := cbGame.ItemIndex;
  if PreviewRunning(k) then
  begin
    WritePreview;
    lblStatus.Caption := 'The GPU preview of ' + cbGame.Text + ' is open already (it shows every change).';
    Exit;
  end;
  exe := GameExe(k);
  if not FileExists(exe) then
  begin
    MessageDlg('GPU preview', 'Not found: ' + exe, mtError, [mbOK], 0);
    Exit;
  end;
  WritePreview;
  FreeAndNil(FPrev[k]);
  FPrev[k] := TProcess.Create(nil);
  FPrev[k].Executable := exe;
  FPrev[k].Parameters.Add('--preview=' + PreviewFile(k));
  FPrev[k].CurrentDirectory := ExtractFilePath(exe);
  FPrev[k].Options := [];
  try
    FPrev[k].Execute;
    lblStatus.Caption := 'GPU preview of ' + cbGame.Text + ': every change shows at once.  ' +
      'In its window: 1 game, 2 menu, 3 background only, Tab next, M sound, Esc close.';
  except
    on E: Exception do
    begin
      FreeAndNil(FPrev[k]);
      MessageDlg('GPU preview', E.Message, mtError, [mbOK], 0);
    end;
  end;
end;

{ ---- ready-made examples (NeonGrid SDL3 GPU Shared\Background Examples) }

function TVisualForm.ExampleDir: string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Shared\Background Examples\');
end;

procedure TVisualForm.FillExamples;
var
  sr: TSearchRec;
  names: TStringList;
begin
  names := TStringList.Create;
  try
    names.Sorted := True;
    if FindFirst(ExampleDir + '*.visuals', faAnyFile, sr) = 0 then
    begin
      repeat
        names.Add(ChangeFileExt(sr.Name, ''));
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    cbExample.Items.Assign(names);
  finally
    names.Free;
  end;
  if cbExample.Items.Count > 0 then cbExample.ItemIndex := 0;
  ExampleChange(nil);
end;

procedure TVisualForm.ExampleChange(Sender: TObject);
var
  sl: TStringList;
  f: string;
begin
  lblExample.Caption := '';
  if cbExample.ItemIndex < 0 then
  begin
    lblExample.Caption := 'no examples in ' + ExampleDir;
    Exit;
  end;
  f := ExampleDir + cbExample.Text + '.visuals';
  sl := TStringList.Create;
  try
    if FileExists(f) then sl.LoadFromFile(f);
    { line 2 of an example describes it }
    if sl.Count > 1 then lblExample.Caption := Trim(Copy(sl[1], 2, MaxInt));
  finally
    sl.Free;
  end;
end;

procedure TVisualForm.ApplyExampleClick(Sender: TObject);
var
  ex: TStringList;
  i, k, p, n: Integer;
  grp, ln, key, val: string;
begin
  if cbExample.ItemIndex < 0 then Exit;
  ex := TStringList.Create;
  try
    ex.LoadFromFile(ExampleDir + cbExample.Text + '.visuals');
    n := 0;
    grp := '';
    for i := 0 to ex.Count - 1 do
    begin
      ln := Trim(ex[i]);
      if (ln = '') or (ln[1] = ';') then Continue;
      if (ln[1] = '[') and (ln[Length(ln)] = ']') then
      begin
        grp := Copy(ln, 2, Length(ln) - 2);
        Continue;
      end;
      p := Pos('=', ln);
      if p <= 1 then Continue;
      key := Trim(Copy(ln, 1, p - 1));
      val := Trim(Copy(ln, p + 1, MaxInt));
      for k := 0 to High(FE) do
        if (FE[k].Group = grp) and (FE[k].Key = key) then
        begin
          SetValue(k, val);
          Inc(n);
          Break;
        end;
    end;
  finally
    ex.Free;
  end;
  ShowRows;
  if chkLive.Checked then
    lblStatus.Caption := Format('Example "%s" applied: %d values (live: the game shows it now).', [cbExample.Text, n])
  else
    lblStatus.Caption := Format('Example "%s" applied: %d values - Save (or tick live) to see it in the game.',
      [cbExample.Text, n]);
end;

procedure TVisualForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if not FDirty then Exit;
  case MessageDlg('Save changes?', 'Values changed. Save them before closing?', mtConfirmation,
    [mbYes, mbNo, mbCancel], 0) of
    mrYes: SaveClick(nil);
    mrCancel: CanClose := False;
  end;
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

end.
