//! Záložka „Okna a prosakování“: vlevo ovládání, vpravo signál s oknem,
//! jeho spektrum a spektrum samotného okna.
//!
//! Všechny frekvence jsou zde v binech (1 bin = fs/N). Celé číslo znamená,
//! že signál má v záznamu celý počet period a k prosakování nedojde.
//!
//! Vysvětlení a návod, co zkoušet: `docs/02-okna-a-prosakovani.md`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const dvui = @import("dvui");
const dsp = @import("dsp");

const common = @import("common.zig");
const plot = @import("plot.zig");

const Component = dsp.signal.Component;
const SpectrumLine = dsp.spectrum.SpectrumLine;
const window = dsp.window;
const WindowKind = window.WindowKind;
const WindowResponse = window.WindowResponse;
const WindowProperties = window.WindowProperties;

const log = std.log.scoped(.windows);

/// Nabízené délky signálu jako mocnina dvou (16 až 1024 vzorků).
const min_length_exponent = 4;
const max_length_exponent = 10;

/// Nabízené násobky délky při doplnění nulami.
const zero_padding_factors = [_]usize{ 1, 2, 4, 8, 16 };

/// Spektrum okna počítáme z okna doplněného nulami alespoň na tuto délku,
/// aby byl dobře vidět tvar laloků i u krátkých oken.
const window_response_min_size = 16_384;
const window_response_oversampling = 16;

/// Kolik binů na každou stranu je vidět v grafu spektra okna po obnovení zobrazení.
const window_plot_range_bins = 10.0;

/// Spodní okraj grafů v decibelech; menší hodnoty se oříznou.
const db_floor = -160.0;

/// Do tohoto počtu bodů spektra se každý bod vyznačí puntíkem.
const max_marked_points = 1025;

const max_weak_level_db = 0.0;
const min_weak_level_db = -120.0;

const signal_color = common.colors.gray;
const window_color = common.colors.amber;
const windowed_color = common.colors.blue;
const rectangular_color = common.colors.gray;
const marker_color = common.colors.green;

/// Všechno, od čeho závisí výsledek výpočtu.
const Settings = struct {
    /// Typ podle šířky `usize` (64 bitů na desktopu, 32 ve WebAssembly),
    /// aby šel přímo použít jako posun v `1 << length_exponent`.
    length_exponent: std.math.Log2Int(usize),
    window: WindowKind,
    zero_padding_factor: usize,
    /// Frekvence hlavní sinusovky (amplituda 1) v binech.
    main_frequency_bins: f64,
    /// Slabá sinusovka ukazuje, jak prosakování silné čáry zakryje slabý signál.
    weak_enabled: bool,
    weak_frequency_bins: f64,
    weak_level_db: f64,

    fn length(self: Settings) usize {
        return @as(usize, 1) << self.length_exponent;
    }

    /// Nejvyšší frekvence v binech: N/2 (Nyquistova frekvence).
    fn maxFrequencyBins(self: Settings) f64 {
        return @floatFromInt(self.length() / 2);
    }
};

/// Výsledek výpočtu pro jedno nastavení. Paměť vlastní tato struktura.
const Computed = struct {
    settings: Settings,
    /// Původní signál délky N.
    samples: []f64,
    window: []f64,
    /// Signál vynásobený oknem a doplněný nulami.
    windowed_padded: []f64,
    lines: []SpectrumLine,
    /// Spektrum téhož signálu bez okna, pro porovnání.
    rectangular_lines: []SpectrumLine,
    response: WindowResponse,
    rectangular_response: WindowResponse,
    properties: WindowProperties,
    /// Nejvyšší čára spektra v dB; skutečná úroveň hlavní sinusovky je 0 dB.
    peak_db: f64,

    fn deinit(self: *Computed, allocator: Allocator) void {
        allocator.free(self.samples);
        allocator.free(self.window);
        allocator.free(self.windowed_padded);
        allocator.free(self.lines);
        allocator.free(self.rectangular_lines);
        self.response.deinit(allocator);
        self.rectangular_response.deinit(allocator);
        self.* = undefined;
    }
};

