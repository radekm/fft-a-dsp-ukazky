//! Záložka „Signály a spektrum“: vlevo ovládání signálu, vpravo grafy
//! časového průběhu, amplitudového spektra a fáze.
//!
//! Vysvětlení a návod, co zkoušet: `docs/01-signaly-a-spektrum.md`.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const dvui = @import("dvui");
const dsp = @import("dsp");

const common = @import("common.zig");
const plot = @import("plot.zig");

const Complex = dsp.Complex;
const Component = dsp.signal.Component;
const SpectrumLine = dsp.spectrum.SpectrumLine;

const log = std.log.scoped(.spectrum);

/// Nejmenší a největší nabízená délka FFT jako mocnina dvou (8 až 4096 vzorků).
const min_fft_exponent = 3;
const max_fft_exponent = 12;

const min_sample_rate_hz = 64.0;
const max_sample_rate_hz = 48_000.0;

const max_components = 6;
const max_amplitude = 2.0;

/// Spodní okraj grafu v decibelech; menší hodnoty se oříznou.
const db_floor = -120.0;

/// Do tohoto počtu binů kreslíme spektrum jako jednotlivé čáry s puntíky,
/// aby bylo vidět, že spektrum je diskrétní. Při větším počtu by splývaly.
const max_stem_bins = 129;

/// Kterým algoritmem se spektrum počítá.
const Algorithm = enum { fft, dft };

/// Vodorovná osa spektra.
const FrequencyAxis = enum { hertz, bin };

/// Všechno, od čeho závisí výsledek výpočtu. Když se změní, počítá se znovu.
const Settings = struct {
    /// Složky signálu; platných je prvních `component_count`.
    components: [max_components]Component,
    component_count: usize,
    dc_offset: f64,
    noise_amplitude: f64,
    noise_seed: u64,
    sample_rate_hz: f64,
    /// Typ podle šířky `usize` (64 bitů na desktopu, 32 ve WebAssembly),
    /// aby šel přímo použít jako posun v `1 << fft_exponent`.
    fft_exponent: std.math.Log2Int(usize),
    algorithm: Algorithm,

    fn activeComponents(self: *Settings) []Component {
        return self.components[0..self.component_count];
    }

    /// Popis signálu pro DSP; půjčuje si pole složek z nastavení.
    fn signalSpec(self: *const Settings) dsp.signal.SignalSpec {
        return .{
            .components = self.components[0..self.component_count],
            .dc_offset = self.dc_offset,
            .noise_amplitude = self.noise_amplitude,
            .noise_seed = self.noise_seed,
        };
    }

    fn fftSize(self: Settings) usize {
        return @as(usize, 1) << self.fft_exponent;
    }

    /// Porovná jen platné složky (zbytek pole je nepodstatný).
    fn eql(a: *const Settings, b: *const Settings) bool {
        if (a.component_count != b.component_count) return false;
        for (a.components[0..a.component_count], b.components[0..b.component_count]) |x, y| {
            if (!std.meta.eql(x, y)) return false;
        }
        return a.dc_offset == b.dc_offset and a.noise_amplitude == b.noise_amplitude and
            a.noise_seed == b.noise_seed and a.sample_rate_hz == b.sample_rate_hz and
            a.fft_exponent == b.fft_exponent and a.algorithm == b.algorithm;
    }
};

/// Výsledek výpočtu pro jedno nastavení. Paměť vlastní tato struktura.
const Computed = struct {
    /// Nastavení, pro které výsledek platí.
    settings: Settings,
    samples: []f64,
    lines: []SpectrumLine,
    /// Jak dlouho trvala samotná transformace.
    transform_ns: u64,
    /// Největší rozdíl mezi původním vzorkem a vzorkem po cestě tam a zpět
    /// (FFT a zpětná FFT). Měl by být na úrovni zaokrouhlovacích chyb.
    round_trip_error: f64,

    fn deinit(self: *Computed, allocator: Allocator) void {
        allocator.free(self.samples);
        allocator.free(self.lines);
        self.* = undefined;
    }
};

