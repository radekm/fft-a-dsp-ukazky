# PLAN.md – plán projektu

## Cíl

Interaktivní desktopový program, na kterém si lze „osahat“ FFT a digitální
zpracování signálu (DSP): pohnu posuvníkem a hned vidím, co to udělá se
signálem a jeho spektrem.

Program je učební pomůcka. Přednost má srozumitelnost před výkonem a úplností.

Program vznikl v Rustu (egui), fáze 0–6. Teď se přepisuje do Zigu (DVUI),
fáze 7. Rust verze je v `last-rust-version/` a slouží jako předloha.

## Rozhodnutí

- FFT i ostatní algoritmy jsou vlastní implementace s českými komentáři.
- Jen syntetické signály generované v programu (bez mikrofonu, přehrávání a WAV).
- Povolené závislosti: viz `AGENTS.md`. Grafy kreslí vlastní widget.
- Texty v uživatelském rozhraní jsou česky. Písmo je Inter, vložené do programu.
- Logování přes `std.log` na standardní výstup, hodnoty ve tvaru `klic=hodnota`.
- Délka FFT je mocnina dvou (radix-2); kratší signál se doplní nulami.
- SDL3 je systémová knihovna, linkuje se dynamicky.
- Zkušenosti z přepisu se zapisují do `PREPIS-DO-ZIGU-Z-RUSTU.md`.

## Struktura (verze v Zigu)

```
build.zig, build.zig.zon
src/
  main.zig         spuštění DVUI aplikace, logování, motiv a písmo
  app.zig          stav aplikace, přepínání záložek
  fonts/           písmo Inter a jeho licence
  dsp/             čisté výpočty, bez DVUI
    complex.zig    komplexní číslo
    signal.zig     generátory signálů
    fft.zig        DFT (pomalá) a FFT (radix-2), zpětná FFT
    spectrum.zig   amplituda, decibely a fáze z výsledku FFT
    window.zig     okénkové funkce
    filter.zig     FIR a IIR filtry, frekvenční odezva
    sampling.zig   převzorkování, rekonstrukce
  ui/              jedna záložka = jeden soubor
    plot.zig       vlastní widget grafu
    common.zig     věci společné pro více záložek
    spectrum.zig
    windows.zig
    sampling.zig
    filters.zig
docs/              česká vysvětlení k jednotlivým tématům
  ucebnice/        pidi učebnice: krátké lekce pro začátečníky
last-rust-version/ původní verze v Rustu
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

- [x] Popisek se souřadnicemi při najetí myší do grafu (`hover_label`
      v `src/ui/common.rs`); učebnice na něj spoléhá.
- [x] `docs/ucebnice/README.md` s obsahem, odkazy z `README.md` a `docs/README.md`.
- [x] 1. Signál a vzorek
- [x] 2. Sinusovka
- [x] 3. Skládání signálů a myšlenka spektra
- [x] 4. DFT jako měření shody
- [x] 5. DFT: komplexní čísla a biny
- [x] 6. FFT a proč je rychlá
- [x] 7. Decibely a fáze ve spektru
- [x] 8. Prosakování
- [x] 9. Okna
- [x] 10. Doplnění nulami a rozlišení
- [x] 11. Vzorkování a aliasing
- [x] 12. Rekonstrukce ze vzorků
- [x] 13. Konvoluce a FIR filtry
- [x] 14. IIR filtr (biquad)
- [x] 15. Shrnutí

### Fáze 7 – přepis do Zigu (DVUI)
Rust verze je předloha: stejné záložky, ovládání, výchozí hodnoty a čísla.

- [x] Tag `last-rust-version`, přesun Rust verze do `last-rust-version/`,
      založení `PREPIS-DO-ZIGU-Z-RUSTU.md`.
- [x] Ověření prostředí: Zig 0.17.1, DVUI se systémovým SDL3, české znaky
      písmem Inter.
- [x] Kostra: `build.zig`, `build.zig.zon`, okno se záložkami, motiv
      s písmem Inter, logování, kontroly `zig fmt` a `zig build test`.
- [x] DSP: `complex`, `signal`, `fft`, `spectrum`, `window`, `filter`,
      `sampling` včetně všech testů z Rust verze.
- [x] Widget grafu: osy s popisky a mřížkou, křivky, body, svislé čáry,
      čárkovaný styl, legenda, výchozí rozsah os, přibližování a posun,
      propojené osy více grafů, popisek se souřadnicemi při najetí myší.
- [x] Záložka Signály a spektrum.
- [x] Záložka Okna a prosakování.
- [ ] Záložka Vzorkování a aliasing.
- [ ] Záložka Filtry.
- [ ] Porovnání s Rust verzí: stejná čísla a srovnatelné snímky všech záložek.
- [ ] Shrnutí v `PREPIS-DO-ZIGU-Z-RUSTU.md`.
- [ ] Na pokyn autora: aktualizace `README.md`, `docs/` a učebnice
      (odkazy na kód, nové snímky).

## Možná později (mimo první verzi)

- Spektrogram (STFT).
- Krokování FFT po jednotlivých fázích (motýlky).
- Zvuk: přehrávání, WAV, mikrofon (vyžádá povolení dalších crates).
- Zobrazení pólů a nul filtru.

## Otevřené otázky

- Zatím žádné.