/// Stav záložky.
pub const WindowsTab = struct {
    /// Výchozí stav: hlavní sinusovka přesně v binu, takže ani bez okna
    /// neprosakuje. Tlačítkem „Mezi biny“ lze prosakování hned vyvolat.
    settings: Settings = .{
        .length_exponent = 6,
        .window = .hann,
        .zero_padding_factor = 1,
        .main_frequency_bins = 10,
        .weak_enabled = true,
        .weak_frequency_bins = 20,
        .weak_level_db = -60,
    },
    amplitude_scale: common.AmplitudeScale = .decibel,
    compare_with_rectangular: bool = true,
    computed: ?Computed = null,

    pub fn deinit(self: *WindowsTab, allocator: Allocator) void {
        if (self.computed) |*computed| computed.deinit(allocator);
        self.computed = null;
    }

    /// Nakreslí obsah záložky.
    pub fn show(self: *WindowsTab, allocator: Allocator) !void {
        var layout = common.Layout.begin(@src());
        defer layout.end();

        layout.beginControls();
        self.showControls();
        layout.beginPlots();

        try self.updateComputed(allocator);
        if (self.computed) |*computed| self.showPlots(&layout, computed);
    }

    /// Přepočítá vše, pokud se od posledního výpočtu změnilo nastavení.
    fn updateComputed(self: *WindowsTab, allocator: Allocator) !void {
        if (self.computed) |*computed| {
            if (std.meta.eql(computed.settings, self.settings)) return;
            computed.deinit(allocator);
            self.computed = null;
        }
        self.computed = try compute(allocator, self.settings);
    }

    // -----------------------------------------------------------------------
    // Ovládací panel
    // -----------------------------------------------------------------------

    fn showControls(self: *WindowsTab) void {
        showLengthControls(&self.settings);
        common.separator(@src());
        showSignalControls(&self.settings);
        common.separator(@src());
        self.showWindowControls();
        common.separator(@src());
        self.showViewControls();
    }

    fn showWindowControls(self: *WindowsTab) void {
        common.heading(@src(), "Okno");
        {
            var row = common.row(@src());
            defer row.deinit();
            for (window.all_windows) |kind| {
                _ = common.radioValue(@src(), WindowKind, &self.settings.window, kind, common.windowName(kind));
            }
        }

        if (self.computed) |computed| {
            const properties = computed.properties;
            var buffer: [32]u8 = undefined;
            propertyRow(@src(), 0, "První nula hlavního laloku:", std.fmt.bufPrint(&buffer, "±{d:.2} binu", .{properties.main_lobe_half_width_bins}) catch "?");
            propertyRow(@src(), 1, "Nejvyšší postranní lalok:", std.fmt.bufPrint(&buffer, "{d:.1} dB", .{properties.highest_side_lobe_db}) catch "?");
            propertyRow(@src(), 2, "Koherentní zisk:", std.fmt.bufPrint(&buffer, "{d:.2}", .{properties.coherent_gain}) catch "?");
            propertyRow(@src(), 3, "Nejvyšší čára spektra:", std.fmt.bufPrint(&buffer, "{d:.2} dB", .{computed.peak_db}) catch "?");
            common.weak(@src(), "Skutečná úroveň hlavní sinusovky je 0 dB. Rozdíl u frekvence mezi " ++
                "biny je ztráta způsobená tím, že vrchol čáry padne mezi body spektra.");
        }
    }

    fn showViewControls(self: *WindowsTab) void {
        common.heading(@src(), "Zobrazení");
        {
            var row = common.row(@src());
            defer row.deinit();
            common.inlineText(@src(), "Amplituda:");
            _ = common.radioValue(@src(), common.AmplitudeScale, &self.amplitude_scale, .linear, "lineárně");
            _ = common.radioValue(@src(), common.AmplitudeScale, &self.amplitude_scale, .decibel, "v dB");
        }
        _ = dvui.checkbox(@src(), &self.compare_with_rectangular, "Porovnat s obdélníkovým oknem", .{});
        common.weak(@src(), common.plot_help);
    }

    // -----------------------------------------------------------------------
    // Grafy
    // -----------------------------------------------------------------------

    fn showPlots(self: *WindowsTab, layout: *const common.Layout, computed: *const Computed) void {
        // Porovnání má smysl, jen když vybrané okno není samo obdélníkové.
        const show_rectangular = self.compare_with_rectangular and computed.settings.window != .rectangular;
        const height = layout.plotHeight(3);

        common.plotTitle(@src(), "Signál, okno a signál vynásobený oknem (za koncem signálu doplněné nuly)");
        showTimePlot(computed, height);

        common.plotTitle(@src(), "Spektrum signálu vynásobeného oknem");
        showSpectrumPlot(computed, self.amplitude_scale, show_rectangular, height);

        common.plotTitle(@src(), "Spektrum samotného okna – tvar, do kterého se rozmaže každá čára");
        showWindowResponsePlot(computed, show_rectangular, height);
    }
};

