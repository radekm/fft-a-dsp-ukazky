//! Okénkové funkce a jejich vlastnosti.
//!
//! FFT předpokládá, že záznam se donekonečna opakuje. Pokud signál nemá
//! v záznamu celý počet period, vznikne na hranici opakování skok a jeho
//! energie se rozlije do celého spektra – tomu se říká prosakování (leakage).
//! Okno záznam na krajích plynule ztlumí k nule, takže skok zmizí. Cenou je
//! širší hlavní lalok: čára ve spektru je rozmazanější.

use std::f64::consts::PI;

use super::fft::{fft, real_to_complex};

/// Nejmenší poměr, který převádíme na decibely (−240 dB).
const MIN_RATIO: f64 = 1e-12;

/// Druh okna.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WindowKind {
    /// Žádné okno – všechny vzorky mají váhu 1.
    Rectangular,
    Hann,
    Hamming,
    Blackman,
}

/// Všechna okna v pořadí od nejužšího hlavního laloku po nejnižší postranní laloky.
pub const ALL_WINDOWS: [WindowKind; 4] = [
    WindowKind::Rectangular,
    WindowKind::Hann,
    WindowKind::Hamming,
    WindowKind::Blackman,
];

/// Všechna zde použitá okna jsou součtem nejvýš tří kosinusovek:
///
/// ```text
/// w[n] = a0 − a1·cos(2πn/N) + a2·cos(4πn/N)
/// ```
///
/// Liší se jen koeficienty.
struct CosineTerms {
    a0: f64,
    a1: f64,
    a2: f64,
}

fn cosine_terms(kind: WindowKind) -> CosineTerms {
    match kind {
        WindowKind::Rectangular => CosineTerms {
            a0: 1.0,
            a1: 0.0,
            a2: 0.0,
        },
        WindowKind::Hann => CosineTerms {
            a0: 0.5,
            a1: 0.5,
            a2: 0.0,
        },
        // Hamming posunul poměr tak, aby se vyrušil první postranní lalok.
        WindowKind::Hamming => CosineTerms {
            a0: 0.54,
            a1: 0.46,
            a2: 0.0,
        },
        WindowKind::Blackman => CosineTerms {
            a0: 0.42,
            a1: 0.5,
            a2: 0.08,
        },
    }
}

/// Koeficienty okna délky `length` pro spektrální analýzu.
///
/// Jde o tzv. periodické okno (dělí se `N`, ne `N − 1`): je to jedna perioda
/// kosinusovek, takže okno se při opakování záznamu plynule navazuje.
/// Pro spektrální analýzu je to správná volba – nuly spektra okna pak padnou
/// přesně na celé biny.
pub fn window(kind: WindowKind, length: usize) -> Vec<f64> {
    cosine_window(kind, length, length as f64)
}

/// Symetrické okno délky `length` pro návrh filtrů (dělí se `N − 1`).
///
/// První a poslední vzorek jsou si rovny, takže filtr navržený s tímto oknem
/// má souměrné koeficienty a tedy lineární fázi.
pub fn symmetric_window(kind: WindowKind, length: usize) -> Vec<f64> {
    if length <= 1 {
        return vec![1.0; length];
    }
    cosine_window(kind, length, (length - 1) as f64)
}

/// Společný výpočet obou druhů oken; `period` je počet vzorků, na který
/// připadne jedna perioda kosinusovek.
fn cosine_window(kind: WindowKind, length: usize, period: f64) -> Vec<f64> {
    let terms = cosine_terms(kind);
    (0..length)
        .map(|n| {
            let angle = 2.0 * PI * n as f64 / period;
            terms.a0 - terms.a1 * angle.cos() + terms.a2 * (2.0 * angle).cos()
        })
        .collect()
}

/// Vynásobí signál oknem vzorek po vzorku.
pub fn apply_window(samples: &[f64], coefficients: &[f64]) -> Vec<f64> {
    assert_eq!(
        samples.len(),
        coefficients.len(),
        "signal and window must have the same length"
    );
    samples
        .iter()
        .zip(coefficients)
        .map(|(sample, weight)| sample * weight)
        .collect()
}

