# FFT a DSP – ukázky

Interaktivní desktopový program v Rustu (egui), na kterém si lze vyzkoušet
FFT a digitální zpracování signálu (DSP). Je to učební pomůcka: přednost má
srozumitelnost před výkonem.

Stav: hotová je záložka **Signály a spektrum**. Ostatní záložky jsou zatím
prázdné a přibývají po fázích podle [PLAN.md](PLAN.md). Pravidla pro práci na
projektu jsou v [AGENTS.md](AGENTS.md).

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
