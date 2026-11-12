//! Záložka „Filtry“: návrh FIR a IIR filtru, jeho impulzní odezva
//! a frekvenční charakteristika a signál i spektrum před a po filtraci.

use egui::Color32;
use egui_plot::{AxisHints, Legend, Line, LineStyle, Plot, PlotPoints, Points, VLine};
use tracing::debug;

use crate::dsp::fft::{fft, real_to_complex};
use crate::dsp::filter::{
    Biquad, FilterType, FirDesign, ResponsePoint, biquad_filter, biquad_impulse_response, convolve,
    design_biquad, design_fir, frequency_response,
};
use crate::dsp::signal::{Component, SignalSpec, Waveform, generate};
use crate::dsp::spectrum::{SpectrumLine, one_sided_spectrum};
use crate::dsp::window::{ALL_WINDOWS, WindowKind, apply_window, window};
use crate::ui::common::{
    CONTROLS_WIDTH, Y_AXIS_WIDTH, component_controls, plot_height, window_name,
};

/// Vzorkovací frekvence je v této záložce pevná; frekvence jdou do 500 Hz.
const SAMPLE_RATE_HZ: f64 = 1000.0;
/// Délka testovacího signálu (mocnina dvou kvůli FFT), zhruba 1 s.
const SIGNAL_LENGTH: usize = 1024;
/// Počet bodů frekvenční charakteristiky od 0 do fs/2.
const RESPONSE_POINTS: usize = 1025;
/// Kolik vzorků nekonečné impulzní odezvy IIR filtru zobrazit.
const IIR_IMPULSE_LENGTH: usize = 200;

const MIN_FREQUENCY_HZ: f64 = 1.0;
/// Mezní frekvence nesmí sahat až na fs/2.
const MAX_FREQUENCY_HZ: f64 = SAMPLE_RATE_HZ / 2.0 - 1.0;
/// Nejmenší rozdíl mezí pásmové propusti FIR.
const MIN_BAND_WIDTH_HZ: f64 = 1.0;
const MAX_FIR_HALF_LENGTH: usize = 200;
const MIN_Q: f64 = 0.1;
const MAX_Q: f64 = 20.0;
const MAX_COMPONENTS: usize = 4;
const MAX_NOISE: f64 = 1.0;

/// Spodní okraj grafů v decibelech; menší hodnoty se oříznou.
const DB_FLOOR: f64 = -120.0;

const INPUT_COLOR: Color32 = Color32::from_rgb(150, 150, 150);
const OUTPUT_COLOR: Color32 = Color32::from_rgb(90, 170, 255);
const RESPONSE_COLOR: Color32 = Color32::from_rgb(230, 180, 60);
const MARKER_COLOR: Color32 = Color32::from_rgb(120, 200, 120);

/// Rodina filtru.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum FilterFamily {
    Fir,
    Iir,
}

/// Co ukazuje graf frekvenční charakteristiky.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ResponseView {
    Magnitude,
    Phase,
}

/// Všechno, od čeho závisí výsledek výpočtu.
#[derive(Clone, Debug, PartialEq)]
struct Settings {
    signal: SignalSpec,
    family: FilterFamily,
    filter_type: FilterType,
    /// Mezní frekvence; u pásmové propusti FIR dolní mez, u IIR střed pásma.
    frequency_hz: f64,
    /// Horní mez pásmové propusti FIR.
    upper_frequency_hz: f64,
    /// Počet koeficientů FIR je 2·k + 1 (vždy lichý); toto je k.
    fir_half_length: usize,
    fir_window: WindowKind,
    q: f64,
}

/// Výsledek výpočtu pro jedno nastavení.
struct Computed {
    settings: Settings,
    /// U FIR jsou to přímo koeficienty filtru.
    impulse_response: Vec<f64>,
    response: Vec<ResponsePoint>,
    /// Koeficienty IIR filtru (u FIR nejsou).
    biquad: Option<Biquad>,
    input: Vec<f64>,
    output: Vec<f64>,
    input_spectrum: Vec<SpectrumLine>,
    output_spectrum: Vec<SpectrumLine>,
}

/// Stav záložky.
pub struct FiltersTab {
    settings: Settings,
    response_view: ResponseView,
    computed: Option<Computed>,
}

