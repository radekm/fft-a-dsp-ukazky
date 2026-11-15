//! Vlastní widget grafu nad kreslicími funkcemi DVUI.
//!
//! Graf DVUI (`dvui.plot`) neumí přibližování, posun, legendu, propojené osy
//! ani čárkované čáry, proto máme vlastní. Napodobuje chování grafů z Rust
//! verze (egui_plot):
//!
//! - tažením myší se graf posouvá, kolečkem také (se Shiftem vodorovně),
//! - Ctrl + kolečko přibližuje a oddaluje kolem kurzoru,
//! - dvojklik vrátí automatický rozsah os,
//! - po najetí myší ukáže popisek se souřadnicemi; je-li kurzor blízko bodu
//!   některé křivky, ukáže přesné souřadnice tohoto bodu a název křivky.
//!
//! Použití (okamžitý režim, jako zbytek DVUI):
//!
//! ```zig
//! var p = plot.Plot.init(@src(), .{ .height = 200, .x_label = "čas [ms]", .y_label = "hodnota" });
//! p.line("signál", points, .{ .color = blue });
//! p.show();
//! ```
//!
//! Křivky si graf jen půjčuje: data musí žít aspoň do volání `show()`.
//! Všechny pomocné alokace jdou do arény aktuálního snímku DVUI.

const std = @import("std");
const dvui = @import("dvui");

const Color = dvui.Color;
const PhysicalPoint = dvui.Point.Physical;
const PhysicalRect = dvui.Rect.Physical;

const log = std.log.scoped(.plot);

/// Bod dat v souřadnicích grafu.
pub const Point = struct {
    x: f64,
    y: f64,
};

/// Rozsah jedné osy.
pub const Range = struct {
    min: f64,
    max: f64,

    pub fn span(self: Range) f64 {
        return self.max - self.min;
    }

    /// Rozsah rozšířený o hodnotu `value`.
    fn including(self: Range, value: f64) Range {
        return .{ .min = @min(self.min, value), .max = @max(self.max, value) };
    }

    /// Rozsah zvětšený o `fraction` své délky na každé straně.
    fn withMargin(self: Range, fraction: f64) Range {
        const margin = self.span() * fraction;
        return .{ .min = self.min - margin, .max = self.max + margin };
    }

    /// Rozsah přiblížený (`factor` < 1) nebo oddálený (`factor` > 1) kolem bodu `center`.
    fn zoomed(self: Range, center: f64, factor: f64) Range {
        return .{
            .min = center + (self.min - center) * factor,
            .max = center + (self.max - center) * factor,
        };
    }

    fn shifted(self: Range, delta: f64) Range {
        return .{ .min = self.min + delta, .max = self.max + delta };
    }

    /// Prázdný rozsah, do kterého se teprve přidávají hodnoty.
    const empty: Range = .{ .min = std.math.inf(f64), .max = -std.math.inf(f64) };

    fn isEmpty(self: Range) bool {
        return !(self.min <= self.max);
    }
};

/// Osa x sdílená několika grafy pod sebou: posun nebo přiblížení v jednom
/// grafu se projeví ve všech (v Rust verzi `link_axis`). Vlastní ji stav
/// záložky, aby přežila mezi snímky.
pub const LinkedAxis = struct {
    /// Rozsah, který nastavil uživatel; platí, jen když `auto` je false.
    range: Range = .{ .min = 0, .max = 1 },
    /// Automatický rozsah podle dat (dokud uživatel graf neposune).
    auto: bool = true,
};

/// Vzhled křivky.
pub const Style = struct {
    /// Barva; když chybí, vezme se další barva z výchozí palety.
    color: ?Color = null,
    /// Tloušťka čáry v logických pixelech.
    width: f32 = 1.5,
    /// Poloměr bodů (u stonků a bodů) v logických pixelech.
    radius: f32 = 2,
    /// Čárkovaná čára (u svislých a lomených čar).
    dashed: bool = false,
    /// Délka čárky a mezery v logických pixelech (u čárkované čáry).
    dash_length: f32 = 6,
    gap_length: f32 = 6,
};

