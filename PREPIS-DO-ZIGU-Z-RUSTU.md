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
| DSP – délka kódu | srovnatelná | asi 1 570 řádků v Zigu proti 1 580 v Rustu včetně testů |
| DSP – vzorce s komplexními čísly | horší | Zig nemá přetěžování operátorů: `a.add(w.mul(b))` místo `a + w * b` |
| DSP – správa paměti | horší i lepší | explicitní alokátor a `defer free` všude; testy ale samy hlídají úniky |
| DSP – chybné vstupy | lepší | chyba v návratovém typu (`error.LengthNotPowerOfTwo`) místo paniky |
| Převody čísel | horší | `@floatFromInt` u každého převodu `usize` → `f64` |
| Grafy | horší | egui_plot dal grafy zadarmo, v Zigu vlastní widget (asi 780 řádků) |
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

## DSP (`src/dsp/`)

Převedeno všech sedm modulů a všech 38 testů z Rust verze. Všechny testy
prošly napoprvé se stejnými tolerancemi, čísla tedy sedí. Kód má
v obou jazycích skoro stejnou délku (Zig 1 566 řádků, Rust 1 584 včetně
testů).

**Horší – komplexní čísla bez operátorů.** Zig nemá přetěžování operátorů.
Motýlek FFT, který v Rustu vypadá jako vzorec z učebnice
(`data[top] = a + b; b = w * data[bottom]`), se v Zigu píše voláním metod
(`a.add(b)`, `w.mul(data[bottom])`). U delších výrazů (frekvenční
charakteristika, DFT) je to hůř čitelné, což je u učební pomůcky citelné.
Zig to dělá záměrně: v kódu nesmí být skrytá volání funkcí.

**Horší i lepší – správa paměti.** Rust vrací `Vec<f64>` a o uvolnění se
nestará. V Zigu dostává každá alokující funkce alokátor a volající musí
výsledek uvolnit (`defer allocator.free(...)`). Testy jsou kvůli tomu
o něco delší: kde Rust napíše `fft(&real_to_complex(&samples))` na jednom
řádku, Zig potřebuje mezivýsledek s vlastním `defer`. Na druhou stranu
`std.testing.allocator` po každém testu ověří, že se všechno uvolnilo.
Únik paměti tak test rovnou shodí. V Rustu se úniky v běžném kódu nestávají,
takže tam podobnou kontrolu ani není potřeba dělat.

Výhodou explicitního alokátoru je, že se dá zvolit, odkud paměť přijde.
Uživatelské rozhraní tak bude moci počítat do arény, kterou na konci snímku
celou zahodí, místo aby uvolňovalo každé pole zvlášť.

**Lepší – chybné vstupy jako chyby.** Rust verze při délce FFT, která není
mocninou dvou, nebo při sudé délce FIR filtru volala `assert!` (panika).
Test na to používal `#[should_panic]`. V Zigu se panika testovat nedá
(ukončí celý testovací proces), proto `fft` a `designFir` vracejí chybu
(`error.LengthNotPowerOfTwo`, `error.FirLengthNotOdd`) a test ji ověří přes
`expectError`. Je to lepší i obecně: z typu funkce je vidět, že může selhat,
a volající to musí ošetřit. Přibyl tím jeden test (sudá délka FIR).
Chyby, které jsou jen chybou programátora (různé délky signálu a okna),
zůstaly jako `std.debug.assert`.

**Horší – převody čísel.** Každý převod indexu na `f64` se v Zigu píše
`@floatFromInt(index)` a navíc potřebuje znát cílový typ. Proto má každý
modul pomocnou funkci `toF64`. Rust má kratší `index as f64`. Podobně
`1 / @sqrt(2.0)` neprojde překladem (dělení celého čísla s desetinným za
překladu je „nejednoznačné“), je třeba psát `1.0 / @sqrt(2.0)`.

