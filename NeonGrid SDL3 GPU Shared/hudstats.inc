{ hudstats.inc - Level / Score / Best of the in-game top bar, drawn every
  frame with their own effects (MenuFx.Stat, see uMenuFx). Included in the
  implementation of uGameHud of Neon Beads and Neon Trail (both HUDs have
  the same helpers: TextBmp, GlowText, Blend, BlendShine, Mix, CycleColour,
  EaseOut, Clamp01, HudClock).

  DrawBase records the stats with StatTxt instead of drawing them; Update
  draws them over the cached base with DrawStats, and keeps redrawing while
  StatsBusy (a looping style, moving colours or a running reaction). }

function StatCard(C: Cardinal): TBGRAPixel;
begin
  Result := BGRA((C shr 16) and 255, (C shr 8) and 255, C and 255);
end;

function StatHue(h: Single): TBGRAPixel;
var
  r, g, b: Single;
begin
  h := Frac(Frac(h) + 1) * 6;
  r := Clamp01(Abs(h - 3) - 1);
  g := Clamp01(2 - Abs(h - 2));
  b := Clamp01(2 - Abs(h - 4));
  { a little white keeps the neon colours readable on the dark bar }
  Result := BGRA(Round(70 + 185 * r), Round(70 + 185 * g), Round(70 + 185 * b));
end;

{ 0..1, the same for the same (a, b) }
function StatRnd(a, b: Integer): Single;
var
  h: Cardinal;
begin
  h := Cardinal(a) * 374761393 + Cardinal(b) * 668265263;
  h := (h xor (h shr 13)) * 1274126177;
  Result := ((h xor (h shr 16)) and $FFFF) / 65535;
end;

procedure TGameHud.StatTxt(AKind: Integer; AFont: THudFont; const APrefix: string; AValue: Int64;
  X, Y: Single; const C: TBGRAPixel; AAlign: Integer);
var
  n: Integer;
begin
  n := Length(FStats);
  SetLength(FStats, n + 1);
  FStats[n].Text := '';
  FStats[n].Kind := EnsureRange(AKind, 0, StatCount - 1);
  FStats[n].Font := Ord(AFont);
  FStats[n].Prefix := APrefix;
  FStats[n].Value := AValue;
  FStats[n].X := X;
  FStats[n].Y := Y;
  FStats[n].Colour := (Cardinal(C.red) shl 16) or (Cardinal(C.green) shl 8) or C.blue;
  FStats[n].Align := AAlign;
end;

{ a stat shown as a whole text (AValue only tells a change: bigger = react) }
procedure TGameHud.StatTxtS(AKind: Integer; AFont: THudFont; const AText: string; AValue: Int64;
  X, Y: Single; const C: TBGRAPixel; AAlign: Integer);
begin
  StatTxt(AKind, AFont, '', AValue, X, Y, C, AAlign);
  FStats[High(FStats)].Text := AText;
end;

function TGameHud.TextAdvance(AFont: THudFont; const S: string): Single;
var
  w, h: LongInt;
begin
  Result := 0;
  if (S = '') or (FFonts[AFont] = nil) then Exit;
  w := 0;
  h := 0;
  if TTF_GetStringSize(FFonts[AFont], PAnsiChar(S), Length(S), @w, @h) then Result := w;
end;

{ Blend scaled by SX, SY around the centre CX, CY (bilinear alpha) }
procedure TGameHud.BlendXf(ASrc: TBGRABitmap; CX, CY, SX, SY: Single; const C: TBGRAPixel; AOpacity: Single);
var
  x0, y0, x1, y1, dx, dy, ix, iy: Integer;
  left, top, u, v, fu, fv, a, da, oa, f1, f2: Single;
  pd: PBGRAPixel;

  function Alpha(px, py: Integer): Single; inline;
  begin
    if (px < 0) or (py < 0) or (px >= ASrc.Width) or (py >= ASrc.Height) then Exit(0);
    Result := (ASrc.ScanLine[py] + px)^.alpha;
  end;

