//! Záložka „Vzorkování a aliasing“: spojitý signál, jeho vzorky, obnova ze
//! vzorků a spektrum před a po vzorkování.
//!
//! Vysvětlení a návod, co zkoušet: `docs/03-vzorkovani-a-aliasing.md`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const dvui = @import("dvui");
const dsp = @import("dsp");

const common = @import("common.zig");
const plot = @import("plot.zig");

const Component = dsp.signal.Component;
const SpectrumLine = dsp.spectrum.SpectrumLine;

const log = std.log.scoped(.sampling);

const min_sample_rate_hz = 1.0;
const max_sample_rate_hz = 200.0;
const max_component_frequency_hz = 100.0;
const max_components = 3;

/// Délka zobrazeného úseku. Je to zároveň délka záznamu pro spektrum,
/// takže biny jsou po 1 Hz a celočíselné frekvence padnou přesně do binu.
const duration_s = 1.0;

/// Vzorky navíc před a za zobrazeným úsekem. Rekonstrukce potřebuje vzorky
/// z obou stran; bez nich by byla u okrajů úseku nepřesná.
const margin_s = 1.0;

/// Počet bodů, kterými kreslíme „spojitý“ signál a jeho rekonstrukci.
const display_points = 2000;

/// Spojitý signál pro spektrum nahrazujeme hodně hustým vzorkováním.
/// 2048 vzorků za 1 s je mocnina dvou, takže lze použít FFT.
const reference_rate_hz = 2048.0;

/// Spektrum kreslíme jen do této frekvence; vyšší harmonické už nejsou zajímavé.
const spectrum_max_hz = 250.0;

/// Čáry spektra slabší než tato amplituda nekreslíme, aby graf nezaplnily
/// puntíky u nuly (drobné prosakování u necelých period obdélníku apod.).
const min_drawn_amplitude = 5e-3;

const continuous_color = common.colors.gray;
const sample_color = common.colors.orange;
const reconstruction_color = common.colors.blue;
const nyquist_color = common.colors.red;
const alias_color = common.colors.red;

/// Všechno, od čeho závisí výsledek výpočtu.
const Settings = struct {
    /// Složky signálu; platných je prvních `component_count`.
    components: [max_components]Component,
    component_count: usize,
    sample_rate_hz: f64,

    fn activeComponents(self: *Settings) []Component {
        return self.components[0..self.component_count];
    }

    fn signalSpec(self: *const Settings) dsp.signal.SignalSpec {
        return .{ .components = self.components[0..self.component_count], .dc_offset = 0, .noise_amplitude = 0, .noise_seed = 1 };
    }

    /// Porovná jen platné složky (zbytek pole je nepodstatný).
    fn eql(a: *const Settings, b: *const Settings) bool {
        if (a.component_count != b.component_count or a.sample_rate_hz != b.sample_rate_hz) return false;
        for (a.components[0..a.component_count], b.components[0..b.component_count]) |x, y| {
            if (!std.meta.eql(x, y)) return false;
        }
        return true;
    }
};

/// Výsledek výpočtu pro jedno nastavení. Paměť vlastní tato struktura.
const Computed = struct {
    settings: Settings,
    /// Spojitý signál v zobrazeném úseku.
    continuous: []plot.Point,
    /// Signál obnovený ze vzorků v zobrazeném úseku.
    reconstructed: []plot.Point,
    /// Vzorky v zobrazeném úseku (čas, hodnota).
    samples: []plot.Point,
    continuous_lines: []SpectrumLine,
    sampled_lines: []SpectrumLine,

    fn deinit(self: *Computed, allocator: Allocator) void {
        allocator.free(self.continuous);
        allocator.free(self.reconstructed);
        allocator.free(self.samples);
        allocator.free(self.continuous_lines);
        allocator.free(self.sampled_lines);
        self.* = undefined;
    }
};

