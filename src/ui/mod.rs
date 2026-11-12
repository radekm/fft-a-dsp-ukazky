//! Uživatelské rozhraní: jedna záložka = jeden soubor.

mod filters;
mod sampling;
mod spectrum;
mod windows;

/// Záložky aplikace v pořadí, v jakém se zobrazují.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Tab {
    #[default]
    Spectrum,
    Windows,
    Sampling,
    Filters,
}

impl Tab {
    /// Všechny záložky – podle tohoto pole se kreslí horní lišta.
    pub const ALL: [Tab; 4] = [Tab::Spectrum, Tab::Windows, Tab::Sampling, Tab::Filters];

    /// Český popisek záložky.
    pub fn title(self) -> &'static str {
        match self {
            Tab::Spectrum => "Signály a spektrum",
            Tab::Windows => "Okna a prosakování",
            Tab::Sampling => "Vzorkování a aliasing",
            Tab::Filters => "Filtry",
        }
    }

    /// Nakreslí obsah záložky.
    pub fn show(self, ui: &mut egui::Ui) {
        match self {
            Tab::Spectrum => spectrum::show(ui),
            Tab::Windows => windows::show(ui),
            Tab::Sampling => sampling::show(ui),
            Tab::Filters => filters::show(ui),
        }
    }
}

/// Dočasný obsah záložky, dokud není její ukázka hotová.
fn placeholder(ui: &mut egui::Ui, heading: &str, description: &str) {
    ui.heading(heading);
    ui.label(description);
    ui.add_space(8.0);
    ui.weak("Tato ukázka zatím není hotová.");
}
