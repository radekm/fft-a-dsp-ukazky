# PLAN.md – plán projektu

## Cíl

Interaktivní desktopový program v Rustu (egui), na kterém si lze „osahat“
FFT a digitální zpracování signálu (DSP): pohnu posuvníkem a hned vidím, co
to udělá se signálem a jeho spektrem.

Program je učební pomůcka. Přednost má srozumitelnost před výkonem a úplností.

## Rozhodnutí

- FFT i ostatní algoritmy jsou vlastní implementace s českými komentáři.
- Jen syntetické signály generované v programu (bez mikrofonu, přehrávání a WAV).
- Povolené crates: viz `AGENTS.md`. Grafy kreslí `egui_plot`.
- Texty v uživatelském rozhraní jsou česky.
- Délka FFT je mocnina dvou (radix-2); kratší signál se doplní nulami.

## Struktura

```
src/
  main.rs          spuštění eframe
  app.rs           stav aplikace, přepínání záložek
  dsp/             čisté výpočty, bez egui
    complex.rs     komplexní číslo
    signal.rs      generátory signálů
    fft.rs         DFT (pomalá) a FFT (radix-2), zpětná FFT
    window.rs      okénkové funkce
    filter.rs      FIR a IIR filtry, frekvenční odezva
    sampling.rs    převzorkování, rekonstrukce
  ui/              jedna záložka = jeden soubor
    spectrum.rs
    windows.rs
    sampling.rs
    filters.rs
docs/              česká vysvětlení k jednotlivým tématům
```

## Fáze

### Fáze 0 – kostra
- [ ] `Cargo.toml` s povolenými crates, prázdné okno se záložkami.
- [ ] Hlášení chyb přes color-eyre, logování přes tracing.
- [ ] `README.md` (česky): co program je, jak ho přeložit a spustit.
- [ ] Nastavení `cargo fmt`, `clippy`, `test`.

### Fáze 1 – signály a spektrum
- [ ] Vlastní typ komplexního čísla.
- [ ] Generátor: součet několika složek (sinus, obdélník, pila, trojúhelník),
      u každé frekvence, amplituda a fáze; volitelně bílý šum a stejnosměrná složka.
- [ ] Pomalá DFT podle definice a rychlá FFT (radix-2), zpětná FFT.
- [ ] Graf časového průběhu.
- [ ] Graf spektra: amplituda (lineárně i v dB) a fáze; osa ve frekvenci i v binech.
- [ ] Volba vzorkovací frekvence a délky FFT.
- [ ] Testy: FFT = DFT, zpětná FFT vrátí signál, špička sinusovky ve správném binu.

### Fáze 2 – okna a prosakování
- [ ] Okna: obdélníkové, Hann, Hamming, Blackman.
- [ ] Zobrazení tvaru okna a jeho spektra (hlavní lalok, postranní laloky).
- [ ] Ukázka prosakování: frekvence přesně v binu a mezi biny, s oknem a bez.
- [ ] Doplnění nulami (zero-padding) a jeho vliv na vzhled spektra.

### Fáze 3 – vzorkování a aliasing
- [ ] „Spojitý“ signál (hustě vzorkovaný) a přes něj vzorky při zvolené
      vzorkovací frekvenci.
- [ ] Vyznačení Nyquistovy frekvence; alias, který ze vzorků vyjde.
- [ ] Rekonstrukce signálu ze vzorků (sinc interpolace).
- [ ] Spektrum před a po podvzorkování.

### Fáze 4 – filtry
- [ ] FIR: návrh metodou okna (windowed-sinc) – dolní, horní a pásmová propust;
      volba mezní frekvence, délky filtru a okna.
- [ ] IIR: bikvadratický filtr (biquad) – dolní, horní a pásmová propust;
      volba mezní frekvence a Q.
- [ ] Zobrazení koeficientů / impulzní odezvy a frekvenční odezvy (amplituda, fáze).
- [ ] Signál a jeho spektrum před a po filtraci.
- [ ] Konvoluce jako samostatná, okomentovaná funkce.

### Fáze 5 – dokumentace
- [ ] `docs/` – ke každé záložce krátké české vysvětlení, co zkoušet a čeho si všímat.
- [ ] Projít komentáře v kódu, doplnit odkazy na vzorce.

## Možná později (mimo první verzi)

- Spektrogram (STFT).
- Krokování FFT po jednotlivých fázích (motýlky).
- Zvuk: přehrávání, WAV, mikrofon (vyžádá povolení dalších crates).
- Zobrazení pólů a nul filtru.

## Otevřené otázky

- Na Linuxu se `eframe` jen s feature `glow` nepřeloží (winit potřebuje
  `x11` nebo `wayland`). Čeká na rozhodnutí autora.