/// Řádek tabulky vlastností okna: popisek vlevo, hodnota v zarovnaném sloupci.
fn propertyRow(src: std.builtin.SourceLocation, id_extra: usize, label: []const u8, value: []const u8) void {
    var row = dvui.box(src, .{ .dir = .horizontal }, .{ .id_extra = id_extra, .expand = .horizontal });
    defer row.deinit();
    dvui.labelNoFmt(@src(), label, .{}, .{ .min_size_content = .{ .w = 190 }, .padding = .{ .x = 2, .y = 1, .w = 2, .h = 1 } });
    dvui.labelNoFmt(@src(), value, .{}, .{ .padding = .{ .x = 2, .y = 1, .w = 2, .h = 1 } });
}

fn compute(allocator: Allocator, settings: Settings) !Computed {
    const length = settings.length();
    // Vzorkovací frekvenci volíme rovnou délce signálu. Pak 1 Hz odpovídá
    // přesně jednomu binu a frekvence lze zadávat přímo v binech.
    const sample_rate_hz: f64 = @floatFromInt(length);
    const fft_size = length * settings.zero_padding_factor;

    var components: [2]Component = undefined;
    const samples = try dsp.signal.generate(allocator, signalSpec(settings, &components), sample_rate_hz, length);
    errdefer allocator.free(samples);
    const coefficients = try window.window(allocator, settings.window, length);
    errdefer allocator.free(coefficients);
    const rectangular = try window.window(allocator, .rectangular, length);
    defer allocator.free(rectangular);

    const lines = try windowedSpectrum(allocator, samples, coefficients, fft_size, sample_rate_hz);
    errdefer allocator.free(lines);
    const rectangular_lines = try windowedSpectrum(allocator, samples, rectangular, fft_size, sample_rate_hz);
    errdefer allocator.free(rectangular_lines);

    const response_size = @max(length * window_response_oversampling, window_response_min_size);
    var response = try window.windowResponse(allocator, coefficients, response_size);
    errdefer response.deinit(allocator);
    var rectangular_response = try window.windowResponse(allocator, rectangular, response_size);
    errdefer rectangular_response.deinit(allocator);
    const properties = window.analyzeWindow(coefficients, response);

    var peak_db = -std.math.inf(f64);
    for (lines) |line| peak_db = @max(peak_db, line.amplitude_db);

    log.debug("windowed spectrum computed window={s} length={d} fft_size={d} main_frequency_bins={d} peak_db={d}", .{
        @tagName(settings.window), length, fft_size, settings.main_frequency_bins, peak_db,
    });

    const windowed = try window.applyWindow(allocator, samples, coefficients);
    defer allocator.free(windowed);

    return .{
        .settings = settings,
        .windowed_padded = try window.zeroPad(allocator, windowed, fft_size),
        .samples = samples,
        .window = coefficients,
        .lines = lines,
        .rectangular_lines = rectangular_lines,
        .response = response,
        .rectangular_response = rectangular_response,
        .properties = properties,
        .peak_db = peak_db,
    };
}

/// Signál: hlavní sinusovka s amplitudou 1 a volitelně slabá sinusovka.
/// Složky se zapíšou do `components`, které musí žít stejně dlouho jako výsledek.
fn signalSpec(settings: Settings, components: *[2]Component) dsp.signal.SignalSpec {
    components[0] = sine(settings.main_frequency_bins, 1);
    components[1] = sine(settings.weak_frequency_bins, dbToAmplitude(settings.weak_level_db));
    const count: usize = if (settings.weak_enabled) 2 else 1;
    return .{ .components = components[0..count], .dc_offset = 0, .noise_amplitude = 0, .noise_seed = 1 };
}

fn sine(frequency_hz: f64, amplitude: f64) Component {
    return .{ .enabled = true, .waveform = .sine, .frequency_hz = frequency_hz, .amplitude = amplitude, .phase_deg = 0 };
}

/// Decibely na amplitudu: 0 dB = 1, −20 dB = 0,1, −40 dB = 0,01 …
fn dbToAmplitude(level_db: f64) f64 {
    return std.math.pow(f64, 10, level_db / 20);
}

/// Signál vynásobí oknem, doplní nulami a spočítá jednostranné spektrum.
fn windowedSpectrum(
    allocator: Allocator,
    samples: []const f64,
    coefficients: []const f64,
    fft_size: usize,
    sample_rate_hz: f64,
) ![]SpectrumLine {
    const windowed = try window.applyWindow(allocator, samples, coefficients);
    defer allocator.free(windowed);
    const padded = try window.zeroPad(allocator, windowed, fft_size);
    defer allocator.free(padded);
    const input = try dsp.fft.realToComplex(allocator, padded);
    defer allocator.free(input);
    const output = try dsp.fft.fft(allocator, input);
    defer allocator.free(output);
    return dsp.spectrum.oneSidedSpectrum(allocator, output, sample_rate_hz, window.sum(coefficients));
}

