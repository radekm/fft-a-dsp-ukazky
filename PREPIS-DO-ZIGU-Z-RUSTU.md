# Přepis z Rustu do Zigu – zkušenosti

Deník přepisu programu z Rustu (egui, egui_plot) do Zigu 0.17.1 (DVUI, backend
SDL3). Původní verze je v adresáři `last-rust-version/` a v gitu pod tagem
`last-rust-version`.

Ke každé zkušenosti je uvedeno, jestli je výsledek v Zigu **lepší**, **horší**,
**srovnatelný**, nebo jestli něco **nejde** přepsat. Záznamy přibývají postupně
během přepisu.

## Celkový dojem

Přepsat šlo všechno: všechny čtyři záložky, všechny výpočty a všech 38 testů.
Nic z Rust verze nezůstalo nepřepsané. Čísla v programu se shodují s Rust
verzí i s čísly v učebnici. Odchylky jsou jen ve vzhledu: světlý motiv, širší panel,
větší písmo a ovládací prvky, posuvníky zaokrouhlují na setiny.

Nejvíc práce navíc stálo uživatelské rozhraní. egui s egui_plot dávají
hotové grafy s přibližováním a legendou a posuvníky s jednotkami
a logaritmickou stupnicí. V DVUI bylo potřeba napsat vlastní widget grafu
(asi 870 řádků) a vlastní posuvník s políčkem. Proto má verze v Zigu
asi 4 900 řádků proti 3 900 v Rustu, přestože DSP i záložky mají délku
podobnou.

Zig byl lepší tam, kde jde o přehled nad pamětí a o kontrolu: DSP je
oddělené od UI přímo překladačem, testy hlídají úniky paměti, chyby jsou
v návratovém typu a bezpečnostní kontroly v režimu Debug okamžitě odhalily
pád uvnitř DVUI (přetečení indexu vrcholů). Horší byla čitelnost vzorců
(žádné přetěžování operátorů), převody čísel a nestabilita jazyka
před verzí 1.0.

| Měřeno na stejném stroji | Zig + DVUI | Rust + egui |
|---|---|---|
| Řádků kódu (včetně testů a komentářů) | 4 899 | 3 913 |
| První sestavení release, bez stažených závislostí v mezipaměti | 1 min 43 s | 3 min 10 s |
| Velikost programu po `strip` | 5,0 MB (+ systémové `libSDL3.so` 4,0 MB) | 8,7 MB |
| Dynamicky linkované knihovny | `libSDL3`, `libc`, `libm` | `libc`, `libm`, `libgcc_s` (OpenGL a X11 se načítají za běhu) |

## Shrnutí po oblastech

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
| Grafy | horší | egui_plot dal grafy zadarmo, v Zigu vlastní widget (asi 870 řádků) |
| Ovládací prvky | horší | posuvník DVUI umí jen zlomek 0–1; jednotky, log. stupnici a políčko s číslem jsme doplnili sami |
| Rozvržení panelu | srovnatelné | levý panel, posuvná oblast a grafy se skládají z boxů podobně jako v egui |
| Políčko s číslem | horší | `dvui.textEntryNumber` ukazuje plnou přesnost, vlastní políčko s pevným počtem míst |
| Dlouhé čáry v DVUI | horší | `strokeTriangles` v DVUI má index vrcholu napevno `u16` (chyba DVUI, volba `vertex-index` nepomůže): čára s 16 000 body shodila program, kreslí se po úsecích |
| Stabilita jazyka | horší | API standardní knihovny a build systému se mezi verzemi Zigu mění |
| Bezpečnostní kontroly | lepší | v Debug/ReleaseSafe Zig okamžitě a přesně ukázal přetečení uvnitř DVUI |
| Nedefinované chování | horší i lepší | v ReleaseFast je UB to, co Rust ohlídá vždy; Debug/ReleaseSafe ho ale spolehlivě zachytí |
| Výsledná čísla | stejné | všechny testy i čísla v učebnici souhlasí |

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
- Na macOS se program se systémovým SDL3 nepřeložil: chyběly symboly
  `_OBJC_CLASS_$_NSEvent` a `_objc_msgSend`. DVUI na macOS přidává do backendu
  SDL3 vlastní soubor v Objective-C (`macos_monitor.m`, používá AppKit), ale
  potřebné knihovny k němu nepřilinkuje – spoléhá na to, že je přinese SDL3
  přeložené ze zdrojů. Sdílená knihovna `libSDL3.dylib` své závislosti do
  programu nepředá. `build.zig` proto na macOS přidává framework AppKit
  a `libobjc`. Je to další drobná chyba DVUI, na Linuxu se neprojeví.
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
Proto vznikl vlastní widget: asi 870 řádků v jednom souboru (po doplnění
všeho, co potřebovaly záložky).

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

