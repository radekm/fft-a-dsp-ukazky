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

use std::f64::consts::PI;

use super::complex::Complex;
use super::sampling::sinc;
use super::window::{WindowKind, symmetric_window};

/// Nejmenší poměr, který převádíme na decibely (−240 dB).
const MIN_RATIO: f64 = 1e-12;

/// Druh filtru podle toho, co propouští.
// Názvy odpovídají zavedeným anglickým termínům (low-pass, high-pass,
// band-pass), proto je ponecháváme i se společnou koncovkou.
#[expect(
    clippy::enum_variant_names,
    reason = "low-pass, high-pass and band-pass are standard terms"
)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FilterType {
    /// Propouští frekvence pod mezní frekvencí.
    LowPass,
    /// Propouští frekvence nad mezní frekvencí.
    HighPass,
    /// Propouští pásmo kolem zvolené frekvence.
    BandPass,
}

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
/// přechodový děj. Výstup má stejnou délku jako vstup.
pub fn convolve(signal: &[f64], kernel: &[f64]) -> Vec<f64> {
    let mut output = Vec::with_capacity(signal.len());
    for n in 0..signal.len() {
        let mut sum = 0.0;
        // Bereme jen ty k, pro které vstupní vzorek x[n − k] existuje.
        for (k, &weight) in kernel.iter().enumerate().take(n + 1) {
            sum += weight * signal[n - k];
        }
        output.push(sum);
    }
    output
}

/// Zadání FIR filtru navrženého metodou okna.
#[derive(Clone, Debug, PartialEq)]
pub struct FirDesign {
    pub filter_type: FilterType,
    /// Mezní frekvence; u pásmové propusti dolní mez pásma.
    pub cutoff_hz: f64,
    /// Horní mez pásma; používá se jen u pásmové propusti.
    pub upper_cutoff_hz: f64,
    /// Počet koeficientů. Musí být lichý, aby měl filtr přesný střed.
    pub length: usize,
    pub window: WindowKind,
}

/// Navrhne FIR filtr metodou okna (windowed-sinc).
///
/// Ideální dolní propust má impulzní odezvu sinc, která je nekonečně dlouhá.
/// Usekneme ji na `length` vzorků a vynásobíme oknem, aby useknutí nezpůsobilo
/// zvlnění (jde o tentýž jev jako prosakování ve spektru). Ostatní typy se
/// z dolní propusti odvodí.
pub fn design_fir(design: &FirDesign, sample_rate_hz: f64) -> Vec<f64> {
    assert!(design.length % 2 == 1, "FIR length must be odd");
    let low_pass = |cutoff_hz: f64| {
        windowed_low_pass(cutoff_hz / sample_rate_hz, design.length, design.window)
    };
    match design.filter_type {
        FilterType::LowPass => low_pass(design.cutoff_hz),
        FilterType::HighPass => spectral_inversion(&low_pass(design.cutoff_hz)),
        // Pásmo = vše pod horní mezí minus vše pod dolní mezí.
        FilterType::BandPass => subtract(
            &low_pass(design.upper_cutoff_hz),
            &low_pass(design.cutoff_hz),
        ),
    }
}

/// Dolní propust: posunutá funkce sinc vynásobená oknem.
///
/// `cutoff_ratio` je mezní frekvence dělená vzorkovací frekvencí (0 až 0,5).
/// Ideální odezva je `h[n] = 2·fc · sinc(2·fc · (n − střed))`.
fn windowed_low_pass(cutoff_ratio: f64, length: usize, window: WindowKind) -> Vec<f64> {
    let center = (length - 1) as f64 / 2.0;
    let weights = symmetric_window(window, length);
    let mut coefficients: Vec<f64> = (0..length)
        .map(|n| {
            let ideal = 2.0 * cutoff_ratio * sinc(2.0 * cutoff_ratio * (n as f64 - center));
            ideal * weights[n]
        })
        .collect();

    // Zesílení na nulové frekvenci je součet koeficientů. Po useknutí a okně
    // není přesně 1, proto koeficienty vydělíme, aby stejnosměrná složka
    // prošla beze změny.
    let sum: f64 = coefficients.iter().sum();
    for coefficient in &mut coefficients {
        *coefficient /= sum;
    }
    coefficients
}

