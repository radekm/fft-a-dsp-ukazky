# Filtry

## Lineární filtr

Číslicový filtr počítá každý výstupní vzorek z několika posledních vstupních
(a případně výstupních) vzorků:

```text
y[n] = b0·x[n] + b1·x[n−1] + … − a1·y[n−1] − a2·y[n−2] − …
```

Sinusovka projde lineárním filtrem jako sinusovka **stejné frekvence**, jen
se změní její amplituda a fáze. Jak moc, popisuje **frekvenční
charakteristika**:

```text
H(ω) = (b0 + b1·e^(−jω) + b2·e^(−2jω) + …) / (1 + a1·e^(−jω) + a2·e^(−2jω) + …)
```

kde `ω = 2π·f/fs`. Velikost `|H|` je zesílení, úhel je fázový posun.

**Impulzní odezva** je výstup filtru, když na vstup přijde jediný vzorek
s hodnotou 1 a pak samé nuly. Filtr je jí úplně popsán – její FFT je právě
frekvenční charakteristika.

Druhy filtrů v programu:

- **dolní propust** – propouští frekvence pod mezní frekvencí,
- **horní propust** – propouští frekvence nad mezní frekvencí,
- **pásmová propust** – propouští jen pásmo kolem zvolené frekvence.

## Konvoluce a FIR filtr

FIR filtr (s konečnou impulzní odezvou) používá jen vstupní vzorky.
Jeho koeficienty `h[k]` jsou přímo jeho impulzní odezva a filtrování je
**konvoluce**:

```text
y[n] = Σ h[k] · x[n − k]      pro k = 0 … M−1
```

Každý výstupní vzorek je vážený průměr posledních `M` vstupních vzorků.
Nejjednodušší příklad je klouzavý průměr (všechny váhy `1/M`).

**Konvoluce v čase odpovídá násobení ve spektru**: spektrum výstupu je
spektrum vstupu krát frekvenční charakteristika filtru. V decibelech se
násobení mění na sčítání – proto program do spektra kreslí i zesílení filtru.

### Návrh metodou okna (windowed-sinc)

1. Ideální dolní propust s mezní frekvencí `fc` má impulzní odezvu
   `h[n] = 2·fc/fs · sinc(2·fc/fs · n)`. Je ale nekonečně dlouhá.
2. Usekneme ji na `M` koeficientů kolem středu. Useknutí způsobí zvlnění
   charakteristiky – je to tentýž jev jako prosakování ve spektru.
3. Proto ji vynásobíme (symetrickým) oknem.
4. Koeficienty vydělíme jejich součtem, aby zesílení na 0 Hz bylo přesně 1.

Horní propust vznikne jako „vše minus dolní propust“
(`δ[n − střed] − h_DP[n]`), pásmová jako rozdíl dvou dolních propustí.

Vlastnosti:

- Na mezní frekvenci má takový filtr zesílení 1/2 (−6 dB).
- Koeficienty jsou souměrné, takže filtr má **lineární fázi**: všechny
  frekvence zpozdí stejně, o `(M − 1)/2` vzorků. Tvar signálu se nezkreslí,
  jen posune.
- Okno určuje útlum v nepropustném pásmu, délka `M` šířku přechodu.
  Pro dolní propust 100 Hz, `M = 61`, `fs = 1000 Hz`:

| Okno        | nejvyšší zvlnění v nepropustném pásmu | první nula |
|-------------|---------------------------------------|------------|
| obdélníkové | −21 dB                                | 110 Hz     |
| Hann        | −44 dB                                | 128 Hz     |
| Hamming     | −52 dB                                | 129 Hz     |
| Blackman    | −75 dB                                | 150 Hz     |

Dvojnásobná délka zhruba zúží přechod na polovinu, útlum se nezmění.

## IIR filtr – biquad

IIR filtr (s nekonečnou impulzní odezvou) používá i předchozí výstupy.
Díky zpětné vazbě stačí málo koeficientů. Bikvadratický filtr (biquad) je
filtr druhého řádu s pěti koeficienty:

