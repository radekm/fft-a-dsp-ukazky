//! Diskrétní Fourierova transformace: pomalá podle definice (DFT)
//! a rychlá (FFT, radix-2).
//!
//! Obě počítají totéž:
//!
//! ```text
//! X[k] = Σ x[n] · e^(−j·2π·k·n/N)      pro n = 0 … N−1
//! ```
//!
//! `X[k]` říká, kolik je v signálu obsaženo kmitání, které se za `N` vzorků
//! zopakuje právě `k`-krát. DFT potřebuje N² násobení, FFT jen N·log₂N.
//!
//! Všechny funkce vracejí nově alokované pole; uvolní ho volající.

const std = @import("std");
const Allocator = std.mem.Allocator;
const pi = std.math.pi;

const Complex = @import("complex.zig").Complex;

/// Chyby FFT.
pub const FftError = Allocator.Error || error{
    /// FFT radix-2 umí jen délky 1, 2, 4, 8, …
    LengthNotPowerOfTwo,
};

/// Znaménko v exponentu pro dopřednou transformaci (čas → frekvence).
const forward: f64 = -1;
/// Znaménko v exponentu pro zpětnou transformaci (frekvence → čas).
const inverse: f64 = 1;

/// Převede reálné vzorky na komplexní čísla s nulovou imaginární částí.
pub fn realToComplex(allocator: Allocator, samples: []const f64) Allocator.Error![]Complex {
    const output = try allocator.alloc(Complex, samples.len);
    for (output, samples) |*value, sample| value.* = .init(sample, 0);
    return output;
}

/// Pomalá DFT přesně podle definice. Funguje pro libovolnou délku.
pub fn dft(allocator: Allocator, input: []const Complex) Allocator.Error![]Complex {
    const n = input.len;
    const output = try allocator.alloc(Complex, n);
    for (output, 0..) |*result, k| {
        var sum = Complex.zero;
        for (input, 0..) |sample, index| {
            // Úhel se opakuje po celých otáčkách, proto stačí zbytek k·n mod N.
            // Udržuje to úhel malý a výpočet přesný.
            const turns = toF64((k * index) % n) / toF64(n);
            const rotation = Complex.fromPolar(1, forward * 2 * pi * turns);
            sum = sum.add(sample.mul(rotation));
        }
        result.* = sum;
    }
    return output;
}

/// Rychlá Fourierova transformace. Délka vstupu musí být mocnina dvou.
pub fn fft(allocator: Allocator, input: []const Complex) FftError![]Complex {
    return transform(allocator, input, forward);
}

/// Zpětná FFT: ze spektra vrátí původní vzorky.
/// Liší se jen znaménkem v exponentu a dělením délkou `N`.
pub fn ifft(allocator: Allocator, input: []const Complex) FftError![]Complex {
    const output = try transform(allocator, input, inverse);
    const scale = 1 / toF64(input.len);
    for (output) |*value| value.* = value.scale(scale);
    return output;
}

/// Společné jádro dopředné i zpětné FFT (iterativní algoritmus Cooley–Tukey).
///
/// Myšlenka: DFT délky N lze složit ze dvou DFT délky N/2 – jedné ze sudých
/// a jedné z lichých vzorků. Opakovaným půlením dojdeme až k délce 1, kde je
/// DFT vzorku on sám. Proto nejdřív vzorky přerovnáme (bitová reverze) a pak
/// je po etapách skládáme do bloků délky 2, 4, 8, … N.
fn transform(allocator: Allocator, input: []const Complex, sign: f64) FftError![]Complex {
    const n = input.len;
    if (!isPowerOfTwo(n)) return error.LengthNotPowerOfTwo;

    const data = try bitReversePermutation(allocator, input);
    var block_size: usize = 2;
    while (block_size <= n) : (block_size *= 2) {
        butterflyStage(data, block_size, sign);
    }
    return data;
}

/// Jedna etapa FFT: sousední dvojice hotových bloků délky `block_size / 2`
/// spojí do bloků délky `block_size`.
///
/// Spojení dvou hodnot `a` (ze sudé poloviny) a `b` (z liché poloviny) se
/// říká „motýlek“:
///
/// ```text
/// horní = a + w·b
/// dolní = a − w·b          kde w = e^(±j·2π·k/block_size)
/// ```
fn butterflyStage(data: []Complex, block_size: usize, sign: f64) void {
    const half = block_size / 2;
    // O tento úhel se `w` pootočí mezi dvěma sousedními motýlky.
    const step = Complex.fromPolar(1, sign * 2 * pi / toF64(block_size));

    var block_start: usize = 0;
    while (block_start < data.len) : (block_start += block_size) {
        var w = Complex.one;
        for (0..half) |k| {
            const top = block_start + k;
            const bottom = top + half;
            const a = data[top];
            const b = w.mul(data[bottom]);
            data[top] = a.add(b);
            data[bottom] = a.sub(b);
            w = w.mul(step);
        }
    }
}

