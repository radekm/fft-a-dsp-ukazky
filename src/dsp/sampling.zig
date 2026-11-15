//! Vzorkování spojitého signálu, aliasing a rekonstrukce ze vzorků.
//!
//! Vzorkovací věta: signál, který neobsahuje frekvence od fs/2 výš
//! (Nyquistova frekvence), lze ze vzorků přesně obnovit. Vyšší frekvence se
//! po navzorkování nedají odlišit od nižších – „převlečou se“ za ně (alias).

const std = @import("std");
const Allocator = std.mem.Allocator;
const pi = std.math.pi;

const signal = @import("signal.zig");
const SignalSpec = signal.SignalSpec;

/// Navzorkovaný signál: vzorek s indexem `n` patří času
/// `start_time_s + n / sample_rate_hz`.
pub const SampledSignal = struct {
    sample_rate_hz: f64,
    start_time_s: f64,
    /// Hodnoty vzorků; vlastní je tato struktura.
    values: []f64,

    pub fn deinit(self: *SampledSignal, allocator: Allocator) void {
        allocator.free(self.values);
        self.* = undefined;
    }

    /// Čas vzorku s daným indexem.
    pub fn sampleTime(self: SampledSignal, index: usize) f64 {
        return self.start_time_s + toF64(index) / self.sample_rate_hz;
    }
};

/// Navzorkuje signál: `count` vzorků od času `start_time_s`.
/// Výsledek uvolní volající přes `SampledSignal.deinit`.
pub fn sample(
    allocator: Allocator,
    spec: SignalSpec,
    sample_rate_hz: f64,
    start_time_s: f64,
    count: usize,
) Allocator.Error!SampledSignal {
    const values = try allocator.alloc(f64, count);
    for (values, 0..) |*value, index| {
        value.* = signal.valueAt(spec, start_time_s + toF64(index) / sample_rate_hz);
    }
    return .{ .sample_rate_hz = sample_rate_hz, .start_time_s = start_time_s, .values = values };
}

/// Frekvence, na které se po navzorkování objeví sinusovka s frekvencí
/// `frequency_hz`. Výsledek leží vždy mezi 0 a fs/2.
///
/// Sinusovky f a f + k·fs mají ve vzorcích stejné hodnoty, protože se mezi
/// dvěma vzorky liší o celý počet otáček. A sinusovka −f vypadá stejně jako f
/// (jen s opačnou fází). Stačí tedy odečíst nejbližší násobek fs a vzít
/// absolutní hodnotu – frekvence se „zrcadlí“ kolem násobků fs/2.
pub fn aliasFrequency(frequency_hz: f64, sample_rate_hz: f64) f64 {
    const nearest_multiple = @round(frequency_hz / sample_rate_hz) * sample_rate_hz;
    return @abs(frequency_hz - nearest_multiple);
}

/// Normovaná funkce sinc: sin(πx) / (πx), v nule rovna 1.
///
/// Je nulová ve všech celých číslech kromě nuly – proto rekonstrukce prochází
/// přesně vzorky.
pub fn sinc(x: f64) f64 {
    if (@abs(x) < 1e-12) return 1;
    return @sin(pi * x) / (pi * x);
}

/// Hodnota signálu obnoveného ze vzorků v čase `time_s`
/// (Whittakerova–Shannonova interpolace):
///
/// ```text
/// x(t) = Σ x[n] · sinc(fs · (t − tₙ))
/// ```
///
/// Každý vzorek přispívá jednou funkcí sinc vycentrovanou na svůj čas.
/// Přesná je jen pro nekonečně mnoho vzorků; u konečného záznamu je obnova
/// nepřesná u okrajů, proto se má vyhodnocovat jen uprostřed záznamu.
pub fn reconstruct(sampled: SampledSignal, time_s: f64) f64 {
    var total: f64 = 0;
    for (sampled.values, 0..) |value, index| {
        const distance_in_samples = (time_s - sampled.sampleTime(index)) * sampled.sample_rate_hz;
        total += value * sinc(distance_in_samples);
    }
    return total;
}

