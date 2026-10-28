unit uMusicEditor;

{ Neon Music Editor - composes the songs of Neon Beads and Neon Trail.

  Left: the song list. Top: song settings (tempo, key, scale, chords, kit,
  instruments with octave and level). Middle: the melody as a piano roll
  (rows = scale degrees over four octaves, columns = steps; left click sets /
  removes a note, right click toggles a hold "-" that lengthens the note
  before it). Bottom: the step patterns (arp chord tones 0-3, bass R / O / 5,
  comp and drum hits; left click cycles, right click clears; click a row name
  to mute that track while listening).
  Play runs the game's own music engine (uGameMusic); edits are heard at
  once. Save writes the game's .music file; a running game reloads it. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Spin,
  Dialogs, LCLType, uGameMusic, uToolAudio;

type
  TMusicForm = class(TForm)
  private
    Audio: TToolAudio;
    FFile: string;
    FCur: Integer;
    FDirty, FUpdating: Boolean;
    FTok: array of string;        // melody tokens, bars * steps
    FSpb: Integer;
    FPats: array[0..8] of string; // arp, bass, comp, kick, snare, clap, hat, open, shaker
    FLastPos: Integer;
    { controls }
    cbGame: TComboBox;
    lblFile, lblStatus: TLabel;
    lbSongs: TListBox;
    edName, edChords, edMelody: TEdit;
    seBPM, seSpb: TSpinEdit;
    fseSwing: TFloatSpinEdit;
    cbKey, cbKit: TComboBox;
    chkMinor, chkPad, chkCalm, chkMuteLead, chkMutePad: TCheckBox;
    cbWave: array[0..3] of TComboBox;     // lead, arp, bass, comp
    seOct: array[0..3] of TSpinEdit;
    fseGain: array[0..6] of TFloatSpinEdit;  // lead, arp, bass, comp, pad, drums, delay
    tbVolume: TTrackBar;
    lblBars: TLabel;
    pbRoll, pbGrid: TPaintBox;
    sbRoll: TScrollBox;
    Timer: TTimer;
    function Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer; AClick: TNotifyEvent): TButton;
    function Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
    procedure BuildUI;
    procedure GameChange(Sender: TObject);
    procedure OpenFile(const AFile: string; AGame: Integer);
    procedure FillList;
    procedure ShowSong(AIndex: Integer);
    procedure ParseSong(const S: TSongDef);
    function BuildSong: TSongDef;
    function MelodyText: string;
    procedure Changed(Sender: TObject);
    procedure SongClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure DefaultsClick(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure AddBarClick(Sender: TObject);
    procedure DelBarClick(Sender: TObject);
    procedure MelodyKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CalmClick(Sender: TObject);
    procedure MuteClick(Sender: TObject);
    procedure VolumeChange(Sender: TObject);
    procedure RollPaint(Sender: TObject);
    procedure RollMouse(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure GridPaint(Sender: TObject);
    procedure GridMouse(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TimerTick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure SetStatus(const S: string);
    function Bars: Integer;
    procedure ResizeRoll;
    function NoteName(AMidi: Integer): string;
    function DegreeMidi(ADeg, AOct: Integer): Integer;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MusicForm: TMusicForm;

implementation

const
  RollRows = 28;           // 4 octaves x 7 degrees (octave -1 .. +2)
  RH = 15;                 // piano roll row height
  CW = 14;                 // step width
  LW = 74;                 // label column
  GridRows = 9;
  GH = 22;
  GridNames: array[0..GridRows - 1] of string = ('Arp', 'Bass', 'Comp', 'Kick', 'Snare', 'Clap',
    'Hat', 'Open hat', 'Shaker');
  GridChars: array[0..GridRows - 1] of string = ('.0123', '.RO5', '.x', '.x', '.x', '.x', '.x', '.x', '.x');
  GridTrack: array[0..GridRows - 1] of Integer = (1, 2, 3, 5, 6, 7, 8, 9, 10);
  NoteNames: array[0..11] of string = ('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B');
  MajorScale: array[0..6] of Integer = (0, 2, 4, 5, 7, 9, 11);
  MinorScale: array[0..6] of Integer = (0, 2, 3, 5, 7, 8, 10);
  DegColours: array[0..6] of TColor = ($F0D723, $9128E6, $2396F5, $37E696, $F04B96, $3737F5, $D0D0D0);

function GameFile(AGame: Integer): string;
begin
  if AGame = MusicGameShooter then
    Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Shooter\NeonShooter.music')
  else if AGame = MusicGameTrail then
    Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Trail\NeonTrail.music')
  else
    Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\NeonGrid SDL3 GPU Game\NeonBeads.music');
end;

{ token <-> degree / octave / accidental }
function ParseTok(const T: string; out ADeg, AOct: Integer; out AAcc: string): Boolean;
var
  k: Integer;
begin
  Result := False;
  ADeg := 0; AOct := 0; AAcc := '';
  if (T = '') or not (T[1] in ['1'..'7']) then Exit;
  ADeg := Ord(T[1]) - Ord('0');
  for k := 2 to Length(T) do
    case T[k] of
      '''': Inc(AOct);
      ',': Dec(AOct);
      '#', 'b': AAcc += T[k];
    end;
  AOct := EnsureRange(AOct, -1, 2);
  Result := True;
end;

function MakeTok(ADeg, AOct: Integer; const AAcc: string): string;
begin
  Result := IntToStr(ADeg);
  if AOct > 0 then Result += StringOfChar('''', AOct)
  else if AOct < 0 then Result += StringOfChar(',', -AOct);
  Result += AAcc;
end;

function RowOf(ADeg, AOct: Integer): Integer;
begin
  { row 0 = top = highest note }
  Result := RollRows - 1 - ((AOct + 1) * 7 + ADeg - 1);
end;

{ TMusicForm }

constructor TMusicForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner, 0);
  Caption := 'Neon Music Editor';
  Width := 1280;
  Height := 860;
  Position := poScreenCenter;
  KeyPreview := True;
  FCur := -1;
  FSpb := 16;
  FLastPos := -2;
  Audio := TToolAudio.Create;
  BuildUI;
  OnCloseQuery := @FormCloseQuery;
  cbGame.ItemIndex := 0;
  OpenFile(GameFile(MusicGameBeads), MusicGameBeads);
  if not Audio.Ok then SetStatus('No audio device: playback is off.');
end;

destructor TMusicForm.Destroy;
begin
  Timer.Enabled := False;
  Audio.Free;
  inherited Destroy;
end;

function TMusicForm.Btn(AParent: TWinControl; const ACaption: string; AX, AY, AW: Integer;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(AX, AY, AW, 26);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function TMusicForm.Lbl(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := AX;
  Result.Top := AY + 4;
  Result.Caption := ACaption;
end;

procedure TMusicForm.BuildUI;
var
  pTop, pLeft, props, pBottom, pBars: TPanel;
  i, x: Integer;
  w: TWave;
  k: TKit;
  m: Integer;

  function Spin(AParent: TWinControl; AX, AY, AW, AMin, AMax: Integer): TSpinEdit;
  begin
    Result := TSpinEdit.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(AX, AY, AW, 24);
    Result.MinValue := AMin;
    Result.MaxValue := AMax;
    Result.OnChange := @Changed;
  end;

  function FSpin(AParent: TWinControl; AX, AY, AW: Integer; AMax, AInc: Double): TFloatSpinEdit;
  begin
    Result := TFloatSpinEdit.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(AX, AY, AW, 24);
    Result.MinValue := 0;
    Result.MaxValue := AMax;
    Result.Increment := AInc;
    Result.DecimalPlaces := 3;
    Result.OnChange := @Changed;
  end;

  function Combo(AParent: TWinControl; AX, AY, AW: Integer): TComboBox;
  begin
    Result := TComboBox.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(AX, AY, AW, 24);
    Result.Style := csDropDownList;
    Result.OnChange := @Changed;
  end;

  function Check(AParent: TWinControl; const ACaption: string; AX, AY: Integer): TCheckBox;
  begin
    Result := TCheckBox.Create(Self);
    Result.Parent := AParent;
    Result.Left := AX;
    Result.Top := AY + 3;
    Result.Caption := ACaption;
    Result.OnClick := @Changed;
  end;

const
  InstNames: array[0..3] of string = ('Lead', 'Arp', 'Bass', 'Comp');
  GainNames: array[0..6] of string = ('Lead', 'Arp', 'Bass', 'Comp', 'Pad', 'Drums', 'Delay');
begin
  { ---- top bar: file, transport }
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
  Btn(pTop, 'Defaults', 462, 7, 70, @DefaultsClick);
  Btn(pTop, '> Play', 556, 7, 70, @PlayClick).Font.Style := [fsBold];
  Btn(pTop, 'Stop', 630, 7, 56, @StopClick);
  chkCalm := TCheckBox.Create(Self);
  chkCalm.Parent := pTop;
  chkCalm.SetBounds(696, 10, 120, 22);
  chkCalm.Caption := 'menu (calm) mix';
  chkCalm.OnClick := @CalmClick;
  Lbl(pTop, 'Volume', 822, 8);
  tbVolume := TTrackBar.Create(Self);
  tbVolume.Parent := pTop;
  tbVolume.SetBounds(870, 4, 130, 30);
  tbVolume.Max := 100;
  tbVolume.Position := 80;
  tbVolume.TickStyle := tsNone;
  tbVolume.OnChange := @VolumeChange;
  lblFile := Lbl(pTop, '', 1010, 8);
  lblFile.Font.Color := clGrayText;

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := Self;
  lblStatus.Align := alBottom;
  lblStatus.BorderSpacing.Around := 4;
  lblStatus.Caption := 'Left click a piano roll cell: note on / off   Right click: hold (lengthens the note before it)';

  { ---- left: songs }
  pLeft := TPanel.Create(Self);
  pLeft.Parent := Self;
  pLeft.Align := alLeft;
  pLeft.Width := 210;
  pLeft.BevelOuter := bvNone;
  lbSongs := TListBox.Create(Self);
  lbSongs.Parent := pLeft;
  lbSongs.Align := alClient;
  lbSongs.BorderSpacing.Around := 6;
  lbSongs.OnClick := @SongClick;
  pBottom := TPanel.Create(Self);
  pBottom.Parent := pLeft;
  pBottom.Align := alBottom;
  pBottom.Height := 64;
  pBottom.BevelOuter := bvNone;
  Btn(pBottom, 'New', 6, 2, 64, @NewClick);
  Btn(pBottom, 'Copy', 72, 2, 64, @CopyClick);
  Btn(pBottom, 'Delete', 138, 2, 64, @DeleteClick);
  Btn(pBottom, 'Up', 6, 32, 64, @UpClick);
  Btn(pBottom, 'Down', 72, 32, 64, @DownClick);

  { ---- song settings }
  props := TPanel.Create(Self);
  props.Parent := Self;
  props.Align := alTop;
  props.Height := 132;
  props.BevelOuter := bvNone;
  Lbl(props, 'Name', 8, 6);
  edName := TEdit.Create(Self);
  edName.Parent := props;
  edName.SetBounds(48, 6, 170, 24);
  edName.OnChange := @Changed;
  Lbl(props, 'BPM', 230, 6);
  seBPM := Spin(props, 262, 6, 64, 30, 300);
  Lbl(props, 'Steps/bar', 336, 6);
  seSpb := Spin(props, 398, 6, 54, 4, 32);
  Lbl(props, 'Swing', 462, 6);
  fseSwing := FSpin(props, 502, 6, 66, 0.45, 0.02);
  Lbl(props, 'Key', 580, 6);
  cbKey := Combo(props, 608, 6, 70);
  for m := 36 to 84 do cbKey.Items.Add(NoteName(m));
  chkMinor := Check(props, 'minor', 686, 6);
  Lbl(props, 'Kit', 754, 6);
  cbKit := Combo(props, 778, 6, 80);
  for k := Low(TKit) to High(TKit) do cbKit.Items.Add(KitNames[k]);
  chkPad := Check(props, 'pad chords', 868, 6);
  Lbl(props, 'Chords (degree per bar)', 970, 6);
  edChords := TEdit.Create(Self);
  edChords.Parent := props;
  edChords.SetBounds(1110, 6, 120, 24);
  edChords.OnChange := @Changed;
  edChords.Hint := 'one scale degree 1-7 per bar, e.g. 1564 = I V vi IV';
  edChords.ShowHint := True;
  { instruments }
  for i := 0 to 3 do
  begin
    x := 8 + i * 250;
    Lbl(props, InstNames[i], x, 40);
    cbWave[i] := Combo(props, x + 40, 40, 100);
    for w := Low(TWave) to High(TWave) do cbWave[i].Items.Add(WaveNames[w]);
    Lbl(props, 'oct', x + 146, 40);
    seOct[i] := Spin(props, x + 170, 40, 56, -48, 48);
    seOct[i].Increment := 12;
  end;
  chkMuteLead := TCheckBox.Create(Self);
  chkMuteLead.Parent := props;
  chkMuteLead.SetBounds(1010, 43, 110, 22);
  chkMuteLead.Caption := 'mute lead';
  chkMuteLead.OnClick := @MuteClick;
  chkMutePad := TCheckBox.Create(Self);
  chkMutePad.Parent := props;
  chkMutePad.SetBounds(1120, 43, 110, 22);
  chkMutePad.Caption := 'mute pad';
  chkMutePad.OnClick := @MuteClick;
  Lbl(props, 'Levels:', 8, 74);
  for i := 0 to 6 do
  begin
    x := 60 + i * 150;
    Lbl(props, GainNames[i], x, 74);
    if i = 6 then fseGain[i] := FSpin(props, x + 46, 74, 80, 1, 0.02)
    else if i = 5 then fseGain[i] := FSpin(props, x + 46, 74, 80, 1.5, 0.02)
    else fseGain[i] := FSpin(props, x + 46, 74, 80, 0.5, 0.005);
  end;
  pBars := TPanel.Create(Self);
  pBars.Parent := props;
  pBars.SetBounds(0, 102, 1200, 30);
  pBars.BevelOuter := bvNone;
  Lbl(pBars, 'Melody', 8, 2);
  Btn(pBars, '+ bar', 60, 1, 56, @AddBarClick);
  Btn(pBars, '- bar', 118, 1, 56, @DelBarClick);
  lblBars := Lbl(pBars, '0 bars', 182, 2);
  Lbl(pBars, 'Text', 250, 2);
  edMelody := TEdit.Create(Self);
  edMelody.Parent := pBars;
  edMelody.SetBounds(282, 2, 900, 24);
  edMelody.Hint := 'tokens per step, pBars separated by |: 1-7 degree, '' up, , down, # b, - hold, . rest  (Enter applies)';
  edMelody.ShowHint := True;
  edMelody.OnKeyDown := @MelodyKey;

  { ---- pattern grid at the pBottom, piano roll in the middle }
  pbGrid := TPaintBox.Create(Self);
  pbGrid.Parent := Self;
  pbGrid.Align := alBottom;
  pbGrid.Height := GridRows * GH + 8;
  pbGrid.OnPaint := @GridPaint;
  pbGrid.OnMouseDown := @GridMouse;
  sbRoll := TScrollBox.Create(Self);
  sbRoll.Parent := Self;
  sbRoll.Align := alClient;
  sbRoll.HorzScrollBar.Tracking := True;
  sbRoll.Color := $201814;
  pbRoll := TPaintBox.Create(Self);
  pbRoll.Parent := sbRoll;
  pbRoll.SetBounds(0, 0, 800, RollRows * RH + 2);
  pbRoll.OnPaint := @RollPaint;
  pbRoll.OnMouseDown := @RollMouse;

  { docking order (LCL sorts aligned controls by their position) }
  pTop.Top := 0;
  props.Top := 50;
  pbGrid.Top := 5000;
  lblStatus.Top := 6000;

  Timer := TTimer.Create(Self);
  Timer.Interval := 40;
  Timer.OnTimer := @TimerTick;
end;

function TMusicForm.NoteName(AMidi: Integer): string;
begin
  Result := NoteNames[AMidi mod 12] + IntToStr(AMidi div 12 - 1);
end;

function TMusicForm.DegreeMidi(ADeg, AOct: Integer): Integer;
var
  key: Integer;
begin
  key := 36 + Max(0, cbKey.ItemIndex);
  if chkMinor.Checked then Result := key + MinorScale[ADeg - 1] else Result := key + MajorScale[ADeg - 1];
  Result += 12 * AOct + seOct[0].Value;
end;

procedure TMusicForm.SetStatus(const S: string);
begin
  lblStatus.Caption := S;
end;

function TMusicForm.Bars: Integer;
begin
  if FSpb <= 0 then Exit(0);
  Result := Length(FTok) div FSpb;
end;

procedure TMusicForm.ResizeRoll;
begin
  pbRoll.Width := LW + Max(1, Bars) * FSpb * CW + 20;
  lblBars.Caption := Format('%d bars', [Bars]);
end;

{ ---- files }

procedure TMusicForm.OpenFile(const AFile: string; AGame: Integer);
var
  songs: TSongArray;
begin
  Audio.Music.SelectSong(-1);
  FFile := AFile;
  if LoadSongsFile(AFile, songs) then
    SetStatus('Loaded ' + AFile)
  else
  begin
    songs := DefaultSongs(AGame);
    SetStatus('No song file yet - the game''s built-in songs are shown. Save writes ' + AFile);
  end;
  SetSongs(songs);
  lblFile.Caption := AFile;
  FDirty := False;
  FillList;
  if SongCount > 0 then ShowSong(0) else ShowSong(-1);
end;

procedure TMusicForm.FillList;
var
  i, keep: Integer;
begin
  keep := lbSongs.ItemIndex;
  lbSongs.Items.BeginUpdate;
  lbSongs.Items.Clear;
  for i := 0 to SongCount - 1 do lbSongs.Items.Add(Format('%d. %s', [i + 1, SongName(i)]));
  lbSongs.Items.EndUpdate;
  if (keep >= 0) and (keep < lbSongs.Count) then lbSongs.ItemIndex := keep;
end;

procedure TMusicForm.GameChange(Sender: TObject);
var
  g: Integer;
begin
  if FDirty and (MessageDlg('Save changes?', 'Save the changed songs before switching?', mtConfirmation,
    [mbYes, mbNo], 0) = mrYes) then SaveClick(nil);
  case cbGame.ItemIndex of
    1: g := MusicGameTrail;
    2: g := MusicGameShooter;
  else
    g := MusicGameBeads;
  end;
  OpenFile(GameFile(g), g);
end;

procedure TMusicForm.OpenClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := 'Neon music (*.music)|*.music|All files|*.*';
    dlg.InitialDir := ExtractFilePath(FFile);
    if dlg.Execute then OpenFile(dlg.FileName, MusicGameBeads);
  finally
    dlg.Free;
  end;
end;

procedure TMusicForm.SaveClick(Sender: TObject);
begin
  try
    SaveSongsFile(FFile, GetSongs);
    FDirty := False;
    SetStatus('Saved ' + FFile + '  (a running game reloads it)');
  except
    on E: Exception do MessageDlg('Save failed', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMusicForm.SaveAsClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := 'Neon music (*.music)|*.music';
    dlg.DefaultExt := 'music';
    dlg.FileName := FFile;
    if dlg.Execute then
    begin
      FFile := dlg.FileName;
      lblFile.Caption := FFile;
      SaveClick(nil);
    end;
  finally
    dlg.Free;
  end;
end;

procedure TMusicForm.ReloadClick(Sender: TObject);
var
  g: Integer;
begin
  case cbGame.ItemIndex of
    1: g := MusicGameTrail;
    2: g := MusicGameShooter;
  else
    g := MusicGameBeads;
  end;
  OpenFile(FFile, g);
end;

procedure TMusicForm.DefaultsClick(Sender: TObject);
var
  g: Integer;
begin
  if MessageDlg('Built-in songs', 'Replace the list with the game''s built-in songs?', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then Exit;
  case cbGame.ItemIndex of
    1: g := MusicGameTrail;
    2: g := MusicGameShooter;
  else
    g := MusicGameBeads;
  end;
  Audio.Music.SelectSong(-1);
  SetSongs(DefaultSongs(g));
  FDirty := True;
  FillList;
  ShowSong(0);
end;

{ ---- song <-> controls }

procedure TMusicForm.ParseSong(const S: TSongDef);
var
  barsArr, toks: TStringArray;
  b, i: Integer;
begin
  FSpb := Max(1, S.StepsPerBar);
  SetLength(FTok, 0);
  if Trim(S.Melody) <> '' then
  begin
    barsArr := S.Melody.Split(['|']);
    SetLength(FTok, Length(barsArr) * FSpb);
    for b := 0 to High(barsArr) do
    begin
      toks := Trim(barsArr[b]).Split([' '], TStringSplitOptions.ExcludeEmpty);
      for i := 0 to FSpb - 1 do
        if i < Length(toks) then FTok[b * FSpb + i] := toks[i] else FTok[b * FSpb + i] := '.';
    end;
  end;
  FPats[0] := S.ArpPat;
  FPats[1] := S.BassPat;
  FPats[2] := S.CompPat;
  FPats[3] := S.KickPat;
  FPats[4] := S.SnarePat;
  FPats[5] := S.ClapPat;
  FPats[6] := S.HatPat;
  FPats[7] := S.OpenPat;
  FPats[8] := S.ShakerPat;
  for i := 0 to GridRows - 1 do
  begin
    if Length(FPats[i]) < FSpb then FPats[i] += StringOfChar('.', FSpb - Length(FPats[i]));
    SetLength(FPats[i], FSpb);
  end;
end;

function TMusicForm.MelodyText: string;
var
  b, i: Integer;
begin
  Result := '';
  for b := 0 to Bars - 1 do
  begin
    if b > 0 then Result += '|';
    for i := 0 to FSpb - 1 do
    begin
      if i > 0 then Result += ' ';
      Result += FTok[b * FSpb + i];
    end;
  end;
end;

procedure TMusicForm.ShowSong(AIndex: Integer);
var
  s: TSongDef;
begin
  FCur := AIndex;
  FUpdating := True;
  try
    if (AIndex < 0) or (AIndex >= SongCount) then s := BlankSong else s := GetSong(AIndex);
    if (AIndex >= 0) and (AIndex < lbSongs.Count) then lbSongs.ItemIndex := AIndex;
    edName.Text := s.Name;
    seBPM.Value := s.BPM;
    seSpb.Value := s.StepsPerBar;
    fseSwing.Value := s.Swing;
    cbKey.ItemIndex := EnsureRange(s.Key - 36, 0, cbKey.Items.Count - 1);
    chkMinor.Checked := s.Minor;
    cbKit.ItemIndex := Ord(s.Kit);
    chkPad.Checked := s.PadOn;
    edChords.Text := s.Chords;
    cbWave[0].ItemIndex := Ord(s.Lead);
    cbWave[1].ItemIndex := Ord(s.Arp);
    cbWave[2].ItemIndex := Ord(s.Bass);
    cbWave[3].ItemIndex := Ord(s.Comp);
    seOct[0].Value := s.LeadOct;
    seOct[1].Value := s.ArpOct;
    seOct[2].Value := s.BassOct;
    seOct[3].Value := s.CompOct;
    fseGain[0].Value := s.LeadGain;
    fseGain[1].Value := s.ArpGain;
    fseGain[2].Value := s.BassGain;
    fseGain[3].Value := s.CompGain;
    fseGain[4].Value := s.PadGain;
    fseGain[5].Value := s.DrumGain;
    fseGain[6].Value := s.DelayMix;
    ParseSong(s);
    edMelody.Text := MelodyText;
    ResizeRoll;
  finally
    FUpdating := False;
  end;
  pbRoll.Invalidate;
  pbGrid.Invalidate;
end;

function TMusicForm.BuildSong: TSongDef;
var
  i, newSpb, b: Integer;
  old: array of string;
  c: Char;
  ch: string;
begin
  Result := GetSong(FCur);
  { steps per bar changed: re-cut the melody and patterns }
  newSpb := seSpb.Value;
  if newSpb <> FSpb then
  begin
    old := Copy(FTok);
    b := Bars;
    SetLength(FTok, b * newSpb);
    for i := 0 to High(FTok) do
    begin
      if (i mod newSpb < FSpb) and ((i div newSpb) * FSpb + i mod newSpb < Length(old)) then
        FTok[i] := old[(i div newSpb) * FSpb + i mod newSpb]
      else
        FTok[i] := '.';
    end;
    for i := 0 to GridRows - 1 do
    begin
      if Length(FPats[i]) < newSpb then FPats[i] += StringOfChar('.', newSpb - Length(FPats[i]));
      SetLength(FPats[i], newSpb);
    end;
    FSpb := newSpb;
    ResizeRoll;
  end;
  Result.Name := Trim(edName.Text);
  if Result.Name = '' then Result.Name := 'Song';
  Result.BPM := seBPM.Value;
  Result.StepsPerBar := FSpb;
  Result.Swing := fseSwing.Value;
  Result.Key := 36 + Max(0, cbKey.ItemIndex);
  Result.Minor := chkMinor.Checked;
  Result.Kit := TKit(Max(0, cbKit.ItemIndex));
  Result.PadOn := chkPad.Checked;
  ch := '';
  for c in edChords.Text do
    if c in ['1'..'7'] then ch += c;
  if ch = '' then ch := '1';
  Result.Chords := ch;
  Result.Lead := TWave(Max(0, cbWave[0].ItemIndex));
  Result.Arp := TWave(Max(0, cbWave[1].ItemIndex));
  Result.Bass := TWave(Max(0, cbWave[2].ItemIndex));
  Result.Comp := TWave(Max(0, cbWave[3].ItemIndex));
  Result.LeadOct := seOct[0].Value;
  Result.ArpOct := seOct[1].Value;
  Result.BassOct := seOct[2].Value;
  Result.CompOct := seOct[3].Value;
  Result.LeadGain := fseGain[0].Value;
  Result.ArpGain := fseGain[1].Value;
  Result.BassGain := fseGain[2].Value;
  Result.CompGain := fseGain[3].Value;
  Result.PadGain := fseGain[4].Value;
  Result.DrumGain := fseGain[5].Value;
  Result.DelayMix := fseGain[6].Value;
  Result.Melody := MelodyText;
  Result.ArpPat := FPats[0];
  Result.BassPat := FPats[1];
  Result.CompPat := FPats[2];
  Result.KickPat := FPats[3];
  Result.SnarePat := FPats[4];
  Result.ClapPat := FPats[5];
  Result.HatPat := FPats[6];
  Result.OpenPat := FPats[7];
  Result.ShakerPat := FPats[8];
end;

procedure TMusicForm.Changed(Sender: TObject);
var
  s: TSongDef;
begin
  if FUpdating or (FCur < 0) then Exit;
  s := BuildSong;
  SetSong(FCur, s);
  if Audio.Music.CurrentSong = FCur then Audio.Music.Refresh;
  FDirty := True;
  if (FCur < lbSongs.Count) and (lbSongs.Items[FCur] <> Format('%d. %s', [FCur + 1, s.Name])) then
    lbSongs.Items[FCur] := Format('%d. %s', [FCur + 1, s.Name]);
  if not edMelody.Focused then edMelody.Text := MelodyText;
  pbRoll.Invalidate;
  pbGrid.Invalidate;
end;

procedure TMusicForm.SongClick(Sender: TObject);
begin
  if lbSongs.ItemIndex = FCur then Exit;
  ShowSong(lbSongs.ItemIndex);
  if Audio.Music.CurrentSong >= 0 then
  begin
    Audio.Music.SelectSong(FCur);
    Audio.Music.Restart(True);
  end;
end;

procedure TMusicForm.PlayClick(Sender: TObject);
begin
  if FCur < 0 then Exit;
  Audio.Music.SelectSong(FCur);
  Audio.Music.Restart(True);
  Timer.Enabled := True;
end;

procedure TMusicForm.StopClick(Sender: TObject);
begin
  Audio.Music.SelectSong(-1);
end;

procedure TMusicForm.CalmClick(Sender: TObject);
begin
  if chkCalm.Checked then Audio.Music.TargetIntensity := 0 else Audio.Music.TargetIntensity := 1;
end;

procedure TMusicForm.MuteClick(Sender: TObject);
begin
  Audio.Music.TrackMute[0] := chkMuteLead.Checked;
  Audio.Music.TrackMute[4] := chkMutePad.Checked;
end;

procedure TMusicForm.VolumeChange(Sender: TObject);
begin
  Audio.MusicVolume := tbVolume.Position / 100;
end;

{ ---- song list }

procedure TMusicForm.NewClick(Sender: TObject);
var
  a: TSongArray;
  s: TSongDef;
begin
  a := GetSongs;
  s := BlankSong;
  s.Melody := '1 - 3 - 5 - 3 - 1 - - - . . . .|5 - 4 - 3 - 2 - 1 - - - . . . .';
  s.KickPat := 'x...x...x...x...';
  s.SnarePat := '....x.......x...';
  s.HatPat := '..x...x...x...x.';
  s.BassPat := 'R.O.R.O.R.O.R.O.';
  SetLength(a, Length(a) + 1);
  a[High(a)] := s;
  SetSongs(a);
  FDirty := True;
  FillList;
  ShowSong(High(a));
end;

procedure TMusicForm.CopyClick(Sender: TObject);
var
  a: TSongArray;
  s: TSongDef;
begin
  if FCur < 0 then Exit;
  a := GetSongs;
  s := a[FCur];
  s.Name := s.Name + ' copy';
  SetLength(a, Length(a) + 1);
  a[High(a)] := s;
  SetSongs(a);
  FDirty := True;
  FillList;
  ShowSong(High(a));
end;

procedure TMusicForm.DeleteClick(Sender: TObject);
var
  a: TSongArray;
  i: Integer;
begin
  if (FCur < 0) or (SongCount <= 1) then Exit;
  if MessageDlg('Delete song', 'Delete "' + SongName(FCur) + '"?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  Audio.Music.SelectSong(-1);
  a := GetSongs;
  for i := FCur to High(a) - 1 do a[i] := a[i + 1];
  SetLength(a, Length(a) - 1);
  SetSongs(a);
  FDirty := True;
  FillList;
  ShowSong(Min(FCur, High(a)));
end;

procedure TMusicForm.UpClick(Sender: TObject);
var
  a: TSongArray;
  t: TSongDef;
begin
  if FCur <= 0 then Exit;
  a := GetSongs;
  t := a[FCur]; a[FCur] := a[FCur - 1]; a[FCur - 1] := t;
  SetSongs(a);
  FDirty := True;
  FillList;
  ShowSong(FCur - 1);
end;

procedure TMusicForm.DownClick(Sender: TObject);
var
  a: TSongArray;
  t: TSongDef;
begin
  if (FCur < 0) or (FCur >= SongCount - 1) then Exit;
  a := GetSongs;
  t := a[FCur]; a[FCur] := a[FCur + 1]; a[FCur + 1] := t;
  SetSongs(a);
  FDirty := True;
  FillList;
  ShowSong(FCur + 1);
end;

{ ---- melody bars / text }

procedure TMusicForm.AddBarClick(Sender: TObject);
var
  i, n: Integer;
begin
  n := Length(FTok);
  SetLength(FTok, n + FSpb);
  for i := n to High(FTok) do FTok[i] := '.';
  ResizeRoll;
  Changed(nil);
end;

procedure TMusicForm.DelBarClick(Sender: TObject);
begin
  if Bars = 0 then Exit;
  SetLength(FTok, Length(FTok) - FSpb);
  ResizeRoll;
  Changed(nil);
end;

procedure TMusicForm.MelodyKey(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  s: TSongDef;
begin
  if Key <> VK_RETURN then Exit;
  Key := 0;
  s := BuildSong;
  s.Melody := Trim(edMelody.Text);
  ParseSong(s);
  ResizeRoll;
  Changed(nil);
  SetStatus('Melody text applied.');
end;

{ ---- piano roll }

procedure TMusicForm.RollPaint(Sender: TObject);
var
  c: TCanvas;
  r, col, n, deg, oct, x, y, k, play, total, midi: Integer;
  acc: string;
  rc: TRect;
begin
  c := pbRoll.Canvas;
  c.Brush.Color := $201814;
  c.FillRect(0, 0, pbRoll.Width, pbRoll.Height);
  n := Length(FTok);
  total := Max(1, Bars) * FSpb;
  { rows }
  for r := 0 to RollRows - 1 do
  begin
    deg := 7 - (r mod 7);
    oct := 2 - r div 7;
    y := r * RH;
    if deg = 1 then c.Brush.Color := $3A2E26
    else if r mod 2 = 0 then c.Brush.Color := $2A221C
    else c.Brush.Color := $241D18;
    c.FillRect(LW, y, LW + total * CW, y + RH);
    c.Brush.Color := $302824;
    c.FillRect(0, y, LW - 2, y + RH);
    c.Font.Color := DegColours[deg - 1];
    c.Font.Height := -11;
    c.Brush.Style := bsClear;
    midi := DegreeMidi(deg, oct);
    c.TextOut(4, y + 1, MakeTok(deg, oct, '') + '  ' + NoteName(EnsureRange(midi, 0, 127)));
    c.Brush.Style := bsSolid;
  end;
  { beat / bar lines }
  for col := 0 to total do
  begin
    x := LW + col * CW;
    if col mod FSpb = 0 then c.Pen.Color := $8A7A6A
    else if col mod 4 = 0 then c.Pen.Color := $4A3E34
    else c.Pen.Color := $30281F;
    c.Line(x, 0, x, RollRows * RH);
  end;
  { playhead }
  play := -1;
  if (Audio.Music.CurrentSong = FCur) and (Audio.Music.Position >= 0) and (n > 0) then
    play := Audio.Music.Position mod n;
  if play >= 0 then
  begin
    c.Brush.Color := $504030;
    c.FillRect(LW + play * CW + 1, 0, LW + play * CW + CW, RollRows * RH);
  end;
  { notes (holds lengthen the note before them) }
  col := 0;
  while col < n do
  begin
    if ParseTok(FTok[col], deg, oct, acc) then
    begin
      k := col + 1;
      while (k < n) and (FTok[k] = '-') do Inc(k);
      r := RowOf(deg, oct);
      rc := Rect(LW + col * CW + 1, r * RH + 2, LW + k * CW - 1, r * RH + RH - 1);
      c.Brush.Color := DegColours[deg - 1];
      c.Pen.Color := clWhite;
      c.Rectangle(rc);
      if acc <> '' then
      begin
        c.Brush.Style := bsClear;
        c.Font.Color := clBlack;
        c.TextOut(rc.Left + 2, rc.Top - 1, acc);
        c.Brush.Style := bsSolid;
      end;
      col := k;
    end
    else
    begin
      if FTok[col] = '-' then
      begin
        { a hold without a note before it (start of the melody) }
        c.Pen.Color := $707070;
        c.Line(LW + col * CW + 2, RollRows * RH - 4, LW + col * CW + CW - 2, RollRows * RH - 4);
      end;
      Inc(col);
    end;
  end;
  if n = 0 then
  begin
    c.Brush.Style := bsClear;
    c.Font.Color := clSilver;
    c.TextOut(LW + 10, 10, 'No melody: press "+ bar" to start one (this song plays only its patterns).');
    c.Brush.Style := bsSolid;
  end;
end;

procedure TMusicForm.RollMouse(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  col, row, deg, oct, d2, o2, k: Integer;
  acc: string;
begin
  if X < LW then Exit;
  col := (X - LW) div CW;
  row := Y div RH;
  if (col < 0) or (col >= Length(FTok)) or (row < 0) or (row >= RollRows) then Exit;
  deg := 7 - (row mod 7);
  oct := 2 - row div 7;
  if Button = mbRight then
  begin
    if FTok[col] = '-' then FTok[col] := '.' else FTok[col] := '-';
  end
  else if ParseTok(FTok[col], d2, o2, acc) and (d2 = deg) and (o2 = oct) then
  begin
    { remove the note and its holds }
    FTok[col] := '.';
    k := col + 1;
    while (k < Length(FTok)) and (FTok[k] = '-') do
    begin
      FTok[k] := '.';
      Inc(k);
    end;
  end
  else
  begin
    FTok[col] := MakeTok(deg, oct, '');
  end;
  Changed(nil);
end;

{ ---- pattern grid }

procedure TMusicForm.GridPaint(Sender: TObject);
var
  c: TCanvas;
  r, col, x, y, play, tr: Integer;
  ch: Char;
begin
  c := pbGrid.Canvas;
  c.Brush.Color := $1C1612;
  c.FillRect(0, 0, pbGrid.Width, pbGrid.Height);
  c.Font.Height := -12;
  play := -1;
  if (Audio.Music.CurrentSong = FCur) and (Audio.Music.Position >= 0) then
    play := Audio.Music.Position mod FSpb;
  for r := 0 to GridRows - 1 do
  begin
    y := 4 + r * GH;
    tr := GridTrack[r];
    if Audio.Music.TrackMute[tr] then c.Brush.Color := $303060 else c.Brush.Color := $302824;
    c.FillRect(0, y, 120, y + GH - 2);
    c.Brush.Style := bsClear;
    if Audio.Music.TrackMute[tr] then
    begin
      c.Font.Color := $8080FF;
      c.TextOut(6, y + 3, GridNames[r] + '  (muted)');
    end
    else
    begin
      c.Font.Color := clWhite;
      c.TextOut(6, y + 3, GridNames[r]);
    end;
    c.Brush.Style := bsSolid;
    for col := 0 to FSpb - 1 do
    begin
      x := 124 + col * 30;
      ch := '.';
      if col < Length(FPats[r]) then ch := FPats[r][col + 1];
      if col = play then c.Brush.Color := $604838
      else if col mod 4 = 0 then c.Brush.Color := $3A302A
      else c.Brush.Color := $2A231E;
      if ch <> '.' then c.Brush.Color := DegColours[(r + 2) mod 7];
      c.FillRect(x, y, x + 28, y + GH - 2);
      if ch <> '.' then
      begin
        c.Brush.Style := bsClear;
        c.Font.Color := clBlack;
        if ch <> 'x' then c.TextOut(x + 9, y + 3, ch);
        c.Brush.Style := bsSolid;
      end;
    end;
  end;
end;

procedure TMusicForm.GridMouse(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  r, col, k: Integer;
  s: string;
  tr: Integer;
begin
  r := (Y - 4) div GH;
  if (r < 0) or (r >= GridRows) then Exit;
  if X < 120 then
  begin
    tr := GridTrack[r];
    Audio.Music.TrackMute[tr] := not Audio.Music.TrackMute[tr];
    pbGrid.Invalidate;
    Exit;
  end;
  col := (X - 124) div 30;
  if (col < 0) or (col >= FSpb) then Exit;
  s := FPats[r];
  if Button = mbRight then s[col + 1] := '.'
  else
  begin
    k := Pos(s[col + 1], GridChars[r]);
    if k <= 0 then k := 1;
    k := k mod Length(GridChars[r]) + 1;
    s[col + 1] := GridChars[r][k];
  end;
  FPats[r] := s;
  Changed(nil);
end;

procedure TMusicForm.TimerTick(Sender: TObject);
var
  p: Integer;
begin
  p := Audio.Music.Position;
  if p <> FLastPos then
  begin
    FLastPos := p;
    pbRoll.Invalidate;
    pbGrid.Invalidate;
  end;
end;

procedure TMusicForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if not FDirty then Exit;
  case MessageDlg('Save changes?', 'The songs changed. Save them before closing?', mtConfirmation,
    [mbYes, mbNo, mbCancel], 0) of
    mrYes: SaveClick(nil);
    mrCancel: CanClose := False;
  end;
end;

end.