/// Přerovná vzorky tak, že vzorek s indexem `i` skončí na indexu, který má
/// bity čísla `i` v opačném pořadí (např. pro N = 8: 1 = 001 → 100 = 4).
/// Přesně takové pořadí vznikne opakovaným dělením na sudé a liché vzorky.
fn bitReversePermutation(allocator: Allocator, input: []const Complex) Allocator.Error![]Complex {
    const n = input.len;
    const bit_count: u6 = @intCast(@ctz(n));
    const output = try allocator.alloc(Complex, n);
    for (input, 0..) |value, index| {
        output[reverseBits(index, bit_count)] = value;
    }
    return output;
}

/// Otočí pořadí spodních `bit_count` bitů čísla `value`.
fn reverseBits(value: usize, bit_count: u6) usize {
    var remaining = value;
    var reversed: usize = 0;
    for (0..bit_count) |_| {
        reversed = (reversed << 1) | (remaining & 1);
        remaining >>= 1;
    }
    return reversed;
}

/// Je `n` mocnina dvou? (Nula není.)
pub fn isPowerOfTwo(n: usize) bool {
    return n != 0 and (n & (n - 1)) == 0;
}

/// Převod celého čísla na `f64`. V Zigu je třeba ho psát výslovně.
fn toF64(value: usize) f64 {
    return @floatFromInt(value);
}

const testing = std.testing;
const test_tolerance = 1e-9;

/// Testovací signál bez jakékoli symetrie, aby se chyba neschovala.
fn testSignal(allocator: Allocator, n: usize) ![]Complex {
    const signal = try allocator.alloc(Complex, n);
    for (signal, 0..) |*value, i| {
        const t = toF64(i);
        value.* = .init(@sin(0.37 * t) + 0.5 * @cos(1.3 * t), 0.25 * @sin(0.9 * t));
    }
    return signal;
}

fn expectClose(expected: []const Complex, actual: []const Complex) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| {
        try testing.expect(a.sub(e).magnitude() < test_tolerance);
    }
}

test "fft matches dft" {
    const allocator = testing.allocator;
    for (0..9) |exponent| {
        const signal = try testSignal(allocator, @as(usize, 1) << @intCast(exponent));
        defer allocator.free(signal);
        const fast = try fft(allocator, signal);
        defer allocator.free(fast);
        const slow = try dft(allocator, signal);
        defer allocator.free(slow);
        try expectClose(slow, fast);
    }
}

test "ifft restores signal" {
    const allocator = testing.allocator;
    const signal = try testSignal(allocator, 256);
    defer allocator.free(signal);
    const spectrum = try fft(allocator, signal);
    defer allocator.free(spectrum);
    const restored = try ifft(allocator, spectrum);
    defer allocator.free(restored);
    try expectClose(signal, restored);
}

test "impulse has flat spectrum" {
    const allocator = testing.allocator;
    var signal: [16]Complex = @splat(Complex.zero);
    signal[0] = Complex.one;
    const spectrum = try fft(allocator, &signal);
    defer allocator.free(spectrum);
    const flat: [16]Complex = @splat(Complex.one);
    try expectClose(&flat, spectrum);
}

test "cosine lands in its bin" {
    // Kosinus, který se za 64 vzorků zopakuje 5krát, patří do binů 5 a 64−5.
    const allocator = testing.allocator;
    const n = 64;
    var samples: [n]f64 = undefined;
    for (&samples, 0..) |*sample, i| sample.* = @cos(2 * pi * 5 * toF64(i) / n);
    const complex_samples = try realToComplex(allocator, &samples);
    defer allocator.free(complex_samples);
    const spectrum = try fft(allocator, complex_samples);
    defer allocator.free(spectrum);
    for (spectrum, 0..) |value, bin| {
        const expected: f64 = if (bin == 5 or bin == n - 5) n / 2 else 0;
        try testing.expectApproxEqAbs(expected, value.magnitude(), test_tolerance);
    }
}

test "bit reversal for eight points" {
    var reversed: [8]usize = undefined;
    for (&reversed, 0..) |*value, i| value.* = reverseBits(i, 3);
    try testing.expectEqualSlices(usize, &.{ 0, 4, 2, 6, 1, 5, 3, 7 }, &reversed);
}

test "fft rejects other lengths" {
    const allocator = testing.allocator;
    const signal = try testSignal(allocator, 12);
    defer allocator.free(signal);
    try testing.expectError(error.LengthNotPowerOfTwo, fft(allocator, signal));
    try testing.expectError(error.LengthNotPowerOfTwo, fft(allocator, &.{}));
}
