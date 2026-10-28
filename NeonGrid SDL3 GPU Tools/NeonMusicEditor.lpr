program NeonMusicEditor;

{ Neon Music Editor: composes the songs of Neon Beads and Neon Trail
  (NeonBeads.music / NeonTrail.music). See uMusicEditor. Needs SDL3.dll. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, uGameMusic, uToolAudio, uMusicEditor;

{$R *.res}

begin
  RequireDerivedFormResource := False;  // the form is built in code
  Application.Title := 'Neon Music Editor';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMusicForm, MusicForm);
  Application.Run;
end.
