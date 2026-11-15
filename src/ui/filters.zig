//! Záložka „Filtry“: návrh FIR a IIR filtru, jeho impulzní odezva
//! a frekvenční charakteristika a signál i spektrum před a po filtraci.
//!
//! Vysvětlení a návod, co zkoušet: `docs/04-filtry.md`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const dvui = @import("dvui");
const dsp = @import("dsp");

const common = @import("common.zig");
const plot = @import("plot.zig");

const Component = dsp.signal.Component;
const SpectrumLine = dsp.spectrum.SpectrumLine;
const filter = dsp.filter;
const Biquad = filter.Biquad;
const FilterType = filter.FilterType;
const ResponsePoint = filter.ResponsePoint;
const WindowKind = dsp.window.WindowKind;

const log = std.log.scoped(.filters);

/// Vzorkovací frekvence je v této záložce pevná; frekvence jdou do 500 Hz.
const sample_rate_hz = 1000.0;
/// Délka testovacího signálu (mocnina dvou kvůli FFT), zhruba 1 s.
const signal_length = 1024;
/// Počet bodů frekvenční charakteristiky od 0 do fs/2.
const response_points = 1025;
/// Kolik vzorků nekonečné impulzní odezvy IIR filtru zobrazit.
const iir_impulse_length = 200;

const min_frequency_hz = 1.0;
/// Mezní frekvence nesmí sahat až na fs/2.
const max_frequency_hz = sample_rate_hz / 2.0 - 1.0;
/// Nejmenší rozdíl mezí pásmové propusti FIR.
const min_band_width_hz = 1.0;
const max_fir_half_length = 200;
const min_q = 0.1;
const max_q = 20.0;
/// Q = 1/√2 dává nejplošší propustné pásmo.
const flattest_q = 1.0 / std.math.sqrt2;
const max_components = 4;
const max_noise = 1.0;

/// Spodní okraj grafů v decibelech; menší hodnoty se oříznou.
const db_floor = -120.0;

/// Rozestup dílků na ose x u úzkých grafů ve dvou sloupcích. Výchozí
/// rozestup je na šířku sloupce moc velký, takže by se ukázala jen nula.
const narrow_x_tick_spacing = 40;

const input_color = common.colors.gray;
const output_color = common.colors.blue;
const response_color = common.colors.amber;
const marker_color = common.colors.green;

/// Rodina filtru.
const FilterFamily = enum { fir, iir };

/// Co ukazuje graf frekvenční charakteristiky.
const ResponseView = enum { magnitude, phase };

/// Všechno, od čeho závisí výsledek výpočtu.
const Settings = struct {
    /// Složky vstupního signálu; platných je prvních `component_count`.
    components: [max_components]Component,
    component_count: usize,
    noise_amplitude: f64,
    noise_seed: u64,
    family: FilterFamily,
    filter_type: FilterType,
    /// Mezní frekvence; u pásmové propusti FIR dolní mez, u IIR střed pásma.
    frequency_hz: f64,
    /// Horní mez pásmové propusti FIR.
    upper_frequency_hz: f64,
    /// Počet koeficientů FIR je 2·k + 1 (vždy lichý); toto je k.
    fir_half_length: usize,
    fir_window: WindowKind,
    q: f64,

    fn activeComponents(self: *Settings) []Component {
        return self.components[0..self.component_count];
    }

    fn signalSpec(self: *const Settings) dsp.signal.SignalSpec {
        return .{
            .components = self.components[0..self.component_count],
            .dc_offset = 0,
            .noise_amplitude = self.noise_amplitude,
            .noise_seed = self.noise_seed,
        };
    }

    fn firLength(self: Settings) usize {
        return 2 * self.fir_half_length + 1;
    }

    fn isFirBand(self: Settings) bool {
        return self.family == .fir and self.filter_type == .band_pass;
    }

    /// Porovná jen platné složky (zbytek pole je nepodstatný).
    fn eql(a: *const Settings, b: *const Settings) bool {
        if (a.component_count != b.component_count) return false;
        for (a.components[0..a.component_count], b.components[0..b.component_count]) |x, y| {
            if (!std.meta.eql(x, y)) return false;
        }
        return a.noise_amplitude == b.noise_amplitude and a.noise_seed == b.noise_seed and
            a.family == b.family and a.filter_type == b.filter_type and
            a.frequency_hz == b.frequency_hz and a.upper_frequency_hz == b.upper_frequency_hz and
            a.fir_half_length == b.fir_half_length and a.fir_window == b.fir_window and a.q == b.q;
    }
};

