# Okna a prosakování

## Prosakování (leakage)

DFT se chová, jako by se záznam donekonečna opakoval. Když signál nemá
v záznamu celý počet period, na hranici opakování vznikne skok. Skok obsahuje
spoustu frekvencí, takže se energie sinusovky „rozlije“ do celého spektra.
Místo jedné ostré čáry je vidět široká hora s pomalu klesajícími boky.

Prosakování nastane, kdykoli frekvence neleží přesně na binu – v praxi skoro
vždy.

## Okno

Okno je funkce, kterou se záznam před FFT vynásobí. Na krajích je blízko
nule, uprostřed kolem jedné. Tím záznam na okrajích plynule ztlumí a skok
zmizí. Všechna okna v programu mají tvar

```text
w[n] = a0 − a1·cos(2πn/N) + a2·cos(4πn/N)
```

| Okno         | a0   | a1   | a2   |
|--------------|------|------|------|
| obdélníkové  | 1    | 0    | 0    |
| Hann         | 0,5  | 0,5  | 0    |
| Hamming      | 0,54 | 0,46 | 0    |
| Blackman     | 0,42 | 0,5  | 0,08 |

Pro spektrální analýzu se používá **periodické** okno (dělí se `N`, ne
`N − 1`). Pro návrh filtrů (čtvrtá záložka) **symetrické**.

## Spektrum okna

Vynásobení oknem v čase znamená, že se každá čára ve spektru nahradí tvarem
spektra okna. Ten má:

- **hlavní lalok** – šířka určuje, jak rozmazaná je čára a jak blízké
  frekvence ještě rozlišíme,
- **postranní laloky** – jejich výška určuje, jak moc silná čára zakryje
  slabé signály jinde ve spektru.

Užší hlavní lalok a nižší postranní laloky jdou proti sobě; každé okno je
jiný kompromis. Hodnoty pro dlouhé okno (N ≥ 256) a frekvenci daleko
od 0 a `fs/2`:

| Okno        | 1. nula   | nejvyšší postranní lalok | koherentní zisk | ztráta mezi biny |
|-------------|-----------|--------------------------|-----------------|------------------|
| obdélníkové | ±1 bin    | −13,3 dB                 | 1,00            | −3,92 dB         |
| Hann        | ±2 biny   | −31,5 dB                 | 0,50            | −1,42 dB         |
| Hamming     | ±2 biny   | −42,7 dB                 | 0,54            | −1,75 dB         |
| Blackman    | ±3 biny   | −58,1 dB                 | 0,42            | −1,10 dB         |

Při krátkém okně se čísla trochu liší. Ve výchozím nastavení záložky
(N = 64) ukáže panel u Hammingova okna nejvyšší postranní lalok −42,4 dB
(při N = 128 −42,6 dB) a obdélníkové okno ztrátu mezi biny −3,79 dB místo
−3,92 dB: u krátkého záznamu se k čáře přimíchá i její zrcadlo ze
záporných frekvencí.

- **Koherentní zisk** je průměrná hodnota okna. O tolik okno zeslabí
  amplitudu, proto ho program při výpočtu amplitudy vykompenzuje (dělí
  součtem koeficientů okna místo `N`).
- **Ztráta mezi biny** (scalloping loss) je, o kolik nižší je nejvyšší čára,
  když frekvence padne přesně doprostřed mezi dva biny.
- Postranní laloky obdélníkového a Hammingova okna klesají pomalu (6 dB na
  oktávu), Hannova a Blackmanova rychle (18 dB na oktávu). Hamming má proto
  nejnižší první postranní lalok, ale daleko od čáry je Hann lepší.

## Doplnění nulami (zero-padding)

Za signál se přidají nuly a spočítá se delší FFT. Body spektra zhoustnou –
je vidět tvar čáry i to, co leží mezi původními biny. **Rozlišení se ale
nezlepší:** šířka hlavního laloku závisí na délce skutečného signálu, ne na
délce FFT. Doplnění nulami spektrum jen hustěji „navzorkuje“.

V kódu: `src/dsp/window.zig`.

## Co zkoušet

Frekvence jsou v této záložce v binech (1 bin = `fs/N`). Výchozí stav:
`N = 64`, okno Hann, hlavní sinusovka v binu 10, slabá sinusovka −60 dB
v binu 20.

1. **Bez prosakování.** Vyber obdélníkové okno. Hlavní sinusovka je přesně
   v binu: jediná čára 0 dB, slabá sinusovka je dobře vidět.
2. **Prosakování.** Klikni na „Mezi biny“ (10,5). Bez okna se hlavní čára
   rozlije a ve vzdálenosti 9,5 binu je prosakování kolem −30 dB – slabá
   sinusovka −60 dB pod ním úplně zmizí.
3. **Okno pomůže.** Přepínej na Hann, Hamming a Blackman a porovnávej
   s šedou křivkou bez okna. Prosakování v binu 20 klesne s Hannem asi na
   −69 dB a s Blackmanem na −77 dB, takže slabá sinusovka je vidět.
   S Hammingem zůstane schovaná (prosakování kolem −48 dB): jeho postranní
   laloky jsou sice nízké, ale daleko od čáry klesají pomalu.
4. **Cena za okno.** Vrať frekvenci do binu („Přesně v binu“). Bez okna je
   čára jediný bod, s Hannem zabere tři biny, s Blackmanem pět. Blízké
   frekvence se hůř rozliší.
5. **Ztráta mezi biny.** Sleduj „Nejvyšší čáru spektra“ při frekvenci mezi
   biny a porovnej s tabulkou výše.
6. **Doplnění nulami.** Nastav ×8: mezi body přibydou další, je vidět skutečný
   tvar laloků, ale čára se nezúží. Porovnej s dolním grafem (spektrum okna).
7. **Rozlišení dvou čar.** Dej slabou sinusovku na úroveň 0 dB a blízko
   hlavní (např. 10 a 12 binů). S obdélníkovým oknem jsou to dvě čáry,
   s Blackmanem splynou v jeden kopec s vrcholem mezi nimi. Pak zvětši `N`
   a frekvence přepočítej, aby zůstaly stejně daleko v hertzích – co se
   stane?

## Otázky k zamyšlení

1. Kdy je nejlepší nepoužít žádné okno?
2. Měřím slabý signál vedle velmi silného. Které okno zvolím?
3. Pomůže doplnění nulami rozlišit dvě frekvence vzdálené půl binu?

<details>
<summary>Odpovědi</summary>

1. Když mají všechny složky v záznamu celý počet period (například při
   synchronním vzorkování periodického signálu) – pak k prosakování
   nedochází a obdélníkové okno má nejužší čáru.
2. Okno s nízkými postranními laloky, například Blackman.
3. Ne. Rozlišení určuje délka skutečného signálu. Pomůže jen delší záznam.

</details>
