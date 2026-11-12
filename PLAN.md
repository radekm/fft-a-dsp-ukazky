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
- Logování je strukturované (pojmenovaná pole, JSON do `logs/`).
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
    spectrum.rs    amplituda, decibely a fáze z výsledku FFT
    window.rs      okénkové funkce
    filter.rs      FIR a IIR filtry, frekvenční odezva
    sampling.rs    převzorkování, rekonstrukce
  ui/              jedna záložka = jeden soubor
    common.rs      věci společné pro více záložek
    spectrum.rs
    windows.rs
    sampling.rs
    filters.rs
docs/              česká vysvětlení k jednotlivým tématům
  ucebnice/        pidi učebnice: krátké lekce pro začátečníky
```

## Fáze

### Fáze 0 – kostra
- [x] `Cargo.toml` s povolenými crates, prázdné okno se záložkami.
- [x] Hlášení chyb přes color-eyre, logování přes tracing.
- [x] `README.md` (česky): co program je, jak ho přeložit a spustit.
- [x] Nastavení `cargo fmt`, `clippy`, `test`.

### Fáze 1 – signály a spektrum
- [x] Vlastní typ komplexního čísla.
- [x] Generátor: součet několika složek (sinus, obdélník, pila, trojúhelník),
      u každé frekvence, amplituda a fáze; volitelně bílý šum a stejnosměrná složka.
- [x] Pomalá DFT podle definice a rychlá FFT (radix-2), zpětná FFT.
- [x] Graf časového průběhu.
- [x] Graf spektra: amplituda (lineárně i v dB) a fáze; osa ve frekvenci i v binech.
- [x] Volba vzorkovací frekvence a délky FFT.
- [x] Testy: FFT = DFT, zpětná FFT vrátí signál, špička sinusovky ve správném binu.

### Fáze 2 – okna a prosakování
- [x] Okna: obdélníkové, Hann, Hamming, Blackman.
- [x] Zobrazení tvaru okna a jeho spektra (hlavní lalok, postranní laloky).
- [x] Ukázka prosakování: frekvence přesně v binu a mezi biny, s oknem a bez.
- [x] Doplnění nulami (zero-padding) a jeho vliv na vzhled spektra.

### Fáze 3 – vzorkování a aliasing
- [x] „Spojitý“ signál (hustě vzorkovaný) a přes něj vzorky při zvolené
      vzorkovací frekvenci.
- [x] Vyznačení Nyquistovy frekvence; alias, který ze vzorků vyjde.
- [x] Rekonstrukce signálu ze vzorků (sinc interpolace).
- [x] Spektrum před a po podvzorkování.

### Fáze 4 – filtry
- [x] FIR: návrh metodou okna (windowed-sinc) – dolní, horní a pásmová propust;
      volba mezní frekvence, délky filtru a okna.
- [x] IIR: bikvadratický filtr (biquad) – dolní, horní a pásmová propust;
      volba mezní frekvence a Q.
- [x] Zobrazení koeficientů / impulzní odezvy a frekvenční odezvy (amplituda, fáze).
- [x] Signál a jeho spektrum před a po filtraci.
- [x] Konvoluce jako samostatná, okomentovaná funkce.

### Fáze 5 – dokumentace
- [x] `docs/` – ke každé záložce krátké české vysvětlení, co zkoušet a čeho si všímat.
- [x] Projít komentáře v kódu, doplnit odkazy na vzorce.

### Fáze 6 – pidi učebnice
Série krátkých lekcí v `docs/ucebnice/` pro úplné začátečníky. Každá lekce
má cíl, základy, postup v programu, pokusy, častá nedorozumění, shrnutí,
otázky a cvičení s řešením a odkaz na kód. Obrázky jsou snímky programu
v `docs/ucebnice/img/`; čísla v textu jsou ověřená výpočtem nebo programem.
Pro snímky se mění výchozí hodnoty jen dočasně, tyto změny se necommitují.

- [x] `docs/ucebnice/README.md` s obsahem, odkazy z `README.md` a `docs/README.md`.
- [x] 1. Signál a vzorek
- [x] 2. Sinusovka
- [x] 3. Skládání signálů a myšlenka spektra
- [x] 4. DFT jako měření shody
- [x] 5. DFT: komplexní čísla a biny
- [x] 6. FFT a proč je rychlá
- [x] 7. Decibely a fáze ve spektru
- [x] 8. Prosakování
- [ ] 9. Okna
- [ ] 10. Doplnění nulami a rozlišení
- [ ] 11. Vzorkování a aliasing
- [ ] 12. Rekonstrukce ze vzorků
- [ ] 13. Konvoluce a FIR filtry
- [ ] 14. IIR filtr (biquad)
- [ ] 15. Shrnutí

## Možná později (mimo první verzi)

- Spektrogram (STFT).
- Krokování FFT po jednotlivých fázích (motýlky).
- Zvuk: přehrávání, WAV, mikrofon (vyžádá povolení dalších crates).
- Zobrazení pólů a nul filtru.

## Otevřené otázky

- Zatím žádné.