/// Nastavení grafu.
pub const Options = struct {
    /// Výška celého grafu včetně popisků os v logických pixelech.
    height: f32,
    x_label: []const u8,
    /// Popisek svislé osy; prázdný = bez popisku (místo pro něj zůstane,
    /// aby byly grafy pod sebou zarovnané).
    y_label: []const u8,
    /// Názvy os v popisku u kurzoru, pokud se mají lišit od popisků os.
    hover_x_label: ?[]const u8 = null,
    hover_y_label: ?[]const u8 = null,
    /// Zobrazit legendu s názvy křivek v pravém horním rohu.
    legend: bool = false,
    /// Šířka sloupce s čísly na svislé ose. Stejná šířka u grafů pod sebou
    /// zajistí, že jsou zarovnané.
    y_axis_width: f32 = default_y_axis_width,
    /// Hodnoty, které musí automatický rozsah osy x vždy obsahovat.
    include_x: []const f64 = &.{},
    /// Hodnoty, které musí automatický rozsah osy y vždy obsahovat.
    include_y: []const f64 = &.{},
    /// Automatický rozsah osy x; když chybí, určí se z dat.
    default_x: ?Range = null,
    /// Automatický rozsah osy y; když chybí, určí se z dat.
    default_y: ?Range = null,
    /// Přibližná vzdálenost hlavních dílků na ose x v logických pixelech
    /// (u úzkých grafů menší, aby tam nebyla jen nula).
    x_tick_spacing: f32 = 80,
    /// Sdílená osa x s jinými grafy.
    linked_x: ?*LinkedAxis = null,
    /// Odliší více grafů vytvořených na stejném řádku zdrojového kódu.
    id_extra: usize = 0,
};

/// Stejná šířka svislé osy u všech grafů, aby byly grafy pod sebou zarovnané.
pub const default_y_axis_width: f32 = 48;

/// Výchozí barvy křivek, kterým nikdo barvu nepřidělil.
const palette = [_]Color{
    .{ .r = 30, .g = 110, .b = 220 },
    .{ .r = 205, .g = 135, .b = 0 },
    .{ .r = 40, .g = 150, .b = 60 },
    .{ .r = 210, .g = 40, .b = 40 },
    .{ .r = 130, .g = 70, .b = 200 },
};

/// Okraj kolem automatického rozsahu (5 % na každé straně, jako egui_plot).
const auto_margin = 0.05;
/// Jak blízko (v logických pixelech) musí být kurzor k bodu, aby ho popisek ukázal.
const hover_radius: f32 = 12;
/// Nejdelší pauza mezi dvěma kliknutími, která se ještě počítá jako dvojklik.
const double_click_ns: i128 = 400 * std.time.ns_per_ms;
/// Nejvíc bodů čáry v jednom volání `dvui.Path.stroke` (viz `drawSeries`).
const max_points_per_stroke = 2000;
/// Přiblížení na jeden pixel otočení kolečka (s Ctrl).
const zoom_per_wheel_pixel = 0.005;

const SeriesKind = enum {
    /// Lomená čára přes body.
    line,
    /// Body se svislou čárou („stonkem“) od nuly.
    stems,
    /// Samotné body bez čar.
    markers,
    /// Svislá čára přes celý graf.
    vertical_line,
};

/// Jedna křivka grafu.
const Series = struct {
    name: []const u8,
    kind: SeriesKind,
    /// Body křivky (u svislé čáry prázdné).
    points: []const Point,
    /// Poloha svislé čáry na ose x.
    x: f64 = 0,
    color: Color,
    style: Style,
};

/// Stav grafu, který přežívá mezi snímky (ukládá se přes `dvui.dataSet`).
const ViewState = struct {
    x: Range = .{ .min = 0, .max = 1 },
    y: Range = .{ .min = 0, .max = 1 },
    auto_x: bool = true,
    auto_y: bool = true,
    /// Čas posledního stisku tlačítka (pro rozpoznání dvojkliku).
    last_press_ns: i128 = 0,
};