/// Stav záložky.
pub const SamplingTab = struct {
    /// Výchozí stav: sinusovka 5 Hz vzorkovaná 40 Hz – hluboko pod Nyquistovou
    /// frekvencí, takže vzorkování funguje. Aliasing se ukáže po zvýšení frekvence.
    settings: Settings = .{
        .components = .{ sine(5), sine(10), sine(10) },
        .component_count = 1,
        .sample_rate_hz = 40,
    },
    show_reconstruction: bool = true,
    computed: ?Computed = null,

    pub fn deinit(self: *SamplingTab, allocator: Allocator) void {
        if (self.computed) |*computed| computed.deinit(allocator);
        self.computed = null;
    }

    /// Nakreslí obsah záložky.
    pub fn show(self: *SamplingTab, allocator: Allocator) !void {
        var layout = common.Layout.begin(@src());
        defer layout.end();

        layout.beginControls();
        self.showControls();
        layout.beginPlots();

        try self.updateComputed(allocator);
        if (self.computed) |*computed| showPlots(&layout, computed, self.show_reconstruction);
    }

    /// Přepočítá vše, pokud se od posledního výpočtu změnilo nastavení.
    fn updateComputed(self: *SamplingTab, allocator: Allocator) !void {
        if (self.computed) |*computed| {
            if (computed.settings.eql(&self.settings)) return;
            computed.deinit(allocator);
            self.computed = null;
        }
        self.computed = try compute(allocator, self.settings);
    }

    fn showControls(self: *SamplingTab) void {
        showSamplingControls(&self.settings);
        common.separator(@src());
        showSignalControls(&self.settings);
        common.separator(@src());
        showAliasSummary(&self.settings);
        common.separator(@src());
        common.heading(@src(), "Zobrazení");
        _ = dvui.checkbox(@src(), &self.show_reconstruction, "Rekonstrukce ze vzorků (interpolace sinc)", .{});
        common.weak(@src(), common.plot_help);
    }
};

fn sine(frequency_hz: f64) Component {
    return .{ .enabled = true, .waveform = .sine, .frequency_hz = frequency_hz, .amplitude = 1, .phase_deg = 0 };
}

fn compute(allocator: Allocator, settings: Settings) !Computed {
    const spec = settings.signalSpec();
    const rate = settings.sample_rate_hz;

    // Vzorky: nejdřív okraj před úsekem, pak úsek, pak okraj za ním.
    // Začátek okraje je celý násobek periody vzorkování, aby jeden vzorek
    // padl přesně na čas 0.
    const margin_count: usize = @intFromFloat(@round(margin_s * rate));
    const visible_count: usize = @intFromFloat(@round(duration_s * rate));
    const start_time_s = -@as(f64, @floatFromInt(margin_count)) / rate;
    var sampled = try dsp.sampling.sample(allocator, spec, rate, start_time_s, margin_count + visible_count + margin_count);
    defer sampled.deinit(allocator);

    const continuous = try allocator.alloc(plot.Point, display_points + 1);
    errdefer allocator.free(continuous);
    const reconstructed = try allocator.alloc(plot.Point, display_points + 1);
    errdefer allocator.free(reconstructed);
    for (continuous, reconstructed, 0..) |*original, *restored, index| {
        const time_s = duration_s * @as(f64, @floatFromInt(index)) / display_points;
        original.* = .{ .x = time_s, .y = dsp.signal.valueAt(spec, time_s) };
        restored.* = .{ .x = time_s, .y = dsp.sampling.reconstruct(sampled, time_s) };
    }

    const visible_values = sampled.values[margin_count .. margin_count + visible_count];
    const samples = try allocator.alloc(plot.Point, visible_count);
    errdefer allocator.free(samples);
    for (samples, visible_values, margin_count..) |*point, value, index| {
        point.* = .{ .x = sampled.sampleTime(index), .y = value };
    }

    // Počet vzorků v úseku obecně není mocnina dvou, proto zde pomalá DFT.
    const sampled_lines = blk: {
        const input = try dsp.fft.realToComplex(allocator, visible_values);
        defer allocator.free(input);
        const output = try dsp.fft.dft(allocator, input);
        defer allocator.free(output);
        break :blk try dsp.spectrum.oneSidedSpectrum(allocator, output, rate, @floatFromInt(visible_count));
    };
    errdefer allocator.free(sampled_lines);

    const continuous_lines = blk: {
        const reference_count: usize = @intFromFloat(reference_rate_hz * duration_s);
        const reference = try dsp.signal.generate(allocator, spec, reference_rate_hz, reference_count);
        defer allocator.free(reference);
        const input = try dsp.fft.realToComplex(allocator, reference);
        defer allocator.free(input);
        const output = try dsp.fft.fft(allocator, input);
        defer allocator.free(output);
        const all_lines = try dsp.spectrum.oneSidedSpectrum(allocator, output, reference_rate_hz, @floatFromInt(reference_count));
        // Ponecháme jen čáry do `spectrum_max_hz`; jsou na začátku pole.
        var kept: usize = 0;
        while (kept < all_lines.len and all_lines[kept].frequency_hz <= spectrum_max_hz) kept += 1;
        break :blk allocator.realloc(all_lines, kept) catch |err| {
            allocator.free(all_lines);
            return err;
        };
    };

    log.debug("sampling demo computed sample_rate_hz={d} sample_count={d}", .{ rate, sampled.values.len });

    return .{
        .settings = settings,
        .continuous = continuous,
        .reconstructed = reconstructed,
        .samples = samples,
        .continuous_lines = continuous_lines,
        .sampled_lines = sampled_lines,
    };
}

