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

use std::f64::consts::PI;

use super::complex::Complex;

/// Znaménko v exponentu pro dopřednou transformaci (čas → frekvence).
const FORWARD: f64 = -1.0;
/// Znaménko v exponentu pro zpětnou transformaci (frekvence → čas).
const INVERSE: f64 = 1.0;

/// Převede reálné vzorky na komplexní čísla s nulovou imaginární částí.
pub fn real_to_complex(samples: &[f64]) -> Vec<Complex> {
    samples
        .iter()
        .map(|&sample| Complex::new(sample, 0.0))
        .collect()
}

/// Pomalá DFT přesně podle definice. Funguje pro libovolnou délku.
pub fn dft(input: &[Complex]) -> Vec<Complex> {
    let n = input.len();
    let mut output = Vec::with_capacity(n);
    for k in 0..n {
        let mut sum = Complex::ZERO;
        for (index, &sample) in input.iter().enumerate() {
            // Úhel se opakuje po celých otáčkách, proto stačí zbytek k·n mod N.
            // Udržuje to úhel malý a výpočet přesný.
            let turns = ((k * index) % n) as f64 / n as f64;
            let rotation = Complex::from_polar(1.0, FORWARD * 2.0 * PI * turns);
            sum = sum + sample * rotation;
        }
        output.push(sum);
    }
    output
}

/// Rychlá Fourierova transformace. Délka vstupu musí být mocnina dvou.
pub fn fft(input: &[Complex]) -> Vec<Complex> {
    transform(input, FORWARD)
}

/// Zpětná FFT: ze spektra vrátí původní vzorky.
/// Liší se jen znaménkem v exponentu a dělením délkou `N`.
pub fn ifft(input: &[Complex]) -> Vec<Complex> {
    let n = input.len();
    let unscaled = transform(input, INVERSE);
    unscaled
        .iter()
        .map(|value| value.scale(1.0 / n as f64))
        .collect()
}

/// Společné jádro dopředné i zpětné FFT (iterativní algoritmus Cooley–Tukey).
///
/// Myšlenka: DFT délky N lze složit ze dvou DFT délky N/2 – jedné ze sudých
/// a jedné z lichých vzorků. Opakovaným půlením dojdeme až k délce 1, kde je
/// DFT vzorku on sám. Proto nejdřív vzorky přerovnáme (bitová reverze) a pak
/// je po etapách skládáme do bloků délky 2, 4, 8, … N.
fn transform(input: &[Complex], sign: f64) -> Vec<Complex> {
    let n = input.len();
    assert!(
        n.is_power_of_two(),
        "FFT length must be a power of two, got {n}"
    );

    let mut data = bit_reverse_permutation(input);
    let mut block_size = 2;
    while block_size <= n {
        butterfly_stage(&mut data, block_size, sign);
        block_size *= 2;
    }
    data
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
fn butterfly_stage(data: &mut [Complex], block_size: usize, sign: f64) {
    let half = block_size / 2;
    // O tento úhel se `w` pootočí mezi dvěma sousedními motýlky.
    let step = Complex::from_polar(1.0, sign * 2.0 * PI / block_size as f64);

    for block_start in (0..data.len()).step_by(block_size) {
        let mut w = Complex::ONE;
        for k in 0..half {
            let top = block_start + k;
            let bottom = top + half;
            let a = data[top];
            let b = w * data[bottom];
            data[top] = a + b;
            data[bottom] = a - b;
            w = w * step;
        }
    }
}

/// Přerovná vzorky tak, že vzorek s indexem `i` skončí na indexu, který má
/// bity čísla `i` v opačném pořadí (např. pro N = 8: 1 = 001 → 100 = 4).
/// Přesně takové pořadí vznikne opakovaným dělením na sudé a liché vzorky.
fn bit_reverse_permutation(input: &[Complex]) -> Vec<Complex> {
    let n = input.len();
    let bit_count = n.trailing_zeros();
    let mut output = vec![Complex::ZERO; n];
    for (index, &value) in input.iter().enumerate() {
        output[reverse_bits(index, bit_count)] = value;
    }
    output
}

/// Otočí pořadí spodních `bit_count` bitů čísla `value`.
fn reverse_bits(value: usize, bit_count: u32) -> usize {
    let mut remaining = value;
    let mut reversed = 0;
    for _ in 0..bit_count {
        reversed = (reversed << 1) | (remaining & 1);
        remaining >>= 1;
    }
    reversed
}

#[cfg(test)]
mod tests {
    use super::*;

    const TOLERANCE: f64 = 1e-9;

    /// Testovací signál bez jakékoli symetrie, aby se chyba neschovala.
    fn test_signal(n: usize) -> Vec<Complex> {
        (0..n)
            .map(|i| {
                let t = i as f64;
                Complex::new(
                    (0.37 * t).sin() + 0.5 * (1.3 * t).cos(),
                    0.25 * (0.9 * t).sin(),
                )
            })
            .collect()
    }

    fn assert_close(actual: &[Complex], expected: &[Complex]) {
        assert_eq!(actual.len(), expected.len());
        for (a, e) in actual.iter().zip(expected) {
            assert!((*a - *e).magnitude() < TOLERANCE, "{a:?} != {e:?}");
        }
    }

    #[test]
    fn fft_matches_dft() {
        for exponent in 0..=8 {
            let signal = test_signal(1 << exponent);
            assert_close(&fft(&signal), &dft(&signal));
        }
    }

    #[test]
    fn ifft_restores_signal() {
        let signal = test_signal(256);
        assert_close(&ifft(&fft(&signal)), &signal);
    }

    #[test]
    fn impulse_has_flat_spectrum() {
        let mut signal = vec![Complex::ZERO; 16];
        signal[0] = Complex::ONE;
        assert_close(&fft(&signal), &[Complex::ONE; 16]);
    }

    #[test]
    fn cosine_lands_in_its_bin() {
        // Kosinus, který se za 64 vzorků zopakuje 5krát, patří do binů 5 a 64−5.
        let n = 64;
        let samples: Vec<f64> = (0..n)
            .map(|i| (2.0 * PI * 5.0 * i as f64 / n as f64).cos())
            .collect();
        let spectrum = fft(&real_to_complex(&samples));
        for (bin, value) in spectrum.iter().enumerate() {
            let expected = if bin == 5 || bin == n - 5 {
                n as f64 / 2.0
            } else {
                0.0
            };
            assert!(
                (value.magnitude() - expected).abs() < TOLERANCE,
                "bin {bin}"
            );
        }
    }

    #[test]
    fn bit_reversal_for_eight_points() {
        let reversed: Vec<usize> = (0..8).map(|i| reverse_bits(i, 3)).collect();
        assert_eq!(reversed, [0, 4, 2, 6, 1, 5, 3, 7]);
    }

    #[test]
    #[should_panic(expected = "power of two")]
    fn fft_rejects_other_lengths() {
        fft(&test_signal(12));
    }
}
