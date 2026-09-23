#!/usr/bin/env python3
"""Generated-lexer property test.

Random lexer specs (random regex patterns, some with trailing context or the
skip action) are turned into grammars, generated with bin/nexus, compiled
together into one driver, and run over random inputs. Every token stream is
compared with a reference computed here from the definition of the lexer:
skip spaces/tabs into `pre`, longest match over all rules (ties to the
earlier rule; trailing context counts toward the match), `err` for one
unmatched byte, `eof` at the end. Match lengths come from a
set-of-positions matcher over the random ASTs, independent of the
generator's automaton.

    test/lexfuzz/fuzz.py [--seed N] [--specs N] [--inputs N] [--keep DIR]
"""
import argparse, os, random, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
NEXUS = os.path.join(ROOT, "bin", "nexus")
ALPHA = "abc"
INPUT_ALPHA = "abcd  \n"

class Node:
    def __init__(self, kind, *args): self.kind, self.args = kind, args

def gen(rng, depth=0):
    k = rng.randrange(10) if depth < 3 else 0
    if k <= 3:
        chars = sorted(set(rng.choice(ALPHA + (" " if rng.random() < 0.1 else "")) for _ in range(rng.randrange(1, 3))))
        if rng.random() < 0.15: return Node("neg", chars)
        if rng.random() < 0.05: return Node("any")
        return Node("set", chars)
    if k == 4: return Node("lit", "".join(rng.choice(ALPHA) for _ in range(rng.randrange(2, 4))))
    if k == 5: return Node("cat", [gen(rng, depth + 1) for _ in range(rng.randrange(2, 4))])
    if k == 6: return Node("alt", [gen(rng, depth + 1) for _ in range(rng.randrange(2, 4))])
    if k == 7: return Node("rep", gen(rng, depth + 1), rng.choice(["*", "+", "?"]))
    if k == 8:
        lo = rng.randrange(0, 3); hi = lo + rng.randrange(0, 3)
        return Node("bound", gen(rng, depth + 1), max(lo, 0), max(hi, 1))
    return Node("set", [rng.choice(ALPHA)])

def esc_class(c): return {" ": " ", "]": "\\]", "\\": "\\\\", "^": "\\^", "-": "\\-"}.get(c, c)

def nexus(n):
    if n.kind == "set":
        return "'%s'" % n.args[0][0] if len(n.args[0]) == 1 else "[" + "".join(esc_class(c) for c in n.args[0]) + "]"
    if n.kind == "neg": return "[^" + "".join(esc_class(c) for c in n.args[0]) + "]"
    if n.kind == "any": return "."
    if n.kind == "lit": return "'%s'" % n.args[0]
    if n.kind == "cat": return "(" + " ".join(nexus(x) for x in n.args[0]) + ")"
    if n.kind == "alt": return "(" + " | ".join(nexus(x) for x in n.args[0]) + ")"
    if n.kind == "rep": return "(" + nexus(n.args[0]) + ")" + n.args[1]
    if n.kind == "bound": return "(" + nexus(n.args[0]) + "){%d,%d}" % (n.args[1], n.args[2])

def lengths(n):
    """(min, max) match length; max None = unbounded."""
    if n.kind in ("set", "neg", "any"): return (1, 1)
    if n.kind == "lit": return (len(n.args[0]),) * 2
    if n.kind == "cat":
        lo = hi = 0
        for x in n.args[0]:
            a, b = lengths(x); lo += a; hi = None if hi is None or b is None else hi + b
        return (lo, hi)
    if n.kind == "alt":
        ls = [lengths(x) for x in n.args[0]]
        return (min(a for a, _ in ls), None if any(b is None for _, b in ls) else max(b for _, b in ls))
    if n.kind == "rep":
        a, b = lengths(n.args[0])
        return ({"*": 0, "+": a, "?": 0}[n.args[1]], b if n.args[1] == "?" else (None if b != 0 else 0))
    if n.kind == "bound":
        a, b = lengths(n.args[0])
        return (a * n.args[1], None if b is None else b * n.args[2])

