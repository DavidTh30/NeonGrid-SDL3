program NeonGrid;

{ Command line: --tab=N (info window tab: 0 Overview, 1 Performance,
  2 Parameters, 3 Layers, 4 Graphics, 5 Export),
  --bench=SECONDS (measure frame pacing, write NeonGrid-bench.txt, quit). }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils, uParams, uRenderer, uMainForm, uInfoForm, uExport, uMFVideo;

{$R *.res}

begin
  RequireDerivedFormResource := False;  // forms are built in code
  Application.Title := 'Neon Dot Grid';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.CreateForm(TInfoForm, InfoForm);
  if Application.HasOption('tab') then  // --tab=N: open the info window on tab N (0 = Overview)
    InfoForm.SelectTab(StrToIntDef(Application.GetOptionValue('tab'), 1));
  InfoForm.Show;
  Application.Run;
  InfoForm.StopAsync;  // no preview thread may outlive the renderer (freed with MainForm)
end.
