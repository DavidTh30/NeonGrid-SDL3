{ hudframes.inc - the frames (panels) of the HUD and the status bar extras
  (MenuFx.Frame, MenuFx.StatusX, see uMenuFx). Included in the
  implementation of uGameHud of Neon Beads and Neon Trail after
  hudstats.inc (uses StatCard, StatHue, StatRnd).

  Panel fills the frame into the cached base. A frame whose border moves
  (a border style, moving colours, an intro) is recorded and its border is
  drawn every frame by DrawFrames; a still one gets its border in the base
  like before. The progress bar and the key hints of the status bar are
  recorded the same way (DrawStatusX) when they are animated. }

function FrameColour(const FX: TFrameFx; T, U: Single): TBGRAPixel;
begin
  case Round(FX.V[fpColourMode]) of
    1: Result := StatCard(FX.Colour);
    2: Result := StatHue(T * 0.12 + U);
    3: Result := CycleColour(T * 0.2 + U);
    4: Result := Mix(StatCard(FX.Colour), StatCard(FX.Colour2), 0.5 + 0.5 * Sin(T * 1.5 + U * 2 * Pi));
  else
    Result := BGRA(70, 200, 230);
  end;
end;

{ a point on the border of a rounded rectangle: U = 0..1 clockwise from the
  top-left end of the top edge; N = the outward normal }
procedure PerimPoint(X1, Y1, X2, Y2, R, U: Single; out P, N: TPointF);
var
  sw, sh, qa, len, d, a: Single;

  procedure Arc(CX, CY, A0: Single);
  begin
    a := A0 + d / Max(R, 1e-3);
    N := PointF(Cos(a), Sin(a));
    P := PointF(CX + N.x * R, CY + N.y * R);
  end;

begin
  sw := Max(0, X2 - X1 - 2 * R);
  sh := Max(0, Y2 - Y1 - 2 * R);
  qa := Pi * R / 2;
  len := 2 * sw + 2 * sh + 4 * qa;
  d := Frac(Frac(U) + 1) * len;
  if d < sw then begin P := PointF(X1 + R + d, Y1); N := PointF(0, -1); Exit; end;
  d -= sw;
  if d < qa then begin Arc(X2 - R, Y1 + R, -Pi / 2); Exit; end;
  d -= qa;
  if d < sh then begin P := PointF(X2, Y1 + R + d); N := PointF(1, 0); Exit; end;
  d -= sh;
  if d < qa then begin Arc(X2 - R, Y2 - R, 0); Exit; end;
  d -= qa;
  if d < sw then begin P := PointF(X2 - R - d, Y2); N := PointF(0, 1); Exit; end;
  d -= sw;
  if d < qa then begin Arc(X1 + R, Y2 - R, Pi / 2); Exit; end;
  d -= qa;
  if d < sh then begin P := PointF(X1, Y2 - R - d); N := PointF(-1, 0); Exit; end;
  d -= sh;
  Arc(X1 + R, Y1 + R, Pi);
end;

function PerimLength(X1, Y1, X2, Y2, R: Single): Single;
begin
  Result := 2 * Max(0, X2 - X1 - 2 * R) + 2 * Max(0, Y2 - Y1 - 2 * R) + 2 * Pi * R;
end;

procedure TGameHud.Panel(X1, Y1, X2, Y2: Single; AAlpha: Byte; AKind: Integer);
var
  fx: TFrameFx;
  r: Single;
  a, i, n: Integer;
  fc, bc, c1, c2: TBGRAPixel;
  sc: TBGRAGradientScanner;
  f: THudFrame;
