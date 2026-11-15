# Přepis z Rustu do Zigu – zkušenosti

Deník přepisu programu z Rustu (egui, egui_plot) do Zigu 0.17.1 (DVUI, backend
SDL3). Původní verze je v adresáři `last-rust-version/` a v gitu pod tagem
`last-rust-version`.

Ke každé zkušenosti je uvedeno, jestli je výsledek v Zigu **lepší**, **horší**,
**srovnatelný**, nebo jestli něco **nejde** přepsat. Záznamy přibývají postupně
během přepisu.

## Shrnutí

| Oblast | Výsledek | Poznámka |
|---|---|---|
| Sestavení a závislosti | horší | DVUI stahuje i nepoužívané balíčky, SDL3 je potřeba mít v systému |
| Písmo s českými znaky | horší | výchozí písmo DVUI nemá ř, ť, ň, ů, ě, ď; řešeno vloženým písmem Inter |
| Pozadí okna | horší (drobnost) | DVUI okno nevyplní, bez vlastního pozadí je černé |
| Logování | horší | `std.log` nemá pojmenovaná pole jako `tracing` |
| Oddělení DSP od UI | lepší | DSP je samostatný modul bez přístupu k DVUI, hlídá to překladač |
| Stabilita jazyka | horší | API standardní knihovny a build systému se mezi verzemi Zigu mění |

## Sestavení a závislosti

**Horší.** V Rustu stačilo `cargo run`: Cargo stáhlo crates a egui přes eframe
nepotřebuje žádnou systémovou knihovnu kromě ovladače OpenGL.

- DVUI s backendem SDL3 umí použít systémovou knihovnu SDL3
  (`zig build -fsys=sdl3`). Program se pak linkuje dynamicky proti
  `libSDL3.so`, ale SDL3 musí být v systému nainstalované. Bez přepínače
  `-fsys=sdl3` by si DVUI přeložil SDL3 ze zdrojů (a s ním i X11, Wayland,
  dbus a další), což nechceme. Přepínač nemusí psát uživatel: `build.zig`
  před načtením DVUI zavolá
  `b.systemIntegrationOption("sdl3", .{ .default = true })` a stačí pak
  obyčejné `zig build`.
- Balíčkovací systém Zigu stáhne všechny nelíné (non-lazy) závislosti DVUI,
  i když je program nepoužívá. Například balíček SDL2 se stahuje, i když
  linkujeme SDL3. Líné (lazy) závislosti se stáhnou, až když jsou opravdu
  potřeba.
- Některé volitelné části DVUI se dají vypnout volbou při načtení závislosti,
  např. `.@"tree-sitter" = false` (zvýrazňování syntaxe v editoru kódu).
  Ubude tím několik stahovaných balíčků.
- Proti Cargu: přesné verze se v Zigu připínají hashem obsahu
  (`build.zig.zon`), což je stejně spolehlivé jako `Cargo.lock`. Seznam
  „povolených features“ jako u crates ale neexistuje, místo nich jsou volby
  v `build.zig`.

## Písmo s českými znaky

**Horší.** egui má ve výchozích písmech celou latinku včetně češtiny.
Výchozí písmo DVUI (Bitstream Vera Sans) obsahuje jen základní latinku
a západoevropské znaky (á, é, í, ó, ú, ý, č, š, ž projdou, ale ř, ť, ň, ů, ě, ď
se vykreslí jako prázdný obdélník). Z písem přibalených v DVUI má české znaky
jen neproporcionální Hack, patkové Aleo a pixelové Pixelify Sans.

Řešení: do programu je přes `@embedFile` vložené písmo Inter (běžný a tučný
řez, asi 690 kB). Funkce `dvui.addFont` umí přidat jen běžný řez (tučnost
z TTF souboru nečte), proto se oba řezy registrují jako
`dvui.Font.Source` v poli `embedded_fonts` vlastního motivu odvozeného
z `Theme.builtin.adwaita_light`. Vložení souboru do binárky je v Zigu
jednodušší než v Rustu (`@embedFile` funguje stejně jako `include_bytes!`),
ale nastavení písma v egui bylo zbytečné, protože výchozí písmo češtinu
umělo.

## Pozadí okna

**Horší (drobnost).** V egui má každý panel automaticky pozadí podle motivu.
V DVUI backend SDL3 na začátku snímku vymaže okno na černo a pozadí se
nakreslí, jen když o něj widget požádá (např. `dvui.box` s
`.background = true`). Tmavý text na černém pozadí pak vypadá jako prázdné
okno.

## Logování

**Horší.** V Rustu se používal `tracing` s pojmenovanými poli
(`info!(fft_size, sample_rate_hz, "spectrum computed")`) a výstupem do JSON
souboru i na terminál. `std.log` v Zigu má jen zprávu s formátovacím řetězcem.
Pojmenovaná pole se dají napodobit textem `klic=hodnota` ve zprávě, ale log
není strojově čitelný jako JSON. Úroveň a rozsah (scope) zprávy `std.log`
podporuje, takže filtrování podle úrovně zůstává.

Vlastní `logFn` v `std_options` je krátký (asi 25 řádků) a dělá přesně to, co
chceme: zapisuje na standardní výstup jeden řádek na zprávu ve tvaru
`info(scope): zpráva klic=hodnota`. Úroveň logování jde stejně jako v Rust
verzi změnit proměnnou prostředí `LOG_LEVEL`. Protože `std.log` filtruje
úroveň už při překladu, propouštíme za překladu všechno (`.log_level = .debug`)
a filtrujeme až za běhu ve vlastní `logFn`. Do stejného logu jdou i zprávy
z DVUI a SDL, což je příjemné. Vlákno pro zápis do souboru a rotace denních
souborů, které Rust verze měla díky `tracing-appender`, odpadly, protože se
loguje jen na standardní výstup.

## Oddělení DSP od uživatelského rozhraní

**Lepší.** V Rust verzi bylo pravidlo „`src/dsp/` nesmí záviset na egui“ jen
dohoda: všechno byl jeden crate a `use egui` by v `src/dsp/` prošlo.
V Zigu je DSP samostatný modul (`src/dsp/dsp.zig`), kterému `build.zig`
nepředá import `dvui`. Pokus o `@import("dvui")` v DSP skončí chybou
překladu. Testy DSP (`zig build test`) se navíc překládají a běží bez DVUI
a bez SDL, takže jsou rychlé. V Rustu by stejného výsledku šlo dosáhnout
rozdělením na dva crates ve workspace, ale bylo by to pracnější.

## Stabilita jazyka

**Horší.** Rust edice 2024 a stabilní toolchain zaručují, že kód napsaný
dnes se přeloží i novější verzí. Zig před verzí 1.0 mění API mezi verzemi
a návody na internetu bývají pro starší verze. Už při psaní kostry:

- `std.meta.fields` je v Zigu 0.17 zrušené (`@compileError`) a struktura
  `@typeInfo` pro enum se změnila (`field_names` místo `fields`).
- `b.args` v `build.zig` zmizelo, argumenty pro `zig build run -- …` se teď
  předávají voláním `run_cmd.addPassthruArgs()`.
- Funkce `main` dostává `std.process.Init` (alokátor, `Io`, proměnné
  prostředí). DVUI ho zpřístupňuje jako `dvui.App.main_init`.

Pomáhá, že překladač hlásí zrušené funkce srozumitelnou chybou a že zdrojáky
standardní knihovny se dobře čtou.
