unit uSfxEditor;

{ Neon Sound Editor - designs the sound effects of Neon Beads and Neon Trail.

  Left: the 12 game sounds. Middle: the layers of the chosen sound (each a
  synthesized tone or noise burst, see uGameSfx). Right: the settings of the
  chosen layer. Bottom: the waveform of the whole sound (left / right) for
  the test parameter (the group size of a pop, the combo in Neon Trail).
  Play (F5) renders it with the game's own code; "play on change" plays it
  after every edit. Save writes the game's .sfx file; a running game
  reloads it. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Spin, Dialogs, LCLType,
  uGameSfx, uToolAudio;

type
  TSfxForm = class(TForm)
  private
    Audio: TToolAudio;
    FBank: TSfxBank;
    FFile: string;
    FSound, FLayer: Integer;
    FDirty, FUpdating: Boolean;
    FL, FR: TSfxData;
    cbGame, cbShape: TComboBox;
    lbSounds, lbLayers: TListBox;
    lblFile, lblInfo, lblLen, lblStatus: TLabel;
    seParam: TSpinEdit;
    chkAuto, chkPanAlt: TCheckBox;
    fse: array[0..17] of TFloatSpinEdit;
    seCount, seBase, seCDiv, seCMax: TSpinEdit;
    edSteps, edStepsEnd: TEdit;
    pbWave: TPaintBox;
    function Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer; AClick: TNotifyEvent): TButton;
    function Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
    procedure BuildUI;
    procedure OpenFile(const AFile: string);
    procedure ShowSound(AIndex: Integer);
    procedure ShowLayer(AIndex: Integer);
    procedure FillLayers;
    function LayerText(const L: TSfxLayer; AIndex: Integer): string;
    procedure Changed(Sender: TObject);
    procedure RenderPreview;
    procedure PlaySound;
    procedure GameChange(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure DefaultClick(Sender: TObject);
    procedure DefaultAllClick(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure ParamChange(Sender: TObject);
    procedure SoundClick(Sender: TObject);
    procedure LayerClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure WavePaint(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  SfxForm: TSfxForm;

implementation

const
  { float fields of a layer: caption, min, max, step, hint }
  FCount = 18;
  FNames: array[0..FCount - 1] of string = ('Start pitch (Hz)', 'End pitch (Hz)', 'Length (s)',
    'Attack (s)', 'Decay', 'Delay (s)', 'Gain', 'Pan', 'Noise click', 'Noise length (s)',
    'Repeat every (s)', 'Pan spread', 'Pitch per param (semitones)', 'Pitch max (semitones)',
    'Length per param (s)', 'Length max (s)', '', '');
  FMin: array[0..FCount - 1] of Double = (1, 1, 0.005, 0, 0, 0, 0, -1, 0, 0, 0, -1, -12, 0, 0, 0, 0, 0);
  FMax: array[0..FCount - 1] of Double = (20000, 20000, 5, 2, 50, 5, 2, 1, 2, 1, 2, 1, 12, 48, 0.2, 2, 0, 0);
  FInc: array[0..FCount - 1] of Double = (10, 10, 0.01, 0.002, 0.25, 0.01, 0.01, 0.1, 0.05, 0.002, 0.01,
    0.1, 0.5, 1, 0.005, 0.01, 0, 0);
  FHints: array[0..FCount - 1] of string = (
    'pitch at the start of the layer', 'pitch at the end (exponential glide)',
    'length of one note', 'linear fade-in time',
    'how fast the level falls after the attack (5 = the classic decay, higher = shorter)',
    'start time of the layer', 'level of the layer', 'stereo position: -1 left .. 1 right',
    'amount of the noise click mixed in at the start', 'length of the noise click',
    'time between repeats (Count)', 'stereo spread of the repeats',
    'pitch rise per parameter unit above Param base (the group size of a pop)',
    'cap of the pitch rise', 'extra length per parameter unit', 'cap of the extra length', '', '');
  FUsed = 16;

function GameFile(AGame: Integer): string;
begin
  if AGame = 2 then
    Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Shooter\NeonShooter.sfx')
  else if AGame = 1 then
    Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Trail\NeonTrail.sfx')
  else
    Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Game\NeonBeads.sfx');
end;

constructor TSfxForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner, 0);
  Caption := 'Neon Sound Editor';
  Width := 1240;
  Height := 820;
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnCloseQuery := @FormCloseQuery;
  Audio := TToolAudio.Create;
  BuildUI;
  cbGame.ItemIndex := 0;
  OpenFile(GameFile(0));
  if not Audio.Ok then lblStatus.Caption := 'No audio device: playback is off.';
end;

destructor TSfxForm.Destroy;
begin
  Audio.Free;
  inherited Destroy;
end;

function TSfxForm.Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AW, 26);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function TSfxForm.Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := AX;
  Result.Top := AY + 4;
  Result.Caption := ACaption;
end;

procedure TSfxForm.BuildUI;
var
  pTop, pLeft, pMid, pProps, pBtns: TPanel;
  i, y, x0: Integer;
  cap: TLabel;
  sh: TSfxShape;

  function Spin(AParent: TWinControl; AX, AY, AMin, AMax: Integer; const AHint: string): TSpinEdit;
  begin
    Result := TSpinEdit.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(AX, AY, 90, 24);
    Result.MinValue := AMin;
    Result.MaxValue := AMax;
    Result.Hint := AHint;
    Result.ShowHint := True;
    Result.OnChange := @Changed;
  end;

begin
  pTop := TPanel.Create(Self);
  pTop.Parent := Self;
  pTop.Align := alTop;
  pTop.Height := 40;
  pTop.BevelOuter := bvNone;
  Lbl(pTop, 'Game', 8, 8);
  cbGame := TComboBox.Create(Self);
  cbGame.Parent := pTop;
  cbGame.SetBounds(48, 8, 120, 24);
  cbGame.Style := csDropDownList;
  cbGame.Items.Add('Neon Beads');
  cbGame.Items.Add('Neon Trail');
  cbGame.Items.Add('Neon Shooter');
  cbGame.OnChange := @GameChange;
  Btn(pTop, 'Open...', 176, 7, 70, @OpenClick);
  Btn(pTop, 'Save', 250, 7, 60, @SaveClick);
  Btn(pTop, 'Save as...', 314, 7, 76, @SaveAsClick);
  Btn(pTop, 'Reload', 394, 7, 64, @ReloadClick);
  Btn(pTop, 'Default sound', 462, 7, 100, @DefaultClick);
  Btn(pTop, 'All defaults', 566, 7, 84, @DefaultAllClick);
  Btn(pTop, '> Play (F5)', 668, 7, 90, @PlayClick).Font.Style := [fsBold];
  Btn(pTop, 'Stop', 762, 7, 50, @StopClick);
  Lbl(pTop, 'Test param', 822, 8);
  seParam := TSpinEdit.Create(Self);
  seParam.Parent := pTop;
  seParam.SetBounds(890, 8, 60, 24);
  seParam.MinValue := 0;
  seParam.MaxValue := 99;
  seParam.Value := 2;
  seParam.Hint := 'the parameter the game passes: pop = group size, Neon Trail eat = combo';
  seParam.ShowHint := True;
  seParam.OnChange := @ParamChange;
  chkAuto := TCheckBox.Create(Self);
  chkAuto.Parent := pTop;
  chkAuto.SetBounds(962, 10, 120, 22);
  chkAuto.Caption := 'play on change';
  chkAuto.Checked := True;

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := Self;
  lblStatus.Align := alBottom;
  lblStatus.BorderSpacing.Around := 4;
  lblStatus.Caption := 'F5 plays the sound. Save writes the game file; a running game reloads it.';

  pbWave := TPaintBox.Create(Self);
  pbWave.Parent := Self;
  pbWave.Align := alBottom;
  pbWave.Height := 200;
  pbWave.OnPaint := @WavePaint;

  pLeft := TPanel.Create(Self);
  pLeft.Parent := Self;
  pLeft.Align := alLeft;
  pLeft.Width := 210;
  pLeft.BevelOuter := bvNone;
  cap := Lbl(pLeft, 'Sounds', 8, 0);
  cap.Align := alTop;
  cap.BorderSpacing.Around := 6;
  lbSounds := TListBox.Create(Self);
  lbSounds.Parent := pLeft;
  lbSounds.Align := alClient;
  lbSounds.BorderSpacing.Around := 6;
  for i := 0 to SfxCount - 1 do lbSounds.Items.Add(SfxNames[i]);
  lbSounds.OnClick := @SoundClick;
  lblInfo := TLabel.Create(Self);
  lblInfo.Parent := pLeft;
  lblInfo.Align := alBottom;
  lblInfo.WordWrap := True;
  lblInfo.AutoSize := True;
  lblInfo.BorderSpacing.Around := 6;
  lblInfo.Font.Color := clGrayText;

  pMid := TPanel.Create(Self);
  pMid.Parent := Self;
  pMid.Align := alLeft;
  pMid.Width := 280;
  pMid.BevelOuter := bvNone;
  cap := Lbl(pMid, 'Layers of the sound', 8, 0);
  cap.Align := alTop;
  cap.BorderSpacing.Around := 6;
  lbLayers := TListBox.Create(Self);
  lbLayers.Parent := pMid;
  lbLayers.Align := alClient;
  lbLayers.BorderSpacing.Around := 6;
  lbLayers.OnClick := @LayerClick;
  pBtns := TPanel.Create(Self);
  pBtns.Parent := pMid;
  pBtns.Align := alBottom;
  pBtns.Height := 36;
  pBtns.BevelOuter := bvNone;
  Btn(pBtns, 'Add', 6, 4, 58, @AddClick);
  Btn(pBtns, 'Copy', 66, 4, 58, @CopyClick);
  Btn(pBtns, 'Delete', 126, 4, 62, @DeleteClick);
  Btn(pBtns, 'Up', 190, 4, 64, @UpClick);
  Btn(pBtns, 'Down', 256, 4, 64, @DownClick);

  pProps := TPanel.Create(Self);
  pProps.Parent := Self;
  pProps.Align := alClient;
  pProps.BevelOuter := bvNone;
  Lbl(pProps, 'Shape', 8, 4);
  cbShape := TComboBox.Create(Self);
  cbShape.Parent := pProps;
  cbShape.SetBounds(190, 4, 110, 24);
  cbShape.Style := csDropDownList;
  for sh := Low(TSfxShape) to High(TSfxShape) do cbShape.Items.Add(ShapeNames[sh]);
  cbShape.OnChange := @Changed;
  y := 32;
  x0 := 0;
  for i := 0 to FUsed - 1 do
  begin
    if i = 10 then
    begin
      { second column: repeats and the game parameter }
      x0 := 330;
      y := 4;
      Lbl(pProps, 'Repeats (Count)', x0 + 8, y);
      seCount := Spin(pProps, x0 + 190, y, 0, 32, 'how many times the layer plays (arpeggio, echo); 0 = only from the parameter');
      Inc(y, 28);
    end;
    if i = 12 then
    begin
      Lbl(pProps, 'Steps (semitones)', x0 + 8, y);
      edSteps := TEdit.Create(Self);
      edSteps.Parent := pProps;
      edSteps.SetBounds(x0 + 190, y, 150, 24);
      edSteps.Hint := 'pitch offset of each repeat, e.g. 0 4 7 12 (a major arpeggio)';
      edSteps.ShowHint := True;
      edSteps.OnChange := @Changed;
      Inc(y, 28);
      Lbl(pProps, 'End steps (semitones)', x0 + 8, y);
      edStepsEnd := TEdit.Create(Self);
      edStepsEnd.Parent := pProps;
      edStepsEnd.SetBounds(x0 + 190, y, 150, 24);
      edStepsEnd.Hint := 'pitch offset of each repeat at its end (empty = like Steps)';
      edStepsEnd.ShowHint := True;
      edStepsEnd.OnChange := @Changed;
      Inc(y, 28);
      chkPanAlt := TCheckBox.Create(Self);
      chkPanAlt.Parent := pProps;
      chkPanAlt.SetBounds(x0 + 190, y + 2, 200, 22);
      chkPanAlt.Caption := 'repeats alternate left / right';
      chkPanAlt.OnClick := @Changed;
      Inc(y, 28);
      Lbl(pProps, 'Param base', x0 + 8, y);
      seBase := Spin(pProps, x0 + 190, y, 0, 99, 'parameter value that changes nothing (a pop of 2 beads)');
      Inc(y, 28);
    end;
    Lbl(pProps, FNames[i], x0 + 8, y);
    fse[i] := TFloatSpinEdit.Create(Self);
    fse[i].Parent := pProps;
    fse[i].SetBounds(x0 + 190, y, 110, 24);
    fse[i].MinValue := FMin[i];
    fse[i].MaxValue := FMax[i];
    fse[i].Increment := FInc[i];
    if FInc[i] < 0.01 then fse[i].DecimalPlaces := 4 else fse[i].DecimalPlaces := 3;
    fse[i].Hint := FHints[i];
    fse[i].ShowHint := True;
    fse[i].OnChange := @Changed;
    Inc(y, 28);
  end;
  Lbl(pProps, 'Extra repeats: param div', x0 + 8, y);
  seCDiv := Spin(pProps, x0 + 190, y, 0, 99, 'one extra repeat per this many parameter units (0 = off)');
  Inc(y, 28);
  Lbl(pProps, 'Extra repeats max', x0 + 8, y);
  seCMax := Spin(pProps, x0 + 190, y, 0, 32, 'cap of the extra repeats');
  lblLen := Lbl(pProps, '', 8, 320);
  lblLen.Font.Style := [fsBold];

  { docking order }
  pTop.Top := 0;
  pLeft.Left := 0;
  pMid.Left := 300;
  pbWave.Top := 5000;
  lblStatus.Top := 6000;
end;

{ ---- files }

procedure TSfxForm.OpenFile(const AFile: string);
begin
  FFile := AFile;
  FBank := DefaultSfxBank;
  if LoadSfxFile(AFile, FBank) then
    lblStatus.Caption := 'Loaded ' + AFile
  else
    lblStatus.Caption := 'No sound file yet - the built-in sounds are shown. Save writes ' + AFile;
  Caption := 'Neon Sound Editor - ' + AFile;
  FDirty := False;
  ShowSound(Max(0, FSound));
end;

procedure TSfxForm.GameChange(Sender: TObject);
begin
  if FDirty and (MessageDlg('Save changes?', 'Save the changed sounds before switching?', mtConfirmation,
    [mbYes, mbNo], 0) = mrYes) then SaveClick(nil);
  OpenFile(GameFile(cbGame.ItemIndex));
end;

procedure TSfxForm.OpenClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := 'Neon sounds (*.sfx)|*.sfx|All files|*.*';
    dlg.InitialDir := ExtractFilePath(FFile);
    if dlg.Execute then OpenFile(dlg.FileName);
  finally
    dlg.Free;
  end;
end;

procedure TSfxForm.SaveClick(Sender: TObject);
begin
  try
    SaveSfxFile(FFile, FBank);
    FDirty := False;
    lblStatus.Caption := 'Saved ' + FFile + '  (a running game reloads it)';
  except
    on E: Exception do MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TSfxForm.SaveAsClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := 'Neon sounds (*.sfx)|*.sfx';
    dlg.DefaultExt := 'sfx';
    dlg.FileName := FFile;
    if dlg.Execute then
    begin
      FFile := dlg.FileName;
      Caption := 'Neon Sound Editor - ' + FFile;
      SaveClick(nil);
    end;
  finally
    dlg.Free;
  end;
end;

procedure TSfxForm.ReloadClick(Sender: TObject);
begin
  OpenFile(FFile);
end;

procedure TSfxForm.DefaultClick(Sender: TObject);
var
  d: TSfxBank;
begin
  d := DefaultSfxBank;
  FBank[FSound] := d[FSound];
  FDirty := True;
  ShowSound(FSound);
  if chkAuto.Checked then PlaySound;
end;

procedure TSfxForm.DefaultAllClick(Sender: TObject);
begin
  if MessageDlg('Built-in sounds', 'Replace every sound with the built-in one?', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then Exit;
  FBank := DefaultSfxBank;
  FDirty := True;
  ShowSound(FSound);
end;

{ ---- sound / layer views }

function TSfxForm.LayerText(const L: TSfxLayer; AIndex: Integer): string;
begin
  if L.Shape = shNoise then
    Result := Format('%d. noise  %.2f s', [AIndex + 1, L.Dur])
  else
    Result := Format('%d. %s  %.0f > %.0f Hz  %.2f s', [AIndex + 1, ShapeNames[L.Shape], L.F0, L.F1, L.Dur]);
  if L.Count <> 1 then Result += Format('  x%d', [L.Count]);
  if L.ParamCountDiv > 0 then Result += '  +param';
  if L.Delay > 0 then Result += Format('  @%.2f s', [L.Delay]);
end;

procedure TSfxForm.FillLayers;
var
  i, keep: Integer;
begin
  keep := FLayer;
  lbLayers.Items.BeginUpdate;
  lbLayers.Items.Clear;
  for i := 0 to High(FBank[FSound].Layers) do lbLayers.Items.Add(LayerText(FBank[FSound].Layers[i], i));
  lbLayers.Items.EndUpdate;
  if keep >= lbLayers.Count then keep := lbLayers.Count - 1;
  FLayer := keep;
  if keep >= 0 then lbLayers.ItemIndex := keep;
end;

procedure TSfxForm.ShowSound(AIndex: Integer);
begin
  FSound := EnsureRange(AIndex, 0, SfxCount - 1);
  lbSounds.ItemIndex := FSound;
  lblInfo.Caption := SfxNames[FSound] + ': ' + SfxInfo[FSound];
  FLayer := 0;
  FillLayers;
  if Length(FBank[FSound].Layers) > 0 then ShowLayer(0) else ShowLayer(-1);
  RenderPreview;
end;

procedure TSfxForm.ShowLayer(AIndex: Integer);
var
  L: TSfxLayer;
  i: Integer;
  v: array[0..FCount - 1] of Single;
begin
  FLayer := AIndex;
  FUpdating := True;
  try
    if (AIndex < 0) or (AIndex > High(FBank[FSound].Layers)) then L := DefaultSfxLayer
    else L := FBank[FSound].Layers[AIndex];
    if AIndex >= 0 then lbLayers.ItemIndex := AIndex;
    cbShape.ItemIndex := Ord(L.Shape);
    v[0] := L.F0; v[1] := L.F1; v[2] := L.Dur; v[3] := L.Attack; v[4] := L.Decay; v[5] := L.Delay;
    v[6] := L.Gain; v[7] := L.Pan; v[8] := L.Noise; v[9] := L.NoiseDur; v[10] := L.Every; v[11] := L.PanSpread;
    v[12] := L.ParamSemis; v[13] := L.ParamSemisMax; v[14] := L.ParamDur; v[15] := L.ParamDurMax;
    for i := 0 to FUsed - 1 do fse[i].Value := v[i];
    seCount.Value := L.Count;
    edSteps.Text := L.Steps;
    edStepsEnd.Text := L.StepsEnd;
    chkPanAlt.Checked := L.PanAlt;
    seBase.Value := L.ParamBase;
    seCDiv.Value := L.ParamCountDiv;
    seCMax.Value := L.ParamCountMax;
  finally
    FUpdating := False;
  end;
end;

procedure TSfxForm.Changed(Sender: TObject);
var
  L: TSfxLayer;
begin
  if FUpdating or (FLayer < 0) or (FLayer > High(FBank[FSound].Layers)) then Exit;
  L := FBank[FSound].Layers[FLayer];
  L.Shape := TSfxShape(Max(0, cbShape.ItemIndex));
  L.F0 := fse[0].Value; L.F1 := fse[1].Value; L.Dur := fse[2].Value; L.Attack := fse[3].Value;
  L.Decay := fse[4].Value; L.Delay := fse[5].Value; L.Gain := fse[6].Value; L.Pan := fse[7].Value;
  L.Noise := fse[8].Value; L.NoiseDur := fse[9].Value; L.Every := fse[10].Value; L.PanSpread := fse[11].Value;
  L.ParamSemis := fse[12].Value; L.ParamSemisMax := fse[13].Value; L.ParamDur := fse[14].Value;
  L.ParamDurMax := fse[15].Value;
  L.Count := seCount.Value;
  L.Steps := edSteps.Text;
  L.StepsEnd := edStepsEnd.Text;
  L.PanAlt := chkPanAlt.Checked;
  L.ParamBase := seBase.Value;
  L.ParamCountDiv := seCDiv.Value;
  L.ParamCountMax := seCMax.Value;
  FBank[FSound].Layers[FLayer] := L;
  FDirty := True;
  lbLayers.Items[FLayer] := LayerText(L, FLayer);
  RenderPreview;
  if chkAuto.Checked and not (Sender is TEdit) then PlaySound;
end;

procedure TSfxForm.RenderPreview;
var
  pk: Single;
  i: Integer;
begin
  SfxMixStereo(FBank[FSound], seParam.Value, FL, FR);
  pk := 0;
  for i := 0 to High(FL) do pk := Max(pk, Max(Abs(FL[i]), Abs(FR[i])));
  lblLen.Caption := Format('%.2f s   peak %.2f   %d layers', [Length(FL) / SfxSR, pk, Length(FBank[FSound].Layers)]);
  pbWave.Invalidate;
end;

procedure TSfxForm.PlaySound;
begin
  Audio.StopSounds;
  Audio.PlayStereo(FL, FR);
end;

procedure TSfxForm.PlayClick(Sender: TObject);
begin
  RenderPreview;
  PlaySound;
end;

procedure TSfxForm.StopClick(Sender: TObject);
begin
  Audio.StopSounds;
end;

procedure TSfxForm.ParamChange(Sender: TObject);
begin
  RenderPreview;
  if chkAuto.Checked then PlaySound;
end;

procedure TSfxForm.SoundClick(Sender: TObject);
begin
  ShowSound(lbSounds.ItemIndex);
  PlaySound;
end;

procedure TSfxForm.LayerClick(Sender: TObject);
begin
  ShowLayer(lbLayers.ItemIndex);
end;

{ ---- layer list }

procedure TSfxForm.AddClick(Sender: TObject);
var
  n: Integer;
begin
  n := Length(FBank[FSound].Layers);
  if n >= MaxSfxLayers then Exit;
  SetLength(FBank[FSound].Layers, n + 1);
  FBank[FSound].Layers[n] := DefaultSfxLayer;
  FDirty := True;
  FLayer := n;
  FillLayers;
  ShowLayer(n);
  RenderPreview;
end;

procedure TSfxForm.CopyClick(Sender: TObject);
var
  n: Integer;
begin
  n := Length(FBank[FSound].Layers);
  if (FLayer < 0) or (n >= MaxSfxLayers) then Exit;
  SetLength(FBank[FSound].Layers, n + 1);
  FBank[FSound].Layers[n] := FBank[FSound].Layers[FLayer];
  FDirty := True;
  FLayer := n;
  FillLayers;
  ShowLayer(n);
  RenderPreview;
end;

procedure TSfxForm.DeleteClick(Sender: TObject);
var
  i: Integer;
begin
  if FLayer < 0 then Exit;
  for i := FLayer to High(FBank[FSound].Layers) - 1 do
    FBank[FSound].Layers[i] := FBank[FSound].Layers[i + 1];
  SetLength(FBank[FSound].Layers, Length(FBank[FSound].Layers) - 1);
  FDirty := True;
  FLayer := Min(FLayer, High(FBank[FSound].Layers));
  FillLayers;
  ShowLayer(FLayer);
  RenderPreview;
end;

procedure TSfxForm.UpClick(Sender: TObject);
var
  t: TSfxLayer;
begin
  if FLayer <= 0 then Exit;
  t := FBank[FSound].Layers[FLayer];
  FBank[FSound].Layers[FLayer] := FBank[FSound].Layers[FLayer - 1];
  FBank[FSound].Layers[FLayer - 1] := t;
  Dec(FLayer);
  FDirty := True;
  FillLayers;
  ShowLayer(FLayer);
end;

procedure TSfxForm.DownClick(Sender: TObject);
var
  t: TSfxLayer;
begin
  if (FLayer < 0) or (FLayer >= High(FBank[FSound].Layers)) then Exit;
  t := FBank[FSound].Layers[FLayer];
  FBank[FSound].Layers[FLayer] := FBank[FSound].Layers[FLayer + 1];
  FBank[FSound].Layers[FLayer + 1] := t;
  Inc(FLayer);
  FDirty := True;
  FillLayers;
  ShowLayer(FLayer);
end;

{ ---- waveform }

procedure TSfxForm.WavePaint(Sender: TObject);
var
  c: TCanvas;
  w, h, x, i, a, b, mid, ch: Integer;
  mn, mx, v: Single;
  data: TSfxData;
begin
  c := pbWave.Canvas;
  w := pbWave.Width;
  h := pbWave.Height;
  c.Brush.Color := $201814;
  c.FillRect(0, 0, w, h);
  if (Length(FL) = 0) or (w < 10) then Exit;
  for ch := 0 to 1 do
  begin
    if ch = 0 then data := FL else data := FR;
    mid := h div 4 + ch * (h div 2);
    c.Pen.Color := $403830;
    c.Line(0, mid, w, mid);
    if ch = 0 then c.Pen.Color := $F0D723 else c.Pen.Color := $9128E6;
    for x := 0 to w - 1 do
    begin
      a := Int64(x) * Length(data) div w;
      b := Max(a + 1, Int64(x + 1) * Length(data) div w);
      mn := 0; mx := 0;
      for i := a to Min(b, Length(data)) - 1 do
      begin
        v := data[i];
        if v < mn then mn := v;
        if v > mx then mx := v;
      end;
      c.Line(x, mid - Round(mx * h / 4.4), x, mid - Round(mn * h / 4.4) + 1);
    end;
  end;
  c.Brush.Style := bsClear;
  c.Font.Color := clSilver;
  c.TextOut(6, 4, 'L');
  c.TextOut(6, h div 2 + 4, 'R');
  { time marks every 0.1 s }
  c.Pen.Color := $504840;
  for i := 1 to Round(Length(FL) / SfxSR * 10) do
  begin
    x := Round(i * 0.1 * SfxSR / Length(FL) * w);
    c.Line(x, h - 8, x, h);
  end;
  c.Brush.Style := bsSolid;
end;

procedure TSfxForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_F5 then
  begin
    PlayClick(nil);
    Key := 0;
  end;
end;

procedure TSfxForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if not FDirty then Exit;
  case MessageDlg('Save changes?', 'The sounds changed. Save them before closing?', mtConfirmation,
    [mbYes, mbNo, mbCancel], 0) of
    mrYes: SaveClick(nil);
    mrCancel: CanClose := False;
  end;
end;

end.
