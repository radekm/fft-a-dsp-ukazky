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

## Webová verze

Tentýž program jde přeložit do WebAssembly a spustit v prohlížeči
(webový backend DVUI, kreslí přes WebGL). SDL3 k tomu potřeba není.

```
zig build web -Doptimize=ReleaseSmall
```

Do `zig-out/web/` se nainstalují tři soubory: `index.html`, `web.js`
a `fft-dsp-demos.wasm` (v ReleaseSmall asi 2 MB). Stránku nejde otevřít
přímo ze souboru (`file://`), prohlížeč by `.wasm` nenačetl – soubory musí
servírovat HTTP server. Nejjednodušší je malý server, který přibaluje DVUI:

```
zig build serve-web -Doptimize=ReleaseSmall
```

a pak otevřít http://localhost:8080. Poslouží i jakýkoli jiný statický
server, např. `python3 -m http.server -d zig-out/web 8080`.

Rozdíly proti desktopu: log jde do konzole prohlížeče (vývojářské nástroje)
a proměnná `LOG_LEVEL` tu není, platí úroveň `info`. Doba transformace
se ukazuje jen v celých milisekundách. Výpočty jsou zhruba o polovinu
pomalejší než na desktopu.

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
zig build web
```