/// Z dolní propusti udělá horní propust: `h_HP[n] = δ[n − střed] − h_LP[n]`.
/// Tedy „původní signál minus to, co propustí dolní propust“.
fn spectral_inversion(low_pass: &[f64]) -> Vec<f64> {
    let center = low_pass.len() / 2;
    let mut high_pass: Vec<f64> = low_pass.iter().map(|value| -value).collect();
    high_pass[center] += 1.0;
    high_pass
}

fn subtract(left: &[f64], right: &[f64]) -> Vec<f64> {
    left.iter().zip(right).map(|(a, b)| a - b).collect()
}

// ---------------------------------------------------------------------------
// IIR – bikvadratický filtr
// ---------------------------------------------------------------------------

/// Bikvadratický filtr (biquad): IIR filtr druhého řádu.
///
/// `y[n] = b0·x[n] + b1·x[n−1] + b2·x[n−2] − a1·y[n−1] − a2·y[n−2]`
#[derive(Clone, Debug, PartialEq)]
pub struct Biquad {
    /// Koeficienty u vstupních vzorků: b0, b1, b2.
    pub b: [f64; 3],
    /// Koeficienty u výstupních vzorků: a0 (vždy 1), a1, a2.
    pub a: [f64; 3],
}

/// Navrhne bikvadratický filtr podle známé „kuchařky“ R. Bristow-Johnsona
/// (Audio EQ Cookbook).
///
/// `frequency_hz` je mezní frekvence (dolní a horní propust) nebo střed pásma
/// (pásmová propust). `q` je činitel jakosti: čím větší, tím ostřejší
/// zlom nebo užší pásmo. Q = 1/√2 ≈ 0,707 dává nejplošší propustné pásmo.
pub fn design_biquad(
    filter_type: FilterType,
    frequency_hz: f64,
    q: f64,
    sample_rate_hz: f64,
) -> Biquad {
    // Úhlová frekvence na jeden vzorek (0 až π).
    let omega = 2.0 * PI * frequency_hz / sample_rate_hz;
    let cos_omega = omega.cos();
    let alpha = omega.sin() / (2.0 * q);

    let b = match filter_type {
        FilterType::LowPass => [
            (1.0 - cos_omega) / 2.0,
            1.0 - cos_omega,
            (1.0 - cos_omega) / 2.0,
        ],
        FilterType::HighPass => [
            (1.0 + cos_omega) / 2.0,
            -(1.0 + cos_omega),
            (1.0 + cos_omega) / 2.0,
        ],
        // Varianta se zesílením 0 dB na střední frekvenci.
        FilterType::BandPass => [alpha, 0.0, -alpha],
    };
    let a0 = 1.0 + alpha;
    let a = [a0, -2.0 * cos_omega, 1.0 - alpha];

    // Vydělíme vše koeficientem a0, aby v rovnici stál výstup y[n] sám.
    Biquad {
        b: [b[0] / a0, b[1] / a0, b[2] / a0],
        a: [1.0, a[1] / a0, a[2] / a0],
    }
}

/// Profiltruje signál bikvadratickým filtrem (tzv. přímá forma I).
/// Předchozí vzorky před začátkem signálu bereme jako nuly.
pub fn biquad_filter(biquad: &Biquad, signal: &[f64]) -> Vec<f64> {
    let [b0, b1, b2] = biquad.b;
    let [_, a1, a2] = biquad.a;
    // Paměť filtru: dva předchozí vstupy a dva předchozí výstupy.
    let (mut x1, mut x2, mut y1, mut y2) = (0.0, 0.0, 0.0, 0.0);
    let mut output = Vec::with_capacity(signal.len());
    for &x0 in signal {
        let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        output.push(y0);
        x2 = x1;
        x1 = x0;
        y2 = y1;
        y1 = y0;
    }
    output
}

/// Impulzní odezva: výstup filtru, když na vstup přijde jediný jednotkový
/// vzorek a pak samé nuly. U IIR je nekonečná, vracíme prvních `length` vzorků.
pub fn biquad_impulse_response(biquad: &Biquad, length: usize) -> Vec<f64> {
    let mut impulse = vec![0.0; length];
    if let Some(first) = impulse.first_mut() {
        *first = 1.0;
    }
    biquad_filter(biquad, &impulse)
}

