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
| Písmo s českými znaky | horší | výchozí písmo DVUI nemá ř, ť, ň, ů, ě, ď |
| Pozadí okna | horší (drobnost) | DVUI okno nevyplní, bez vlastního pozadí je černé |
| Logování | horší | `std.log` nemá pojmenovaná pole jako `tracing` |

## Sestavení a závislosti

**Horší.** V Rustu stačilo `cargo run`: Cargo stáhlo crates a egui přes eframe
nepotřebuje žádnou systémovou knihovnu kromě ovladače OpenGL.

- DVUI s backendem SDL3 umí použít systémovou knihovnu SDL3
  (`zig build -fsys=sdl3`). Program se pak linkuje dynamicky proti
  `libSDL3.so`, ale SDL3 musí být v systému nainstalované. Bez přepínače
  `-fsys=sdl3` by si DVUI přeložil SDL3 ze zdrojů (a s ním i X11, Wayland,
  dbus a další), což nechceme.
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
