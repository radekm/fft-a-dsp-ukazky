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

    // DVUI na macOS přidává do backendu SDL3 soubor macos_monitor.m (AppKit,
    // Objective-C), ale samo k němu nepřilinkuje potřebné knihovny: spoléhá na
    // SDL3 přeložené ze zdrojů. Se systémovým SDL3 je tedy přidáme sami.
    if (target.result.os.tag == .macos) {
        exe_mod.linkFramework("AppKit", .{});
        exe_mod.linkSystemLibrary("objc", .{});
    }

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

    addWebSteps(b, optimize, build_options);

    // Testy DSP běží bez DVUI a bez okna, testy UI potřebují přeložit DVUI.
    const dsp_tests = b.addTest(.{ .root_module = dsp_mod });
    const ui_tests = b.addTest(.{ .root_module = exe_mod });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(dsp_tests).step);
    test_step.dependOn(&b.addRunArtifact(ui_tests).step);
}

/// Webová verze: stejný program přeložený do WebAssembly (`wasm32-freestanding`)
/// s webovým backendem DVUI. Kreslí do `<canvas>` přes WebGL a události
/// z prohlížeče předává `web.js` z DVUI.
///
/// - `zig build web` nainstaluje do `zig-out/web/` soubory `index.html`,
///   `web.js` a `fft-dsp-demos.wasm`; servírovat je musí HTTP server.
/// - `zig build serve-web` je servíruje malým serverem z DVUI
///   na http://localhost:8080.
///
/// SDL3 (ani AppKit) se webu netýká, ten má vlastní backend.
fn addWebSteps(
    b: *std.Build,
    optimize: std.lang.Optimize,
    build_options: *std.Build.Step.Options,
) void {
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Druhá instance DVUI, tentokrát s webovým backendem a cílem wasm32.
    // Volby pro desktop (výše) zůstávají beze změny.
    const dvui_web_dep = b.dependency("dvui", .{
        .target = wasm_target,
        .optimize = optimize,
        .backend = .web,
        .@"tree-sitter" = false,
    });

    const dsp_mod = b.createModule(.{
        .root_source_file = b.path("src/dsp/dsp.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });

    const web_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_target,
        .optimize = optimize,
        // V prohlížeči není libc ani vlákna.
        .link_libc = false,
        .single_threaded = true,
        // Release verze bez ladicích informací je několikanásobně menší.
        .strip = optimize == .small or optimize == .fast,
    });
    web_mod.addImport("dvui", dvui_web_dep.module("dvui_web"));
    web_mod.addImport("dsp", dsp_mod);
    web_mod.addOptions("build_options", build_options);

    const wasm = b.addExecutable(.{
        .name = "fft-dsp-demos",
        .root_module = web_mod,
    });
    // Program nemá vstupní bod `_start`; funkce, které volá `web.js`
    // (`dvui_init`, `dvui_update`…), exportuje modul backendu z DVUI.
    wasm.entry = .disabled;

    const install_dir: std.Build.InstallDir = .{ .custom = "web" };
    const web_js = dvui_web_dep.namedLazyPath("web.js");

    // Do `index.html` se místo zástupného textu doplní otisk (SHA-256) souborů
    // `web.js` a `.wasm`. Prohlížeč pak po novém sestavení nepoužije starou
    // verzi z mezipaměti. Nástroj je součástí DVUI.
    const cache_buster = b.addExecutable(.{
        .name = "cacheBuster",
        .root_module = b.createModule(.{
            .root_source_file = dvui_web_dep.path("src/cacheBuster.zig"),
            .target = b.graph.host,
        }),
    });
    const cache_buster_run = b.addRunArtifact(cache_buster);
    cache_buster_run.addFileArg(b.path("web/index.html"));
    cache_buster_run.addFileArg(web_js);
    cache_buster_run.addFileArg(wasm.getEmittedBin());
    const index_html = cache_buster_run.captureStdOut(.{ .basename = "index.html" });

    const web_step = b.step("web", "Build the web (WebAssembly) version into zig-out/web");
    web_step.dependOn(&b.addInstallArtifact(wasm, .{ .dest_dir = .{ .override = install_dir } }).step);
    web_step.dependOn(&b.addInstallFileWithDir(web_js, install_dir, "web.js").step);
    web_step.dependOn(&b.addInstallFileWithDir(index_html, install_dir, "index.html").step);

    // Malý HTTP server z DVUI; servíruje právě tyto tři soubory na portu 8080.
    const server = b.addExecutable(.{
        .name = "serve-web",
        .root_module = b.createModule(.{
            .root_source_file = dvui_web_dep.path("tools/serve_web_demo.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    const serve_run = b.addRunArtifact(server);
    serve_run.addFileArg(index_html);
    serve_run.addFileArg(web_js);
    serve_run.addArtifactArg(wasm);
    const serve_step = b.step("serve-web", "Serve the web version at http://localhost:8080");
    serve_step.dependOn(&serve_run.step);
}
