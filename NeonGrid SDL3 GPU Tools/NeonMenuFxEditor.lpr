program NeonMenuFxEditor;

{ Neon Menu Effect Editor: tunes the animated menus of Neon Beads and Neon
  Trail (NeonBeads.menufx / NeonTrail.menufx) with a live preview drawn by
  the game's HUD code. See uMenuFxEditor. Needs SDL3.dll and SDL3_ttf.dll. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, uMenuFx, uMenuFxEditor;

{$R *.res}

begin
  RequireDerivedFormResource := False;  // the form is built in code
  Application.Title := 'Neon Menu Effect Editor';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TFxForm, FxForm);
  Application.Run;
end.