/// Graf jednoho snímku. Vzniká voláním `init`, křivky se přidají metodami
/// `line`, `stems` a `verticalLine` a vše se nakreslí voláním `show`.
pub const Plot = struct {
    src: std.builtin.SourceLocation,
    options: Options,
    series: std.ArrayList(Series) = .empty,
    /// Kolik barev z palety už se přidělilo.
    next_palette_index: usize = 0,

    pub fn init(src: std.builtin.SourceLocation, options: Options) Plot {
        return .{ .src = src, .options = options };
    }

    /// Lomená čára přes body.
    pub fn line(self: *Plot, name: []const u8, points: []const Point, style: Style) void {
        self.add(.{ .name = name, .kind = .line, .points = points, .color = self.colorFor(style), .style = style });
    }

    /// Body se svislými čarami od nuly (jako „stonky“ v egui_plot).
    pub fn stems(self: *Plot, name: []const u8, points: []const Point, style: Style) void {
        self.add(.{ .name = name, .kind = .stems, .points = points, .color = self.colorFor(style), .style = style });
    }

    /// Samotné body (puntíky) bez čar.
    pub fn markers(self: *Plot, name: []const u8, points: []const Point, style: Style) void {
        self.add(.{ .name = name, .kind = .markers, .points = points, .color = self.colorFor(style), .style = style });
    }

    /// Svislá čára přes celou výšku grafu na souřadnici `x`.
    pub fn verticalLine(self: *Plot, name: []const u8, x: f64, style: Style) void {
        self.add(.{ .name = name, .kind = .vertical_line, .points = &.{}, .x = x, .color = self.colorFor(style), .style = style });
    }

    fn colorFor(self: *Plot, style: Style) Color {
        if (style.color) |color| return color;
        const color = palette[self.next_palette_index % palette.len];
        self.next_palette_index += 1;
        return color;
    }

    fn add(self: *Plot, series: Series) void {
        // Selhání alokace v aréně snímku jen zaznamenáme; graf bez jedné
        // křivky je lepší než pád programu.
        self.series.append(dvui.currentWindow().arena(), series) catch |err| {
            log.warn("cannot add series name={s} error={s}", .{ series.name, @errorName(err) });
        };
    }

    /// Rozmístí, obslouží myš a nakreslí celý graf.
    pub fn show(self: *Plot) void {
        const theme = dvui.themeGet();
        const font = theme.font_body;
        const tick_font = font.larger(-2);

        var box = dvui.box(self.src, .{}, .{
            .id_extra = self.options.id_extra,
            .expand = .horizontal,
            .min_size_content = .{ .h = self.options.height },
        });
        defer box.deinit();

        const content = box.data().contentRectScale();
        const scale = content.s;
        const line_height = font.lineHeight() * scale;
        const tick_line_height = tick_font.lineHeight() * scale;

        // Rozvržení: vlevo svislý popisek osy y a čísla osy y, dole čísla
        // osy x a popisek osy x, uprostřed kreslicí plocha s daty.
        const left = line_height + 4 * scale + self.options.y_axis_width * scale;
        const bottom = tick_line_height + line_height + 6 * scale;
        const data_rect: PhysicalRect = .{
            .x = content.r.x + left,
            .y = content.r.y + 4 * scale,
            .w = @max(1, content.r.w - left - 12 * scale),
            .h = @max(1, content.r.h - bottom - 4 * scale),
        };

        const id = box.data().id;
        var view = dvui.dataGet(null, id, "view", ViewState) orelse ViewState{};
        self.updateAutoRanges(&view);
        var x_range = self.currentXRange(view);
        var y_range = view.y;

        self.handleEvents(box.data(), data_rect, &view, &x_range, &y_range);
        dvui.dataSet(null, id, "view", view);

        const transform: Transform = .{ .rect = data_rect, .x = x_range, .y = y_range };

        // Pozadí a rámeček kreslicí plochy.
        data_rect.fill(.{}, .{ .color = .{ .color = theme.fill.opacity(0.6) } });
        drawGrid(transform, tick_font, scale, theme.text, self.options.x_tick_spacing);

        // Křivky se kreslí jen dovnitř kreslicí plochy.
        const previous_clip = dvui.clip(data_rect);
        for (self.series.items) |series| drawSeries(transform, series, scale);
        dvui.clipSet(previous_clip);

        data_rect.stroke(.{}, .{ .thickness = 1, .color = .{ .color = theme.border } });
        drawAxisLabels(self.options, content.r, data_rect, font, scale, theme.text);
        if (self.options.legend) self.drawLegend(data_rect, font, scale, theme);
        self.drawHover(box.data(), transform, font, scale, theme);
    }

    /// Spočítá automatický rozsah os z dat a uloží ho do stavu, pokud ho
    /// uživatel nezměnil posunem nebo přiblížením.
    fn updateAutoRanges(self: *const Plot, view: *ViewState) void {
        var x_data = Range.empty;
        var y_data = Range.empty;
        for (self.series.items) |series| {
            switch (series.kind) {
                .vertical_line => x_data = x_data.including(series.x),
                .line, .stems, .markers => for (series.points) |point| {
                    if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y)) continue;
                    x_data = x_data.including(point.x);
                    y_data = y_data.including(point.y);
                },
            }
            // Stonky začínají v nule, ta tedy musí být vidět.
            if (series.kind == .stems and series.points.len > 0) y_data = y_data.including(0);
        }
        for (self.options.include_x) |value| x_data = x_data.including(value);
        for (self.options.include_y) |value| y_data = y_data.including(value);

        // U sdílené osy rozhoduje o automatickém rozsahu sdílený příznak,
        // aby se dvojklik v jednom grafu projevil ve všech.
        const auto_x = if (self.options.linked_x) |linked| linked.auto else view.auto_x;
        if (auto_x) {
            view.x = self.options.default_x orelse autoRange(x_data);
            view.auto_x = true;
        }
        if (view.auto_y) {
            view.y = self.options.default_y orelse autoRange(y_data);
        }
    }

    /// Rozsah osy x, který platí v tomto snímku (vlastní, nebo sdílený).
    fn currentXRange(self: *const Plot, view: ViewState) Range {
        if (self.options.linked_x) |linked| {
            if (!linked.auto) return linked.range;
        }
        return view.x;
    }

    /// Obslouží myš: tažení, kolečko a dvojklik.
    fn handleEvents(
        self: *const Plot,
        widget: *dvui.WidgetData,
        data_rect: PhysicalRect,
        view: *ViewState,
        x_range: *Range,
        y_range: *Range,
    ) void {
        var x_changed = false;
        var y_changed = false;

        for (dvui.events()) |*event| {
            if (!dvui.eventMatchSimple(event, widget)) continue;
            const mouse = switch (event.evt) {
                .mouse => |mouse| mouse,
                else => continue,
            };
            switch (mouse.action) {
                .press => {
                    if (!mouse.button.pointer() or !data_rect.contains(mouse.p)) continue;
                    event.handle(@src(), widget);
                    const now = dvui.frameTimeNS();
                    if (now - view.last_press_ns < double_click_ns) {
                        // Dvojklik: zpět na automatický rozsah.
                        view.auto_x = true;
                        view.auto_y = true;
                        if (self.options.linked_x) |linked| linked.auto = true;
                        view.last_press_ns = 0;
                        dvui.refresh(null, @src(), widget.id);
                        continue;
                    }
                    view.last_press_ns = now;
                    dvui.captureMouse(widget, event.num);
                    dvui.dragPreStart(mouse.button, mouse.p, .{ .cursor = .hand });
                },
                .release => {
                    if (!mouse.button.pointer() or !dvui.captured(widget.id)) continue;
                    event.handle(@src(), widget);
                    dvui.captureMouse(null, event.num);
                    dvui.dragEnd(mouse.button);
                },
                .motion => {
                    if (!dvui.captured(widget.id)) continue;
                    event.handle(@src(), widget);
                    if (dvui.dragging(mouse, null)) |delta| {
                        // Posun dat o tolik, o kolik se pohnula myš.
                        x_range.* = x_range.shifted(-delta.x / data_rect.w * x_range.span());
                        y_range.* = y_range.shifted(delta.y / data_rect.h * y_range.span());
                        x_changed = true;
                        y_changed = true;
                    }
                },
                .wheel_y, .wheel_x => {
                    if (!data_rect.contains(mouse.p)) continue;
                    event.handle(@src(), widget);
                    const amount: f64 = switch (mouse.action) {
                        .wheel_y => |value| value,
                        .wheel_x => |value| value,
                        else => unreachable,
                    };
                    if (mouse.mod.control()) {
                        // Přiblížení kolem bodu pod kurzorem.
                        const factor = @exp(-amount * zoom_per_wheel_pixel);
                        const transform: Transform = .{ .rect = data_rect, .x = x_range.*, .y = y_range.* };
                        const center = transform.toData(mouse.p);
                        x_range.* = x_range.zoomed(center.x, factor);
                        y_range.* = y_range.zoomed(center.y, factor);
                        x_changed = true;
                        y_changed = true;
                    } else if (mouse.mod.shift() or mouse.action == .wheel_x) {
                        x_range.* = x_range.shifted(-amount / data_rect.w * x_range.span());
                        x_changed = true;
                    } else {
                        y_range.* = y_range.shifted(amount / data_rect.h * y_range.span());
                        y_changed = true;
                    }
                },
                else => {},
            }
        }

        if (x_changed or y_changed) {
            // Grafy propojené osou se už mohly v tomto snímku nakreslit
            // se starým rozsahem; další snímek je srovná.
            dvui.refresh(null, @src(), widget.id);
        }
        if (x_changed) {
            view.auto_x = false;
            view.x = x_range.*;
            if (self.options.linked_x) |linked| {
                linked.auto = false;
                linked.range = x_range.*;
            }
        }
        if (y_changed) {
            view.auto_y = false;
            view.y = y_range.*;
        }
    }

    /// Legenda: názvy křivek s barevnou tečkou v pravém horním rohu.
    fn drawLegend(self: *const Plot, data_rect: PhysicalRect, font: dvui.Font, scale: f32, theme: dvui.Theme) void {
        const line_height = font.lineHeight() * scale;
        const padding = 6 * scale;
        const dot_radius = 4 * scale;

        var names: std.ArrayList(*const Series) = .empty;
        var max_width: f32 = 0;
        const arena = dvui.currentWindow().arena();
        outer: for (self.series.items) |*series| {
            if (series.name.len == 0) continue;
            // Stejný název se v legendě ukáže jen jednou.
            for (names.items) |seen| {
                if (std.mem.eql(u8, seen.name, series.name)) continue :outer;
            }
            names.append(arena, series) catch return;
            max_width = @max(max_width, font.textSize(series.name).w * scale);
        }
        if (names.items.len == 0) return;

        const width = max_width + 3 * padding + 2 * dot_radius;
        const height = @as(f32, @floatFromInt(names.items.len)) * line_height + 2 * padding;
        const legend_rect: PhysicalRect = .{
            .x = data_rect.x + data_rect.w - width - padding,
            .y = data_rect.y + padding,
            .w = width,
            .h = height,
        };
        const corners: dvui.CornerRect.Physical = .all(4 * scale);
        legend_rect.fill(corners, .{ .color = .{ .color = theme.fill.opacity(0.85) } });
        legend_rect.stroke(corners, .{ .thickness = 1, .color = .{ .color = theme.border } });

        for (names.items, 0..) |series, index| {
            const row_y = legend_rect.y + padding + @as(f32, @floatFromInt(index)) * line_height;
            const text_width = font.textSize(series.name).w * scale;
            drawText(font, series.name, .{
                .x = legend_rect.x + legend_rect.w - 2 * padding - 2 * dot_radius - text_width,
                .y = row_y,
            }, scale, theme.text);
            fillCircle(.{
                .x = legend_rect.x + legend_rect.w - padding - dot_radius,
                .y = row_y + line_height / 2,
            }, dot_radius, series.color);
        }
    }

    /// Popisek se souřadnicemi u kurzoru a zaměřovací kříž.
    fn drawHover(self: *const Plot, widget: *dvui.WidgetData, transform: Transform, font: dvui.Font, scale: f32, theme: dvui.Theme) void {
        // Popisek jen tehdy, když je myš nad grafem a nic jiného ji nedrží.
        if (!dvui.captured(widget.id) and dvui.captureMouseGet(null) != null) return;
        const mouse = dvui.currentWindow().mouse_pt;
        if (!transform.rect.contains(mouse)) return;

        dvui.cursorSet(.crosshair);

        // Nejbližší bod některé křivky.
        var nearest: ?struct { series: *const Series, point: Point } = null;
        var nearest_distance = hover_radius * scale;
        for (self.series.items) |*series| {
            if (series.kind == .vertical_line) continue;
            for (series.points) |point| {
                if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y)) continue;
                const screen = transform.toScreen(point);
                const distance = std.math.hypot(screen.x - mouse.x, screen.y - mouse.y);
                // Při stejné vzdálenosti vyhraje později přidaná křivka, protože
                // je nakreslená navrchu (např. vzorky přes spojitý signál).
                if (distance <= nearest_distance) {
                    nearest_distance = distance;
                    nearest = .{ .series = series, .point = point };
                }
            }
        }

        const crosshair_color = theme.text.opacity(0.35);
        const target: PhysicalPoint = if (nearest) |found| transform.toScreen(found.point) else mouse;
        strokeLine(.{ .x = target.x, .y = transform.rect.y }, .{ .x = target.x, .y = transform.rect.y + transform.rect.h }, 1, crosshair_color);
        strokeLine(.{ .x = transform.rect.x, .y = target.y }, .{ .x = transform.rect.x + transform.rect.w, .y = target.y }, 1, crosshair_color);

        const arena = dvui.currentWindow().arena();
        const x_name = self.options.hover_x_label orelse self.options.x_label;
        const y_name = self.options.hover_y_label orelse self.options.y_label;
        var x_buffer: [32]u8 = undefined;
        var y_buffer: [32]u8 = undefined;
        const text = blk: {
            if (nearest) |found| {
                fillCircle(target, (found.series.style.radius + 2) * scale, theme.text);
                break :blk std.fmt.allocPrint(arena, "{s}\n{s}: {s}\n{s}: {s}", .{
                    found.series.name,
                    x_name,
                    formatCoordinate(&x_buffer, found.point.x),
                    y_name,
                    formatCoordinate(&y_buffer, found.point.y),
                }) catch return;
            }
            const position = transform.toData(mouse);
            break :blk std.fmt.allocPrint(arena, "{s}: {s}\n{s}: {s}", .{
                x_name,
                formatCoordinate(&x_buffer, position.x),
                y_name,
                formatCoordinate(&y_buffer, position.y),
            }) catch return;
        };

        // Rámeček popisku vpravo dole od kurzoru; u okraje grafu se přesune
        // na druhou stranu, aby nevyčníval.
        const line_height = font.lineHeight() * scale;
        const padding = 6 * scale;
        var line_count: f32 = 0;
        var max_width: f32 = 0;
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |text_line| {
            line_count += 1;
            max_width = @max(max_width, font.textSize(text_line).w * scale);
        }
        var box_rect: PhysicalRect = .{
            .x = mouse.x + 14 * scale,
            .y = mouse.y + 14 * scale,
            .w = max_width + 2 * padding,
            .h = line_count * line_height + 2 * padding,
        };
        if (box_rect.x + box_rect.w > transform.rect.x + transform.rect.w) box_rect.x = mouse.x - 14 * scale - box_rect.w;
        if (box_rect.y + box_rect.h > transform.rect.y + transform.rect.h) box_rect.y = mouse.y - 14 * scale - box_rect.h;

        const corners: dvui.CornerRect.Physical = .all(5 * scale);
        box_rect.fill(corners, .{ .color = .{ .color = theme.fill } });
        box_rect.stroke(corners, .{ .thickness = 1, .color = .{ .color = theme.border } });
        lines = std.mem.splitScalar(u8, text, '\n');
        var row: f32 = 0;
        while (lines.next()) |text_line| : (row += 1) {
            drawText(font, text_line, .{ .x = box_rect.x + padding, .y = box_rect.y + padding + row * line_height }, scale, theme.text);
        }
    }
};

