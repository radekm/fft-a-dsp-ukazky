//! Věci společné pro více záložek: ovládací prvky v podobě, na kterou jsme
//! zvyklí z Rust verze (egui), a společné texty.

const std = @import("std");
const dvui = @import("dvui");
const dsp = @import("dsp");

const Component = dsp.signal.Component;
const Waveform = dsp.signal.Waveform;
const WindowKind = dsp.window.WindowKind;

/// Šířka levého panelu s ovládáním. V Rust verzi 300 px; písmo Inter je
/// širší než výchozí písmo egui, proto je panel o něco širší.
pub const controls_width: f32 = 320;

/// Šířka posuvníku v logických pixelech.
const slider_width: f32 = 90;
/// Šířka políčka s číslem vedle posuvníku.
const number_width: f32 = 52;

/// Největší amplituda, kterou lze nastavit u složky signálu.
const max_component_amplitude = 2.0;

/// Nápověda k ovládání grafů, stejná ve všech záložkách.
pub const plot_help = "Grafy: tažením posun, kolečkem s Ctrl zvětšení, dvojklik obnoví zobrazení.";

/// Svislá osa amplitudového spektra.
pub const AmplitudeScale = enum { linear, decibel };

/// Nastavení posuvníku.
pub const SliderOptions = struct {
    min: f64,
    max: f64,
    /// Zaokrouhlení hodnoty při tažení posuvníkem (0 = bez zaokrouhlení).
    /// Do políčka lze napsat i hodnotu mezi kroky.
    step: f64 = 0,
    /// Logaritmická stupnice (pro rozsahy přes několik řádů, např. fs).
    logarithmic: bool = false,
    /// Jednotka za číslem, např. „Hz“.
    suffix: []const u8 = "",
    id_extra: usize = 0,
};

/// Posuvník, políčko s číslem (dá se do něj psát) a popisek – obdoba
/// `egui::Slider` z Rust verze. Vrací true, pokud se hodnota změnila.
pub fn slider(src: std.builtin.SourceLocation, label: []const u8, value: *f64, options: SliderOptions) bool {
    var line_box = dvui.box(src, .{ .dir = .horizontal }, .{ .id_extra = options.id_extra, .expand = .horizontal });
    defer line_box.deinit();

    var changed = false;

    // Posuvník DVUI pracuje se zlomkem 0 až 1; převedeme na naši stupnici.
    var fraction: f32 = @floatCast(std.math.clamp(toFraction(value.*, options), 0, 1));
    if (dvui.slider(@src(), .{ .fraction = &fraction }, .{
        .min_size_content = .{ .w = slider_width, .h = 18 },
        .gravity_y = 0.5,
    })) {
        var new_value = fromFraction(fraction, options);
        if (options.step > 0) new_value = roundToStep(new_value, options.step);
        value.* = std.math.clamp(new_value, options.min, options.max);
        changed = true;
    }

    const result = dvui.textEntryNumber(@src(), f64, .{
        .value = value,
        .min = options.min,
        .max = options.max,
    }, .{
        .min_size_content = .{ .w = number_width },
        .max_size_content = .width(number_width),
        .gravity_y = 0.5,
        .padding = .{ .x = 4, .y = 2, .w = 4, .h = 2 },
        .margin = .{ .x = 2, .y = 1, .w = 2, .h = 1 },
    });
    if (result.changed) changed = true;

    if (options.suffix.len > 0) {
        dvui.labelNoFmt(@src(), options.suffix, .{}, .{ .gravity_y = 0.5 });
    }
    dvui.labelNoFmt(@src(), label, .{}, .{ .gravity_y = 0.5 });
    return changed;
}

/// Zaokrouhlí hodnotu na násobek kroku. U kroků menších než 1 dělíme
/// převrácenou hodnotou (37.29 = 3729 / 100), aby výsledek byl nejbližší
/// číslo k desetinnému zápisu a v políčku se neukázalo 37.290000000000006.
fn roundToStep(value: f64, step: f64) f64 {
    if (step < 1) {
        const inverse = @round(1 / step);
        return @round(value * inverse) / inverse;
    }
    return @round(value / step) * step;
}

fn toFraction(value: f64, options: SliderOptions) f64 {
    if (options.logarithmic) return @log(value / options.min) / @log(options.max / options.min);
    return (value - options.min) / (options.max - options.min);
}

