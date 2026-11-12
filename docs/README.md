# Dokumentace – FFT a DSP

Ke každé záložce programu je jeden text. Každý obsahuje stručnou teorii,
návod, co v záložce zkoušet, čeho si všímat, a na konci otázky k zamyšlení
s odpověďmi.

Doporučené pořadí (každé téma staví na předchozím):

1. [Signály a spektrum](01-signaly-a-spektrum.md) – co je spektrum, DFT a FFT.
2. [Okna a prosakování](02-okna-a-prosakovani.md) – proč spektrum není vždy
   ostré a jak to napravit.
3. [Vzorkování a aliasing](03-vzorkovani-a-aliasing.md) – co se ztratí, když
   ze spojitého signálu uděláme vzorky.
4. [Filtry](04-filtry.md) – jak ze signálu vybrat jen některé frekvence.

## Společné ovládání grafů

- tažením myši se graf posouvá,
- kolečkem myši s klávesou Ctrl se zvětšuje a zmenšuje,
- dvojklik vrátí výchozí zobrazení,
- najetí myší na graf ukáže souřadnice.

## Kde je co v kódu

| Téma                     | Výpočty               | Záložka               |
|--------------------------|-----------------------|-----------------------|
| komplexní čísla          | `src/dsp/complex.rs`  |                       |
| generátor signálů        | `src/dsp/signal.rs`   |                       |
| DFT, FFT, zpětná FFT     | `src/dsp/fft.rs`      | `src/ui/spectrum.rs`  |
| amplituda, dB, fáze      | `src/dsp/spectrum.rs` | `src/ui/spectrum.rs`  |
| okna, doplnění nulami    | `src/dsp/window.rs`   | `src/ui/windows.rs`   |
| vzorkování, sinc         | `src/dsp/sampling.rs` | `src/ui/sampling.rs`  |
| konvoluce, FIR, IIR      | `src/dsp/filter.rs`   | `src/ui/filters.rs`   |

Výpočty v `src/dsp/` nezávisí na grafickém rozhraní a mají jednotkové testy
(`cargo test`), které ověřují i čísla uvedená v těchto textech.
