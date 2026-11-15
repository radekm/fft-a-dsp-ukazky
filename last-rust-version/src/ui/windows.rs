//! Záložka „Okna a prosakování“: vlevo ovládání, vpravo signál s oknem,
//! jeho spektrum a spektrum samotného okna.
//!
//! Všechny frekvence jsou zde v binech (1 bin = fs/N). Celé číslo znamená,
//! že signál má v záznamu celý počet period a k prosakování nedojde.
//!
//! Vysvětlení a návod, co zkoušet: `docs/02-okna-a-prosakovani.md`.

use egui::Color32;
use egui_plot::{Legend, Line, LineStyle, Plot, PlotPoints, Points, VLine};
use tracing::debug;

use crate::dsp::fft::{fft, real_to_complex};
use crate::dsp::signal::{Component, SignalSpec, Waveform, generate};
use crate::dsp::spectrum::{SpectrumLine, one_sided_spectrum};
use crate::dsp::window::{
    ALL_WINDOWS, WindowKind, WindowProperties, WindowResponse, analyze_window, apply_window,
    window, window_response, zero_pad,
};
use crate::ui::common::{
    AmplitudeScale, CONTROLS_WIDTH, Y_AXIS_WIDTH, hover_label, plot_height, window_name,
};

/// Nabízené délky signálu jako mocnina dvou (16 až 1024 vzorků).
const MIN_LENGTH_EXPONENT: u32 = 4;
const MAX_LENGTH_EXPONENT: u32 = 10;

/// Nabízené násobky délky při doplnění nulami.
const ZERO_PADDING_FACTORS: [usize; 5] = [1, 2, 4, 8, 16];

/// Spektrum okna počítáme z okna doplněného nulami alespoň na tuto délku,
/// aby byl dobře vidět tvar laloků i u krátkých oken.
const WINDOW_RESPONSE_MIN_SIZE: usize = 16_384;
const WINDOW_RESPONSE_OVERSAMPLING: usize = 16;

/// Kolik binů na každou stranu je vidět v grafu spektra okna po obnovení zobrazení.
const WINDOW_PLOT_RANGE_BINS: f64 = 10.0;

/// Spodní okraj grafů v decibelech; menší hodnoty se oříznou.
const DB_FLOOR: f64 = -160.0;

/// Do tohoto počtu bodů spektra se každý bod vyznačí puntíkem.
const MAX_MARKED_POINTS: usize = 1025;

const MAX_WEAK_LEVEL_DB: f64 = 0.0;
const MIN_WEAK_LEVEL_DB: f64 = -120.0;

const SIGNAL_COLOR: Color32 = Color32::from_rgb(150, 150, 150);
const WINDOW_COLOR: Color32 = Color32::from_rgb(230, 180, 60);
const WINDOWED_COLOR: Color32 = Color32::from_rgb(90, 170, 255);
const RECTANGULAR_COLOR: Color32 = Color32::from_rgb(150, 150, 150);
const MARKER_COLOR: Color32 = Color32::from_rgb(120, 200, 120);

/// Všechno, od čeho závisí výsledek výpočtu.
#[derive(Clone, Debug, PartialEq)]
struct Settings {
    length_exponent: u32,
    window: WindowKind,
    zero_padding_factor: usize,
    /// Frekvence hlavní sinusovky (amplituda 1) v binech.
    main_frequency_bins: f64,
    /// Slabá sinusovka ukazuje, jak prosakování silné čáry zakryje slabý signál.
    weak_enabled: bool,
    weak_frequency_bins: f64,
    weak_level_db: f64,
}

/// Výsledek výpočtu pro jedno nastavení.
struct Computed {
    settings: Settings,
    /// Původní signál délky N.
    samples: Vec<f64>,
    window: Vec<f64>,
    /// Signál vynásobený oknem a doplněný nulami.
    windowed_padded: Vec<f64>,
    lines: Vec<SpectrumLine>,
    /// Spektrum téhož signálu bez okna, pro porovnání.
    rectangular_lines: Vec<SpectrumLine>,
    response: WindowResponse,
    rectangular_response: WindowResponse,
    properties: WindowProperties,
    /// Nejvyšší čára spektra v dB; skutečná úroveň hlavní sinusovky je 0 dB.
    peak_db: f64,
}