/// Stav záložky.
pub const SpectrumTab = struct {
    settings: Settings = default_settings,
    amplitude_scale: common.AmplitudeScale = .linear,
    frequency_axis: FrequencyAxis = .hertz,
    computed: ?Computed = null,
    /// Osa x sdílená grafy amplitudy a fáze.
    frequency_link: plot.LinkedAxis = .{},

    pub fn deinit(self: *SpectrumTab, allocator: Allocator) void {
        if (self.computed) |*computed| computed.deinit(allocator);
        self.computed = null;
    }

    /// Nakreslí obsah záložky.
    pub fn show(self: *SpectrumTab, allocator: Allocator) !void {
        var layout = common.Layout.begin(@src());
        defer layout.end();

        layout.beginControls();
        self.showControls();
        layout.beginPlots();

        try self.updateComputed(allocator);
        if (self.computed) |*computed| self.showPlots(&layout, computed);
    }

    /// Přepočítá signál a spektrum, pokud se od posledního výpočtu změnilo nastavení.
    fn updateComputed(self: *SpectrumTab, allocator: Allocator) !void {
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

    fn showControls(self: *SpectrumTab) void {
        showSamplingControls(&self.settings);
        common.separator(@src());
        showSignalControls(&self.settings);
        common.separator(@src());
        self.showAlgorithmControls();
        common.separator(@src());
        self.showViewControls();
    }

    fn showAlgorithmControls(self: *SpectrumTab) void {
        common.heading(@src(), "Výpočet");
        {
            var row = common.row(@src());
            defer row.deinit();
            _ = common.radioValue(@src(), Algorithm, &self.settings.algorithm, .fft, "FFT (rychlá)");
            _ = common.radioValue(@src(), Algorithm, &self.settings.algorithm, .dft, "DFT (podle definice)");
        }
        if (self.computed) |computed| {
            if (builtin.cpu.arch.isWasm()) {
                // Webový backend DVUI měří čas jen po celých milisekundách
                // (`performance.now()` ořízne na celé číslo), mikrosekundy
                // by tu předstíraly přesnost, kterou nemáme.
                const milliseconds = computed.transform_ns / std.time.ns_per_ms;
                if (milliseconds == 0) {
                    common.text(@src(), "Doba transformace: pod 1 ms", .{});
                } else {
                    common.text(@src(), "Doba transformace: {d} ms", .{milliseconds});
                }
                common.weak(@src(), "V prohlížeči se čas měří jen po celých ms.");
            } else {
                const microseconds = @as(f64, @floatFromInt(computed.transform_ns)) / 1000;
                common.text(@src(), "Doba transformace: {d:.0} µs", .{microseconds});
            }
            common.text(@src(), "Zpětná FFT vrátí signál s chybou nejvýš {e:.1}", .{computed.round_trip_error});
        }
        common.weak(@src(), "Obě metody dávají stejné spektrum, liší se jen rychlostí.");
    }

    fn showViewControls(self: *SpectrumTab) void {
        common.heading(@src(), "Zobrazení");
        {
            var row = common.row(@src());
            defer row.deinit();
            common.inlineText(@src(), "Amplituda:");
            _ = common.radioValue(@src(), common.AmplitudeScale, &self.amplitude_scale, .linear, "lineárně");
            _ = common.radioValue(@src(), common.AmplitudeScale, &self.amplitude_scale, .decibel, "v dB");
        }
        {
            var row = common.row(@src());
            defer row.deinit();
            common.inlineText(@src(), "Osa spektra:");
            _ = common.radioValue(@src(), FrequencyAxis, &self.frequency_axis, .hertz, "Hz");
            _ = common.radioValue(@src(), FrequencyAxis, &self.frequency_axis, .bin, "číslo binu");
        }
        common.weak(@src(), common.plot_help);
    }

    // -----------------------------------------------------------------------
    // Grafy
    // -----------------------------------------------------------------------

    fn showPlots(self: *SpectrumTab, layout: *const common.Layout, computed: *const Computed) void {
        // Tři grafy pod sebou si rozdělí dostupnou výšku rovným dílem.
        const height = layout.plotHeight(3);

        common.plotTitle(@src(), "Časový průběh");
        showTimePlot(computed, height);

        common.plotTitle(@src(), "Amplitudové spektrum");
        self.showAmplitudePlot(computed, height);

        common.plotTitle(@src(), "Fázové spektrum (vztaženo ke kosinu, sinus má −90°)");
        self.showPhasePlot(computed, height);
    }

    fn showAmplitudePlot(self: *SpectrumTab, computed: *const Computed, height: f32) void {
        const points = plot.allocPoints(computed.lines.len) orelse return;
        for (points, computed.lines) |*point, line| {
            point.* = .{
                .x = frequencyCoordinate(line, self.frequency_axis),
                .y = switch (self.amplitude_scale) {
                    .linear => line.amplitude,
                    .decibel => @max(line.amplitude_db, db_floor),
                },
            };
        }

        const y_label = switch (self.amplitude_scale) {
            .linear => "amplituda",
            .decibel => "amplituda [dB]",
        };
        var amplitude_plot = plot.Plot.init(@src(), .{
            .height = height,
            .x_label = frequencyAxisLabel(self.frequency_axis),
            .y_label = y_label,
            .linked_x = &self.frequency_link,
        });
        // Čáry od nuly dávají smysl jen v lineárním měřítku a při málo binech.
        const draw_stems = self.amplitude_scale == .linear and computed.lines.len <= max_stem_bins;
        if (draw_stems) {
            amplitude_plot.stems("amplituda", points, .{ .radius = 3 });
        } else {
            amplitude_plot.line("amplituda", points, .{});
        }
        amplitude_plot.show();
    }

    fn showPhasePlot(self: *SpectrumTab, computed: *const Computed, height: f32) void {
        const points = plot.allocPoints(computed.lines.len) orelse return;
        for (points, computed.lines) |*point, line| {
            point.* = .{ .x = frequencyCoordinate(line, self.frequency_axis), .y = line.phase_deg };
        }
        var phase_plot = plot.Plot.init(@src(), .{
            .height = height,
            .x_label = frequencyAxisLabel(self.frequency_axis),
            .y_label = "fáze [°]",
            .include_y = &.{ -180, 180 },
            .linked_x = &self.frequency_link,
        });
        phase_plot.stems("fáze", points, .{ .radius = 2 });
        phase_plot.show();
    }
};

/// Výchozí nastavení: fs = 1024 Hz a N = 1024, takže biny jsou přesně
/// po 1 Hz a obě sinusovky padnou přesně do svého binu.
const default_settings: Settings = .{
    .components = defaultComponents(),
    .component_count = 2,
    .dc_offset = 0,
    .noise_amplitude = 0,
    .noise_seed = 1,
    .sample_rate_hz = 1024,
    .fft_exponent = 10,
    .algorithm = .fft,
};

/// Dvě sinusovky (50 Hz a 120 Hz), zbytek pole je zatím nepoužitý.
fn defaultComponents() [max_components]Component {
    var components: [max_components]Component = @splat(newComponent(0, 0));
    components[0] = newComponent(50, 1);
    components[1] = newComponent(120, 0.5);
    return components;
}

fn newComponent(frequency_hz: f64, amplitude: f64) Component {
    return .{ .enabled = true, .waveform = .sine, .frequency_hz = frequency_hz, .amplitude = amplitude, .phase_deg = 0 };
}

fn compute(allocator: Allocator, settings: Settings) !Computed {
    const fft_size = settings.fftSize();
    const samples = try dsp.signal.generate(allocator, settings.signalSpec(), settings.sample_rate_hz, fft_size);
    errdefer allocator.free(samples);
    const input = try dsp.fft.realToComplex(allocator, samples);
    defer allocator.free(input);

    const clock = dvui.currentWindow().backend;
    const start = clock.nanoTime();
    const output = switch (settings.algorithm) {
        .fft => try dsp.fft.fft(allocator, input),
        .dft => try dsp.fft.dft(allocator, input),
    };
    defer allocator.free(output);
    const transform_ns: u64 = @intCast(@max(0, clock.nanoTime() - start));

    // Při tažení posuvníku se počítá v každém snímku, proto jen úroveň debug.
    log.debug("spectrum computed algorithm={s} fft_size={d} sample_rate_hz={d} transform_time_us={d}", .{
        @tagName(settings.algorithm), fft_size, settings.sample_rate_hz, transform_ns / 1000,
    });

    const restored = try dsp.fft.ifft(allocator, output);
    defer allocator.free(restored);

    return .{
        .settings = settings,
        .round_trip_error = maxDifference(samples, restored),
        .samples = samples,
        // Bez okna je součet vah roven počtu vzorků.
        .lines = try dsp.spectrum.oneSidedSpectrum(allocator, output, settings.sample_rate_hz, @floatFromInt(fft_size)),
        .transform_ns = transform_ns,
    };
}

/// Největší vzdálenost mezi původními vzorky a vzorky obnovenými zpětnou FFT.
fn maxDifference(samples: []const f64, restored: []const Complex) f64 {
    var largest: f64 = 0;
    for (samples, restored) |sample, value| {
        largest = @max(largest, value.sub(.init(sample, 0)).magnitude());
    }
    return largest;
}

fn showSamplingControls(settings: *Settings) void {
    common.heading(@src(), "Vzorkování");
    _ = common.slider(@src(), "fs", &settings.sample_rate_hz, .{
        .min = min_sample_rate_hz,
        .max = max_sample_rate_hz,
        .logarithmic = true,
        .step = 1,
        .suffix = "Hz",
    });

    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();
        const sizes = comptime fftSizeNames();
        var index: usize = settings.fft_exponent - min_fft_exponent;
        if (dvui.dropdown(@src(), &sizes, .{ .choice = &index }, .{}, .{ .min_size_content = .{ .w = 110 }, .gravity_y = 0.5 })) {
            settings.fft_exponent = @intCast(index + min_fft_exponent);
        }
        common.inlineText(@src(), "délka FFT (N)");
    }

    const fft_size: f64 = @floatFromInt(settings.fftSize());
    var buffer: [32]u8 = undefined;
    common.text(@src(), "Rozestup binů fs/N: {s}", .{common.formatHz(&buffer, settings.sample_rate_hz / fft_size)});
    common.text(@src(), "Délka záznamu N/fs: {d:.1} ms", .{1000 * fft_size / settings.sample_rate_hz});
    common.text(@src(), "Nyquistova frekvence fs/2: {s}", .{common.formatHz(&buffer, settings.sample_rate_hz / 2)});

    clampFrequencies(settings);
}