/// Doplní signál nulami na délku `length`.
///
/// Delší FFT pak vrátí víc bodů spektra, které leží mezi původními biny.
/// Spektrum se tím jen hustěji „navzorkuje“ – nové informace nepřibudou
/// a dvě blízké čáry se tím od sebe neoddělí.
pub fn zero_pad(samples: &[f64], length: usize) -> Vec<f64> {
    assert!(
        length >= samples.len(),
        "padded length must not be shorter than the signal"
    );
    let mut padded = samples.to_vec();
    padded.resize(length, 0.0);
    padded
}

/// Spektrum samotného okna: jak by ve spektru vypadala jedna čistá sinusovka.
#[derive(Clone, Debug, PartialEq)]
pub struct WindowResponse {
    /// Vzdálenost od středu čáry v binech původní délky okna (0 až N/2).
    pub offsets_bins: Vec<f64>,
    /// Útlum vůči středu čáry v decibelech (střed má 0 dB).
    pub magnitude_db: Vec<f64>,
}

/// Spočítá spektrum okna. Okno se doplní nulami na `fft_size` vzorků, aby
/// bylo vidět i to, co leží mezi celými biny (tvar laloků).
pub fn window_response(coefficients: &[f64], fft_size: usize) -> WindowResponse {
    let length = coefficients.len();
    let spectrum = fft(&real_to_complex(&zero_pad(coefficients, fft_size)));
    // Na nulové frekvenci je spektrum okna rovno součtu jeho koeficientů;
    // tím dělíme, aby střed čáry vyšel 0 dB.
    let sum: f64 = coefficients.iter().sum();
    let bins_per_point = length as f64 / fft_size as f64;

    let point_count = fft_size / 2 + 1;
    let mut offsets_bins = Vec::with_capacity(point_count);
    let mut magnitude_db = Vec::with_capacity(point_count);
    for (index, value) in spectrum.iter().enumerate().take(point_count) {
        offsets_bins.push(index as f64 * bins_per_point);
        magnitude_db.push(20.0 * (value.magnitude() / sum).max(MIN_RATIO).log10());
    }
    WindowResponse {
        offsets_bins,
        magnitude_db,
    }
}

/// Číselné vlastnosti okna.
#[derive(Clone, Debug, PartialEq)]
pub struct WindowProperties {
    /// Průměrná hodnota okna. O tolik okno zeslabí amplitudu sinusovky,
    /// proto se jí spektrum při výpočtu amplitudy dělí.
    pub coherent_gain: f64,
    /// Vzdálenost první nuly od středu čáry v binech (poloviční šířka hlavního laloku).
    pub main_lobe_half_width_bins: f64,
    /// Nejvyšší postranní lalok v decibelech vůči středu čáry.
    pub highest_side_lobe_db: f64,
}

