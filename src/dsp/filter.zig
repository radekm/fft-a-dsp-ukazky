//! Číslicové filtry: FIR navržený metodou okna a IIR bikvadratický filtr.
//!
//! Každý lineární filtr lze popsat rovnicí
//!
//! ```text
//! y[n] = b0·x[n] + b1·x[n−1] + … − a1·y[n−1] − a2·y[n−2] − …
//! ```
//!
//! FIR (konečná impulzní odezva) používá jen vstupní vzorky – koeficienty `b`
//! jsou přímo jeho impulzní odezva. IIR (nekonečná impulzní odezva) používá
//! i předchozí výstupy, díky zpětné vazbě mu stačí málo koeficientů.

const std = @import("std");
const Allocator = std.mem.Allocator;
const pi = std.math.pi;

const Complex = @import("complex.zig").Complex;
const sinc = @import("sampling.zig").sinc;
const toDecibels = @import("spectrum.zig").toDecibels;
const window_module = @import("window.zig");
const WindowKind = window_module.WindowKind;

/// Druh filtru podle toho, co propouští.
pub const FilterType = enum {
    /// Propouští frekvence pod mezní frekvencí.
    low_pass,
    /// Propouští frekvence nad mezní frekvencí.
    high_pass,
    /// Propouští pásmo kolem zvolené frekvence.
    band_pass,
};

// ---------------------------------------------------------------------------
// Konvoluce a FIR
// ---------------------------------------------------------------------------

/// Konvoluce signálu s jádrem (impulzní odezvou FIR filtru):
///
/// ```text
/// y[n] = Σ h[k] · x[n − k]      pro k = 0 … M−1
/// ```
///
/// Každý výstupní vzorek je vážený součet posledních M vstupních vzorků.
/// Vzorky před začátkem signálu bereme jako nuly, proto má začátek výstupu
/// přechodový děj. Výstup má stejnou délku jako vstup; uvolní ho volající.
pub fn convolve(allocator: Allocator, signal: []const f64, kernel: []const f64) Allocator.Error![]f64 {
    const output = try allocator.alloc(f64, signal.len);
    for (output, 0..) |*result, n| {
        var total: f64 = 0;
        // Bereme jen ty k, pro které vstupní vzorek x[n − k] existuje.
        const usable = @min(kernel.len, n + 1);
        for (kernel[0..usable], 0..) |weight, k| total += weight * signal[n - k];
        result.* = total;
    }
    return output;
}

/// Zadání FIR filtru navrženého metodou okna.
pub const FirDesign = struct {
    filter_type: FilterType,
    /// Mezní frekvence; u pásmové propusti dolní mez pásma.
    cutoff_hz: f64,
    /// Horní mez pásma; používá se jen u pásmové propusti.
    upper_cutoff_hz: f64,
    /// Počet koeficientů. Musí být lichý, aby měl filtr přesný střed.
    length: usize,
    window: WindowKind,
};

pub const FirError = Allocator.Error || error{
    /// Délka FIR filtru musí být lichá.
    FirLengthNotOdd,
};

/// Navrhne FIR filtr metodou okna (windowed-sinc).
///
/// Ideální dolní propust má impulzní odezvu sinc, která je nekonečně dlouhá.
/// Usekneme ji na `length` vzorků a vynásobíme oknem, aby useknutí nezpůsobilo
/// zvlnění (jde o tentýž jev jako prosakování ve spektru). Ostatní typy se
/// z dolní propusti odvodí. Vrácené koeficienty uvolní volající.
pub fn designFir(allocator: Allocator, design: FirDesign, sample_rate_hz: f64) FirError![]f64 {
    if (design.length % 2 != 1) return error.FirLengthNotOdd;
    const low_pass = try windowedLowPass(allocator, design.cutoff_hz / sample_rate_hz, design.length, design.window);
    switch (design.filter_type) {
        .low_pass => return low_pass,
        .high_pass => {
            spectralInversion(low_pass);
            return low_pass;
        },
        // Pásmo = vše pod horní mezí minus vše pod dolní mezí.
        .band_pass => {
            defer allocator.free(low_pass);
            const upper = try windowedLowPass(allocator, design.upper_cutoff_hz / sample_rate_hz, design.length, design.window);
            for (upper, low_pass) |*value, lower| value.* -= lower;
            return upper;
        },
    }
}