begin
  AKind := EnsureRange(AKind, 0, FrameCount - 1);
  fx := MenuFx.Frame[AKind];
  r := Min(18, (Y2 - Y1) / 4) * fx.V[fpRadius];
  a := EnsureRange(Round(AAlpha * fx.V[fpFill]), 0, 255);
  fc := StatCard(fx.FillColour);
  bc := FrameColour(fx, 0, 0);
  case Round(fx.V[fpFillStyle]) of
    1:
      begin
        { gradient: a touch of the border colour at the top, darker below }
        c1 := Mix(fc, bc, 0.22);
        c1.alpha := a;
        c2 := Mix(fc, BGRA(0, 0, 0), 0.4);
        c2.alpha := a;
        sc := TBGRAGradientScanner.Create(c1, c2, gtLinear, PointF(0, Y1), PointF(0, Y2));
        try
          FTarget.FillRoundRectAntialias(X1, Y1, X2, Y2, r, r, sc);
        finally
          sc.Free;
        end;
      end;
    2:
      begin
        { glass: a soft light on the upper half }
        FTarget.FillRoundRectAntialias(X1, Y1, X2, Y2, r, r, BGRA(fc.red, fc.green, fc.blue, a));
        FTarget.FillRoundRectAntialias(X1 + 2, Y1 + 2, X2 - 2, Y1 + (Y2 - Y1) * 0.46, Max(0, r - 2), Max(0, r - 2),
          BGRA(255, 255, 255, Round(a * 0.09)));
      end;
    3:
      begin
        c1 := Mix(fc, bc, 0.18);
        FTarget.FillRoundRectAntialias(X1, Y1, X2, Y2, r, r, BGRA(c1.red, c1.green, c1.blue, a));
      end;
  else
    FTarget.FillRoundRectAntialias(X1, Y1, X2, Y2, r, r, BGRA(fc.red, fc.green, fc.blue, a));
  end;

  f.Kind := AKind;
  f.X1 := X1; f.Y1 := Y1; f.X2 := X2; f.Y2 := Y2; f.R := r;
  f.Live := (Round(fx.V[fpStyle]) <> 0) or (Round(fx.V[fpColourMode]) in [2, 3, 4]) or
    (Round(fx.V[fpIntro]) <> 0) or (fx.V[fpGlow] > 0);
  { the same frame as before keeps its intro time }
  f.T0 := HudClock;
  for i := 0 to High(FFramesPrev) do
    if (FFramesPrev[i].Kind = AKind) and (Abs(FFramesPrev[i].X1 - X1) < 1) and (Abs(FFramesPrev[i].Y1 - Y1) < 1) and
      (Abs(FFramesPrev[i].X2 - X2) < 1) and (Abs(FFramesPrev[i].Y2 - Y2) < 1) then
    begin
      f.T0 := FFramesPrev[i].T0;
      Break;
    end;
  n := Length(FFrames);
  SetLength(FFrames, n + 1);
  FFrames[n] := f;
  if not f.Live then DrawBorder(f);   // still: in the base, like the original
end;

{ the border of a frame, with its style, colour, glow and intro }
procedure TGameHud.DrawBorder(const F: THudFrame);
var
  fx: TFrameFx;
  now: Double;
  t, ab, wid, glow, ip, k, cx, cy, x1, y1, x2, y2, r, len, u, u2, pulse, w, h, L, d, per, bx: Single;
  style, cmode, intro, cnt, i, j, n: Integer;
  col, c: TBGRAPixel;
  p, q, nn: TPointF;
  pts: array of TPointF;
  qa, sw, sh: Single;
  mids: array[0..3] of Single;

  { the border from U0 to U1 in segments (colour along the border) }
  procedure Segs(U0, U1, AAlpha, AWidth: Single; ARainbow, ADashes: Boolean);
  var
    m, s: Integer;
    ua, ub: Single;
    pa, pb, na, nb: TPointF;
    cc: TBGRAPixel;
  begin
    m := Max(8, Round(len * (U1 - U0) / 5));
    for s := 0 to m - 1 do
    begin
      ua := U0 + (U1 - U0) * s / m;
      ub := U0 + (U1 - U0) * (s + 1) / m;
      if ADashes and (Frac(Frac(ua * len / per - t * 1.5) + 1) > 0.55) then Continue;
      PerimPoint(x1, y1, x2, y2, r, ua, pa, na);
      PerimPoint(x1, y1, x2, y2, r, ub, pb, nb);
      if ARainbow then cc := StatHue(ua + t * 0.15) else cc := FrameColour(fx, t, ua);
      cc.alpha := EnsureRange(Round(AAlpha), 0, 255);
      FTarget.DrawLineAntialias(pa.x, pa.y, pb.x, pb.y, cc, AWidth);
    end;
  end;

  procedure Ring(AGrow, AAlpha, AWidth: Single; const AC: TBGRAPixel);
  begin
    if AAlpha < 1 then Exit;
    FTarget.RoundRectAntialias(x1 - AGrow, y1 - AGrow, x2 + AGrow, y2 + AGrow, r + AGrow, r + AGrow,
      BGRA(AC.red, AC.green, AC.blue, EnsureRange(Round(AAlpha), 0, 255)), AWidth);
  end;

