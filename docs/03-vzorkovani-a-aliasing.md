# Vzorkování a aliasing

## Vzorkovací věta

Spojitý signál, který neobsahuje frekvence od `fs/2` výš, lze ze vzorků
odebraných s frekvencí `fs` **přesně** obnovit. Hranici `fs/2` se říká
**Nyquistova frekvence**.

## Aliasing

Sinusovky s frekvencemi `f` a `f + k·fs` (pro celé `k`) mají ve vzorcích
úplně stejné hodnoty: mezi dvěma vzorky se liší o celý počet otáček.
A sinusovka s frekvencí `−f` vypadá stejně jako `f`, jen s opačnou fází.
Proto se po navzorkování každá frekvence objeví na

```text
f_alias = | f − fs · round(f / fs) |
```

tedy vždy mezi 0 a `fs/2`. Frekvence se „zrcadlí“ kolem násobků `fs/2`.
Příklady pro `fs = 40 Hz`:

| skutečná frekvence | po navzorkování |
|--------------------|-----------------|
| 5 Hz               | 5 Hz            |
| 20 Hz              | 20 Hz           |
| 30 Hz              | 10 Hz           |
| 33 Hz              | 7 Hz            |
| 40 Hz              | 0 Hz            |
| 70 Hz              | 10 Hz           |

Po navzorkování už **nelze poznat**, která z těchto frekvencí to byla.
Proto se před převodníkem zařazuje analogová dolní propust (antialiasingový
filtr), která frekvence nad `fs/2` odstraní dřív, než se navzorkují.

Známý příklad z běžného života: kola vozu ve filmu se zdánlivě točí pomalu
nebo pozpátku, protože kamera „vzorkuje“ 24 snímky za sekundu.

## Rekonstrukce ze vzorků

Spojitý signál se ze vzorků obnoví tak, že se na každý vzorek položí funkce
`sinc` a vše se sečte (Whittakerova–Shannonova interpolace):

```text
x(t) = Σ x[n] · sinc(fs · (t − tₙ)),      sinc(x) = sin(πx) / (πx)
```

Funkce `sinc` je v nule rovna 1 a ve všech ostatních celých číslech 0,
proto obnovený signál prochází přesně vzorky. Mezi nimi dopočítá jedinou
křivku, která neobsahuje frekvence nad `fs/2`.

Pokud původní signál frekvence nad `fs/2` obsahoval, rekonstrukce místo nich
ukáže jejich aliasy – je to jiný signál, který má ve vzorcích stejné hodnoty.

Přesná rekonstrukce potřebuje nekonečně mnoho vzorků. Program proto počítá
i se vzorky jednu sekundu před a za zobrazeným úsekem, aby byla obnova
přesná i u jeho okrajů.

V kódu: `src/dsp/sampling.rs`.

## Jak záložka počítá spektra

- **Spektrum spojitého signálu** nahrazuje velmi husté vzorkování (2048 Hz).
- **Spektrum po navzorkování** se počítá z vzorků v zobrazeném úseku (1 s).
  Jejich počet je `fs` a obecně to není mocnina dvou, proto se zde používá
  pomalá DFT.
- Úsek trvá přesně 1 s a frekvence složek se nastavují v celých hertzích,
  takže všechny složky mají v úseku celý počet period a nevzniká prosakování.

## Co zkoušet

Výchozí stav: sinusovka 5 Hz vzorkovaná 40 Hz.

1. **Vše v pořádku.** Rekonstrukce (modře) přesně kopíruje spojitý signál
   (šedě), ve spektru jsou obě čáry na 5 Hz.
2. **Aliasing.** Pomalu zvyšuj frekvenci nad 20 Hz. Rekonstrukce ukáže nižší
   sinusovku a čára „po navzorkování“ se odráží od Nyquistovy frekvence
   (červená čárkovaná čára) zpět dolů. Při 33 Hz se signál jeví jako 7 Hz.
3. **Přesně na Nyquistově frekvenci.** Nastav 20 Hz při `fs = 40 Hz`: všechny
   vzorky padnou do průchodů nulou a signál „zmizí“. Změň fázi na 90°
   a vzorky budou střídavě +1 a −1. Na hranici `fs/2` záleží na fázi, proto
   věta vyžaduje frekvence **pod** `fs/2`.
4. **Frekvence rovná fs.** Při 40 Hz padne každý vzorek na stejné místo
   periody – sinusovka se změní na konstantu (alias 0 Hz).
5. **Snižuj fs** při pevné frekvenci a sleduj, kdy rekonstrukce přestane
   odpovídat originálu.
6. **Obdélník.** Přidej obdélník 3 Hz. Jeho liché harmonické (9, 15, 21,
   27, 33… Hz) sahají nad 20 Hz a po navzorkování se složí zpět do pásma
   0 až 20 Hz. Rekonstrukce už není obdélník. Proto se ostré hrany před
   vzorkováním zaoblují filtrem.

## Otázky k zamyšlení

1. Zvuk na CD se vzorkuje 44 100 Hz. Proč zrovna tolik?
2. Na jaké frekvenci se při `fs = 1000 Hz` objeví signál 1300 Hz?
3. Proč nestačí vzorkovat přesně dvojnásobkem nejvyšší frekvence?

<details>
<summary>Odpovědi</summary>

1. Lidské ucho slyší zhruba do 20 kHz. Nyquistova frekvence 22,05 kHz
   nechává rezervu pro antialiasingový filtr, který nemůže mít nekonečně
   strmý přechod.
2. `|1300 − 1000·round(1,3)| = |1300 − 1000| = 300 Hz`.
3. Na samotné hranici `fs/2` záleží na fázi (může vyjít i nula, viz pokus 3)
   a skutečné filtry potřebují přechodové pásmo.

</details>