begin
  if (ASrc = nil) or (AOpacity <= 0.004) or (SX <= 0.01) or (SY <= 0.01) then Exit;
  if (Abs(SX - 1) < 0.01) and (Abs(SY - 1) < 0.01) then
  begin
    Blend(ASrc, Round(CX - ASrc.Width / 2), Round(CY - ASrc.Height / 2), C, AOpacity);
    Exit;
  end;
  left := CX - ASrc.Width * SX / 2;
  top := CY - ASrc.Height * SY / 2;
  x0 := Max(0, Floor(left));
  y0 := Max(0, Floor(top));
  x1 := Min(FTarget.Width - 1, Ceil(left + ASrc.Width * SX));
  y1 := Min(FTarget.Height - 1, Ceil(top + ASrc.Height * SY));
  for dy := y0 to y1 do
  begin
    v := (dy + 0.5 - top) / SY - 0.5;
    iy := Floor(v);
    fv := v - iy;
    pd := FTarget.ScanLine[dy] + x0;
    for dx := x0 to x1 do
    begin
      u := (dx + 0.5 - left) / SX - 0.5;
      ix := Floor(u);
      fu := u - ix;
      a := (Alpha(ix, iy) * (1 - fu) + Alpha(ix + 1, iy) * fu) * (1 - fv) +
        (Alpha(ix, iy + 1) * (1 - fu) + Alpha(ix + 1, iy + 1) * fu) * fv;
      a := a * AOpacity / 255;
      if a > 0.004 then
      begin
        da := pd^.alpha / 255;
        oa := a + da * (1 - a);
        f1 := a / oa;
        f2 := 1 - f1;
        pd^.red := Round(C.red * f1 + pd^.red * f2);
        pd^.green := Round(C.green * f1 + pd^.green * f2);
        pd^.blue := Round(C.blue * f1 + pd^.blue * f2);
        pd^.alpha := Round(oa * 255);
      end;
      Inc(pd);
    end;
  end;
end;

function TGameHud.StatsBusy: Boolean;
var
  i: Integer;
  fx: TStatFx;
  st: THudStatState;
begin
  for i := 0 to High(FStats) do
  begin
    fx := MenuFx.Stat[FStats[i].Kind];
    if (Round(fx.V[spStyle]) <> 0) or (Round(fx.V[spColourMode]) in [2, 3, 4]) then Exit(True);
    st := FStatSt[FStats[i].Kind];
    if st.Known and (Round(fx.V[spReact]) <> 0) and (HudClock - st.T0 < fx.V[spReactTime]) then Exit(True);
  end;
  Result := False;
end;

procedure TGameHud.DrawStats;
var
  k, i, j, n, style, react, cmode, len: Integer;
  fx: TStatFx;
  hs: THudStat;
  font: THudFont;
  now, t, s, a, p, q, sx, sy, glow, op, h, w, anchor, x0, cx, cy, dyl, dxl, fl, band, r, ang: Single;
  shown: Int64;
  stext, ch, och: string;
  gl, gg: TBGRABitmap;
  base, col: TBGRAPixel;
  active, glitch: Boolean;
  adv: array of Single;
