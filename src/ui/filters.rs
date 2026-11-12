//! Záložka „Filtry“ (fáze 4).

/// Nakreslí obsah záložky.
pub fn show(ui: &mut egui::Ui) {
    super::placeholder(
        ui,
        "Filtry",
        "Návrh FIR a IIR filtrů, jejich frekvenční odezva a vliv na signál.",
    );
}
