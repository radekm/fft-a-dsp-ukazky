# AGENTS.md – pravidla projektu

Pravidla pro každého (člověka i AI agenta), kdo v tomto repozitáři pracuje.
Před začátkem práce si přečti tento soubor a `PLAN.md`.

## Jazyk

- Komunikace s autorem projektu: pouze česky.
- Zdrojový kód (identifikátory, názvy souborů, commit zprávy): anglicky.
- Komentáře ve zdrojovém kódu: česky.
- Dokumentace (`README.md`, `PLAN.md`, `docs/`): česky.
- Texty v uživatelském rozhraní (popisky, tlačítka, osy grafů): česky.

## Když si nejsi jistý

- Raději se zeptej autora, než abys hádal.
- Nepřidávej žádnou crate ani feature, která není v seznamu níže. Pokud by se
  nějaká hodila, napiš proč a počkej na povolení. Po povolení ji doplň sem.

## Technologie

- Jazyk: Rust (edice 2024, stabilní toolchain, minimálně 1.95).
- GUI: egui přes eframe (backend glow), grafy přes egui_plot.
- Chyby: color-eyre. Logování: tracing.
- Cílová platforma: nativní desktopová aplikace.

## Povolené crates a jejich features

Do `Cargo.toml` se zapisují přesně takto (přesné verze, jen uvedené features):

```toml
color-eyre = "=0.6.5"
time = { version = "=0.3.55", default-features = false, features = ["formatting", "macros", "parsing"] }
rust_decimal = { version = "=1.43.0", default-features = false, features = ["macros", "std"] }
tokio = { version = "=1.54.1", default-features = false, features = ["rt-multi-thread", "net", "macros"] }
tracing = "=0.1.44"
tracing-subscriber = { version = "=0.3.23", features = ["json"] }
tracing-appender = "=0.2.5"
tracing-error = "=0.2.1"
egui = { version = "=0.37.0", default-features = false, features = ["default_fonts"] }
eframe = { version = "=0.37.0", default-features = false, features = ["glow"] }
egui_plot = { version = "=0.38.0", default-features = false }
```

- Do `Cargo.toml` se přidá jen to, co kód opravdu používá; seznam říká, co je
  povoleno, ne co je povinné.
- Cokoli jiného (včetně `rustfft`, `num-complex`, `cpal`, `hound`, `serde`)
  i jakákoli další feature je zakázané, dokud to autor výslovně nepovolí.
  Platí to i pro `dev-dependencies` a `build-dependencies`.

## Zásady pro kód

- FFT, DFT, okna, filtry a komplexní čísla jsou vlastní implementace.
  Cílem je čitelnost a pochopení, ne maximální rychlost.
- Výpočty DSP (`src/dsp/`) nesmí záviset na egui. UI (`src/ui/`) jen volá DSP
  a kreslí výsledky.
- Každý netriviální algoritmus má český komentář, který vysvětluje, co a proč
  se děje (ideálně s odkazem na vzorec).
- Žádný `unsafe` kód.
- Jen syntetické signály; práce se zvukem (mikrofon, přehrávání, WAV) není
  součástí první verze.

## Kontrola před odevzdáním

Každá změna musí projít:

```
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```

- DSP funkce mají jednotkové testy (např. FFT proti pomalé DFT, FFT a zpětná
  FFT vrátí původní signál, spektrum sinusovky má špičku ve správném binu).

## Postup práce

- Pracuje se po fázích podle `PLAN.md`; po dokončení fáze se v plánu odškrtne.
- Změna rozsahu nebo pravidel se nejdřív domluví s autorem a zapíše do
  `PLAN.md` nebo sem.
- Malé, srozumitelné commity.