/// Výsledek výpočtu pro jedno nastavení. Paměť vlastní tato struktura.
const Computed = struct {
    settings: Settings,
    /// U FIR jsou to přímo koeficienty filtru.
    impulse_response: []f64,
    response: []ResponsePoint,
    /// Koeficienty IIR filtru (u FIR nejsou).
    biquad: ?Biquad,
    input: []f64,
    output: []f64,
    input_spectrum: []SpectrumLine,
    output_spectrum: []SpectrumLine,

    fn deinit(self: *Computed, allocator: Allocator) void {
        allocator.free(self.impulse_response);
        allocator.free(self.response);
        allocator.free(self.input);
        allocator.free(self.output);
        allocator.free(self.input_spectrum);
        allocator.free(self.output_spectrum);
        self.* = undefined;
    }
};

/// Stav záložky.
pub const FiltersTab = struct {
    /// Výchozí stav: pomalá sinusovka, rychlejší sinusovka a šum; dolní
    /// propust 100 Hz nechá projít jen tu pomalou.
    settings: Settings = .{
        .components = .{ sine(20, 1), sine(200, 0.5), sine(50, 0.5), sine(50, 0.5) },
        .component_count = 2,
        .noise_amplitude = 0.2,
        .noise_seed = 1,
        .family = .fir,
        .filter_type = .low_pass,
        .frequency_hz = 100,
        .upper_frequency_hz = 250,
        .fir_half_length = 30,
        .fir_window = .hamming,
        .q = flattest_q,
    },
    response_view: ResponseView = .magnitude,
    computed: ?Computed = null,
    /// Osa x sdílená grafy frekvenční charakteristiky a spektra.
    frequency_link: plot.LinkedAxis = .{},

    pub fn deinit(self: *FiltersTab, allocator: Allocator) void {
        if (self.computed) |*computed| computed.deinit(allocator);
        self.computed = null;
    }

    /// Nakreslí obsah záložky.
    pub fn show(self: *FiltersTab, allocator: Allocator) !void {
        var layout = common.Layout.begin(@src());
        defer layout.end();

        layout.beginControls();
        self.showControls();
        layout.beginPlots();

        try self.updateComputed(allocator);
        if (self.computed) |*computed| self.showPlots(&layout, computed);
    }

    /// Přepočítá vše, pokud se od posledního výpočtu změnilo nastavení.
    fn updateComputed(self: *FiltersTab, allocator: Allocator) !void {
        if (self.computed) |*computed| {
            if (computed.settings.eql(&self.settings)) return;
            computed.deinit(allocator);
            self.computed = null;
        }
        self.computed = try compute(allocator, self.settings);
    }

    // -----------------------------------------------------------------------
    // Ovládací panel
    // -----------------------------------------------------------------------

    fn showControls(self: *FiltersTab) void {
        self.showFilterControls();
        common.separator(@src());
        showSignalControls(&self.settings);
        common.separator(@src());
        common.heading(@src(), "Zobrazení");
        {
            var row = common.row(@src());
            defer row.deinit();
            common.inlineText(@src(), "Charakteristika:");
            _ = common.radioValue(@src(), ResponseView, &self.response_view, .magnitude, "zesílení");
            _ = common.radioValue(@src(), ResponseView, &self.response_view, .phase, "fáze");
        }
        common.weak(@src(), common.plot_help);
    }

    fn showFilterControls(self: *FiltersTab) void {
        const settings = &self.settings;
        common.heading(@src(), "Filtr");
        common.text(@src(), "Vzorkovací frekvence fs = {d} Hz", .{sample_rate_hz});
        {
            var row = common.row(@src());
            defer row.deinit();
            _ = common.radioValue(@src(), FilterFamily, &settings.family, .fir, "FIR");
            _ = common.radioValue(@src(), FilterFamily, &settings.family, .iir, "IIR (biquad)");
        }
        {
            var row = common.row(@src());
            defer row.deinit();
            for ([_]FilterType{ .low_pass, .high_pass, .band_pass }) |filter_type| {
                _ = common.radioValue(@src(), FilterType, &settings.filter_type, filter_type, filterTypeName(filter_type));
            }
        }

        _ = dvui.spacer(@src(), .{ .min_size_content = .{ .h = 4 } });
        showFrequencyControls(settings);

        _ = dvui.spacer(@src(), .{ .min_size_content = .{ .h = 4 } });
        switch (settings.family) {
            .fir => showFirControls(settings),
            .iir => showIirControls(settings, if (self.computed) |computed| computed.biquad else null),
        }
    }

    // -----------------------------------------------------------------------
    // Grafy
    // -----------------------------------------------------------------------

    fn showPlots(self: *FiltersTab, layout: *const common.Layout, computed: *const Computed) void {
        // Čtyři grafy ve dvou řádcích a dvou sloupcích.
        const height = layout.plotHeight(2);
        var columns = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, .{ .expand = .both });
        defer columns.deinit();
        {
            var left = dvui.box(@src(), .{}, .{ .expand = .both });
            defer left.deinit();
            common.plotTitle(@src(), impulseTitle(computed.settings.family));
            showImpulsePlot(computed, height);
            common.plotTitle(@src(), "Signál před a po filtraci");
            showTimePlot(computed, height);
        }
        {
            var right = dvui.box(@src(), .{}, .{ .expand = .both });
            defer right.deinit();
            common.plotTitle(@src(), switch (self.response_view) {
                .magnitude => "Frekvenční charakteristika – zesílení",
                .phase => "Frekvenční charakteristika – fáze",
            });
            self.showResponsePlot(computed, height);
            common.plotTitle(@src(), "Spektrum před a po filtraci (s oknem Hann)");
            self.showSpectrumPlot(computed, height);
        }
    }

    fn showResponsePlot(self: *FiltersTab, computed: *const Computed, height: f32) void {
        const points = plot.allocPoints(computed.response.len) orelse return;
        for (points, computed.response) |*point, response| {
            point.* = .{
                .x = response.frequency_hz,
                .y = switch (self.response_view) {
                    .magnitude => @max(response.magnitude_db, db_floor),
                    .phase => response.phase_deg,
                },
            };
        }
        var response_plot = plot.Plot.init(@src(), .{
            .height = height,
            .x_label = "frekvence [Hz]",
            .y_label = switch (self.response_view) {
                .magnitude => "zesílení [dB]",
                .phase => "fáze [°]",
            },
            .x_tick_spacing = narrow_x_tick_spacing,
            .linked_x = &self.frequency_link,
        });
        response_plot.line("filtr", points, .{ .color = response_color, .width = 2 });
        const marker_style: plot.Style = .{ .color = marker_color, .dashed = true };
        response_plot.verticalLine("nastavená frekvence", computed.settings.frequency_hz, marker_style);
        if (computed.settings.isFirBand()) {
            response_plot.verticalLine("nastavená frekvence", computed.settings.upper_frequency_hz, marker_style);
        }
        response_plot.show();
    }

    fn showSpectrumPlot(self: *FiltersTab, computed: *const Computed, height: f32) void {
        var spectrum_plot = plot.Plot.init(@src(), .{
            .height = height,
            .x_label = "frekvence [Hz]",
            .y_label = "amplituda [dB]",
            .x_tick_spacing = narrow_x_tick_spacing,
            .linked_x = &self.frequency_link,
            .legend = true,
        });
        spectrum_plot.line("vstup", spectrumPoints(computed.input_spectrum) orelse return, .{ .color = input_color });
        spectrum_plot.line("výstup", spectrumPoints(computed.output_spectrum) orelse return, .{ .color = output_color, .width = 2 });
        // Zesílení filtru pro srovnání: výstup ≈ vstup + zesílení (v dB).
        const response = plot.allocPoints(computed.response.len) orelse return;
        for (response, computed.response) |*point, value| {
            point.* = .{ .x = value.frequency_hz, .y = @max(value.magnitude_db, db_floor) };
        }
        spectrum_plot.line("zesílení filtru", response, .{ .color = response_color, .dashed = true });
        spectrum_plot.show();
    }
};