/// Popisky nabídky délek FFT („1024 = 2^10“).
fn fftSizeNames() [max_fft_exponent - min_fft_exponent + 1][]const u8 {
    var names: [max_fft_exponent - min_fft_exponent + 1][]const u8 = undefined;
    for (&names, min_fft_exponent..) |*name, exponent| {
        name.* = std.fmt.comptimePrint("{d} = 2^{d}", .{ 1 << exponent, exponent });
    }
    return names;
}

/// Frekvence složek držíme pod Nyquistovou frekvencí; co se stane nad ní,
/// ukazuje záložka o vzorkování a aliasingu.
fn clampFrequencies(settings: *Settings) void {
    const nyquist_hz = settings.sample_rate_hz / 2;
    for (settings.activeComponents()) |*component| {
        component.frequency_hz = @min(component.frequency_hz, nyquist_hz);
    }
}

fn showSignalControls(settings: *Settings) void {
    common.heading(@src(), "Signál");
    const nyquist_hz = settings.sample_rate_hz / 2;

    // Složku nelze odebrat uprostřed procházení seznamu, proto si jen
    // zapamatujeme její index a odebereme ji až po cyklu.
    var index_to_remove: ?usize = null;
    for (settings.activeComponents(), 0..) |*component, index| {
        // Krok 0 znamená jemný posuvník.
        if (common.componentControls(index, component, nyquist_hz, 0)) index_to_remove = index;
    }
    if (index_to_remove) |index| {
        // Posuneme následující složky o jedno místo dopředu.
        const components = settings.activeComponents();
        std.mem.copyForwards(Component, components[index .. components.len - 1], components[index + 1 ..]);
        settings.component_count -= 1;
    }

    const can_add = settings.component_count < max_components;
    if (dvui.button(@src(), "Přidat složku", .{ .grayed = !can_add }, .{ .padding = .all(4) }) and can_add) {
        settings.components[settings.component_count] = newComponent(nyquist_hz / 4, 0.5);
        settings.component_count += 1;
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .{ .h = 6 } });
    _ = common.slider(@src(), "stejnosměrná složka", &settings.dc_offset, .{ .min = -max_amplitude, .max = max_amplitude, .step = 0.01 });
    _ = common.slider(@src(), "šum", &settings.noise_amplitude, .{ .min = 0, .max = max_amplitude, .step = 0.01 });
    if (dvui.button(@src(), "Nový šum", .{}, .{ .padding = .all(4) })) settings.noise_seed += 1;
}

fn showTimePlot(computed: *const Computed, height: f32) void {
    const sample_rate_hz = computed.settings.sample_rate_hz;
    const points = plot.allocPoints(computed.samples.len) orelse return;
    for (points, computed.samples, 0..) |*point, sample, index| {
        point.* = .{ .x = 1000 * @as(f64, @floatFromInt(index)) / sample_rate_hz, .y = sample };
    }
    var time_plot = plot.Plot.init(@src(), .{ .height = height, .x_label = "čas [ms]", .y_label = "hodnota" });
    time_plot.line("signál", points, .{});
    time_plot.show();
}

fn frequencyCoordinate(line: SpectrumLine, frequency_axis: FrequencyAxis) f64 {
    return switch (frequency_axis) {
        .hertz => line.frequency_hz,
        .bin => @floatFromInt(line.bin),
    };
}

fn frequencyAxisLabel(frequency_axis: FrequencyAxis) []const u8 {
    return switch (frequency_axis) {
        .hertz => "frekvence [Hz]",
        .bin => "číslo binu k",
    };
}
