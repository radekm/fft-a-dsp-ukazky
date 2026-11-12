//! Vstupní bod programu: nastaví hlášení chyb a logování a otevře okno.

mod app;
mod dsp;
mod ui;

use color_eyre::eyre::{Result, eyre};
use tracing::info;
use tracing_error::ErrorLayer;
use tracing_subscriber::filter::LevelFilter;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

/// Titulek okna.
const WINDOW_TITLE: &str = "FFT a DSP – ukázky";

fn main() -> Result<()> {
    color_eyre::install()?;
    init_logging()?;

    info!("starting application");

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

/// Logy jdou na standardní chybový výstup. `ErrorLayer` přidává k chybám
/// z color-eyre informaci, ve kterém tracing spanu vznikly.
fn init_logging() -> Result<()> {
    tracing_subscriber::registry()
        .with(LevelFilter::INFO)
        .with(tracing_subscriber::fmt::layer().with_writer(std::io::stderr))
        .with(ErrorLayer::default())
        .try_init()?;
    Ok(())
}