Motiv: Rust verze měla tmavý motiv egui. Verze v Zigu nejdřív převzala tmavý
motiv `adwaita_dark`, na přání autora ale nakonec používá světlý
`adwaita_light`. Barvy křivek jsou proto tmavší (`common.colors`), aby byly
na bílém pozadí dobře vidět. Změna motivu v DVUI je jeden řádek, barvy
grafu (mřížka, popisky, rámečky) se berou z motivu samy.

Čísla na osách (oprava po nasazení webové verze): u sinusovky 0 Hz s fází
180° je signál 0,11 · sin(π), v počítači ale vyjde asi 1,3·10⁻¹⁷.
Automatický rozsah se natáhl na tento zaokrouhlovací šum, čísla osy y měla
19 desetinných míst a přetekla do levého panelu. Oprava má tři části:

- Automatický rozsah bere data s rozpětím pod 10⁻¹² nebo pod tisícinou
  velikosti hodnot jako konstantu a ukáže vodorovnou čáru (osa −1,1 až 1,1).
  Stejná mez platí pro přiblížení kolečkem (dřív miliardtina), takže čísla
  na osách mají nejvýš asi 6 znaků („51.13“, „0.9184“).
- Velmi malé (pod 10⁻⁴) a velké (od 10⁶) hodnoty se na osách
  i v popisku u kurzoru píšou vědecky: `2e-5`, `1.5e6`, `1.347e-17`.
  Rozhoduje velikost hodnot, ne kroku: u malého rozsahu daleko od nuly by
  vědecký zápis dal samá stejná čísla („5.112e1“).
- Čísla osy y se ořezávají na svůj pás vedle grafu, aby nikdy nezasáhla
  do panelu.

Společný násobitel u osy (jako „×10⁻⁵“ v matplotlib) by se četl lépe, ale
autor dal přednost jednoduššímu kódu.

## Záložka „Signály a spektrum“ (`src/ui/spectrum.zig`, `src/ui/common.zig`)

Rozsahem kódu je záložka podobná Rust verzi (spectrum.zig 426 řádků,
spectrum.rs 453). Výpočty a čísla sedí: biny po 1 Hz, špičky 1,0 a 0,5 na
50 Hz a 120 Hz, fáze sinusovky −90°.

**Horší – ovládací prvky.** `egui::Slider` uměl v jednom řádku posuvník,
políčko s číslem (dá se do něj psát i táhnout), jednotku („Hz“),
logaritmickou stupnici a krok. Posuvník DVUI (`dvui.slider`) pracuje jen se
zlomkem 0 až 1 typu `f32`. Funkce `common.slider` proto skládá posuvník,
políčko `dvui.textEntryNumber` (do něj se dá psát) a popisek a sama
převádí zlomek na hodnotu (lineárně i logaritmicky). Hotový
`dvui.sliderEntry` jsme nepoužili: neumí logaritmickou stupnici a pracuje
jen s `f32`.

Políčko DVUI vypisuje číslo v plné přesnosti (`{d}`), takže po tažení
posuvníkem by ukázalo třeba 37.29384756. Posuvník proto hodnotu zaokrouhlí
na krok (frekvence na setiny, amplituda na setiny, fáze na celé stupně).
Do políčka lze napsat libovolnou hodnotu. Navíc to usnadní nastavit přesné
hodnoty, které chce učebnice (10 Hz, 0,50, 90°). Pozor na zaokrouhlení
`f64`: `round(x / 0.01) * 0.01` dá 37.290000000000006, správně je
`round(x * 100) / 100`.