// ---------------------------------------------------------------------------
// Frekvenční charakteristika
// ---------------------------------------------------------------------------

/// Jeden bod frekvenční charakteristiky.
#[derive(Clone, Debug, PartialEq)]
pub struct ResponsePoint {
    pub frequency_hz: f64,
    /// Zesílení: kolikrát filtr zvětší amplitudu sinusovky této frekvence.
    pub magnitude: f64,
    pub magnitude_db: f64,
    /// Fázový posun ve stupních (−180° až 180°).
    pub phase_deg: f64,
}

/// Frekvenční charakteristika filtru s koeficienty `b` a `a` (a[0] = 1)
/// v `point_count` bodech od 0 do fs/2.
///
/// Sinusovka e^(jωn) projde lineárním filtrem jako sinusovka stejné
/// frekvence, jen vynásobená komplexním číslem
///
/// ```text
/// H(ω) = (b0 + b1·e^(−jω) + b2·e^(−2jω) + …) / (a0 + a1·e^(−jω) + …)
/// ```
///
/// Jeho velikost je zesílení a úhel fázový posun.
pub fn frequency_response(
    b: &[f64],
    a: &[f64],
    sample_rate_hz: f64,
    point_count: usize,
) -> Vec<ResponsePoint> {
    assert!(point_count >= 2, "need at least two points");
    (0..point_count)
        .map(|index| {
            let frequency_hz = sample_rate_hz / 2.0 * index as f64 / (point_count - 1) as f64;
            let omega = 2.0 * PI * frequency_hz / sample_rate_hz;
            let numerator = evaluate_polynomial(b, omega);
            let denominator = evaluate_polynomial(a, omega);
            let response = divide(numerator, denominator);
            let magnitude = response.magnitude();
            ResponsePoint {
                frequency_hz,
                magnitude,
                magnitude_db: 20.0 * magnitude.max(MIN_RATIO).log10(),
                phase_deg: response.phase().to_degrees(),
            }
        })
        .collect()
}

/// Spočítá Σ c[k] · e^(−jωk).
fn evaluate_polynomial(coefficients: &[f64], omega: f64) -> Complex {
    coefficients
        .iter()
        .enumerate()
        .fold(Complex::ZERO, |sum, (k, &coefficient)| {
            sum + Complex::from_polar(coefficient, -omega * k as f64)
        })
}

