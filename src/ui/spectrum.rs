//! Záložka „Signály a spektrum“: vlevo ovládání signálu, vpravo grafy
//! časového průběhu, amplitudového spektra a fáze.

use std::time::{Duration, Instant};

use tracing::debug;

use egui_plot::{Line, Plot, PlotPoints, Points};

use crate::dsp::complex::Complex;
use crate::dsp::fft::{dft, fft, ifft, real_to_complex};
use crate::dsp::signal::{Component, SignalSpec, Waveform, generate};
use crate::dsp::spectrum::{SpectrumLine, one_sided_spectrum};

/// Nejmenší a největší nabízená délka FFT jako mocnina dvou (8 až 4096 vzorků).
const MIN_FFT_EXPONENT: u32 = 3;
const MAX_FFT_EXPONENT: u32 = 12;

const MIN_SAMPLE_RATE_HZ: f64 = 64.0;
const MAX_SAMPLE_RATE_HZ: f64 = 48_000.0;

const MAX_COMPONENTS: usize = 6;
const MAX_AMPLITUDE: f64 = 2.0;

/// Spodní okraj grafu v decibelech; menší hodnoty se oříznou.
const DB_FLOOR: f64 = -120.0;

/// Do tohoto počtu binů kreslíme spektrum jako jednotlivé čáry s puntíky,
/// aby bylo vidět, že spektrum je diskrétní. Při větším počtu by splývaly.
const MAX_STEM_BINS: usize = 129;

const CONTROLS_WIDTH: f32 = 300.0;

/// Stejná šířka svislé osy u všech grafů, aby byly grafy pod sebou zarovnané.
const Y_AXIS_WIDTH: f32 = 48.0;

/// Kterým algoritmem se spektrum počítá.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Algorithm {
    Fft,
    Dft,
}

/// Svislá osa amplitudového spektra.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AmplitudeScale {
    Linear,
    Decibel,
}

/// Vodorovná osa spektra.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum FrequencyAxis {
    Hertz,
    Bin,
}

/// Všechno, od čeho závisí výsledek výpočtu. Když se změní, počítá se znovu.
#[derive(Clone, Debug, PartialEq)]
struct Settings {
    signal: SignalSpec,
    sample_rate_hz: f64,
    fft_exponent: u32,
    algorithm: Algorithm,
}

/// Výsledek výpočtu pro jedno nastavení.
struct Computed {
    /// Nastavení, pro které výsledek platí.
    settings: Settings,
    samples: Vec<f64>,
    lines: Vec<SpectrumLine>,
    /// Jak dlouho trvala samotná transformace.
    transform_time: Duration,
    /// Největší rozdíl mezi původním vzorkem a vzorkem po cestě tam a zpět
    /// (FFT a zpětná FFT). Měl by být na úrovni zaokrouhlovacích chyb.
    round_trip_error: f64,
}

/// Stav záložky.
pub struct SpectrumTab {
    settings: Settings,
    amplitude_scale: AmplitudeScale,
    frequency_axis: FrequencyAxis,
    computed: Option<Computed>,
}

impl Default for SpectrumTab {
    /// Výchozí nastavení: fs = 1024 Hz a N = 1024, takže biny jsou přesně
    /// po 1 Hz a obě sinusovky padnou přesně do svého binu.
    fn default() -> Self {
        SpectrumTab {
            settings: Settings {
                signal: SignalSpec {
                    components: vec![new_component(50.0, 1.0), new_component(120.0, 0.5)],
                    dc_offset: 0.0,
                    noise_amplitude: 0.0,
                    noise_seed: 1,
                },
                sample_rate_hz: 1024.0,
                fft_exponent: 10,
                algorithm: Algorithm::Fft,
            },
            amplitude_scale: AmplitudeScale::Linear,
            frequency_axis: FrequencyAxis::Hertz,
            computed: None,
        }
    }
}

fn new_component(frequency_hz: f64, amplitude: f64) -> Component {
    Component {
        enabled: true,
        waveform: Waveform::Sine,
        frequency_hz,
        amplitude,
        phase_deg: 0.0,
    }
}

