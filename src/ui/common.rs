//! Věci společné pro více záložek.

/// Šířka levého panelu s ovládáním.
pub const CONTROLS_WIDTH: f32 = 300.0;

/// Stejná šířka svislé osy u všech grafů, aby byly grafy pod sebou zarovnané.
pub const Y_AXIS_WIDTH: f32 = 48.0;

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
