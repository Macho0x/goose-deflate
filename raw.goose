// Raw DEFLATE compressor (RFC 1951).
// One encoder. It writes a single final fixed-Huffman block when that
// encoding is shorter than stored blocks, and stored blocks otherwise.
// Stored blocks hold at most 65535 bytes. Match distances stay within
// 32768. The bytes are not a miniz compression level.

import inflate;

namespace raw;

const HASH_BITS: i64 = 12;
const HASH_SIZE: i64 = 4096;
const WINDOW: i64 = 32768;
const MAX_MATCH: i64 = 258;

struct Bw {
    acc: u64,
    n: i64,
}

fn put(out: u8[>..]&, bw: Bw&, v: u64, k: i64) {
    if k <= 0 { return; }
    let mask = ((1 as u64) << k) - 1;
    bw.acc = bw.acc | ((v & mask) << bw.n);
    bw.n += k;
    while bw.n >= 8 {
        out.push((bw.acc & 0xff) as u8);
        bw.acc = bw.acc >> 8;
        bw.n -= 8;
    }
}

fn flush(out: u8[>..]&, bw: Bw&) {
    if bw.n > 0 {
        out.push((bw.acc & 0xff) as u8);
        bw.acc = 0;
        bw.n = 0;
    }
}

fn rev_bits(code: u32, n: i64) -> u32 {
    var c = code;
    var r: u32 = 0;
    for i in 0..n {
        r = (r << 1) | (c & 1);
        c = c >> 1;
    }
    return r;
}

fn fill_fixed(lbits: u32[288]&, lwidth: i64[288]&, dbits: u32[30]&, dwidth: i64[30]&) {
    for sym in 0..288 {
        var code: i64 = 0;
        var n: i64 = 0;
        if sym <= 143 {
            code = 0x30 + sym;
            n = 8;
        } else if sym <= 255 {
            code = 0x190 + sym - 144;
            n = 9;
        } else if sym <= 279 {
            code = sym - 256;
            n = 7;
        } else {
            code = 0xc0 + sym - 280;
            n = 8;
        }
        lbits[sym] = rev_bits(code as u32, n);
        lwidth[sym] = n;
    }
    for d in 0..30 {
        dbits[d] = rev_bits(d as u32, 5);
        dwidth[d] = 5;
    }
}

fn lit_width(b: u8) -> i64 {
    if b <= 143 { return 8; }
    return 9;
}

fn sym_width(sym: i64) -> i64 {
    if sym <= 143 { return 8; }
    if sym <= 255 { return 9; }
    if sym <= 279 { return 7; }
    return 8;
}

fn code_index(base: i64[:], value: i64) -> i64 {
    var i = 0;
    while i + 1 < base.len && base[i + 1] <= value { i += 1; }
    return i;
}

fn len_pair(length: i64) -> i64, i64, i64 {
    let i = code_index(inflate::LEN_BASE, length);
    return 257 + i, length - inflate::LEN_BASE[i], inflate::LEN_EXTRA[i];
}

fn dist_pair(distance: i64) -> i64, i64, i64 {
    let i = code_index(inflate::DIST_BASE, distance);
    return i, distance - inflate::DIST_BASE[i], inflate::DIST_EXTRA[i];
}

fn length_bits(length: i64) -> i64 {
    let sym, extra, en = len_pair(length);
    if extra < 0 { abort("raw: length"); }
    return sym_width(sym) + en;
}

fn dist_bits(distance: i64) -> i64 {
    let sym, extra, en = dist_pair(distance);
    if sym < 0 || extra < 0 { abort("raw: distance"); }
    return 5 + en;
}

fn span_bits(data: u8[:], pos: i64, n: i64) -> i64 {
    var s = 0;
    for i in 0..n { s += lit_width(data[pos + i]); }
    return s;
}

fn hash3(a: u8, b: u8, c: u8) -> i64 {
    var v: u32 = a;
    v = (v << 8) | b;
    v = (v << 8) | c;
    v = v * 0x1e35a7bd;
    return v >> (32 - HASH_BITS);
}

