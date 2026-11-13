//! Záložka „Vzorkování a aliasing“: spojitý signál, jeho vzorky, obnova ze
//! vzorků a spektrum před a po vzorkování.
//!
//! Vysvětlení a návod, co zkoušet: `docs/03-vzorkovani-a-aliasing.md`.

use egui::Color32;
use egui_plot::{Legend, Line, LineStyle, Plot, PlotPoints, Points, VLine};
use tracing::debug;

use crate::dsp::fft::{dft, fft, real_to_complex};
use crate::dsp::sampling::{alias_frequency, reconstruct, sample, sample_time};
use crate::dsp::signal::{Component, SignalSpec, Waveform, generate, value_at};
use crate::dsp::spectrum::{SpectrumLine, one_sided_spectrum};
use crate::ui::common::{
    CONTROLS_WIDTH, Y_AXIS_WIDTH, component_controls, format_hz, hover_label, plot_height,
    waveform_name,
};

const MIN_SAMPLE_RATE_HZ: f64 = 1.0;
const MAX_SAMPLE_RATE_HZ: f64 = 200.0;
const MAX_COMPONENT_FREQUENCY_HZ: f64 = 100.0;
const MAX_COMPONENTS: usize = 3;

/// Délka zobrazeného úseku. Je to zároveň délka záznamu pro spektrum,
/// takže biny jsou po 1 Hz a celočíselné frekvence padnou přesně do binu.
const DURATION_S: f64 = 1.0;

/// Vzorky navíc před a za zobrazeným úsekem. Rekonstrukce potřebuje vzorky
/// z obou stran; bez nich by byla u okrajů úseku nepřesná.
const MARGIN_S: f64 = 1.0;

/// Počet bodů, kterými kreslíme „spojitý“ signál a jeho rekonstrukci.
const DISPLAY_POINTS: usize = 2000;

/// Spojitý signál pro spektrum nahrazujeme hodně hustým vzorkováním.
/// 2048 vzorků za 1 s je mocnina dvou, takže lze použít FFT.
const REFERENCE_RATE_HZ: f64 = 2048.0;

/// Spektrum kreslíme jen do této frekvence; vyšší harmonické už nejsou zajímavé.
const SPECTRUM_MAX_HZ: f64 = 250.0;

/// Čáry spektra slabší než tato amplituda nekreslíme, aby graf nezaplnily
/// puntíky u nuly (drobné prosakování u necelých period obdélníku apod.).
const MIN_DRAWN_AMPLITUDE: f64 = 5e-3;

const CONTINUOUS_COLOR: Color32 = Color32::from_rgb(150, 150, 150);
const SAMPLE_COLOR: Color32 = Color32::from_rgb(240, 150, 50);
const RECONSTRUCTION_COLOR: Color32 = Color32::from_rgb(90, 170, 255);
const NYQUIST_COLOR: Color32 = Color32::from_rgb(230, 80, 80);
const ALIAS_COLOR: Color32 = Color32::from_rgb(230, 80, 80);

/// Všechno, od čeho závisí výsledek výpočtu.
#[derive(Clone, Debug, PartialEq)]
struct Settings {
    signal: SignalSpec,
    sample_rate_hz: f64,
}

/// Výsledek výpočtu pro jedno nastavení.
struct Computed {
    settings: Settings,
    /// Spojitý signál v zobrazeném úseku.
    continuous: Vec<[f64; 2]>,
    /// Signál obnovený ze vzorků v zobrazeném úseku.
    reconstructed: Vec<[f64; 2]>,
    /// Vzorky v zobrazeném úseku (čas, hodnota).
    samples: Vec<[f64; 2]>,
    continuous_lines: Vec<SpectrumLine>,
    sampled_lines: Vec<SpectrumLine>,
}

/// Stav záložky.
pub struct SamplingTab {
    settings: Settings,
    show_reconstruction: bool,
    computed: Option<Computed>,
}

impl Default for SamplingTab {
    /// Výchozí stav: sinusovka 5 Hz vzorkovaná 40 Hz – hluboko pod Nyquistovou
    /// frekvencí, takže vzorkování funguje. Aliasing se ukáže po zvýšení frekvence.
    fn default() -> Self {
        SamplingTab {
            settings: Settings {
                signal: SignalSpec {
                    components: vec![sine(5.0)],
                    dc_offset: 0.0,
                    noise_amplitude: 0.0,
                    noise_seed: 1,
                },
                sample_rate_hz: 40.0,
            },
            show_reconstruction: true,
            computed: None,
        }
    }
}

fn sine(frequency_hz: f64) -> Component {
    Component {
        enabled: true,
        waveform: Waveform::Sine,
        frequency_hz,
        amplitude: 1.0,
        phase_deg: 0.0,
    }
}