fn showLengthControls(settings: *Settings) void {
    common.heading(@src(), "Záznam");
    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();
        const names = comptime lengthNames();
        var index: usize = settings.length_exponent - min_length_exponent;
        if (dvui.dropdown(@src(), &names, .{ .choice = &index }, .{}, .{ .min_size_content = .{ .w = 80 }, .gravity_y = 0.5 })) {
            settings.length_exponent = @intCast(index + min_length_exponent);
        }
        common.inlineText(@src(), "délka signálu (N)");
    }
    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();
        const names = comptime paddingNames();
        var index: usize = 0;
        for (zero_padding_factors, 0..) |factor, i| {
            if (factor == settings.zero_padding_factor) index = i;
        }
        if (dvui.dropdown(@src(), &names, .{ .choice = &index }, .{}, .{ .min_size_content = .{ .w = 80 }, .gravity_y = 0.5 })) {
            settings.zero_padding_factor = zero_padding_factors[index];
        }
        common.inlineText(@src(), "doplnění nulami");
    }
    common.weak(@src(), "Doplnění nulami zhustí body spektra, ale nezlepší rozlišení: " ++
        "tvar čar zůstane stejný, jen je lépe vidět.");

    clampFrequencies(settings);
}

fn lengthNames() [max_length_exponent - min_length_exponent + 1][]const u8 {
    var names: [max_length_exponent - min_length_exponent + 1][]const u8 = undefined;
    for (&names, min_length_exponent..) |*name, exponent| {
        name.* = std.fmt.comptimePrint("{d}", .{1 << exponent});
    }
    return names;
}

fn paddingNames() [zero_padding_factors.len][]const u8 {
    var names: [zero_padding_factors.len][]const u8 = undefined;
    for (&names, zero_padding_factors) |*name, factor| {
        name.* = std.fmt.comptimePrint("×{d}", .{factor});
    }
    return names;
}

/// Frekvence držíme v rozsahu 0 až N/2 binů (po Nyquistovu frekvenci).
fn clampFrequencies(settings: *Settings) void {
    const max_bins = settings.maxFrequencyBins();
    settings.main_frequency_bins = @min(settings.main_frequency_bins, max_bins);
    settings.weak_frequency_bins = @min(settings.weak_frequency_bins, max_bins);
}

fn showSignalControls(settings: *Settings) void {
    common.heading(@src(), "Signál");
    const max_bins = settings.maxFrequencyBins();

    common.text(@src(), "Hlavní sinusovka (amplituda 1 = 0 dB)", .{});
    _ = common.slider(@src(), "frekvence [biny]", &settings.main_frequency_bins, .{ .min = 0, .max = max_bins, .step = 0.01 });
    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();
        if (dvui.button(@src(), "Přesně v binu", .{}, .{ .padding = .all(4) })) {
            settings.main_frequency_bins = @round(settings.main_frequency_bins);
        }
        if (dvui.button(@src(), "Mezi biny", .{}, .{ .padding = .all(4) })) {
            const between = @floor(settings.main_frequency_bins) + 0.5;
            settings.main_frequency_bins = @min(between, max_bins - 0.5);
        }
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .{ .h = 6 } });
    _ = dvui.checkbox(@src(), &settings.weak_enabled, "Slabá sinusovka", .{});
    // DVUI nemá zakázané (šedé) ovládací prvky jako egui, proto posuvníky
    // slabé sinusovky při jejím vypnutí skryjeme.
    if (settings.weak_enabled) {
        _ = common.slider(@src(), "frekvence [biny]", &settings.weak_frequency_bins, .{ .min = 0, .max = max_bins, .step = 0.01 });
        _ = common.slider(@src(), "úroveň", &settings.weak_level_db, .{
            .min = min_weak_level_db,
            .max = max_weak_level_db,
            .step = 1,
            .suffix = "dB",
        });
    }
    common.weak(@src(), "Frekvence je v binech (1 bin = fs/N). Celé číslo znamená celý počet " ++
        "period v záznamu – pak k prosakování nedojde.");
}

