//! Okénkové funkce a jejich vlastnosti.
//!
//! FFT předpokládá, že záznam se donekonečna opakuje. Pokud signál nemá
//! v záznamu celý počet period, vznikne na hranici opakování skok a jeho
//! energie se rozlije do celého spektra – tomu se říká prosakování (leakage).
//! Okno záznam na krajích plynule ztlumí k nule, takže skok zmizí. Cenou je
//! širší hlavní lalok: čára ve spektru je rozmazanější.

const std = @import("std");
const Allocator = std.mem.Allocator;
const pi = std.math.pi;

const fft_module = @import("fft.zig");
const toDecibels = @import("spectrum.zig").toDecibels;

/// Druh okna.
pub const WindowKind = enum {
    /// Žádné okno – všechny vzorky mají váhu 1.
    rectangular,
    hann,
    hamming,
    blackman,
};

/// Všechna okna v pořadí od nejužšího hlavního laloku po nejnižší postranní laloky.
pub const all_windows = [_]WindowKind{ .rectangular, .hann, .hamming, .blackman };

/// Všechna zde použitá okna jsou součtem nejvýš tří kosinusovek:
///
/// ```text
/// w[n] = a0 − a1·cos(2πn/N) + a2·cos(4πn/N)
/// ```
///
/// Liší se jen koeficienty.
const CosineTerms = struct {
    a0: f64,
    a1: f64,
    a2: f64,
};

fn cosineTerms(kind: WindowKind) CosineTerms {
    return switch (kind) {
        .rectangular => .{ .a0 = 1, .a1 = 0, .a2 = 0 },
        .hann => .{ .a0 = 0.5, .a1 = 0.5, .a2 = 0 },
        // Hamming posunul poměr tak, aby se vyrušil první postranní lalok.
        .hamming => .{ .a0 = 0.54, .a1 = 0.46, .a2 = 0 },
        .blackman => .{ .a0 = 0.42, .a1 = 0.5, .a2 = 0.08 },
    };
}

/// Koeficienty okna délky `length` pro spektrální analýzu.
///
/// Jde o tzv. periodické okno (dělí se `N`, ne `N − 1`): je to jedna perioda
/// kosinusovek, takže okno se při opakování záznamu plynule navazuje.
/// Pro spektrální analýzu je to správná volba – nuly spektra okna pak padnou
/// přesně na celé biny. Vrácené pole uvolní volající.
pub fn window(allocator: Allocator, kind: WindowKind, length: usize) Allocator.Error![]f64 {
    return cosineWindow(allocator, kind, length, toF64(length));
}

/// Symetrické okno délky `length` pro návrh filtrů (dělí se `N − 1`).
///
/// První a poslední vzorek jsou si rovny, takže filtr navržený s tímto oknem
/// má souměrné koeficienty a tedy lineární fázi. Vrácené pole uvolní volající.
pub fn symmetricWindow(allocator: Allocator, kind: WindowKind, length: usize) Allocator.Error![]f64 {
    if (length <= 1) {
        const ones = try allocator.alloc(f64, length);
        @memset(ones, 1);
        return ones;
    }
    return cosineWindow(allocator, kind, length, toF64(length - 1));
}

/// Společný výpočet obou druhů oken; `period` je počet vzorků, na který
/// připadne jedna perioda kosinusovek.
fn cosineWindow(allocator: Allocator, kind: WindowKind, length: usize, period: f64) Allocator.Error![]f64 {
    const terms = cosineTerms(kind);
    const coefficients = try allocator.alloc(f64, length);
    for (coefficients, 0..) |*coefficient, n| {
        const angle = 2 * pi * toF64(n) / period;
        coefficient.* = terms.a0 - terms.a1 * @cos(angle) + terms.a2 * @cos(2 * angle);
    }
    return coefficients;
}