**Horší – zalamování textu.** V egui se běžný text v panelu sám zalomí do
šířky panelu. `dvui.label` text nezalamuje, ale zkrátí ho „…“. Pro delší
texty je třeba `dvui.textLayout`. Řádky s přepínači, které se nevejdou,
pokračují na dalším řádku díky `dvui.flexbox` (v egui
`horizontal_wrapped`).

**Drobné odchylky od Rust verze:**
- Písmo Inter je širší než výchozí písmo egui, proto má levý panel 320 px
  místo 300 px a běžný text velikost 13 px.
- V nabídce délky FFT je vidět „1024 = 2^10“ (v egui jen „1024“), protože
  `dvui.dropdown` ukazuje vybranou položku tak, jak je v seznamu.
- Tlačítko „Přidat složku“ je při šesti složkách jen zašedlé
  (`grayed`), DVUI nemá zakázaný stav tlačítka.

**Srovnatelné – rozvržení.** Levý panel s posuvnou oblastí a pravá oblast
s grafy se skládají z `dvui.box` a `dvui.scrollArea`, podobně jako
`egui::Panel::left` a `ScrollArea`. Výšku grafů lze spočítat z velikosti
boxu hned po jeho vytvoření, stejně jako `ui.available_height()` v egui.

**Lepší – kešování výsledku.** Rust verze porovnávala nastavení přes
`#[derive(PartialEq)]`. V Zigu stačí `std.meta.eql`, ale nastavení obsahuje
pole šesti složek, z nichž platí jen několik prvních. Vlastní funkce `eql`
porovná jen platné složky. Pevné pole místo `Vec` znamená, že nastavení
nepotřebuje alokaci a dá se kopírovat jako hodnota.

**Jazyk – drobnosti, na které jsme narazili:**
- Operátor `**` (opakování pole) už v Zigu 0.17 není; pole se plní přes
  `@splat` a přiřazení.
- Zig nedovolí, aby lokální proměnná nebo parametr měly stejné jméno jako
  funkce ve stejném souboru (`text`, `row`). Rust zastínění dovoluje.
- Ostré špičky spektra se při napojování úseků čáry způsobem `.strip`
  zkracovaly (špička 1,0 vypadala jako 0,75). Výchozí `.miter` je kreslí
  správně.

## Záložka „Okna a prosakování“ (`src/ui/windows.zig`)

Čísla souhlasí s Rust verzí do posledního zobrazeného místa. Pro obdélníkové
okno, N = 64 a frekvenci 10,5 binu ukazují obě verze první nulu ±1,00 binu,
postranní lalok −13,3 dB, koherentní zisk 1,00 a nejvyšší čáru −3,79 dB.
Kód má 512 řádků (Rust 553).

**Horší – pád programu kvůli délce čáry.** Spektrum okna se kreslí z
16 385 bodů. DVUI čísluje vrcholy jednoho tahu (`dvui.Path.stroke`)
typem `u16`, takže víc než 65 535 vrcholů (na bod čáry jich připadá
několik) skončí přetečením celého čísla. V režimu Debug to Zig zachytí
a program spadne s hlášením „integer overflow“ a přesným místem. Bez
kontrol (ReleaseFast) by šlo o nedefinované chování. egui se s tím
nepotýkalo. Zkusili jsme přepnout DVUI volbou `vertex-index` na
32bitové indexy, ale nepomohlo to. Funkce `strokeTriangles` v DVUI
(`src/Path.zig`, commit `485a1ed`) je v tomto ohledu rozbitá: index vrcholu
má napevno jako `u16` (např. `const vtx_base: u16 = ...`) a volbu
`vertex-index` ignoruje, přestože zbytek DVUI typ indexu bere z této volby
(`dvui.Vertex.Index`). Jde o chybu v DVUI, ne o omezení backendu SDL3, který
32bitové indexy umí.
Widget grafu proto kreslí dlouhé čáry po úsecích nejvýš 2 000 bodů
a DVUI zůstává s výchozími 16bitovými indexy. Pozitivní je, že bezpečnostní kontroly Zigu
chybu ukázaly okamžitě a přesně.

