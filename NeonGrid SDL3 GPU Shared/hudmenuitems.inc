{ hudmenuitems.inc - the menu items that are not selected (MenuFx.Item, see
  uMenuFx). Included in the implementation of uGameHud of Neon Beads and
  Neon Trail after hudstats.inc (uses StatHue, StatCard, BlendXf).

  DrawMenuItems calls ItemsTrack first (it notices the selector moving:
  the item it left starts its reaction and gets the trail particles), draws
  every other item with DrawIdleItem and finally the particles with
  DrawMenuParts. Art styles that change the letters (pixel art, neon tube,
  LED dots) are made once per text and cached (ArtBmp). }

const
  MaxMenuParts = 500;

{ the white letters of S in an art style (cached; plain styles use TextBmp) }
function TGameHud.ArtBmp(AFont: THudFont; const S: string; AArt, APix: Integer): TBGRABitmap;
var
  key: string;
  i, x, y, bx, by, n, sum, r, e, mn, xx, yy: Integer;
  src: TBGRABitmap;
  ps, pd: PBGRAPixel;
begin
  src := TextBmp(AFont, S, White);
  Result := src;
  if (src = nil) or not (AArt in [1, 2, 6]) then Exit;
  APix := EnsureRange(APix, 2, 8);
  key := Format('%d|%d|%d|%s', [AArt, APix, Ord(AFont), S]);
  i := FArtCache.IndexOf(key);
  if i >= 0 then Exit(TBGRABitmap(FArtCache.Objects[i]));
  Result := TBGRABitmap.Create(src.Width, src.Height, BGRAPixelTransparent);
  case AArt of
    1, 6:
      { pixel art: blocks of APix pixels, on or off; LED dots: a round dot per block }
      for by := 0 to (src.Height - 1) div APix do
        for bx := 0 to (src.Width - 1) div APix do
        begin
          sum := 0;
          n := 0;
          for y := by * APix to Min(src.Height - 1, by * APix + APix - 1) do
            for x := bx * APix to Min(src.Width - 1, bx * APix + APix - 1) do
            begin
              sum += (src.ScanLine[y] + x)^.alpha;
              Inc(n);
            end;
          if n = 0 then Continue;
          if AArt = 1 then
          begin
            if sum / n > 90 then
              Result.FillRect(bx * APix, by * APix, bx * APix + APix, by * APix + APix, White, dmSet);
          end
          else if sum / n > 60 then
            Result.FillEllipseAntialias(bx * APix + APix / 2 - 0.5, by * APix + APix / 2 - 0.5, APix * 0.42,
              APix * 0.42, White);
        end;
    2:
      begin
        { neon tube: only the rim of the letters (alpha minus the eroded alpha) }
        r := Max(1, Round(src.Height * 0.06));
        for y := 0 to src.Height - 1 do
        begin
          pd := Result.ScanLine[y];
          ps := src.ScanLine[y];
          for x := 0 to src.Width - 1 do
          begin
            e := ps[x].alpha;
            if e > 0 then
            begin
              mn := e;
              for yy := Max(0, y - r) to Min(src.Height - 1, y + r) do
                for xx := Max(0, x - r) to Min(src.Width - 1, x + r) do
                  mn := Min(mn, (src.ScanLine[yy] + xx)^.alpha);
              e := EnsureRange(e - Round(mn * 0.9), 0, 255);
              pd[x] := BGRA(255, 255, 255, e);
            end;
          end;
        end;
      end;
  end;
  Result.InvalidateBitmap;
  if FArtCache.Count > 200 then FArtCache.Clear;
  FArtCache.AddObject(key, Result);
end;

{ like BlendXf with a colour per source row (one colour: the whole text) }
procedure TGameHud.BlendRows(ASrc: TBGRABitmap; CX, CY, SX, SY: Single; const ARows: array of TBGRAPixel;
  AOpacity: Single);
