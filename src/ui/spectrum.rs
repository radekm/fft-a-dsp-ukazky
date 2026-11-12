//! Záložka „Signály a spektrum“ (fáze 1).

/// Nakreslí obsah záložky.
pub fn show(ui: &mut egui::Ui) {
    super::placeholder(
        ui,
        "Signály a spektrum",
        "Skládání signálů a pohled na jejich časový průběh a spektrum (FFT).",
    );
}