**Horší – zakázané ovládací prvky.** V Rust verzi byly posuvníky slabé
sinusovky při jejím vypnutí zašedlé (`add_enabled_ui`). DVUI zakázaný stav
nemá, posuvníky se proto při vypnutí slabé sinusovky skryjí.

**Srovnatelné.** Tabulku vlastností okna (v egui `Grid`) nahradily řádky
s popiskem pevné šířky. Rozbalovací seznamy s délkou signálu a násobkem
doplnění nulami mají popisky vytvořené už za překladu
(`std.fmt.comptimePrint`), takže nepotřebují žádnou alokaci.

**Lepší – sdílené pomocné funkce grafu.** Widget grafu dostal body bez čar
(`markers`) a jiný název osy v popisku u kurzoru (`hover_x_label`). Obojí
egui_plot uměl, u vlastního widgetu se to doplní pár řádky.

## Záložka „Vzorkování a aliasing“ (`src/ui/sampling.zig`)

Výsledek odpovídá Rust verzi: výchozí 5 Hz při fs = 40 Hz, po nastavení
35 Hz se složka jeví jako 5,000 Hz (alias, červeně), rekonstrukce je
otočená sinusovka 5 Hz. Kód má 361 řádků (Rust 401).

**Srovnatelné – iterátory a pole.** Rust verze skládala body grafů řetězci
iterátorů (`map`, `filter`, `collect`). V Zigu jsou to obyčejné cykly do
předem alokovaných polí. Kód je o něco delší, ale je z něj vidět, kolik
paměti se alokuje. Filtrování (čáry spektra nad 250 Hz, slabé čáry) se
dělá dvěma průchody: nejdřív se spočítá, kolik prvků zůstane, pak se pole
naplní. Zkrácení pole po filtrování přes `allocator.realloc` je potřeba
ošetřit, protože i zmenšení může selhat.

**Lepší – bloky s návratovou hodnotou.** Mezivýsledky, které se hned
uvolní (vstup a výstup DFT), jsou v bloku `blk: { ... break :blk výsledek; }`
s vlastními `defer`. Paměť se uvolní hned na konci bloku a ve zbytku funkce
mezivýsledky nepřekážejí. V Rustu se o to stará automatický `Drop`
na konci bloku, v Zigu je to vidět přímo v kódu.

## Záložka „Filtry“ (`src/ui/filters.zig`)

Výsledky odpovídají číslům v učebnici (lekce 14): pro IIR dolní propust
100 Hz s Q = 1/√2 vychází b0 = 0,06746, a1 = −1,14298, a2 = 0,41280.
Snímek `docs/ucebnice/img/14-vychozi.png` z Rust verze ukazuje mírně jiné
koeficienty (0,06754; −1,14435; 0,41449), které přesně odpovídají Q = 0,71.
Snímek tedy vznikl s Q zaokrouhleným na dvě desetinná místa, výpočet je
v obou verzích stejný. Kód má 565 řádků (Rust 597).

**Srovnatelné – dva sloupce grafů.** egui má `ui.columns(2, …)`, v DVUI
stačí vodorovný box s volbou `equal_space` a dvěma svislými boxy.

**Horší – políčko s číslem.** Tlačítko „Q = 0,707“ nastaví Q na přesně
1/√2. `dvui.textEntryNumber` by ukázal 0.7071067811865476 (do políčka se to
nevejde). Políčko u posuvníku je proto vlastní (`common.numberEntry`): dokud
do něj uživatel nepíše, ukazuje číslo zaokrouhlené na pevný počet míst
(jako `fixed_decimals` v egui), při psaní mění hodnotu průběžně. Uložená
hodnota zůstává přesná. Rozpoznat, zda uživatel do políčka právě píše,
jde přes `dvui.focusedWidgetId()`.