var
  x0, y0, x1, y1, dx, dy, ix, iy, nr: Integer;
  left, top, u, v, fu, fv, a, da, oa, f1, f2: Single;
  pd: PBGRAPixel;
  c: TBGRAPixel;

  function Alpha(px, py: Integer): Single; inline;
  begin
    if (px < 0) or (py < 0) or (px >= ASrc.Width) or (py >= ASrc.Height) then Exit(0);
    Result := (ASrc.ScanLine[py] + px)^.alpha;
  end;

begin
  nr := Length(ARows);
  if (ASrc = nil) or (nr = 0) or (AOpacity <= 0.004) or (SX <= 0.01) or (SY <= 0.01) then Exit;
  if nr = 1 then
  begin
    BlendXf(ASrc, CX, CY, SX, SY, ARows[0], AOpacity);
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
    c := ARows[EnsureRange(Round(v), 0, nr - 1)];
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
        pd^.red := Round(c.red * f1 + pd^.red * f2);
        pd^.green := Round(c.green * f1 + pd^.green * f2);
        pd^.blue := Round(c.blue * f1 + pd^.blue * f2);
        pd^.alpha := Round(oa * 255);
      end;
      Inc(pd);
    end;
  end;
end;

{ the size and place an item was drawn at (where its trail starts) }
procedure TGameHud.ItemGeom(AIndex: Integer; X, Y, W, H: Single);
begin
  if (AIndex < 0) or (AIndex > High(FItSt)) then Exit;
  FItSt[AIndex].X := X;
  FItSt[AIndex].Y := Y;
  FItSt[AIndex].W := W;
  FItSt[AIndex].H := H;
end;

function TGameHud.ItemColour(AIndex: Integer; T: Single): TBGRAPixel;
begin
  case Round(MenuFx.Item.V[ipColourMode]) of
    1: Result := StatCard(MenuFx.Item.Colour);
    2: Result := StatHue(T * 0.1 + AIndex * 0.12);
    3: Result := CycleColour(T * 0.25 + AIndex * 0.4);
    4: Result := Mix(StatCard(MenuFx.Item.Colour), StatCard(MenuFx.Item.Colour2), 0.5);
  else
    Result := Mix(BGRA(200, 206, 222), CycleColour(T * MenuFx.V[fxColourSpeed] * 0.25 + AIndex * 0.4),
      (0.12 + 0.08 * Sin(T * 2 + AIndex)) * MenuFx.V[fxItemBreath]);
  end;
end;

procedure TGameHud.SpawnTrail(AIndex: Integer);
var
  kind, n, i: Integer;
  st: TMenuItemState;
  h, w, life: Single;
  p: TMenuPart;
  c: TBGRAPixel;
