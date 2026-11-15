//! Převod výsledku FFT na veličiny, které se dobře čtou z grafu:
//! amplituda, amplituda v decibelech a fáze pro každý bin.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Complex = @import("complex.zig").Complex;

/// Nejmenší amplituda, kterou ještě převádíme na decibely (−240 dB).
/// Logaritmus nuly neexistuje, proto menší hodnoty ořízneme.
const min_amplitude = 1e-12;

/// Pod touto amplitudou je fáze jen zaokrouhlovací šum, proto ji nulujeme.
const phase_threshold = 1e-9;

/// Jedna spektrální čára (jeden bin jednostranného spektra).
pub const SpectrumLine = struct {
    /// Pořadové číslo binu `k`.
    bin: usize,
    /// Frekvence binu: `k · fs / N`.
    frequency_hz: f64,
    /// Amplituda složky ve stejných jednotkách jako vzorky signálu.
    amplitude: f64,
    /// Amplituda v decibelech: `20 · log₁₀(amplituda)`.
    amplitude_db: f64,
    /// Fáze ve stupních, vztažená ke kosinu (sinus má fázi −90°).
    phase_deg: f64,
};

/// Frekvence binu `bin` při vzorkovací frekvenci `sample_rate_hz` a délce FFT `fft_size`.
pub fn binFrequency(bin: usize, sample_rate_hz: f64, fft_size: usize) f64 {
    return toF64(bin) * sample_rate_hz / toF64(fft_size);
}

/// Převod poměru amplitud na decibely: `20 · log₁₀(ratio)`. Velmi malé
/// hodnoty (i nulu) ořízne na −240 dB.
pub fn toDecibels(ratio: f64) f64 {
    return 20 * @log10(@max(ratio, min_amplitude));
}

/// Z výsledku FFT reálného signálu udělá jednostranné spektrum (biny 0 až N/2).
///
/// Spektrum reálného signálu je symetrické: bin `N − k` je komplexně sdružený
/// s binem `k`, takže horní polovina nenese nic nového. Energie každé složky
/// je ale rozdělená mezi obě poloviny, proto amplitudu násobíme dvěma.
/// Výjimkou jsou bin 0 (stejnosměrná složka) a při sudém N bin N/2
/// (Nyquistova frekvence), které protějšek nemají. Při lichém N padne
/// N/2 mezi biny, takže protějšek má každý bin kromě nultého.
///
/// `window_sum` je součet koeficientů okna, kterým byl signál vynásoben
/// (bez okna je to počet vzorků signálu). Sinusovka s amplitudou A dá v FFT
/// hodnotu A · window_sum / 2, proto tímto součtem dělíme. Vzorky doplněné
/// nulami se do součtu nepočítají.
///
/// Vrácené pole uvolní volající.
pub fn oneSidedSpectrum(
    allocator: Allocator,
    fft_output: []const Complex,
    sample_rate_hz: f64,
    window_sum: f64,
) Allocator.Error![]SpectrumLine {
    const n = fft_output.len;
    const last_bin = n / 2;
    const lines = try allocator.alloc(SpectrumLine, @min(n, last_bin + 1));
    for (lines, fft_output[0..lines.len], 0..) |*line, value, bin| {
        const has_mirror_bin = bin != 0 and 2 * bin != n;
        const fold_factor: f64 = if (has_mirror_bin) 2 else 1;
        const amplitude = fold_factor * value.magnitude() / window_sum;
        line.* = .{
            .bin = bin,
            .frequency_hz = binFrequency(bin, sample_rate_hz, n),
            .amplitude = amplitude,
            .amplitude_db = toDecibels(amplitude),
            .phase_deg = if (amplitude > phase_threshold) std.math.radiansToDegrees(value.phase()) else 0,
        };
    }
    return lines;
}

fn toF64(value: usize) f64 {
    return @floatFromInt(value);
}

const testing = std.testing;
const test_tolerance = 1e-9;
const fft = @import("fft.zig");
const signal = @import("signal.zig");

test "sine peak is in the right bin with the right amplitude" {
    // 50 Hz při fs = 1024 Hz a N = 1024: biny jsou po 1 Hz, špička je v binu 50.
    const allocator = testing.allocator;
    const components = [_]signal.Component{.{
        .enabled = true,
        .waveform = .sine,
        .frequency_hz = 50,
        .amplitude = 0.7,
        .phase_deg = 0,
    }};
    const spec: signal.SignalSpec = .{ .components = &components, .dc_offset = 0.25, .noise_amplitude = 0, .noise_seed = 1 };
    const samples = try signal.generate(allocator, spec, 1024, 1024);
    defer allocator.free(samples);
    const complex_samples = try fft.realToComplex(allocator, samples);
    defer allocator.free(complex_samples);
    const spectrum = try fft.fft(allocator, complex_samples);
    defer allocator.free(spectrum);
    const lines = try oneSidedSpectrum(allocator, spectrum, 1024, 1024);
    defer allocator.free(lines);

    try testing.expectEqual(513, lines.len);
    for (lines) |line| {
        const expected: f64 = switch (line.bin) {
            0 => 0.25,
            50 => 0.7,
            else => 0,
        };
        try testing.expectApproxEqAbs(expected, line.amplitude, test_tolerance);
    }
    try testing.expectApproxEqAbs(50.0, lines[50].frequency_hz, test_tolerance);
    // Sinus je kosinus zpožděný o čtvrt periody.
    try testing.expectApproxEqAbs(-90.0, lines[50].phase_deg, 1e-6);
    try testing.expectApproxEqAbs(20 * @log10(0.7), lines[50].amplitude_db, test_tolerance);
}

test "odd length keeps amplitude of last bin" {
    // N = 5: bin 2 má protějšek v binu 3, amplituda se tedy musí zdvojit.
    const allocator = testing.allocator;
    const n = 5;
    var samples: [n]f64 = undefined;
    for (&samples, 0..) |*sample, i| sample.* = @cos(2 * std.math.pi * 2 * toF64(i) / n);
    const complex_samples = try fft.realToComplex(allocator, &samples);
    defer allocator.free(complex_samples);
    const spectrum = try fft.dft(allocator, complex_samples);
    defer allocator.free(spectrum);
    const lines = try oneSidedSpectrum(allocator, spectrum, 5, 5);
    defer allocator.free(lines);
    try testing.expectEqual(3, lines.len);
    try testing.expectApproxEqAbs(1.0, lines[2].amplitude, test_tolerance);
}

test "bin frequency spacing" {
    try testing.expectEqual(0.0, binFrequency(0, 8000, 256));
    try testing.expectEqual(4000.0, binFrequency(128, 8000, 256));
    try testing.expectEqual(31.25, binFrequency(1, 8000, 256));
}