/// Vynásobí signál oknem vzorek po vzorku. Signál i okno musí mít stejnou
/// délku. Vrácené pole uvolní volající.
pub fn applyWindow(allocator: Allocator, samples: []const f64, coefficients: []const f64) Allocator.Error![]f64 {
    std.debug.assert(samples.len == coefficients.len);
    const output = try allocator.alloc(f64, samples.len);
    for (output, samples, coefficients) |*result, sample, weight| result.* = sample * weight;
    return output;
}

/// Doplní signál nulami na délku `length` (nesmí být kratší než signál).
///
/// Delší FFT pak vrátí víc bodů spektra, které leží mezi původními biny.
/// Spektrum se tím jen hustěji „navzorkuje“ – nové informace nepřibudou
/// a dvě blízké čáry se tím od sebe neoddělí. Vrácené pole uvolní volající.
pub fn zeroPad(allocator: Allocator, samples: []const f64, length: usize) Allocator.Error![]f64 {
    std.debug.assert(length >= samples.len);
    const padded = try allocator.alloc(f64, length);
    @memcpy(padded[0..samples.len], samples);
    @memset(padded[samples.len..], 0);
    return padded;
}

/// Spektrum samotného okna: jak by ve spektru vypadala jedna čistá sinusovka.
pub const WindowResponse = struct {
    /// Vzdálenost od středu čáry v binech původní délky okna (0 až N/2).
    offsets_bins: []f64,
    /// Útlum vůči středu čáry v decibelech (střed má 0 dB).
    magnitude_db: []f64,

    pub fn deinit(self: *WindowResponse, allocator: Allocator) void {
        allocator.free(self.offsets_bins);
        allocator.free(self.magnitude_db);
        self.* = undefined;
    }
};

/// Spočítá spektrum okna. Okno se doplní nulami na `fft_size` vzorků, aby
/// bylo vidět i to, co leží mezi celými biny (tvar laloků).
/// Výsledek uvolní volající přes `WindowResponse.deinit`.
pub fn windowResponse(
    allocator: Allocator,
    coefficients: []const f64,
    fft_size: usize,
) fft_module.FftError!WindowResponse {
    const length = coefficients.len;
    const padded = try zeroPad(allocator, coefficients, fft_size);
    defer allocator.free(padded);
    const complex_samples = try fft_module.realToComplex(allocator, padded);
    defer allocator.free(complex_samples);
    const spectrum = try fft_module.fft(allocator, complex_samples);
    defer allocator.free(spectrum);

    // Na nulové frekvenci je spektrum okna rovno součtu jeho koeficientů;
    // tím dělíme, aby střed čáry vyšel 0 dB.
    const total = sum(coefficients);
    const bins_per_point = toF64(length) / toF64(fft_size);

    const point_count = fft_size / 2 + 1;
    const offsets_bins = try allocator.alloc(f64, point_count);
    errdefer allocator.free(offsets_bins);
    const magnitude_db = try allocator.alloc(f64, point_count);
    for (offsets_bins, magnitude_db, spectrum[0..point_count], 0..) |*offset, *db, value, index| {
        offset.* = toF64(index) * bins_per_point;
        db.* = toDecibels(value.magnitude() / total);
    }
    return .{ .offsets_bins = offsets_bins, .magnitude_db = magnitude_db };
}

/// Číselné vlastnosti okna.
pub const WindowProperties = struct {
    /// Průměrná hodnota okna. O tolik okno zeslabí amplitudu sinusovky,
    /// proto se jí spektrum při výpočtu amplitudy dělí.
    coherent_gain: f64,
    /// Vzdálenost první nuly od středu čáry v binech (poloviční šířka hlavního laloku).
    main_lobe_half_width_bins: f64,
    /// Nejvyšší postranní lalok v decibelech vůči středu čáry.
    highest_side_lobe_db: f64,
};