begin
  kind := Round(MenuFx.Item.V[ipTrail]);
  if (kind <= 0) or (AIndex < 0) or (AIndex > High(FItSt)) then Exit;
  st := FItSt[AIndex];
  h := Max(8, FItemStep);
  w := st.W;
  if w < 4 then w := h * 4;
  case kind of
    3: n := 26;
    5: n := 24;
  else
    n := 20;
  end;
  n := Round(n * MenuFx.Item.V[ipTrailAmount]);
  life := MenuFx.Item.V[ipTrailTime];
  c := ItemColour(AIndex, Menu.Clock * MenuFx.V[fxMenuSpeed]);
  for i := 1 to n do
  begin
    if Length(FMParts) >= MaxMenuParts then Exit;
    p := Default(TMenuPart);
    p.Kind := kind;
    p.X := st.X + (Random - 0.5) * w;
    p.Y := st.Y + (Random - 0.5) * h * 0.5;
    p.Life := life * (0.6 + 0.4 * Random);
    p.Spin := Random * 2 * Pi;
    p.Colour := (Cardinal(c.red) shl 16) or (Cardinal(c.green) shl 8) or c.blue;
    case kind of
      1:
        begin   // dust: drifts off and fades
          p.VX := (Random - 0.5) * h * 1.2 + st.Dir * h * 0.3;
          p.VY := -Random * h * 0.4;
          p.Size := h * (0.05 + 0.07 * Random);
          c := Mix(c, BGRA(190, 190, 205), 0.5);
          p.Colour := (Cardinal(c.red) shl 16) or (Cardinal(c.green) shl 8) or c.blue;
        end;
      2:
        begin   // liquid: drops hang under the letters, then fall
          p.Y := st.Y + st.H * 0.32;
          p.VX := 0;
          p.VY := 0;
          p.Size := h * (0.035 + 0.05 * Random);
          p.Life := life * (0.8 + 0.6 * Random);
        end;
      3:
        begin   // sparks: fly out fast
          p.VX := (Random - 0.5) * h * 7;
          p.VY := -(0.3 + Random) * h * 3;
          p.Size := h * (0.03 + 0.03 * Random);
          p.Life := p.Life * 0.6;
        end;
      4:
        begin   // bubbles: rise and wobble
          p.VY := -h * (0.5 + 0.7 * Random);
          p.Size := h * (0.05 + 0.08 * Random);
        end;
    else
      begin     // confetti: tossed up, tumbling down
        p.VX := (Random - 0.5) * h * 3;
        p.VY := -h * (0.8 + 1.4 * Random);
        p.Size := h * (0.06 + 0.05 * Random);
        c := CycleColour(Random);
        p.Colour := (Cardinal(c.red) shl 16) or (Cardinal(c.green) shl 8) or c.blue;
      end;
    end;
    SetLength(FMParts, Length(FMParts) + 1);
    FMParts[High(FMParts)] := p;
  end;
end;

{ the selector moved: the item it left reacts and gets the trail }
procedure TGameHud.ItemsTrack;
var
  n, i, old: Integer;
  now: Double;
begin
  now := HudClock;
  n := Length(Menu.Items);
  if (n <> Length(FItSt)) or (Menu.Screen <> FItScreen) then
  begin
    SetLength(FItSt, n);
    for i := 0 to n - 1 do
    begin
      FItSt[i] := Default(TMenuItemState);
      FItSt[i].LeaveT := -1000;
      FItSt[i].Dir := 1;
    end;
    FItScreen := Menu.Screen;
    FItSel := Menu.Sel;
    Exit;
  end;
  if Menu.Sel <> FItSel then
  begin
    old := FItSel;
    FItSel := Menu.Sel;
    if (old < 0) or (old >= n) then Exit;
    FItSt[old].LeaveT := now;
    if Menu.Sel > old then FItSt[old].Dir := 1 else FItSt[old].Dir := -1;
    SpawnTrail(old);
  end;
end;

procedure TGameHud.DrawIdleItem(AIndex: Integer; const S: string; X, Y, AOpacity, T: Single);
var
  fx: TItemFx;
  art, pix, j, nr: Integer;
  g, gg, gm, gb: TBGRABitmap;
  k, h, sx, sy, dx, dy, op, a, p, q, w, glow, f: Single;
  col, c1, c2: TBGRAPixel;
  rows: array of TBGRAPixel;