/// Stav záložky.
pub struct WindowsTab {
    settings: Settings,
    amplitude_scale: AmplitudeScale,
    compare_with_rectangular: bool,
    computed: Option<Computed>,
}

impl Default for WindowsTab {
    /// Výchozí stav: hlavní sinusovka přesně v binu, takže ani bez okna
    /// neprosakuje. Tlačítkem „Mezi biny“ lze prosakování hned vyvolat.
    fn default() -> Self {
        WindowsTab {
            settings: Settings {
                length_exponent: 6,
                window: WindowKind::Hann,
                zero_padding_factor: 1,
                main_frequency_bins: 10.0,
                weak_enabled: true,
                weak_frequency_bins: 20.0,
                weak_level_db: -60.0,
            },
            amplitude_scale: AmplitudeScale::Decibel,
            compare_with_rectangular: true,
            computed: None,
        }
    }
}

/// Nakreslí obsah záložky.
pub fn show(ui: &mut egui::Ui, tab: &mut WindowsTab) {
    egui::Panel::left("windows_controls")
        .exact_size(CONTROLS_WIDTH)
        .show(ui, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| show_controls(ui, tab));
        });

    update_computed(tab);

    egui::CentralPanel::default().show(ui, |ui| {
        if let Some(computed) = &tab.computed {
            show_plots(
                ui,
                computed,
                tab.amplitude_scale,
                tab.compare_with_rectangular,
            );
        }
    });
}

/// Přepočítá vše, pokud se od posledního výpočtu změnilo nastavení.
fn update_computed(tab: &mut WindowsTab) {
    let is_current = tab
        .computed
        .as_ref()
        .is_some_and(|computed| computed.settings == tab.settings);
    if !is_current {
        tab.computed = Some(compute(&tab.settings));
    }
}

fn compute(settings: &Settings) -> Computed {
    let length = 1usize << settings.length_exponent;
    // Vzorkovací frekvenci volíme rovnou délce signálu. Pak 1 Hz odpovídá
    // přesně jednomu binu a frekvence lze zadávat přímo v binech.
    let sample_rate_hz = length as f64;
    let fft_size = length * settings.zero_padding_factor;

    let samples = generate(&signal_spec(settings), sample_rate_hz, length);
    let coefficients = window(settings.window, length);
    let rectangular = window(WindowKind::Rectangular, length);

    let lines = windowed_spectrum(&samples, &coefficients, fft_size, sample_rate_hz);
    let rectangular_lines = windowed_spectrum(&samples, &rectangular, fft_size, sample_rate_hz);

    let response_size = (length * WINDOW_RESPONSE_OVERSAMPLING).max(WINDOW_RESPONSE_MIN_SIZE);
    let response = window_response(&coefficients, response_size);
    let rectangular_response = window_response(&rectangular, response_size);
    let properties = analyze_window(&coefficients, &response);

    let peak_db = lines
        .iter()
        .map(|line| line.amplitude_db)
        .fold(f64::NEG_INFINITY, f64::max);

    debug!(
        window = ?settings.window,
        length,
        fft_size,
        main_frequency_bins = settings.main_frequency_bins,
        peak_db,
        "windowed spectrum computed"
    );

    Computed {
        settings: settings.clone(),
        windowed_padded: zero_pad(&apply_window(&samples, &coefficients), fft_size),
        samples,
        window: coefficients,
        lines,
        rectangular_lines,
        response,
        rectangular_response,
        properties,
        peak_db,
    }
}

/// Signál: hlavní sinusovka s amplitudou 1 a volitelně slabá sinusovka.
fn signal_spec(settings: &Settings) -> SignalSpec {
    let mut components = vec![sine(settings.main_frequency_bins, 1.0)];
    if settings.weak_enabled {
        components.push(sine(
            settings.weak_frequency_bins,
            db_to_amplitude(settings.weak_level_db),
        ));
    }
    SignalSpec {
        components,
        dc_offset: 0.0,
        noise_amplitude: 0.0,
        noise_seed: 1,
    }
}

fn sine(frequency_hz: f64, amplitude: f64) -> Component {
    Component {
        enabled: true,
        waveform: Waveform::Sine,
        frequency_hz,
        amplitude,
        phase_deg: 0.0,
    }
}

