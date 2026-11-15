//! Čisté výpočty DSP. Tento modul nesmí záviset na DVUI ani na jiné části
//! uživatelského rozhraní; `build.zig` ho překládá samostatně.

const std = @import("std");

test {
    // Zahrne testy ze všech podmodulů.
    std.testing.refAllDecls(@This());
}