begin
  fx := MenuFx.Item;
  art := Round(fx.V[ipArt]);
  pix := Round(fx.V[ipPixel]);
  { the letter-changing styles start from the big font (finer blocks and
    rims at the menu size), drawn scaled down to the menu font }
  k := 1;
  if art in [1, 2, 6] then
  begin
    g := ArtBmp(hfBig, S, art, pix);
    gm := TextBmp(hfMid, 'M', White);
    gb := TextBmp(hfBig, 'M', White);
    if (gm <> nil) and (gb <> nil) and (gb.Height > 0) then k := gm.Height / gb.Height;
  end
  else
    g := ArtBmp(hfMid, S, art, pix);
  if g = nil then Exit;
  h := g.Height * k;
  col := ItemColour(AIndex, T);
  sx := fx.V[ipSize] * k;
  sy := sx;
  dx := 0;
  dy := 0;
  op := AOpacity;
  { idle motion }
  a := fx.V[ipIdleAmount];
  case Round(fx.V[ipIdle]) of
    1: dy := h * 0.08 * a * Sin(T * 1.6 + AIndex * 0.9);
    2: dx := h * 0.18 * a * Sin(T * 1.3 + AIndex * 0.7);
    3: begin sx *= 1 + 0.05 * a * Sin(T * 2 + AIndex); sy := sx; end;
    4: op *= 1 - Min(0.8, 0.35 * a * (0.5 + 0.5 * Sin(T * 3 + AIndex * 1.1)));
  end;
  { the reaction after the selector left }
  if (AIndex >= 0) and (AIndex <= High(FItSt)) then
  begin
    a := HudClock - FItSt[AIndex].LeaveT;
    p := a / Max(0.05, fx.V[ipLeaveTime]);
    if p < 1 then
    begin
      f := fx.V[ipLeaveStrength];
      case Round(fx.V[ipLeave]) of
        1:
          begin
            { slingshot: pulled after the selector, let go, overshoots, settles }
            q := Exp(-4.5 * p) * Cos(p * 16);
            dy += FItSt[AIndex].Dir * h * 0.5 * f * q;
            sy *= 1 + 0.25 * f * Abs(q);
            sx *= 1 - 0.1 * f * Abs(q);
          end;
        2: dx += h * 0.25 * f * Sqr(1 - p) * Sin(a * 48);
        3:
          begin
            { rubber band twang: stretched sideways, vibrating out }
            q := Exp(-3.5 * p) * Sin(p * 28);
            sx *= 1 + 0.25 * f * q;
            sy *= 1 - 0.12 * f * q;
          end;
        4:
          begin
            q := Exp(-3 * p) * Sin(p * 20);
            sx *= 1 + 0.2 * f * q;
            sy *= 1 - 0.2 * f * q;
          end;
        5: dy -= h * 0.55 * f * (1 - p) * Abs(Sin(p * 3 * Pi));
        6: sx *= Max(0.03, Abs(Cos(EaseOut(p) * 2 * Pi)));
      end;
    end;
  end;
  sx := Max(0.05, sx);
  sy := Max(0.05, sy);

  { the colour of each row: gradient, chrome, scanlines }
  nr := g.Height;
  SetLength(rows, nr);
  c1 := StatCard(fx.Colour);
  c2 := StatCard(fx.Colour2);
  for j := 0 to nr - 1 do
  begin
    f := j / Max(1, nr - 1);
    if Round(fx.V[ipColourMode]) = 4 then
      rows[j] := Mix(c1, c2, Clamp01(f + 0.35 * Sin(T * 1.5 + AIndex)))
    else
      rows[j] := col;
    case art of
      4:
        if f < 0.5 then rows[j] := Mix(White, rows[j], f * 1.7)
        else rows[j] := Mix(Mix(rows[j], BGRA(0, 0, 0), 0.55), rows[j], (f - 0.5) * 2);
      5:
        if (j div Max(1, pix div 2)) mod 2 = 1 then rows[j] := Mix(rows[j], BGRA(0, 0, 0), 0.65);
    end;
  end;

  { halo: own glow, the neon tube and the soft glow styles add to it }
  glow := fx.V[ipGlow];
  if art = 2 then glow += 0.7;
  if art = 7 then glow += 0.9;
  if glow > 0 then
  begin
    gg := GlowText(hfMid, S);
    BlendXf(gg, X + dx, Y + dy, sx / k, sy / k, col, Min(1, glow * op));
  end;
  { 3D block: darker copies behind, down and to the right }
  if art = 3 then
    for j := pix downto 1 do
      BlendXf(g, X + dx + j * 0.7, Y + dy + j, sx, sy, Mix(col, BGRA(0, 0, 0), 0.62), op);
  BlendRows(g, X + dx, Y + dy, sx, sy, rows, op);
  w := g.Width * sx;
  ItemGeom(AIndex, X, Y, w, g.Height * sy);
