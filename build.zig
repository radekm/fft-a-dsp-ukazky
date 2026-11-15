//! Sestavení programu. Povolené závislosti a jejich volby určuje AGENTS.md.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // SDL3 bereme ze systému a linkujeme dynamicky (odpovídá `zig build -fsys=sdl3`).
    // Musí se to vyhlásit dřív, než se načte DVUI, které tuto volbu čte.
    // Bez toho by DVUI překládalo SDL3 (a s ním X11, Wayland, dbus…) ze zdrojů.
    if (!b.systemIntegrationOption("sdl3", .{ .default = true })) {
        std.debug.panic("SDL3 must come from the system, do not use -fno-sys=sdl3", .{});
    }

    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
        // Zvýrazňování syntaxe v editoru kódu nepotřebujeme, ušetříme závislosti.
        .@"tree-sitter" = false,
    });

    // Verze programu pro log; musí odpovídat `.version` v build.zig.zon.
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", "0.2.0");

    // Čisté výpočty DSP – samostatný modul bez DVUI. Díky tomu překladač hlídá,
    // že DSP na uživatelském rozhraní nezávisí.
    const dsp_mod = b.createModule(.{
        .root_source_file = b.path("src/dsp/dsp.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    exe_mod.addImport("dsp", dsp_mod);
    exe_mod.addOptions("build_options", build_options);

    const exe = b.addExecutable(.{
        .name = "fft-dsp-demos",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run_cmd.step);

    // Testy DSP běží bez DVUI a bez okna.
    const dsp_tests = b.addTest(.{ .root_module = dsp_mod });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(dsp_tests).step);
}