/// Decibely na amplitudu: 0 dB = 1, −20 dB = 0,1, −40 dB = 0,01 …
fn db_to_amplitude(level_db: f64) -> f64 {
    10f64.powf(level_db / 20.0)
}

/// Signál vynásobí oknem, doplní nulami a spočítá jednostranné spektrum.
fn windowed_spectrum(
    samples: &[f64],
    coefficients: &[f64],
    fft_size: usize,
    sample_rate_hz: f64,
) -> Vec<SpectrumLine> {
    let windowed = zero_pad(&apply_window(samples, coefficients), fft_size);
    let output = fft(&real_to_complex(&windowed));
    let window_sum: f64 = coefficients.iter().sum();
    one_sided_spectrum(&output, sample_rate_hz, window_sum)
}

// ---------------------------------------------------------------------------
// Ovládací panel
// ---------------------------------------------------------------------------

fn show_controls(ui: &mut egui::Ui, tab: &mut WindowsTab) {
    show_length_controls(ui, &mut tab.settings);
    ui.separator();
    show_signal_controls(ui, &mut tab.settings);
    ui.separator();
    show_window_controls(ui, tab);
    ui.separator();
    show_view_controls(ui, tab);
}

fn show_length_controls(ui: &mut egui::Ui, settings: &mut Settings) {
    ui.heading("Záznam");
    egui::ComboBox::from_label("délka signálu (N)")
        .selected_text(format!("{}", 1usize << settings.length_exponent))
        .show_ui(ui, |ui| {
            for exponent in MIN_LENGTH_EXPONENT..=MAX_LENGTH_EXPONENT {
                let label = format!("{}", 1usize << exponent);
                ui.selectable_value(&mut settings.length_exponent, exponent, label);
            }
        });

    egui::ComboBox::from_label("doplnění nulami")
        .selected_text(format!("×{}", settings.zero_padding_factor))
        .show_ui(ui, |ui| {
            for factor in ZERO_PADDING_FACTORS {
                ui.selectable_value(
                    &mut settings.zero_padding_factor,
                    factor,
                    format!("×{factor}"),
                );
            }
        });
    ui.weak(
        "Doplnění nulami zhustí body spektra, ale nezlepší rozlišení: \
         tvar čar zůstane stejný, jen je lépe vidět.",
    );

    clamp_frequencies(settings);
}

/// Frekvence držíme v rozsahu 0 až N/2 binů (po Nyquistovu frekvenci).
fn clamp_frequencies(settings: &mut Settings) {
    let max_bins = max_frequency_bins(settings);
    settings.main_frequency_bins = settings.main_frequency_bins.min(max_bins);
    settings.weak_frequency_bins = settings.weak_frequency_bins.min(max_bins);
}

fn max_frequency_bins(settings: &Settings) -> f64 {
    ((1usize << settings.length_exponent) / 2) as f64
}

fn show_signal_controls(ui: &mut egui::Ui, settings: &mut Settings) {
    ui.heading("Signál");
    let max_bins = max_frequency_bins(settings);

    ui.label("Hlavní sinusovka (amplituda 1 = 0 dB)");
    ui.add(
        egui::Slider::new(&mut settings.main_frequency_bins, 0.0..=max_bins)
            .step_by(0.01)
            .fixed_decimals(2)
            .text("frekvence [biny]"),
    );
    ui.horizontal(|ui| {
        if ui.button("Přesně v binu").clicked() {
            settings.main_frequency_bins = settings.main_frequency_bins.round();
        }
        if ui.button("Mezi biny").clicked() {
            let between = settings.main_frequency_bins.floor() + 0.5;
            settings.main_frequency_bins = between.min(max_bins - 0.5);
        }
    });

    ui.add_space(6.0);
    ui.checkbox(&mut settings.weak_enabled, "Slabá sinusovka");
    ui.add_enabled_ui(settings.weak_enabled, |ui| {
        ui.add(
            egui::Slider::new(&mut settings.weak_frequency_bins, 0.0..=max_bins)
                .step_by(0.01)
                .fixed_decimals(2)
                .text("frekvence [biny]"),
        );
        ui.add(
            egui::Slider::new(
                &mut settings.weak_level_db,
                MIN_WEAK_LEVEL_DB..=MAX_WEAK_LEVEL_DB,
            )
            .suffix(" dB")
            .text("úroveň"),
        );
    });
    ui.weak(
        "Frekvence je v binech (1 bin = fs/N). Celé číslo znamená celý počet \
         period v záznamu – pak k prosakování nedojde.",
    );
}