fn match_len(data: u8[:], from: i64, pos: i64) -> i64 {
    var n = 0;
    var limit = data.len - pos;
    if limit > MAX_MATCH { limit = MAX_MATCH; }
    while n < limit && data[from + n] == data[pos + n] { n += 1; }
    return n;
}

fn clear_head(head: i64[HASH_SIZE]&) {
    for i in 0..HASH_SIZE { head[i] = -1; }
}

// length and distance. distance 0 means one literal at pos.
fn next_match(data: u8[:], pos: i64, head: i64[HASH_SIZE]&) -> i64, i64 {
    if pos + 3 > data.len { return 1, 0; }
    let h = hash3(data[pos], data[pos + 1], data[pos + 2]);
    let prev = head[h];
    head[h] = pos;
    if prev < 0 { return 1, 0; }
    let dist = pos - prev;
    if dist < 1 || dist > WINDOW { return 1, 0; }
    let n = match_len(data, prev, pos);
    if n < 3 { return 1, 0; }
    if length_bits(n) + dist_bits(dist) >= span_bits(data, pos, n) { return 1, 0; }
    return n, dist;
}

fn count_bits(data: u8[:]) -> i64 {
    var head: i64[HASH_SIZE] = [0; HASH_SIZE];
    clear_head(head);
    var bits = 10;
    var pos = 0;
    while pos < data.len {
        let n, dist = next_match(data, pos, head);
        if dist == 0 {
            bits += lit_width(data[pos]);
            pos += 1;
        } else {
            bits += length_bits(n) + dist_bits(dist);
            pos += n;
        }
    }
    return bits;
}

fn emit_fixed(data: u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    var bw = Bw { acc: 0, n: 0 };
    var lbits: u32[288] = [0; 288];
    var lwidth: i64[288] = [0; 288];
    var dbits: u32[30] = [0; 30];
    var dwidth: i64[30] = [0; 30];
    fill_fixed(lbits, lwidth, dbits, dwidth);
    put(out, bw, 1, 1);
    put(out, bw, 1, 2);
    var head: i64[HASH_SIZE] = [0; HASH_SIZE];
    clear_head(head);
    var pos = 0;
    while pos < data.len {
        let n, dist = next_match(data, pos, head);
        if dist == 0 {
            let s: i64 = data[pos];
            put(out, bw, lbits[s], lwidth[s]);
            pos += 1;
        } else {
            let sym, extra, en = len_pair(n);
            put(out, bw, lbits[sym], lwidth[sym]);
            put(out, bw, extra as u64, en);
            let dsym, dextra, den = dist_pair(dist);
            put(out, bw, dbits[dsym], dwidth[dsym]);
            put(out, bw, dextra as u64, den);
            pos += n;
        }
    }
    put(out, bw, lbits[256], lwidth[256]);
    flush(out, bw);
    return out;
}

fn stored_bytes(n: i64) -> i64 {
    if n <= 0 { return 5; }
    var bytes = 0;
    var left = n;
    while left > 0 {
        var chunk = left;
        if chunk > 65535 { chunk = 65535; }
        bytes += 5 + chunk;
        left -= chunk;
    }
    return bytes;
}

fn push_u16(out: u8[>..]&, v: i64) {
    out.push((v & 0xff) as u8);
    out.push(((v >> 8) & 0xff) as u8);
}

fn emit_stored(data: u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    if data.len == 0 {
        out.push(0x01);
        out.push(0x00);
        out.push(0x00);
        out.push(0xff);
        out.push(0xff);
        return out;
    }
    var off = 0;
    while off < data.len {
        var chunk = data.len - off;
        if chunk > 65535 { chunk = 65535; }
        if off + chunk == data.len { out.push(0x01); } else { out.push(0x00); }
        push_u16(out, chunk);
        push_u16(out, chunk ^ 0xffff);
        for i in 0..chunk { out.push(data[off + i]); }
        off += chunk;
    }
    return out;
}

fn encode(data: u8[:]) -> u8[>..] {
    let bits = count_bits(data);
    if (bits + 7) / 8 < stored_bytes(data.len) {
        return emit_fixed(data);
    }
    return emit_stored(data);
}
