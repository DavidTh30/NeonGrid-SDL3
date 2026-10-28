program NeonIronFlow;

{ Neon Iron Flow: the VS BOT iron rules of Neon Beads as a flowchart -
  Open, edit, Save, Save As, and simulate in a GPU window (Neon Beads,
  bot against bot) or quickly without a window. See uIronFlowEditor,
  uIronFlow. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, uIronFlowEditor;

{$R *.res}

begin
  RequireDerivedFormResource := False;  // the form is built in code
  Application.Title := 'Neon Iron Flow';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TFlowForm, FlowForm);
  Application.Run;
end.
