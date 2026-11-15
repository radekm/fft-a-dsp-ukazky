//! Generátor syntetických signálů: součet periodických složek,
//! stejnosměrné složky a šumu.

use std::f64::consts::PI;

/// Tvar jedné periody signálu. Všechny tvary mají rozkmit −1 až 1.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Waveform {
    Sine,
    Square,
    Sawtooth,
    Triangle,
}

/// Jedna periodická složka signálu.
#[derive(Clone, Debug, PartialEq)]
pub struct Component {
    /// Vypnutá složka se do signálu nepřičítá.
    pub enabled: bool,
    pub waveform: Waveform,
    pub frequency_hz: f64,
    pub amplitude: f64,
    /// Počáteční fáze ve stupních.
    pub phase_deg: f64,
}

/// Úplný popis signálu.
#[derive(Clone, Debug, PartialEq)]
pub struct SignalSpec {
    pub components: Vec<Component>,
    /// Stejnosměrná složka (konstanta přičtená ke každému vzorku).
    pub dc_offset: f64,
    /// Šum je rovnoměrně rozložený v rozsahu ± tato hodnota.
    pub noise_amplitude: f64,
    /// Stejné semínko dává pokaždé stejný šum, takže graf neposkakuje.
    pub noise_seed: u64,
}

/// Vygeneruje `sample_count` vzorků signálu při dané vzorkovací frekvenci.
/// Vzorek číslo `n` odpovídá času `n / sample_rate_hz`.
pub fn generate(spec: &SignalSpec, sample_rate_hz: f64, sample_count: usize) -> Vec<f64> {
    let mut noise_state = noise_start(spec.noise_seed);
    let mut samples = Vec::with_capacity(sample_count);
    for index in 0..sample_count {
        let time_s = index as f64 / sample_rate_hz;
        let noise = spec.noise_amplitude * noise_next(&mut noise_state);
        samples.push(value_at(spec, time_s) + noise);
    }
    samples
}

/// Hodnota signálu v libovolném čase – takto si představujeme „spojitý“
/// (analogový) signál před vzorkováním. Šum se zde nepřičítá, protože
/// generátor šumu dává hodnoty jen postupně, vzorek po vzorku.
pub fn value_at(spec: &SignalSpec, time_s: f64) -> f64 {
    let mut value = spec.dc_offset;
    for component in &spec.components {
        if component.enabled {
            value += component_value(component, time_s);
        }
    }
    value
}

/// Hodnota jedné složky v daném čase.
fn component_value(component: &Component, time_s: f64) -> f64 {
    let angle_rad = 2.0 * PI * component.frequency_hz * time_s + component.phase_deg.to_radians();
    component.amplitude * waveform_value(component.waveform, angle_rad)
}

/// Hodnota průběhu pro daný úhel; jedna perioda odpovídá úhlu 2π.
/// Všechny průběhy začínají v nule a jdou nahoru, podobně jako sinus
/// (obdélník rovnou skočí na 1, pila začíná na −1).
fn waveform_value(waveform: Waveform, angle_rad: f64) -> f64 {
    // Poloha uvnitř periody: 0 = začátek, 1 = konec.
    let position = fraction(angle_rad / (2.0 * PI));
    match waveform {
        Waveform::Sine => angle_rad.sin(),
        Waveform::Square => {
            if position < 0.5 {
                1.0
            } else {
                -1.0
            }
        }
        Waveform::Sawtooth => 2.0 * position - 1.0,
        Waveform::Triangle => 4.0 * (fraction(position + 0.75) - 0.5).abs() - 1.0,
    }
}

/// Desetinná část čísla v rozsahu 0 až 1 (i pro záporná čísla).
fn fraction(value: f64) -> f64 {
    value - value.floor()
}

/// Počáteční stav generátoru šumu. Stav nesmí být nula, jinak by generátor
/// vracel samé nuly.
fn noise_start(seed: u64) -> u64 {
    if seed == 0 {
        0x9E37_79B9_7F4A_7C15
    } else {
        seed
    }
}

/// Další pseudonáhodné číslo rovnoměrně z rozsahu −1 až 1.
///
/// Generátor je xorshift64*: stav se zamíchá třemi posuny a operací XOR
/// a výsledek se vynásobí konstantou. Je krátký a pro ukázky bohatě stačí.
fn noise_next(state: &mut u64) -> f64 {
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    let random = x.wrapping_mul(0x2545_F491_4F6C_DD1D);
    // Horních 53 bitů převedeme na číslo 0 až 1 (tolik bitů má mantisa f64).
    let unit = (random >> 11) as f64 / (1u64 << 53) as f64;
    2.0 * unit - 1.0
}

#[cfg(test)]
mod tests {
    use super::*;

    const TOLERANCE: f64 = 1e-12;

    fn spec_with(component: Component) -> SignalSpec {
        SignalSpec {
            components: vec![component],
            dc_offset: 0.0,
            noise_amplitude: 0.0,
            noise_seed: 1,
        }
    }

    fn component(waveform: Waveform) -> Component {
        Component {
            enabled: true,
            waveform,
            frequency_hz: 1.0,
            amplitude: 1.0,
            phase_deg: 0.0,
        }
    }

    #[test]
    fn sine_quarter_period_is_peak() {
        // 1 Hz vzorkovaný 4 Hz: vzorky 0, 1, 0, −1.
        let samples = generate(&spec_with(component(Waveform::Sine)), 4.0, 4);
        let expected = [0.0, 1.0, 0.0, -1.0];
        for (sample, expected) in samples.iter().zip(expected) {
            assert!((sample - expected).abs() < TOLERANCE);
        }
    }

    #[test]
    fn waveform_shapes() {
        let quarter = PI / 2.0;
        assert_eq!(waveform_value(Waveform::Square, quarter), 1.0);
        assert_eq!(waveform_value(Waveform::Square, 3.0 * quarter), -1.0);
        assert!((waveform_value(Waveform::Sawtooth, PI)).abs() < TOLERANCE);
        assert!((waveform_value(Waveform::Triangle, 0.0)).abs() < TOLERANCE);
        assert!((waveform_value(Waveform::Triangle, quarter) - 1.0).abs() < TOLERANCE);
        assert!((waveform_value(Waveform::Triangle, 3.0 * quarter) + 1.0).abs() < TOLERANCE);
    }

    #[test]
    fn disabled_component_and_dc_offset() {
        let mut spec = spec_with(component(Waveform::Sine));
        spec.components[0].enabled = false;
        spec.dc_offset = 0.5;
        assert_eq!(generate(&spec, 8.0, 3), [0.5, 0.5, 0.5]);
    }

    #[test]
    fn noise_is_bounded_and_repeatable() {
        let mut spec = spec_with(component(Waveform::Sine));
        spec.components.clear();
        spec.noise_amplitude = 0.3;
        let first = generate(&spec, 100.0, 1000);
        let second = generate(&spec, 100.0, 1000);
        assert_eq!(first, second);
        assert!(first.iter().all(|sample| sample.abs() <= 0.3));
        // Šum nesmí být konstantní.
        assert!(first.iter().any(|sample| (sample - first[0]).abs() > 0.01));
    }
}