fn show_window_controls(ui: &mut egui::Ui, tab: &mut WindowsTab) {
    ui.heading("Okno");
    ui.horizontal_wrapped(|ui| {
        for kind in ALL_WINDOWS {
            ui.radio_value(&mut tab.settings.window, kind, window_name(kind));
        }
    });

    if let Some(computed) = &tab.computed {
        let properties = &computed.properties;
        egui::Grid::new("window_properties")
            .num_columns(2)
            .show(ui, |ui| {
                ui.label("První nula hlavního laloku:");
                ui.label(format!("±{:.2} binu", properties.main_lobe_half_width_bins));
                ui.end_row();
                ui.label("Nejvyšší postranní lalok:");
                ui.label(format!("{:.1} dB", properties.highest_side_lobe_db));
                ui.end_row();
                ui.label("Koherentní zisk:");
                ui.label(format!("{:.2}", properties.coherent_gain));
                ui.end_row();
                ui.label("Nejvyšší čára spektra:");
                ui.label(format!("{:.2} dB", computed.peak_db));
                ui.end_row();
            });
        ui.weak(
            "Skutečná úroveň hlavní sinusovky je 0 dB. Rozdíl u frekvence mezi \
             biny je ztráta způsobená tím, že vrchol čáry padne mezi body spektra.",
        );
    }
}

fn show_view_controls(ui: &mut egui::Ui, tab: &mut WindowsTab) {
    ui.heading("Zobrazení");
    ui.horizontal(|ui| {
        ui.label("Amplituda:");
        ui.radio_value(&mut tab.amplitude_scale, AmplitudeScale::Linear, "lineárně");
        ui.radio_value(&mut tab.amplitude_scale, AmplitudeScale::Decibel, "v dB");
    });
    ui.checkbox(
        &mut tab.compare_with_rectangular,
        "Porovnat s obdélníkovým oknem",
    );
    ui.weak("Grafy: tažením posun, kolečkem s Ctrl zvětšení, dvojklik obnoví zobrazení.");
}

// ---------------------------------------------------------------------------
// Grafy
// ---------------------------------------------------------------------------

fn show_plots(
    ui: &mut egui::Ui,
    computed: &Computed,
    amplitude_scale: AmplitudeScale,
    compare_with_rectangular: bool,
) {
    // Porovnání má smysl, jen když vybrané okno není samo obdélníkové.
    let show_rectangular =
        compare_with_rectangular && computed.settings.window != WindowKind::Rectangular;
    let height = plot_height(ui, 3);

    ui.label("Signál, okno a signál vynásobený oknem (za koncem signálu doplněné nuly)");
    show_time_plot(ui, computed, height);

    ui.label("Spektrum signálu vynásobeného oknem");
    show_spectrum_plot(ui, computed, amplitude_scale, show_rectangular, height);

    ui.label("Spektrum samotného okna – tvar, do kterého se rozmaže každá čára");
    show_window_response_plot(ui, computed, show_rectangular, height);
}

fn show_time_plot(ui: &mut egui::Ui, computed: &Computed, height: f32) {
    Plot::new("window_time_plot")
        .height(height)
        .label_formatter(hover_label("vzorek n", "hodnota"))
        .y_axis_min_width(Y_AXIS_WIDTH)
        .x_axis_label("vzorek n")
        .legend(Legend::default())
        .show(ui, |plot_ui| {
            plot_ui
                .line(Line::new("signál", indexed_points(&computed.samples)).color(SIGNAL_COLOR));
            plot_ui.line(Line::new("okno", indexed_points(&computed.window)).color(WINDOW_COLOR));
            plot_ui.line(
                Line::new("signál × okno", indexed_points(&computed.windowed_padded))
                    .color(WINDOWED_COLOR)
                    .width(2.0),
            );
        });
}

/// Body grafu, kde vodorovná souřadnice je pořadové číslo vzorku.
fn indexed_points(values: &[f64]) -> PlotPoints<'static> {
    values
        .iter()
        .enumerate()
        .map(|(index, &value)| [index as f64, value])
        .collect()
}