/// Pole bodů pro graf v aréně snímku (DVUI ho na konci snímku zahodí).
/// Při nedostatku paměti vrátí null a graf se v tomto snímku nenakreslí.
pub fn allocPoints(count: usize) ?[]Point {
    return dvui.currentWindow().arena().alloc(Point, count) catch |err| {
        log.warn("cannot allocate plot points count={d} error={s}", .{ count, @errorName(err) });
        return null;
    };
}

/// Automatický rozsah z rozsahu dat: přidá okraj a ošetří prázdná data
/// a data s jedinou hodnotou.
fn autoRange(data: Range) Range {
    if (data.isEmpty()) return .{ .min = 0, .max = 1 };
    if (data.span() == 0) return .{ .min = data.min - 1, .max = data.max + 1 };
    return data.withMargin(auto_margin);
}

/// Převod mezi souřadnicemi dat a pixely obrazovky.
const Transform = struct {
    rect: PhysicalRect,
    x: Range,
    y: Range,

    fn toScreen(self: Transform, point: Point) PhysicalPoint {
        const fx = (point.x - self.x.min) / self.x.span();
        const fy = (point.y - self.y.min) / self.y.span();
        return .{
            .x = self.rect.x + @as(f32, @floatCast(fx)) * self.rect.w,
            // Osa y míří na obrazovce dolů, v grafu nahoru.
            .y = self.rect.y + self.rect.h - @as(f32, @floatCast(fy)) * self.rect.h,
        };
    }

    fn toData(self: Transform, screen: PhysicalPoint) Point {
        const fx: f64 = (screen.x - self.rect.x) / self.rect.w;
        const fy: f64 = (self.rect.y + self.rect.h - screen.y) / self.rect.h;
        return .{ .x = self.x.min + fx * self.x.span(), .y = self.y.min + fy * self.y.span() };
    }
};