// ---------------------------------------------------------------------------
// Ovládací panel
// ---------------------------------------------------------------------------

fn showSamplingControls(settings: *Settings) void {
    common.heading(@src(), "Vzorkování");
    _ = common.slider(@src(), "fs", &settings.sample_rate_hz, .{
        .min = min_sample_rate_hz,
        .max = max_sample_rate_hz,
        .step = 1,
        .suffix = "Hz",
    });
    var buffer: [32]u8 = undefined;
    common.text(@src(), "Perioda vzorkování 1/fs: {d:.1} ms", .{1000 / settings.sample_rate_hz});
    common.text(@src(), "Nyquistova frekvence fs/2: {s}", .{common.formatHz(&buffer, settings.sample_rate_hz / 2)});
}

fn showSignalControls(settings: *Settings) void {
    common.heading(@src(), "Signál");

    // Složku nelze odebrat uprostřed procházení seznamu, proto si jen
    // zapamatujeme její index a odebereme ji až po cyklu.
    var index_to_remove: ?usize = null;
    for (settings.activeComponents(), 0..) |*component, index| {
        // Celé hertzy: záznam trvá 1 s, takže pak nevzniká prosakování.
        if (common.componentControls(index, component, max_component_frequency_hz, 1)) index_to_remove = index;
    }
    if (index_to_remove) |index| {
        const components = settings.activeComponents();
        std.mem.copyForwards(Component, components[index .. components.len - 1], components[index + 1 ..]);
        settings.component_count -= 1;
    }

    const can_add = settings.component_count < max_components;
    if (dvui.button(@src(), "Přidat složku", .{ .grayed = !can_add }, .{ .padding = .all(4) }) and can_add) {
        settings.components[settings.component_count] = sine(10);
        settings.component_count += 1;
    }
}