begin
  fx := MenuFx.Frame[F.Kind];
  now := HudClock;
  t := now * fx.V[fpSpeed];
  style := Round(fx.V[fpStyle]);
  cmode := Round(fx.V[fpColourMode]);
  intro := Round(fx.V[fpIntro]);
  cnt := Round(fx.V[fpCount]);
  ab := 110 * fx.V[fpBright];
  wid := fx.V[fpWidth];
  glow := fx.V[fpGlow];
  ip := 1;
  if intro <> 0 then ip := Clamp01((now - F.T0) / Max(0.05, fx.V[fpIntroTime]));
  x1 := F.X1; y1 := F.Y1; x2 := F.X2; y2 := F.Y2; r := F.R;
  if (intro = 3) and (ip < 1) then
  begin
    { expand: the border grows out of a smaller one }
    k := 0.82 + 0.18 * EaseOutBack(ip);
    cx := (x1 + x2) / 2;
    cy := (y1 + y2) / 2;
    x1 := cx - (cx - x1) * k; x2 := cx + (x2 - cx) * k;
    y1 := cy - (cy - y1) * k; y2 := cy + (y2 - cy) * k;
    ab *= ip;
  end;
  w := x2 - x1;
  h := y2 - y1;
  len := PerimLength(x1, y1, x2, y2, r);
  per := 10 + 30 / Max(1, cnt);
  col := FrameColour(fx, t, 0);
  FTarget := Bmp;
  if not F.Live then FTarget := FBase;

  { glow: soft rings around any style }
  if glow > 0 then
    for j := 1 to 3 do Ring(j * 2, ab * 0.4 * glow / j, 2, col);

  if (intro = 1) and (ip < 1) then
  begin
    { the border draws itself in, a bright head leading }
    u := EaseOut(ip);
    Segs(0, u, Min(255, ab * 1.6), wid, False, False);
    PerimPoint(x1, y1, x2, y2, r, u, p, nn);
    FTarget.FillEllipseAntialias(p.x, p.y, wid * 2.2, wid * 2.2, BGRA(255, 255, 255, 230));
    Exit;
  end;

  case style of
    1:
      begin
        pulse := 0.5 + 0.5 * Sin(t * 2.5);
        if cmode in [2, 3, 4] then Segs(0, 1, ab * (0.6 + 0.7 * pulse), wid, False, False)
        else Ring(0, ab * (0.6 + 0.7 * pulse), wid, col);
        for j := 1 to 3 do Ring(j * 2, ab * (0.25 + 0.3 * pulse) / j, 2, col);
      end;
    2:
      begin
        if cmode in [2, 3, 4] then Segs(0, 1, ab * 0.7, wid, False, False) else Ring(0, ab * 0.7, wid, col);
        for i := 0 to cnt - 1 do
        begin
          u := Frac(t * 0.12 + i / cnt);
          for j := 0 to 13 do
          begin
            u2 := u - j * 0.005;
            PerimPoint(x1, y1, x2, y2, r, u2, p, nn);
            c := Mix(FrameColour(fx, t, u2), White, 0.55 - j * 0.04);
            c.alpha := EnsureRange(Round(255 * (1 - j / 14) * Min(1, fx.V[fpBright])), 0, 255);
            FTarget.FillEllipseAntialias(p.x, p.y, wid * (1.9 - j * 0.1), wid * (1.9 - j * 0.1), c);
          end;
        end;
      end;
    3: Segs(0, 1, Min(255, ab * 1.5), wid, True, False);
    4: Segs(0, 1, Min(255, ab * 1.6), wid, False, True);
    5:
      begin
        if cmode in [2, 3, 4] then Segs(0, 1, ab, wid, False, False) else Ring(0, ab, wid, col);
        for i := 0 to Min(cnt, 4) - 1 do
        begin
          d := Frac(t * 0.5 + i / Max(1, Min(cnt, 4)));
          Ring(d * 14, ab * 1.2 * (1 - d), Max(1, wid * (1 - d)), col);
        end;
      end;
    6:
      begin
        { electric: a jagged line that jumps around the border }
        Ring(0, ab * 0.5, wid, col);
        n := Max(16, Round(len / 9));
        SetLength(pts, n + 1);
        for i := 0 to n do
        begin
          PerimPoint(x1, y1, x2, y2, r, i / n, p, nn);
          d := (StatRnd(i mod n, Floor(t * 18)) - 0.5) * wid * 4;
          pts[i] := PointF(p.x + nn.x * d, p.y + nn.y * d);
        end;
        c := Mix(col, White, 0.45);
        c.alpha := EnsureRange(Round(ab * 2), 0, 255);
        FTarget.DrawPolyLineAntialias(pts, c, Max(1, wid * 0.8));
        Ring(2, ab * 0.5, 3, col);
      end;
    7:
      begin
        { neon tube flicker }
        k := 0.85 + 0.15 * Sin(t * 50);
        if StatRnd(Floor(t * 12), F.Kind) < 0.15 then k := 0.2;
        if cmode in [2, 3, 4] then Segs(0, 1, Min(255, ab * 1.4 * k), wid, False, False)
        else Ring(0, Min(255, ab * 1.4 * k), wid, col);
        Ring(2, ab * 0.5 * k, 3, col);
      end;
    8:
      begin
        { corner brackets: bright pieces of the border around the corners }
        if cmode in [2, 3, 4] then Segs(0, 1, ab * 0.5, wid, False, False) else Ring(0, ab * 0.5, wid, col);
        sw := Max(0, w - 2 * r);
        sh := Max(0, h - 2 * r);
        qa := Pi * r / 2;
        mids[0] := sw + qa / 2;
        mids[1] := sw + qa + sh + qa / 2;
        mids[2] := 2 * sw + 2 * qa + sh + qa / 2;
        mids[3] := len - qa / 2;
        L := Min(w, h) * (0.2 + 0.08 * Sin(t * 2)) / Max(1, len);
        for i := 0 to 3 do
        begin
          u := mids[i] / Max(1, len);
          Segs(u - L, u + L, Min(255, 255 * fx.V[fpBright]), wid * 2, False, False);
        end;
      end;
    9:
      begin
        { scan line: a band of light sweeping across the inside }
        if cmode in [2, 3, 4] then Segs(0, 1, ab, wid, False, False) else Ring(0, ab, wid, col);
        bx := x1 + Frac(t * 0.3) * (w + 80) - 40;
        for j := -6 to 6 do
          if (bx + j > x1 + r) and (bx + j < x2 - r) then
            FTarget.FillRect(Round(bx + j), Round(y1 + 2), Round(bx + j) + 1, Round(y2 - 2),
              BGRA(col.red, col.green, col.blue, Round(Min(255, 26 * fx.V[fpBright]) * (1 - Abs(j) / 7))),
              dmDrawWithTransparency);
      end;
  else
    if cmode in [2, 3, 4] then Segs(0, 1, ab, wid, False, False) else Ring(0, ab, wid, col);
  end;

  { flash intro: white light fading off the border }
  if (intro = 2) and (ip < 1) then
    for j := 0 to 3 do Ring(j * 2, 255 * (1 - ip) / (j + 1), 2.5, White);