/// Dolní propust: posunutá funkce sinc vynásobená oknem.
///
/// `cutoff_ratio` je mezní frekvence dělená vzorkovací frekvencí (0 až 0,5).
/// Ideální odezva je `h[n] = 2·fc · sinc(2·fc · (n − střed))`.
fn windowedLowPass(allocator: Allocator, cutoff_ratio: f64, length: usize, kind: WindowKind) Allocator.Error![]f64 {
    const center = toF64(length - 1) / 2;
    const coefficients = try window_module.symmetricWindow(allocator, kind, length);
    // Pole s okenními vahami rovnou přepíšeme koeficienty filtru.
    for (coefficients, 0..) |*coefficient, n| {
        const ideal = 2 * cutoff_ratio * sinc(2 * cutoff_ratio * (toF64(n) - center));
        coefficient.* *= ideal;
    }

    // Zesílení na nulové frekvenci je součet koeficientů. Po useknutí a okně
    // není přesně 1, proto koeficienty vydělíme, aby stejnosměrná složka
    // prošla beze změny.
    const total = window_module.sum(coefficients);
    for (coefficients) |*coefficient| coefficient.* /= total;
    return coefficients;
}

/// Z dolní propusti udělá (na místě) horní propust:
/// `h_HP[n] = δ[n − střed] − h_LP[n]`.
/// Tedy „původní signál minus to, co propustí dolní propust“.
fn spectralInversion(coefficients: []f64) void {
    for (coefficients) |*value| value.* = -value.*;
    coefficients[coefficients.len / 2] += 1;
}

// ---------------------------------------------------------------------------
// IIR – bikvadratický filtr
// ---------------------------------------------------------------------------

/// Bikvadratický filtr (biquad): IIR filtr druhého řádu.
///
/// `y[n] = b0·x[n] + b1·x[n−1] + b2·x[n−2] − a1·y[n−1] − a2·y[n−2]`
pub const Biquad = struct {
    /// Koeficienty u vstupních vzorků: b0, b1, b2.
    b: [3]f64,
    /// Koeficienty u výstupních vzorků: a0 (vždy 1), a1, a2.
    a: [3]f64,
};

/// Navrhne bikvadratický filtr podle známé „kuchařky“ R. Bristow-Johnsona
/// (Audio EQ Cookbook).
///
/// `frequency_hz` je mezní frekvence (dolní a horní propust) nebo střed pásma
/// (pásmová propust). `q` je činitel jakosti: čím větší, tím ostřejší
/// zlom nebo užší pásmo. Q = 1/√2 ≈ 0,707 dává nejplošší propustné pásmo.
pub fn designBiquad(filter_type: FilterType, frequency_hz: f64, q: f64, sample_rate_hz: f64) Biquad {
    // Úhlová frekvence na jeden vzorek (0 až π).
    const omega = 2 * pi * frequency_hz / sample_rate_hz;
    const cos_omega = @cos(omega);
    const alpha = @sin(omega) / (2 * q);

    const b: [3]f64 = switch (filter_type) {
        .low_pass => .{ (1 - cos_omega) / 2, 1 - cos_omega, (1 - cos_omega) / 2 },
        .high_pass => .{ (1 + cos_omega) / 2, -(1 + cos_omega), (1 + cos_omega) / 2 },
        // Varianta se zesílením 0 dB na střední frekvenci.
        .band_pass => .{ alpha, 0, -alpha },
    };
    const a0 = 1 + alpha;
    const a = [3]f64{ a0, -2 * cos_omega, 1 - alpha };

    // Vydělíme vše koeficientem a0, aby v rovnici stál výstup y[n] sám.
    return .{
        .b = .{ b[0] / a0, b[1] / a0, b[2] / a0 },
        .a = .{ 1, a[1] / a0, a[2] / a0 },
    };
}

/// Profiltruje signál bikvadratickým filtrem (tzv. přímá forma I).
/// Předchozí vzorky před začátkem signálu bereme jako nuly.
/// Vrácené pole uvolní volající.
pub fn biquadFilter(allocator: Allocator, biquad: Biquad, signal: []const f64) Allocator.Error![]f64 {
    const b0, const b1, const b2 = biquad.b;
    _, const a1, const a2 = biquad.a;
    // Paměť filtru: dva předchozí vstupy a dva předchozí výstupy.
    var x1: f64 = 0;
    var x2: f64 = 0;
    var y1: f64 = 0;
    var y2: f64 = 0;
    const output = try allocator.alloc(f64, signal.len);
    for (output, signal) |*result, x0| {
        const y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        result.* = y0;
        x2 = x1;
        x1 = x0;
        y2 = y1;
        y1 = y0;
    }
    return output;
}

/// Impulzní odezva: výstup filtru, když na vstup přijde jediný jednotkový
/// vzorek a pak samé nuly. U IIR je nekonečná, vracíme prvních `length` vzorků.
/// Vrácené pole uvolní volající.
pub fn biquadImpulseResponse(allocator: Allocator, biquad: Biquad, length: usize) Allocator.Error![]f64 {
    const impulse = try allocator.alloc(f64, length);
    defer allocator.free(impulse);
    @memset(impulse, 0);
    if (length > 0) impulse[0] = 1;
    return biquadFilter(allocator, biquad, impulse);
}