fn showTimePlot(computed: *const Computed, height: f32) void {
    var time_plot = plot.Plot.init(@src(), .{
        .height = height,
        .x_label = "vzorek n",
        .y_label = "",
        .hover_y_label = "hodnota",
        .legend = true,
    });
    time_plot.line("signál", indexedPoints(computed.samples) orelse return, .{ .color = signal_color });
    time_plot.line("okno", indexedPoints(computed.window) orelse return, .{ .color = window_color });
    time_plot.line("signál × okno", indexedPoints(computed.windowed_padded) orelse return, .{ .color = windowed_color, .width = 2 });
    time_plot.show();
}

/// Body grafu, kde vodorovná souřadnice je pořadové číslo vzorku.
fn indexedPoints(values: []const f64) ?[]plot.Point {
    const points = plot.allocPoints(values.len) orelse return null;
    for (points, values, 0..) |*point, value, index| {
        point.* = .{ .x = @floatFromInt(index), .y = value };
    }
    return points;
}

fn showSpectrumPlot(computed: *const Computed, amplitude_scale: common.AmplitudeScale, show_rectangular: bool, height: f32) void {
    const y_label = switch (amplitude_scale) {
        .linear => "amplituda",
        .decibel => "amplituda [dB]",
    };
    const settings = computed.settings;

    var spectrum_plot = plot.Plot.init(@src(), .{
        .height = height,
        .x_label = "frekvence [biny]",
        .y_label = y_label,
        .legend = true,
    });
    if (show_rectangular) {
        spectrum_plot.line("bez okna", spectrumPoints(computed.rectangular_lines, amplitude_scale) orelse return, .{ .color = rectangular_color });
    }

    const name = common.windowName(settings.window);
    const points = spectrumPoints(computed.lines, amplitude_scale) orelse return;
    if (computed.lines.len <= max_marked_points) {
        spectrum_plot.markers(name, points, .{ .color = windowed_color, .radius = 2 });
    }
    spectrum_plot.line(name, points, .{ .color = windowed_color, .width = 2 });

    // Svislé čárkované čáry ukazují skutečné frekvence sinusovek.
    const marker_style: plot.Style = .{ .color = marker_color, .dashed = true };
    spectrum_plot.verticalLine("skutečná frekvence", settings.main_frequency_bins, marker_style);
    if (settings.weak_enabled) {
        spectrum_plot.verticalLine("skutečná frekvence", settings.weak_frequency_bins, marker_style);
    }
    spectrum_plot.show();
}

fn spectrumPoints(lines: []const SpectrumLine, amplitude_scale: common.AmplitudeScale) ?[]plot.Point {
    const points = plot.allocPoints(lines.len) orelse return null;
    for (points, lines) |*point, line| {
        point.* = .{
            // Vzorkovací frekvence je rovna délce signálu, takže Hz = biny.
            .x = line.frequency_hz,
            .y = switch (amplitude_scale) {
                .linear => line.amplitude,
                .decibel => @max(line.amplitude_db, db_floor),
            },
        };
    }
    return points;
}

fn showWindowResponsePlot(computed: *const Computed, show_rectangular: bool, height: f32) void {
    var response_plot = plot.Plot.init(@src(), .{
        .height = height,
        .x_label = "vzdálenost od frekvence sinusovky [biny]",
        .y_label = "útlum [dB]",
        .hover_x_label = "vzdálenost [biny]",
        .default_x = .{ .min = -window_plot_range_bins, .max = window_plot_range_bins },
        .default_y = .{ .min = -120, .max = 5 },
        .legend = true,
    });
    if (show_rectangular) {
        response_plot.line("bez okna", mirroredPoints(computed.rectangular_response) orelse return, .{ .color = rectangular_color });
    }
    response_plot.line(common.windowName(computed.settings.window), mirroredPoints(computed.response) orelse return, .{
        .color = windowed_color,
        .width = 2,
    });
    response_plot.show();
}

/// Spektrum okna je souměrné kolem nuly; máme jen kladnou polovinu, zápornou
/// doplníme zrcadlením.
fn mirroredPoints(response: WindowResponse) ?[]plot.Point {
    const positive_count = response.offsets_bins.len;
    if (positive_count == 0) return &.{};
    const points = plot.allocPoints(2 * positive_count - 1) orelse return null;
    // Záporná polovina (bez nuly) v opačném pořadí, pak kladná včetně nuly.
    for (1..positive_count) |index| {
        const source = positive_count - index;
        points[index - 1] = .{ .x = -response.offsets_bins[source], .y = @max(response.magnitude_db[source], db_floor) };
    }
    for (response.offsets_bins, response.magnitude_db, 0..) |offset, db, index| {
        points[positive_count - 1 + index] = .{ .x = offset, .y = @max(db, db_floor) };
    }
    return points;
}