/// Podíl komplexních čísel: velikosti se dělí, úhly odečítají.
fn divide(numerator: Complex, denominator: Complex) -> Complex {
    Complex::from_polar(
        numerator.magnitude() / denominator.magnitude(),
        numerator.phase() - denominator.phase(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dsp::fft::{fft, real_to_complex};

    const TOLERANCE: f64 = 1e-9;
    const RATE: f64 = 1000.0;

    /// Zesílení filtru na jedné frekvenci.
    fn gain(b: &[f64], a: &[f64], frequency_hz: f64) -> f64 {
        // 1001 bodů od 0 do 500 Hz: bod i leží na frekvenci i/2 Hz.
        let response = frequency_response(b, a, RATE, 1001);
        response[(frequency_hz * 2.0).round() as usize].magnitude
    }

    fn fir(filter_type: FilterType, cutoff_hz: f64, upper_cutoff_hz: f64) -> Vec<f64> {
        design_fir(
            &FirDesign {
                filter_type,
                cutoff_hz,
                upper_cutoff_hz,
                length: 101,
                window: WindowKind::Hamming,
            },
            RATE,
        )
    }

    #[test]
    fn convolution_examples() {
        assert_eq!(convolve(&[1.0, 2.0, 3.0], &[1.0]), [1.0, 2.0, 3.0]);
        // Jednotkový impulz na vstupu vrátí jádro.
        assert_eq!(
            convolve(&[1.0, 0.0, 0.0, 0.0], &[0.5, 0.25]),
            [0.5, 0.25, 0.0, 0.0]
        );
        // Klouzavý průměr dvou vzorků.
        assert_eq!(convolve(&[2.0, 4.0, 6.0], &[0.5, 0.5]), [1.0, 3.0, 5.0]);
    }

    #[test]
    fn fir_low_pass() {
        let h = fir(FilterType::LowPass, 100.0, 0.0);
        assert!((gain(&h, &[1.0], 0.0) - 1.0).abs() < TOLERANCE);
        // Na mezní frekvenci má filtr navržený metodou okna zesílení 1/2 (−6 dB).
        assert!((gain(&h, &[1.0], 100.0) - 0.5).abs() < 0.02);
        assert!(gain(&h, &[1.0], 200.0) < 0.01);
        // Souměrné koeficienty = lineární fáze.
        for n in 0..h.len() {
            assert!((h[n] - h[h.len() - 1 - n]).abs() < TOLERANCE);
        }
    }

    #[test]
    fn fir_high_pass() {
        let h = fir(FilterType::HighPass, 100.0, 0.0);
        assert!(gain(&h, &[1.0], 0.0) < TOLERANCE);
        assert!(gain(&h, &[1.0], 30.0) < 0.01);
        assert!((gain(&h, &[1.0], 300.0) - 1.0).abs() < 0.01);
        assert!((gain(&h, &[1.0], 500.0) - 1.0).abs() < 0.01);
    }

    #[test]
    fn fir_band_pass() {
        let h = fir(FilterType::BandPass, 100.0, 200.0);
        assert!(gain(&h, &[1.0], 0.0) < TOLERANCE);
        assert!((gain(&h, &[1.0], 150.0) - 1.0).abs() < 0.01);
        assert!(gain(&h, &[1.0], 30.0) < 0.01);
        assert!(gain(&h, &[1.0], 300.0) < 0.01);
    }

    #[test]
    fn fir_filters_sine_by_its_gain() {
        // Po odeznění přechodového děje má sinusovka na výstupu amplitudu
        // vynásobenou zesílením filtru na její frekvenci.
        let h = fir(FilterType::LowPass, 100.0, 0.0);
        let input: Vec<f64> = (0..2000)
            .map(|n| (2.0 * PI * 90.0 * n as f64 / RATE).sin())
            .collect();
        let output = convolve(&input, &h);
        let peak = output[500..]
            .iter()
            .fold(0.0f64, |max, value| max.max(value.abs()));
        assert!((peak - gain(&h, &[1.0], 90.0)).abs() < 0.01);
    }

    #[test]
    fn biquad_gains_at_characteristic_frequencies() {
        let q = 1.0 / 2f64.sqrt();
        let low = design_biquad(FilterType::LowPass, 100.0, q, RATE);
        assert!((gain(&low.b, &low.a, 0.0) - 1.0).abs() < TOLERANCE);
        // Na mezní frekvenci má dolní i horní propust zesílení rovné Q.
        assert!((gain(&low.b, &low.a, 100.0) - q).abs() < TOLERANCE);
        assert!(gain(&low.b, &low.a, 500.0) < TOLERANCE);

        let high = design_biquad(FilterType::HighPass, 100.0, q, RATE);
        assert!(gain(&high.b, &high.a, 0.0) < TOLERANCE);
        assert!((gain(&high.b, &high.a, 100.0) - q).abs() < TOLERANCE);
        assert!((gain(&high.b, &high.a, 500.0) - 1.0).abs() < TOLERANCE);

        let band = design_biquad(FilterType::BandPass, 100.0, 5.0, RATE);
        assert!((gain(&band.b, &band.a, 100.0) - 1.0).abs() < TOLERANCE);
        assert!(gain(&band.b, &band.a, 0.0) < TOLERANCE);
    }

    #[test]
    fn biquad_impulse_response_matches_frequency_response() {
        // FFT impulzní odezvy je frekvenční charakteristika – dvě nezávislé
        // cesty k témuž výsledku se musí shodnout.
        let biquad = design_biquad(FilterType::LowPass, 100.0, 2.0, RATE);
        let impulse = biquad_impulse_response(&biquad, 4096);
        let spectrum = fft(&real_to_complex(&impulse));
        let response = frequency_response(&biquad.b, &biquad.a, RATE, 2049);
        for bin in (0..=2048).step_by(64) {
            let difference = (spectrum[bin].magnitude() - response[bin].magnitude).abs();
            assert!(difference < 1e-6, "bin {bin}: {difference}");
        }
    }
}