/// Nakreslí obsah záložky.
pub fn show(ui: &mut egui::Ui, tab: &mut SpectrumTab) {
    egui::Panel::left("spectrum_controls")
        .exact_size(CONTROLS_WIDTH)
        .show(ui, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| show_controls(ui, tab));
        });

    update_computed(tab);

    egui::CentralPanel::default().show(ui, |ui| {
        if let Some(computed) = &tab.computed {
            show_plots(ui, computed, tab.amplitude_scale, tab.frequency_axis);
        }
    });
}

/// Přepočítá signál a spektrum, pokud se od posledního výpočtu změnilo nastavení.
fn update_computed(tab: &mut SpectrumTab) {
    let is_current = tab
        .computed
        .as_ref()
        .is_some_and(|computed| computed.settings == tab.settings);
    if !is_current {
        tab.computed = Some(compute(&tab.settings));
    }
}

fn compute(settings: &Settings) -> Computed {
    let fft_size = 1usize << settings.fft_exponent;
    let samples = generate(&settings.signal, settings.sample_rate_hz, fft_size);
    let input = real_to_complex(&samples);

    let start = Instant::now();
    let output = match settings.algorithm {
        Algorithm::Fft => fft(&input),
        Algorithm::Dft => dft(&input),
    };
    let transform_time = start.elapsed();

    // Při tažení posuvníku se počítá v každém snímku, proto jen úroveň debug.
    debug!(
        algorithm = ?settings.algorithm,
        fft_size,
        sample_rate_hz = settings.sample_rate_hz,
        transform_time_us = transform_time.as_micros() as u64,
        "spectrum computed"
    );

    let round_trip_error = max_difference(&samples, &ifft(&output));

    Computed {
        settings: settings.clone(),
        round_trip_error,
        samples,
        lines: one_sided_spectrum(&output, settings.sample_rate_hz),
        transform_time,
    }
}

/// Největší vzdálenost mezi původními vzorky a vzorky obnovenými zpětnou FFT.
fn max_difference(samples: &[f64], restored: &[Complex]) -> f64 {
    samples
        .iter()
        .zip(restored)
        .map(|(&sample, &value)| (value - Complex::new(sample, 0.0)).magnitude())
        .fold(0.0, f64::max)
}

// ---------------------------------------------------------------------------
// Ovládací panel
// ---------------------------------------------------------------------------

fn show_controls(ui: &mut egui::Ui, tab: &mut SpectrumTab) {
    show_sampling_controls(ui, &mut tab.settings);
    ui.separator();
    show_signal_controls(ui, &mut tab.settings);
    ui.separator();
    show_algorithm_controls(ui, tab);
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
        .logarithmic(true)
        .integer()
        .suffix(" Hz")
        .text("fs"),
    );

    egui::ComboBox::from_label("délka FFT (N)")
        .selected_text(format!("{}", 1usize << settings.fft_exponent))
        .show_ui(ui, |ui| {
            for exponent in MIN_FFT_EXPONENT..=MAX_FFT_EXPONENT {
                let label = format!("{} = 2^{}", 1usize << exponent, exponent);
                ui.selectable_value(&mut settings.fft_exponent, exponent, label);
            }
        });

    let fft_size = (1usize << settings.fft_exponent) as f64;
    ui.label(format!(
        "Rozestup binů fs/N: {}",
        format_hz(settings.sample_rate_hz / fft_size)
    ));
    ui.label(format!(
        "Délka záznamu N/fs: {:.1} ms",
        1000.0 * fft_size / settings.sample_rate_hz
    ));
    ui.label(format!(
        "Nyquistova frekvence fs/2: {}",
        format_hz(settings.sample_rate_hz / 2.0)
    ));

    clamp_frequencies(settings);
}

/// Frekvence složek držíme pod Nyquistovou frekvencí; co se stane nad ní,
/// ukazuje záložka o vzorkování a aliasingu.
fn clamp_frequencies(settings: &mut Settings) {
    let nyquist_hz = settings.sample_rate_hz / 2.0;
    for component in &mut settings.signal.components {
        component.frequency_hz = component.frequency_hz.min(nyquist_hz);
    }
}

