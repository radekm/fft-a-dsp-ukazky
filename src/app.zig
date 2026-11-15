//! Stav celé aplikace a přepínání mezi záložkami.

const std = @import("std");
const dvui = @import("dvui");

const ui = @import("ui/ui.zig");
const Tab = ui.Tab;

const log = std.log.scoped(.app);

/// Stav aplikace: vybraná záložka a stav jednotlivých ukázek.
pub const App = struct {
    selected_tab: Tab = .spectrum,

    /// Nakreslí jeden snímek celé aplikace.
    pub fn frame(self: *App) !void {
        // Pozadí okna: DVUI ho samo nekreslí, bez něj by bylo černé.
        var background = dvui.box(@src(), .{}, .{
            .expand = .both,
            .background = true,
            .style = .window,
        });
        defer background.deinit();

        self.tabBar();

        // Zbytek okna patří vybrané záložce.
        var content = dvui.box(@src(), .{}, .{
            .expand = .both,
            .padding = .all(8),
        });
        defer content.deinit();

        switch (self.selected_tab) {
            .spectrum, .windows, .sampling, .filters => {
                dvui.label(@src(), "Záložka „{s}“ se teprve přepisuje.", .{self.selected_tab.title()}, .{});
            },
        }
    }

    /// Horní lišta se záložkami.
    fn tabBar(self: *App) void {
        var tabs = dvui.tabs(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer tabs.deinit();

        const previous_tab = self.selected_tab;
        for (ui.all_tabs, 0..) |tab, index| {
            if (tabs.addTabLabel(self.selected_tab == tab, tab.title(), .{ .id_extra = index })) {
                self.selected_tab = tab;
            }
        }
        if (self.selected_tab != previous_tab) {
            log.info("tab selected tab={s}", .{@tagName(self.selected_tab)});
        }
    }
};
