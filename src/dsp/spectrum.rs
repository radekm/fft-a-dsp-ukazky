//! Převod výsledku FFT na veličiny, které se dobře čtou z grafu:
//! amplituda, amplituda v decibelech a fáze pro každý bin.

use super::complex::Complex;

/// Nejmenší amplituda, kterou ještě převádíme na decibely (−240 dB).
/// Logaritmus nuly neexistuje, proto menší hodnoty ořízneme.
const MIN_AMPLITUDE: f64 = 1e-12;

/// Pod touto amplitudou je fáze jen zaokrouhlovací šum, proto ji nulujeme.
const PHASE_THRESHOLD: f64 = 1e-9;

/// Jedna spektrální čára (jeden bin jednostranného spektra).
#[derive(Clone, Debug, PartialEq)]
pub struct SpectrumLine {
    /// Pořadové číslo binu `k`.
    pub bin: usize,
    /// Frekvence binu: `k · fs / N`.
    pub frequency_hz: f64,
    /// Amplituda složky ve stejných jednotkách jako vzorky signálu.
    pub amplitude: f64,
    /// Amplituda v decibelech: `20 · log₁₀(amplituda)`.
    pub amplitude_db: f64,
    /// Fáze ve stupních, vztažená ke kosinu (sinus má fázi −90°).
    pub phase_deg: f64,
}

/// Frekvence binu `bin` při vzorkovací frekvenci `sample_rate_hz` a délce FFT `fft_size`.
pub fn bin_frequency(bin: usize, sample_rate_hz: f64, fft_size: usize) -> f64 {
    bin as f64 * sample_rate_hz / fft_size as f64
}

/// Z výsledku FFT reálného signálu udělá jednostranné spektrum (biny 0 až N/2).
///
/// Spektrum reálného signálu je symetrické: bin `N − k` je komplexně sdružený
/// s binem `k`, takže horní polovina nenese nic nového. Energie každé složky
/// je ale rozdělená mezi obě poloviny, proto amplitudu násobíme dvěma.
/// Výjimkou jsou bin 0 (stejnosměrná složka) a bin N/2 (Nyquistova
/// frekvence), které protějšek nemají.
///
/// `window_sum` je součet koeficientů okna, kterým byl signál vynásoben
/// (bez okna je to počet vzorků signálu). Sinusovka s amplitudou A dá v FFT
/// hodnotu A · window_sum / 2, proto tímto součtem dělíme. Vzorky doplněné
/// nulami se do součtu nepočítají.
pub fn one_sided_spectrum(
    fft_output: &[Complex],
    sample_rate_hz: f64,
    window_sum: f64,
) -> Vec<SpectrumLine> {
    let n = fft_output.len();
    let last_bin = n / 2;
    let mut lines = Vec::with_capacity(last_bin + 1);
    for (bin, value) in fft_output.iter().enumerate().take(last_bin + 1) {
        let has_mirror_bin = bin != 0 && bin != last_bin;
        let fold_factor = if has_mirror_bin { 2.0 } else { 1.0 };
        let amplitude = fold_factor * value.magnitude() / window_sum;
        let phase_deg = if amplitude > PHASE_THRESHOLD {
            value.phase().to_degrees()
        } else {
            0.0
        };
        lines.push(SpectrumLine {
            bin,
            frequency_hz: bin_frequency(bin, sample_rate_hz, n),
            amplitude,
            amplitude_db: 20.0 * amplitude.max(MIN_AMPLITUDE).log10(),
            phase_deg,
        });
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dsp::fft::{fft, real_to_complex};
    use crate::dsp::signal::{Component, SignalSpec, Waveform, generate};

    const TOLERANCE: f64 = 1e-9;

    #[test]
    fn sine_peak_is_in_the_right_bin_with_the_right_amplitude() {
        // 50 Hz při fs = 1024 Hz a N = 1024: biny jsou po 1 Hz, špička je v binu 50.
        let spec = SignalSpec {
            components: vec![Component {
                enabled: true,
                waveform: Waveform::Sine,
                frequency_hz: 50.0,
                amplitude: 0.7,
                phase_deg: 0.0,
            }],
            dc_offset: 0.25,
            noise_amplitude: 0.0,
            noise_seed: 1,
        };
        let samples = generate(&spec, 1024.0, 1024);
        let lines = one_sided_spectrum(&fft(&real_to_complex(&samples)), 1024.0, 1024.0);

        assert_eq!(lines.len(), 513);
        for line in &lines {
            let expected = match line.bin {
                0 => 0.25,
                50 => 0.7,
                _ => 0.0,
            };
            assert!(
                (line.amplitude - expected).abs() < TOLERANCE,
                "bin {}",
                line.bin
            );
        }
        assert!((lines[50].frequency_hz - 50.0).abs() < TOLERANCE);
        // Sinus je kosinus zpožděný o čtvrt periody.
        assert!((lines[50].phase_deg + 90.0).abs() < 1e-6);
        assert!((lines[50].amplitude_db - 20.0 * 0.7f64.log10()).abs() < TOLERANCE);
    }

    #[test]
    fn bin_frequency_spacing() {
        assert_eq!(bin_frequency(0, 8000.0, 256), 0.0);
        assert_eq!(bin_frequency(128, 8000.0, 256), 4000.0);
        assert_eq!(bin_frequency(1, 8000.0, 256), 31.25);
    }
}
