//! Uživatelské rozhraní: jedna záložka = jeden soubor.

pub mod common;
pub mod filters;
pub mod sampling;
pub mod spectrum;
pub mod windows;

/// Záložky aplikace v pořadí, v jakém se zobrazují.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Tab {
    #[default]
    Spectrum,
    Windows,
    Sampling,
    Filters,
}

/// Všechny záložky – podle tohoto pole se kreslí horní lišta.
pub const ALL_TABS: [Tab; 4] = [Tab::Spectrum, Tab::Windows, Tab::Sampling, Tab::Filters];

/// Český popisek záložky.
pub fn tab_title(tab: Tab) -> &'static str {
    match tab {
        Tab::Spectrum => "Signály a spektrum",
        Tab::Windows => "Okna a prosakování",
        Tab::Sampling => "Vzorkování a aliasing",
        Tab::Filters => "Filtry",
    }
}

/// Dočasný obsah záložky, dokud není její ukázka hotová.
fn placeholder(ui: &mut egui::Ui, heading: &str, description: &str) {
    ui.heading(heading);
    ui.label(description);
    ui.add_space(8.0);
    ui.weak("Tato ukázka zatím není hotová.");
}