end;

procedure TGameHud.DrawMenuParts;
var
  now: Double;
  dt, h, f, r, ry, cs, sn: Single;
  i, n: Integer;
  c: TBGRAPixel;
  pts: array of TPointF;
begin
  now := HudClock;
  dt := EnsureRange(now - FPartT, 0, 0.1);
  FPartT := now;
  h := Max(8, FItemStep);
  n := 0;
  for i := 0 to High(FMParts) do
    with FMParts[i] do
    begin
      Age += dt;
      if Age >= Life then Continue;
      f := Age / Life;
      c := StatCard(Colour);
      case Kind of
        1:
          begin
            X += VX * dt;
            Y += VY * dt;
            VX -= VX * 2.2 * dt;
            VY -= VY * 2.2 * dt;
            r := Size * (1 + 1.5 * f);
            c.alpha := Round(110 * (1 - f));
            FTarget.FillEllipseAntialias(X, Y, r, r, c);
          end;
        2:
          begin
            { a drop swells under the letter for a quarter of its life, then falls }
            if f < 0.25 then
            begin
              r := Size * (0.4 + 2.4 * f);
              ry := r * 1.2;
            end
            else
            begin
              VY += h * 7 * dt;
              Y += VY * dt;
              r := Size;
              ry := Size * (1 + Min(2.2, VY / (h * 3)));
            end;
            c.alpha := Round(230 * Min(1, (1 - f) * 2));
            FTarget.FillEllipseAntialias(X, Y + ry * 0.3, r, ry, c);
            FTarget.FillEllipseAntialias(X - r * 0.3, Y, r * 0.3, r * 0.3, BGRA(255, 255, 255, Round(c.alpha * 0.7)));
          end;
        3:
          begin
            X += VX * dt;
            Y += VY * dt;
            VY += h * 6 * dt;
            VX -= VX * 1.5 * dt;
            r := Size * (1 - f * 0.6);
            c := Mix(c, White, 0.4);
            c.alpha := Round(255 * (1 - f));
            FTarget.FillEllipseAntialias(X, Y, r * 1.8, r * 1.8, BGRA(c.red, c.green, c.blue, c.alpha div 3));
            FTarget.FillEllipseAntialias(X, Y, r, r, c);
          end;
        4:
          begin
            Y += VY * dt;
            X += Sin(Age * 6 + Spin) * h * 0.4 * dt;
            r := Size * (1 + 0.3 * f);
            c.alpha := Round(200 * (1 - f));
            FTarget.EllipseAntialias(X, Y, r, r, c, Max(1, r * 0.18));
            FTarget.FillEllipseAntialias(X - r * 0.35, Y - r * 0.35, r * 0.2, r * 0.2,
              BGRA(255, 255, 255, Round(c.alpha * 0.8)));
          end;
      else
        begin
          X += VX * dt;
          Y += VY * dt;
          VY += h * 4 * dt;
          VX -= VX * 1.2 * dt;
          Spin += dt * 9;
          cs := Cos(Spin) * Size;
          sn := Sin(Spin) * Size * 0.5;
          SetLength(pts, 4);
          pts[0] := PointF(X - cs, Y - sn * Abs(Cos(Spin * 0.7)));
          pts[1] := PointF(X + sn, Y - cs * 0.5);
          pts[2] := PointF(X + cs, Y + sn * Abs(Cos(Spin * 0.7)));
          pts[3] := PointF(X - sn, Y + cs * 0.5);
          c.alpha := Round(255 * Min(1, (1 - f) * 3));
          FTarget.FillPolyAntialias(pts, c);
        end;
      end;
      FMParts[n] := FMParts[i];
      Inc(n);
    end;
  SetLength(FMParts, n);
end;