fn sine(frequency_hz: f64, amplitude: f64) Component {
    return .{ .enabled = true, .waveform = .sine, .frequency_hz = frequency_hz, .amplitude = amplitude, .phase_deg = 0 };
}

fn compute(allocator: Allocator, settings: Settings) !Computed {
    const input = try dsp.signal.generate(allocator, settings.signalSpec(), sample_rate_hz, signal_length);
    errdefer allocator.free(input);

    var impulse_response: []f64 = undefined;
    var response: []ResponsePoint = undefined;
    var biquad: ?Biquad = null;
    var output: []f64 = undefined;
    switch (settings.family) {
        .fir => {
            impulse_response = try filter.designFir(allocator, firDesign(settings), sample_rate_hz);
            errdefer allocator.free(impulse_response);
            // FIR filtr nemá zpětnou vazbu: jmenovatel je jen a0 = 1.
            response = try filter.frequencyResponse(allocator, impulse_response, &.{1}, sample_rate_hz, response_points);
            errdefer allocator.free(response);
            output = try filter.convolve(allocator, input, impulse_response);
        },
        .iir => {
            const designed = filter.designBiquad(settings.filter_type, settings.frequency_hz, settings.q, sample_rate_hz);
            biquad = designed;
            response = try filter.frequencyResponse(allocator, &designed.b, &designed.a, sample_rate_hz, response_points);
            errdefer allocator.free(response);
            impulse_response = try filter.biquadImpulseResponse(allocator, designed, iir_impulse_length);
            errdefer allocator.free(impulse_response);
            output = try filter.biquadFilter(allocator, designed, input);
        },
    }
    errdefer allocator.free(impulse_response);
    errdefer allocator.free(response);
    errdefer allocator.free(output);

    log.debug("filter computed family={s} filter_type={s} frequency_hz={d} impulse_length={d}", .{
        @tagName(settings.family), @tagName(settings.filter_type), settings.frequency_hz, impulse_response.len,
    });

    const input_spectrum = try analyze(allocator, input);
    errdefer allocator.free(input_spectrum);
    return .{
        .settings = settings,
        .input_spectrum = input_spectrum,
        .output_spectrum = try analyze(allocator, output),
        .impulse_response = impulse_response,
        .response = response,
        .biquad = biquad,
        .input = input,
        .output = output,
    };
}

