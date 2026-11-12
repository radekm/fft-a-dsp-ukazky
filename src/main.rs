//! Vstupní bod programu: nastaví hlášení chyb a logování a otevře okno.

mod app;
mod dsp;
mod ui;

use color_eyre::eyre::{Result, WrapErr, eyre};
use tracing::{Level, info};
use tracing_appender::non_blocking::WorkerGuard;
use tracing_appender::rolling::{RollingFileAppender, Rotation};
use tracing_error::ErrorLayer;
use tracing_subscriber::filter::LevelFilter;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

/// Titulek okna.
const WINDOW_TITLE: &str = "FFT a DSP – ukázky";

/// Adresář se soubory logu (relativně k pracovnímu adresáři).
const LOG_DIRECTORY: &str = "logs";
const LOG_FILE_PREFIX: &str = "fft-dsp-demos";
const LOG_FILE_SUFFIX: &str = "jsonl";
/// Kolik denních souborů logu se uchovává.
const MAX_LOG_FILES: usize = 7;

/// Proměnná prostředí, kterou lze změnit úroveň logování (např. `debug`).
const LOG_LEVEL_VARIABLE: &str = "LOG_LEVEL";
const DEFAULT_LOG_LEVEL: Level = Level::INFO;

fn main() -> Result<()> {
    color_eyre::install()?;
    // Hlídač musí žít do konce programu: při zániku dopíše zbytek logu do souboru.
    let _log_guard = init_logging()?;

    info!(version = env!("CARGO_PKG_VERSION"), "application started");

    let native_options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1100.0, 720.0])
            .with_min_inner_size([640.0, 400.0]),
        ..Default::default()
    };

    // Chybu z eframe převádíme na text, protože ji nelze bezpečně poslat mezi vlákny,
    // což typ chyby v color-eyre vyžaduje.
    eframe::run_native(
        WINDOW_TITLE,
        native_options,
        Box::new(|_cc| Ok(Box::new(app::App::default()))),
    )
    .map_err(|err| eyre!("failed to run the GUI: {err}"))?;

    info!("application closed");
    Ok(())
}

/// Nastaví strukturované logování.
///
/// Každá událost má kromě zprávy pojmenovaná pole (např. `fft_size = 1024`).
/// Do souboru se zapisuje jako JSON, jeden objekt na řádek, aby šel log
/// strojově zpracovat; na standardní chybový výstup jde tatáž událost
/// v čitelné podobě. `ErrorLayer` přidává k chybám z color-eyre informaci,
/// ve kterém tracing spanu vznikly.
fn init_logging() -> Result<WorkerGuard> {
    let file_appender = RollingFileAppender::builder()
        .rotation(Rotation::DAILY)
        .filename_prefix(LOG_FILE_PREFIX)
        .filename_suffix(LOG_FILE_SUFFIX)
        .max_log_files(MAX_LOG_FILES)
        .build(LOG_DIRECTORY)
        .wrap_err("failed to create the log file")?;
    // Zápis do souboru běží ve vlastním vlákně, aby nezdržoval kreslení okna.
    let (file_writer, guard) = tracing_appender::non_blocking(file_appender);

    tracing_subscriber::registry()
        .with(LevelFilter::from_level(log_level()))
        .with(tracing_subscriber::fmt::layer().with_writer(std::io::stderr))
        .with(
            tracing_subscriber::fmt::layer()
                .json()
                .with_writer(file_writer),
        )
        .with(ErrorLayer::default())
        .try_init()?;
    Ok(guard)
}

/// Úroveň logování z proměnné prostředí; když chybí nebo je neplatná,
/// použije se výchozí.
fn log_level() -> Level {
    std::env::var(LOG_LEVEL_VARIABLE)
        .ok()
        .and_then(|text| text.parse().ok())
        .unwrap_or(DEFAULT_LOG_LEVEL)
}