**Lepší – `errdefer` u větvení.** Výpočet má dvě větve (FIR a IIR), každá
alokuje jinak. `errdefer` uvnitř větve uvolní jen to, co alokovala tato
větev, a `errdefer` za větvením pak hlídá zbytek funkce. Při chybě se tak
uvolní přesně to, co už existuje. V Rustu to řeší `Drop` automaticky.

**Doplněno do widgetu grafu:** čárkovaná lomená čára (zesílení filtru
ve spektru, v egui `LineStyle::dashed_loose`) a menší rozestup dílků
na ose x pro úzké grafy (v egui `AxisHints::label_spacing`).

## Dokumentace a snímky do učebnice

Odkazy na kód v dokumentaci šly převést skoro mechanicky: soubory `.rs`
na `.zig` a názvy funkcí ze `snake_case` na `camelCase` (`one_sided_spectrum`
→ `oneSidedSpectrum`). Konstanty se v Zigu píší malými písmeny (`DB_FLOOR`
→ `db_floor`). Všechna čísla v učebnici zůstala platná, protože DSP počítá
stejně. Změnily se jen naměřené doby výpočtu v lekci 6.

Všech 48 snímků se pořídilo znovu ve světlém motivu stejným postupem jako
v Rust verzi: dočasná kopie programu (git worktree mimo repozitář) nastaví
stav podle proměnné prostředí `SHOT`, program běží ve virtuálním displeji
Xvfb, myš a klávesnici ovládá XTest a snímek pořídí `import`. Celé snímky
a výřezy se pak skládají přes ImageMagick.

Při focení se ukázaly dvě drobnosti ve widgetu grafu, které jsme opravili
i v programu:
- Popisek u kurzoru se u vzorku přichytil ke spojitému signálu, protože
  ten má body hustě (0,3 px od sebe). Samostatné body (stonky, puntíky)
  teď mají při najetí myší přednost před lomenou čárou.
- Frekvence složek se v políčku ukazují bez nul na konci („300“ místo
  „300.00“), jinak by se delší čísla do políčka nevešla.

## Kontrola nedefinovaného chování

V Zigu je řada chyb (přetečení celého čísla, převod NaN nebo nekonečna
na celé číslo `@intFromFloat`, nesplněný `assert`, index mimo pole)
v režimech Debug a ReleaseSafe zachycená a program spadne s přesným
hlášením. V ReleaseFast a ReleaseSmall jde ale o **nedefinované chování**.
Rust tyto chyby (kromě přetečení v release) kontroluje vždy. Proto jsme
kód prošli a krajní případy vyzkoušeli v programu. Našly se tyto chyby:

- **Filtry, pásmová propust:** při dolní mezi 499 Hz (maximum posuvníku)
  volal kód `std.math.clamp(horní, dolní + 1, 499)`, tedy s dolní hranicí
  nad horní. `clamp` to hlídá přes `assert` a program v Debug spadl.
  Rust verze měla stejnou chybu (`f64::clamp` při `min > max` panikuje).
  Oprava: dolní mez se nejdřív omezí na 498 Hz.
- **Graf, silné přiblížení:** po mnoha otočeních kolečkem s Ctrl se rozsah
  osy zmenšil pod přesnost `f64`. Dílky osy se počítaly přičítáním kroku
  (`x += krok`), a když byl krok menší než přesnost čísla, cyklus se
  zacyklil a program zamrzl. Při nulovém rozsahu by navíc
  `@intFromFloat(inf)` byl nedefinovaný. Oprava: dílky se počítají z
  celočíselného indexu (`i · krok`) s horní mezí počtu, neplatný rozsah
  nemá dílky a přiblížení nebo posun, po kterém by osa nešla zobrazit, se
  zahodí. Přidány testy krajních případů.
- **Úroveň logování:** globální proměnnou čte každé volání logu, i z vláken
  DVUI a SDL. Souběžný zápis a čtení obyčejné proměnné je datový závod,
  proto je teď atomická (`std.atomic.Value`).
