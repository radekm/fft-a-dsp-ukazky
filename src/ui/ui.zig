//! Uživatelské rozhraní: jedna záložka = jeden soubor.

/// Záložky aplikace.
pub const Tab = enum {
    spectrum,
    windows,
    sampling,
    filters,

    /// Český popisek záložky.
    pub fn title(tab: Tab) []const u8 {
        return switch (tab) {
            .spectrum => "Signály a spektrum",
            .windows => "Okna a prosakování",
            .sampling => "Vzorkování a aliasing",
            .filters => "Filtry",
        };
    }
};

/// Všechny záložky v pořadí, v jakém se zobrazují v horní liště.
pub const all_tabs = [_]Tab{ .spectrum, .windows, .sampling, .filters };