/// Změří vlastnosti okna z jeho spektra.
pub fn analyze_window(coefficients: &[f64], response: &WindowResponse) -> WindowProperties {
    let sum: f64 = coefficients.iter().sum();
    let db = &response.magnitude_db;

    // Hlavní lalok končí prvním místním minimem (nulou) spektra.
    let first_null = (1..db.len().saturating_sub(1))
        .find(|&i| db[i] <= db[i - 1] && db[i] <= db[i + 1])
        .unwrap_or(db.len() - 1);

    // Za první nulou už jsou jen postranní laloky; hledáme ten nejvyšší.
    let highest_side_lobe_db = db[first_null..]
        .iter()
        .copied()
        .fold(f64::NEG_INFINITY, f64::max);

    WindowProperties {
        coherent_gain: sum / coefficients.len() as f64,
        main_lobe_half_width_bins: response.offsets_bins[first_null],
        highest_side_lobe_db,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dsp::signal::{Component, SignalSpec, Waveform, generate};
    use crate::dsp::spectrum::one_sided_spectrum;

    const TOLERANCE: f64 = 1e-12;

    fn properties(kind: WindowKind) -> WindowProperties {
        let coefficients = window(kind, 64);
        analyze_window(&coefficients, &window_response(&coefficients, 64 * 64))
    }

    fn sine_samples(frequency_bins: f64, length: usize) -> Vec<f64> {
        let spec = SignalSpec {
            components: vec![Component {
                enabled: true,
                waveform: Waveform::Sine,
                frequency_hz: frequency_bins,
                amplitude: 1.0,
                phase_deg: 0.0,
            }],
            dc_offset: 0.0,
            noise_amplitude: 0.0,
            noise_seed: 1,
        };
        // Vzorkovací frekvence = délka, takže 1 Hz = 1 bin.
        generate(&spec, length as f64, length)
    }

    #[test]
    fn hann_shape() {
        let hann = window(WindowKind::Hann, 8);
        assert!(hann[0].abs() < TOLERANCE);
        assert!((hann[4] - 1.0).abs() < TOLERANCE);
        assert!((hann[2] - 0.5).abs() < TOLERANCE);
        // Periodické okno je souměrné kolem prostředního vzorku: w[n] = w[N − n].
        assert!((hann[1] - hann[7]).abs() < TOLERANCE);
    }

    #[test]
    fn symmetric_hann_shape() {
        let hann = symmetric_window(WindowKind::Hann, 9);
        assert!(hann[0].abs() < TOLERANCE);
        assert!(hann[8].abs() < TOLERANCE);
        assert!((hann[4] - 1.0).abs() < TOLERANCE);
        assert_eq!(symmetric_window(WindowKind::Hann, 1), [1.0]);
    }

    #[test]
    fn rectangular_is_all_ones() {
        assert_eq!(window(WindowKind::Rectangular, 4), [1.0; 4]);
    }

    #[test]
    fn coherent_gain_equals_a0() {
        assert!((properties(WindowKind::Rectangular).coherent_gain - 1.0).abs() < TOLERANCE);
        assert!((properties(WindowKind::Hann).coherent_gain - 0.5).abs() < TOLERANCE);
        assert!((properties(WindowKind::Hamming).coherent_gain - 0.54).abs() < TOLERANCE);
        assert!((properties(WindowKind::Blackman).coherent_gain - 0.42).abs() < TOLERANCE);
    }

    #[test]
    fn main_lobe_widths() {
        let expected = [
            (WindowKind::Rectangular, 1.0),
            (WindowKind::Hann, 2.0),
            (WindowKind::Hamming, 2.0),
            (WindowKind::Blackman, 3.0),
        ];
        for (kind, half_width) in expected {
            let measured = properties(kind).main_lobe_half_width_bins;
            assert!((measured - half_width).abs() < 1e-9, "{kind:?}: {measured}");
        }
    }

    #[test]
    fn side_lobe_levels_match_textbook_values() {
        let expected = [
            (WindowKind::Rectangular, -13.3),
            (WindowKind::Hann, -31.5),
            (WindowKind::Hamming, -42.7),
            (WindowKind::Blackman, -58.1),
        ];
        for (kind, level_db) in expected {
            let measured = properties(kind).highest_side_lobe_db;
            assert!((measured - level_db).abs() < 0.5, "{kind:?}: {measured}");
        }
    }

    #[test]
    fn window_gain_is_compensated() {
        // Sinus s amplitudou 1 přesně v binu 8; po oknu i po doplnění nulami
        // musí spektrum ukázat amplitudu 1.
        let samples = sine_samples(8.0, 64);
        let hann = window(WindowKind::Hann, 64);
        let windowed = zero_pad(&apply_window(&samples, &hann), 256);
        let sum: f64 = hann.iter().sum();
        let lines = one_sided_spectrum(&fft(&real_to_complex(&windowed)), 64.0, sum);
        // Po čtyřnásobném doplnění nulami je frekvence 8 v binu 32.
        assert!((lines[32].frequency_hz - 8.0).abs() < TOLERANCE);
        assert!((lines[32].amplitude - 1.0).abs() < 1e-9);
    }

    #[test]
    fn between_bins_rectangular_loses_about_four_db() {
        // Frekvence přesně mezi biny: obdélníkové okno ukáže nejvyšší čáru
        // asi o 3,9 dB níž, než je skutečná amplituda (tzv. scalloping loss).
        // Záznam je dlouhý a frekvence daleko od nuly, aby výsledek neovlivnilo
        // prosakování zrcadlové čáry na záporné frekvenci.
        let samples = sine_samples(100.5, 1024);
        let lines = one_sided_spectrum(&fft(&real_to_complex(&samples)), 1024.0, 1024.0);
        let peak_db = lines
            .iter()
            .map(|line| line.amplitude_db)
            .fold(f64::NEG_INFINITY, f64::max);
        assert!((peak_db + 3.92).abs() < 0.1, "{peak_db}");
    }

    #[test]
    fn zero_pad_appends_zeros() {
        assert_eq!(zero_pad(&[1.0, 2.0], 4), [1.0, 2.0, 0.0, 0.0]);
    }
}
