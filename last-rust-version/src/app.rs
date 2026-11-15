//! Stav celé aplikace a přepínání mezi záložkami.

use tracing::info;

use crate::ui::filters::FiltersTab;
use crate::ui::sampling::SamplingTab;
use crate::ui::spectrum::SpectrumTab;
use crate::ui::windows::WindowsTab;
use crate::ui::{self, Tab};

/// Stav aplikace: vybraná záložka a stav jednotlivých ukázek.
#[derive(Default)]
pub struct App {
    selected_tab: Tab,
    spectrum: SpectrumTab,
    windows: WindowsTab,
    sampling: SamplingTab,
    filters: FiltersTab,
}

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let previous_tab = self.selected_tab;

        // Horní lišta se záložkami.
        egui::Panel::top("tabs").show(ui, |ui| {
            ui.horizontal(|ui| {
                for tab in ui::ALL_TABS {
                    ui.selectable_value(&mut self.selected_tab, tab, ui::tab_title(tab));
                }
            });
        });
        if self.selected_tab != previous_tab {
            info!(tab = ?self.selected_tab, "tab selected");
        }

        // Zbytek okna patří vybrané záložce.
        egui::CentralPanel::default().show(ui, |ui| match self.selected_tab {
            Tab::Spectrum => ui::spectrum::show(ui, &mut self.spectrum),
            Tab::Windows => ui::windows::show(ui, &mut self.windows),
            Tab::Sampling => ui::sampling::show(ui, &mut self.sampling),
            Tab::Filters => ui::filters::show(ui, &mut self.filters),
        });
    }
}
