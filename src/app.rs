//! Stav celé aplikace a přepínání mezi záložkami.

use crate::ui::Tab;

/// Stav aplikace. Zatím si pamatuje jen vybranou záložku;
/// stav jednotlivých ukázek přibude v dalších fázích.
#[derive(Default)]
pub struct App {
    selected_tab: Tab,
}

impl eframe::App for App {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        // Horní lišta se záložkami.
        egui::Panel::top("tabs").show(ui, |ui| {
            ui.horizontal(|ui| {
                for tab in Tab::ALL {
                    ui.selectable_value(&mut self.selected_tab, tab, tab.title());
                }
            });
        });

        // Zbytek okna patří vybrané záložce.
        egui::CentralPanel::default().show(ui, |ui| {
            self.selected_tab.show(ui);
        });
    }
}
