unit uPreview;

{ GPU preview mode of Neon Beads and Neon Trail: "--preview=FILE".
  NeonVisualEditor starts the game this way in its own window ("GPU preview")
  and writes every change of its values to FILE (a copy in the temp folder,
  not the game's .visuals): the game reads it again within 0.1 s, so the
  background, beads, colour show, dot motion and dot shape change while the
  sliders move - with the real game shaders.

  In preview mode the game plays by itself, starts muted, never pauses on
  focus loss, keeps no records (its ini is a temp copy of the real one: the
  theme and options stay as the player has them) and never writes FILE.
  Keys: 1 game, 2 menu, 3 background only (no board, no HUD), Tab next scene,
  M sound, F11 fullscreen, Esc closes the preview.

  "--vssim=FLOW [--left=L] [--right=R]" (Neon Beads, started by NeonIronFlow):
  a VS BOT match of two bots (levels 0..2) with the iron flowchart FLOW,
  read again whenever it changes; the nodes that fire are written to
  FLOW.trace for the editor. Same temp ini and sound as the preview; keys
  1-4 speed x1 / x2 / x4 / x8, R a new match, Esc close.

  "--shapes=FILE" (with --preview, started by NeonShapeEditor): the dot and
  bead shapes come from FILE (the editor's live copy), read again whenever
  its content changes. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils;

const
  PreviewScenes = 3;
  PreviewSceneNames: array[0..PreviewScenes - 1] of string = ('GAME', 'MENU', 'BACKGROUND');

type
  TPreview = record
    Active: Boolean;
    VisualsFile: string;   // the editor's live copy of the .visuals
    Scene: Integer;        // 0 game, 1 title menu, 2 background only
    LastText: string;      // file content last loaded
    T: Double;             // seconds since the last check
    VsSim: Boolean;        // --vssim: bots play VS BOT with an iron flowchart
    FlowFile: string;
    LeftLevel, RightLevel, Speed: Integer;
    FlowText: string;
    FlowT: Double;
    ShapesFile, ShapesText: string;   // --shapes
    ShapesT: Double;
  end;

var
  Preview: TPreview;

{ reads "--preview=FILE" from the command line }
procedure PreviewInit;
{ a temp copy of the game's ini (written by the game instead of the real one) }
function PreviewIni(const ARealIni: string): string;
{ every 0.1 s: True when the content of the preview file has changed }
function PreviewChanged(dt: Double): Boolean;
{ remember the content just loaded (no reload for the same text) }
procedure PreviewLoaded;
function PreviewTitle(const AGame: string): string;
{ --vssim: the flow file changed (every 0.25 s) }
function FlowChanged(dt: Double): Boolean;
{ --shapes: the shapes file changed (every 0.15 s) }
function ShapesChanged(dt: Double): Boolean;

implementation

function ReadAll(const AFile: string): string;
var
  fs: TFileStream;
begin
  Result := '';
  try
    { the editor may be writing it: share everything }
    fs := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, fs.Size);
      if fs.Size > 0 then fs.ReadBuffer(Result[1], fs.Size);
    finally
      fs.Free;
    end;
  except
    Result := '';
  end;
end;

procedure PreviewInit;
var
  i: Integer;
  a: string;
begin
  Preview := Default(TPreview);
  Preview.LeftLevel := 1;
  Preview.RightLevel := 1;
  Preview.Speed := 1;
  for i := 1 to ParamCount do
  begin
    a := ParamStr(i);
    if SameText(Copy(a, 1, 10), '--preview=') then
    begin
      Preview.Active := True;
      Preview.VisualsFile := Copy(a, 11, MaxInt);
    end
    else if SameText(Copy(a, 1, 8), '--vssim=') then
    begin
      Preview.Active := True;      // temp ini, sound off, no records ...
      Preview.VsSim := True;
      Preview.FlowFile := Copy(a, 9, MaxInt);
    end
    else if SameText(Copy(a, 1, 9), '--shapes=') then
      Preview.ShapesFile := Copy(a, 10, MaxInt)
    else if SameText(Copy(a, 1, 7), '--left=') then
      Preview.LeftLevel := StrToIntDef(Copy(a, 8, 5), 1)
    else if SameText(Copy(a, 1, 8), '--right=') then
      Preview.RightLevel := StrToIntDef(Copy(a, 9, 5), 1);
  end;
end;

function PreviewIni(const ARealIni: string): string;
var
  src, dst: TFileStream;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + ChangeFileExt(ExtractFileName(ARealIni), '') +
    '-preview.ini';
  try
    if FileExists(Result) then DeleteFile(Result);
    if FileExists(ARealIni) then
    begin
      src := TFileStream.Create(ARealIni, fmOpenRead or fmShareDenyNone);
      try
        dst := TFileStream.Create(Result, fmCreate);
        try
          dst.CopyFrom(src, 0);
        finally
          dst.Free;
        end;
      finally
        src.Free;
      end;
    end;
  except
    { no copy: the game starts with its defaults }
  end;
end;

function PreviewChanged(dt: Double): Boolean;
var
  s: string;
begin
  Result := False;
  if Preview.VisualsFile = '' then Exit;   // --vssim: the normal visuals
  Preview.T += dt;
  if Preview.T < 0.1 then Exit;
  Preview.T := 0;
  s := ReadAll(Preview.VisualsFile);
  { an empty read is a file being written: wait for the next check }
  Result := (s <> '') and (s <> Preview.LastText);
end;

function FlowChanged(dt: Double): Boolean;
var
  s: string;
begin
  Result := False;
  if not Preview.VsSim then Exit;
  Preview.FlowT += dt;
  if Preview.FlowT < 0.25 then Exit;
  Preview.FlowT := 0;
  s := ReadAll(Preview.FlowFile);
  Result := (s <> '') and (s <> Preview.FlowText);
  if Result then Preview.FlowText := s;
end;

function ShapesChanged(dt: Double): Boolean;
var
  s: string;
begin
  Result := False;
  if Preview.ShapesFile = '' then Exit;
  Preview.ShapesT += dt;
  if Preview.ShapesT < 0.15 then Exit;
  Preview.ShapesT := 0;
  s := ReadAll(Preview.ShapesFile);
  Result := (s <> '') and (s <> Preview.ShapesText);
  if Result then Preview.ShapesText := s;
end;

procedure PreviewLoaded;
begin
  Preview.LastText := ReadAll(Preview.VisualsFile);
end;

function PreviewTitle(const AGame: string): string;
begin
  if Preview.VsSim then
    Exit(Format('%s  -  VS BOT iron flow simulation  x%d   (1-4 speed, R new match, M sound, Esc close)',
      [AGame, Preview.Speed]));
  Result := Format('%s  -  GPU preview: %s   (1 game, 2 menu, 3 background, Tab next, M sound, Esc close)',
    [AGame, PreviewSceneNames[Preview.Scene]]);
end;

end.