- **`analyzeWindow`:** u prázdného spektra by `db.len - 1` podteklo;
  ošetřeno, i když to program nikdy nevolá.

Ostatní místa jsou v pořádku: převody `@intCast` a `@intFromFloat` dostávají
hodnoty z ověřených rozsahů (políčko s číslem přijme jen hodnotu mezi
minimem a maximem posuvníku, do políčka nejde napsat „nan“ ani „inf“),
`undefined` se vždy přepíše dřív, než se čte, a ukazatele do arény snímku
se používají jen v rámci snímku.

### Druhá, podrobnější kontrola vestavěných funkcí (`@…`)

Prošli jsme každé volání vestavěné funkce a porovnali ho s dokumentací
jazyka pro Zig 0.17.1 (`doc/langref.html` u překladače). Nedefinované
chování (v řeči Zigu „safety-checked Illegal Behavior“) hrozí jen u:

| Funkce | Kdy je to chyba | Stav v našem kódu |
|---|---|---|
| `@intCast` | hodnota se nevejde do cílového typu | jen indexy z rozbalovacích seznamů, `@ctz` mocniny dvou a doba výpočtu v ns – vždy v rozsahu |
| `@intFromFloat` | NaN nebo hodnota mimo rozsah (v 0.17 je zastaralé, odpovídá `@trunc`) | počet desetinných míst (omezen na 0–20) a číslic mantisy (0–6), počet dílků (1–1000), `k` filtru (1–200), počet vzorků (fs 1–200) |
| `@round`, `@floor`, `@ceil`, `@trunc` | totéž, **pokud je odvozený typ výsledku celé číslo** – v 0.17 tak tyto funkce převádějí na celé číslo | všude s výsledkem `f64`, převod vždy výslovně přes `@intFromFloat` |
| `@mod` | nulový dělitel | čárkování čáry – nově ošetřený nulový vzor |
| `@memcpy` | různé délky nebo překryv | `zeroPad` – stejné délky, nově alokovaná paměť |
| `@tagName` | neplatná hodnota neúplného výčtu | jen úplné výčty |

Bezpečné vždy jsou `@floatFromInt`, `@floatCast` (jen ztráta přesnosti,
mimo rozsah dá nekonečno), `@abs`, `@max`/`@min` (NaN ignorují),
`@sin`, `@cos`, `@log`, `@sqrt`, `@exp` (u neplatného vstupu vrátí NaN),
`@memset`, `@splat`, `@backingInt`, `@ctz` (pro nulu vrátí šířku typu).

Kontrola ale odhalila další chybu, tentokrát v okolí `@mod`: čárkovaná
lomená čára (zesílení filtru ve spektru) se při silném přiblížení
**zasekla**. Jeden úsek čáry měl na obrazovce stovky milionů pixelů,
čárkovalo se tedy obrovské množství čárek, a protože pozice byla v `f32`,
krok 6 px se k ní od jisté velikosti vůbec nepřičetl a cyklus neskončil.
Oprava: každý úsek lomené čáry se nejdřív ořízne na kreslicí plochu
(algoritmus Liang–Barsky v `f64`) a kreslí se jen viditelná část. Body,
stonky a svislé čáry mimo plochu se přeskočí. Rozsah osy má navíc
absolutní dolní mez 10⁻¹², aby souřadnice vzdálených bodů nemohly přetéct
do nekonečna, a ořezání odmítne nekonečno i NaN. Podmínky „je mimo plochu“
jsou psané jako `!(x >= a and x <= b)`, protože `x < a or x > b` by NaN
pustilo dál.

Ponaučení: nedefinované chování v Zigu se neschovává jen v ukazatelích.
Hlavní riziko u tohoto programu byly převody desetinných čísel na celá
a cykly řízené desetinnými čísly. U obojího je potřeba myslet na NaN,
nekonečno a omezenou přesnost.

