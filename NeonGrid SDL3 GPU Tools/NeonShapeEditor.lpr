program NeonShapeEditor;

{ Neon Shape Editor: Open, edit, add, Save, Save As the geometry shapes of
  the dots and beads of Neon Beads and Neon Trail (.shapes files), with a
  neon preview and a GPU preview in the game. See uShapeEditor, uShapes. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, uShapeEditor;

{$R *.res}

begin
  RequireDerivedFormResource := False;  // the form is built in code
  Application.Title := 'Neon Shape Editor';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TShapeForm, ShapeForm);
  Application.Run;
end.