fn fromFraction(fraction: f32, options: SliderOptions) f64 {
    const f: f64 = fraction;
    if (options.logarithmic) return options.min * std.math.pow(f64, options.max / options.min, f);
    return options.min + f * (options.max - options.min);
}

/// Nadpis oddílu v ovládacím panelu (obdoba `ui.heading`).
pub fn heading(src: std.builtin.SourceLocation, title: []const u8) void {
    dvui.labelNoFmt(src, title, .{}, .{ .font = dvui.themeGet().font_title, .padding = .{ .y = 4, .h = 2 } });
}

/// Méně výrazný vysvětlující text, zalomený do šířky panelu (obdoba `ui.weak`).
pub fn weak(src: std.builtin.SourceLocation, message: []const u8) void {
    var layout = dvui.textLayout(src, .{}, .{ .expand = .horizontal, .background = false, .padding = .{ .x = 2, .y = 2, .w = 2, .h = 2 } });
    defer layout.deinit();
    layout.addText(message, .{ .color_text = .{ .color = dvui.themeGet().text.opacity(0.6) } });
}

/// Běžný text s formátováním, zalomený do šířky panelu
/// (obdoba `ui.label(format!(...))`).
pub fn text(src: std.builtin.SourceLocation, comptime format: []const u8, args: anytype) void {
    const message = std.fmt.allocPrint(dvui.currentWindow().arena(), format, args) catch format;
    var layout = dvui.textLayout(src, .{}, .{ .expand = .horizontal, .background = false, .padding = .{ .x = 2, .y = 1, .w = 2, .h = 1 } });
    defer layout.deinit();
    layout.addText(message, .{});
}

/// Krátký popisek na jednom řádku, např. před přepínači.
pub fn inlineText(src: std.builtin.SourceLocation, message: []const u8) void {
    dvui.labelNoFmt(src, message, .{}, .{ .gravity_y = 0.5, .padding = .{ .x = 2, .y = 1, .w = 2, .h = 1 } });
}

/// Řádek ovládacích prvků, který při nedostatku místa pokračuje na dalším
/// řádku (obdoba `ui.horizontal_wrapped`).
pub fn row(src: std.builtin.SourceLocation) *dvui.FlexBoxWidget {
    return dvui.flexbox(src, .{ .justify_content = .start }, .{ .expand = .horizontal });
}

/// Vodorovná dělicí čára mezi oddíly.
pub fn separator(src: std.builtin.SourceLocation) void {
    _ = dvui.separator(src, .{ .expand = .horizontal, .margin = .{ .y = 6, .h = 6 } });
}

/// Přepínač (radio button), který při kliknutí nastaví `target` na `value`
/// (obdoba `ui.radio_value`). Vrací true při změně.
pub fn radioValue(src: std.builtin.SourceLocation, comptime T: type, target: *T, value: T, label: []const u8) bool {
    if (dvui.radio(src, target.* == value, label, .{ .id_extra = @backingInt(value) }) and target.* != value) {
        target.* = value;
        return true;
    }
    return false;
}

/// Rozbalovací seznam hodnot výčtového typu s českými názvy.
/// `names` musí mít stejné pořadí jako `values`.
pub fn dropdown(
    src: std.builtin.SourceLocation,
    comptime T: type,
    target: *T,
    values: []const T,
    names: []const []const u8,
    opts: dvui.Options,
) bool {
    var index: usize = 0;
    for (values, 0..) |value, i| {
        if (value == target.*) index = i;
    }
    if (dvui.dropdown(src, names, .{ .choice = &index }, .{}, opts) and values[index] != target.*) {
        target.* = values[index];
        return true;
    }
    return false;
}