/// Změří vlastnosti okna z jeho spektra.
pub fn analyzeWindow(coefficients: []const f64, response: WindowResponse) WindowProperties {
    const db = response.magnitude_db;
    // Prázdné spektrum nemá laloky (a `db.len - 1` by podteklo).
    if (db.len == 0 or coefficients.len == 0) {
        return .{ .coherent_gain = 0, .main_lobe_half_width_bins = 0, .highest_side_lobe_db = -std.math.inf(f64) };
    }

    // Hlavní lalok končí prvním místním minimem (nulou) spektra.
    var first_null = db.len - 1;
    var i: usize = 1;
    while (i + 1 < db.len) : (i += 1) {
        if (db[i] <= db[i - 1] and db[i] <= db[i + 1]) {
            first_null = i;
            break;
        }
    }

    // Za první nulou už jsou jen postranní laloky; hledáme ten nejvyšší.
    var highest_side_lobe_db = -std.math.inf(f64);
    for (db[first_null..]) |value| highest_side_lobe_db = @max(highest_side_lobe_db, value);

    return .{
        .coherent_gain = sum(coefficients) / toF64(coefficients.len),
        .main_lobe_half_width_bins = response.offsets_bins[first_null],
        .highest_side_lobe_db = highest_side_lobe_db,
    };
}

/// Součet prvků pole.
pub fn sum(values: []const f64) f64 {
    var total: f64 = 0;
    for (values) |value| total += value;
    return total;
}

fn toF64(value: usize) f64 {
    return @floatFromInt(value);
}

const testing = std.testing;
const test_tolerance = 1e-12;
const signal = @import("signal.zig");
const spectrum_module = @import("spectrum.zig");

fn properties(kind: WindowKind) !WindowProperties {
    const allocator = testing.allocator;
    const coefficients = try window(allocator, kind, 64);
    defer allocator.free(coefficients);
    var response = try windowResponse(allocator, coefficients, 64 * 64);
    defer response.deinit(allocator);
    return analyzeWindow(coefficients, response);
}

/// Sinusovka s amplitudou 1. Vzorkovací frekvence = délka, takže 1 Hz = 1 bin.
fn sineSamples(frequency_bins: f64, length: usize) ![]f64 {
    const components = [_]signal.Component{.{
        .enabled = true,
        .waveform = .sine,
        .frequency_hz = frequency_bins,
        .amplitude = 1,
        .phase_deg = 0,
    }};
    const spec: signal.SignalSpec = .{ .components = &components, .dc_offset = 0, .noise_amplitude = 0, .noise_seed = 1 };
    return signal.generate(testing.allocator, spec, toF64(length), length);
}

/// FFT reálného signálu převedená na jednostranné spektrum.
fn spectrumOf(samples: []const f64, sample_rate_hz: f64, window_sum: f64) ![]spectrum_module.SpectrumLine {
    const allocator = testing.allocator;
    const complex_samples = try fft_module.realToComplex(allocator, samples);
    defer allocator.free(complex_samples);
    const transformed = try fft_module.fft(allocator, complex_samples);
    defer allocator.free(transformed);
    return spectrum_module.oneSidedSpectrum(allocator, transformed, sample_rate_hz, window_sum);
}

test "hann shape" {
    const hann = try window(testing.allocator, .hann, 8);
    defer testing.allocator.free(hann);
    try testing.expectApproxEqAbs(0.0, hann[0], test_tolerance);
    try testing.expectApproxEqAbs(1.0, hann[4], test_tolerance);
    try testing.expectApproxEqAbs(0.5, hann[2], test_tolerance);
    // Periodické okno je souměrné kolem prostředního vzorku: w[n] = w[N − n].
    try testing.expectApproxEqAbs(hann[1], hann[7], test_tolerance);
}

test "symmetric hann shape" {
    const hann = try symmetricWindow(testing.allocator, .hann, 9);
    defer testing.allocator.free(hann);
    try testing.expectApproxEqAbs(0.0, hann[0], test_tolerance);
    try testing.expectApproxEqAbs(0.0, hann[8], test_tolerance);
    try testing.expectApproxEqAbs(1.0, hann[4], test_tolerance);
    const single = try symmetricWindow(testing.allocator, .hann, 1);
    defer testing.allocator.free(single);
    try testing.expectEqualSlices(f64, &.{1}, single);
}