impl Default for FiltersTab {
    /// Výchozí stav: pomalá sinusovka, rychlejší sinusovka a šum; dolní
    /// propust 100 Hz nechá projít jen tu pomalou.
    fn default() -> Self {
        FiltersTab {
            settings: Settings {
                signal: SignalSpec {
                    components: vec![sine(20.0, 1.0), sine(200.0, 0.5)],
                    dc_offset: 0.0,
                    noise_amplitude: 0.2,
                    noise_seed: 1,
                },
                family: FilterFamily::Fir,
                filter_type: FilterType::LowPass,
                frequency_hz: 100.0,
                upper_frequency_hz: 250.0,
                fir_half_length: 30,
                fir_window: WindowKind::Hamming,
                q: 1.0 / 2f64.sqrt(),
            },
            response_view: ResponseView::Magnitude,
            computed: None,
        }
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

/// Nakreslí obsah záložky.
pub fn show(ui: &mut egui::Ui, tab: &mut FiltersTab) {
    egui::Panel::left("filters_controls")
        .exact_size(CONTROLS_WIDTH)
        .show(ui, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| show_controls(ui, tab));
        });

    update_computed(tab);

    egui::CentralPanel::default().show(ui, |ui| {
        if let Some(computed) = &tab.computed {
            show_plots(ui, computed, tab.response_view);
        }
    });
}

/// Přepočítá vše, pokud se od posledního výpočtu změnilo nastavení.
fn update_computed(tab: &mut FiltersTab) {
    let is_current = tab
        .computed
        .as_ref()
        .is_some_and(|computed| computed.settings == tab.settings);
    if !is_current {
        tab.computed = Some(compute(&tab.settings));
    }
}

fn compute(settings: &Settings) -> Computed {
    let input = generate(&settings.signal, SAMPLE_RATE_HZ, SIGNAL_LENGTH);

    let (impulse_response, response, biquad, output) = match settings.family {
        FilterFamily::Fir => {
            let coefficients = design_fir(&fir_design(settings), SAMPLE_RATE_HZ);
            // FIR filtr nemá zpětnou vazbu: jmenovatel je jen a0 = 1.
            let response =
                frequency_response(&coefficients, &[1.0], SAMPLE_RATE_HZ, RESPONSE_POINTS);
            let output = convolve(&input, &coefficients);
            (coefficients, response, None, output)
        }
        FilterFamily::Iir => {
            let biquad = design_biquad(
                settings.filter_type,
                settings.frequency_hz,
                settings.q,
                SAMPLE_RATE_HZ,
            );
            let response =
                frequency_response(&biquad.b, &biquad.a, SAMPLE_RATE_HZ, RESPONSE_POINTS);
            let impulse = biquad_impulse_response(&biquad, IIR_IMPULSE_LENGTH);
            let output = biquad_filter(&biquad, &input);
            (impulse, response, Some(biquad), output)
        }
    };

    debug!(
        family = ?settings.family,
        filter_type = ?settings.filter_type,
        frequency_hz = settings.frequency_hz,
        impulse_length = impulse_response.len(),
        "filter computed"
    );

    Computed {
        settings: settings.clone(),
        input_spectrum: analyze(&input),
        output_spectrum: analyze(&output),
        impulse_response,
        response,
        biquad,
        input,
        output,
    }
}

fn fir_design(settings: &Settings) -> FirDesign {
    FirDesign {
        filter_type: settings.filter_type,
        cutoff_hz: settings.frequency_hz,
        upper_cutoff_hz: settings.upper_frequency_hz,
        length: fir_length(settings),
        window: settings.fir_window,
    }
}

fn fir_length(settings: &Settings) -> usize {
    2 * settings.fir_half_length + 1
}

/// Spektrum signálu. Frekvence složek nejsou obecně v celých binech, proto
/// signál nejdřív vynásobíme oknem Hann, aby prosakování nezakrylo, co filtr
/// udělal.
fn analyze(signal: &[f64]) -> Vec<SpectrumLine> {
    let coefficients = window(WindowKind::Hann, signal.len());
    let window_sum: f64 = coefficients.iter().sum();
    let windowed = apply_window(signal, &coefficients);
    one_sided_spectrum(
        &fft(&real_to_complex(&windowed)),
        SAMPLE_RATE_HZ,
        window_sum,
    )
}

// ---------------------------------------------------------------------------
// Ovládací panel
// ---------------------------------------------------------------------------

fn show_controls(ui: &mut egui::Ui, tab: &mut FiltersTab) {
    show_filter_controls(ui, tab);
    ui.separator();
    show_signal_controls(ui, &mut tab.settings);
    ui.separator();
    show_view_controls(ui, tab);
}

