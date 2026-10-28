program NeonVisualEditor;

{ Neon Visual Editor: edits the .visuals files of Neon Beads and Neon Trail
  (background, board look, bead colours, animation, particle effects,
  score popups). See uVisualEditor. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, uVisualEditor;

{$R *.res}

begin
  RequireDerivedFormResource := False;  // the form is built in code
  Application.Title := 'Neon Visual Editor';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TVisualForm, VisualForm);
  Application.Run;
end.
