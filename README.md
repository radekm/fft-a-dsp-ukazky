# FFT a DSP – ukázky

Interaktivní desktopový program v Rustu (egui), na kterém si lze vyzkoušet
FFT a digitální zpracování signálu (DSP). Je to učební pomůcka: přednost má
srozumitelnost před výkonem.

Stav: hotové jsou všechny čtyři záložky. Zbývá česká dokumentace k jednotlivým
tématům (fáze 5 v [PLAN.md](PLAN.md)). Pravidla pro práci na projektu jsou
v [AGENTS.md](AGENTS.md).

## Záložky

- **Signály a spektrum** – skládání signálů, časový průběh a FFT spektrum.
- **Okna a prosakování** – okénkové funkce a jejich vliv na spektrum.
- **Vzorkování a aliasing** – vzorkovací frekvence, Nyquistova mez, aliasy.
- **Filtry** – FIR a IIR filtry, frekvenční odezva, signál před a po filtraci.

## Překlad a spuštění

Je potřeba stabilní Rust 1.95 nebo novější.

```
cargo run --release
```

Na Linuxu program běží přes X11 (pod Waylandem přes XWayland) a potřebuje
ovladač s OpenGL.

## Co zkusit v záložce Signály a spektrum

- Výchozí nastavení má fs = 1024 Hz a N = 1024, takže biny jsou po 1 Hz a obě
  sinusovky (50 a 120 Hz) dají ve spektru dvě ostré čáry.
- Posuň frekvenci na necelé číslo (např. 50,5 Hz): čára se rozlije do okolních
  binů. To je prosakování, kterému se věnuje další záložka.
- Změň sinus na obdélník nebo pilu a sleduj vyšší harmonické.
- Přidej šum a přepni amplitudu na decibely.
- Přepni výpočet z FFT na DFT a porovnej dobu transformace při N = 4096.

## Co zkusit v záložce Okna a prosakování

Frekvence se zde zadávají v binech (1 bin = fs/N).

- Bez okna (obdélníkové) a s hlavní sinusovkou přesně v binu je ve spektru
  jediná ostrá čára a slabá sinusovka −60 dB je dobře vidět.
- Klikni na „Mezi biny“: bez okna se hlavní čára rozlije po celém spektru
  a slabou sinusovku zakryje. S oknem Hann nebo Blackman je zase vidět.
- Sleduj „Nejvyšší čáru spektra“: mezi biny ukáže bez okna asi −3,9 dB,
  s oknem Hann jen asi −1,4 dB.
- Porovnej okna v dolním grafu: užší hlavní lalok znamená lepší rozlišení
  blízkých frekvencí, nižší postranní laloky menší prosakování.
- Zapni doplnění nulami ×8: body spektra zhoustnou a je vidět skutečný tvar
  čáry, ale čára se nezúží.

## Co zkusit v záložce Vzorkování a aliasing

- Výchozí sinusovka 5 Hz vzorkovaná 40 Hz: rekonstrukce ze vzorků (modře)
  přesně kopíruje spojitý signál (šedě).
- Zvyšuj frekvenci nad 20 Hz (Nyquistova frekvence): rekonstrukce začne
  ukazovat jinou, nižší sinusovku – alias. Při 33 Hz se signál jeví jako 7 Hz.
- Nastav frekvenci přesně na fs/2 nebo na fs a sleduj, kam padnou vzorky.
- Snižuj fs a sleduj, kdy přestane rekonstrukce odpovídat originálu.
- Přidej obdélník 3 Hz: jeho vyšší harmonické sahají nad fs/2 a po
  navzorkování se složí zpět do pásma 0 až fs/2.

## Co zkusit v záložce Filtry

Vzorkovací frekvence je zde pevně 1000 Hz. Výchozí signál je sinusovka 20 Hz,
sinusovka 200 Hz a šum; výchozí filtr je FIR dolní propust 100 Hz.

- Sleduj spektrum: výstup (modře) je vstup (šedě) posunutý o zesílení filtru
  (žlutá čárkovaná čára). Sinusovka 200 Hz i šum nad mezí zmizí.
- Měň k (délku FIR filtru): delší filtr má strmější přechod, ale větší
  zpoždění – v časovém grafu je výstup posunutý doprava.
- Přepni okno na obdélníkové: v nepropustném pásmu se objeví vysoké zvlnění.
  Blackman potlačí nepropustné pásmo nejvíc.
- Přepni na IIR: stejná mezní frekvence s pouhými pěti koeficienty, ale
  pozvolnější přechod. Zvyš Q a sleduj převýšení u mezní frekvence a dlouho
  doznívající impulzní odezvu.
- Porovnej fázi: FIR má lineární fázi (pila se stálým sklonem v propustném
  pásmu), IIR ne.
- Pásmovou propustí vyber z několika složek jen jednu.

## Logování

Program loguje strukturovaně: každá událost má zprávu a pojmenovaná pole.
Čitelná podoba jde na standardní chybový výstup, JSON (jeden objekt na řádek)
do souboru `logs/fft-dsp-demos.RRRR-MM-DD.jsonl` v pracovním adresáři;
uchovává se posledních 7 dní.

Výchozí úroveň je `info`. Podrobnější log zapne proměnná prostředí:

```
LOG_LEVEL=debug cargo run --release
```

## Kontrola kódu

```
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```
