# FFT a DSP – ukázky

Interaktivní desktopový program v Zigu (grafické rozhraní DVUI), na kterém si
lze vyzkoušet FFT a digitální zpracování signálu (DSP). Je to učební pomůcka:
přednost má srozumitelnost před výkonem.

Stav: hotové jsou všechny čtyři záložky i dokumentace. Plán je
v [PLAN.md](PLAN.md), pravidla pro práci na projektu v [AGENTS.md](AGENTS.md).

Program původně vznikl v Rustu (egui). Tato verze je v adresáři
[last-rust-version/](last-rust-version/) a v gitu pod tagem
`last-rust-version`. Zkušenosti z přepisu do Zigu jsou
v [PREPIS-DO-ZIGU-Z-RUSTU.md](PREPIS-DO-ZIGU-Z-RUSTU.md).

## Záložky

- **Signály a spektrum** – skládání signálů, časový průběh a FFT spektrum.
- **Okna a prosakování** – okénkové funkce a jejich vliv na spektrum.
- **Vzorkování a aliasing** – vzorkovací frekvence, Nyquistova mez, aliasy.
- **Filtry** – FIR a IIR filtry, frekvenční odezva, signál před a po filtraci.

## Překlad a spuštění

Je potřeba Zig 0.17.1 a v systému musí být nainstalovaná knihovna SDL3.
Program se proti ní linkuje dynamicky. Ostatní závislosti (DVUI) stáhne
Zig sám.

```
zig build run -Doptimize=ReleaseSafe
```

Přeložený program je pak v `zig-out/bin/fft-dsp-demos`.

## Dokumentace

Ke každé záložce je česky vysvětlena teorie, co zkoušet a čeho si všímat,
včetně otázek k zamyšlení: viz [docs/README.md](docs/README.md).

Pro úplné začátečníky je tu [pidi učebnice FFT a DSP](docs/ucebnice/README.md):
série krátkých lekcí od pojmu vzorek až po filtry, s pokusy v programu
a cvičeními s řešením.

## Logování

Program loguje na standardní výstup, jedna zpráva na řádek, například:

```
info(app): tab selected tab=windows
```

Proměnné hodnoty jsou na konci zprávy ve tvaru `klic=hodnota`. Výchozí
úroveň je `info`. Podrobnější log zapne proměnná prostředí:

```
LOG_LEVEL=debug zig build run
```

## Kontrola kódu

```
zig fmt --check build.zig build.zig.zon src
zig build
zig build test
```
