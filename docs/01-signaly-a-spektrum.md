# Signály a spektrum

## O co jde

Každý signál lze složit ze sinusovek různých frekvencí, amplitud a fází.
**Spektrum** říká, které sinusovky to jsou: pro každou frekvenci jejich
amplitudu a fázi. Časový průběh a spektrum jsou dva pohledy na tentýž signál.

## Vzorkovaný signál

Počítač nepracuje se spojitým signálem, ale s **vzorky** odebranými
v pravidelných okamžicích. Vzorkovací frekvence `fs` udává, kolik vzorků
připadá na sekundu. Vzorek číslo `n` patří času `n / fs`.

## Diskrétní Fourierova transformace (DFT)

Z `N` vzorků `x[0] … x[N−1]` spočítá `N` komplexních čísel:

```text
X[k] = Σ x[n] · e^(−j·2π·k·n/N)      pro n = 0 … N−1
```

Člen `e^(−j·2π·k·n/N)` je otáčející se ručička, která za `N` vzorků
oběhne `k`-krát dokola. Součet ukazuje, jak moc se signál s touto otáčkou
„shoduje“. Číslu `k` se říká **bin** a odpovídá mu frekvence

```text
f = k · fs / N
```

Biny jsou tedy od sebe vzdálené `fs/N` (rozlišení spektra). Čím delší
záznam (`N/fs` sekund), tím jemnější rozlišení.

Velikost `|X[k]|` souvisí s amplitudou, úhel s fází. Program z `X[k]`
počítá:

- **amplitudu** `2·|X[k]| / N` (dvojka proto, že reálná sinusovka se
  rozdělí mezi bin `k` a jeho zrcadlo `N−k`; nultý bin a bin `N/2` zrcadlo
  nemají),
- **amplitudu v decibelech** `20·log₁₀(amplituda)` – 0 dB je amplituda 1,
  −20 dB je 0,1, −40 dB je 0,01,
- **fázi** jako úhel `X[k]` ve stupních. Je vztažená ke kosinu: kosinus má
  fázi 0°, sinus −90°.

Program ukazuje jen biny 0 až `N/2` (jednostranné spektrum). Horní polovina
spektra reálného signálu je zrcadlem dolní a nenese nic nového.

## Rychlá Fourierova transformace (FFT)

DFT podle definice potřebuje `N²` násobení. FFT (algoritmus Cooley–Tukey)
dává přesně stejný výsledek za zhruba `N·log₂N` operací. Myšlenka:

1. DFT délky `N` lze složit ze dvou DFT délky `N/2` – jedné ze sudých
   a jedné z lichých vzorků.
2. Opakovaným půlením se dojde až k délce 1, kde je DFT vzorku on sám.
3. Skládání dvou polovin obstarává „motýlek“:
   `horní = a + w·b`, `dolní = a − w·b`, kde `w` je otočení
   `e^(−j·2π·k/délka bloku)`.

Proto musí být `N` mocnina dvou. Vzorky se na začátku přerovnají podle
obrácených bitů indexu (pro `N = 8`: 0, 4, 2, 6, 1, 5, 3, 7), což je přesně
pořadí, které opakované dělení na sudé a liché vytvoří.

**Zpětná FFT** vrátí ze spektra původní vzorky. Liší se jen znaménkem
v exponentu a dělením `N`. Program ukazuje, s jakou chybou se signál po cestě
tam a zpět vrátí – je na úrovni zaokrouhlovacích chyb (kolem 10⁻¹⁴).

V kódu: `src/dsp/fft.zig`, převod na amplitudu a fázi v `src/dsp/spectrum.zig`.

## Co zkoušet

Výchozí nastavení: `fs = 1024 Hz`, `N = 1024`, sinusovky 50 Hz (amplituda 1)
a 120 Hz (amplituda 0,5).

1. **Ostré čáry.** Rozestup binů je `1024/1024 = 1 Hz`, obě frekvence padnou
   přesně do binu. Ve spektru jsou dvě čáry s výškou přesně 1 a 0,5
   a fází −90°.
2. **Fáze.** Nastav u složky fázi 90°: ze sinu se stane kosinus a fáze ve
   spektru bude 0°. Časový průběh se posune, amplitudové spektrum se nezmění.
3. **Stejnosměrná složka** se objeví v binu 0 (frekvence 0 Hz).
4. **Tvar vlny.** Přepni sinus na obdélník: objeví se liché harmonické
   (150, 250, 350 Hz…) s amplitudami `4/π`, `4/(3π)`, `4/(5π)`… ≈ 1,27;
   0,42; 0,25. Pila má všechny harmonické (`2/(πk)`), trojúhelník jen liché
   a velmi rychle slábnoucí (`8/(π²k²)`). Ostré hrany = hodně vysokých
   frekvencí.
5. **Drobné čáry navíc u obdélníku.** Harmonické nad 512 Hz (Nyquistova
   frekvence) se „přeloží“ zpět do spektra. To je aliasing – viz třetí
   záložka.
6. **Necelá frekvence.** Nastav 50,5 Hz: čára se rozlije do okolních binů.
   To je prosakování – viz druhá záložka.
7. **Šum.** Přidej šum a přepni amplitudu na dB. Šum je rozprostřený po
   celém spektru, sinusovky z něj vyčnívají. Delší záznam (`N`) šumovou
   hladinu na bin sníží, čáry zůstanou stejně vysoké.
8. **Rozlišení.** Dej dvě sinusovky blízko sebe (50 a 52 Hz) a zkracuj `N`.
   Jakmile je rozestup binů větší než rozdíl frekvencí, čáry splynou.
9. **Rychlost.** Přepni výpočet na DFT a nastav `N = 4096`. Teoretický poměr
   rychlostí je `N / log₂N = 4096/12 ≈ 340`. Spektrum je přitom stejné.

## Otázky k zamyšlení

1. Jaké rozlišení má spektrum při `fs = 48 000 Hz` a `N = 4096`?
2. Proč má sinus fázi −90° a ne 0°?
3. Proč se amplituda násobí dvěma, ale u binu 0 ne?

<details>
<summary>Odpovědi</summary>

1. `48 000 / 4096 ≈ 11,7 Hz`; záznam trvá asi 85 ms.
2. Fáze se měří vůči kosinu a `sin(x) = cos(x − 90°)`.
3. Reálná sinusovka je součet dvou komplexních ručiček otáčejících se
   opačně (kladná a záporná frekvence), každá nese polovinu amplitudy.
   Stejnosměrná složka se neotáčí, takže protějšek nemá.

</details>