fn show_filter_controls(ui: &mut egui::Ui, tab: &mut FiltersTab) {
    let settings = &mut tab.settings;
    ui.heading("Filtr");
    ui.label(format!("Vzorkovací frekvence fs = {SAMPLE_RATE_HZ} Hz"));
    ui.horizontal(|ui| {
        ui.radio_value(&mut settings.family, FilterFamily::Fir, "FIR");
        ui.radio_value(&mut settings.family, FilterFamily::Iir, "IIR (biquad)");
    });
    ui.horizontal_wrapped(|ui| {
        for filter_type in [
            FilterType::LowPass,
            FilterType::HighPass,
            FilterType::BandPass,
        ] {
            ui.radio_value(
                &mut settings.filter_type,
                filter_type,
                filter_type_name(filter_type),
            );
        }
    });

    ui.add_space(4.0);
    show_frequency_controls(ui, settings);

    ui.add_space(4.0);
    match settings.family {
        FilterFamily::Fir => show_fir_controls(ui, settings),
        FilterFamily::Iir => show_iir_controls(ui, settings, tab.computed.as_ref()),
    }
}

fn filter_type_name(filter_type: FilterType) -> &'static str {
    match filter_type {
        FilterType::LowPass => "dolní propust",
        FilterType::HighPass => "horní propust",
        FilterType::BandPass => "pásmová propust",
    }
}

/// Posuvníky frekvencí; jejich význam záleží na druhu filtru.
fn show_frequency_controls(ui: &mut egui::Ui, settings: &mut Settings) {
    let is_fir_band =
        settings.family == FilterFamily::Fir && settings.filter_type == FilterType::BandPass;
    let first_label = match (settings.family, settings.filter_type) {
        (FilterFamily::Fir, FilterType::BandPass) => "dolní mez",
        (FilterFamily::Iir, FilterType::BandPass) => "střed pásma",
        _ => "mezní frekvence",
    };
    frequency_slider(ui, &mut settings.frequency_hz, first_label);

    if is_fir_band {
        frequency_slider(ui, &mut settings.upper_frequency_hz, "horní mez");
        // Horní mez musí ležet nad dolní.
        let lowest_upper = settings.frequency_hz + MIN_BAND_WIDTH_HZ;
        settings.upper_frequency_hz = settings
            .upper_frequency_hz
            .clamp(lowest_upper, MAX_FREQUENCY_HZ);
        settings.frequency_hz = settings
            .frequency_hz
            .min(settings.upper_frequency_hz - MIN_BAND_WIDTH_HZ);
    }
}

fn frequency_slider(ui: &mut egui::Ui, value: &mut f64, label: &str) {
    ui.add(
        egui::Slider::new(value, MIN_FREQUENCY_HZ..=MAX_FREQUENCY_HZ)
            .logarithmic(true)
            .fixed_decimals(0)
            .suffix(" Hz")
            .text(label),
    );
}

fn show_fir_controls(ui: &mut egui::Ui, settings: &mut Settings) {
    ui.add(egui::Slider::new(&mut settings.fir_half_length, 1..=MAX_FIR_HALF_LENGTH).text("k"));
    let length = fir_length(settings);
    let delay_samples = settings.fir_half_length;
    ui.label(format!("Počet koeficientů M = 2k + 1 = {length}"));
    ui.label(format!(
        "Zpoždění (M − 1)/2 = {delay_samples} vzorků = {:.0} ms",
        1000.0 * delay_samples as f64 / SAMPLE_RATE_HZ
    ));

    ui.label("Okno:");
    ui.horizontal_wrapped(|ui| {
        for kind in ALL_WINDOWS {
            ui.radio_value(&mut settings.fir_window, kind, window_name(kind));
        }
    });
    ui.weak(
        "Delší filtr má strmější přechod mezi propustným a nepropustným pásmem, \
         ale větší zpoždění. Okno určuje, jak hluboko filtr potlačí nepropustné \
         pásmo (stejně jako postranní laloky ve spektru).",
    );
}