```text
y[n] = b0·x[n] + b1·x[n−1] + b2·x[n−2] − a1·y[n−1] − a2·y[n−2]
```

Program koeficienty počítá podle známé „kuchařky“ R. Bristow-Johnsona
(Audio EQ Cookbook) z frekvence `f0` a činitele jakosti `Q`.

- Na frekvenci `f0` má dolní i horní propust zesílení rovné `Q`.
  `Q = 0,707` dává nejplošší propustné pásmo (−3 dB na `f0`), větší `Q`
  převýšení. Pásmová propust má na `f0` zesílení 1, větší `Q` znamená užší
  pásmo.
- Fáze **není lineární**: různé frekvence se zpozdí různě, tvar signálu se
  zkreslí.
- Impulzní odezva teoreticky nikdy neskončí, jen doznívá. Čím větší `Q`,
  tím déle.
- Špatně zvolené koeficienty IIR filtru by mohly vést k nestabilitě (výstup
  roste nade všechny meze). Filtry z kuchařky jsou pro `Q > 0` a
  `0 < f0 < fs/2` vždy stabilní.

V kódu: `src/dsp/filter.zig`.

## Co zkoušet

Vzorkovací frekvence je pevně 1000 Hz. Výchozí signál: sinusovka 20 Hz,
sinusovka 200 Hz a šum. Výchozí filtr: FIR dolní propust 100 Hz,
`M = 61`, okno Hamming.

1. **Filtrace ve spektru.** Výstup (modře) je vstup (šedě) posunutý dolů
   o zesílení filtru (oranžová čárkovaná). Sinusovka 200 Hz i šum nad 100 Hz
   zmizí, v časovém grafu zůstane čistá sinusovka 20 Hz.
2. **Zpoždění.** Přibliž si začátek časového grafu: výstup je posunutý
   o 30 vzorků (30 ms) a prvních 60 ms trvá přechodový děj.
3. **Délka filtru.** Měň `k`. Delší filtr = strmější přechod, ale větší
   zpoždění. Krátký filtr (`k = 3`) skoro nefiltruje.
4. **Okno.** Přepni na obdélníkové: v nepropustném pásmu je zvlnění jen
   −21 dB. Blackman dá −75 dB, ale pozvolnější přechod.
5. **Fáze FIR.** Přepni charakteristiku na fázi: v propustném pásmu je
   pravidelná „pila“ – fáze klesá lineárně s frekvencí a jen se přetáčí
   přes ±180°.
6. **IIR.** Přepni na IIR: přechod je mnohem pozvolnější (filtr druhého
   řádu klesá jen o 12 dB na oktávu), ale stačí pět koeficientů a zpoždění
   je malé. Fáze lineární není.
7. **Q.** Zvyšuj `Q` u IIR dolní propusti: u mezní frekvence vznikne
   převýšení (při `Q = 8` asi +18 dB) a impulzní odezva dlouho kmitá.
8. **Pásmová propust.** Přidej složky 50, 100 a 300 Hz a pásmovou propustí
   vyber jen jednu z nich.
9. **Horní propust** odstraní pomalou složku 20 Hz a nechá jen 200 Hz a šum.

## Otázky k zamyšlení

1. Proč je výstup FIR filtru zpožděný a o kolik?
2. Kdy bych zvolil IIR a kdy FIR?
3. Proč se na začátku výstupu objevuje přechodový děj?

<details>
<summary>Odpovědi</summary>

1. Souměrná impulzní odezva má těžiště uprostřed, tedy `(M − 1)/2` vzorků
   od začátku. Výstup je vážený průměr vzorků kolem tohoto místa.
2. IIR, když záleží na výpočetní náročnosti a malém zpoždění a nevadí
   nelineární fáze (např. ekvalizéry v audiu). FIR, když je potřeba lineární
   fáze, zaručená stabilita nebo velmi přesně tvarovaná charakteristika.
3. Filtr považuje vzorky před začátkem signálu za nuly. Dokud nemá v paměti
   celou délku skutečného signálu, počítá s chybějícími hodnotami.

</details>