/// U každé složky ukáže, na jaké frekvenci se objeví po navzorkování.
fn showAliasSummary(settings: *Settings) void {
    common.heading(@src(), "Po navzorkování");
    const rate = settings.sample_rate_hz;
    const arena = dvui.currentWindow().arena();
    for (settings.activeComponents(), 0..) |component, index| {
        if (!component.enabled) continue;
        const frequency = component.frequency_hz;
        const alias = dsp.sampling.aliasFrequency(frequency, rate);
        var frequency_buffer: [32]u8 = undefined;
        var alias_buffer: [32]u8 = undefined;
        const is_alias = @abs(alias - frequency) > 1e-9;
        const message = std.fmt.allocPrint(arena, "Složka {d} ({s}): {s} se jeví jako {s}{s}", .{
            index + 1,
            common.waveformName(component.waveform),
            common.formatHz(&frequency_buffer, frequency),
            common.formatHz(&alias_buffer, alias),
            if (is_alias) " (alias)" else "",
        }) catch continue;
        if (is_alias) {
            common.coloredText(@src(), alias_color, message);
        } else {
            common.coloredText(@src(), dvui.themeGet().text, message);
        }
    }
    common.weak(@src(), "Frekvence nad fs/2 se zrcadlí kolem násobků fs/2. U obdélníku, pily " ++
        "a trojúhelníku se takto překládají i vyšší harmonické.");
}

// ---------------------------------------------------------------------------
// Grafy
// ---------------------------------------------------------------------------

fn showPlots(layout: *const common.Layout, computed: *const Computed, show_reconstruction: bool) void {
    const height = layout.plotHeight(2);

    common.plotTitle(@src(), "Spojitý signál, jeho vzorky a signál obnovený ze vzorků");
    showTimePlot(computed, show_reconstruction, height);

    common.plotTitle(@src(), "Amplitudové spektrum před a po navzorkování");
    showSpectrumPlot(computed, height);
}

fn showTimePlot(computed: *const Computed, show_reconstruction: bool, height: f32) void {
    var time_plot = plot.Plot.init(@src(), .{
        .height = height,
        .x_label = "čas [s]",
        .y_label = "",
        .hover_y_label = "hodnota",
        .legend = true,
    });
    time_plot.line("spojitý signál", computed.continuous, .{ .color = continuous_color });
    if (show_reconstruction) {
        time_plot.line("rekonstrukce ze vzorků", computed.reconstructed, .{ .color = reconstruction_color, .width = 2 });
    }
    time_plot.stems("vzorky", computed.samples, .{ .color = sample_color, .radius = 3.5 });
    time_plot.show();
}

fn showSpectrumPlot(computed: *const Computed, height: f32) void {
    const rate = computed.settings.sample_rate_hz;
    var spectrum_plot = plot.Plot.init(@src(), .{
        .height = height,
        .x_label = "frekvence [Hz]",
        .y_label = "amplituda",
        .include_x = &.{0},
        .include_y = &.{0},
        .legend = true,
    });
    spectrum_plot.stems("spojitý signál", visibleLines(computed.continuous_lines) orelse return, .{ .color = continuous_color, .radius = 4 });
    spectrum_plot.stems("po navzorkování", visibleLines(computed.sampled_lines) orelse return, .{ .color = sample_color, .radius = 3 });
    spectrum_plot.verticalLine("Nyquistova frekvence fs/2", rate / 2, .{ .color = nyquist_color, .dashed = true });
    spectrum_plot.verticalLine("vzorkovací frekvence fs", rate, .{
        .color = continuous_color,
        .dashed = true,
        .dash_length = 4,
        .gap_length = 3,
    });
    spectrum_plot.show();
}

/// Body pro graf spektra bez čar s téměř nulovou amplitudou.
fn visibleLines(lines: []const SpectrumLine) ?[]plot.Point {
    var count: usize = 0;
    for (lines) |line| {
        if (line.amplitude > min_drawn_amplitude) count += 1;
    }
    const points = plot.allocPoints(count) orelse return null;
    var index: usize = 0;
    for (lines) |line| {
        if (line.amplitude <= min_drawn_amplitude) continue;
        points[index] = .{ .x = line.frequency_hz, .y = line.amplitude };
        index += 1;
    }
    return points;
}
