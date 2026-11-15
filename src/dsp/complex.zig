//! Komplexní číslo – základní stavební kámen Fourierovy transformace.

const std = @import("std");

/// Komplexní číslo `re + j·im`.
pub const Complex = struct {
    /// Reálná část.
    re: f64,
    /// Imaginární část.
    im: f64,

    pub const zero: Complex = .{ .re = 0, .im = 0 };
    pub const one: Complex = .{ .re = 1, .im = 0 };

    pub fn init(re: f64, im: f64) Complex {
        return .{ .re = re, .im = im };
    }

    /// Číslo zadané velikostí a úhlem: `magnitude · e^(j·angle)`.
    /// Podle Eulerova vzorce je `e^(jφ) = cos φ + j·sin φ`.
    pub fn fromPolar(magnitude_value: f64, angle_rad: f64) Complex {
        return .{
            .re = magnitude_value * @cos(angle_rad),
            .im = magnitude_value * @sin(angle_rad),
        };
    }

    /// Velikost (absolutní hodnota): vzdálenost od počátku v komplexní rovině.
    pub fn magnitude(self: Complex) f64 {
        return std.math.hypot(self.re, self.im);
    }

    /// Úhel (fáze) v radiánech v rozsahu −π až π.
    pub fn phase(self: Complex) f64 {
        return std.math.atan2(self.im, self.re);
    }

    /// Násobení reálným číslem.
    pub fn scale(self: Complex, factor: f64) Complex {
        return .{ .re = self.re * factor, .im = self.im * factor };
    }

    pub fn add(self: Complex, other: Complex) Complex {
        return .{ .re = self.re + other.re, .im = self.im + other.im };
    }

    pub fn sub(self: Complex, other: Complex) Complex {
        return .{ .re = self.re - other.re, .im = self.im - other.im };
    }

    /// (a + jb)(c + jd) = (ac − bd) + j(ad + bc), protože j² = −1.
    pub fn mul(self: Complex, other: Complex) Complex {
        return .{
            .re = self.re * other.re - self.im * other.im,
            .im = self.re * other.im + self.im * other.re,
        };
    }
};

const testing = std.testing;
const tolerance = 1e-12;

test "multiplication follows j squared is minus one" {
    const j = Complex.init(0, 1);
    const product = j.mul(j);
    try testing.expectApproxEqAbs(-1.0, product.re, tolerance);
    try testing.expectApproxEqAbs(0.0, product.im, tolerance);
}

test "polar form round trips" {
    const value = Complex.fromPolar(2, std.math.pi / 3.0);
    try testing.expectApproxEqAbs(2.0, value.magnitude(), tolerance);
    try testing.expectApproxEqAbs(std.math.pi / 3.0, value.phase(), tolerance);
}

test "add sub scale" {
    const a = Complex.init(1, 2);
    const b = Complex.init(3, -5);
    try testing.expectEqual(Complex.init(4, -3), a.add(b));
    try testing.expectEqual(Complex.init(-2, 7), a.sub(b));
    try testing.expectEqual(Complex.init(2, 4), a.scale(2));
}