fn show_spectrum_plot(
    ui: &mut egui::Ui,
    computed: &Computed,
    amplitude_scale: AmplitudeScale,
    show_rectangular: bool,
    height: f32,
) {
    let y_label = match amplitude_scale {
        AmplitudeScale::Linear => "amplituda",
        AmplitudeScale::Decibel => "amplituda [dB]",
    };
    let mark_points = computed.lines.len() <= MAX_MARKED_POINTS;
    let settings = &computed.settings;

    Plot::new("window_spectrum_plot")
        .height(height)
        .label_formatter(hover_label("frekvence [biny]", y_label))
        .y_axis_min_width(Y_AXIS_WIDTH)
        .x_axis_label("frekvence [biny]")
        .y_axis_label(y_label)
        .legend(Legend::default())
        .show(ui, |plot_ui| {
            if show_rectangular {
                let points = spectrum_points(&computed.rectangular_lines, amplitude_scale);
                plot_ui.line(Line::new("bez okna", points).color(RECTANGULAR_COLOR));
            }

            let name = window_name(settings.window);
            let points = spectrum_points(&computed.lines, amplitude_scale);
            if mark_points {
                plot_ui.points(
                    Points::new(name, spectrum_points(&computed.lines, amplitude_scale))
                        .color(WINDOWED_COLOR)
                        .radius(2.0),
                );
            }
            plot_ui.line(Line::new(name, points).color(WINDOWED_COLOR).width(2.0));

            // Svislé čárkované čáry ukazují skutečné frekvence sinusovek.
            plot_ui.vline(frequency_marker(settings.main_frequency_bins));
            if settings.weak_enabled {
                plot_ui.vline(frequency_marker(settings.weak_frequency_bins));
            }
        });
}

fn spectrum_points(lines: &[SpectrumLine], amplitude_scale: AmplitudeScale) -> PlotPoints<'static> {
    lines
        .iter()
        .map(|line| {
            let y = match amplitude_scale {
                AmplitudeScale::Linear => line.amplitude,
                AmplitudeScale::Decibel => line.amplitude_db.max(DB_FLOOR),
            };
            // Vzorkovací frekvence je rovna délce signálu, takže Hz = biny.
            [line.frequency_hz, y]
        })
        .collect()
}

fn frequency_marker(frequency_bins: f64) -> VLine {
    VLine::new("skutečná frekvence", frequency_bins)
        .color(MARKER_COLOR)
        .style(LineStyle::dashed_loose())
}

fn show_window_response_plot(
    ui: &mut egui::Ui,
    computed: &Computed,
    show_rectangular: bool,
    height: f32,
) {
    Plot::new("window_response_plot")
        .height(height)
        .label_formatter(hover_label("vzdálenost [biny]", "útlum [dB]"))
        .y_axis_min_width(Y_AXIS_WIDTH)
        .x_axis_label("vzdálenost od frekvence sinusovky [biny]")
        .y_axis_label("útlum [dB]")
        .default_x_bounds(-WINDOW_PLOT_RANGE_BINS, WINDOW_PLOT_RANGE_BINS)
        .default_y_bounds(-120.0, 5.0)
        .legend(Legend::default())
        .show(ui, |plot_ui| {
            if show_rectangular {
                plot_ui.line(
                    Line::new("bez okna", mirrored_points(&computed.rectangular_response))
                        .color(RECTANGULAR_COLOR),
                );
            }
            plot_ui.line(
                Line::new(
                    window_name(computed.settings.window),
                    mirrored_points(&computed.response),
                )
                .color(WINDOWED_COLOR)
                .width(2.0),
            );
        });
}

/// Spektrum okna je souměrné kolem nuly; máme jen kladnou polovinu, zápornou
/// doplníme zrcadlením.
fn mirrored_points(response: &WindowResponse) -> PlotPoints<'static> {
    let positive = response
        .offsets_bins
        .iter()
        .zip(&response.magnitude_db)
        .map(|(&offset, &db)| [offset, db.max(DB_FLOOR)]);
    let negative = positive
        .clone()
        .skip(1)
        .rev()
        .map(|[offset, db]| [-offset, db]);
    negative.chain(positive).collect()
}