/// Nakreslí jednu křivku.
fn drawSeries(transform: Transform, series: Series, scale: f32) void {
    const thickness = series.style.width * scale;
    switch (series.kind) {
        .line => {
            const arena = dvui.currentWindow().arena();
            const screen_points = arena.alloc(PhysicalPoint, series.points.len) catch return;
            var count: usize = 0;
            for (series.points) |point| {
                if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y)) continue;
                screen_points[count] = transform.toScreen(point);
                count += 1;
            }
            // DVUI čísluje vrcholy jednoho tahu typem u16 (nejvýš 65 535
            // vrcholů, na bod čáry jich padne několik). Dlouhou čáru proto
            // kreslíme po úsecích; sousední úseky sdílejí jeden bod, aby
            // čára nebyla přerušená.
            if (series.style.dashed) {
                strokeDashed(screen_points[0..count], series.style, scale, series.color);
                return;
            }
            var start: usize = 0;
            while (start + 1 < count) {
                const end = @min(start + max_points_per_stroke, count);
                dvui.Path.stroke(.{ .points = screen_points[start..end] }, .{
                    .thickness = thickness,
                    .color = .{ .color = series.color },
                });
                start = end - 1;
            }
        },
        .stems => {
            const zero_y = transform.toScreen(.{ .x = 0, .y = 0 }).y;
            for (series.points) |point| {
                if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y)) continue;
                const top = transform.toScreen(point);
                strokeLine(.{ .x = top.x, .y = zero_y }, top, thickness * 0.7, series.color);
                fillCircle(top, series.style.radius * scale, series.color);
            }
        },
        .markers => {
            for (series.points) |point| {
                if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y)) continue;
                fillCircle(transform.toScreen(point), series.style.radius * scale, series.color);
            }
        },
        .vertical_line => {
            const x = transform.toScreen(.{ .x = series.x, .y = 0 }).x;
            const top = transform.rect.y;
            const bottom = transform.rect.y + transform.rect.h;
            if (!series.style.dashed) {
                strokeLine(.{ .x = x, .y = top }, .{ .x = x, .y = bottom }, thickness, series.color);
                return;
            }
            // Čárkovaná čára: střídání čárek a mezer.
            const dash = series.style.dash_length * scale;
            const gap = series.style.gap_length * scale;
            var y = top;
            while (y < bottom) : (y += dash + gap) {
                strokeLine(.{ .x = x, .y = y }, .{ .x = x, .y = @min(y + dash, bottom) }, thickness, series.color);
            }
        },
    }
}