// ---------------------------------------------------------------------------
// Frekvenční charakteristika
// ---------------------------------------------------------------------------

/// Jeden bod frekvenční charakteristiky.
pub const ResponsePoint = struct {
    frequency_hz: f64,
    /// Zesílení: kolikrát filtr zvětší amplitudu sinusovky této frekvence.
    magnitude: f64,
    magnitude_db: f64,
    /// Fázový posun ve stupních (−180° až 180°).
    phase_deg: f64,
};

/// Frekvenční charakteristika filtru s koeficienty `b` a `a` (a[0] = 1)
/// v `point_count` bodech (aspoň dvou) od 0 do fs/2.
///
/// Sinusovka e^(jωn) projde lineárním filtrem jako sinusovka stejné
/// frekvence, jen vynásobená komplexním číslem
///
/// ```text
/// H(ω) = (b0 + b1·e^(−jω) + b2·e^(−2jω) + …) / (a0 + a1·e^(−jω) + …)
/// ```
///
/// Jeho velikost je zesílení a úhel fázový posun. Vrácené pole uvolní volající.
pub fn frequencyResponse(
    allocator: Allocator,
    b: []const f64,
    a: []const f64,
    sample_rate_hz: f64,
    point_count: usize,
) Allocator.Error![]ResponsePoint {
    std.debug.assert(point_count >= 2);
    const points = try allocator.alloc(ResponsePoint, point_count);
    for (points, 0..) |*point, index| {
        const frequency_hz = sample_rate_hz / 2 * toF64(index) / toF64(point_count - 1);
        const omega = 2 * pi * frequency_hz / sample_rate_hz;
        const response = divide(evaluatePolynomial(b, omega), evaluatePolynomial(a, omega));
        const magnitude = response.magnitude();
        point.* = .{
            .frequency_hz = frequency_hz,
            .magnitude = magnitude,
            .magnitude_db = toDecibels(magnitude),
            .phase_deg = std.math.radiansToDegrees(response.phase()),
        };
    }
    return points;
}

/// Spočítá Σ c[k] · e^(−jωk).
fn evaluatePolynomial(coefficients: []const f64, omega: f64) Complex {
    var total = Complex.zero;
    for (coefficients, 0..) |coefficient, k| {
        total = total.add(Complex.fromPolar(coefficient, -omega * toF64(k)));
    }
    return total;
}

/// Podíl komplexních čísel: velikosti se dělí, úhly odečítají.
fn divide(numerator: Complex, denominator: Complex) Complex {
    return Complex.fromPolar(
        numerator.magnitude() / denominator.magnitude(),
        numerator.phase() - denominator.phase(),
    );
}

fn toF64(value: usize) f64 {
    return @floatFromInt(value);
}

const testing = std.testing;
const test_tolerance = 1e-9;
const rate = 1000.0;
const fft_module = @import("fft.zig");

/// Zesílení filtru na jedné frekvenci.
fn gain(b: []const f64, a: []const f64, frequency_hz: f64) !f64 {
    // 1001 bodů od 0 do 500 Hz: bod i leží na frekvenci i/2 Hz.
    const response = try frequencyResponse(testing.allocator, b, a, rate, 1001);
    defer testing.allocator.free(response);
    return response[@intFromFloat(@round(frequency_hz * 2))].magnitude;
}

fn fir(filter_type: FilterType, cutoff_hz: f64, upper_cutoff_hz: f64) ![]f64 {
    return designFir(testing.allocator, .{
        .filter_type = filter_type,
        .cutoff_hz = cutoff_hz,
        .upper_cutoff_hz = upper_cutoff_hz,
        .length = 101,
        .window = .hamming,
    }, rate);
}

fn expectConvolution(expected: []const f64, signal: []const f64, kernel: []const f64) !void {
    const output = try convolve(testing.allocator, signal, kernel);
    defer testing.allocator.free(output);
    try testing.expectEqualSlices(f64, expected, output);
}

test "convolution examples" {
    try expectConvolution(&.{ 1, 2, 3 }, &.{ 1, 2, 3 }, &.{1});
    // Jednotkový impulz na vstupu vrátí jádro.
    try expectConvolution(&.{ 0.5, 0.25, 0, 0 }, &.{ 1, 0, 0, 0 }, &.{ 0.5, 0.25 });
    // Klouzavý průměr dvou vzorků.
    try expectConvolution(&.{ 1, 3, 5 }, &.{ 2, 4, 6 }, &.{ 0.5, 0.5 });
}

