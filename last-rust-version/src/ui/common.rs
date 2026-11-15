//! Věci společné pro více záložek.

use crate::dsp::signal::{Component, Waveform};
use crate::dsp::window::WindowKind;

/// Největší amplituda, kterou lze nastavit u složky signálu.
const MAX_COMPONENT_AMPLITUDE: f64 = 2.0;

/// Šířka levého panelu s ovládáním.
pub const CONTROLS_WIDTH: f32 = 300.0;

/// Stejná šířka svislé osy u všech grafů, aby byly grafy pod sebou zarovnané.
pub const Y_AXIS_WIDTH: f32 = 48.0;

/// Popisek u kurzoru myši v grafu: název nejbližší křivky a souřadnice.
///
/// egui_plot bez vlastního popisku ukáže jen zaměřovací kříž. Tento popisek
/// vypíše čísla s osami pojmenovanými stejně jako v grafu. Když je kurzor
/// blízko bodu některé křivky, ukáže přesné souřadnice toho bodu, jinak
/// souřadnice samotného kurzoru.
pub fn hover_label(
    x_name: &'static str,
    y_name: &'static str,
) -> impl Fn(&egui_plot::HoverPosition<'_>) -> Option<String> {
    move |position| {
        let text = match position {
            egui_plot::HoverPosition::NearDataPoint {
                plot_name,
                position,
                ..
            } => format!(
                "{plot_name}\n{x_name}: {}\n{y_name}: {}",
                format_coordinate(position.x),
                format_coordinate(position.y)
            ),
            egui_plot::HoverPosition::Elsewhere { position } => format!(
                "{x_name}: {}\n{y_name}: {}",
                format_coordinate(position.x),
                format_coordinate(position.y)
            ),
        };
        Some(text)
    }
}

/// Číslo na nejvýš 4 desetinná místa bez zbytečných nul na konci
/// (25.0000 → „25“, 0.70711 → „0.7071“).
fn format_coordinate(value: f64) -> String {
    let text = format!("{value:.4}");
    let text = text.trim_end_matches('0').trim_end_matches('.');
    // Malé záporné číslo by se zaokrouhlilo na „-0“.
    if text == "-0" {
        "0".to_owned()
    } else {
        text.to_owned()
    }
}

/// Svislá osa amplitudového spektra.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AmplitudeScale {
    Linear,
    Decibel,
}

/// Výška jednoho grafu, když se do zbylého místa mají vejít `plot_count` grafy
/// pod sebou, každý s jedním řádkem nadpisu.
pub fn plot_height(ui: &egui::Ui, plot_count: usize) -> f32 {
    let label_height = ui.text_style_height(&egui::TextStyle::Body) + ui.spacing().item_spacing.y;
    (ui.available_height() / plot_count as f32 - label_height - 4.0).max(80.0)
}

/// Ovládání jedné složky signálu. Vrací `true`, pokud uživatel klikl na „Odebrat“.
///
/// `frequency_step` je krok posuvníku frekvence; 0 znamená plynulý posuvník.
pub fn component_controls(
    ui: &mut egui::Ui,
    index: usize,
    component: &mut Component,
    max_frequency_hz: f64,
    frequency_step: f64,
) -> bool {
    let mut remove_clicked = false;
    ui.push_id(index, |ui| {
        ui.group(|ui| {
            ui.horizontal(|ui| {
                ui.checkbox(&mut component.enabled, format!("Složka {}", index + 1));
                egui::ComboBox::from_id_salt("waveform")
                    .selected_text(waveform_name(component.waveform))
                    .show_ui(ui, |ui| {
                        for waveform in ALL_WAVEFORMS {
                            ui.selectable_value(
                                &mut component.waveform,
                                waveform,
                                waveform_name(waveform),
                            );
                        }
                    });
                remove_clicked = ui.small_button("Odebrat").clicked();
            });
            ui.add(
                egui::Slider::new(&mut component.frequency_hz, 0.0..=max_frequency_hz)
                    .step_by(frequency_step)
                    .suffix(" Hz")
                    .text("frekvence"),
            );
            ui.add(
                egui::Slider::new(&mut component.amplitude, 0.0..=MAX_COMPONENT_AMPLITUDE)
                    .text("amplituda"),
            );
            ui.add(
                egui::Slider::new(&mut component.phase_deg, -180.0..=180.0)
                    .suffix("°")
                    .text("fáze"),
            );
        });
    });
    remove_clicked
}

const ALL_WAVEFORMS: [Waveform; 4] = [
    Waveform::Sine,
    Waveform::Square,
    Waveform::Sawtooth,
    Waveform::Triangle,
];

/// Český název tvaru signálu.
pub fn waveform_name(waveform: Waveform) -> &'static str {
    match waveform {
        Waveform::Sine => "sinus",
        Waveform::Square => "obdélník",
        Waveform::Sawtooth => "pila",
        Waveform::Triangle => "trojúhelník",
    }
}

/// Frekvence jako text; malé hodnoty s více desetinnými místy.
pub fn format_hz(frequency_hz: f64) -> String {
    if frequency_hz < 10.0 {
        format!("{frequency_hz:.3} Hz")
    } else {
        format!("{frequency_hz:.1} Hz")
    }
}

/// Český název okna.
pub fn window_name(kind: WindowKind) -> &'static str {
    match kind {
        WindowKind::Rectangular => "obdélníkové (žádné)",
        WindowKind::Hann => "Hann",
        WindowKind::Hamming => "Hamming",
        WindowKind::Blackman => "Blackman",
    }
}
