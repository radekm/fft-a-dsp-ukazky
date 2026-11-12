# FFT a DSP – ukázky

Interaktivní desktopový program v Rustu (egui), na kterém si lze vyzkoušet
FFT a digitální zpracování signálu (DSP). Je to učební pomůcka: přednost má
srozumitelnost před výkonem.

Stav: hotová je kostra aplikace (okno se čtyřmi záložkami). Jednotlivé ukázky
přibývají po fázích podle [PLAN.md](PLAN.md). Pravidla pro práci na projektu
jsou v [AGENTS.md](AGENTS.md).

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

## Kontrola kódu

```
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```