def make_spec(rng):
    rules = []
    for i in range(rng.randrange(1, 6)):
        main = gen(rng)
        rule = {"main": main, "trail": None, "skip": False}
        r = rng.random()
        if r < 0.15:
            rule["trail"] = gen(rng)
        elif r < 0.22:
            rule["skip"] = True
        rules.append(rule)
    return rules

def ends(n, s, starts):
    """Set of positions e such that s[p:e] matches n for some p in starts
    (set-of-positions simulation: linear in the input, no backtracking)."""
    if not starts: return set()
    k = n.kind
    if k in ("set", "neg", "any"):
        ok = (lambda c: c in n.args[0]) if k == "set" else (lambda c: c not in n.args[0]) if k == "neg" else (lambda c: True)
        return {p + 1 for p in starts if p < len(s) and ok(s[p])}
    if k == "lit":
        t = n.args[0]
        return {p + len(t) for p in starts if s.startswith(t, p)}
    if k == "cat":
        cur = set(starts)
        for x in n.args[0]: cur = ends(x, s, cur)
        return cur
    if k == "alt":
        out = set()
        for x in n.args[0]: out |= ends(x, s, starts)
        return out
    if k in ("rep", "bound"):
        sub = n.args[0]
        if k == "rep": lo, hi = {"*": (0, None), "+": (1, None), "?": (0, 1)}[n.args[1]]
        else: lo, hi = n.args[1], n.args[2]
        cur = set(starts)
        for _ in range(lo): cur = ends(sub, s, cur)
        result = set(cur); i = lo
        while hi is None or i < hi:
            cur = ends(sub, s, cur) - set() if cur else set()
            new = result | cur
            if new == result and hi is None: break
            result = new; i += 1
            if not cur: break
        return result

def reference(rules, src):
    """Token stream per the lexer definition: list of (cat, pos, len, pre)."""
    out = []
    p = 0; n = len(src)
    ws_start = p
    while True:
        while p < n and src[p] in " \t": p += 1
        pre = min(p - ws_start, 255)
        if p >= n:
            out.append(("eof", p, 0, pre)); return out
        best = None
        for i, r in enumerate(rules):
            e = ends(r["main"], src, {p})
            if r["trail"] is not None: e = ends(r["trail"], src, e)
            e.discard(p)
            if not e: continue
            L = max(e) - p
            if best is None or L > best[1]: best = (i, L)
        if best is None:
            out.append(("err", p, 1, pre)); p += 1; ws_start = p; continue
        i, L = best
        tok = L
        if rules[i]["trail"] is not None:
            mlen = lengths(rules[i]["main"]); tlen = lengths(rules[i]["trail"])
            tok = mlen[0] if mlen[0] == mlen[1] else L - tlen[0]
        if rules[i]["skip"]:
            p += tok; continue          # skipped bytes count toward pre
        out.append(("t%d" % i, p, tok, pre)); p += tok; ws_start = p

def grammar(rules):
    lines = ["@lexer", "tokens"]
    lines += ["    t%d" % i for i in range(len(rules))] + ["    eof", "    err"]
    for i, r in enumerate(rules):
        pat = nexus(r["main"]) + (" / " + nexus(r["trail"]) if r["trail"] else "")
        lines.append("%s → t%d%s" % (pat, i, ", skip" if r["skip"] else ""))
    lines += [".  → err", "@parser", "top! = ERR → 1", ""]
    return "\n".join(lines)

