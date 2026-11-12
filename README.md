# FFT a DSP – ukázky

Interaktivní desktopový program v Rustu (egui), na kterém si lze vyzkoušet
FFT a digitální zpracování signálu (DSP). Je to učební pomůcka: přednost má
srozumitelnost před výkonem.

Stav: hotové jsou všechny čtyři záložky i dokumentace. Plán je
v [PLAN.md](PLAN.md), pravidla pro práci na projektu v [AGENTS.md](AGENTS.md).

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

## Dokumentace

Ke každé záložce je česky vysvětlena teorie, co zkoušet a čeho si všímat,
včetně otázek k zamyšlení: viz [docs/README.md](docs/README.md).

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
