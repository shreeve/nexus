//! The lexer generated from zig.grammar against std.zig.Tokenizer of the
//! Zig that runs the test: the same tokens (tag by name, start, end), up to
//! and including eof, on the inputs of std.zig.Tokenizer's own tests, on
//! line-ending, byte-order-mark and control-byte cases, and on random
//! inputs. grammars/zig/compare-tokens runs the same comparison over any
//! corpus.
const std = @import("std");
const parser = @import("parser.zig");

/// Fails, printing the input and the first difference, unless both lexers
/// give `src` the same token stream. The generated lexer starts as the
/// lang module starts it (after a byte order mark) and runs without the
/// lang Lexer's own token rewriting.
fn expectSameTokens(src: [:0]const u8) !void {
    var lx = parser.Lexer.init(src).base;
    var tz = std.zig.Tokenizer.init(src);
    var n: usize = 0;
    while (true) : (n += 1) {
        const a = lx.next();
        const b = tz.next();
        const same = std.mem.eql(u8, @tagName(a.cat), @tagName(b.tag)) and
            a.pos == b.loc.start and @as(usize, a.pos) + a.len == b.loc.end;
        if (!same) {
            std.debug.print("input {f}: token {d}: nexus {t} {d} {d}, std {t} {d} {d}\n", .{
                std.zig.fmtString(src), n, a.cat, a.pos, a.pos + a.len, b.tag, b.loc.start, b.loc.end,
            });
            return error.TestUnexpectedResult;
        }
        if (b.tag == .eof) return;
    }
}

test "the inputs of std.zig.Tokenizer's tests" {
    for (tokenizer_test_inputs) |src| try expectSameTokens(src);
}

test "line endings, byte order marks, control bytes" {
    for (edge_inputs) |src| try expectSameTokens(src);
    // Every byte, in every position a token can hold it.
    const forms = [_][]const u8{
        "// a@b\nx", "/// a@b\nx",  "//! a@b\nx",   "////@b\nx",  "\\\\ a@b\nx",   "\"a@b\"\nx",
        "'a@b'\nx",  "@\"a@b\"\nx", "\"a\\@b\"\nx", "'a\\@b'\nx", "@\"a\\@b\"\nx", "@@x\ny",
        "\\@x\ny",   "x@y\nz",      "1@2\n3",       "//@\nx",     "///@\nx",       "1e@",
    };
    var buf: [32]u8 = undefined;
    for (forms) |form| {
        const at = std.mem.findScalar(u8, form, '@').?;
        for (0..256) |c| {
            for ([_]bool{ false, true }) |cut| {
                // The byte, then the rest of the form, or the end of input.
                const len = if (cut) at + 1 else form.len;
                @memcpy(buf[0..form.len], form);
                buf[at] = @intCast(c);
                buf[len] = 0;
                try expectSameTokens(buf[0..len :0]);
            }
        }
    }
}

const fragment_bytes = "/\\\"'@\n\r\t \x00\x7f#09eEpP+-._xa*%|=!<>&^~?:;,()[]{}";

test "random inputs" {
    var prng: std.Random.DefaultPrng = .init(0x5eed);
    const rand = prng.random();
    var buf: [256]u8 = undefined;
    for (0..20_000) |k| {
        const len = rand.uintLessThan(usize, buf.len);
        for (buf[0..len]) |*c| {
            // std.zig.Tokenizer's fuzz test weights, and token fragments.
            c.* = if (k % 2 == 0) switch (rand.uintLessThan(u8, 27)) {
                0 => rand.int(u8),
                1...4 => rand.intRangeAtMost(u8, 0x20, 0x7e),
                5 => rand.intRangeAtMost(u8, 0x00, 0x1f),
                6...11 => 0,
                12...17 => ' ',
                18...23 => rand.intRangeAtMost(u8, '\t', '\n'),
                else => '\r',
            } else fragment_bytes[rand.uintLessThan(usize, fragment_bytes.len)];
        }
        buf[len] = 0;
        try expectSameTokens(buf[0..len :0]);
    }
}

test "a token over 65535 bytes is an err token over its first 65535" {
    const gpa = std.testing.allocator;
    for ([_]usize{ 65535, 65536 }) |n| {
        const src = try gpa.alloc(u8, n + 3);
        defer gpa.free(src);
        src[0] = '"';
        @memset(src[1 .. n - 1], 'a');
        src[n - 1] = '"';
        @memcpy(src[n..], " x;");
        var lx = parser.Lexer.init(src).base;
        const t = lx.next();
        try std.testing.expectEqual(@as(u32, 0), t.pos);
        try std.testing.expectEqual(if (n == 65535) parser.TokenCat.string_literal else .err, t.cat);
        try std.testing.expectEqual(@as(u16, 65535), t.len);
        // The scan goes on after the whole literal, in step with std.zig.Tokenizer.
        try std.testing.expectEqual(n, lx.pos);
        const x = lx.next();
        try std.testing.expectEqual(parser.TokenCat.identifier, x.cat);
        try std.testing.expectEqual(@as(u32, @intCast(n + 1)), x.pos);
    }
}