fn firDesign(settings: Settings) filter.FirDesign {
    return .{
        .filter_type = settings.filter_type,
        .cutoff_hz = settings.frequency_hz,
        .upper_cutoff_hz = settings.upper_frequency_hz,
        .length = settings.firLength(),
        .window = settings.fir_window,
    };
}

/// Spektrum signálu. Frekvence složek nejsou obecně v celých binech, proto
/// signál nejdřív vynásobíme oknem Hann, aby prosakování nezakrylo, co filtr
/// udělal.
fn analyze(allocator: Allocator, signal: []const f64) ![]SpectrumLine {
    const coefficients = try dsp.window.window(allocator, .hann, signal.len);
    defer allocator.free(coefficients);
    const windowed = try dsp.window.applyWindow(allocator, signal, coefficients);
    defer allocator.free(windowed);
    const input = try dsp.fft.realToComplex(allocator, windowed);
    defer allocator.free(input);
    const output = try dsp.fft.fft(allocator, input);
    defer allocator.free(output);
    return dsp.spectrum.oneSidedSpectrum(allocator, output, sample_rate_hz, dsp.window.sum(coefficients));
}

// ---------------------------------------------------------------------------
// Ovládací panel
// ---------------------------------------------------------------------------

fn filterTypeName(filter_type: FilterType) []const u8 {
    return switch (filter_type) {
        .low_pass => "dolní propust",
        .high_pass => "horní propust",
        .band_pass => "pásmová propust",
    };
}