**Lepší – drobnosti v syntaxi.**
- Cyklus přes několik polí najednou je přímo v jazyce:
  `for (output, samples, coefficients) |*result, sample, weight|`.
  V Rustu to vyžaduje `iter().zip()`, u tří polí dvakrát.
- Rozbalení pole do proměnných: `const b0, const b1, const b2 = biquad.b;`.
- Násobení s přetečením má vlastní operátor `*%` (generátor šumu), Rust volá
  `wrapping_mul`.
- `@memset`, `@memcpy`, `@abs`, `@sin`, `@log10` jsou vestavěné a fungují
  i pro vektory.

**Srovnatelné.** Výčtové typy (`enum`) a `switch` fungují jako `enum`
a `match` v Rustu, včetně kontroly, že jsou pokryté všechny možnosti.
Struktury s metodami (`Complex`, `SampledSignal.sampleTime`) jsou si také
podobné. Návrat mezivýsledku místo kopírování (horní propust se z dolní
udělá na místě) je v Zigu přirozenější, protože pole není „přesunuté“
a dá se dál upravovat.

## Grafy (`src/ui/plot.zig`)

**Horší.** V Rust verzi kreslil grafy hotový crate `egui_plot`. Každý graf
se nastavil několika řádky (`Plot::new(...).legend(...).link_axis(...)`)
a přibližování, posun, legenda, mřížka i dílky os fungovaly samy. Graf
v DVUI (`dvui.plot`) umí jen osy, čáry, sloupce a jednoduchý popisek;
chybí přibližování a posun, legenda, propojené osy a čárkované čáry.
Proto vznikl vlastní widget: asi 780 řádků v jednom souboru.

Co widget umí (stejně jako grafy v Rust verzi):
- lomené čáry, body se stonky, svislé (i čárkované) čáry, barvy a tloušťky,
- osy s „hezkými“ dílky (1, 2, 5 × 10ⁿ), mřížku a zvýrazněné osy v nule,
- popisky os, pevnou šířku svislé osy (grafy pod sebou jsou zarovnané),
- legendu v pravém horním rohu,
- automatický rozsah s okrajem 5 %, `include_y` a výchozí rozsah,
- tažení myší = posun, kolečko = posun, Ctrl + kolečko = přiblížení kolem
  kurzoru, dvojklik = automatický rozsah,
- propojenou osu x více grafů (`LinkedAxis`),
- popisek se souřadnicemi a názvem nejbližší křivky a zaměřovací kříž.

Co oproti egui_plot chybí: výběr oblasti pro přiblížení pravým tlačítkem
a skrývání křivek kliknutím do legendy. Rust verze ani učebnice je
nepoužívaly.

Lepší je, že widget je celý náš a dá se upravit. Například popisek
u kurzoru musela Rust verze skládat přes `label_formatter`, protože výchozí
popisek egui_plot souřadnice neukazoval. Tady je to přímo součást widgetu.
Kreslení v DVUI je přímočaré: `dvui.Path.stroke` pro čáry, `fillConvex`
pro kruhy, `dvui.renderText` pro text (umí i otočení pro svislý popisek
osy), `dvui.clip` pro ořez na kreslicí plochu.

DVUI je v okamžitém režimu jako egui, takže widget funguje podobně:
křivky se během snímku jen posbírají a při `show()` se spočítá rozsah,
obslouží myš a vše se nakreslí. Stav mezi snímky (rozsah os, čas
posledního kliknutí pro dvojklik) se ukládá přes `dvui.dataSet` pod ID
widgetu. Dvojklik DVUI jako událost nehlásí, rozpozná se podle času mezi
dvěma stisky.

Pomocné alokace (body v pixelech, texty popisků) jdou do arény snímku
(`dvui.currentWindow().arena()`), kterou DVUI na konci snímku celou zahodí.
Uvolňovat je tedy není potřeba, podobně jako v Rustu, kde se `Vec` uvolní
sám.

Tmavý motiv: barvy grafů v Rust verzi byly zvolené pro tmavé pozadí egui,
proto i verze v Zigu používá tmavý motiv `adwaita_dark`.
