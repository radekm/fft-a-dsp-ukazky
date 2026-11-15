//! Čisté výpočty DSP (FFT, okna, filtry, vzorkování). Tento modul nesmí
//! záviset na DVUI ani na jiné části uživatelského rozhraní; `build.zig` ho
//! překládá samostatně, takže by se to ani nepřeložilo.

const std = @import("std");

pub const complex = @import("complex.zig");
pub const fft = @import("fft.zig");
pub const filter = @import("filter.zig");
pub const sampling = @import("sampling.zig");
pub const signal = @import("signal.zig");
pub const spectrum = @import("spectrum.zig");
pub const window = @import("window.zig");

pub const Complex = complex.Complex;

test {
    // Zahrne testy ze všech podmodulů.
    std.testing.refAllDecls(@This());
}