/// Nakreslí obsah záložky.
pub fn show(ui: &mut egui::Ui, tab: &mut SamplingTab) {
    egui::Panel::left("sampling_controls")
        .exact_size(CONTROLS_WIDTH)
        .show(ui, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| show_controls(ui, tab));
        });

    update_computed(tab);

    egui::CentralPanel::default().show(ui, |ui| {
        if let Some(computed) = &tab.computed {
            show_plots(ui, computed, tab.show_reconstruction);
        }
    });
}

/// Přepočítá vše, pokud se od posledního výpočtu změnilo nastavení.
fn update_computed(tab: &mut SamplingTab) {
    let is_current = tab
        .computed
        .as_ref()
        .is_some_and(|computed| computed.settings == tab.settings);
    if !is_current {
        tab.computed = Some(compute(&tab.settings));
    }
}

fn compute(settings: &Settings) -> Computed {
    let spec = &settings.signal;
    let rate = settings.sample_rate_hz;

    // Vzorky: nejdřív okraj před úsekem, pak úsek, pak okraj za ním.
    // Začátek okraje je celý násobek periody vzorkování, aby jeden vzorek
    // padl přesně na čas 0.
    let margin_count = (MARGIN_S * rate).round() as usize;
    let visible_count = (DURATION_S * rate).round() as usize;
    let start_time_s = -(margin_count as f64) / rate;
    let sampled = sample(
        spec,
        rate,
        start_time_s,
        margin_count + visible_count + margin_count,
    );

    let display_times: Vec<f64> = (0..=DISPLAY_POINTS)
        .map(|index| DURATION_S * index as f64 / DISPLAY_POINTS as f64)
        .collect();
    let continuous = display_times
        .iter()
        .map(|&time_s| [time_s, value_at(spec, time_s)])
        .collect();
    let reconstructed = display_times
        .iter()
        .map(|&time_s| [time_s, reconstruct(&sampled, time_s)])
        .collect();

    let visible_range = margin_count..margin_count + visible_count;
    let samples = visible_range
        .clone()
        .map(|index| [sample_time(&sampled, index), sampled.values[index]])
        .collect();

    // Počet vzorků v úseku obecně není mocnina dvou, proto zde pomalá DFT.
    let visible_values = &sampled.values[visible_range];
    let sampled_lines = one_sided_spectrum(
        &dft(&real_to_complex(visible_values)),
        rate,
        visible_count as f64,
    );

    let reference_count = (REFERENCE_RATE_HZ * DURATION_S) as usize;
    let reference = generate(spec, REFERENCE_RATE_HZ, reference_count);
    let continuous_lines = one_sided_spectrum(
        &fft(&real_to_complex(&reference)),
        REFERENCE_RATE_HZ,
        reference_count as f64,
    )
    .into_iter()
    .filter(|line| line.frequency_hz <= SPECTRUM_MAX_HZ)
    .collect();

    debug!(
        sample_rate_hz = rate,
        sample_count = sampled.values.len(),
        "sampling demo computed"
    );

    Computed {
        settings: settings.clone(),
        continuous,
        reconstructed,
        samples,
        continuous_lines,
        sampled_lines,
    }
}

// ---------------------------------------------------------------------------
// Ovládací panel
// ---------------------------------------------------------------------------

fn show_controls(ui: &mut egui::Ui, tab: &mut SamplingTab) {
    show_sampling_controls(ui, &mut tab.settings);
    ui.separator();
    show_signal_controls(ui, &mut tab.settings);
    ui.separator();
    show_alias_summary(ui, &tab.settings);
    ui.separator();
    show_view_controls(ui, tab);
}

fn show_sampling_controls(ui: &mut egui::Ui, settings: &mut Settings) {
    ui.heading("Vzorkování");
    ui.add(
        egui::Slider::new(
            &mut settings.sample_rate_hz,
            MIN_SAMPLE_RATE_HZ..=MAX_SAMPLE_RATE_HZ,
        )
        .integer()
        .suffix(" Hz")
        .text("fs"),
    );
    ui.label(format!(
        "Perioda vzorkování 1/fs: {:.1} ms",
        1000.0 / settings.sample_rate_hz
    ));
    ui.label(format!(
        "Nyquistova frekvence fs/2: {}",
        format_hz(settings.sample_rate_hz / 2.0)
    ));
}

fn show_signal_controls(ui: &mut egui::Ui, settings: &mut Settings) {
    ui.heading("Signál");
    let signal = &mut settings.signal;

    // Složku nelze odebrat uprostřed procházení seznamu, proto si jen
    // zapamatujeme její index a odebereme ji až po cyklu.
    let mut index_to_remove = None;
    for (index, component) in signal.components.iter_mut().enumerate() {
        // Celé hertzy: záznam trvá 1 s, takže pak nevzniká prosakování.
        let remove_clicked =
            component_controls(ui, index, component, MAX_COMPONENT_FREQUENCY_HZ, 1.0);
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
        signal.components.push(sine(10.0));
    }
}

