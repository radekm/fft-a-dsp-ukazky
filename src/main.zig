//! Vstupní bod programu: nastaví logování, motiv s písmem Inter a otevře okno.
//!
//! Hlavní smyčku řídí DVUI (`dvui.App`): my dodáme funkci pro start,
//! inicializaci, jeden snímek a ukončení.

const std = @import("std");
const dvui = @import("dvui");
const build_options = @import("build_options");

const App = @import("app.zig").App;

const log = std.log.scoped(.main);

/// Titulek okna.
const window_title = "FFT a DSP – ukázky";

/// Proměnná prostředí, kterou lze změnit úroveň logování (např. `debug`).
const log_level_variable = "LOG_LEVEL";
const default_log_level: std.log.Level = .info;

/// Úroveň logování platná za běhu. Nastaví se při startu z proměnné prostředí.
var runtime_log_level: std.log.Level = default_log_level;

/// Zámek pro standardní výstup, aby se řádky logu z více vláken nepromíchaly.
var stdout_mutex: std.Io.Mutex = .init;

/// Stav celé aplikace. Žije po celou dobu běhu programu.
var app: App = .{};

pub const dvui_app: dvui.App = .{
    .config = .{ .startFn = start },
    .initFn = init,
    .deinitFn = deinit,
    .frameFn = frame,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;

pub const std_options: std.Options = .{
    // Za překladu propustíme všechny úrovně; filtruje až `logFn` podle
    // `runtime_log_level`, aby šla úroveň změnit bez nového překladu.
    .log_level = .debug,
    .logFn = logFn,
};

/// Zapíše jednu zprávu logu na standardní výstup jako jeden řádek
/// ve tvaru `info(scope): zpráva klic=hodnota`.
fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    // Nižší číslo = závažnější zpráva (err = 0, debug = 3).
    if (@backingInt(level) > @backingInt(runtime_log_level)) return;

    const io = std.Options.debug_io;
    // Zápis logu se nesmí přerušit uprostřed řádku.
    const previous_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(previous_protection);

    stdout_mutex.lockUncancelable(io);
    defer stdout_mutex.unlock(io);

    var buffer: [256]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(io, &buffer);
    const writer = &file_writer.interface;
    const prefix = comptime level.asText() ++ "(" ++ @tagName(scope) ++ "): ";
    // Chybu zápisu nemá kam ohlásit; log je jen pomocník, program kvůli němu nespadne.
    writer.print(prefix ++ format ++ "\n", args) catch return;
    writer.flush() catch return;
}

/// Zjistí úroveň logování z proměnné prostředí; když chybí nebo je neplatná,
/// použije se výchozí.
fn logLevelFromEnvironment() std.log.Level {
    const main_init = dvui.App.main_init orelse return default_log_level;
    const text = main_init.environ_map.get(log_level_variable) orelse return default_log_level;
    for ([_]std.log.Level{ .err, .warn, .info, .debug }) |level| {
        if (std.ascii.eqlIgnoreCase(text, @tagName(level))) return level;
    }
    // Tolerujeme i názvy z Rust verze (tracing).
    if (std.ascii.eqlIgnoreCase(text, "error")) return .err;
    if (std.ascii.eqlIgnoreCase(text, "trace")) return .debug;
    return default_log_level;
}

/// Spustí se jako první, ještě před otevřením okna.
fn start() dvui.App.StartOptions {
    runtime_log_level = logLevelFromEnvironment();
    log.info("application started version={s}", .{build_options.version});

    return .{
        .size = .{ .w = 1100, .h = 720 },
        .min_size = .{ .w = 640, .h = 400 },
        .title = window_title,
        .app = "fft-dsp-demos",
        .org = "fft-dsp-demos",
        // Rust verze si velikost okna nepamatovala, držíme se toho.
        .persist_window_geometry = false,
        .window_init_options = .{
            .keybinds_zoom = true,
            .theme = theme(),
        },
    };
}

/// Písmo Inter vložené přímo do programu. Výchozí písmo DVUI (Bitstream Vera)
/// nemá znaky ř, ť, ň, ů, ě, ď. Tučný řez se musí zaregistrovat jako zvláštní
/// zdroj: `dvui.addFont` umí přidat jen běžný řez.
const inter_fonts = [_]dvui.Font.Source{
    .{
        .family = dvui.Font.array("Inter"),
        .bytes = @embedFile("fonts/Inter_18pt-Regular.ttf"),
    },
    .{
        .family = dvui.Font.array("Inter"),
        .weight = .bold,
        .bytes = @embedFile("fonts/Inter_18pt-Bold.ttf"),
    },
};

/// Velikost běžného textu v logických pixelech.
const body_font_size = 13;

/// Světlý motiv DVUI s písmem Inter (Rust verze měla tmavý).
fn theme() dvui.Theme {
    var result = dvui.Theme.builtin.adwaita_light;
    result.embedded_fonts = &inter_fonts;
    result.font_body = .find(.{ .family = "Inter", .size = body_font_size });
    result.font_heading = .find(.{ .family = "Inter", .weight = .bold, .size = body_font_size });
    // Nadpisy oddílů jsou větší, ale ne tučné (jako `ui.heading` v egui).
    result.font_title = .find(.{ .family = "Inter", .size = body_font_size + 4 });
    return result;
}

/// Spustí se po otevření okna, před prvním snímkem.
fn init(win: *dvui.Window) !void {
    _ = win;
    log.debug("window initialized", .{});
}

/// Spustí se při zavírání okna.
fn deinit(win: *dvui.Window) void {
    app.deinit(win.gpa);
    log.info("application closed", .{});
}

/// Nakreslí jeden snímek.
fn frame() !dvui.App.Result {
    try app.frame(dvui.currentWindow().gpa);
    return .ok;
}

test {
    // Testy uživatelského rozhraní, které nepotřebují okno.
    _ = @import("ui/plot.zig");
}
