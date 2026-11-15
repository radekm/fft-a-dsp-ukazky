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

Úplným začátečníkům doporučujeme začít [pidi učebnicí](ucebnice/README.md):
jde pomaleji, po menších krocích a ke každé lekci má cvičení s řešením.

## Společné ovládání grafů

- tažením myši se graf posouvá, kolečkem myši také (se Shiftem vodorovně),
- kolečkem myši s klávesou Ctrl se zvětšuje a zmenšuje,
- dvojklik vrátí výchozí zobrazení,
- najetí myší do grafu ukáže popisek se souřadnicemi; blízko bodu křivky
  se popisek k bodu přichytí a ukáže název křivky a přesné hodnoty bodu.

## Kde je co v kódu

| Téma                     | Výpočty                | Záložka                |
|--------------------------|------------------------|------------------------|
| komplexní čísla          | `src/dsp/complex.zig`  |                        |
| generátor signálů        | `src/dsp/signal.zig`   |                        |
| DFT, FFT, zpětná FFT     | `src/dsp/fft.zig`      | `src/ui/spectrum.zig`  |
| amplituda, dB, fáze      | `src/dsp/spectrum.zig` | `src/ui/spectrum.zig`  |
| okna, doplnění nulami    | `src/dsp/window.zig`   | `src/ui/windows.zig`   |
| vzorkování, sinc         | `src/dsp/sampling.zig` | `src/ui/sampling.zig`  |
| konvoluce, FIR, IIR      | `src/dsp/filter.zig`   | `src/ui/filters.zig`   |

Grafy kreslí vlastní widget v `src/ui/plot.zig`, společné ovládací prvky
jsou v `src/ui/common.zig`.

Výpočty v `src/dsp/` nezávisí na grafickém rozhraní a mají jednotkové testy
(`zig build test`), které ověřují i čísla uvedená v těchto textech.
