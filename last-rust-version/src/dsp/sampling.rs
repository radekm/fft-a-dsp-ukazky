//! Vzorkování spojitého signálu, aliasing a rekonstrukce ze vzorků.
//!
//! Vzorkovací věta: signál, který neobsahuje frekvence od fs/2 výš
//! (Nyquistova frekvence), lze ze vzorků přesně obnovit. Vyšší frekvence se
//! po navzorkování nedají odlišit od nižších – „převlečou se“ za ně (alias).

use std::f64::consts::PI;

use super::signal::{SignalSpec, value_at};

/// Navzorkovaný signál: vzorek s indexem `n` patří času
/// `start_time_s + n / sample_rate_hz`.
#[derive(Clone, Debug, PartialEq)]
pub struct SampledSignal {
    pub sample_rate_hz: f64,
    pub start_time_s: f64,
    pub values: Vec<f64>,
}

/// Navzorkuje signál: `count` vzorků od času `start_time_s`.
pub fn sample(
    spec: &SignalSpec,
    sample_rate_hz: f64,
    start_time_s: f64,
    count: usize,
) -> SampledSignal {
    let values = (0..count)
        .map(|index| value_at(spec, start_time_s + index as f64 / sample_rate_hz))
        .collect();
    SampledSignal {
        sample_rate_hz,
        start_time_s,
        values,
    }
}

/// Čas vzorku s daným indexem.
pub fn sample_time(signal: &SampledSignal, index: usize) -> f64 {
    signal.start_time_s + index as f64 / signal.sample_rate_hz
}

/// Frekvence, na které se po navzorkování objeví sinusovka s frekvencí
/// `frequency_hz`. Výsledek leží vždy mezi 0 a fs/2.
///
/// Sinusovky f a f + k·fs mají ve vzorcích stejné hodnoty, protože se mezi
/// dvěma vzorky liší o celý počet otáček. A sinusovka −f vypadá stejně jako f
/// (jen s opačnou fází). Stačí tedy odečíst nejbližší násobek fs a vzít
/// absolutní hodnotu – frekvence se „zrcadlí“ kolem násobků fs/2.
pub fn alias_frequency(frequency_hz: f64, sample_rate_hz: f64) -> f64 {
    let nearest_multiple = (frequency_hz / sample_rate_hz).round() * sample_rate_hz;
    (frequency_hz - nearest_multiple).abs()
}

/// Normovaná funkce sinc: sin(πx) / (πx), v nule rovna 1.
///
/// Je nulová ve všech celých číslech kromě nuly – proto rekonstrukce prochází
/// přesně vzorky.
pub fn sinc(x: f64) -> f64 {
    if x.abs() < 1e-12 {
        1.0
    } else {
        (PI * x).sin() / (PI * x)
    }
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
pub fn reconstruct(signal: &SampledSignal, time_s: f64) -> f64 {
    signal
        .values
        .iter()
        .enumerate()
        .map(|(index, &value)| {
            let distance_in_samples = (time_s - sample_time(signal, index)) * signal.sample_rate_hz;
            value * sinc(distance_in_samples)
        })
        .sum()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dsp::signal::{Component, Waveform};

    const TOLERANCE: f64 = 1e-9;

    fn sine_spec(frequency_hz: f64) -> SignalSpec {
        SignalSpec {
            components: vec![Component {
                enabled: true,
                waveform: Waveform::Sine,
                frequency_hz,
                amplitude: 1.0,
                phase_deg: 0.0,
            }],
            dc_offset: 0.0,
            noise_amplitude: 0.0,
            noise_seed: 1,
        }
    }

    #[test]
    fn alias_frequencies() {
        let cases = [
            (5.0, 40.0, 5.0),
            (20.0, 40.0, 20.0),
            (30.0, 40.0, 10.0),
            (40.0, 40.0, 0.0),
            (70.0, 40.0, 10.0),
            (85.0, 40.0, 5.0),
        ];
        for (frequency, rate, expected) in cases {
            let alias = alias_frequency(frequency, rate);
            assert!(
                (alias - expected).abs() < TOLERANCE,
                "{frequency} Hz → {alias}"
            );
        }
    }

    #[test]
    fn sinc_values() {
        assert_eq!(sinc(0.0), 1.0);
        assert!(sinc(1.0).abs() < TOLERANCE);
        assert!(sinc(-3.0).abs() < TOLERANCE);
        assert!((sinc(0.5) - 2.0 / PI).abs() < TOLERANCE);
    }

    #[test]
    fn sample_times_follow_start_and_rate() {
        let sampled = sample(&sine_spec(1.0), 4.0, -0.5, 4);
        assert!((sample_time(&sampled, 0) + 0.5).abs() < TOLERANCE);
        assert!((sample_time(&sampled, 3) - 0.25).abs() < TOLERANCE);
        // sin(2π · (−0,25)) = −1
        assert!((sampled.values[1] + 1.0).abs() < TOLERANCE);
    }

    #[test]
    fn reconstruction_passes_through_samples() {
        let sampled = sample(&sine_spec(3.0), 20.0, 0.0, 40);
        for index in 0..sampled.values.len() {
            let restored = reconstruct(&sampled, sample_time(&sampled, index));
            assert!((restored - sampled.values[index]).abs() < TOLERANCE);
        }
    }

    #[test]
    fn reconstruction_restores_signal_below_nyquist() {
        // 10 Hz vzorkované 100 Hz: uprostřed dlouhého záznamu musí obnova
        // sedět i mezi vzorky.
        let spec = sine_spec(10.0);
        let sampled = sample(&spec, 100.0, -5.0, 1000);
        for step in 0..50 {
            let time_s = 0.0013 + step as f64 * 0.0071;
            let error = (reconstruct(&sampled, time_s) - value_at(&spec, time_s)).abs();
            assert!(error < 0.01, "t = {time_s}: error {error}");
        }
    }

    #[test]
    fn undersampled_sine_is_reconstructed_as_its_alias() {
        // 80 Hz vzorkované 100 Hz se obnoví jako 20 Hz s opačnou fází:
        // sin(2π·80·n/100) = sin(2π·(80 − 100)·n/100) = −sin(2π·20·n/100).
        let sampled = sample(&sine_spec(80.0), 100.0, -5.0, 1000);
        let alias = sine_spec(20.0);
        for step in 0..50 {
            let time_s = 0.0013 + step as f64 * 0.0071;
            let expected = -value_at(&alias, time_s);
            let error = (reconstruct(&sampled, time_s) - expected).abs();
            assert!(error < 0.01, "t = {time_s}: error {error}");
        }
    }
}
