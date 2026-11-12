//! Komplexní číslo – základní stavební kámen Fourierovy transformace.

use std::ops::{Add, Mul, Sub};

/// Komplexní číslo `re + j·im`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Complex {
    /// Reálná část.
    pub re: f64,
    /// Imaginární část.
    pub im: f64,
}

impl Complex {
    pub const ZERO: Complex = Complex { re: 0.0, im: 0.0 };
    pub const ONE: Complex = Complex { re: 1.0, im: 0.0 };

    pub fn new(re: f64, im: f64) -> Complex {
        Complex { re, im }
    }

    /// Číslo zadané velikostí a úhlem: `magnitude · e^(j·angle)`.
    /// Podle Eulerova vzorce je `e^(jφ) = cos φ + j·sin φ`.
    pub fn from_polar(magnitude: f64, angle_rad: f64) -> Complex {
        Complex {
            re: magnitude * angle_rad.cos(),
            im: magnitude * angle_rad.sin(),
        }
    }

    /// Velikost (absolutní hodnota): vzdálenost od počátku v komplexní rovině.
    pub fn magnitude(self) -> f64 {
        self.re.hypot(self.im)
    }

    /// Úhel (fáze) v radiánech v rozsahu −π až π.
    pub fn phase(self) -> f64 {
        self.im.atan2(self.re)
    }

    /// Násobení reálným číslem.
    pub fn scale(self, factor: f64) -> Complex {
        Complex {
            re: self.re * factor,
            im: self.im * factor,
        }
    }
}

impl Add for Complex {
    type Output = Complex;

    fn add(self, other: Complex) -> Complex {
        Complex {
            re: self.re + other.re,
            im: self.im + other.im,
        }
    }
}

impl Sub for Complex {
    type Output = Complex;

    fn sub(self, other: Complex) -> Complex {
        Complex {
            re: self.re - other.re,
            im: self.im - other.im,
        }
    }
}

impl Mul for Complex {
    type Output = Complex;

    /// (a + jb)(c + jd) = (ac − bd) + j(ad + bc), protože j² = −1.
    fn mul(self, other: Complex) -> Complex {
        Complex {
            re: self.re * other.re - self.im * other.im,
            im: self.re * other.im + self.im * other.re,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f64::consts::PI;

    const TOLERANCE: f64 = 1e-12;

    #[test]
    fn multiplication_follows_j_squared_is_minus_one() {
        let j = Complex::new(0.0, 1.0);
        let product = j * j;
        assert!((product.re + 1.0).abs() < TOLERANCE);
        assert!(product.im.abs() < TOLERANCE);
    }

    #[test]
    fn polar_form_round_trips() {
        let value = Complex::from_polar(2.0, PI / 3.0);
        assert!((value.magnitude() - 2.0).abs() < TOLERANCE);
        assert!((value.phase() - PI / 3.0).abs() < TOLERANCE);
    }

    #[test]
    fn add_sub_scale() {
        let a = Complex::new(1.0, 2.0);
        let b = Complex::new(3.0, -5.0);
        assert_eq!(a + b, Complex::new(4.0, -3.0));
        assert_eq!(a - b, Complex::new(-2.0, 7.0));
        assert_eq!(a.scale(2.0), Complex::new(2.0, 4.0));
    }
}