fn show_signal_controls(ui: &mut egui::Ui, settings: &mut Settings) {
    ui.heading("Signál");
    let nyquist_hz = settings.sample_rate_hz / 2.0;
    let signal = &mut settings.signal;

    // Složku nelze odebrat uprostřed procházení seznamu, proto si jen
    // zapamatujeme její index a odebereme ji až po cyklu.
    let mut index_to_remove = None;
    for (index, component) in signal.components.iter_mut().enumerate() {
        let remove_clicked = show_component_controls(ui, index, component, nyquist_hz);
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
        signal.components.push(new_component(nyquist_hz / 4.0, 0.5));
    }

    ui.add_space(6.0);
    ui.add(
        egui::Slider::new(&mut signal.dc_offset, -MAX_AMPLITUDE..=MAX_AMPLITUDE)
            .text("stejnosměrná složka"),
    );
    ui.add(egui::Slider::new(&mut signal.noise_amplitude, 0.0..=MAX_AMPLITUDE).text("šum"));
    if ui.button("Nový šum").clicked() {
        signal.noise_seed += 1;
    }
}

/// Ovládání jedné složky. Vrací `true`, pokud uživatel klikl na „Odebrat“.
fn show_component_controls(
    ui: &mut egui::Ui,
    index: usize,
    component: &mut Component,
    nyquist_hz: f64,
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
                egui::Slider::new(&mut component.frequency_hz, 0.0..=nyquist_hz)
                    .suffix(" Hz")
                    .text("frekvence"),
            );
            ui.add(
                egui::Slider::new(&mut component.amplitude, 0.0..=MAX_AMPLITUDE).text("amplituda"),
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

fn waveform_name(waveform: Waveform) -> &'static str {
    match waveform {
        Waveform::Sine => "sinus",
        Waveform::Square => "obdélník",
        Waveform::Sawtooth => "pila",
        Waveform::Triangle => "trojúhelník",
    }
}

fn show_algorithm_controls(ui: &mut egui::Ui, tab: &mut SpectrumTab) {
    ui.heading("Výpočet");
    ui.horizontal(|ui| {
        let algorithm = &mut tab.settings.algorithm;
        ui.radio_value(algorithm, Algorithm::Fft, "FFT (rychlá)");
        ui.radio_value(algorithm, Algorithm::Dft, "DFT (podle definice)");
    });
    if let Some(computed) = &tab.computed {
        let microseconds = computed.transform_time.as_secs_f64() * 1e6;
        ui.label(format!("Doba transformace: {microseconds:.0} µs"));
        ui.label(format!(
            "Zpětná FFT vrátí signál s chybou nejvýš {:.1e}",
            computed.round_trip_error
        ));
    }
    ui.weak("Obě metody dávají stejné spektrum, liší se jen rychlostí.");
}

fn show_view_controls(ui: &mut egui::Ui, tab: &mut SpectrumTab) {
    ui.heading("Zobrazení");
    ui.horizontal(|ui| {
        ui.label("Amplituda:");
        ui.radio_value(&mut tab.amplitude_scale, AmplitudeScale::Linear, "lineárně");
        ui.radio_value(&mut tab.amplitude_scale, AmplitudeScale::Decibel, "v dB");
    });
    ui.horizontal(|ui| {
        ui.label("Osa spektra:");
        ui.radio_value(&mut tab.frequency_axis, FrequencyAxis::Hertz, "Hz");
        ui.radio_value(&mut tab.frequency_axis, FrequencyAxis::Bin, "číslo binu");
    });
    ui.weak("Grafy: tažením posun, kolečkem s Ctrl zvětšení, dvojklik obnoví zobrazení.");
}

fn format_hz(frequency_hz: f64) -> String {
    if frequency_hz < 10.0 {
        format!("{frequency_hz:.3} Hz")
    } else {
        format!("{frequency_hz:.1} Hz")
    }
}

// ---------------------------------------------------------------------------
// Grafy
// ---------------------------------------------------------------------------