test "rectangular is all ones" {
    const rectangular = try window(testing.allocator, .rectangular, 4);
    defer testing.allocator.free(rectangular);
    try testing.expectEqualSlices(f64, &.{ 1, 1, 1, 1 }, rectangular);
}

test "coherent gain equals a0" {
    try testing.expectApproxEqAbs(1.0, (try properties(.rectangular)).coherent_gain, test_tolerance);
    try testing.expectApproxEqAbs(0.5, (try properties(.hann)).coherent_gain, test_tolerance);
    try testing.expectApproxEqAbs(0.54, (try properties(.hamming)).coherent_gain, test_tolerance);
    try testing.expectApproxEqAbs(0.42, (try properties(.blackman)).coherent_gain, test_tolerance);
}

test "main lobe widths" {
    const Case = struct { kind: WindowKind, half_width: f64 };
    const cases = [_]Case{
        .{ .kind = .rectangular, .half_width = 1 },
        .{ .kind = .hann, .half_width = 2 },
        .{ .kind = .hamming, .half_width = 2 },
        .{ .kind = .blackman, .half_width = 3 },
    };
    for (cases) |case| {
        const measured = (try properties(case.kind)).main_lobe_half_width_bins;
        try testing.expectApproxEqAbs(case.half_width, measured, 1e-9);
    }
}

test "side lobe levels match textbook values" {
    const Case = struct { kind: WindowKind, level_db: f64 };
    const cases = [_]Case{
        .{ .kind = .rectangular, .level_db = -13.3 },
        .{ .kind = .hann, .level_db = -31.5 },
        .{ .kind = .hamming, .level_db = -42.7 },
        .{ .kind = .blackman, .level_db = -58.1 },
    };
    for (cases) |case| {
        const measured = (try properties(case.kind)).highest_side_lobe_db;
        try testing.expectApproxEqAbs(case.level_db, measured, 0.5);
    }
}

test "window gain is compensated" {
    // Sinus s amplitudou 1 přesně v binu 8; po oknu i po doplnění nulami
    // musí spektrum ukázat amplitudu 1.
    const allocator = testing.allocator;
    const samples = try sineSamples(8, 64);
    defer allocator.free(samples);
    const hann = try window(allocator, .hann, 64);
    defer allocator.free(hann);
    const windowed = try applyWindow(allocator, samples, hann);
    defer allocator.free(windowed);
    const padded = try zeroPad(allocator, windowed, 256);
    defer allocator.free(padded);
    const lines = try spectrumOf(padded, 64, sum(hann));
    defer allocator.free(lines);
    // Po čtyřnásobném doplnění nulami je frekvence 8 v binu 32.
    try testing.expectApproxEqAbs(8.0, lines[32].frequency_hz, test_tolerance);
    try testing.expectApproxEqAbs(1.0, lines[32].amplitude, 1e-9);
}

test "between bins rectangular loses about four dB" {
    // Frekvence přesně mezi biny: obdélníkové okno ukáže nejvyšší čáru
    // asi o 3,9 dB níž, než je skutečná amplituda (tzv. scalloping loss).
    // Záznam je dlouhý a frekvence daleko od nuly, aby výsledek neovlivnilo
    // prosakování zrcadlové čáry na záporné frekvenci.
    const allocator = testing.allocator;
    const samples = try sineSamples(100.5, 1024);
    defer allocator.free(samples);
    const lines = try spectrumOf(samples, 1024, 1024);
    defer allocator.free(lines);
    var peak_db = -std.math.inf(f64);
    for (lines) |line| peak_db = @max(peak_db, line.amplitude_db);
    try testing.expectApproxEqAbs(-3.92, peak_db, 0.1);
}

test "zero pad appends zeros" {
    const padded = try zeroPad(testing.allocator, &.{ 1, 2 }, 4);
    defer testing.allocator.free(padded);
    try testing.expectEqualSlices(f64, &.{ 1, 2, 0, 0 }, padded);
}