DRIVER_HEAD = '''const std = @import("std");
'''

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--specs", type=int, default=60)
    ap.add_argument("--inputs", type=int, default=200)
    ap.add_argument("--keep")
    a = ap.parse_args()
    rng = random.Random(a.seed)
    work = a.keep or tempfile.mkdtemp(prefix="lexfuzz.")
    os.makedirs(work, exist_ok=True)
    specs = []; rejected = 0; attempts = 0
    while len(specs) < a.specs:
        attempts += 1
        rules = make_spec(rng)
        k = len(specs)
        d = os.path.join(work, "m%d" % k); os.makedirs(d, exist_ok=True)
        g = os.path.join(d, "g.grammar")
        open(g, "w").write(grammar(rules))
        r = subprocess.run([NEXUS, g, os.path.join(d, "parser.zig")], capture_output=True, text=True)
        if r.returncode != 0:
            msg = r.stderr.strip().splitlines()[-1]
            # Specs the generator rightly rejects (dead rule, empty match,
            # trailing context with no fixed side) are regenerated.
            if not any(s in msg for s in ("can never match", "matches the empty string", "must not match the empty string", "fixed-length", "space or tab", "zero-width")):
                print("unexpected generation error:", msg, "\n" + grammar(rules)); sys.exit(1)
            rejected += 1
            continue
        specs.append(rules)
    inputs = ["".join(rng.choice(INPUT_ALPHA) for _ in range(rng.randrange(0, 24))) for _ in range(a.inputs)]
    open(os.path.join(work, "inputs.txt"), "w").write("\x00".join(inputs))
    # Driver: every module lexes every input.
    drv = [DRIVER_HEAD]
    for k in range(len(specs)): drv.append('const m%d = @import("m%d");\n' % (k, k))
    drv.append('''
fn run(comptime M: type, src: []const u8, w: *std.Io.Writer) !void {
    var lx = M.Lexer.init(src);
    var guard: usize = 0;
    while (guard < 4 * src.len + 8) : (guard += 1) {
        const t = lx.next();
        try w.print("{s}:{d}:{d}:{d} ", .{ @tagName(t.cat), t.pos, t.len, t.pre });
        if (t.cat == .eof) break;
    }
    try w.writeAll("\\n");
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const all = try std.Io.Dir.cwd().readFileAlloc(io, args[1], init.arena.allocator(), .limited(1 << 24));
    var buf: [1 << 16]u8 = undefined;
    var fw = std.Io.File.stdout().writerStreaming(io, &buf);
    const w = &fw.interface;
''')
    for k in range(len(specs)):
        drv.append('    { var it = std.mem.splitScalar(u8, all, 0); while (it.next()) |s| try run(m%d, s, w); }\n' % k)
    drv.append('    try w.flush();\n}\n')
    open(os.path.join(work, "driver.zig"), "w").write("".join(drv))
    cmd = ["zig", "build-exe", "-O", "ReleaseSafe"]
    for k in range(len(specs)): cmd += ["--dep", "m%d" % k]
    cmd += ["-Mroot=driver.zig"] + ["-Mm%d=m%d/parser.zig" % (k, k) for k in range(len(specs))]
    cmd += ["-femit-bin=driver"]
    r = subprocess.run(cmd, cwd=work, capture_output=True, text=True)
    if r.returncode != 0: print(r.stderr[:4000]); sys.exit(1)
    got = subprocess.run([os.path.join(work, "driver"), os.path.join(work, "inputs.txt")], capture_output=True, text=True).stdout.split("\n")
    li = 0; mism = 0; tokens = 0
    for k, rules in enumerate(specs):
        for s in inputs:
            exp = " ".join("%s:%d:%d:%d" % t for t in reference(rules, s)) + " "
            tokens += exp.count(":") // 3
            if got[li] != exp:
                mism += 1
                if mism <= 5:
                    print("MISMATCH spec m%d input %r\n  want %s\n  got  %s\n%s" % (k, s, exp, got[li], grammar(rules)))
            li += 1
    print("lexfuzz: %d specs (%d rejected by the generator), %d inputs, %d streams, %d tokens, %d mismatches"
          % (len(specs), rejected, len(inputs), len(specs) * len(inputs), tokens, mism))
    if not a.keep: shutil.rmtree(work)
    sys.exit(1 if mism else 0)

main()