/// Mřížka a čísla na osách.
fn drawGrid(transform: Transform, font: dvui.Font, scale: f32, text_color: Color, x_tick_spacing: f32) void {
    const rect = transform.rect;
    const minor_color = text_color.opacity(0.06);
    const major_color = text_color.opacity(0.16);
    const zero_color = text_color.opacity(0.45);
    const line_height = font.lineHeight() * scale;
    var buffer: [32]u8 = undefined;

    // Svislé čáry a čísla osy x: dílek zhruba na každých `x_tick_spacing` pixelů.
    const x_ticks = Ticks.init(transform.x, rect.w / scale / x_tick_spacing);
    var x_tick = x_ticks.firstMinor();
    while (x_tick <= transform.x.max) : (x_tick += x_ticks.minor) {
        const px = transform.toScreen(.{ .x = x_tick, .y = 0 }).x;
        const major = x_ticks.isMajor(x_tick);
        const color = if (x_ticks.isZero(x_tick)) zero_color else if (major) major_color else minor_color;
        strokeLine(.{ .x = px, .y = rect.y }, .{ .x = px, .y = rect.y + rect.h }, 1, color);
        if (major) {
            const label = x_ticks.format(&buffer, x_tick);
            const width = font.textSize(label).w * scale;
            drawText(font, label, .{ .x = px - width / 2, .y = rect.y + rect.h + 2 * scale }, scale, text_color);
        }
    }

    // Vodorovné čáry a čísla osy y: dílek zhruba na každých 28 pixelů.
    const y_ticks = Ticks.init(transform.y, rect.h / scale / 28);
    var y_tick = y_ticks.firstMinor();
    while (y_tick <= transform.y.max) : (y_tick += y_ticks.minor) {
        const py = transform.toScreen(.{ .x = 0, .y = y_tick }).y;
        const major = y_ticks.isMajor(y_tick);
        const color = if (y_ticks.isZero(y_tick)) zero_color else if (major) major_color else minor_color;
        strokeLine(.{ .x = rect.x, .y = py }, .{ .x = rect.x + rect.w, .y = py }, 1, color);
        if (major) {
            const label = y_ticks.format(&buffer, y_tick);
            const width = font.textSize(label).w * scale;
            drawText(font, label, .{ .x = rect.x - width - 4 * scale, .y = py - line_height / 2 }, scale, text_color);
        }
    }
}