Zajímavost: `zig fmt` v Zigu 0.17 sám přepisuje zastaralé `@intFromEnum`
na novější `@backingInt`. Formátovač tedy mění i význam kódu, nejen
mezery, a jedno místo tím rozbil (dvě různé úpravy se potkaly na jednom
řádku). Další drobný příklad nestability jazyka před verzí 1.0.

## Webová verze (WebAssembly)

Po dokončení přepisu přibyla webová verze: tentýž program přeložený pro
`wasm32-freestanding` s webovým backendem DVUI. Kreslí do `<canvas>` přes
WebGL, události z prohlížeče předává `web.js` z DVUI. Sestavení
a spuštění popisuje `README.md`.

**Celkově snadné.** Program běžel v prohlížeči napoprvé, jakmile se
přeložil. Kód záložek, grafu ani DSP se neměnil (kromě dvou řádků s typem,
viz níže). Celá změna má asi 160 řádků, z toho 100 v `build.zig`.

| Měřeno na stejném stroji | Desktop (SDL3) | Web (Chrome) |
|---|---|---|
| Velikost programu, ReleaseSmall | 3,3 MB (+ `libSDL3.so` 4,0 MB) | 2,2 MB `.wasm` + 66 kB `web.js` |
| Velikost programu, Debug | – | 8,6 MB `.wasm` |
| DFT pro N = 4096, ReleaseSmall | 199 ms | 302 ms |
| DFT pro N = 4096, Debug | 562 ms | 547 ms |
| FFT pro N = 4096, Debug | 1,2 ms | pod 1 ms |

Čísla ve všech záložkách se shodují s desktopem (koeficienty filtrů,
chyba zpětné FFT 7,1·10⁻¹⁴ pro N = 4096, hodnoty v popiscích u kurzoru).
Kus `.wasm` tvoří písmo Inter (2 × 340 kB).

### Co šlo snadno

- **Abstrakce `dvui.App`.** Program nemá vlastní hlavní smyčku, jen dodává
  `startFn`, `initFn`, `frameFn` a `deinitFn`. Webový backend je volá
  stejně jako SDL3, takže `main.zig` zůstal skoro beze změny.
- **Sestavení.** Do `build.zig` stačilo načíst DVUI podruhé, s jinými
  volbami (`.backend = .web`, cíl `wasm32-freestanding`). Obě instance
  existují vedle sebe a desktop se nijak nezměnil. Krok `zig build web`
  je inspirovaný funkcí `addWebExample` v `build.zig` DVUI: `.wasm` bez
  vstupního bodu (`entry = .disabled`), `web.js` z DVUI a `index.html`,
  do kterého nástroj `cacheBuster` z DVUI doplní otisk souborů (prohlížeč
  pak po novém sestavení nepoužije starou verzi z mezipaměti).
- **Žádné nové stahování.** Webový backend nepotřebuje SDL3 ani jiné
  balíčky, používá stb_truetype a stb_image přibalené v DVUI. Webovou verzi
  jde sestavit i na stroji bez SDL3.
- **Křížový překlad je v Zigu samozřejmost.** Žádný další překladač ani
  nástroj (v Rustu `rustup target add`, `wasm-bindgen`, `trunk`).
- **Ovládání.** Posuvníky, psaní čísel, rozbalovací seznamy, tažení
  a přibližování grafů, dvojklik i popisek u kurzoru fungují stejně jako
  na desktopu. `web.js` volá u kolečka nad plátnem `preventDefault()`,
  takže Ctrl + kolečko přibližuje graf a nezvětší celou stránku. Na displeji
  s vysokým rozlišením (devicePixelRatio 2) je vše ostré.

### Co bylo potřeba změnit

- **`usize` má ve WebAssembly 32 bitů.** Exponent délky FFT měl typ `u6`,
  aby šel použít jako posun v `@as(usize, 1) << exponent`. Pro 64bitový
  `usize` musí být posun `u6`, pro 32bitový `u5` – Zig typ posunu kontroluje
  přesně a kód se nepřeložil. Oprava: `std.math.Log2Int(usize)`, typ
  odvozený z šířky `usize`. Chyba se ukázala až při překladu pro jiný cíl;
  přesná kontrola je tu výhoda (v Rustu je posun libovolným celým číslem
  a přetečení se hlídá až za běhu).
