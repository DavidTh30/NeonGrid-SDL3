program NeonVsEditor;

{ Neon Beads VS BOT Rules: Open, edit, Save, Save As and simulate
  the VS BOT rules of Neon Beads (NeonBeads.versus): iron attacks, the score gap, stalling, the board, the bot.
  See uRulesEditor, uBeadRules, uBeadSim. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, uBeadRules, uRulesEditor;

{$R *.res}

begin
  RequireDerivedFormResource := False;  // the form is built in code
  Application.Title := 'Neon Beads VS BOT Rules';
  Application.Scaled := True;
  Application.Initialize;
  RulesKind := rkVersus;
  Application.CreateForm(TRulesForm, RulesForm);
  Application.Run;
end.