const edge_inputs = [_][:0]const u8{
    "\r\n",             "\r",                       "\r\r\n",                           "x\r\ny\rz\n",
    "// c\r\nx",        "// c\r",                   "// c\r\r\nx",                      "// c\rx\ny",
    "/// d\r\nx",       "/// d\r",                  "/// d\r\r\nx",                     "///\r\n///\r\n",
    "//! e\r\nx",       "//! e\r",                  "//!\r\r\n",                        "////\r\n",
    "\\\\ m\r\nx",      "\\\\ m\r",                 "\\\\\r\r\n",                       "\\\\\r\n\\\\\r\n;",
    "\"s\r\"",          "'\r'",                     "@\"\r\"",                          "\"a\\\r\"",
    "\xef\xbb\xbf",     "\xef\xbb\xbf\xef\xbb\xbf", "\xef\xbb\xbf\nconst x = 1;",       " \xef\xbb\xbf",
    "\xef\xbb\xbf// c", "\xef\xbb\xbf/// d",        "\xef\xbb",                         "\xef",
    "\xef\xbb\xbf\x00", "x\xef\xbb\xbf",            "\xef\xbb\xbf\r\nconst x = 1;\r\n", "\tpub\tswitch\t",
    "\x00\x00",         "a\x00b\nc",                "\"\\\x00",                         "'\\\x00",
    "'\\\x00'\nx",      "@\"\\\x00",                "1.\x00",
};