- **Logování.** Naše `logFn` píše přes `std.Io` na standardní výstup a čte
  `LOG_LEVEL` z prostředí; ve `wasm32-freestanding` nic z toho není a
  standardní knihovna se ani nepřeloží (chybí `getrandom`, `IOV_MAX`).
  Na webu se proto za překladu (`builtin.cpu.arch.isWasm()`) použije
  `dvui.App.logFn`, která píše do konzole prohlížeče. Úroveň je pevně
  `info`: `logFn` z DVUI úrovně nefiltruje a s úrovní `debug` by konzoli
  zahltily zprávy z každého snímku. Protože Zig překládá jen použitý kód,
  stačila podmínka v `std_options`; vlastní `logFn` se pro web vůbec
  nepřekládá.
- **`index.html`.** Upravená kopie z DVUI: český titulek, `lang="cs"`
  a jméno našeho `.wasm`.

### Co funguje hůř

- **Měření času po milisekundách.** Webový backend DVUI vrací v `nanoTime`
  hodnotu `performance.now()` oříznutou na celé milisekundy. Doba FFT
  vycházela 0 nebo přesně 1000 µs. Na webu se proto ukazuje v celých ms
  („pod 1 ms“) s poznámkou. Opravit by to šlo jen v DVUI (`web.zig`).
- **Rychlost.** Výpočty jsou v release asi 1,5× pomalejší než nativně
  (WebAssembly bez SIMD, jedno vlákno). Pro učební program to nevadí,
  DFT pro N = 4096 trvá 0,3 s.
- **Mírně jiné vykreslení textu.** Web používá stb_truetype, desktop
  FreeType. Šířky textu se nepatrně liší, takže dlouhé poznámky se jinde
  zalomí a grafy mají o pixel jinou velikost. Čísla v popiscích u kurzoru
  se proto pro stejné místo obrazovky liší v posledních platných číslicích
  (souřadnice kurzoru, ne výpočet); u bodů křivek jsou stejná.
- **`LOG_LEVEL` není.** Úroveň logu se dá změnit jen novým překladem.
- **Nutný HTTP server.** Prohlížeč z `file://` WebAssembly nenačte.
  DVUI přibaluje malý server (`zig build serve-web`, port 8080), servíruje
  ale jen tři soubory (`favicon.ico` vrací 404, což nevadí).

Nic nezůstalo nefunkční.

### Srovnání s Rustem (jen pro kontext, neověřeno)

Rust verzi jsme neměnili. eframe webový běh podporuje (`eframe::WebRunner`
přes `wasm-bindgen`), takže by šlo o podobný rozsah práce, ale s jinými
překážkami:

- Cíl `wasm32-unknown-unknown` a k tomu nástroje `wasm-bindgen-cli` nebo
  `trunk`; navíc crates `wasm-bindgen`, `wasm-bindgen-futures`, `web-sys`
  – tedy rozšíření seznamu povolených závislostí.
- Zvlášť vstupní bod pro web (`#[cfg(target_arch = "wasm32")]`), protože
  `fn main` s `eframe::run_native` tam nefunguje.
- `std::time::Instant` na `wasm32-unknown-unknown` za běhu spadne, měření
  doby transformace by potřebovalo jiné hodiny (např. crate `web-time`).
  Zig s DVUI se tomu vyhnul díky `nanoTime` backendu, i když s horší
  přesností.
- Logování přes `tracing-subscriber` a `tracing-appender` (soubor) by se
  muselo nahradit výstupem do konzole a `color-eyre` by na webu ztratil
  smysl.

Zig tu vychází jednodušeji hlavně díky vestavěnému křížovému překladu
a tomu, že webový backend DVUI je hotový včetně JavaScriptu; Rust
by výměnou za víc nástrojů dal lepší napojení na API prohlížeče.