/// Dílky jedné osy: „hezký“ krok (1, 2 nebo 5 × 10ⁿ) a jemnější krok mřížky.
const Ticks = struct {
    major: f64,
    minor: f64,
    /// Počet desetinných míst v číslech na ose.
    decimals: usize,
    range: Range,

    /// `target_count` je přibližný počet hlavních dílků, který se vejde.
    fn init(range: Range, target_count: f32) Ticks {
        const raw_step = range.span() / @max(1, target_count);
        const magnitude = std.math.pow(f64, 10, @floor(@log10(raw_step)));
        const normalized = raw_step / magnitude;
        // Hlavní krok zaokrouhlíme nahoru na 1, 2 nebo 5 krát mocnina deseti
        // a jemný krok zvolíme tak, aby hlavní dílek dělil na 5 (u dvojky na 4) částí.
        const base: f64, const parts: f64 = if (normalized <= 1)
            .{ 1, 5 }
        else if (normalized <= 2)
            .{ 2, 4 }
        else if (normalized <= 5)
            .{ 5, 5 }
        else
            .{ 10, 5 };
        const major = base * magnitude;
        const decimals: usize = if (major >= 1) 0 else @intFromFloat(@ceil(-@log10(major) - 1e-9));
        return .{ .major = major, .minor = major / parts, .decimals = decimals, .range = range };
    }

    fn firstMinor(self: Ticks) f64 {
        return @ceil(self.range.min / self.minor) * self.minor;
    }

    fn isMajor(self: Ticks, value: f64) bool {
        const ratio = value / self.major;
        return @abs(ratio - @round(ratio)) < 1e-6;
    }

    fn isZero(self: Ticks, value: f64) bool {
        return @abs(value) < self.minor * 1e-6;
    }

    fn format(self: Ticks, buffer: []u8, value: f64) []const u8 {
        // Hodnota těsně kolem nuly by se vypsala jako „-0“.
        const clean = if (self.isZero(value)) 0 else value;
        return std.fmt.bufPrint(buffer, "{[value]d:.[decimals]}", .{ .value = clean, .decimals = self.decimals }) catch "?";
    }
};

