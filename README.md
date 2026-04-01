# 🧹 Translation Table Mapper

Load translation data from a CSV file to that translations may be
served based on a translation key.

This library does not provide LLM or online automated translation of text.

# 📝 Usage

Tokenise your text into words and use `translator.translate("FIRST_NAME")` to
retrieve a translation of a keyword.

```zig
    const Translation = @import("translation").Translation;

    pub fn main() void {
        // Initialise a translator with a data file
        var translator: Translation = .empty;
        defer translator.deinit(allocator);
        try translator.loadTranslationData(allocator, "keys,en,el\nBREAD,bread,ἄρτος\n");

        try std.debug.assert(translator.maps.contains(Lang.english));

        translator.setLanguage(.english);
        std.log.info("FIRST_NAME={s}", .{translator.translate("FIRST_NAME")});
    }
```

## TODO

Store language information based on ISO 639 language and ISO 3166 country
information.

## 📨 Contributing

Contributions under the MIT license are welcome. Consider raising an issue
first to discuss the proposed change.

## 🔒 License

This code is released under the terms of the MIT license. This
code is useful for my purposes. No warrantee is given or implied
that this library will be suitable for your purpose and no warantee
is given or implied that this code is free from defects.
