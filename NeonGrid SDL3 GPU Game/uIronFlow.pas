unit uIronFlow;

{ The VS BOT iron rules of Neon Beads as a flowchart (NeonBeads.ironflow),
  drawn and edited with NeonIronFlow (NeonGrid SDL3 GPU Tools).

  A flow is a set of nodes:
    Start      an event of one side: a pop, stalling (no pop for the
               stalling seconds of the VS rules) or every second
    Condition  compares a variable with a number or another variable;
               goes on at Yes or No
    Action     send iron to the other board, iron on the own board (after a
               pop it comes with the refill), add points (negative = take),
               show a message ({n} = the amount), stop
    End        the end of this path
  Every Start of the event runs (in the order of the file); a path stops at
  an End, a Stop or after MaxSteps nodes (a loop). The amounts are
  round(variable x multiplier + add).

  The variables are seen from the side that has the event (my / other).
  With a flow loaded and enabled the game takes its iron from the flow
  instead of the built-in rules (uBeadGame.MoveIron, stalling); the default
  flow (DefaultFlow) is exactly the built-in rules, reading their numbers
  from the VS rules (uBeadRules). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, IniFiles;

type
  TFlowKind = (fkStart, fkIf, fkAction, fkEnd);
  TFlowEvent = (feOnPop, feOnStall, feEverySecond);

const
  FlowVarCount = 19;
  fvPopSize = 0;
  fvMyScore = 1;
  fvOtherScore = 2;
  fvGap = 3;
  fvGapSize = 4;
  fvMyIron = 5;
  fvOtherIron = 6;
  fvAttackIron = 7;
  fvRefillIron = 8;
  fvSeconds = 9;
  fvMySent = 10;
  fvMyReceived = 11;
  fvRandom = 12;
  fvRuleGap = 13;
  fvRuleLeaderRefill = 14;
  fvRuleTrailerIron = 15;
  fvRuleStallPoints = 16;
  fvRuleStallIron = 17;
  fvIdleSecs = 18;
  FlowVarNames: array[0..FlowVarCount - 1] of string = ('pop size', 'my score', 'other score',
    'score gap (my - other)', 'gap size |my - other|', 'my iron on board', 'other iron on board',
    'attack iron of this pop', 'refill iron of this pop', 'match seconds', 'my iron sent', 'my iron received',
    'random 0..99', 'rule: iron gap', 'rule: leader''s 2-3 pops to the other', 'rule: side behind makes iron',
    'rule: stalling points', 'rule: stalling iron', 'seconds without a pop');

  FlowOpCount = 6;
  FlowOpNames: array[0..FlowOpCount - 1] of string = ('>', '>=', '<', '<=', '=', '<>');

  FlowActCount = 5;
  faSend = 0;
  faOwn = 1;
  faPoints = 2;
  faMessage = 3;
  faStop = 4;
  FlowActNames: array[0..FlowActCount - 1] of string = ('Send iron to the other board', 'Iron on my board',
    'Add points', 'Show a message', 'Stop');

  FlowEventNames: array[TFlowEvent] of string = ('A pop', 'Stalling', 'Every second');
  FlowKindNames: array[TFlowKind] of string = ('start', 'if', 'action', 'end');
  MaxSteps = 200;

type
  TFlowNode = record
    Id: Integer;
    Kind: TFlowKind;
    X, Y: Single;              // editor position (centre)
    Event: TFlowEvent;         // start
    LeftVar, Op, RightVar: Integer;   // if (RightVar -1 = the number Right)
    Right: Single;
    Act, AmountVar: Integer;   // action (AmountVar -1 = only Add)
    Mul, Add: Single;
    Text: string;              // message / note
    Next, No: Integer;         // ids (0 = none): Next = Yes for a condition
  end;

  TFlowCtx = record
    V: array[0..FlowVarCount - 1] of Single;
  end;

  TFlowOut = record
    Send, Own, Points: Integer;
    Msgs: array of string;
    Fired: array of Integer;   // node ids in the order they ran
    FiredAmt: array of Integer;   // the amount of each (actions), else 0
  end;

  TIronFlow = class
  public
    Nodes: array of TFlowNode;
    Enabled: Boolean;
    function IndexOf(AId: Integer): Integer;
    function NewId: Integer;
    function Add(AKind: TFlowKind; AX, AY: Single): Integer;   // index
    procedure Delete(AId: Integer);
    procedure Clear;
    procedure Assign(ASource: TIronFlow);
    function LoadFromFile(const AFile: string): Boolean;
    procedure SaveToFile(const AFile: string);
    procedure Run(AEvent: TFlowEvent; const ACtx: TFlowCtx; var AOut: TFlowOut);
    function Caption(AIndex: Integer): string;
  end;

  TFlowTraceProc = procedure(ASide, ANode, AAmount: Integer);

var
  IronFlow: TIronFlow;           // the flow of the game
  FlowStamp: Integer = 0;        // changes when the flow is loaded
  FlowTrace: TFlowTraceProc = nil;   // the --vssim window reports fired nodes

{ the built-in rules as a flow }
procedure DefaultFlow(AFlow: TIronFlow);
{ a flow is loaded and enabled: the game uses it }
function FlowOn: Boolean;
function Compare(A: Single; AOp: Integer; B: Single): Boolean;

implementation

var
  FS: TFormatSettings;

function FlowOn: Boolean;
begin
  Result := (IronFlow <> nil) and IronFlow.Enabled and (Length(IronFlow.Nodes) > 0);
end;

function Compare(A: Single; AOp: Integer; B: Single): Boolean;
begin
  case AOp of
    0: Result := A > B + 1e-6;
    1: Result := A >= B - 1e-6;
    2: Result := A < B - 1e-6;
    3: Result := A <= B + 1e-6;
    4: Result := Abs(A - B) <= 1e-6;
  else
    Result := Abs(A - B) > 1e-6;
  end;
end;

{ TIronFlow }

function TIronFlow.IndexOf(AId: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Nodes) do
    if Nodes[i].Id = AId then Exit(i);
  Result := -1;
end;

function TIronFlow.NewId: Integer;
var
  i: Integer;
begin
  Result := 1;
  for i := 0 to High(Nodes) do Result := Max(Result, Nodes[i].Id + 1);
end;

function TIronFlow.Add(AKind: TFlowKind; AX, AY: Single): Integer;
var
  n: TFlowNode;
begin
  n := Default(TFlowNode);
  n.Id := NewId;
  n.Kind := AKind;
  n.X := AX;
  n.Y := AY;
  n.RightVar := -1;
  n.AmountVar := -1;
  n.Mul := 1;
  Result := Length(Nodes);
  SetLength(Nodes, Result + 1);
  Nodes[Result] := n;
end;

procedure TIronFlow.Delete(AId: Integer);
var
  i, k: Integer;
begin
  k := IndexOf(AId);
  if k < 0 then Exit;
  for i := k to High(Nodes) - 1 do Nodes[i] := Nodes[i + 1];
  SetLength(Nodes, Length(Nodes) - 1);
  for i := 0 to High(Nodes) do
  begin
    if Nodes[i].Next = AId then Nodes[i].Next := 0;
    if Nodes[i].No = AId then Nodes[i].No := 0;
  end;
end;

procedure TIronFlow.Clear;
begin
  SetLength(Nodes, 0);
end;

procedure TIronFlow.Assign(ASource: TIronFlow);
begin
  Nodes := Copy(ASource.Nodes);
  Enabled := ASource.Enabled;
end;

function TIronFlow.LoadFromFile(const AFile: string): Boolean;
var
  ini: TMemIniFile;
  secs: TStringList;
  i: Integer;
  n: TFlowNode;
  s, k: string;
begin
  Result := False;
  if not FileExists(AFile) then Exit;
  secs := TStringList.Create;
  try
    ini := TMemIniFile.Create(AFile);
    try
      Clear;
      Enabled := ini.ReadBool('Flow', 'Enabled', True);
      ini.ReadSections(secs);
      for i := 0 to secs.Count - 1 do
      begin
        s := secs[i];
        if not SameText(Copy(s, 1, 4), 'Node') then Continue;
        n := Default(TFlowNode);
        n.Id := StrToIntDef(Copy(s, 5, 10), 0);
        if n.Id <= 0 then Continue;
        k := LowerCase(ini.ReadString(s, 'Kind', 'end'));
        if k = 'start' then n.Kind := fkStart
        else if k = 'if' then n.Kind := fkIf
        else if k = 'action' then n.Kind := fkAction
        else n.Kind := fkEnd;
        n.X := StrToFloatDef(ini.ReadString(s, 'X', '0'), 0, FS);
        n.Y := StrToFloatDef(ini.ReadString(s, 'Y', '0'), 0, FS);
        n.Event := TFlowEvent(EnsureRange(ini.ReadInteger(s, 'Event', 0), 0, Ord(High(TFlowEvent))));
        n.LeftVar := EnsureRange(ini.ReadInteger(s, 'Left', 0), 0, FlowVarCount - 1);
        n.Op := EnsureRange(ini.ReadInteger(s, 'Op', 0), 0, FlowOpCount - 1);
        n.RightVar := EnsureRange(ini.ReadInteger(s, 'RightVar', -1), -1, FlowVarCount - 1);
        n.Right := StrToFloatDef(ini.ReadString(s, 'Right', '0'), 0, FS);
        n.Act := EnsureRange(ini.ReadInteger(s, 'Action', 0), 0, FlowActCount - 1);
        n.AmountVar := EnsureRange(ini.ReadInteger(s, 'AmountVar', -1), -1, FlowVarCount - 1);
        n.Mul := StrToFloatDef(ini.ReadString(s, 'Mul', '1'), 1, FS);
        n.Add := StrToFloatDef(ini.ReadString(s, 'Add', '0'), 0, FS);
        n.Text := ini.ReadString(s, 'Text', '');
        n.Next := ini.ReadInteger(s, 'Next', 0);
        n.No := ini.ReadInteger(s, 'No', 0);
        SetLength(Nodes, Length(Nodes) + 1);
        Nodes[High(Nodes)] := n;
      end;
    finally
      ini.Free;
    end;
    Result := Length(Nodes) > 0;
  except
    Result := False;
  end;
  secs.Free;
  Inc(FlowStamp);
end;

procedure TIronFlow.SaveToFile(const AFile: string);
var
  sl: TStringList;
  i: Integer;
  n: TFlowNode;
begin
  sl := TStringList.Create;
  try
    sl.Add('; Neon Beads VS BOT iron flow - edit with NeonIronFlow (NeonGrid SDL3 GPU Tools).');
    sl.Add('; Kind: start / if / action / end. Event: 0 a pop, 1 stalling, 2 every second.');
    sl.Add('; Left / RightVar / AmountVar: variable numbers (see NeonIronFlow), RightVar -1 = the number Right.');
    sl.Add('; Op: 0 >, 1 >=, 2 <, 3 <=, 4 =, 5 <>. Action: 0 send iron, 1 iron on my board, 2 points, 3 message, 4 stop.');
    sl.Add('; Next = the next node (Yes of a condition), No = the No of a condition (0 = none).');
    sl.Add('[Flow]');
    sl.Add('Enabled=' + IntToStr(Ord(Enabled)));
    for i := 0 to High(Nodes) do
    begin
      n := Nodes[i];
      sl.Add('');
      sl.Add('[Node' + IntToStr(n.Id) + ']');
      sl.Add('Kind=' + FlowKindNames[n.Kind]);
      sl.Add('X=' + FormatFloat('0', n.X, FS));
      sl.Add('Y=' + FormatFloat('0', n.Y, FS));
      case n.Kind of
        fkStart: sl.Add('Event=' + IntToStr(Ord(n.Event)));
        fkIf:
          begin
            sl.Add('Left=' + IntToStr(n.LeftVar));
            sl.Add('Op=' + IntToStr(n.Op));
            sl.Add('RightVar=' + IntToStr(n.RightVar));
            sl.Add('Right=' + FormatFloat('0.###', n.Right, FS));
          end;
        fkAction:
          begin
            sl.Add('Action=' + IntToStr(n.Act));
            sl.Add('AmountVar=' + IntToStr(n.AmountVar));
            sl.Add('Mul=' + FormatFloat('0.###', n.Mul, FS));
            sl.Add('Add=' + FormatFloat('0.###', n.Add, FS));
          end;
      end;
      if n.Text <> '' then sl.Add('Text=' + n.Text);
      if n.Kind <> fkEnd then sl.Add('Next=' + IntToStr(n.Next));
      if n.Kind = fkIf then sl.Add('No=' + IntToStr(n.No));
    end;
    sl.SaveToFile(AFile);
  finally
    sl.Free;
  end;
end;

function AmountText(const N: TFlowNode): string;
begin
  if N.AmountVar < 0 then Exit(FormatFloat('0.##', N.Add, FS));
  Result := FlowVarNames[N.AmountVar];
  if Abs(N.Mul - 1) > 1e-6 then Result += ' x ' + FormatFloat('0.##', N.Mul, FS);
  if Abs(N.Add) > 1e-6 then
  begin
    if N.Add > 0 then Result += ' + ' else Result += ' - ';
    Result += FormatFloat('0.##', Abs(N.Add), FS);
  end;
end;

function TIronFlow.Caption(AIndex: Integer): string;
var
  n: TFlowNode;
  r: string;
begin
  n := Nodes[AIndex];
  case n.Kind of
    fkStart: Result := 'START: ' + FlowEventNames[n.Event];
    fkIf:
      begin
        if n.RightVar >= 0 then r := FlowVarNames[n.RightVar] else r := FormatFloat('0.##', n.Right, FS);
        Result := FlowVarNames[n.LeftVar] + ' ' + FlowOpNames[n.Op] + ' ' + r + ' ?';
      end;
    fkAction:
      case n.Act of
        faSend: Result := 'SEND IRON: ' + AmountText(n);
        faOwn: Result := 'IRON ON MY BOARD: ' + AmountText(n);
        faPoints: Result := 'POINTS: ' + AmountText(n);
        faMessage: Result := 'MESSAGE: ' + n.Text;
      else
        Result := 'STOP';
      end;
  else
    Result := 'END';
  end;
end;

procedure TIronFlow.Run(AEvent: TFlowEvent; const ACtx: TFlowCtx; var AOut: TFlowOut);
var
  i, k, cur, steps, amt, last: Integer;
  n: TFlowNode;
  b: Single;
  stop: Boolean;
  msg: string;

  procedure Fire(AId: Integer; AAmount: Integer = 0);
  begin
    SetLength(AOut.Fired, Length(AOut.Fired) + 1);
    AOut.Fired[High(AOut.Fired)] := AId;
    SetLength(AOut.FiredAmt, Length(AOut.Fired));
    AOut.FiredAmt[High(AOut.Fired)] := AAmount;
  end;

begin
  last := 0;
  for i := 0 to High(Nodes) do
  begin
    if (Nodes[i].Kind <> fkStart) or (Nodes[i].Event <> AEvent) then Continue;
    Fire(Nodes[i].Id);
    cur := Nodes[i].Next;
    steps := 0;
    stop := False;
    while (cur > 0) and (steps < MaxSteps) and not stop do
    begin
      Inc(steps);
      k := IndexOf(cur);
      if k < 0 then Break;
      n := Nodes[k];
      if n.Kind <> fkAction then Fire(n.Id);
      case n.Kind of
        fkStart:
          cur := n.Next;
        fkIf:
          begin
            if n.RightVar >= 0 then b := ACtx.V[n.RightVar] else b := n.Right;
            if Compare(ACtx.V[n.LeftVar], n.Op, b) then cur := n.Next else cur := n.No;
          end;
        fkAction:
          begin
            if n.AmountVar >= 0 then amt := Round(ACtx.V[n.AmountVar] * n.Mul + n.Add)
            else amt := Round(n.Add);
            Fire(n.Id, amt);
            case n.Act of
              faSend: begin AOut.Send += amt; last := amt; end;
              faOwn: begin AOut.Own += amt; last := amt; end;
              faPoints: begin AOut.Points += amt; last := amt; end;
              faMessage:
                begin
                  msg := StringReplace(n.Text, '{n}', IntToStr(Abs(last)), [rfReplaceAll]);
                  if msg <> '' then
                  begin
                    SetLength(AOut.Msgs, Length(AOut.Msgs) + 1);
                    AOut.Msgs[High(AOut.Msgs)] := msg;
                  end;
                end;
              faStop: stop := True;
            end;
            cur := n.Next;
          end;
      else
        cur := 0;
      end;
    end;
  end;
end;

{ the built-in VS BOT rules (uBeadGame.MoveIron + stalling) as a flow }
procedure DefaultFlow(AFlow: TIronFlow);

  function N(AKind: TFlowKind; AX, AY: Single): Integer;   // id
  var
    k: Integer;
  begin
    k := AFlow.Add(AKind, AX, AY);   // first: Add grows the array
    Result := AFlow.Nodes[k].Id;
  end;

  procedure SetIf(AId, ALeft, AOp, ARightVar: Integer; ARight: Single; AYes, ANo: Integer);
  var
    k: Integer;
  begin
    k := AFlow.IndexOf(AId);
    AFlow.Nodes[k].LeftVar := ALeft;
    AFlow.Nodes[k].Op := AOp;
    AFlow.Nodes[k].RightVar := ARightVar;
    AFlow.Nodes[k].Right := ARight;
    AFlow.Nodes[k].Next := AYes;
    AFlow.Nodes[k].No := ANo;
  end;

  procedure SetAct(AId, AAct, AVar: Integer; AMul, AAdd: Single; const AText: string; ANext: Integer);
  var
    k: Integer;
  begin
    k := AFlow.IndexOf(AId);
    AFlow.Nodes[k].Act := AAct;
    AFlow.Nodes[k].AmountVar := AVar;
    AFlow.Nodes[k].Mul := AMul;
    AFlow.Nodes[k].Add := AAdd;
    AFlow.Nodes[k].Text := AText;
    AFlow.Nodes[k].Next := ANext;
  end;

var
  s1, gap0, gapBig, lead, sendAtk, ldrRef, sendRef, ownRef, trl, trlAtk, trlRef, e1: Integer;
  s2, pen, pts, msg, irn, ownIrn, e2: Integer;
begin
  AFlow.Clear;
  AFlow.Enabled := True;
  { a pop: iron only above the gap; the leader's iron to the other board }
  s1 := N(fkStart, 180, 50);
  gap0 := N(fkIf, 180, 150);
  gapBig := N(fkIf, 460, 150);
  lead := N(fkIf, 180, 270);
  sendAtk := N(fkAction, 180, 380);
  ldrRef := N(fkIf, 180, 490);
  sendRef := N(fkAction, 140, 610);
  ownRef := N(fkAction, 400, 610);
  trl := N(fkIf, 760, 270);
  trlAtk := N(fkAction, 760, 380);
  trlRef := N(fkAction, 760, 490);
  e1 := N(fkEnd, 460, 740);
  AFlow.Nodes[AFlow.IndexOf(s1)].Event := feOnPop;
  AFlow.Nodes[AFlow.IndexOf(s1)].Next := gap0;
  SetIf(gap0, fvRuleGap, 4, -1, 0, lead, gapBig);
  SetIf(gapBig, fvGapSize, 0, fvRuleGap, 0, lead, e1);
  SetIf(lead, fvGap, 0, -1, 0, sendAtk, trl);
  SetAct(sendAtk, faSend, fvAttackIron, 1, 0, '', ldrRef);
  SetIf(ldrRef, fvRuleLeaderRefill, 4, -1, 1, sendRef, ownRef);
  SetAct(sendRef, faSend, fvRefillIron, 1, 0, '', e1);
  SetAct(ownRef, faOwn, fvRefillIron, 1, 0, '', e1);
  SetIf(trl, fvRuleTrailerIron, 4, -1, 1, trlAtk, e1);
  SetAct(trlAtk, faSend, fvAttackIron, 1, 0, '', trlRef);
  SetAct(trlRef, faOwn, fvRefillIron, 1, 0, '', e1);

  { stalling: points and / or iron on the own board }
  s2 := N(fkStart, 1080, 50);
  pen := N(fkIf, 1080, 150);
  pts := N(fkAction, 1080, 270);
  msg := N(fkAction, 1080, 380);
  irn := N(fkIf, 1340, 270);
  ownIrn := N(fkAction, 1340, 380);
  e2 := N(fkEnd, 1340, 490);
  AFlow.Nodes[AFlow.IndexOf(s2)].Event := feOnStall;
  AFlow.Nodes[AFlow.IndexOf(s2)].Next := pen;
  SetIf(pen, fvRuleStallPoints, 0, -1, 0, pts, irn);
  SetAct(pts, faPoints, fvRuleStallPoints, -1, 0, '', msg);
  SetAct(msg, faMessage, -1, 1, 0, 'TOO SLOW!  -{n}', irn);
  SetIf(irn, fvRuleStallIron, 0, -1, 0, ownIrn, e2);
  SetAct(ownIrn, faOwn, fvRuleStallIron, 1, 0, '', e2);
end;

initialization
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  IronFlow := TIronFlow.Create;

finalization
  IronFlow.Free;

end.
