program NeonScoreEditor;

{ Neon Beads Scoring Rules: Open, edit, Save, Save As and simulate
  the scoring rules of Neon Beads (NeonBeads.scoring): points, arrangement bonuses, rewards, level end, time attack, survival.
  See uRulesEditor, uBeadRules, uBeadSim. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, uBeadRules, uRulesEditor;

{$R *.res}

begin
  RequireDerivedFormResource := False;  // the form is built in code
  Application.Title := 'Neon Beads Scoring Rules';
  Application.Scaled := True;
  Application.Initialize;
  RulesKind := rkScoring;
  Application.CreateForm(TRulesForm, RulesForm);
  Application.Run;
end.
