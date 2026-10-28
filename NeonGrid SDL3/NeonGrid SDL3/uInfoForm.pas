unit uInfoForm;

{ Separate information / settings window.
  Tabs: Overview (pipeline + full parameter dump), Performance (live stats,
  per-thread timing, frame-interval graph), Parameters (editor generated from
  the ParamDefs registry), Layers (every layer with toggle, amount and live
  preview), Graphics (sprite layers, colour field maps, palette, live frame). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  Spin, Dialogs, CheckLst, LCLIntf, BGRABitmap, BGRABitmapTypes, uParams, uRenderer, uExport, uMFVideo;

type
  TInfoForm = class(TForm)
  private
    FPages: TPageControl;
    FTabOverview, FTabPerf, FTabParams, FTabLayers, FTabGfx, FTabExport: TTabSheet;
    { export tab }
    FExpFolder: TEdit;
    FExpW, FExpH, FExpFrames, FExpFps: TSpinEdit;
    FExpScale: TFloatSpinEdit;
    FMp4Secs, FMp4Fps, FMp4Mbps: TSpinEdit;
    FMp4Scale: TFloatSpinEdit;
    FMp4Hw: TCheckBox;
    FCurGif: TGifWriter;      // target of SinkFrame
    FCurMp4: TMp4Writer;
    FSinkDone, FSinkTotal: Integer;
    FExpLayers, FExpGraphics: TCheckListBox;
    FExpProgress: TProgressBar;
    FExpLog: TMemo;
    FExporting: Boolean;
    FOrder: Integer;  // increasing Left/Top so aligned controls keep creation order
    FOverview: TMemo;
    FPerfBox: TPaintBox;
    FGroupList: TListBox;
    FParamHeader: TLabel;
    FParamScroll: TScrollBox;
    FLayerScroll: TScrollBox;
    FGfxScroll: TScrollBox;
    FGfxBox: TPaintBox;
    FBtnPause: TButton;
    FTimer: TTimer;
    FUpdating: Boolean;
    FTick: Integer;
    FLastPaused: Boolean;
    FTracks: array of TTrackBar;
    FSpins: array of TFloatSpinEdit;
    FChecks: array of TCheckBox;
    FColors: array of TColorButton;
    FHexLabels: array of TLabel;
    FLayerBox: array[TLayerKind] of TPaintBox;
    FLayerBmp: array[TLayerKind] of TBGRABitmap;
    FLayerCheck: array[TLayerKind] of TCheckBox;
    FLayerTrack: array[TLayerKind] of TTrackBar;
    FGfxBmp: TBGRABitmap;
    { expensive preview images are built on a background thread so the SDL
      render loop (same main thread) never stalls }
    FAsync: TThread;
    FGfxField0, FGfxField1, FGfxDots, FGfxFrame: TBGRABitmap;
    FGfxPanels: array[0..3] of TRect;  // where the live panels sit on the sheet
    FGfxSheetTick: Integer;
    FGfxSheetKey: string;  // static sheet content; rebuilt only when it changes
    FGfxDDB: TBitmap;      // static sheet + text as a GDI bitmap (one BitBlt per paint)
    FPerfBuf: TBitmap;  // GDI back buffer of the performance panel
    FGfxTexts: array of record
      X, Y, Size: Integer;
      S: string;
      C: TBGRAPixel;
      Bold: Boolean;
    end;
    function GfxSheetKey: string;
    procedure StartAsync(APurpose: Integer);
    procedure CollectAsync;
    procedure GfxPanelSize(out APW, APH: Integer);
    procedure BuildUI;
    procedure BuildLayerTab;
    procedure ShowGroup(const AGroup: string);
    procedure GroupClick(Sender: TObject);
    procedure TrackChange(Sender: TObject);
    procedure SpinChange(Sender: TObject);
    procedure CheckChange(Sender: TObject);
    procedure ColorChange(Sender: TObject);
    procedure LayerCheckChange(Sender: TObject);
    procedure LayerTrackChange(Sender: TObject);
    procedure LayerEditClick(Sender: TObject);
    procedure LayerPaint(Sender: TObject);
    procedure PerfPaint(Sender: TObject);
    procedure GfxPaint(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure PageChange(Sender: TObject);
    procedure BtnResetClick(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    procedure BtnLoadClick(Sender: TObject);
    procedure BtnPauseClick(Sender: TObject);
    procedure BtnFullClick(Sender: TObject);
    procedure BtnHideClick(Sender: TObject);
    procedure InfoCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure SyncControls;
    procedure RebuildLayerPreviews;
    procedure RebuildGfxSheet(AWithText: Boolean = False);
    procedure RefreshOverview;
    function MakeButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
    function AddRow(AParent: TWinControl; AHeight: Integer): TPanel;
    function AddLbl(AParent: TWinControl; const ACaption: string): TLabel;
    function AddSpin(AParent: TWinControl; AMin, AMax, AValue: Integer): TSpinEdit;
    function AddGroup(const ACaption: string; AHeight: Integer): TGroupBox;
    function NextOrder: Integer;
    procedure BuildExportTab;
    procedure ExpBrowseClick(Sender: TObject);
    procedure ExpOpenClick(Sender: TObject);
    procedure ExpAspectClick(Sender: TObject);
    procedure ExpCheckClick(Sender: TObject);
    procedure ExpRunClick(Sender: TObject);
    procedure ExpLog(const S: string);
    procedure ExpProgress(ADone, ATotal: Integer);
    function ExportDir: string;
    function GifDelayMs: Integer;
    function GifTimeStep: Double;
    procedure ExportLayers(AGif: Boolean);
    procedure ExportGraphics(AGif: Boolean);
    procedure ExportMainPng;
    procedure ExportMainGif;
    function Mp4Writer(const AFileName: string; AW, AH: Integer): TMp4Writer;
    procedure LogMp4(const AFileName: string; AWriter: TMp4Writer);
    procedure ExportLayersMp4;
    procedure ExportGraphicsMp4;
    procedure ExportMainMp4;
    procedure SinkFrame(AIndex: Integer; AFrame: TBGRABitmap);
    procedure ExpIdle;
    procedure RunPreviewFrames(AIsLayer: Boolean; AKind: TLayerKind; AGraphic: TGraphicItem;
      AW, AH, ACount: Integer; AT0, ADt: Double; var ADone: Integer; ATotal: Integer);
    function MakeGraphic(AItem: TGraphicItem; AW, AH: Integer; ATime: Double; ATimed: Boolean;
      var AOffline: TNeonRenderer): TBGRABitmap;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure StopAsync;
    procedure SelectTab(AIndex: Integer);
  public
    { main-thread time spent by this window (shown in --bench reports) }
    PaintMsMax, TickMsMax: Double;
    PaintCount: Integer;
    PaintMsSum: Double;
    PaintStages: string;  // stage times of the slowest paint
  end;

var
  InfoForm: TInfoForm;

implementation

uses
  uSDLView, SDL3;

function TrackFromValue(AIndex: Integer; AValue: Double): Integer;
begin
  with ParamDefs[AIndex] do
    if MaxV > MinV then
      Result := EnsureRange(Round((AValue - MinV) / (MaxV - MinV) * 1000), 0, 1000)
    else
      Result := 0;
end;

function ValueFromTrack(AIndex, APos: Integer): Double;
begin
  with ParamDefs[AIndex] do
    Result := MinV + APos / 1000 * (MaxV - MinV);
end;

function Decimals(AIndex: Integer): Integer;
var
  r: Double;
begin
  with ParamDefs[AIndex] do
  begin
    if Kind = pkInt then Exit(0);
    r := MaxV - MinV;
    if r <= 2 then Result := 3 else if r <= 20 then Result := 2 else Result := 1;
  end;
end;

type
  { Builds preview images on a background thread (BGRABitmap drawing only, no
    fonts; reads the parameters and the renderer's colour model). }
  TAsyncImages = class(TThread)
  public
    R: TNeonRenderer;
    Geo: TFrameGeom;
    Purpose: Integer;  // 1 = layer previews, 2 = graphics sheet maps
    Kinds: array of TLayerKind;
    Fields: array of Integer;  // -1 = layer preview, 0 = blob map, 1 = full field map
    Ws, Hs: array of Integer;
    Imgs: array of TBGRABitmap;
    constructor Create(AR: TNeonRenderer; const AGeo: TFrameGeom; APurpose: Integer);
    destructor Destroy; override;
    procedure Add(AKind: TLayerKind; AField, AW, AH: Integer);
    procedure Execute; override;
  end;

constructor TAsyncImages.Create(AR: TNeonRenderer; const AGeo: TFrameGeom; APurpose: Integer);
begin
  R := AR;
  Geo := AGeo;
  Purpose := APurpose;
  FreeOnTerminate := False;
  inherited Create(True);
  Priority := tpLower;
end;

destructor TAsyncImages.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(Imgs) do Imgs[i].Free;
  inherited Destroy;
end;

procedure TAsyncImages.Add(AKind: TLayerKind; AField, AW, AH: Integer);
var
  n: Integer;
begin
  n := Length(Kinds);
  SetLength(Kinds, n + 1); SetLength(Fields, n + 1);
  SetLength(Ws, n + 1); SetLength(Hs, n + 1); SetLength(Imgs, n + 1);
  Kinds[n] := AKind; Fields[n] := AField; Ws[n] := Max(8, AW); Hs[n] := Max(8, AH);
  Imgs[n] := nil;
end;

procedure TAsyncImages.Execute;
var
  i: Integer;
begin
  for i := 0 to High(Kinds) do
  begin
    if Terminated then Exit;
    try
      if Fields[i] >= 0 then
        Imgs[i] := R.BuildFieldMapAt(Ws[i], Hs[i], Fields[i] = 1, Geo)
      else
        Imgs[i] := R.BuildPreviewAt(Kinds[i], Ws[i], Hs[i], Geo);
    except
      Imgs[i] := nil;
    end;
  end;
end;

const
  { layer previews cheap enough for the main thread (sprite masks, solid colour) }
  MainThreadLayers = [lkBackground, lkFill, lkCenter, lkGlow, lkRing, lkSparks];

{ TInfoForm }

constructor TInfoForm.Create(TheOwner: TComponent);
var
  n: Integer;
begin
  inherited CreateNew(TheOwner, 0);
  Caption := 'Neon Dot Grid SDL3 - Info, Layers, Settings & Export  (F1 toggles)';
  if Assigned(View) then
    SetBounds(View.Left + View.Width + 10, View.Top,
      Min(860, Screen.WorkAreaWidth - View.Left - View.Width - 20), View.Height)
  else
    SetBounds(100, 50, 860, 900);
  if Width < 520 then Width := 520;
  OnCloseQuery := @InfoCloseQuery;
  n := Length(ParamDefs);
  SetLength(FTracks, n);
  SetLength(FSpins, n);
  SetLength(FChecks, n);
  SetLength(FColors, n);
  SetLength(FHexLabels, n);
  BuildUI;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 100;
  FTimer.OnTimer := @TimerTick;
  FTimer.Enabled := True;
end;

destructor TInfoForm.Destroy;
var
  k: TLayerKind;
begin
  StopAsync;
  for k := Low(TLayerKind) to High(TLayerKind) do FreeAndNil(FLayerBmp[k]);
  FreeAndNil(FGfxBmp);
  FreeAndNil(FGfxField0);
  FreeAndNil(FGfxField1);
  FreeAndNil(FGfxDots);
  FreeAndNil(FGfxFrame);
  FreeAndNil(FPerfBuf);
  FreeAndNil(FGfxDDB);
  inherited Destroy;
end;

function TInfoForm.MakeButton(AParent: TWinControl; const ACaption: string; AHandler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.AutoSize := True;
  Result.Align := alLeft;
  Result.BorderSpacing.Around := 4;
  Result.Left := NextOrder;
  Result.OnClick := AHandler;
end;

procedure TInfoForm.BuildUI;
var
  bottom, right: TPanel;
begin
  bottom := TPanel.Create(Self);
  bottom.Parent := Self;
  bottom.Align := alBottom;
  bottom.Height := 40;
  bottom.BevelOuter := bvNone;
  MakeButton(bottom, 'Reset defaults', @BtnResetClick);
  MakeButton(bottom, 'Save preset...', @BtnSaveClick);
  MakeButton(bottom, 'Load preset...', @BtnLoadClick);
  FBtnPause := MakeButton(bottom, 'Pause', @BtnPauseClick);
  MakeButton(bottom, 'Fullscreen (F11)', @BtnFullClick);
  MakeButton(bottom, 'Hide (F1)', @BtnHideClick);

  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.OnChange := @PageChange;

  FTabOverview := FPages.AddTabSheet;
  FTabOverview.Caption := 'Overview';
  FTabPerf := FPages.AddTabSheet;
  FTabPerf.Caption := 'Performance';
  FTabParams := FPages.AddTabSheet;
  FTabParams.Caption := 'Parameters';
  FTabLayers := FPages.AddTabSheet;
  FTabLayers.Caption := 'Layers';
  FTabGfx := FPages.AddTabSheet;
  FTabGfx.Caption := 'Graphics';
  FTabExport := FPages.AddTabSheet;
  FTabExport.Caption := 'Export';

  FOverview := TMemo.Create(Self);
  FOverview.Parent := FTabOverview;
  FOverview.Align := alClient;
  FOverview.ReadOnly := True;
  FOverview.ScrollBars := ssBoth;
  FOverview.WordWrap := False;
  FOverview.Font.Name := 'Consolas';
  FOverview.Font.Size := 9;

  FPerfBox := TPaintBox.Create(Self);
  FPerfBox.Parent := FTabPerf;
  FPerfBox.Align := alClient;
  FPerfBox.OnPaint := @PerfPaint;

  FGroupList := TListBox.Create(Self);
  FGroupList.Parent := FTabParams;
  FGroupList.Align := alLeft;
  FGroupList.Width := 170;
  GetGroups(FGroupList.Items);
  FGroupList.OnClick := @GroupClick;
  right := TPanel.Create(Self);
  right.Parent := FTabParams;
  right.Align := alClient;
  right.BevelOuter := bvNone;
  FParamHeader := TLabel.Create(Self);
  FParamHeader.Parent := right;
  FParamHeader.Align := alTop;
  FParamHeader.BorderSpacing.Around := 6;
  FParamHeader.Font.Style := [fsBold];
  FParamHeader.Font.Size := 12;
  FParamScroll := TScrollBox.Create(Self);
  FParamScroll.Parent := right;
  FParamScroll.Align := alClient;
  FParamScroll.HorzScrollBar.Visible := False;
  FParamScroll.VertScrollBar.Tracking := True;

  FLayerScroll := TScrollBox.Create(Self);
  FLayerScroll.Parent := FTabLayers;
  FLayerScroll.Align := alClient;
  FLayerScroll.HorzScrollBar.Visible := False;
  FLayerScroll.VertScrollBar.Tracking := True;
  BuildLayerTab;

  FGfxScroll := TScrollBox.Create(Self);
  FGfxScroll.Parent := FTabGfx;
  FGfxScroll.Align := alClient;
  FGfxScroll.VertScrollBar.Tracking := True;
  FGfxBox := TPaintBox.Create(Self);
  FGfxBox.Parent := FGfxScroll;
  FGfxBox.SetBounds(0, 0, 600, 400);
  FGfxBox.OnPaint := @GfxPaint;

  BuildExportTab;

  FGroupList.ItemIndex := 0;
  ShowGroup(FGroupList.Items[0]);
  RefreshOverview;
  FPages.ActivePage := FTabPerf;
end;

procedure TInfoForm.ShowGroup(const AGroup: string);
var
  i, k: Integer;
  row: TPanel;
  lbl: TLabel;
  track: TTrackBar;
  spin: TFloatSpinEdit;
  chk: TCheckBox;
  btn: TColorButton;
begin
  FParamHeader.Caption := AGroup;
  FParamScroll.DisableAutoSizing;
  try
    while FParamScroll.ControlCount > 0 do FParamScroll.Controls[0].Free;
    for i := 0 to High(ParamDefs) do
    begin
      FTracks[i] := nil; FSpins[i] := nil; FChecks[i] := nil;
      FColors[i] := nil; FHexLabels[i] := nil;
    end;
    k := 0;
    for i := 0 to High(ParamDefs) do
    begin
      if not SameText(ParamDefs[i].Group, AGroup) then Continue;
      row := TPanel.Create(FParamScroll);
      row.Parent := FParamScroll;
      row.BevelOuter := bvNone;
      row.Align := alTop;
      row.Top := k * 200;
      row.BorderSpacing.Around := 3;
      Inc(k);

      lbl := TLabel.Create(row);
      lbl.Parent := row;
      lbl.Align := alTop;
      lbl.Top := 0;
      lbl.Caption := ParamDefs[i].Name;
      lbl.Font.Style := [fsBold];
      lbl.BorderSpacing.Left := 4;

      lbl := TLabel.Create(row);
      lbl.Parent := row;
      lbl.Align := alTop;
      lbl.Top := 20;
      lbl.Caption := ParamDefs[i].Hint;
      lbl.Font.Color := clGrayText;
      lbl.BorderSpacing.Left := 4;

      case ParamDefs[i].Kind of
        pkFloat, pkInt:
          begin
            row.Height := 70;
            spin := TFloatSpinEdit.Create(row);
            spin.Parent := row;
            spin.Align := alRight;
            spin.Width := 100;
            spin.BorderSpacing.Around := 4;
            spin.DecimalPlaces := Decimals(i);
            spin.MinValue := ParamDefs[i].MinV;
            spin.MaxValue := ParamDefs[i].MaxV;
            spin.Increment := IfThen(ParamDefs[i].Kind = pkInt, 1, (ParamDefs[i].MaxV - ParamDefs[i].MinV) / 100);
            spin.Value := GetParam(i);
            spin.Tag := i;
            spin.OnChange := @SpinChange;
            FSpins[i] := spin;
            track := TTrackBar.Create(row);
            track.Parent := row;
            track.Align := alClient;
            track.Min := 0;
            track.Max := 1000;
            track.TickStyle := tsNone;
            track.Position := TrackFromValue(i, GetParam(i));
            track.Tag := i;
            track.OnChange := @TrackChange;
            FTracks[i] := track;
          end;
        pkBool:
          begin
            row.Height := 64;
            chk := TCheckBox.Create(row);
            chk.Parent := row;
            chk.Align := alClient;
            chk.BorderSpacing.Left := 6;
            chk.Caption := 'On';
            chk.Checked := GetParam(i) > 0.5;
            chk.Tag := i;
            chk.OnChange := @CheckChange;
            FChecks[i] := chk;
          end;
        pkColor:
          begin
            row.Height := 76;
            btn := TColorButton.Create(row);
            btn.Parent := row;
            btn.Align := alLeft;
            btn.Width := 140;
            btn.BorderSpacing.Around := 4;
            btn.ButtonColor := BGRAToColor(GetParamColor(i));
            btn.Tag := i;
            btn.OnColorChanged := @ColorChange;
            FColors[i] := btn;
            lbl := TLabel.Create(row);
            lbl.Parent := row;
            lbl.Align := alClient;
            lbl.Layout := tlCenter;
            lbl.BorderSpacing.Left := 8;
            lbl.Caption := ParamToText(i);
            FHexLabels[i] := lbl;
          end;
      end;
    end;
  finally
    FParamScroll.EnableAutoSizing;
  end;
end;

procedure TInfoForm.BuildLayerTab;
var
  k: TLayerKind;
  row, body: TPanel;
  pb: TPaintBox;
  btn: TButton;
  chk: TCheckBox;
  lbl: TLabel;
  track: TTrackBar;
  idx: Integer;
begin
  for k := Low(TLayerKind) to High(TLayerKind) do
  begin
    row := TPanel.Create(FLayerScroll);
    row.Parent := FLayerScroll;
    row.Align := alTop;
    row.Top := Ord(k) * 200;
    row.Height := 104;
    row.BevelOuter := bvLowered;
    row.BorderSpacing.Around := 3;

    pb := TPaintBox.Create(row);
    pb.Parent := row;
    pb.Align := alLeft;
    pb.Width := 56;
    pb.BorderSpacing.Around := 2;
    pb.Tag := Ord(k);
    pb.OnPaint := @LayerPaint;
    FLayerBox[k] := pb;

    btn := TButton.Create(row);
    btn.Parent := row;
    btn.Align := alRight;
    btn.Width := 90;
    btn.BorderSpacing.Left := 8;
    btn.BorderSpacing.Right := 8;
    btn.BorderSpacing.Top := 34;
    btn.BorderSpacing.Bottom := 34;
    btn.Caption := 'Parameters...';
    btn.Tag := Ord(k);
    btn.OnClick := @LayerEditClick;

    body := TPanel.Create(row);
    body.Parent := row;
    body.Align := alClient;
    body.BevelOuter := bvNone;

    chk := TCheckBox.Create(row);
    chk.Parent := body;
    chk.Align := alTop;
    chk.Top := 0;
    chk.BorderSpacing.Left := 8;
    chk.Caption := Format('%d.  %s', [Ord(k) + 1, LayerDefs[k].Name]);
    chk.Font.Style := [fsBold];
    chk.Tag := Ord(k);
    if LayerDefs[k].EnabledName = '' then
    begin
      chk.Checked := True;
      chk.Enabled := False;
    end
    else
      chk.Checked := GetParam(FindParam(LayerDefs[k].Group, LayerDefs[k].EnabledName)) > 0.5;
    chk.OnChange := @LayerCheckChange;
    FLayerCheck[k] := chk;

    lbl := TLabel.Create(row);
    lbl.Parent := body;
    lbl.Align := alTop;
    lbl.Top := 30;
    lbl.WordWrap := True;
    lbl.BorderSpacing.Left := 8;
    lbl.Caption := LayerDefs[k].Desc;

    if LayerDefs[k].AmountName <> '' then
    begin
      idx := FindParam(LayerDefs[k].Group, LayerDefs[k].AmountName);
      track := TTrackBar.Create(row);
      track.Parent := body;
      track.Align := alBottom;
      track.Height := 30;
      track.Min := 0;
      track.Max := 1000;
      track.TickStyle := tsNone;
      track.Position := TrackFromValue(idx, GetParam(idx));
      track.Tag := Ord(k);
      track.Hint := LayerDefs[k].AmountName;
      track.ShowHint := True;
      track.OnChange := @LayerTrackChange;
      FLayerTrack[k] := track;
    end;
  end;
end;

procedure TInfoForm.GroupClick(Sender: TObject);
begin
  if FGroupList.ItemIndex >= 0 then
    ShowGroup(FGroupList.Items[FGroupList.ItemIndex]);
end;

procedure TInfoForm.TrackChange(Sender: TObject);
var
  i: Integer;
begin
  if FUpdating then Exit;
  i := TTrackBar(Sender).Tag;
  SetParam(i, ValueFromTrack(i, TTrackBar(Sender).Position));
  SyncControls;
end;

procedure TInfoForm.SpinChange(Sender: TObject);
var
  i: Integer;
begin
  if FUpdating then Exit;
  i := TFloatSpinEdit(Sender).Tag;
  SetParam(i, TFloatSpinEdit(Sender).Value);
  SyncControls;
end;

procedure TInfoForm.CheckChange(Sender: TObject);
begin
  if FUpdating then Exit;
  SetParam(TCheckBox(Sender).Tag, Ord(TCheckBox(Sender).Checked));
  SyncControls;
end;

procedure TInfoForm.ColorChange(Sender: TObject);
begin
  if FUpdating then Exit;
  SetParamColor(TColorButton(Sender).Tag, ColorToBGRA(ColorToRGB(TColorButton(Sender).ButtonColor)));
  SyncControls;
end;

procedure TInfoForm.LayerCheckChange(Sender: TObject);
var
  k: TLayerKind;
  idx: Integer;
begin
  if FUpdating then Exit;
  k := TLayerKind(TCheckBox(Sender).Tag);
  idx := FindParam(LayerDefs[k].Group, LayerDefs[k].EnabledName);
  if idx >= 0 then SetParam(idx, Ord(TCheckBox(Sender).Checked));
  SyncControls;
end;

procedure TInfoForm.LayerTrackChange(Sender: TObject);
var
  k: TLayerKind;
  idx: Integer;
begin
  if FUpdating then Exit;
  k := TLayerKind(TTrackBar(Sender).Tag);
  idx := FindParam(LayerDefs[k].Group, LayerDefs[k].AmountName);
  if idx >= 0 then SetParam(idx, ValueFromTrack(idx, TTrackBar(Sender).Position));
  SyncControls;
end;

procedure TInfoForm.LayerEditClick(Sender: TObject);
var
  g: string;
begin
  g := LayerDefs[TLayerKind(TButton(Sender).Tag)].Group;
  FGroupList.ItemIndex := FGroupList.Items.IndexOf(g);
  ShowGroup(g);
  FPages.ActivePage := FTabParams;
end;

procedure TInfoForm.SyncControls;
var
  i, idx: Integer;
  k: TLayerKind;
begin
  FUpdating := True;
  try
    for i := 0 to High(ParamDefs) do
    begin
      if Assigned(FTracks[i]) then FTracks[i].Position := TrackFromValue(i, GetParam(i));
      if Assigned(FSpins[i]) and (Abs(FSpins[i].Value - GetParam(i)) > 1e-6) then FSpins[i].Value := GetParam(i);
      if Assigned(FChecks[i]) then FChecks[i].Checked := GetParam(i) > 0.5;
      if Assigned(FColors[i]) then FColors[i].ButtonColor := BGRAToColor(GetParamColor(i));
      if Assigned(FHexLabels[i]) then FHexLabels[i].Caption := ParamToText(i);
    end;
    for k := Low(TLayerKind) to High(TLayerKind) do
    begin
      if LayerDefs[k].EnabledName <> '' then
        FLayerCheck[k].Checked := GetParam(FindParam(LayerDefs[k].Group, LayerDefs[k].EnabledName)) > 0.5;
      if Assigned(FLayerTrack[k]) then
      begin
        idx := FindParam(LayerDefs[k].Group, LayerDefs[k].AmountName);
        FLayerTrack[k].Position := TrackFromValue(idx, GetParam(idx));
      end;
    end;
    if P.Paused then FBtnPause.Caption := 'Resume' else FBtnPause.Caption := 'Pause';
    FLastPaused := P.Paused;
  finally
    FUpdating := False;
  end;
end;

procedure TInfoForm.PageChange(Sender: TObject);
begin
  if FPages.ActivePage = FTabOverview then RefreshOverview
  else if FPages.ActivePage = FTabLayers then RebuildLayerPreviews
  else if FPages.ActivePage = FTabGfx then
  begin
    RebuildGfxSheet;
    FGfxBox.Invalidate;
  end;
end;

procedure TInfoForm.TimerTick(Sender: TObject);
var
  t0: Double;
begin
  t0 := HiResSeconds;
  try
  Inc(FTick);
  if not Visible or (View = nil) or (View.Renderer = nil) then Exit;
  CollectAsync;
  if FLastPaused <> P.Paused then SyncControls;
  if (FPages.ActivePage = FTabPerf) and (FTick mod 2 = 0) then
    FPerfBox.Invalidate
  else if (FPages.ActivePage = FTabLayers) and (FTick mod 3 = 0) then
    RebuildLayerPreviews
  else if (FPages.ActivePage = FTabGfx) and (FTick mod 4 = 0) then
  begin
    if FAsync = nil then StartAsync(2);
    FreeAndNil(FGfxFrame);
    if FGfxPanels[3].Right > 0 then
      FGfxFrame := View.Renderer.SnapshotFast(FGfxPanels[3].Right - FGfxPanels[3].Left,
        FGfxPanels[3].Bottom - FGfxPanels[3].Top);
    if (FGfxBmp = nil) or (GfxSheetKey <> FGfxSheetKey) then RebuildGfxSheet;
    FGfxBox.Invalidate;
  end;
  finally
    TickMsMax := Max(TickMsMax, (HiResSeconds - t0) * 1000);
  end;
end;

procedure TInfoForm.RebuildLayerPreviews;
var
  k: TLayerKind;
  w, h: Integer;
begin
  if (View = nil) or (View.Renderer = nil) then Exit;
  for k := Low(TLayerKind) to High(TLayerKind) do
    if k in MainThreadLayers then
    begin
      w := Max(8, FLayerBox[k].Width);
      h := Max(8, FLayerBox[k].Height);
      FreeAndNil(FLayerBmp[k]);
      FLayerBmp[k] := View.Renderer.BuildPreview(k, w, h);
      FLayerBox[k].Invalidate;
    end;
  { the colour-field / dot-grid previews are computed in the background }
  if FAsync = nil then StartAsync(1);
end;

procedure TInfoForm.GfxPanelSize(out APW, APH: Integer);
var
  Geo: TFrameGeom;
  W: Integer;
begin
  Geo := View.Renderer.ReadyGeom;
  if Geo.W <= 0 then begin Geo.W := 9; Geo.H := 16; end;
  W := Max(560, FGfxScroll.ClientWidth - 4);
  APW := (W - 50) div 4;
  APH := EnsureRange(Round(APW * Geo.H / Geo.W), 40, 600);
end;

procedure TInfoForm.StartAsync(APurpose: Integer);
var
  a: TAsyncImages;
  k: TLayerKind;
  pw, ph: Integer;
begin
  if (FAsync <> nil) or (View = nil) or (View.Renderer = nil) then Exit;
  a := TAsyncImages.Create(View.Renderer, View.Renderer.GeomAt(View.SimTime), APurpose);
  if APurpose = 1 then
  begin
    for k := Low(TLayerKind) to High(TLayerKind) do
      if not (k in MainThreadLayers) then
        a.Add(k, -1, FLayerBox[k].Width, FLayerBox[k].Height);
  end
  else
  begin
    GfxPanelSize(pw, ph);
    a.Add(lkColorField, 0, pw, ph);
    a.Add(lkColorField, 1, pw, ph);
    a.Add(lkJitter, -1, pw, ph);
  end;
  FAsync := a;
  a.Start;
end;

procedure TInfoForm.CollectAsync;
var
  a: TAsyncImages;
  i: Integer;
  k: TLayerKind;
begin
  if (FAsync = nil) or not FAsync.Finished then Exit;
  a := TAsyncImages(FAsync);
  FAsync := nil;
  try
    if a.Purpose = 1 then
      for i := 0 to High(a.Kinds) do
      begin
        if a.Imgs[i] = nil then Continue;
        k := a.Kinds[i];
        FreeAndNil(FLayerBmp[k]);
        FLayerBmp[k] := a.Imgs[i];
        a.Imgs[i] := nil;
        FLayerBox[k].Invalidate;
      end
    else
    begin
      if a.Imgs[0] <> nil then begin FGfxField0.Free; FGfxField0 := a.Imgs[0]; a.Imgs[0] := nil; end;
      if a.Imgs[1] <> nil then begin FGfxField1.Free; FGfxField1 := a.Imgs[1]; a.Imgs[1] := nil; end;
      if a.Imgs[2] <> nil then begin FGfxDots.Free; FGfxDots := a.Imgs[2]; a.Imgs[2] := nil; end;
    end;
  finally
    a.Free;
  end;
end;

procedure TInfoForm.SelectTab(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FPages.PageCount) then
  begin
    FPages.ActivePageIndex := AIndex;
    PageChange(FPages);
  end;
end;

procedure TInfoForm.StopAsync;
begin
  if FAsync = nil then Exit;
  FAsync.Terminate;
  FAsync.WaitFor;
  FreeAndNil(FAsync);
end;

procedure TInfoForm.LayerPaint(Sender: TObject);
var
  k: TLayerKind;
begin
  k := TLayerKind(TPaintBox(Sender).Tag);
  if Assigned(FLayerBmp[k]) then
    FLayerBmp[k].Draw(TPaintBox(Sender).Canvas, 0, 0, True)
  else
  begin
    TPaintBox(Sender).Canvas.Brush.Color := clBlack;
    TPaintBox(Sender).Canvas.FillRect(TPaintBox(Sender).ClientRect);
  end;
end;

procedure TInfoForm.PerfPaint(Sender: TObject);
var
  C: TCanvas;
  R: TNeonRenderer;
  Geo: TFrameGeom;
  wk: TRenderWorker;
  w, h, y, i, n, lh, dots, gy, gh, x0, gw: Integer;
  budget, maxMs, v, PerfT0: Double;
  pts: array of TPoint;

  procedure Head(const S: string);
  begin
    Inc(y, 6);
    C.Font.Color := RGBToColor(90, 210, 235);
    C.TextOut(12, y, S);
    Inc(y, lh + 2);
  end;

  procedure Line(const S: string);
  begin
    C.Font.Color := RGBToColor(225, 225, 230);
    C.TextOut(20, y, S);
    Inc(y, lh);
  end;

  procedure Bar(AX, AY, AW, AH: Integer; AColor: TColor);
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := AColor;
    C.FillRect(AX, AY, AX + AW, AY + AH);
    C.Brush.Style := bsClear;
  end;

begin
  { drawn with plain GDI into a back buffer: ~1 ms, so the SDL frame loop on
    the same main thread keeps its vsync timing }
  PerfT0 := HiResSeconds;
  w := FPerfBox.Width;
  h := FPerfBox.Height;
  if (w < 20) or (h < 20) or (View = nil) or (View.Renderer = nil) then Exit;
  R := View.Renderer;
  Geo := R.ReadyGeom;
  if FPerfBuf = nil then
  begin
    FPerfBuf := TBitmap.Create;
    FPerfBuf.PixelFormat := pf24bit;
  end;
  if (FPerfBuf.Width <> w) or (FPerfBuf.Height <> h) then FPerfBuf.SetSize(w, h);
  C := FPerfBuf.Canvas;
  Bar(0, 0, w, h, RGBToColor(16, 18, 26));
  C.Font.Name := 'Consolas';
  C.Font.Height := -13;
  C.Brush.Style := bsClear;
  lh := 17;
  y := 4;
  if Stats.RefreshHz > 1 then budget := 1000 / Stats.RefreshHz else budget := 1000 / 60;

  Head('DISPLAY');
  Line(Format('Window      %d x %d px      CPU render %d x %d  (scale %.2f)',
    [Stats.ViewW, Stats.ViewH, Stats.RenderW, Stats.RenderH, P.RenderScale]));
  Line(Format('Monitor     %d Hz reported      %.1f Hz measured', [Stats.RefreshHz, Stats.MeasuredHz]));
  Line(Format('VSync       requested %s   active %s   SDL_SetRenderVSync %s',
    [BoolToStr(P.VSync, 'ON', 'off'), BoolToStr(Stats.VSyncActive, 'YES', 'no'),
     BoolToStr(Stats.VSyncSupported, 'available', 'missing')]));

  Head('FRAME');
  Line(Format('FPS         %.1f      frame interval %.2f ms      budget %.2f ms',
    [Stats.FPS, Stats.FrameMs, budget]));
  Line(Format('CPU render  %.2f ms wall-clock on all threads  (%.0f%% of budget)',
    [Stats.CpuMs, Stats.CpuMs / budget * 100]));
  Line(Format('Wait %.2f ms    Upload %.2f ms    Draw+Present %.2f ms',
    [Stats.WaitMs, Stats.UploadMs, Stats.SwapMs]));
  Line(Format('Frames      %d      sim time %.1f s %s',
    [Stats.Frames, View.SimTime, BoolToStr(P.Paused, '(paused)', '')]));

  Head('CPU / BGRABITMAP');
  dots := 0;
  for i := 0 to R.WorkerCount - 1 do dots += R.Worker(i).DotsComputed;
  Line(Format('Logical cores %d     worker threads %d (1 band each, double-buffered)',
    [TThread.ProcessorCount, R.WorkerCount]));
  Line(Format('Grid %d x %d dots   cell %.1f px   dot evaluations/frame %d',
    [Geo.NCols, Geo.NRows, Geo.Cell, dots]));
  Line(Format('Sprite %d x %d px   rebuilds %d   accum: int32 RGB   output: TBGRABitmap bands',
    [R.SpriteSize, R.SpriteSize, R.SpriteRebuilds]));
  if R.LastError <> '' then Line('Last worker error: ' + R.LastError);

  Head('SDL3 OUTPUT');
  Line('Library   ' + Stats.GLVendor);
  Line('Backend   ' + Stats.GLRenderer + '  (SDL_GetRendererName)');
  Line('Path      ' + Stats.GLVersion);
  Line('Upload    SDL_UpdateTexture per band, ' + Stats.TexFormat);
  Line(Format('Info UI   paint max %.1f ms, avg %.1f ms (shares the main thread with SDL)',
    [PaintMsMax, PaintMsSum / Max(1, PaintCount)]));

  Head('THREAD JOBS (ms, bar = share of frame budget)');
  n := R.WorkerCount;
  if n > 16 then lh := 13;
  for i := 0 to n - 1 do
  begin
    wk := R.Worker(i);
    C.Font.Color := RGBToColor(200, 200, 210);
    C.TextOut(20, y, Format('T%.2d rows %4d-%4d %5.2f  dot %4.2f spr %4.2f fin %4.2f',
      [i, wk.Y0, wk.Y1 - 1, wk.JobMs, wk.PhaseMs[0], wk.PhaseMs[1], wk.PhaseMs[2]]));
    x0 := 470;
    gw := w - x0 - 20;
    Bar(x0, y + 3, gw, lh - 6, RGBToColor(40, 44, 56));
    Bar(x0, y + 3, Round(Min(1, wk.JobMs / budget) * gw), lh - 6, RGBToColor(230, 140, 40));
    Inc(y, lh);
  end;
  lh := 17;

  Head('FRAME INTERVAL HISTORY (ms)   green = refresh budget');
  gy := y + 4;
  gh := h - gy - 12;
  if gh > 40 then
  begin
    x0 := 50;
    gw := w - x0 - 16;
    maxMs := budget * 2.5;
    for i := 0 to High(Stats.History) do maxMs := Max(maxMs, Stats.History[i]);
    C.Pen.Width := 1;
    C.Pen.Color := RGBToColor(60, 66, 80);
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(22, 25, 34);
    C.Rectangle(x0, gy, x0 + gw, gy + gh);
    C.Brush.Style := bsClear;
    v := gy + gh - budget / maxMs * gh;
    C.Pen.Color := RGBToColor(60, 200, 90);
    C.Line(x0, Round(v), x0 + gw, Round(v));
    C.Font.Color := RGBToColor(60, 200, 90);
    C.TextOut(6, Round(v) - 8, FormatFloat('0.0', budget));
    C.Font.Color := RGBToColor(150, 150, 160);
    C.TextOut(6, gy, FormatFloat('0', maxMs));
    SetLength(pts, Length(Stats.History));
    for i := 0 to High(Stats.History) do
    begin
      v := Stats.History[(Stats.HistPos + i) mod Length(Stats.History)];
      pts[i] := Point(x0 + Round(i / High(Stats.History) * gw), gy + gh - Round(Min(v, maxMs) / maxMs * gh));
    end;
    C.Pen.Color := RGBToColor(90, 210, 235);
    C.Polyline(pts);
  end;
  FPerfBox.Canvas.Draw(0, 0, FPerfBuf);
  v := (HiResSeconds - PerfT0) * 1000;
  PaintMsMax := Max(PaintMsMax, v);
  PaintMsSum += v;
  Inc(PaintCount);
end;

procedure TInfoForm.RebuildGfxSheet(AWithText: Boolean);
type
  TSwatch = record
    Name: string;
    C: TBGRAPixel;
  end;
var
  R: TNeonRenderer;
  Geo: TFrameGeom;
  W, N, z, pw, ph, x, y, i, rows1, rows3, totalH, cw: Integer;
  tmp: TBGRABitmap;
  masks: array[0..5] of TBGRABitmap;
  names: array[0..5] of string;
  sw: array of TSwatch;

  { live view: text is drawn by GfxPaint with GDI; exported sheet: into the bitmap }
  procedure AddText(AX, AY, ASize: Integer; const AText: string; const AColor: TBGRAPixel; ABold: Boolean);
  var
    n: Integer;
  begin
    if AWithText then
    begin
      FGfxBmp.FontHeight := ASize;
      if ABold then FGfxBmp.FontStyle := [fsBold] else FGfxBmp.FontStyle := [];
      FGfxBmp.TextOut(AX, AY, AText, AColor);
      FGfxBmp.FontStyle := [];
      Exit;
    end;
    n := Length(FGfxTexts);
    SetLength(FGfxTexts, n + 1);
    FGfxTexts[n].X := AX;
    FGfxTexts[n].Y := AY;
    FGfxTexts[n].Size := ASize;
    FGfxTexts[n].Bold := ABold;
    FGfxTexts[n].S := AText;
    FGfxTexts[n].C := AColor;
  end;

  procedure Title(AX, AY: Integer; const S: string);
  begin
    AddText(AX, AY, 15, S, BGRA(90, 210, 235), True);
  end;

  procedure Caption_(AX, AY: Integer; const S: string);
  begin
    AddText(AX, AY, 13, S, BGRA(210, 210, 220), False);
  end;

  procedure AddSwatch(const AName: string; const AC: TBGRAPixel);
  begin
    SetLength(sw, Length(sw) + 1);
    sw[High(sw)].Name := AName;
    sw[High(sw)].C := AC;
  end;

  procedure PutPanel(ABmp: TBGRABitmap; AOwned: Boolean; AX, AY: Integer; const ACaption: string);
  begin
    FGfxPanels[(AX - 10) div (pw + 10)] := Rect(AX, AY, AX + pw, AY + ph);
    if Assigned(ABmp) then
    begin
      if (ABmp.Width = pw) and (ABmp.Height = ph) then
        FGfxBmp.PutImage(AX, AY, ABmp, dmSet)
      else
        FGfxBmp.StretchPutImage(Rect(AX, AY, AX + pw, AY + ph), ABmp, dmSet);
      if AOwned then ABmp.Free;
    end;
    FGfxBmp.Rectangle(AX - 1, AY - 1, AX + pw + 1, AY + ph + 1, BGRA(70, 76, 90), dmSet);
    Caption_(AX, AY + ph + 4, ACaption);
  end;

begin
  if (View = nil) or (View.Renderer = nil) then Exit;
  R := View.Renderer;
  if R.SpriteComposite = nil then Exit;
  Geo := R.ReadyGeom;
  if Geo.W <= 0 then begin Geo.W := 9; Geo.H := 16; end;
  sw := nil;
  W := Max(560, FGfxScroll.ClientWidth - 4);
  N := R.SpriteSize;
  z := Max(1, Min(6, 150 div Max(1, N)));
  cw := Max(N * z, 90) + 14;
  rows1 := Max(1, Ceil(6 * cw / (W - 20)));
  pw := (W - 50) div 4;
  ph := EnsureRange(Round(pw * Geo.H / Geo.W), 40, 600);

  AddSwatch('Background', P.BgColor);
  AddSwatch('Ambient', P.AmbientColor);
  AddSwatch('Boundary', P.BoundaryColor);
  AddSwatch('Spark', P.SparkColor);
  AddSwatch('Highlight', P.HighlightColor);
  for i := 0 to PaletteSize - 1 do AddSwatch('Palette ' + IntToStr(i + 1), P.Palette[i]);
  for i := 0 to MaxBlobs - 1 do AddSwatch('Blob ' + IntToStr(i + 1), P.Blobs[i].Color);
  rows3 := Ceil(Length(sw) * 100 / (W - 20));
  totalH := 34 + rows1 * (N * z + 34) + 30 + ph + 40 + 30 + rows3 * 78 + 30 + 140;

  FreeAndNil(FGfxBmp);
  FreeAndNil(FGfxDDB);
  FGfxTexts := nil;
  FGfxSheetTick := FTick;
  FGfxSheetKey := GfxSheetKey;
  FGfxBmp := TBGRABitmap.Create(W, totalH, BGRA(16, 18, 26));
  FGfxBmp.FontName := 'Segoe UI';
  FGfxBmp.FontQuality := fqSystemClearType;

  { row 1: sprite layers drawn with BGRABitmap }
  y := 8;
  Title(10, y, Format('DOT SPRITE LAYERS  -  %d x %d px, shown x%d  (fill/center/ring/glow/sparks are white masks)', [N, N, z]));
  y += 26;
  masks[0] := R.SpriteComposite; names[0] := 'Composite (sample tint)';
  masks[1] := R.LayerFill;       names[1] := 'Fill disc';
  masks[2] := R.LayerCenter;     names[2] := 'Center cross';
  masks[3] := R.LayerRing;       names[3] := 'Ring outline';
  masks[4] := R.LayerGlow;       names[4] := 'Glow (radial blur)';
  masks[5] := R.LayerSpark;      names[5] := 'Contact sparks';
  x := 10;
  for i := 0 to 5 do
  begin
    if x + cw > W then
    begin
      x := 10;
      y += N * z + 34;
    end;
    if Assigned(masks[i]) then
    begin
      tmp := masks[i].Resample(N * z, N * z, rmSimpleStretch) as TBGRABitmap;
      FGfxBmp.PutImage(x, y, tmp, dmSet);
      tmp.Free;
      FGfxBmp.Rectangle(x - 1, y - 1, x + N * z + 1, y + N * z + 1, BGRA(70, 76, 90), dmSet);
    end;
    Caption_(x, y + N * z + 4, names[i]);
    x += cw;
  end;
  y += N * z + 34;

  { row 2: colour field maps and live frame }
  Title(10, y, 'COLOUR FIELD  -  blobs, modifiers, per-dot colours, final frame (live)');
  y += 28;
  x := 10;
  if AWithText then PutPanel(R.BuildFieldMap(pw, ph, False), True, x, y, 'Blobs + ambient') else PutPanel(FGfxField0, False, x, y, 'Blobs + ambient');
  x += pw + 10;
  if AWithText then PutPanel(R.BuildFieldMap(pw, ph, True), True, x, y, '+ boundary + shadow') else PutPanel(FGfxField1, False, x, y, '+ boundary + shadow');
  x += pw + 10;
  if AWithText then PutPanel(R.BuildPreview(lkJitter, pw, ph), True, x, y, 'Dot colours (all effects)') else PutPanel(FGfxDots, False, x, y, 'Dot colours (all effects)');
  x += pw + 10;
  if AWithText then PutPanel(R.Snapshot(pw, ph), True, x, y, 'Final frame') else PutPanel(nil, False, x, y, 'Final frame');
  y += ph + 40;

  { row 3: colours }
  Title(10, y, 'COLOURS');
  y += 28;
  x := 10;
  for i := 0 to High(sw) do
  begin
    if x + 100 > W then
    begin
      x := 10;
      y += 78;
    end;
    FGfxBmp.FillRect(x, y, x + 88, y + 34, sw[i].C, dmSet);
    FGfxBmp.Rectangle(x - 1, y - 1, x + 89, y + 35, BGRA(70, 76, 90), dmSet);
    Caption_(x, y + 38, sw[i].Name);
    Caption_(x, y + 54, ColorToHex(sw[i].C));
    x += 100;
  end;
  y += 78 + 10;

  { metrics }
  Title(10, y, 'GEOMETRY');
  y += 26;
  Caption_(14, y, Format('Cell %.2f px    radius %.2f px    ring %.2f px    glow blur %.2f px    spark %.2f px    center %.2f px',
    [Geo.Cell, P.DotRadius * Geo.Cell, Max(1, P.RingWidth * Geo.Cell), Max(0.5, P.GlowRadius * Geo.Cell),
     Max(0.6, P.SparkSize * Geo.Cell), Max(1, P.CenterSize * Geo.Cell * 0.5)]));
  y += 20;
  Caption_(14, y, Format('Grid origin (%.1f, %.1f)   columns %d   rows %d   frame %d x %d',
    [Geo.OriginX, Geo.OriginY, Geo.NCols, Geo.NRows, Geo.W, Geo.H]));

  FGfxBox.SetBounds(0, 0, FGfxBmp.Width, FGfxBmp.Height);
end;

function TInfoForm.GfxSheetKey: string;
var
  i, pw, ph: Integer;
begin
  Result := '';
  if (View = nil) or (View.Renderer = nil) then Exit;
  GfxPanelSize(pw, ph);
  Result := Format('%d|%d|%d|%d|%.2f|%s%s%s%s%s', [View.Renderer.SpriteRebuilds,
    FGfxScroll.ClientWidth, pw, ph, View.Renderer.ReadyGeom.Cell, ColorToHex(P.BgColor),
    ColorToHex(P.AmbientColor), ColorToHex(P.BoundaryColor), ColorToHex(P.SparkColor),
    ColorToHex(P.HighlightColor)]);
  for i := 0 to PaletteSize - 1 do Result += ColorToHex(P.Palette[i]);
  for i := 0 to MaxBlobs - 1 do Result += ColorToHex(P.Blobs[i].Color);
end;

procedure TInfoForm.GfxPaint(Sender: TObject);
var
  i: Integer;
begin
  if not Assigned(FGfxBmp) then Exit;
  if FGfxDDB = nil then
  begin
    { convert the static sheet once: bitmap + text in a GDI bitmap }
    FGfxDDB := TBitmap.Create;
    FGfxDDB.PixelFormat := pf24bit;  // no alpha channel: GDI text stays opaque
    FGfxDDB.SetSize(FGfxBmp.Width, FGfxBmp.Height);
    FGfxBmp.Draw(FGfxDDB.Canvas, 0, 0, True);
    with FGfxDDB.Canvas do
    begin
      Font.Name := 'Segoe UI';
      Brush.Style := bsClear;
      for i := 0 to High(FGfxTexts) do
      begin
        Font.Height := -FGfxTexts[i].Size;
        if FGfxTexts[i].Bold then Font.Style := [fsBold] else Font.Style := [];
        Font.Color := BGRAToColor(FGfxTexts[i].C);
        TextOut(FGfxTexts[i].X, FGfxTexts[i].Y, FGfxTexts[i].S);
      end;
    end;
  end;
  FGfxBox.Canvas.Draw(0, 0, FGfxDDB);
  if Assigned(FGfxField0) then FGfxField0.Draw(FGfxBox.Canvas, FGfxPanels[0], True);
  if Assigned(FGfxField1) then FGfxField1.Draw(FGfxBox.Canvas, FGfxPanels[1], True);
  if Assigned(FGfxDots) then FGfxDots.Draw(FGfxBox.Canvas, FGfxPanels[2], True);
  if Assigned(FGfxFrame) then FGfxFrame.Draw(FGfxBox.Canvas, FGfxPanels[3], True);
end;

procedure TInfoForm.RefreshOverview;
var
  sl: TStringList;
  i: Integer;
  k: TLayerKind;
  g: string;
begin
  sl := TStringList.Create;
  try
    sl.Add('NEON DOT GRID SDL3 - animated UI background');
    sl.Add('===========================================');
    sl.Add('Recreates the neon bead/LED mosaic wallpaper (see image-description.md):');
    sl.Add('a grid of glowing translucent circles on black, diamond gaps between them,');
    sl.Add('warm orange/teal left side, dark navy right side, a colourful diagonal');
    sl.Add('stream and white-hot highlighted rings.');
    sl.Add('');
    sl.Add('RENDER PIPELINE (per frame)');
    sl.Add('  CPU  : ' + IntToStr(TThread.ProcessorCount) + ' logical cores -> one worker thread per core (Rendering/Threads).');
    sl.Add('         The frame is split into horizontal bands, one TBGRABitmap per worker.');
    sl.Add('    1. Dot pass     colour field + boundary + shadow + jitter + sparkles + trail + highlights + breathing');
    sl.Add('    2. Sprite pass  additive int32 accumulation of the BGRABitmap-built dot sprite');
    sl.Add('                    (fill*lens*(1-center) * fillColour + (ring+glow) * ringColour + sparks * sparkColour)');
    sl.Add('    3. Final pass   background + bilinear haze + accumulator, * exposure * vignette -> band pixels');
    sl.Add('  SDL3 : SDL_UpdateTexture per band into a streaming texture -> SDL_RenderTexture ->');
    sl.Add('         SDL_RenderPresent with SDL_SetRenderVSync(1) (backend: ' + Stats.GLRenderer + ').');
    sl.Add('  Double buffering: workers render frame N+1 while SDL waits for vsync with frame N,');
    sl.Add('  so the frame rate follows the monitor refresh (60 / 120 / 144 Hz ...).');
    sl.Add('');
    sl.Add('LAYER STACK (bottom -> top)');
    for k := Low(TLayerKind) to High(TLayerKind) do
      sl.Add(Format('  %2d. %-15s %s', [Ord(k) + 1, LayerDefs[k].Name, LayerDefs[k].Desc]));
    sl.Add('');
    sl.Add('KEYS (main window)');
    sl.Add('  F1 show/hide this window   F11 or Alt+Enter fullscreen   Esc leave fullscreen   Space pause');
    sl.Add('');
    sl.Add(Format('ALL PARAMETERS (%d)  -  group / name = value  [range]  hint', [Length(ParamDefs)]));
    g := '';
    for i := 0 to High(ParamDefs) do
    begin
      if ParamDefs[i].Group <> g then
      begin
        g := ParamDefs[i].Group;
        sl.Add('');
        sl.Add('[' + g + ']');
      end;
      if ParamDefs[i].Kind in [pkFloat, pkInt] then
        sl.Add(Format('  %-18s = %-9s [%g .. %g]  %s', [ParamDefs[i].Name, ParamToText(i),
          ParamDefs[i].MinV, ParamDefs[i].MaxV, ParamDefs[i].Hint]))
      else
        sl.Add(Format('  %-18s = %-9s %s', [ParamDefs[i].Name, ParamToText(i), ParamDefs[i].Hint]));
    end;
    FOverview.Lines.Assign(sl);
  finally
    sl.Free;
  end;
end;

procedure TInfoForm.BtnResetClick(Sender: TObject);
begin
  ResetDefaults;
  SyncControls;
  RefreshOverview;
end;

procedure TInfoForm.BtnSaveClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := 'Neon preset (*.ini)|*.ini';
    dlg.DefaultExt := 'ini';
    dlg.FileName := 'neon-preset.ini';
    if dlg.Execute then SaveParams(dlg.FileName);
  finally
    dlg.Free;
  end;
end;

procedure TInfoForm.BtnLoadClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := 'Neon preset (*.ini)|*.ini';
    if dlg.Execute then
    begin
      LoadParams(dlg.FileName);
      SyncControls;
      RefreshOverview;
    end;
  finally
    dlg.Free;
  end;
end;

procedure TInfoForm.BtnPauseClick(Sender: TObject);
begin
  P.Paused := not P.Paused;
  SyncControls;
end;

procedure TInfoForm.BtnFullClick(Sender: TObject);
begin
  if Assigned(View) then View.ToggleFullScreen;
end;

procedure TInfoForm.BtnHideClick(Sender: TObject);
begin
  Hide;
end;

procedure TInfoForm.InfoCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  { this LCL form is the application's main form: closing it only hides it,
    the program ends when the SDL window is closed }
  CanClose := Application.Terminated;
  if not CanClose then Hide;
end;

{ ---------------------------------------------------------------- Export tab }

function TInfoForm.NextOrder: Integer;
begin
  Inc(FOrder, 10);
  Result := 1000 + FOrder;
end;

function FileSizeKB(const AFileName: string): string;
var
  sr: TSearchRec;
begin
  Result := '?';
  if FindFirst(AFileName, faAnyFile, sr) = 0 then
  begin
    Result := FormatFloat('#,##0', sr.Size / 1024) + ' KB';
    FindClose(sr);
  end;
end;

function TInfoForm.AddRow(AParent: TWinControl; AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.BevelOuter := bvNone;
  Result.Align := alTop;
  Result.Top := NextOrder;
  Result.Height := AHeight;
end;

function TInfoForm.AddLbl(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Align := alLeft;
  Result.Left := NextOrder;
  Result.Layout := tlCenter;
  Result.BorderSpacing.Left := 8;
  Result.BorderSpacing.Right := 2;
end;

function TInfoForm.AddSpin(AParent: TWinControl; AMin, AMax, AValue: Integer): TSpinEdit;
begin
  Result := TSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.Align := alLeft;
  Result.Left := NextOrder;
  Result.Width := 70;
  Result.BorderSpacing.Around := 4;
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Value := AValue;
end;

function TInfoForm.AddGroup(const ACaption: string; AHeight: Integer): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Parent := FTabExport;
  Result.Caption := ACaption;
  Result.Align := alTop;
  Result.Top := NextOrder;
  Result.Height := AHeight;
  Result.BorderSpacing.Around := 4;
end;

procedure TInfoForm.BuildExportTab;
var
  gb: TGroupBox;
  row: TPanel;
  btn: TButton;
  k: TLayerKind;
  gi: TGraphicItem;
  s: string;

  function RunButton(AParent: TWinControl; const ACaption: string; ATag: Integer): TButton;
  begin
    Result := MakeButton(AParent, ACaption, @ExpRunClick);
    Result.Tag := ATag;
  end;

  function CheckButton(AParent: TWinControl; const ACaption: string; ATag: Integer): TButton;
  begin
    Result := MakeButton(AParent, ACaption, @ExpCheckClick);
    Result.Tag := ATag;
  end;

begin
  { output settings }
  gb := AddGroup('Output', 176);
  row := AddRow(gb, 34);
  AddLbl(row, 'Folder');
  btn := MakeButton(row, 'Open folder', @ExpOpenClick);
  btn.Align := alRight;
  btn := MakeButton(row, 'Browse...', @ExpBrowseClick);
  btn.Align := alRight;
  FExpFolder := TEdit.Create(Self);
  FExpFolder.Parent := row;
  FExpFolder.Align := alClient;
  FExpFolder.BorderSpacing.Around := 4;
  FExpFolder.Text := ExtractFilePath(Application.ExeName) + 'export';

  row := AddRow(gb, 34);
  AddLbl(row, 'Layer / graphic size');
  FExpW := AddSpin(row, 16, 4096, 360);
  AddLbl(row, 'x');
  FExpH := AddSpin(row, 16, 4096, 640);
  MakeButton(row, 'Match main window aspect', @ExpAspectClick);

  row := AddRow(gb, 34);
  AddLbl(row, 'GIF frames');
  FExpFrames := AddSpin(row, 1, 600, 60);
  AddLbl(row, 'GIF fps');
  FExpFps := AddSpin(row, 1, 50, 20);
  AddLbl(row, 'Main window GIF scale');
  FExpScale := TFloatSpinEdit.Create(Self);
  FExpScale.Parent := row;
  FExpScale.Align := alLeft;
  FExpScale.Left := NextOrder;
  FExpScale.Width := 70;
  FExpScale.BorderSpacing.Around := 4;
  FExpScale.MinValue := 0.1;
  FExpScale.MaxValue := 1;
  FExpScale.Increment := 0.05;
  FExpScale.DecimalPlaces := 2;
  FExpScale.Value := 0.5;

  row := AddRow(gb, 34);
  AddLbl(row, 'MP4 seconds');
  FMp4Secs := AddSpin(row, 1, 600, 10);
  AddLbl(row, 'MP4 fps');
  FMp4Fps := AddSpin(row, 1, 240, 60);
  AddLbl(row, 'Mbps');
  FMp4Mbps := AddSpin(row, 1, 200, 16);
  AddLbl(row, 'Main MP4 scale');
  FMp4Scale := TFloatSpinEdit.Create(Self);
  FMp4Scale.Parent := row;
  FMp4Scale.Align := alLeft;
  FMp4Scale.Left := NextOrder;
  FMp4Scale.Width := 64;
  FMp4Scale.BorderSpacing.Around := 4;
  FMp4Scale.MinValue := 0.1;
  FMp4Scale.MaxValue := 1;
  FMp4Scale.Increment := 0.05;
  FMp4Scale.DecimalPlaces := 2;
  FMp4Scale.Value := 1;
  FMp4Hw := TCheckBox.Create(Self);
  FMp4Hw.Parent := row;
  FMp4Hw.Align := alLeft;
  FMp4Hw.Left := NextOrder;
  FMp4Hw.BorderSpacing.Left := 10;
  FMp4Hw.Caption := 'GPU encoder';
  FMp4Hw.Hint := 'Allow a hardware H.264 encoder (falls back to the Windows software encoder).';
  FMp4Hw.ShowHint := True;
  FMp4Hw.Checked := True;

  { layers }
  gb := AddGroup('Layers  (PNG = current moment, GIF/MP4 = animation from now; static layers: 1-frame GIF, no MP4)', 230);
  row := AddRow(gb, 36);
  row.Align := alBottom;
  RunButton(row, 'Save PNG', 1);
  RunButton(row, 'Save GIF', 2);
  RunButton(row, 'Save MP4', 7);
  CheckButton(row, 'Select all', 1);
  CheckButton(row, 'Select none', 2);
  FExpLayers := TCheckListBox.Create(Self);
  FExpLayers.Parent := gb;
  FExpLayers.Align := alClient;
  FExpLayers.BorderSpacing.Around := 4;
  FExpLayers.Columns := 2;
  for k := Low(TLayerKind) to High(TLayerKind) do
  begin
    s := Format('%.2d. %s', [Ord(k) + 1, LayerDefs[k].Name]);
    if LayerAnimated(k) then s += '   (animated)';
    FExpLayers.Items.Add(s);
    FExpLayers.Checked[Ord(k)] := True;
  end;

  { graphics }
  gb := AddGroup('Graphics  (sprite masks are scaled by a whole factor to fit, keeping pixels crisp)', 200);
  row := AddRow(gb, 36);
  row.Align := alBottom;
  RunButton(row, 'Save PNG', 3);
  RunButton(row, 'Save GIF', 4);
  RunButton(row, 'Save MP4', 8);
  CheckButton(row, 'Select all', 3);
  CheckButton(row, 'Select none', 4);
  FExpGraphics := TCheckListBox.Create(Self);
  FExpGraphics.Parent := gb;
  FExpGraphics.Align := alClient;
  FExpGraphics.BorderSpacing.Around := 4;
  FExpGraphics.Columns := 2;
  for gi := Low(TGraphicItem) to High(TGraphicItem) do
  begin
    s := GraphicNames[gi];
    if GraphicAnimated[gi] then s += '   (animated)';
    FExpGraphics.Items.Add(s);
    FExpGraphics.Checked[Ord(gi)] := True;
  end;

  { main window }
  gb := AddGroup('Main window', 70);
  row := AddRow(gb, 36);
  RunButton(row, 'Capture PNG (current frame, full resolution)', 5);
  RunButton(row, 'Record GIF (frames x fps, scaled)', 6);
  RunButton(row, 'Record MP4 (H.264, seconds x fps)', 9);

  { log }
  gb := TGroupBox.Create(Self);
  gb.Parent := FTabExport;
  gb.Caption := 'Log';
  gb.Align := alClient;
  gb.BorderSpacing.Around := 4;
  FExpProgress := TProgressBar.Create(Self);
  FExpProgress.Parent := gb;
  FExpProgress.Align := alTop;
  FExpProgress.Height := 18;
  FExpProgress.BorderSpacing.Around := 4;
  FExpLog := TMemo.Create(Self);
  FExpLog.Parent := gb;
  FExpLog.Align := alClient;
  FExpLog.ReadOnly := True;
  FExpLog.ScrollBars := ssAutoBoth;
  FExpLog.WordWrap := False;
  FExpLog.Font.Name := 'Consolas';
  FExpLog.Font.Size := 9;
end;

procedure TInfoForm.ExpLog(const S: string);
begin
  FExpLog.Lines.Add(FormatDateTime('hh:nn:ss  ', Now) + S);
  FExpLog.SelStart := Length(FExpLog.Text);
end;

procedure TInfoForm.ExpProgress(ADone, ATotal: Integer);
begin
  FExpProgress.Max := Max(1, ATotal);
  FExpProgress.Position := ADone;
  Application.ProcessMessages;  // keep the UI and the main window animating
end;

function TInfoForm.ExportDir: string;
begin
  Result := IncludeTrailingPathDelimiter(Trim(FExpFolder.Text));
  if not ForceDirectories(Result) then
    raise Exception.Create('Cannot create folder ' + Result);
end;

function TInfoForm.GifDelayMs: Integer;
begin
  Result := Round(1000 / Max(1, FExpFps.Value));
end;

function TInfoForm.GifTimeStep: Double;
var
  ts: Double;
begin
  ts := P.TimeScale;
  if ts <= 0 then ts := 1;
  Result := ts / Max(1, FExpFps.Value);
end;

procedure TInfoForm.ExpBrowseClick(Sender: TObject);
var
  dlg: TSelectDirectoryDialog;
begin
  dlg := TSelectDirectoryDialog.Create(Self);
  try
    dlg.InitialDir := FExpFolder.Text;
    if dlg.Execute then FExpFolder.Text := dlg.FileName;
  finally
    dlg.Free;
  end;
end;

procedure TInfoForm.ExpOpenClick(Sender: TObject);
begin
  OpenDocument(ExportDir);
end;

procedure TInfoForm.ExpAspectClick(Sender: TObject);
var
  Geo: TFrameGeom;
begin
  if (View = nil) or (View.Renderer = nil) then Exit;
  Geo := View.Renderer.ReadyGeom;
  if Geo.W > 0 then FExpH.Value := Round(FExpW.Value * Geo.H / Geo.W);
end;

procedure TInfoForm.ExpCheckClick(Sender: TObject);
var
  list: TCheckListBox;
  i: Integer;
begin
  if TButton(Sender).Tag <= 2 then list := FExpLayers else list := FExpGraphics;
  for i := 0 to list.Items.Count - 1 do
    list.Checked[i] := Odd(TButton(Sender).Tag);
end;

procedure TInfoForm.ExpRunClick(Sender: TObject);
begin
  if FExporting or (View = nil) or (View.Renderer = nil) then Exit;
  FExporting := True;
  Screen.Cursor := crHourGlass;
  try
    try
      case TButton(Sender).Tag of
        1: ExportLayers(False);
        2: ExportLayers(True);
        3: ExportGraphics(False);
        4: ExportGraphics(True);
        5: ExportMainPng;
        6: ExportMainGif;
        7: ExportLayersMp4;
        8: ExportGraphicsMp4;
        9: ExportMainMp4;
      end;
    except
      on E: Exception do ExpLog('ERROR: ' + E.Message);
    end;
  finally
    if Assigned(View.Renderer) then View.Renderer.UsePreviewTime := False;
    FExpProgress.Position := 0;
    Screen.Cursor := crDefault;
    FExporting := False;
  end;
end;

procedure TInfoForm.ExportLayers(AGif: Boolean);
var
  R: TNeonRenderer;
  dir, fn: string;
  k: TLayerKind;
  w, h, n, i, total, done, files: Integer;
  t0: Double;
  bmp: TBGRABitmap;
  gw: TGifWriter;
begin
  R := View.Renderer;
  dir := ExportDir;
  w := FExpW.Value;
  h := FExpH.Value;
  t0 := View.SimTime;
  total := 0;
  for k := Low(TLayerKind) to High(TLayerKind) do
    if FExpLayers.Checked[Ord(k)] then
      if AGif and LayerAnimated(k) then total += FExpFrames.Value else total += 1;
  if total = 0 then
  begin
    ExpLog('No layer selected.');
    Exit;
  end;
  done := 0;
  files := 0;
  for k := Low(TLayerKind) to High(TLayerKind) do
  begin
    if not FExpLayers.Checked[Ord(k)] then Continue;
    fn := dir + Format('layer_%.2d_%s', [Ord(k) + 1, SafeName(LayerDefs[k].Name)]);
    if not AGif then
    begin
      R.UsePreviewTime := False;
      bmp := R.BuildPreview(k, w, h);
      try
        bmp.SaveToFile(fn + '.png');
      finally
        bmp.Free;
      end;
      Inc(done);
      ExpLog('PNG  ' + fn + '.png  (' + FileSizeKB(fn + '.png') + ')');
      ExpProgress(done, total);
    end
    else
    begin
      if LayerAnimated(k) then n := FExpFrames.Value else n := 1;
      gw := TGifWriter.Create(w, h, GifDelayMs);
      try
        FCurGif := gw;
        try
          RunPreviewFrames(True, k, giSprite, w, h, n, t0, GifTimeStep, done, total);
        finally
          FCurGif := nil;
        end;
        gw.Save(fn + '.gif');
      finally
        gw.Free;
      end;
      ExpLog(Format('GIF  %s.gif  (%d frames, %s)', [fn, n, FileSizeKB(fn + '.gif')]));
    end;
    Inc(files);
  end;
  ExpLog(Format('Done: %d layer file(s) in %s', [files, dir]));
end;

function TInfoForm.MakeGraphic(AItem: TGraphicItem; AW, AH: Integer; ATime: Double; ATimed: Boolean;
  var AOffline: TNeonRenderer): TBGRABitmap;
var
  R: TNeonRenderer;
  rw, rh: Integer;
begin
  R := View.Renderer;
  R.PreviewTime := ATime;
  R.UsePreviewTime := ATimed;
  Result := nil;
  case AItem of
    giSprite, giFill, giCenter, giRing, giGlow, giSpark:
      Result := RenderSpriteItem(R, AItem, AW, AH);
    giFieldBlobs:
      Result := R.BuildFieldMap(AW, AH, False);
    giFieldFull:
      Result := R.BuildFieldMap(AW, AH, True);
    giDotColours:
      Result := R.BuildPreview(lkJitter, AW, AH);
    giFinalFrame:
      begin
        if not ATimed then Result := R.Snapshot(AW, AH);
        if Result = nil then
        begin
          { render the exact moment offline, at the main window's render size }
          if AOffline = nil then AOffline := TNeonRenderer.Create;
          rw := R.ReadyGeom.W;
          rh := R.ReadyGeom.H;
          if rw <= 0 then begin rw := 600; rh := 1066; end;
          AOffline.BeginFrame(rw, rh, ATime);
          AOffline.WaitFrame;
          Result := AOffline.Snapshot(AW, AH);
        end;
      end;
    giPalette:
      Result := RenderSwatches(AW, AH);
    giSheet:
      begin
        RebuildGfxSheet(True);
        if Assigned(FGfxBmp) then
        begin
          Result := TBGRABitmap.Create(FGfxBmp.Width, FGfxBmp.Height);
          Result.PutImage(0, 0, FGfxBmp, dmSet);
        end;
      end;
  end;
  R.UsePreviewTime := False;
  if Result = nil then Result := TBGRABitmap.Create(Max(1, AW), Max(1, AH), BGRABlack);
end;

procedure TInfoForm.ExportGraphics(AGif: Boolean);
var
  dir, fn: string;
  gi: TGraphicItem;
  w, h, n, i, total, done, files: Integer;
  t0: Double;
  bmp: TBGRABitmap;
  gw: TGifWriter;
  off: TNeonRenderer;
begin
  dir := ExportDir;
  w := FExpW.Value;
  h := FExpH.Value;
  t0 := View.SimTime;
  total := 0;
  for gi := Low(TGraphicItem) to High(TGraphicItem) do
    if FExpGraphics.Checked[Ord(gi)] then
      if AGif and GraphicAnimated[gi] then total += FExpFrames.Value else total += 1;
  if total = 0 then
  begin
    ExpLog('No graphic selected.');
    Exit;
  end;
  done := 0;
  files := 0;
  off := nil;
  try
    for gi := Low(TGraphicItem) to High(TGraphicItem) do
    begin
      if not FExpGraphics.Checked[Ord(gi)] then Continue;
      fn := dir + 'graphic_' + SafeName(GraphicNames[gi]);
      if not AGif then
      begin
        bmp := MakeGraphic(gi, w, h, t0, False, off);
        try
          bmp.SaveToFile(fn + '.png');
        finally
          bmp.Free;
        end;
        Inc(done);
        ExpLog('PNG  ' + fn + '.png  (' + FileSizeKB(fn + '.png') + ')');
        ExpProgress(done, total);
      end
      else
      begin
        if GraphicAnimated[gi] then n := FExpFrames.Value else n := 1;
        gw := nil;
        try
          if gi in ParallelGraphics then
          begin
            gw := TGifWriter.Create(w, h, GifDelayMs);
            FCurGif := gw;
            try
              RunPreviewFrames(False, lkBackground, gi, w, h, n, t0, GifTimeStep, done, total);
            finally
              FCurGif := nil;
            end;
          end
          else
            for i := 0 to n - 1 do
            begin
              bmp := MakeGraphic(gi, w, h, t0 + i * GifTimeStep, GraphicAnimated[gi], off);
              try
                if gw = nil then gw := TGifWriter.Create(bmp.Width, bmp.Height, GifDelayMs);
                gw.Add(bmp);
              finally
                bmp.Free;
              end;
              Inc(done);
              ExpProgress(done, total);
            end;
          gw.Save(fn + '.gif');
        finally
          gw.Free;
        end;
        ExpLog(Format('GIF  %s.gif  (%d frames, %s)', [fn, n, FileSizeKB(fn + '.gif')]));
      end;
      Inc(files);
    end;
  finally
    off.Free;
  end;
  ExpLog(Format('Done: %d graphic file(s) in %s', [files, dir]));
end;

procedure TInfoForm.ExportMainPng;
var
  R: TNeonRenderer;
  bmp: TBGRABitmap;
  fn: string;
begin
  R := View.Renderer;
  bmp := R.Snapshot(R.ReadyGeom.W, R.ReadyGeom.H);
  if bmp = nil then
  begin
    ExpLog('No frame available yet.');
    Exit;
  end;
  try
    fn := ExportDir + 'main_' + TimeStamp + '.png';
    bmp.SaveToFile(fn);
    ExpLog(Format('PNG  %s  (%d x %d, %s)', [fn, bmp.Width, bmp.Height, FileSizeKB(fn)]));
  finally
    bmp.Free;
  end;
end;

procedure TInfoForm.ExportMainGif;
var
  R, off: TNeonRenderer;
  bmp: TBGRABitmap;
  gw: TGifWriter;
  fn: string;
  rw, rh, ow, oh, i, n: Integer;
  t0: Double;
begin
  R := View.Renderer;
  rw := R.ReadyGeom.W;
  rh := R.ReadyGeom.H;
  if rw <= 0 then
  begin
    ExpLog('No frame available yet.');
    Exit;
  end;
  ow := Max(16, Round(rw * FExpScale.Value));
  oh := Max(16, Round(rh * FExpScale.Value));
  n := FExpFrames.Value;
  t0 := View.SimTime;
  fn := ExportDir + 'main_' + TimeStamp + '.gif';
  ExpLog(Format('Recording %d frames at %d fps, render %d x %d -> GIF %d x %d ...',
    [n, FExpFps.Value, rw, rh, ow, oh]));
  off := TNeonRenderer.Create;
  gw := TGifWriter.Create(ow, oh, GifDelayMs);
  try
    for i := 0 to n - 1 do
    begin
      { offline render of the exact moment on all cores, identical to the main window }
      off.BeginFrame(rw, rh, t0 + i * GifTimeStep);
      off.WaitFrame;
      bmp := off.Snapshot(ow, oh);
      if Assigned(bmp) then
      try
        gw.Add(bmp);
      finally
        bmp.Free;
      end;
      ExpProgress(i + 1, n + 1);
    end;
    ExpLog('Encoding GIF (palette quantisation + dithering) ...');
    Application.ProcessMessages;
    gw.Save(fn);
    ExpProgress(n + 1, n + 1);
  finally
    gw.Free;
    off.Free;
  end;
  ExpLog(Format('GIF  %s  (%d frames, %.1f s, %s)', [fn, n, n / FExpFps.Value, FileSizeKB(fn)]));
end;

{ MP4 (H.264 via Windows Media Foundation) }

function EvenSize(V: Integer): Integer;
begin
  Result := Max(16, V and not 1);
end;

function TInfoForm.Mp4Writer(const AFileName: string; AW, AH: Integer): TMp4Writer;
begin
  Result := TMp4Writer.Create(AFileName, AW, AH, FMp4Fps.Value, FMp4Mbps.Value * 1000,
    FMp4Hw.Checked);
end;

procedure TInfoForm.LogMp4(const AFileName: string; AWriter: TMp4Writer);
begin
  ExpLog(Format('MP4  %s  (%d x %d, %d frames, %.1f s, %s encoder, %s)',
    [AFileName, AWriter.Width, AWriter.Height, AWriter.Frames, AWriter.Frames / FMp4Fps.Value,
     BoolToStr(AWriter.Hardware, 'GPU-enabled', 'software'), FileSizeKB(AFileName)]));
end;

procedure TInfoForm.ExportLayersMp4;
var
  R: TNeonRenderer;
  dir, fn, why: string;
  k: TLayerKind;
  w, h, n, i, total, done: Integer;
  t0, dt: Double;
  bmp: TBGRABitmap;
  mw: TMp4Writer;
begin
  if not MP4Available(why) then raise Exception.Create(why);
  R := View.Renderer;
  dir := ExportDir;
  w := EvenSize(FExpW.Value);
  h := EvenSize(FExpH.Value);
  n := FMp4Secs.Value * FMp4Fps.Value;
  dt := GifTimeStep * FExpFps.Value / FMp4Fps.Value;
  t0 := View.SimTime;
  total := 0;
  for k := Low(TLayerKind) to High(TLayerKind) do
    if FExpLayers.Checked[Ord(k)] and LayerAnimated(k) then total += n;
  if total = 0 then
  begin
    ExpLog('No animated layer selected (static layers have no MP4).');
    Exit;
  end;
  done := 0;
  for k := Low(TLayerKind) to High(TLayerKind) do
  begin
    if not FExpLayers.Checked[Ord(k)] then Continue;
    if not LayerAnimated(k) then
    begin
      ExpLog('MP4  skipped static layer: ' + LayerDefs[k].Name);
      Continue;
    end;
    fn := dir + Format('layer_%.2d_%s.mp4', [Ord(k) + 1, SafeName(LayerDefs[k].Name)]);
    mw := Mp4Writer(fn, w, h);
    try
      FCurMp4 := mw;
      try
        RunPreviewFrames(True, k, giSprite, w, h, n, t0, dt, done, total);
      finally
        FCurMp4 := nil;
      end;
      mw.Finish;
      LogMp4(fn, mw);
    finally
      mw.Free;
    end;
  end;
end;

procedure TInfoForm.ExportGraphicsMp4;
var
  dir, fn, why: string;
  gi: TGraphicItem;
  w, h, n, i, total, done: Integer;
  t0, dt: Double;
  bmp: TBGRABitmap;
  mw: TMp4Writer;
  off: TNeonRenderer;
begin
  if not MP4Available(why) then raise Exception.Create(why);
  dir := ExportDir;
  w := EvenSize(FExpW.Value);
  h := EvenSize(FExpH.Value);
  n := FMp4Secs.Value * FMp4Fps.Value;
  dt := GifTimeStep * FExpFps.Value / FMp4Fps.Value;
  t0 := View.SimTime;
  total := 0;
  for gi := Low(TGraphicItem) to High(TGraphicItem) do
    if FExpGraphics.Checked[Ord(gi)] and GraphicAnimated[gi] then total += n;
  if total = 0 then
  begin
    ExpLog('No animated graphic selected (static graphics have no MP4).');
    Exit;
  end;
  done := 0;
  off := nil;
  try
    for gi := Low(TGraphicItem) to High(TGraphicItem) do
    begin
      if not FExpGraphics.Checked[Ord(gi)] then Continue;
      if not GraphicAnimated[gi] then
      begin
        ExpLog('MP4  skipped static graphic: ' + GraphicNames[gi]);
        Continue;
      end;
      fn := dir + 'graphic_' + SafeName(GraphicNames[gi]) + '.mp4';
      mw := Mp4Writer(fn, w, h);
      try
        if gi in ParallelGraphics then
        begin
          FCurMp4 := mw;
          try
            RunPreviewFrames(False, lkBackground, gi, w, h, n, t0, dt, done, total);
          finally
            FCurMp4 := nil;
          end;
        end
        else
          for i := 0 to n - 1 do
          begin
            bmp := MakeGraphic(gi, w, h, t0 + i * dt, True, off);
            try
              mw.AddFrame(bmp);
            finally
              bmp.Free;
            end;
            Inc(done);
            ExpProgress(done, total);
          end;
        mw.Finish;
        LogMp4(fn, mw);
      finally
        mw.Free;
      end;
    end;
  finally
    off.Free;
  end;
end;

procedure TInfoForm.ExportMainMp4;
var
  R, off: TNeonRenderer;
  bmp: TBGRABitmap;
  mw: TMp4Writer;
  fn, why: string;
  rw, rh, ow, oh, i, n: Integer;
  t0, dt: Double;
begin
  if not MP4Available(why) then raise Exception.Create(why);
  R := View.Renderer;
  rw := R.ReadyGeom.W;
  rh := R.ReadyGeom.H;
  if rw <= 0 then
  begin
    ExpLog('No frame available yet.');
    Exit;
  end;
  ow := EvenSize(Round(rw * FMp4Scale.Value));
  oh := EvenSize(Round(rh * FMp4Scale.Value));
  n := FMp4Secs.Value * FMp4Fps.Value;
  dt := GifTimeStep * FExpFps.Value / FMp4Fps.Value;
  t0 := View.SimTime;
  fn := ExportDir + 'main_' + TimeStamp + '.mp4';
  ExpLog(Format('Recording MP4: %d frames at %d fps, render %d x %d -> video %d x %d, %d Mbps ...',
    [n, FMp4Fps.Value, rw, rh, ow, oh, FMp4Mbps.Value]));
  off := TNeonRenderer.Create;
  mw := Mp4Writer(fn, ow, oh);
  try
    for i := 0 to n - 1 do
    begin
      { offline render of the exact moment on all cores, identical to the main window }
      off.BeginFrame(rw, rh, t0 + i * dt);
      off.WaitFrame;
      bmp := off.Snapshot(ow, oh);
      if Assigned(bmp) then
      try
        mw.AddFrame(bmp);
      finally
        bmp.Free;
      end;
      ExpProgress(i + 1, n);
    end;
    mw.Finish;
    LogMp4(fn, mw);
  finally
    mw.Free;
    off.Free;
  end;
end;

procedure TInfoForm.SinkFrame(AIndex: Integer; AFrame: TBGRABitmap);
begin
  if Assigned(FCurGif) then FCurGif.Add(AFrame);
  if Assigned(FCurMp4) then FCurMp4.AddFrame(AFrame);
  Inc(FSinkDone);
  ExpProgress(FSinkDone, FSinkTotal);
end;

procedure TInfoForm.ExpIdle;
begin
  Application.ProcessMessages;
end;

procedure TInfoForm.RunPreviewFrames(AIsLayer: Boolean; AKind: TLayerKind; AGraphic: TGraphicItem;
  AW, AH, ACount: Integer; AT0, ADt: Double; var ADone: Integer; ATotal: Integer);
var
  job: TPreviewJob;
begin
  job := TPreviewJob.Create(View.Renderer, AIsLayer, AKind, AGraphic, AW, AH, ACount, AT0, ADt);
  try
    FSinkDone := ADone;
    FSinkTotal := ATotal;
    RenderFramesParallel(@job.Frame, ACount, @SinkFrame, @ExpIdle);
    ADone := FSinkDone;
  finally
    job.Free;
  end;
end;

end.