/// Popisky os: vodorovný pod grafem, svislý (otočený) vlevo.
fn drawAxisLabels(options: Options, content: PhysicalRect, data_rect: PhysicalRect, font: dvui.Font, scale: f32, color: Color) void {
    const line_height = font.lineHeight() * scale;

    const x_width = font.textSize(options.x_label).w * scale;
    drawText(font, options.x_label, .{
        .x = data_rect.x + data_rect.w / 2 - x_width / 2,
        .y = content.y + content.h - line_height,
    }, scale, color);

    if (options.y_label.len == 0) return;
    // Text otočený o 270° po směru hodinových ručiček se čte zdola nahoru.
    const y_width = font.textSize(options.y_label).w * scale;
    const position: PhysicalPoint = .{
        .x = content.x,
        .y = data_rect.y + data_rect.h / 2 + y_width / 2,
    };
    dvui.renderText(.{
        .font = font,
        .text = options.y_label,
        .rs = .{ .r = PhysicalRect.fromPoint(position).toSize(.{ .w = y_width, .h = line_height }), .s = scale },
        .color = color,
        .rotation = std.math.pi * 1.5,
    }) catch |err| log.warn("cannot draw text error={s}", .{@errorName(err)});
}

/// Formátuje souřadnici v popisku: nejvýš 4 desetinná místa bez zbytečných
/// nul na konci (25.0000 → „25“, 0.70711 → „0.7071“).
pub fn formatCoordinate(buffer: []u8, value: f64) []const u8 {
    const text = std.fmt.bufPrint(buffer, "{d:.4}", .{value}) catch return "?";
    var trimmed = std.mem.trimEnd(u8, text, "0");
    trimmed = std.mem.trimEnd(u8, trimmed, ".");
    // Malé záporné číslo by se zaokrouhlilo na „-0“.
    if (std.mem.eql(u8, trimmed, "-0")) return "0";
    return trimmed;
}

fn drawText(font: dvui.Font, text: []const u8, top_left: PhysicalPoint, scale: f32, color: Color) void {
    const size = font.textSize(text);
    dvui.renderText(.{
        .font = font,
        .text = text,
        .rs = .{ .r = PhysicalRect.fromPoint(top_left).toSize(.{ .w = size.w * scale, .h = size.h * scale }), .s = scale },
        .color = color,
    }) catch |err| log.warn("cannot draw text error={s}", .{@errorName(err)});
}

/// Čárkovaná lomená čára: podél čáry se střídají čárky a mezery, vzor
/// navazuje přes zlomy čáry.
fn strokeDashed(points: []const PhysicalPoint, style: Style, scale: f32, color: Color) void {
    const dash = style.dash_length * scale;
    const gap = style.gap_length * scale;
    const thickness = style.width * scale;
    // Kde ve vzoru „čárka + mezera“ právě jsme (0 až dash + gap).
    var phase: f32 = 0;
    for (points[0 .. points.len - 1], points[1..]) |from, to| {
        const length = std.math.hypot(to.x - from.x, to.y - from.y);
        if (length == 0) continue;
        var position: f32 = 0;
        while (position < length) {
            const in_dash = phase < dash;
            const remaining_in_part = if (in_dash) dash - phase else dash + gap - phase;
            const step = @min(remaining_in_part, length - position);
            if (in_dash) {
                const a = position / length;
                const b = (position + step) / length;
                strokeLine(
                    .{ .x = from.x + (to.x - from.x) * a, .y = from.y + (to.y - from.y) * a },
                    .{ .x = from.x + (to.x - from.x) * b, .y = from.y + (to.y - from.y) * b },
                    thickness,
                    color,
                );
            }
            position += step;
            phase = @mod(phase + step, dash + gap);
        }
    }
}

fn strokeLine(from: PhysicalPoint, to: PhysicalPoint, thickness: f32, color: Color) void {
    dvui.Path.stroke(.{ .points = &.{ from, to } }, .{ .thickness = thickness, .color = .{ .color = color } });
}

fn fillCircle(center: PhysicalPoint, radius: f32, color: Color) void {
    var builder = dvui.Path.Builder.init(dvui.currentWindow().lifo());
    defer builder.deinit();
    builder.addArc(center, radius, std.math.pi * 2, 0, true);
    builder.build().fillConvex(.{ .color = .{ .color = color } });
}

test "format coordinate trims zeros" {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("25", formatCoordinate(&buffer, 25));
    try std.testing.expectEqualStrings("0.7071", formatCoordinate(&buffer, 0.70711));
    try std.testing.expectEqualStrings("0", formatCoordinate(&buffer, -0.00001));
    try std.testing.expectEqualStrings("-1.5", formatCoordinate(&buffer, -1.5));
}

test "ticks use nice steps" {
    const ticks = Ticks.init(.{ .min = 0, .max = 63 }, 8);
    try std.testing.expectEqual(10.0, ticks.major);
    try std.testing.expectEqual(2.0, ticks.minor);
    const small = Ticks.init(.{ .min = -1.05, .max = 1.05 }, 5);
    try std.testing.expectEqual(0.5, small.major);
    try std.testing.expectEqual(1, small.decimals);
}