fn show_iir_controls(ui: &mut egui::Ui, settings: &mut Settings, computed: Option<&Computed>) {
    ui.add(
        egui::Slider::new(&mut settings.q, MIN_Q..=MAX_Q)
            .logarithmic(true)
            .fixed_decimals(2)
            .text("Q (jakost)"),
    );
    if ui.button("Q = 0,707 (nejplošší)").clicked() {
        settings.q = 1.0 / 2f64.sqrt();
    }

    if let Some(biquad) = computed.and_then(|computed| computed.biquad.as_ref()) {
        ui.label("Koeficienty:");
        egui::Grid::new("biquad_coefficients")
            .num_columns(3)
            .show(ui, |ui| {
                for (index, (b, a)) in biquad.b.iter().zip(&biquad.a).enumerate() {
                    ui.label(format!("b{index} = {b:.5}"));
                    ui.label(format!("a{index} = {a:.5}"));
                    ui.end_row();
                }
            });
    }
    ui.weak(
        "y[n] = b0·x[n] + b1·x[n−1] + b2·x[n−2] − a1·y[n−1] − a2·y[n−2]. \
         Díky zpětné vazbě stačí pět čísel, ale fáze není lineární. Velké Q \
         dává převýšení u mezní frekvence a dlouho doznívající odezvu.",
    );
}

fn show_signal_controls(ui: &mut egui::Ui, settings: &mut Settings) {
    ui.heading("Vstupní signál");
    let signal = &mut settings.signal;

    // Složku nelze odebrat uprostřed procházení seznamu, proto si jen
    // zapamatujeme její index a odebereme ji až po cyklu.
    let mut index_to_remove = None;
    for (index, component) in signal.components.iter_mut().enumerate() {
        let remove_clicked = component_controls(ui, index, component, SAMPLE_RATE_HZ / 2.0, 0.0);
        if remove_clicked {
            index_to_remove = Some(index);
        }
    }
    if let Some(index) = index_to_remove {
        signal.components.remove(index);
    }

    let can_add = signal.components.len() < MAX_COMPONENTS;
    if ui
        .add_enabled(can_add, egui::Button::new("Přidat složku"))
        .clicked()
    {
        signal.components.push(sine(50.0, 0.5));
    }

    ui.add_space(6.0);
    ui.add(egui::Slider::new(&mut signal.noise_amplitude, 0.0..=MAX_NOISE).text("šum"));
    if ui.button("Nový šum").clicked() {
        signal.noise_seed += 1;
    }
}

fn show_view_controls(ui: &mut egui::Ui, tab: &mut FiltersTab) {
    ui.heading("Zobrazení");
    ui.horizontal(|ui| {
        ui.label("Charakteristika:");
        ui.radio_value(&mut tab.response_view, ResponseView::Magnitude, "zesílení");
        ui.radio_value(&mut tab.response_view, ResponseView::Phase, "fáze");
    });
    ui.weak("Grafy: tažením posun, kolečkem s Ctrl zvětšení, dvojklik obnoví zobrazení.");
}

// ---------------------------------------------------------------------------
// Grafy
// ---------------------------------------------------------------------------

fn show_plots(ui: &mut egui::Ui, computed: &Computed, response_view: ResponseView) {
    // Čtyři grafy ve dvou řádcích a dvou sloupcích.
    let height = plot_height(ui, 2);
    ui.columns(2, |columns| {
        columns[0].label(impulse_title(computed.settings.family));
        show_impulse_plot(&mut columns[0], computed, height);
        columns[0].label("Signál před a po filtraci");
        show_time_plot(&mut columns[0], computed, height);

        columns[1].label(match response_view {
            ResponseView::Magnitude => "Frekvenční charakteristika – zesílení",
            ResponseView::Phase => "Frekvenční charakteristika – fáze",
        });
        show_response_plot(&mut columns[1], computed, response_view, height);
        columns[1].label("Spektrum před a po filtraci (s oknem Hann)");
        show_spectrum_plot(&mut columns[1], computed, height);
    });
}

/// Vodorovná osa pro úzké grafy ve dvou sloupcích. Výchozí rozestup popisků
/// je na šířku sloupce moc velký, takže by se ukázala jen nula.
fn narrow_x_axis(label: &str) -> Vec<AxisHints<'static>> {
    vec![
        AxisHints::new_x()
            .label(label.to_owned())
            .label_spacing(30.0..=40.0),
    ]
}

fn impulse_title(family: FilterFamily) -> &'static str {
    match family {
        FilterFamily::Fir => "Impulzní odezva = koeficienty filtru",
        FilterFamily::Iir => "Impulzní odezva (prvních 200 vzorků)",
    }
}

fn show_impulse_plot(ui: &mut egui::Ui, computed: &Computed, height: f32) {
    let points: PlotPoints = computed
        .impulse_response
        .iter()
        .enumerate()
        .map(|(index, &value)| [index as f64, value])
        .collect();
    Plot::new("filter_impulse_plot")
        .height(height)
        .y_axis_min_width(Y_AXIS_WIDTH)
        .custom_x_axes(narrow_x_axis("vzorek n"))
        .show(ui, |plot_ui| {
            plot_ui.points(
                Points::new("h[n]", points)
                    .color(RESPONSE_COLOR)
                    .stems(0.0)
                    .radius(2.0),
            );
        });
}