/// Posuvníky frekvencí; jejich význam záleží na druhu filtru.
fn showFrequencyControls(settings: *Settings) void {
    const first_label = if (settings.filter_type != .band_pass)
        "mezní frekvence"
    else switch (settings.family) {
        .fir => "dolní mez",
        .iir => "střed pásma",
    };
    frequencySlider(@src(), &settings.frequency_hz, first_label);

    if (settings.isFirBand()) {
        frequencySlider(@src(), &settings.upper_frequency_hz, "horní mez");
        // Horní mez musí ležet nad dolní.
        const lowest_upper = settings.frequency_hz + min_band_width_hz;
        settings.upper_frequency_hz = std.math.clamp(settings.upper_frequency_hz, lowest_upper, max_frequency_hz);
        settings.frequency_hz = @min(settings.frequency_hz, settings.upper_frequency_hz - min_band_width_hz);
    }
}

fn frequencySlider(src: std.builtin.SourceLocation, value: *f64, label: []const u8) void {
    _ = common.slider(src, label, value, .{
        .min = min_frequency_hz,
        .max = max_frequency_hz,
        .logarithmic = true,
        .step = 1,
        .suffix = "Hz",
    });
}

fn showFirControls(settings: *Settings) void {
    // Posuvník pracuje s f64; k je celé číslo.
    var half_length: f64 = @floatFromInt(settings.fir_half_length);
    if (common.slider(@src(), "k", &half_length, .{ .min = 1, .max = max_fir_half_length, .step = 1 })) {
        settings.fir_half_length = @intFromFloat(@round(half_length));
    }
    const delay_samples = settings.fir_half_length;
    common.text(@src(), "Počet koeficientů M = 2k + 1 = {d}", .{settings.firLength()});
    common.text(@src(), "Zpoždění (M − 1)/2 = {d} vzorků = {d:.0} ms", .{
        delay_samples,
        1000 * @as(f64, @floatFromInt(delay_samples)) / sample_rate_hz,
    });

    common.text(@src(), "Okno:", .{});
    {
        var row = common.row(@src());
        defer row.deinit();
        for (dsp.window.all_windows) |kind| {
            _ = common.radioValue(@src(), WindowKind, &settings.fir_window, kind, common.windowName(kind));
        }
    }
    common.weak(@src(), "Delší filtr má strmější přechod mezi propustným a nepropustným pásmem, " ++
        "ale větší zpoždění. Okno určuje, jak hluboko filtr potlačí nepropustné " ++
        "pásmo (stejně jako postranní laloky ve spektru).");
}

fn showIirControls(settings: *Settings, biquad: ?Biquad) void {
    _ = common.slider(@src(), "Q (jakost)", &settings.q, .{ .min = min_q, .max = max_q, .logarithmic = true, .step = 0.01 });
    if (dvui.button(@src(), "Q = 0,707 (nejplošší)", .{}, .{ .padding = .all(4) })) {
        settings.q = flattest_q;
    }

    if (biquad) |coefficients| {
        common.text(@src(), "Koeficienty:", .{});
        for (coefficients.b, coefficients.a, 0..) |b, a, index| {
            var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .id_extra = index });
            defer row.deinit();
            dvui.label(@src(), "b{d} = {d:.5}", .{ index, b }, .{ .min_size_content = .{ .w = 120 } });
            dvui.label(@src(), "a{d} = {d:.5}", .{ index, a }, .{});
        }
    }
    common.weak(@src(), "y[n] = b0·x[n] + b1·x[n−1] + b2·x[n−2] − a1·y[n−1] − a2·y[n−2]. " ++
        "Díky zpětné vazbě stačí pět čísel, ale fáze není lineární. Velké Q " ++
        "dává převýšení u mezní frekvence a dlouho doznívající odezvu.");
}