end;

procedure TGameHud.DrawFrames;
var
  i: Integer;
begin
  for i := 0 to High(FFrames) do
    if FFrames[i].Live then DrawBorder(FFrames[i]);
end;

function TGameHud.FramesBusy: Boolean;
var
  i: Integer;
  fx: TFrameFx;
begin
  for i := 0 to High(FFrames) do
    if FFrames[i].Live then
    begin
      fx := MenuFx.Frame[FFrames[i].Kind];
      if (Round(fx.V[fpStyle]) <> 0) or (Round(fx.V[fpColourMode]) in [2, 3, 4]) then Exit(True);
      if (Round(fx.V[fpIntro]) <> 0) and (HudClock - FFrames[i].T0 < fx.V[fpIntroTime]) then Exit(True);
    end;
  Result := (FBarOn and (Round(MenuFx.StatusX[sxBar]) <> 0)) or
    ((Length(FHintsL) > 0) and (Round(MenuFx.StatusX[sxHints]) <> 0));
end;

{ ---- status bar extras }

{ the filled part of a progress bar (the empty bar is in the base) }
procedure TGameHud.BarFill(X1, Y1, X2, Y2, AFrac: Single; const C: TBGRAPixel);
begin
  FBarOn := False;
  if AFrac <= 0 then Exit;
  if Round(MenuFx.StatusX[sxBar]) = 0 then
  begin
    FTarget.FillRoundRectAntialias(X1, Y1, X1 + (X2 - X1) * AFrac, Y2, 4, 4, C);   // the original
    Exit;
  end;
  FBarOn := True;
  FBarX1 := X1; FBarY1 := Y1; FBarX2 := X2; FBarY2 := Y2;
  FBarFrac := AFrac;
  FBarC := C;