fn show_plots(
    ui: &mut egui::Ui,
    computed: &Computed,
    amplitude_scale: AmplitudeScale,
    frequency_axis: FrequencyAxis,
) {
    // Tři grafy pod sebou si rozdělí dostupnou výšku rovným dílem.
    let label_height = ui.text_style_height(&egui::TextStyle::Body) + ui.spacing().item_spacing.y;
    let plot_height = (ui.available_height() / 3.0 - label_height - 4.0).max(80.0);

    ui.label("Časový průběh");
    show_time_plot(ui, computed, plot_height);

    ui.label("Amplitudové spektrum");
    show_amplitude_plot(ui, computed, amplitude_scale, frequency_axis, plot_height);

    ui.label("Fázové spektrum (vztaženo ke kosinu, sinus má −90°)");
    show_phase_plot(ui, computed, frequency_axis, plot_height);
}

fn show_time_plot(ui: &mut egui::Ui, computed: &Computed, height: f32) {
    let sample_rate_hz = computed.settings.sample_rate_hz;
    let points: Vec<[f64; 2]> = computed
        .samples
        .iter()
        .enumerate()
        .map(|(index, &sample)| [1000.0 * index as f64 / sample_rate_hz, sample])
        .collect();

    Plot::new("time_plot")
        .height(height)
        .y_axis_min_width(Y_AXIS_WIDTH)
        .x_axis_label("čas [ms]")
        .y_axis_label("hodnota")
        .show(ui, |plot_ui| {
            plot_ui.line(Line::new("signál", PlotPoints::new(points)));
        });
}

fn show_amplitude_plot(
    ui: &mut egui::Ui,
    computed: &Computed,
    amplitude_scale: AmplitudeScale,
    frequency_axis: FrequencyAxis,
    height: f32,
) {
    let points: Vec<[f64; 2]> = computed
        .lines
        .iter()
        .map(|line| {
            let y = match amplitude_scale {
                AmplitudeScale::Linear => line.amplitude,
                AmplitudeScale::Decibel => line.amplitude_db.max(DB_FLOOR),
            };
            [frequency_coordinate(line, frequency_axis), y]
        })
        .collect();

    let y_label = match amplitude_scale {
        AmplitudeScale::Linear => "amplituda",
        AmplitudeScale::Decibel => "amplituda [dB]",
    };
    // Čáry od nuly dávají smysl jen v lineárním měřítku a při málo binech.
    let draw_stems =
        amplitude_scale == AmplitudeScale::Linear && computed.lines.len() <= MAX_STEM_BINS;

    Plot::new("amplitude_plot")
        .height(height)
        .y_axis_min_width(Y_AXIS_WIDTH)
        .x_axis_label(frequency_axis_label(frequency_axis))
        .y_axis_label(y_label)
        .link_axis(egui::Id::unique("spectrum_axes"), [true, false])
        .show(ui, |plot_ui| {
            if draw_stems {
                plot_ui.points(
                    Points::new("amplituda", PlotPoints::new(points))
                        .stems(0.0)
                        .radius(3.0),
                );
            } else {
                plot_ui.line(Line::new("amplituda", PlotPoints::new(points)));
            }
        });
}

fn show_phase_plot(
    ui: &mut egui::Ui,
    computed: &Computed,
    frequency_axis: FrequencyAxis,
    height: f32,
) {
    let points: Vec<[f64; 2]> = computed
        .lines
        .iter()
        .map(|line| [frequency_coordinate(line, frequency_axis), line.phase_deg])
        .collect();

    Plot::new("phase_plot")
        .height(height)
        .y_axis_min_width(Y_AXIS_WIDTH)
        .x_axis_label(frequency_axis_label(frequency_axis))
        .y_axis_label("fáze [°]")
        .include_y(-180.0)
        .include_y(180.0)
        .link_axis(egui::Id::unique("spectrum_axes"), [true, false])
        .show(ui, |plot_ui| {
            plot_ui.points(
                Points::new("fáze", PlotPoints::new(points))
                    .stems(0.0)
                    .radius(2.0),
            );
        });
}

fn frequency_coordinate(line: &SpectrumLine, frequency_axis: FrequencyAxis) -> f64 {
    match frequency_axis {
        FrequencyAxis::Hertz => line.frequency_hz,
        FrequencyAxis::Bin => line.bin as f64,
    }
}

fn frequency_axis_label(frequency_axis: FrequencyAxis) -> &'static str {
    match frequency_axis {
        FrequencyAxis::Hertz => "frekvence [Hz]",
        FrequencyAxis::Bin => "číslo binu k",
    }
}
