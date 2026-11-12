//! Záložka „Vzorkování a aliasing“ (fáze 3).

/// Nakreslí obsah záložky.
pub fn show(ui: &mut egui::Ui) {
    super::placeholder(
        ui,
        "Vzorkování a aliasing",
        "Vzorkovací frekvence, Nyquistova mez a vznik aliasů.",
    );
}