test "fir low pass" {
    const h = try fir(.low_pass, 100, 0);
    defer testing.allocator.free(h);
    try testing.expectApproxEqAbs(1.0, try gain(h, &.{1}, 0), test_tolerance);
    // Na mezní frekvenci má filtr navržený metodou okna zesílení 1/2 (−6 dB).
    try testing.expectApproxEqAbs(0.5, try gain(h, &.{1}, 100), 0.02);
    try testing.expect(try gain(h, &.{1}, 200) < 0.01);
    // Souměrné koeficienty = lineární fáze.
    for (h, 0..) |value, n| {
        try testing.expectApproxEqAbs(h[h.len - 1 - n], value, test_tolerance);
    }
}

test "fir high pass" {
    const h = try fir(.high_pass, 100, 0);
    defer testing.allocator.free(h);
    try testing.expect(try gain(h, &.{1}, 0) < test_tolerance);
    try testing.expect(try gain(h, &.{1}, 30) < 0.01);
    try testing.expectApproxEqAbs(1.0, try gain(h, &.{1}, 300), 0.01);
    try testing.expectApproxEqAbs(1.0, try gain(h, &.{1}, 500), 0.01);
}

test "fir band pass" {
    const h = try fir(.band_pass, 100, 200);
    defer testing.allocator.free(h);
    try testing.expect(try gain(h, &.{1}, 0) < test_tolerance);
    try testing.expectApproxEqAbs(1.0, try gain(h, &.{1}, 150), 0.01);
    try testing.expect(try gain(h, &.{1}, 30) < 0.01);
    try testing.expect(try gain(h, &.{1}, 300) < 0.01);
}

test "fir rejects even length" {
    const design: FirDesign = .{ .filter_type = .low_pass, .cutoff_hz = 100, .upper_cutoff_hz = 0, .length = 100, .window = .hamming };
    try testing.expectError(error.FirLengthNotOdd, designFir(testing.allocator, design, rate));
}

test "fir filters sine by its gain" {
    // Po odeznění přechodového děje má sinusovka na výstupu amplitudu
    // vynásobenou zesílením filtru na její frekvenci.
    const allocator = testing.allocator;
    const h = try fir(.low_pass, 100, 0);
    defer allocator.free(h);
    var input: [2000]f64 = undefined;
    for (&input, 0..) |*value, n| value.* = @sin(2 * pi * 90 * toF64(n) / rate);
    const output = try convolve(allocator, &input, h);
    defer allocator.free(output);
    var peak: f64 = 0;
    for (output[500..]) |value| peak = @max(peak, @abs(value));
    try testing.expectApproxEqAbs(try gain(h, &.{1}, 90), peak, 0.01);
}

test "biquad gains at characteristic frequencies" {
    const q = 1.0 / @sqrt(2.0);
    const low = designBiquad(.low_pass, 100, q, rate);
    try testing.expectApproxEqAbs(1.0, try gain(&low.b, &low.a, 0), test_tolerance);
    // Na mezní frekvenci má dolní i horní propust zesílení rovné Q.
    try testing.expectApproxEqAbs(q, try gain(&low.b, &low.a, 100), test_tolerance);
    try testing.expect(try gain(&low.b, &low.a, 500) < test_tolerance);

    const high = designBiquad(.high_pass, 100, q, rate);
    try testing.expect(try gain(&high.b, &high.a, 0) < test_tolerance);
    try testing.expectApproxEqAbs(q, try gain(&high.b, &high.a, 100), test_tolerance);
    try testing.expectApproxEqAbs(1.0, try gain(&high.b, &high.a, 500), test_tolerance);

    const band = designBiquad(.band_pass, 100, 5, rate);
    try testing.expectApproxEqAbs(1.0, try gain(&band.b, &band.a, 100), test_tolerance);
    try testing.expect(try gain(&band.b, &band.a, 0) < test_tolerance);
}

test "biquad impulse response matches frequency response" {
    // FFT impulzní odezvy je frekvenční charakteristika – dvě nezávislé
    // cesty k témuž výsledku se musí shodnout.
    const allocator = testing.allocator;
    const biquad = designBiquad(.low_pass, 100, 2, rate);
    const impulse = try biquadImpulseResponse(allocator, biquad, 4096);
    defer allocator.free(impulse);
    const complex_samples = try fft_module.realToComplex(allocator, impulse);
    defer allocator.free(complex_samples);
    const spectrum = try fft_module.fft(allocator, complex_samples);
    defer allocator.free(spectrum);
    const response = try frequencyResponse(allocator, &biquad.b, &biquad.a, rate, 2049);
    defer allocator.free(response);
    var bin: usize = 0;
    while (bin <= 2048) : (bin += 64) {
        try testing.expectApproxEqAbs(response[bin].magnitude, spectrum[bin].magnitude(), 1e-6);
    }
}