fn show_response_plot(
    ui: &mut egui::Ui,
    computed: &Computed,
    response_view: ResponseView,
    height: f32,
) {
    let points: PlotPoints = computed
        .response
        .iter()
        .map(|point| {
            let y = match response_view {
                ResponseView::Magnitude => point.magnitude_db.max(DB_FLOOR),
                ResponseView::Phase => point.phase_deg,
            };
            [point.frequency_hz, y]
        })
        .collect();
    let y_label = match response_view {
        ResponseView::Magnitude => "zesílení [dB]",
        ResponseView::Phase => "fáze [°]",
    };

    Plot::new("filter_response_plot")
        .height(height)
        .y_axis_min_width(Y_AXIS_WIDTH)
        .custom_x_axes(narrow_x_axis("frekvence [Hz]"))
        .y_axis_label(y_label)
        .link_axis(egui::Id::unique("filter_frequency_axes"), [true, false])
        .show(ui, |plot_ui| {
            plot_ui.line(Line::new("filtr", points).color(RESPONSE_COLOR).width(2.0));
            for frequency_hz in marker_frequencies(&computed.settings) {
                plot_ui.vline(
                    VLine::new("nastavená frekvence", frequency_hz)
                        .color(MARKER_COLOR)
                        .style(LineStyle::dashed_loose()),
                );
            }
        });
}

/// Frekvence nastavené v ovládání, které vyznačíme svislou čarou.
fn marker_frequencies(settings: &Settings) -> Vec<f64> {
    let is_fir_band =
        settings.family == FilterFamily::Fir && settings.filter_type == FilterType::BandPass;
    if is_fir_band {
        vec![settings.frequency_hz, settings.upper_frequency_hz]
    } else {
        vec![settings.frequency_hz]
    }
}

fn show_time_plot(ui: &mut egui::Ui, computed: &Computed, height: f32) {
    Plot::new("filter_time_plot")
        .height(height)
        .y_axis_min_width(Y_AXIS_WIDTH)
        .custom_x_axes(narrow_x_axis("čas [ms]"))
        .legend(Legend::default())
        .show(ui, |plot_ui| {
            plot_ui.line(Line::new("vstup", time_points(&computed.input)).color(INPUT_COLOR));
            plot_ui.line(
                Line::new("výstup", time_points(&computed.output))
                    .color(OUTPUT_COLOR)
                    .width(2.0),
            );
        });
}

fn time_points(samples: &[f64]) -> PlotPoints<'static> {
    samples
        .iter()
        .enumerate()
        .map(|(index, &value)| [1000.0 * index as f64 / SAMPLE_RATE_HZ, value])
        .collect()
}

fn show_spectrum_plot(ui: &mut egui::Ui, computed: &Computed, height: f32) {
    Plot::new("filter_spectrum_plot")
        .height(height)
        .y_axis_min_width(Y_AXIS_WIDTH)
        .custom_x_axes(narrow_x_axis("frekvence [Hz]"))
        .y_axis_label("amplituda [dB]")
        .link_axis(egui::Id::unique("filter_frequency_axes"), [true, false])
        .legend(Legend::default())
        .show(ui, |plot_ui| {
            plot_ui.line(
                Line::new("vstup", spectrum_points(&computed.input_spectrum)).color(INPUT_COLOR),
            );
            plot_ui.line(
                Line::new("výstup", spectrum_points(&computed.output_spectrum))
                    .color(OUTPUT_COLOR)
                    .width(2.0),
            );
            // Zesílení filtru pro srovnání: výstup ≈ vstup + zesílení (v dB).
            let response: PlotPoints = computed
                .response
                .iter()
                .map(|point| [point.frequency_hz, point.magnitude_db.max(DB_FLOOR)])
                .collect();
            plot_ui.line(
                Line::new("zesílení filtru", response)
                    .color(RESPONSE_COLOR)
                    .style(LineStyle::dashed_loose()),
            );
        });
}

fn spectrum_points(lines: &[SpectrumLine]) -> PlotPoints<'static> {
    lines
        .iter()
        .map(|line| [line.frequency_hz, line.amplitude_db.max(DB_FLOOR)])
        .collect()
}