fn showSignalControls(settings: *Settings) void {
    common.heading(@src(), "Vstupní signál");

    // Složku nelze odebrat uprostřed procházení seznamu, proto si jen
    // zapamatujeme její index a odebereme ji až po cyklu.
    var index_to_remove: ?usize = null;
    for (settings.activeComponents(), 0..) |*component, index| {
        if (common.componentControls(index, component, sample_rate_hz / 2.0, 0)) index_to_remove = index;
    }
    if (index_to_remove) |index| {
        const components = settings.activeComponents();
        std.mem.copyForwards(Component, components[index .. components.len - 1], components[index + 1 ..]);
        settings.component_count -= 1;
    }

    const can_add = settings.component_count < max_components;
    if (dvui.button(@src(), "Přidat složku", .{ .grayed = !can_add }, .{ .padding = .all(4) }) and can_add) {
        settings.components[settings.component_count] = sine(50, 0.5);
        settings.component_count += 1;
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .{ .h = 6 } });
    _ = common.slider(@src(), "šum", &settings.noise_amplitude, .{ .min = 0, .max = max_noise, .step = 0.01 });
    if (dvui.button(@src(), "Nový šum", .{}, .{ .padding = .all(4) })) settings.noise_seed += 1;
}

// ---------------------------------------------------------------------------
// Grafy
// ---------------------------------------------------------------------------

fn impulseTitle(family: FilterFamily) []const u8 {
    return switch (family) {
        .fir => "Impulzní odezva = koeficienty filtru",
        .iir => "Impulzní odezva (prvních 200 vzorků)",
    };
}

fn showImpulsePlot(computed: *const Computed, height: f32) void {
    const points = plot.allocPoints(computed.impulse_response.len) orelse return;
    for (points, computed.impulse_response, 0..) |*point, value, index| {
        point.* = .{ .x = @floatFromInt(index), .y = value };
    }
    var impulse_plot = plot.Plot.init(@src(), .{
        .height = height,
        .x_label = "vzorek n",
        .y_label = "",
        .hover_y_label = "h[n]",
        .x_tick_spacing = narrow_x_tick_spacing,
    });
    impulse_plot.stems("h[n]", points, .{ .color = response_color, .radius = 2 });
    impulse_plot.show();
}

fn showTimePlot(computed: *const Computed, height: f32) void {
    var time_plot = plot.Plot.init(@src(), .{
        .height = height,
        .x_label = "čas [ms]",
        .y_label = "",
        .hover_y_label = "hodnota",
        .x_tick_spacing = narrow_x_tick_spacing,
        .legend = true,
    });
    time_plot.line("vstup", timePoints(computed.input) orelse return, .{ .color = input_color });
    time_plot.line("výstup", timePoints(computed.output) orelse return, .{ .color = output_color, .width = 2 });
    time_plot.show();
}

fn timePoints(samples: []const f64) ?[]plot.Point {
    const points = plot.allocPoints(samples.len) orelse return null;
    for (points, samples, 0..) |*point, value, index| {
        point.* = .{ .x = 1000 * @as(f64, @floatFromInt(index)) / sample_rate_hz, .y = value };
    }
    return points;
}

fn spectrumPoints(lines: []const SpectrumLine) ?[]plot.Point {
    const points = plot.allocPoints(lines.len) orelse return null;
    for (points, lines) |*point, line| {
        point.* = .{ .x = line.frequency_hz, .y = @max(line.amplitude_db, db_floor) };
    }
    return points;
}