begin
  now := HudClock;
  FTarget := Bmp;
  for k := 0 to High(FStats) do
  begin
    hs := FStats[k];
    fx := MenuFx.Stat[hs.Kind];
    font := THudFont(EnsureRange(hs.Font, 0, Ord(High(THudFont))));
    style := Round(fx.V[spStyle]);
    react := Round(fx.V[spReact]);
    cmode := Round(fx.V[spColourMode]);
    s := fx.V[spStrength];

    { a changed value starts the reaction (not a smaller one: a new game) }
    with FStatSt[hs.Kind] do
    begin
      if not Known or (hs.Value < Val) then
      begin
        Known := True;
        Val := hs.Value;
        OldVal := hs.Value;
        OldText := '';
        T0 := -1000;
      end
      else if hs.Value <> Val then
      begin
        OldVal := Val;
        OldText := LastText;
        Val := hs.Value;
        T0 := now;
      end;
      a := now - T0;
      p := a / Max(0.05, fx.V[spReactTime]);
      active := (react <> 0) and (p < 1);
      shown := Val;
      { a text stat (the status bar) has nothing to count up }
      if active and (react in [3, 4]) and (hs.Text = '') then shown := OldVal + Round((Val - OldVal) * EaseOut(p));
      och := OldText;
      if hs.Text <> '' then LastText := hs.Text else LastText := hs.Prefix + FormatFloat('#,##0', Val);
    end;
    if hs.Text <> '' then stext := hs.Text
    else stext := hs.Prefix + FormatFloat('#,##0', shown);
    len := Length(stext);
    if len = 0 then Continue;

    t := now * fx.V[spSpeed];
    gl := TextBmp(font, 'M', White);
    if gl = nil then Continue;
    h := gl.Height;

    { the whole text: size, pulse / heartbeat / jelly, the pop reaction }
    sx := fx.V[spSize];
    sy := sx;
    case style of
      1: begin sx *= 1 + 0.07 * s * (0.5 + 0.5 * Sin(t * 4)); sy := sx; end;
      7:
        begin
          q := Frac(t * 0.9);
          q := Exp(-Sqr((q - 0.1) * 18)) + 0.6 * Exp(-Sqr((q - 0.3) * 18));
          sx *= 1 + 0.12 * s * q;
          sy := sx;
        end;
      8:
        begin
          q := Sin(t * 6);
          sx *= 1 + 0.08 * s * q;
          sy *= 1 - 0.08 * s * q;
        end;
    end;
    if active and (react in [1, 4]) then
    begin
      q := 1 + 0.45 * s * Power(1 - p, 3);
      sx *= q;
      sy *= q;
    end;

    { letter positions (kerning of the whole string), anchored like the text was }
    SetLength(adv, len + 1);
    for i := 0 to len do adv[i] := TextAdvance(font, Copy(stext, 1, i));
    w := adv[len];
    anchor := hs.X;   // the text grows from where it is aligned
    case hs.Align of
      0: x0 := hs.X - w / 2;
      1: x0 := hs.X - w;
    else
      x0 := hs.X;
    end;

    { glow: its own amount, pulsing (style 2), flashing (reaction) }
    glow := fx.V[spGlow];
    if style = 2 then glow += s * (0.35 + 0.45 * (0.5 + 0.5 * Sin(t * 3)));
    if active and (react = 2) then glow += 1.2 * (1 - p);

    { glitch: short bursts of torn letters with colour split }
    glitch := (style = 9) and (Frac(t * 0.6) < 0.05 + 0.06 * Min(s, 2));
    base := StatCard(hs.Colour);
    if cmode = 1 then base := StatCard(fx.Colour);

    for i := 1 to len do
    begin
      ch := stext[i];
      if ch = ' ' then Continue;
      gl := TextBmp(font, ch, White);
      if gl = nil then Continue;
      { colour of this letter }
      case cmode of
        2: col := StatHue(t * 0.15 + i * 0.07);
        3: col := CycleColour(t * 0.25 + i * 0.12);
        4: col := Mix(StatCard(fx.Colour), StatCard(fx.Colour2), 0.5 + 0.5 * Sin(t * 2 - i * 0.5));
      else
        col := base;
      end;
      if style = 2 then col := Mix(col, White, 0.15 * s * (0.5 + 0.5 * Sin(t * 3)));
      if active and (react = 2) then col := Mix(col, White, 1 - p);
      op := 1;
      dxl := 0;
      dyl := 0;
      case style of
        3: dyl := -h * 0.12 * s * Sin(t * 5 - i * 0.7);
        5:
          begin
            { neon tube flicker: random short dips per letter }
            fl := StatRnd(i, Floor(t * 14));
            if fl < 0.12 * Min(s, 3) then op := 0.25 + 0.5 * StatRnd(i * 7, Floor(t * 40));
          end;
        6: dyl := -h * 0.3 * s * Sqr(Max(0, Sin(t * 3 - i * 0.45)));
        9:
          if glitch then
          begin
            dxl := (StatRnd(i, Floor(t * 30)) - 0.5) * h * 0.3 * s;
            dyl := (StatRnd(i * 3, Floor(t * 30)) - 0.5) * h * 0.12 * s;
          end;
      end;
      if active and (react = 5) then dxl += s * h * 0.15 * (1 - p) * Sin(a * 55 + i);
      { the letter centre, scaled from the anchor }
      cx := anchor + (x0 + (adv[i - 1] + gl.Width / 2) - anchor) * sx + dxl;
      cy := hs.Y + dyl * sy;

      { rolling digits: the changed letters roll up out of the old value }
      if active and (react = 7) then
      begin
        j := i - (len - Length(och));
        if (j >= 1) and (j <= Length(och)) and (och[j] = ch) then
          { unchanged letter: drawn below as usual }
        else
        begin
          q := EaseOut(p);
          if (j >= 1) and (j <= Length(och)) and (och[j] <> ' ') then
          begin
            gg := TextBmp(font, och[j], White);
            BlendXf(gg, cx, cy - h * 0.8 * q * sy, sx, sy, col, (1 - q) * op);
          end;
          if glow > 0 then BlendXf(GlowText(font, ch), cx, cy + h * 0.8 * (1 - q) * sy, sx, sy, col, Min(1, glow) * q);
          BlendXf(gl, cx, cy + h * 0.8 * (1 - q) * sy, sx, sy, col, q * op);
          Continue;
        end;
      end;

      if glow > 0 then
      begin
        gg := GlowText(font, ch);
        BlendXf(gg, cx, cy, sx, sy, col, Min(1, glow * op));
      end;
      if glitch then
      begin
        BlendXf(gl, cx - h * 0.06, cy, sx, sy, BGRA(255, 40, 200), 0.55 * op);
        BlendXf(gl, cx + h * 0.06, cy, sx, sy, BGRA(40, 230, 255), 0.55 * op);
      end;
      BlendXf(gl, cx, cy, sx, sy, col, op);
      { light sweep across the whole text (unscaled letters only) }
      if (style = 4) and (Abs(sx - 1) < 0.01) and (Abs(sy - 1) < 0.01) then
      begin
        band := x0 + (Frac(t * 0.35) * 1.8 - 0.4) * w;
        BlendShine(gl, Round(cx - gl.Width / 2), Round(cy - gl.Height / 2), White, Min(1, 0.85 * s), band, h * 0.55);
      end;
    end;

    { sparkle burst: little stars flying out of the text }
    if active and (react = 6) then
    begin
      n := 14;
      for j := 0 to n - 1 do
      begin
        ang := j * 2 * Pi / n + StatRnd(j, hs.Kind) * 0.5;
        r := (0.15 + EaseOut(p) * (0.7 + 0.4 * StatRnd(j * 5, hs.Kind))) * Max(w * 0.6, h * 1.2) * Min(2, 0.6 + 0.4 * s);
        cx := x0 + w / 2 + Cos(ang) * r;
        cy := hs.Y + Sin(ang) * r * 0.55;
        q := h * 0.07 * (1 - p) * (0.7 + 0.6 * StatRnd(j * 11, hs.Kind));
        col := CycleColour(j / n + t * 0.2);
        col.alpha := Round(255 * (1 - p));
        FTarget.FillEllipseAntialias(cx, cy, q, q, col);
        FTarget.FillEllipseAntialias(cx, cy, q * 0.45, q * 0.45, BGRA(255, 255, 255, Round(255 * (1 - p))));
      end;
    end;
  end;
end;
