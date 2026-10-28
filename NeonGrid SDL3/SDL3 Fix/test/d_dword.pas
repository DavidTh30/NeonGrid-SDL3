program d_dword;
{$mode objfpc}
{ sdl3.pas SetMXCSR exactly, called after earlier code left non-zero bytes on the stack }
procedure SetMXCSR;
var
  w2: dword = 8064;
begin
  asm
           Ldmxcsr w2
  end;
end;

procedure LeaveGarbage;
var
  junk: array[0..15] of LongWord;
  i: Integer;
begin
  for i := 0 to 15 do junk[i] := $FFFFFFFF;
  if junk[3] = 0 then WriteLn;
end;

begin
  LeaveGarbage;
  SetMXCSR;
  WriteLn('w2 as dword: OK, MXCSR loaded');
end.