/// U každé složky ukáže, na jaké frekvenci se objeví po navzorkování.
fn show_alias_summary(ui: &mut egui::Ui, settings: &Settings) {
    ui.heading("Po navzorkování");
    let rate = settings.sample_rate_hz;
    for (index, component) in settings.signal.components.iter().enumerate() {
        if !component.enabled {
            continue;
        }
        let frequency = component.frequency_hz;
        let alias = alias_frequency(frequency, rate);
        let text = format!(
            "Složka {} ({}): {} se jeví jako {}",
            index + 1,
            waveform_name(component.waveform),
            format_hz(frequency),
            format_hz(alias)
        );
        if (alias - frequency).abs() > 1e-9 {
            ui.colored_label(ALIAS_COLOR, format!("{text} (alias)"));
        } else {
            ui.label(text);
        }
    }
    ui.weak(
        "Frekvence nad fs/2 se zrcadlí kolem násobků fs/2. U obdélníku, pily \
         a trojúhelníku se takto překládají i vyšší harmonické.",
    );
}

fn show_view_controls(ui: &mut egui::Ui, tab: &mut SamplingTab) {
    ui.heading("Zobrazení");
    ui.checkbox(
        &mut tab.show_reconstruction,
        "Rekonstrukce ze vzorků (interpolace sinc)",
    );
    ui.weak("Grafy: tažením posun, kolečkem s Ctrl zvětšení, dvojklik obnoví zobrazení.");
}

// ---------------------------------------------------------------------------
// Grafy
// ---------------------------------------------------------------------------

fn show_plots(ui: &mut egui::Ui, computed: &Computed, show_reconstruction: bool) {
    let height = plot_height(ui, 2);

    ui.label("Spojitý signál, jeho vzorky a signál obnovený ze vzorků");
    show_time_plot(ui, computed, show_reconstruction, height);

    ui.label("Amplitudové spektrum před a po navzorkování");
    show_spectrum_plot(ui, computed, height);
}

fn show_time_plot(ui: &mut egui::Ui, computed: &Computed, show_reconstruction: bool, height: f32) {
    Plot::new("sampling_time_plot")
        .height(height)
        .label_formatter(hover_label("čas [s]", "hodnota"))
        .y_axis_min_width(Y_AXIS_WIDTH)
        .x_axis_label("čas [s]")
        .legend(Legend::default())
        .show(ui, |plot_ui| {
            plot_ui.line(
                Line::new(
                    "spojitý signál",
                    PlotPoints::new(computed.continuous.clone()),
                )
                .color(CONTINUOUS_COLOR),
            );
            if show_reconstruction {
                plot_ui.line(
                    Line::new(
                        "rekonstrukce ze vzorků",
                        PlotPoints::new(computed.reconstructed.clone()),
                    )
                    .color(RECONSTRUCTION_COLOR)
                    .width(2.0),
                );
            }
            plot_ui.points(
                Points::new("vzorky", PlotPoints::new(computed.samples.clone()))
                    .color(SAMPLE_COLOR)
                    .stems(0.0)
                    .radius(3.5),
            );
        });
}

fn show_spectrum_plot(ui: &mut egui::Ui, computed: &Computed, height: f32) {
    let rate = computed.settings.sample_rate_hz;

    Plot::new("sampling_spectrum_plot")
        .height(height)
        .label_formatter(hover_label("frekvence [Hz]", "amplituda"))
        .y_axis_min_width(Y_AXIS_WIDTH)
        .x_axis_label("frekvence [Hz]")
        .y_axis_label("amplituda")
        .include_x(0.0)
        .include_y(0.0)
        .legend(Legend::default())
        .show(ui, |plot_ui| {
            plot_ui.points(
                Points::new("spojitý signál", visible_lines(&computed.continuous_lines))
                    .color(CONTINUOUS_COLOR)
                    .stems(0.0)
                    .radius(4.0),
            );
            plot_ui.points(
                Points::new("po navzorkování", visible_lines(&computed.sampled_lines))
                    .color(SAMPLE_COLOR)
                    .stems(0.0)
                    .radius(3.0),
            );
            plot_ui.vline(
                VLine::new("Nyquistova frekvence fs/2", rate / 2.0)
                    .color(NYQUIST_COLOR)
                    .style(LineStyle::dashed_loose()),
            );
            plot_ui.vline(
                VLine::new("vzorkovací frekvence fs", rate)
                    .color(CONTINUOUS_COLOR)
                    .style(LineStyle::dashed_dense()),
            );
        });
}

/// Body pro graf spektra bez čar s téměř nulovou amplitudou.
fn visible_lines(lines: &[SpectrumLine]) -> PlotPoints<'static> {
    lines
        .iter()
        .filter(|line| line.amplitude > MIN_DRAWN_AMPLITUDE)
        .map(|line| [line.frequency_hz, line.amplitude])
        .collect()
}
