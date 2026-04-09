/// Load translation data from a CSV, and serve text strings from either the
/// default language the user requested language.
pub const Translation = @This();

maps: std.AutoHashMapUnmanaged(Lang, std.StringHashMapUnmanaged([]const u8)) = .empty,
current: ?std.StringHashMapUnmanaged([]const u8) = .empty,
data: std.ArrayListUnmanaged([]const u8) = .empty,

pub const empty: @This() = .{
    .maps = .empty,
    .data = .empty,
    .current = .empty,
};

pub fn deinit(self: *Translation, allocator: Allocator) void {
    var i = self.maps.iterator();
    while (i.next()) |map| {
        map.value_ptr.deinit(allocator);
    }
    self.maps.deinit(allocator);
    for (self.data.items) |*item| {
        allocator.free(item.*);
    }
    self.data.deinit(allocator);
    self.* = undefined;
}

/// Each colum represents a langauge in the `lang.Lang` enum. The header row
/// contans the language code (defined by the enum), and every subsequent row
/// should have the same number of columns as the header row.
pub fn loadTranslationData(
    self: *Translation,
    allocator: Allocator,
    tdata: []const u8,
) Allocator.Error!void {
    // Take a copy of the CSV data, and hold it in our list of CSV Data files.
    const data = try allocator.dupe(u8, tdata);
    try self.data.append(allocator, data);

    var headers: std.ArrayListUnmanaged(*std.StringHashMapUnmanaged([]const u8)) = .empty;
    defer headers.deinit(allocator);
    var i = CsvReader{ .data = data };

    var col: usize = 0;
    var line: usize = 0;
    while (true) {
        // Read header
        switch (i.next()) {
            .eol => {
                line += 1;
                break;
            },
            .eof => {
                err("loadTranslationData has no row data. Line: {d}", .{line});
                return;
            },
            .field => {
                col += 1;
                if (col == 1) continue; // Skip unused first cell
                const lr: Lang = Lang.parse_code(i.value);
                if (lr == .unknown) {
                    err("loadTranslationData has invalid languge code: '{s}'", .{i.value});
                    return;
                }
                const entry = try self.maps.getOrPut(allocator, lr);
                if (!entry.found_existing) {
                    entry.key_ptr.* = lr;
                    entry.value_ptr.* = .empty;
                }
                try headers.append(allocator, self.maps.getPtr(lr).?);
            },
        }
    }
    if (headers.items.len == 0) {
        err("loadTranslationData found no language data. Line: {d}", .{line});
        return;
    }

    while (true) {
        // Read rows
        switch (i.next()) {
            .eof => {
                return;
            },
            .eol => {
                line += 1;
                continue;
            },
            .field => {
                const key = i.value;
                col = 0;
                var n: Token = .eof;
                while (col < headers.items.len) : (col += 1) {
                    n = i.next();
                    if (n == .field) {
                        const entry = try headers.items[col].*.getOrPut(allocator, key);
                        if (!entry.found_existing)
                            entry.key_ptr.* = key;
                        entry.value_ptr.* = i.value;
                    } else if (n == .eol or n == .eof) {
                        // Handle case where last column(s) are empty
                        break;
                    } else {
                        err("loadTranslationData has unexpected token {s} on row {d}.", .{ @tagName(n), i.row });
                        return;
                    }
                }
                if (n == .eof) return;
                if (n == .eol) continue;
                // Next should be eol or eof
                if (i.next() == .field) {
                    err("loadTranslationData has too many entries on row {d} line {d}.", .{ i.row, line });
                    return;
                }
            },
        }
    }
}

/// Specify the preferred language that `translate()` should return.
pub fn setLanguage(self: *Translation, language: Lang) void {
    if (self.maps.contains(language)) {
        self.current = self.maps.get(language).?;
        return;
    }
    self.current = null;
}

/// Return the localised version of a key in the currently selected language.
/// Specify the currently selected language using `setLanguage()`.
pub fn translate(self: *Translation, key: []const u8) []const u8 {
    if (self.current) |current| {
        if (current.get(key)) |value| {
            return value;
        }
    }
    if (self.maps.get(Lang.english)) |english| {
        if (english.get(key)) |value| {
            return value;
        }
    }
    return key;
}

