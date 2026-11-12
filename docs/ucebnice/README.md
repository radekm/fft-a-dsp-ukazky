# Pidi učebnice FFT a DSP

Série krátkých lekcí pro začátečníky. Vede od toho, co je vzorek, až
k číslicovým filtrům. Stačí středoškolská matematika (goniometrické funkce,
mocniny); komplexní čísla se vysvětlí v lekci, kde jsou poprvé potřeba.

Každá lekce se dá přečíst za 10 až 15 minut a má stejnou stavbu:

1. **Cíl lekce** – co po ní budeš umět.
2. **Základy** – nejdřív intuice a příklad, potom vzorec.
3. **V programu** – přesný postup v programu a co se v grafech objeví.
4. **Pokusy** – „změň X → uvidíš Y, protože Z“.
5. **Častá nedorozumění.**
6. **Shrnutí.**
7. **Otázky k zamyšlení** a **cvičení** s řešením (skrytá, rozbal kliknutím).
8. **Kam dál** – další lekce a místo v kódu.

Program spustíš příkazem `cargo run --release` (viz [README](../../README.md)).
Stručnější přehled teorie ke každé záložce je v [docs/](../README.md);
učebnice jde pomaleji a po menších krocích.

## Obsah

| #  | Lekce | Záložka programu |
|----|-------|------------------|
| 1  | [Signál a vzorek](01-signal-a-vzorek.md) | Vzorkování a aliasing |
| 2  | [Sinusovka](02-sinusovka.md) | Vzorkování a aliasing |
| 3  | [Skládání signálů a myšlenka spektra](03-skladani-a-spektrum.md) | Signály a spektrum |
| 4  | [DFT jako měření shody](04-dft-mereni-shody.md) | Signály a spektrum |
| 5  | DFT: komplexní čísla a biny | Signály a spektrum |
| 6  | FFT a proč je rychlá | Signály a spektrum |
| 7  | Decibely a fáze ve spektru | Signály a spektrum |
| 8  | Prosakování | Okna a prosakování |
| 9  | Okna | Okna a prosakování |
| 10 | Doplnění nulami a rozlišení | Okna a prosakování |
| 11 | Vzorkování a aliasing | Vzorkování a aliasing |
| 12 | Rekonstrukce ze vzorků | Vzorkování a aliasing |
| 13 | Konvoluce a FIR filtry | Filtry |
| 14 | IIR filtr (biquad) | Filtry |
| 15 | Shrnutí | – |

Lekce bez odkazu se připravují.

## Jak ovládat grafy

- tažením myši se graf posouvá,
- kolečkem myši s klávesou Ctrl se zvětšuje a zmenšuje,
- dvojklik vrátí výchozí zobrazení,
- najetí myší na graf ukáže souřadnice,
- přesnou hodnotu posuvníku zadáš kliknutím na číslo vedle něj, napsáním
  hodnoty a klávesou Enter. Program používá desetinnou tečku (`0.50`),
  text lekcí desetinnou čárku (0,5).

Obrázky v lekcích jsou snímky programu; barvy a rozložení odpovídají
tomu, co uvidíš na obrazovce.