/// Ovládání jedné složky signálu v rámečku. Vrací true, pokud uživatel
/// klikl na „Odebrat“.
///
/// `frequency_step` je krok posuvníku frekvence; 0 znamená jemný posuvník
/// (zaokrouhlení na setiny).
pub fn componentControls(
    index: usize,
    component: *Component,
    max_frequency_hz: f64,
    frequency_step: f64,
) bool {
    var group = dvui.box(@src(), .{}, .{
        .id_extra = index,
        .expand = .horizontal,
        .border = .all(1),
        .corners = .all(4),
        .padding = .all(4),
        .margin = .{ .y = 2, .h = 2 },
    });
    defer group.deinit();

    var remove_clicked = false;
    {
        var header = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer header.deinit();
        var label_buffer: [32]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buffer, "Složka {d}", .{index + 1}) catch "Složka";
        _ = dvui.checkbox(@src(), &component.enabled, label, .{ .gravity_y = 0.5 });
        _ = dropdown(@src(), Waveform, &component.waveform, &all_waveforms, &waveform_names, .{
            .min_size_content = .{ .w = 90 },
            .gravity_y = 0.5,
            .padding = .{ .x = 4, .y = 2, .w = 4, .h = 2 },
        });
        remove_clicked = dvui.button(@src(), "Odebrat", .{}, .{ .gravity_y = 0.5, .padding = .{ .x = 4, .y = 2, .w = 4, .h = 2 } });
    }

    const step = if (frequency_step > 0) frequency_step else 0.01;
    _ = slider(@src(), "frekvence", &component.frequency_hz, .{ .min = 0, .max = max_frequency_hz, .step = step, .suffix = "Hz" });
    _ = slider(@src(), "amplituda", &component.amplitude, .{ .min = 0, .max = max_component_amplitude, .step = 0.01 });
    _ = slider(@src(), "fáze", &component.phase_deg, .{ .min = -180, .max = 180, .step = 1, .suffix = "°" });
    return remove_clicked;
}

pub const all_waveforms = [_]Waveform{ .sine, .square, .sawtooth, .triangle };
const waveform_names = [_][]const u8{ "sinus", "obdélník", "pila", "trojúhelník" };

/// Český název tvaru signálu.
pub fn waveformName(waveform: Waveform) []const u8 {
    return waveform_names[@backingInt(waveform)];
}

/// Frekvence jako text; malé hodnoty s více desetinnými místy.
pub fn formatHz(buffer: []u8, frequency_hz: f64) []const u8 {
    if (frequency_hz < 10) return std.fmt.bufPrint(buffer, "{d:.3} Hz", .{frequency_hz}) catch "?";
    return std.fmt.bufPrint(buffer, "{d:.1} Hz", .{frequency_hz}) catch "?";
}

/// Český název okna.
pub fn windowName(kind: WindowKind) []const u8 {
    return switch (kind) {
        .rectangular => "obdélníkové (žádné)",
        .hann => "Hann",
        .hamming => "Hamming",
        .blackman => "Blackman",
    };
}

/// Rozdělení obrazovky záložky: vlevo panel s ovládáním (se svislým
/// posuvníkem, když se nevejde), vpravo místo pro grafy.
pub const Layout = struct {
    root: *dvui.BoxWidget,
    controls: ?*dvui.BoxWidget = null,
    scroll: ?*dvui.ScrollAreaWidget = null,
    plots: ?*dvui.BoxWidget = null,

    pub fn begin(src: std.builtin.SourceLocation) Layout {
        const root = dvui.box(src, .{ .dir = .horizontal }, .{ .expand = .both });
        return .{ .root = root };
    }

    /// Začne levý panel s ovládáním. Ukončí se voláním `beginPlots`.
    pub fn beginControls(self: *Layout) void {
        self.controls = dvui.box(@src(), .{}, .{
            .expand = .vertical,
            .min_size_content = .{ .w = controls_width },
            .max_size_content = .width(controls_width),
        });
        self.scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
    }

    /// Ukončí panel s ovládáním a začne oblast s grafy.
    pub fn beginPlots(self: *Layout) void {
        if (self.scroll) |scroll| scroll.deinit();
        if (self.controls) |controls| controls.deinit();
        self.scroll = null;
        self.controls = null;
        _ = dvui.separator(@src(), .{ .expand = .vertical, .margin = .{ .x = 6, .w = 6 } });
        self.plots = dvui.box(@src(), .{}, .{ .expand = .both });
    }

    /// Výška jednoho grafu, když se do oblasti s grafy mají vejít `plot_count`
    /// grafy pod sebou, každý s jedním řádkem nadpisu.
    pub fn plotHeight(self: *const Layout, plot_count: usize) f32 {
        const plots = self.plots orelse return 200;
        const available = plots.data().contentRect().h;
        const label_height = dvui.themeGet().font_body.lineHeight() + 4;
        const count: f32 = @floatFromInt(plot_count);
        return @max(80, available / count - label_height - 4);
    }

    pub fn end(self: *Layout) void {
        if (self.plots) |plots| plots.deinit();
        self.root.deinit();
    }
};

/// Nadpis grafu (řádek nad grafem).
pub fn plotTitle(src: std.builtin.SourceLocation, title: []const u8) void {
    dvui.labelNoFmt(src, title, .{}, .{ .padding = .{ .x = 2, .y = 2, .h = 0 } });
}