end;

{ a key hint of the status bar: drawn now when still, else every frame }
procedure TGameHud.HintTxt(AFont: THudFont; const S: string; X, Y: Single; const C: TBGRAPixel; AAlign: Integer);
var
  n: Integer;
begin
  if Round(MenuFx.StatusX[sxHints]) = 0 then
  begin
    Txt(AFont, S, X, Y, C, AAlign);
    Exit;
  end;
  n := Length(FHintsL);
  SetLength(FHintsL, n + 1);
  FHintsL[n].Font := Ord(AFont);
  FHintsL[n].Text := S;
  FHintsL[n].X := X;
  FHintsL[n].Y := Y;
  FHintsL[n].Colour := (Cardinal(C.red) shl 16) or (Cardinal(C.green) shl 8) or C.blue;
  FHintsL[n].Align := AAlign;
end;

procedure TGameHud.DrawStatusX;
var
  t, x, x2, y1, y2, h, f, a, op, dy, bw, px: Single;
  style, i, n, k: Integer;
  c, cc: TBGRAPixel;
  pts: array of TPointF;
  tb: TBGRABitmap;
  hs: THudHint;
  font: THudFont;
  pd: PBGRAPixel;
begin
  FTarget := Bmp;
  t := HudClock;
  if FBarOn then
  begin
    style := Round(MenuFx.StatusX[sxBar]);
    x := FBarX1;
    y1 := FBarY1;
    y2 := FBarY2;
    h := y2 - y1;
    x2 := x + (FBarX2 - x) * FBarFrac;
    c := FBarC;
    a := MenuFx.StatusX[sxBarGlow];
    if a > 0 then
      for k := 1 to 3 do
        FTarget.RoundRectAntialias(x - k * 1.5, y1 - k * 1.5, x2 + k * 1.5, y2 + k * 1.5, 4 + k, 4 + k,
          BGRA(c.red, c.green, c.blue, EnsureRange(Round(90 * a / k), 0, 255)), 1.5);
    case style of
      2:
        begin
          { moving diagonal stripes, lighter where the fill is }
          FTarget.FillRoundRectAntialias(x, y1, x2, y2, 4, 4, c);
          for k := Max(0, Floor(y1)) to Min(FTarget.Height - 1, Ceil(y2)) do
          begin
            pd := FTarget.ScanLine[k];
            for i := Max(0, Floor(x)) to Min(FTarget.Width - 1, Ceil(x2)) do
              if (pd[i].alpha > 200) and (Frac((i + k) / (h * 1.6) - t * 1.2 + 100) < 0.5) then
                pd[i] := Mix(pd[i], White, 0.28);
          end;
          FTarget.InvalidateBitmap;
        end;
      3:
        begin
          { liquid: a wavy surface sloshing in the bar }
          FTarget.FillRoundRectAntialias(x, y1, x2, y2, 4, 4, Mix(c, BGRA(0, 0, 0), 0.35));
          n := Max(2, Round((x2 - x) / 3));
          SetLength(pts, n + 3);
          for i := 0 to n do
          begin
            f := x + (x2 - x) * i / n;
            pts[i] := PointF(f, y1 + h * (0.3 + 0.22 * Sin(f * 0.25 - t * 6)));
          end;
          pts[n + 1] := PointF(x2, y2);
          pts[n + 2] := PointF(x, y2);
          FTarget.FillPolyAntialias(pts, Mix(c, White, 0.15));
        end;
      4:
        begin
          { LED segments: the last lit one blinks }
          bw := h * 1.3;
          n := Max(1, Floor((FBarX2 - x) / bw));
          k := Ceil(FBarFrac * n);
          for i := 0 to k - 1 do
          begin
            cc := c;
            if (i = k - 1) and (Frac(t * 2.5) > 0.5) then cc := Mix(c, White, 0.6);
            FTarget.FillRoundRectAntialias(x + i * bw, y1, x + i * bw + bw * 0.78, y2, 2, 2, cc);
          end;
        end;
      5:
        begin
          n := Max(1, Round((x2 - x) / 4));
          for i := 0 to n - 1 do
          begin
            cc := StatHue((i / Max(1, n)) * FBarFrac + t * 0.2);
            FTarget.FillRectAntialias(x + (x2 - x) * i / n, y1, x + (x2 - x) * (i + 1) / n + 0.5, y2, cc);
          end;
        end;
      6:
        begin
          op := 0.5 + 0.5 * Sin(t * 4);
          FTarget.FillRoundRectAntialias(x, y1, x2, y2, 4, 4, Mix(c, White, 0.3 * op));
          FTarget.FillEllipseAntialias(x2, (y1 + y2) / 2, h * (1 + op), h * (1 + op),
            BGRA(255, 255, 255, Round(90 * op)));
        end;
    else
      FTarget.FillRoundRectAntialias(x, y1, x2, y2, 4, 4, c);   // glow only
    end;
  end;

  style := Round(MenuFx.StatusX[sxHints]);
  a := MenuFx.StatusX[sxHintAmount];
  for i := 0 to High(FHintsL) do
  begin
    hs := FHintsL[i];
    font := THudFont(EnsureRange(hs.Font, 0, Ord(High(THudFont))));
    c := StatCard(hs.Colour);
    op := 1;
    dy := 0;
    case style of
      1: op := 1 - Min(0.9, a * 0.45 * (0.5 + 0.5 * Sin(t * 2 + i * 1.3)));
      2: c := Mix(c, CycleColour(t * 0.2 + i * 0.3), Min(1, 0.6 * a));
      4:
        begin
          tb := TextBmp(font, 'M', White);
          if tb <> nil then dy := tb.Height * 0.12 * a * Sin(t * 2.4 + i * 1.7);
        end;
    end;
    TxtTint(font, hs.Text, hs.X, hs.Y + dy, c, hs.Align, op, 0);
    if style = 3 then
    begin
      tb := TextBmp(font, hs.Text, White);
      if tb <> nil then
      begin
        case hs.Align of
          0: px := hs.X - tb.Width / 2;
          1: px := hs.X - tb.Width;
        else
          px := hs.X;
        end;
        f := Frac(t * 0.3 + i * 0.37);
        BlendShine(tb, Round(px), Round(hs.Y - tb.Height / 2), White, Min(1, 0.8 * a),
          px - tb.Width * 0.3 + f * tb.Width * 1.6, tb.Height * 0.8);
      end;
    end;
  end;
end;