test "translator" {
    const allocator = std.testing.allocator;
    {
        var translator: Translation = .empty;
        defer translator.deinit(allocator);
        try translator.loadTranslationData(allocator, "keys,en,el\nBREAD,bread,ἄρτος\n");

        try expect(translator.maps.contains(Lang.english));
        try expect(!translator.maps.contains(Lang.hebrew));
        try expect(translator.maps.contains(Lang.greek));

        translator.setLanguage(.english);
        try expectEqualStrings("bread", translator.translate("BREAD"));
        translator.setLanguage(.greek);
        try expectEqualStrings("ἄρτος", translator.translate("BREAD"));
    }
    {
        var translator: Translation = .empty;
        defer translator.deinit(allocator);
        try translator.loadTranslationData(allocator,
            \\keys,en,el
            \\VERB,Verb,ῥῆμα
            \\NOUN,Noun,ὄνομα
            \\ADJECTIVE,Adjective,ἐπὶθετον
            \\ADVERB,Adverb,ἐπίρρημα
        );
        translator.setLanguage(.english);
        try expectEqualStrings("Noun", translator.translate("NOUN"));
        translator.setLanguage(.greek);
        try expectEqualStrings("ὄνομα", translator.translate("NOUN"));
    }
    {
        var translator: Translation = .empty;
        defer translator.deinit(allocator);
        try translator.loadTranslationData(allocator,
            \\keys,en,es,zh_TW,ko,Uk
            \\NONE,,,,,
            \\APPLE,a,a,a,a,a
            \\PEAR,a,a,a
            \\COFFEE,a,a,a,a,a
        );
        try expectEqual(5, translator.maps.count());
    }
}

test "ammend_translation_data" {
    const allocator = std.testing.allocator;
    var translator: Translation = .empty;
    defer translator.deinit(allocator);

    try translator.loadTranslationData(allocator,
        \\keys,en,es
        \\NONE,,
        \\APPLE,a,a
        \\PEAR,p,p
    );
    try expectEqual(2, translator.maps.count());
    try expect(!translator.maps.contains(Lang.chinese));
    try expect(translator.maps.contains(Lang.english));
    translator.setLanguage(Lang.english);
    try expectEqual(3, translator.current.?.count());
    try expectEqualStrings("a", translator.translate("APPLE"));
    try expectEqualStrings("p", translator.translate("PEAR"));
    try expectEqualStrings("COFFEE", translator.translate("COFFEE"));
    translator.setLanguage(Lang.hebrew);
    try expectEqualStrings("a", translator.translate("APPLE"));

    try translator.loadTranslationData(allocator,
        \\keys,en,es,zh_TW
        \\PEAR,pear,pearo,水果
        \\COFFEE,coffee,cafe,咖啡
    );
    if (false) {
        try expectEqual(3, translator.maps.count());
        translator.setLanguage(Lang.english);
        try expect(translator.maps.contains(Lang.chinese));
        try expect(translator.maps.contains(Lang.english));
        try expectEqual(4, translator.current.?.count());
        try expectEqualStrings("a", translator.translate("APPLE"));
        try expectEqualStrings("pear", translator.translate("PEAR"));
        try expectEqualStrings("coffee", translator.translate("COFFEE"));
    }
}

test "translator_with_cr" {
    const allocator = std.testing.allocator;
    {
        var translator: Translation = .empty;
        defer translator.deinit(allocator);
        try translator.loadTranslationData(allocator, "keys,en,el\nBREAD,\"bread\nloaf\",ἄρτος\n");
        try expect(translator.maps.contains(Lang.english));
        try expect(translator.maps.contains(Lang.greek));
        translator.setLanguage(.english);
        try expectEqualStrings("bread\nloaf", translator.translate("BREAD"));
        translator.setLanguage(.greek);
        try expectEqualStrings("ἄρτος", translator.translate("BREAD"));
    }

    {
        var translator: Translation = .empty;
        defer translator.deinit(allocator);
        try translator.loadTranslationData(allocator, "keys,en,el\nBREAD,bread\\nloaf,ἄρτος\n");
        try expect(translator.maps.contains(Lang.english));
        try expect(translator.maps.contains(Lang.greek));
        translator.setLanguage(.english);
        try expectEqualStrings("bread\\nloaf", translator.translate("BREAD"));
        translator.setLanguage(.greek);
        try expectEqualStrings("ἄρτος", translator.translate("BREAD"));
    }

    {
        var translator: Translation = .empty;
        defer translator.deinit(allocator);
        try translator.loadTranslationData(allocator, "keys,en,el\nBREAD,\"bread\\nloaf\",ἄρτος\n");
        try expect(translator.maps.contains(Lang.english));
        try expect(translator.maps.contains(Lang.greek));
        translator.setLanguage(.english);
        try expectEqualStrings("bread\\nloaf", translator.translate("BREAD"));
        translator.setLanguage(.greek);
        try expectEqualStrings("ἄρτος", translator.translate("BREAD"));
    }
}

const std = @import("std");
const err = std.log.err;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const praxis = @import("praxis");
const Lang = praxis.Lang;
const CsvReader = @import("CsvReader.zig");
const Token = CsvReader.Token;