const tokenizer_test_inputs = [_][:0]const u8{
    "test const else",
    \\// line comment
    \\comptime {}
    \\
    ,
    \\[*]u8
    \\[*c]u8
    ,
    \\'\x1b'
    ,
    \\'\x1'
    ,
    \\'
    \\'
    ,
    \\"
    \\"
    ,
    \\'\u{3}'
    ,
    \\'\u{01}'
    ,
    \\'\u{2a}'
    ,
    \\'\u{3f9}'
    ,
    \\'\u{6E09aBc1523}'
    ,
    \\"\u{440}"
    ,
    \\'\u'
    ,
    \\'\u{{'
    ,
    \\'\u{}'
    ,
    \\'\u{s}'
    ,
    \\'\u{2z}'
    ,
    \\'\u{4a'
    ,
    \\'\u0333'
    ,
    \\'\U0333'
    ,
    \\'💩'
    ,
    "a = 4.94065645841246544177e-324;\n",
    "a = 0x1.a827999fcef32p+1022;\n",
    "'c'",
    "#",
    "`",
    "'c",
    "'",
    "''",
    "'\n'",
    "\"\x00\"",
    "`\x00`",
    "//\x00",
    "//\x1f",
    "//\x7f",
    "//\xc2\x80",
    "//\xf4\x8f\xbf\xbf",
    "//\x80",
    "//\xbf",
    "//\xf8",
    "//\xff",
    "//\xc2\xc0",
    "//\xe0",
    "//\xf0",
    "//\xf0\x90\x80\xc0",
    "//\xc2\x84",
    "//\xc2\x85",
    "//\xc2\x86",
    "//\xe2\x80\xa7",
    "//\xe2\x80\xa8",
    "//\xe2\x80\xa9",
    "//\xe2\x80\xaa",
    \\const @"if" = @import("std");
    ,
    "||=",
    "//",
    "// a / b",
    "// /",
    "/// a",
    "///",
    "////",
    "//!",
    "//!!",
    \\    Unexpected,
    \\    // another
    \\    Another,
    ,
    "\xEF\xBB\xBFa;\n",
    "b.*=3;\n",
    "0...9",
    "'0'...'9'",
    "0x00...0x09",
    "0b00...0b11",
    "0o00...0o11",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "1..",
    "0a",
    "9b",
    "1z",
    "1z_1",
    "9z3",
    "0_0",
    "0001",
    "01234567890",
    "012_345_6789_0",
    "0_1_2_3_4_5_6_7_8_9_0",
    "00_",
    "0_0_",
    "0__0",
    "0_0f",
    "0_0_f",
    "0_0_f_00",
    "1_,",
    "0.0",
    "1.0",
    "10.0",
    "0e0",
    "1e0",
    "1e100",
    "1.0e100",
    "1.0e+100",
    "1.0e-100",
    "1_0_0_0.0_0_0_0_0_1e1_0_0_0",
    "1.",
    "1e",
    "1.e100",
    "1.0e1f0",
    "1.0p100",
    "1.0p-100",
    "1.0p1f0",
    "1.0_,",
    "1_.0",
    "1._",
    "1.a",
    "1.z",
    "1._0",
    "1.+",
    "1._+",
    "1._e",
    "1.0e",
    "1.0e,",
    "1.0e_",
    "1.0e+_",
    "1.0e-_",
    "1.0e0_+",
    "0b0",
    "0b1",
    "0b2",
    "0b3",
    "0b4",
    "0b5",
    "0b6",
    "0b7",
    "0b8",
    "0b9",
    "0ba",
    "0bb",
    "0bc",
    "0bd",
    "0be",
    "0bf",
    "0bz",
    "0b0000_0000",
    "0b1111_1111",
    "0b10_10_10_10",
    "0b0_1_0_1_0_1_0_1",
    "0b1.",
    "0b1.0",
    "0B0",
    "0b_",
    "0b_0",
    "0b1_",
    "0b0__1",
    "0b0_1_",
    "0b1e",
    "0b1p",
    "0b1e0",
    "0b1p0",
    "0b1_,",
    "0o0",
    "0o1",
    "0o2",
    "0o3",
    "0o4",
    "0o5",
    "0o6",
    "0o7",
    "0o8",
    "0o9",
    "0oa",
    "0ob",
    "0oc",
    "0od",
    "0oe",
    "0of",
    "0oz",
    "0o01234567",
    "0o0123_4567",
    "0o01_23_45_67",
    "0o0_1_2_3_4_5_6_7",
    "0o7.",
    "0o7.0",
    "0O0",
    "0o_",
    "0o_0",
    "0o1_",
    "0o0__1",
    "0o0_1_",
    "0o1e",
    "0o1p",
    "0o1e0",
    "0o1p0",
    "0o_,",
    "0x0",
    "0x1",
    "0x2",
    "0x3",
    "0x4",
    "0x5",
    "0x6",
    "0x7",
    "0x8",
    "0x9",
    "0xa",
    "0xb",
    "0xc",
    "0xd",
    "0xe",
    "0xf",
    "0xA",
    "0xB",
    "0xC",
    "0xD",
    "0xE",
    "0xF",
    "0x0z",
    "0xz",
    "0x0123456789ABCDEF",
    "0x0123_4567_89AB_CDEF",
    "0x01_23_45_67_89AB_CDE_F",
    "0x0_1_2_3_4_5_6_7_8_9_A_B_C_D_E_F",
    "0X0",
    "0x_",
    "0x_1",
    "0x1_",
    "0x0__1",
    "0x0_1_",
    "0x_,",
    "0x1.0",
    "0xF.0",
    "0xF.F",
    "0xF.Fp0",
    "0xF.FP0",
    "0x1p0",
    "0xfp0",
    "0x1.0+0xF.0",
    "0x1.",
    "0xF.",
    "0x1.+0xF.",
    "0xff.p10",
    "0x0123456.789ABCDEF",
    "0x0_123_456.789_ABC_DEF",
    "0x0_1_2_3_4_5_6.7_8_9_A_B_C_D_E_F",
    "0x0p0",
    "0x0.0p0",
    "0xff.ffp10",
    "0xff.ffP10",
    "0xffp10",
    "0xff_ff.ff_ffp1_0_0_0",
    "0xf_f_f_f.f_f_f_fp+1_000",
    "0xf_f_f_f.f_f_f_fp-1_00_0",
    "0x1e",
    "0x1e0",
    "0x1p",
    "0xfp0z1",
    "0xff.ffpff",
    "0x0.p",
    "0x0.z",
    "0x0._",
    "0x0_.0",
    "0x0_.0.0",
    "0x0._0",
    "0x0.0_",
    "0x0_p0",
    "0x0_.p0",
    "0x0._p0",
    "0x0.0_p0",
    "0x0._0p0",
    "0x0.0p_0",
    "0x0.0p+_0",
    "0x0.0p-_0",
    "0x0.0p0_",
    "x \\\n;",
    "@()",
    "@0()",
    "\"\\",
    "'\\",
    "'\\u",
    "<<",
    "<<|",
    "<<|=",
    "*",
    "*|",
    "*|=",
    "+",
    "+|",
    "+|=",
    "-",
    "-|",
    "-|=",
    "123 \x00 456",
    "\\\\\x00",
    "\x00",
    "// NUL\x00\n",
    "///\x00\n",
    "/// NUL\x00\n",
    "//\t",
    "// \t",
    "///\t",
    "/// \t",
    "//!\t",
    "//! \t",
    "//\r",
    "// \r",
    "///\r",
    "/// \r",
    "//\r ",
    "// \r ",
    "///\r ",
    "/// \r ",
    "//\r\n",
    "// \r\n",
    "///\r\n",
    "/// \r\n",
    "//!\r",
    "//! \r",
    "//!\r ",
    "//! \r ",
    "//!\r\n",
    "//! \r\n",
    "\\\\\r",
    "\\\\\r ",
    "\\\\ \r",
    "\\\\\t",
    "\\\\\t ",
    "\\\\ \t",
    "\\\\\r\n",
    "\tpub\tswitch\t",
    "\rpub\rswitch\r",
};
