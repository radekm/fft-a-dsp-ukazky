//! Generátor syntetických signálů: součet periodických složek,
//! stejnosměrné složky a šumu.

const std = @import("std");
const Allocator = std.mem.Allocator;
const pi = std.math.pi;

/// Tvar jedné periody signálu. Všechny tvary mají rozkmit −1 až 1.
pub const Waveform = enum {
    sine,
    square,
    sawtooth,
    triangle,
};

/// Jedna periodická složka signálu.
pub const Component = struct {
    /// Vypnutá složka se do signálu nepřičítá.
    enabled: bool,
    waveform: Waveform,
    frequency_hz: f64,
    amplitude: f64,
    /// Počáteční fáze ve stupních.
    phase_deg: f64,
};

/// Úplný popis signálu.
pub const SignalSpec = struct {
    /// Složky signálu. Pole vlastní volající, popis si ho jen půjčuje.
    components: []const Component,
    /// Stejnosměrná složka (konstanta přičtená ke každému vzorku).
    dc_offset: f64,
    /// Šum je rovnoměrně rozložený v rozsahu ± tato hodnota.
    noise_amplitude: f64,
    /// Stejné semínko dává pokaždé stejný šum, takže graf neposkakuje.
    noise_seed: u64,
};

/// Vygeneruje `sample_count` vzorků signálu při dané vzorkovací frekvenci.
/// Vzorek číslo `n` odpovídá času `n / sample_rate_hz`.
/// Vrácené pole uvolní volající.
pub fn generate(
    allocator: Allocator,
    spec: SignalSpec,
    sample_rate_hz: f64,
    sample_count: usize,
) Allocator.Error![]f64 {
    var noise_state = noiseStart(spec.noise_seed);
    const samples = try allocator.alloc(f64, sample_count);
    for (samples, 0..) |*sample, index| {
        const time_s = toF64(index) / sample_rate_hz;
        const noise = spec.noise_amplitude * noiseNext(&noise_state);
        sample.* = valueAt(spec, time_s) + noise;
    }
    return samples;
}

/// Hodnota signálu v libovolném čase – takto si představujeme „spojitý“
/// (analogový) signál před vzorkováním. Šum se zde nepřičítá, protože
/// generátor šumu dává hodnoty jen postupně, vzorek po vzorku.
pub fn valueAt(spec: SignalSpec, time_s: f64) f64 {
    var value = spec.dc_offset;
    for (spec.components) |component| {
        if (component.enabled) value += componentValue(component, time_s);
    }
    return value;
}

/// Hodnota jedné složky v daném čase.
fn componentValue(component: Component, time_s: f64) f64 {
    const angle_rad = 2 * pi * component.frequency_hz * time_s +
        std.math.degreesToRadians(component.phase_deg);
    return component.amplitude * waveformValue(component.waveform, angle_rad);
}

/// Hodnota průběhu pro daný úhel; jedna perioda odpovídá úhlu 2π.
/// Všechny průběhy začínají v nule a jdou nahoru, podobně jako sinus
/// (obdélník rovnou skočí na 1, pila začíná na −1).
fn waveformValue(waveform: Waveform, angle_rad: f64) f64 {
    // Poloha uvnitř periody: 0 = začátek, 1 = konec.
    const position = fraction(angle_rad / (2 * pi));
    return switch (waveform) {
        .sine => @sin(angle_rad),
        .square => if (position < 0.5) 1 else -1,
        .sawtooth => 2 * position - 1,
        .triangle => 4 * @abs(fraction(position + 0.75) - 0.5) - 1,
    };
}

/// Desetinná část čísla v rozsahu 0 až 1 (i pro záporná čísla).
fn fraction(value: f64) f64 {
    return value - @floor(value);
}

/// Počáteční stav generátoru šumu. Stav nesmí být nula, jinak by generátor
/// vracel samé nuly.
fn noiseStart(seed: u64) u64 {
    return if (seed == 0) 0x9E37_79B9_7F4A_7C15 else seed;
}

/// Další pseudonáhodné číslo rovnoměrně z rozsahu −1 až 1.
///
/// Generátor je xorshift64*: stav se zamíchá třemi posuny a operací XOR
/// a výsledek se vynásobí konstantou. Je krátký a pro ukázky bohatě stačí.
fn noiseNext(state: *u64) f64 {
    var x = state.*;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    state.* = x;
    // `*%` je násobení s přetečením (modulo 2⁶⁴), které tu chceme.
    const random = x *% 0x2545_F491_4F6C_DD1D;
    // Horních 53 bitů převedeme na číslo 0 až 1 (tolik bitů má mantisa f64).
    const top_bits: f64 = @floatFromInt(random >> 11);
    const unit = top_bits / @as(f64, @floatFromInt(@as(u64, 1) << 53));
    return 2 * unit - 1;
}

fn toF64(value: usize) f64 {
    return @floatFromInt(value);
}

const testing = std.testing;
const test_tolerance = 1e-12;

fn testComponent(waveform: Waveform) Component {
    return .{ .enabled = true, .waveform = waveform, .frequency_hz = 1, .amplitude = 1, .phase_deg = 0 };
}

fn specWith(components: []const Component) SignalSpec {
    return .{ .components = components, .dc_offset = 0, .noise_amplitude = 0, .noise_seed = 1 };
}

test "sine quarter period is peak" {
    // 1 Hz vzorkovaný 4 Hz: vzorky 0, 1, 0, −1.
    const components = [_]Component{testComponent(.sine)};
    const samples = try generate(testing.allocator, specWith(&components), 4, 4);
    defer testing.allocator.free(samples);
    for ([_]f64{ 0, 1, 0, -1 }, samples) |expected, sample| {
        try testing.expectApproxEqAbs(expected, sample, test_tolerance);
    }
}

test "waveform shapes" {
    const quarter = pi / 2.0;
    try testing.expectEqual(1.0, waveformValue(.square, quarter));
    try testing.expectEqual(-1.0, waveformValue(.square, 3 * quarter));
    try testing.expectApproxEqAbs(0.0, waveformValue(.sawtooth, pi), test_tolerance);
    try testing.expectApproxEqAbs(0.0, waveformValue(.triangle, 0), test_tolerance);
    try testing.expectApproxEqAbs(1.0, waveformValue(.triangle, quarter), test_tolerance);
    try testing.expectApproxEqAbs(-1.0, waveformValue(.triangle, 3 * quarter), test_tolerance);
}

test "disabled component and dc offset" {
    var components = [_]Component{testComponent(.sine)};
    components[0].enabled = false;
    var spec = specWith(&components);
    spec.dc_offset = 0.5;
    const samples = try generate(testing.allocator, spec, 8, 3);
    defer testing.allocator.free(samples);
    try testing.expectEqualSlices(f64, &.{ 0.5, 0.5, 0.5 }, samples);
}

test "noise is bounded and repeatable" {
    var spec = specWith(&.{});
    spec.noise_amplitude = 0.3;
    const first = try generate(testing.allocator, spec, 100, 1000);
    defer testing.allocator.free(first);
    const second = try generate(testing.allocator, spec, 100, 1000);
    defer testing.allocator.free(second);
    try testing.expectEqualSlices(f64, first, second);
    var varies = false;
    for (first) |sample| {
        try testing.expect(@abs(sample) <= 0.3);
        // Šum nesmí být konstantní.
        if (@abs(sample - first[0]) > 0.01) varies = true;
    }
    try testing.expect(varies);
}