fn toF64(value: usize) f64 {
    return @floatFromInt(value);
}

const testing = std.testing;
const test_tolerance = 1e-9;

fn sineComponents(frequency_hz: f64) [1]signal.Component {
    return .{.{ .enabled = true, .waveform = .sine, .frequency_hz = frequency_hz, .amplitude = 1, .phase_deg = 0 }};
}

fn specOf(components: []const signal.Component) SignalSpec {
    return .{ .components = components, .dc_offset = 0, .noise_amplitude = 0, .noise_seed = 1 };
}

test "alias frequencies" {
    const Case = struct { frequency: f64, rate: f64, expected: f64 };
    const cases = [_]Case{
        .{ .frequency = 5, .rate = 40, .expected = 5 },
        .{ .frequency = 20, .rate = 40, .expected = 20 },
        .{ .frequency = 30, .rate = 40, .expected = 10 },
        .{ .frequency = 40, .rate = 40, .expected = 0 },
        .{ .frequency = 70, .rate = 40, .expected = 10 },
        .{ .frequency = 85, .rate = 40, .expected = 5 },
    };
    for (cases) |case| {
        try testing.expectApproxEqAbs(case.expected, aliasFrequency(case.frequency, case.rate), test_tolerance);
    }
}

test "sinc values" {
    try testing.expectEqual(1.0, sinc(0));
    try testing.expectApproxEqAbs(0.0, sinc(1), test_tolerance);
    try testing.expectApproxEqAbs(0.0, sinc(-3), test_tolerance);
    try testing.expectApproxEqAbs(2.0 / pi, sinc(0.5), test_tolerance);
}

test "sample times follow start and rate" {
    const components = sineComponents(1);
    var sampled = try sample(testing.allocator, specOf(&components), 4, -0.5, 4);
    defer sampled.deinit(testing.allocator);
    try testing.expectApproxEqAbs(-0.5, sampled.sampleTime(0), test_tolerance);
    try testing.expectApproxEqAbs(0.25, sampled.sampleTime(3), test_tolerance);
    // sin(2π · (−0,25)) = −1
    try testing.expectApproxEqAbs(-1.0, sampled.values[1], test_tolerance);
}

test "reconstruction passes through samples" {
    const components = sineComponents(3);
    var sampled = try sample(testing.allocator, specOf(&components), 20, 0, 40);
    defer sampled.deinit(testing.allocator);
    for (sampled.values, 0..) |value, index| {
        try testing.expectApproxEqAbs(value, reconstruct(sampled, sampled.sampleTime(index)), test_tolerance);
    }
}

test "reconstruction restores signal below nyquist" {
    // 10 Hz vzorkované 100 Hz: uprostřed dlouhého záznamu musí obnova
    // sedět i mezi vzorky.
    const components = sineComponents(10);
    const spec = specOf(&components);
    var sampled = try sample(testing.allocator, spec, 100, -5, 1000);
    defer sampled.deinit(testing.allocator);
    for (0..50) |step| {
        const time_s = 0.0013 + toF64(step) * 0.0071;
        try testing.expectApproxEqAbs(signal.valueAt(spec, time_s), reconstruct(sampled, time_s), 0.01);
    }
}

test "undersampled sine is reconstructed as its alias" {
    // 80 Hz vzorkované 100 Hz se obnoví jako 20 Hz s opačnou fází:
    // sin(2π·80·n/100) = sin(2π·(80 − 100)·n/100) = −sin(2π·20·n/100).
    const components = sineComponents(80);
    var sampled = try sample(testing.allocator, specOf(&components), 100, -5, 1000);
    defer sampled.deinit(testing.allocator);
    const alias_components = sineComponents(20);
    const alias = specOf(&alias_components);
    for (0..50) |step| {
        const time_s = 0.0013 + toF64(step) * 0.0071;
        try testing.expectApproxEqAbs(-signal.valueAt(alias, time_s), reconstruct(sampled, time_s), 0.01);
    }
}
