program NeonSfxEditor;

{ Neon Sound Editor: designs the sound effects of Neon Beads and Neon Trail
  (NeonBeads.sfx / NeonTrail.sfx). See uSfxEditor. Needs SDL3.dll. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, uGameSfx, uToolAudio, uSfxEditor;

{$R *.res}

begin
  RequireDerivedFormResource := False;  // the form is built in code
  Application.Title := 'Neon Sound Editor';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TSfxForm, SfxForm);
  Application.Run;
end.
