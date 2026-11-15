# AGENTS.md – pravidla projektu

Pravidla pro každého (člověka i AI agenta), kdo v tomto repozitáři pracuje.
Před začátkem práce si přečti tento soubor a `PLAN.md`.

Program se přepisuje z Rustu do Zigu. Původní verze v Rustu je v adresáři
`last-rust-version/` (a v gitu pod tagem `last-rust-version`) a slouží jako
předloha. Pravidla níže platí pro verzi v Zigu v kořeni repozitáře.

## Jazyk

- Komunikace s autorem projektu: pouze česky.
- Zdrojový kód (identifikátory, názvy souborů, commit zprávy): anglicky.
- Komentáře ve zdrojovém kódu: česky.
- Dokumentace (`README.md`, `PLAN.md`, `docs/`, `PREPIS-DO-ZIGU-Z-RUSTU.md`):
  česky.
- Texty v uživatelském rozhraní (popisky, tlačítka, osy grafů): česky.

## Když si nejsi jistý

- Raději se zeptej autora, než abys hádal.
- Nepřidávej žádnou závislost, která není v seznamu níže. Pokud by se nějaká
  hodila, napiš proč a počkej na povolení. Po povolení ji doplň sem.

## Technologie

- Jazyk: Zig 0.17.1.
- GUI: DVUI s backendem SDL3 (desktop) a webovým backendem (prohlížeč).
- Grafy: vlastní widget nad kreslicími funkcemi DVUI (`src/ui/plot.zig`).
- Chyby: chybové typy Zigu (`error{...}`, `try`, `errdefer`).
- Logování: `std.log` na standardní výstup (na webu do konzole prohlížeče).
- Písmo: Inter (běžný a tučný řez), vložené do programu přes `@embedFile`.
- Cílová platforma: nativní desktopová aplikace a WebAssembly v prohlížeči
  (`wasm32-freestanding`, krok `zig build web`). Desktopová verze je hlavní,
  webová ji nesmí rozbít.

## Povolené závislosti

- `dvui` v `build.zig.zon`, připnutý na commit
  `485a1ed8d155fc38759713dad3f039de213e46cc`, s volbami
  `.backend = .sdl3` a `.@"tree-sitter" = false`.
- Webová verze: tentýž `dvui` (stejný commit) ještě jednou, s volbami
  `.backend = .web` a `.@"tree-sitter" = false`, pro cíl
  `wasm32-freestanding`. Volby pro desktop zůstávají beze změny.
- Soubory, které DVUI pro web přibaluje: `src/backends/web.js` (instaluje
  se beze změny), `src/backends/index.html` (náš upravený `web/index.html`),
  `src/cacheBuster.zig` (doplní otisk souborů do `index.html`)
  a `tools/serve_web_demo.zig` (malý HTTP server pro `zig build serve-web`).
- Balíčky, které DVUI s těmito volbami samo stáhne (např. `translate_c`,
  `freetype`, `svg2tvg`). Neuvádějí se v našem `build.zig.zon`.
- Systémová knihovna SDL3, linkovaná dynamicky. `build.zig` zapíná systémové
  SDL3 jako výchozí (odpovídá `zig build -fsys=sdl3`). SDL3 se nepřekládá ze
  zdrojů.
- Jen na macOS: systémový framework AppKit a knihovna `libobjc`. Potřebuje
  je soubor `macos_monitor.m` z DVUI, který je sám nepřilinkuje (spoléhá na
  SDL3 přeložené ze zdrojů).
- Písmo Inter v `src/fonts/` (licence SIL OFL 1.1, soubor `src/fonts/OFL.txt`).
- Cokoli jiného (další balíčky Zigu, knihovny v C, další systémové knihovny)
  je zakázané, dokud to autor výslovně nepovolí. Zakázané je i měnit volby
  DVUI nebo verzi DVUI.

## Zásady pro kód

- FFT, DFT, okna, filtry a komplexní čísla jsou vlastní implementace.
  Cílem je čitelnost a pochopení, ne maximální rychlost.
- Výpočty DSP (`src/dsp/`) nesmí záviset na DVUI. UI (`src/ui/`) jen volá DSP
  a kreslí výsledky.
- Každý netriviální algoritmus má český komentář, který vysvětluje, co a proč
  se děje (ideálně s odkazem na vzorec).
- Chování se drží Rust verze: stejné záložky, ovládací prvky, výchozí hodnoty
  a vypočtená čísla. Odchylku je třeba domluvit s autorem.
- Žádné nebezpečné konstrukce bez nutnosti: v našem kódu žádné `@ptrCast`,
  `@alignCast`, `@intFromPtr`, `@ptrFromInt` ani `undefined` u hodnot, které
  se čtou. Kde je to nutné kvůli API DVUI, je u toho komentář proč.
- Paměť: alokátor se předává explicitně. Každá alokace má jasného vlastníka
  a uvolnění (`defer`/`errdefer`). Testy používají `std.testing.allocator`,
  který hlídá úniky paměti.
- Logování přes `std.log` se scope (`std.log.scoped(.dsp)` apod.). Zpráva je
  krátký anglický text. Proměnné hodnoty jsou na konci zprávy ve tvaru
  `klic=hodnota`, aby šly snadno vyhledat:
  - Správně: `log.info("spectrum computed fft_size={d} sample_rate_hz={d}", .{ fft_size, sample_rate_hz })`
  - Špatně: `log.info("computed spectrum of {d} samples", .{fft_size})`
- Log jde na standardní výstup, na webu do konzole prohlížeče
  (`dvui.App.logFn`). Události, které mohou nastat v každém snímku,
  mají úroveň `debug`.
- Jen syntetické signály; práce se zvukem (mikrofon, přehrávání, WAV) není
  součástí programu.

## Kontrola před odevzdáním

Každá změna musí projít:

```
zig fmt --check build.zig build.zig.zon src
zig build
zig build test
zig build web
```

- DSP funkce mají jednotkové testy (např. FFT proti pomalé DFT, FFT a zpětná
  FFT vrátí původní signál, spektrum sinusovky má špičku ve správném binu).
  Testy z Rust verze se převádějí všechny.

## Postup práce

- Pracuje se po fázích podle `PLAN.md`; po dokončení fáze se v plánu odškrtne.
- Změna rozsahu nebo pravidel se nejdřív domluví s autorem a zapíše do
  `PLAN.md` nebo sem.
- Malé, srozumitelné commity.
- Během přepisu se do `PREPIS-DO-ZIGU-Z-RUSTU.md` zapisuje, co šlo v Zigu
  napsat lépe než v Rustu, co hůř a co nešlo vůbec.
- Dokumentace (`README.md`, `docs/`, učebnice) se aktualizuje až po dokončení
  přepisu a na pokyn autora.
