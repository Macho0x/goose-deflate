// Raw DEFLATE inflate (RFC 1951).
// Stored blocks, fixed Huffman blocks, and dynamic Huffman blocks.
// Bits in a byte are read least-significant first. Huffman codes are
// most-significant bit first. The distance window is 32768 bytes.
// decode returns false on truncated or illegal input. Not constant-time.

namespace inflate;

// RFC 1951 section 3.2.5. Length symbol 257 is index 0.
const LEN_BASE: i64[29] = [
    3, 4, 5, 6, 7, 8, 9, 10,
    11, 13, 15, 17,
    19, 23, 27, 31,
    35, 43, 51, 59,
    67, 83, 99, 115,
    131, 163, 195, 227,
    258,
];

const LEN_EXTRA: i64[29] = [
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1,
    2, 2, 2, 2,
    3, 3, 3, 3,
    4, 4, 4, 4,
    5, 5, 5, 5,
    0,
];

// Distance symbol 0 is 1 byte back.
const DIST_BASE: i64[30] = [
    1, 2, 3, 4,
    5, 7,
    9, 13,
    17, 25,
    33, 49,
    65, 97,
    129, 193,
    257, 385,
    513, 769,
    1025, 1537,
    2049, 3073,
    4097, 6145,
    8193, 12289,
    16385, 24577,
];

const DIST_EXTRA: i64[30] = [
    0, 0, 0, 0,
    1, 1,
    2, 2,
    3, 3,
    4, 4,
    5, 5,
    6, 6,
    7, 7,
    8, 8,
    9, 9,
    10, 10,
    11, 11,
    12, 12,
    13, 13,
];

// RFC 1951 section 3.2.7. Order of the code-length code lengths.
const CL_ORDER: i64[19] = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
];

struct Cur {
    acc: u64,
    n: i64,
    at: i64,
}

// count[n] is how many codes have length n.
// symbol lists those codes in canonical order.
struct Huff {
    count: i64[16],
    symbol: i64[288],
}

fn get(src: u8[:], c: Cur&, k: i64) -> u64, bool {
    if k == 0 { return 0, true; }
    if k < 0 || k > 16 { abort("inflate: bit width"); }
    while c.n < k {
        if c.at >= src.len { return 0, false; }
        c.acc = c.acc | ((src[c.at] as u64) << c.n);
        c.at += 1;
        c.n += 8;
    }
    let mask = ((1 as u64) << k) - 1;
    let v = c.acc & mask;
    c.acc = c.acc >> k;
    c.n -= k;
    return v, true;
}

fn construct(h: Huff&, length: i64[:], n: i64) -> bool {
    for i in 0..16 { h.count[i] = 0; }
    for i in 0..288 { h.symbol[i] = 0; }
    if n < 0 || n > 288 { return false; }
    for sym in 0..n {
        let L = length[sym];
        if L < 0 || L > 15 { return false; }
        h.count[L] += 1;
    }
    if h.count[0] == n { return true; }
    var left: i64 = 1;
    for len in 1..16 {
        left = left * 2 - h.count[len];
        if left < 0 { return false; }
    }
    var offs: i64[16] = [0; 16];
    for len in 1..15 {
        offs[len + 1] = offs[len] + h.count[len];
    }
    for sym in 0..n {
        let L = length[sym];
        if L != 0 {
            let at = offs[L];
            if at < 0 || at >= 288 { return false; }
            h.symbol[at] = sym;
            offs[L] = at + 1;
        }
    }
    return true;
}

fn dec(src: u8[:], c: Cur&, h: Huff&) -> i64, bool {
    var code = 0;
    var first = 0;
    var index = 0;
    for len in 1..16 {
        let b, ok = get(src, c, 1);
        if !ok { return 0, false; }
        code = (code << 1) | (b as i64);
        let count = h.count[len];
        if code >= first && code < first + count {
            let si = index + code - first;
            if si < 0 || si >= 288 { return 0, false; }
            return h.symbol[si], true;
        }
        index += count;
        first = (first + count) << 1;
    }
    return 0, false;
}

fn extra(src: u8[:], c: Cur&, n: i64) -> i64, bool {
    if n == 0 { return 0, true; }
    let v, ok = get(src, c, n);
    if !ok { return 0, false; }
    return v as i64, true;
}

fn copy_match(out: u8[>..]&, distance: i64, length: i64) {
    var left = length;
    while left > 0 {
        let b = out[out.len - distance];
        out.push(b);
        left -= 1;
    }
}

fn codes(src: u8[:], c: Cur&, out: u8[>..]&, lit: Huff&, dist: Huff&, window: i64) -> bool {
    while true {
        let sym, ok = dec(src, c, lit);
        if !ok { return false; }
        if sym < 0 { return false; }
        if sym < 256 {
            out.push(sym as! u8);
        } else if sym == 256 {
            return true;
        } else if sym > 285 {
            return false;
        } else {
            let li = sym - 257;
            let add, okl = extra(src, c, LEN_EXTRA[li]);
            if !okl { return false; }
            let length = LEN_BASE[li] + add;
            let ds, okd = dec(src, c, dist);
            if !okd || ds < 0 || ds > 29 { return false; }
            let dadd, oke = extra(src, c, DIST_EXTRA[ds]);
            if !oke { return false; }
            let distance = DIST_BASE[ds] + dadd;
            if distance < 1 || distance > window || distance > out.len { return false; }
            copy_match(out, distance, length);
        }
    }
    // A trailing loop is the function value unless a return follows it.
    return false;
}

fn stored_block(src: u8[:], c: Cur&, out: u8[>..]&) -> bool {
    if c.n >= 8 { abort("inflate: bit buffer"); }
    if c.n > 0 {
        c.acc = c.acc >> c.n;
        c.n = 0;
    }
    let len, ok1 = get(src, c, 16);
    let nlen, ok2 = get(src, c, 16);
    if !ok1 || !ok2 { return false; }
    if (len ^ nlen) != 0xffff { return false; }
    let n = len as i64;
    if c.at + n > src.len { return false; }
    out.append(src[c.at..c.at + n]);
    c.at += n;
    return true;
}

fn blank() -> Huff {
    Huff { count: [0; 16], symbol: [0; 288] }
}

fn fixed_block(src: u8[:], c: Cur&, out: u8[>..]&, window: i64) -> bool {
    var lit_len: i64[288] = [0; 288];
    for i in 0..144 { lit_len[i] = 8; }
    for i in 144..256 { lit_len[i] = 9; }
    for i in 256..280 { lit_len[i] = 7; }
    for i in 280..288 { lit_len[i] = 8; }
    var dist_len: i64[30] = [0; 30];
    for i in 0..30 { dist_len[i] = 5; }
    var lit = blank();
    var dist = blank();
    if !construct(lit, lit_len, 288) { abort("inflate: fixed literal table"); }
    if !construct(dist, dist_len, 30) { abort("inflate: fixed distance table"); }
    return codes(src, c, out, lit, dist, window);
}

fn repeat(lens: i64[320]&, i: i64&, value: i64, rep: i64, ntot: i64) -> bool {
    if i + rep > ntot { return false; }
    var left = rep;
    while left > 0 {
        lens[i] = value;
        i += 1;
        left -= 1;
    }
    return true;
}

fn dynamic_block(src: u8[:], c: Cur&, out: u8[>..]&, window: i64) -> bool {
    let hlit, ok1 = get(src, c, 5);
    let hdist, ok2 = get(src, c, 5);
    let hclen, ok3 = get(src, c, 4);
    if !ok1 || !ok2 || !ok3 { return false; }
    let nlit = (hlit as i64) + 257;
    let ndist = (hdist as i64) + 1;
    let nclen = (hclen as i64) + 4;
    if nlit > 288 || ndist > 32 || nclen > 19 { return false; }
    var clen: i64[19] = [0; 19];
    for i in 0..nclen {
        let v, ok = get(src, c, 3);
        if !ok { return false; }
        clen[CL_ORDER[i]] = v as i64;
    }
    var clh = blank();
    if !construct(clh, clen, 19) { return false; }
    var lens: i64[320] = [0; 320];
    let ntot = nlit + ndist;
    var filled = 0;
    while filled < ntot {
        let sym, ok = dec(src, c, clh);
        if !ok { return false; }
        if sym < 16 {
            lens[filled] = sym;
            filled += 1;
        } else if sym == 16 {
            if filled == 0 { return false; }
            let more, oke = extra(src, c, 2);
            if !oke { return false; }
            if !repeat(lens, filled, lens[filled - 1], 3 + more, ntot) { return false; }
        } else if sym == 17 {
            let more, oke = extra(src, c, 3);
            if !oke { return false; }
            if !repeat(lens, filled, 0, 3 + more, ntot) { return false; }
        } else if sym == 18 {
            let more, oke = extra(src, c, 7);
            if !oke { return false; }
            if !repeat(lens, filled, 0, 11 + more, ntot) { return false; }
        } else {
            return false;
        }
    }
    var lit = blank();
    var dist = blank();
    if !construct(lit, lens[..nlit], nlit) { return false; }
    if !construct(dist, lens[nlit..ntot], ndist) { return false; }
    return codes(src, c, out, lit, dist, window);
}

fn blocks(src: u8[:], c: Cur&, out: u8[>..]&, window: i64) -> bool {
    while true {
        let bfinal, ok1 = get(src, c, 1);
        let btype, ok2 = get(src, c, 2);
        if !ok1 || !ok2 { return false; }
        var ok = false;
        if btype == 0 {
            ok = stored_block(src, c, out);
        } else if btype == 1 {
            ok = fixed_block(src, c, out, window);
        } else if btype == 2 {
            ok = dynamic_block(src, c, out, window);
        } else {
            return false;
        }
        if !ok { return false; }
        if bfinal == 1 { return true; }
    }
    // A trailing loop is the function value unless a return follows it.
    return false;
}

// Bytes of one raw DEFLATE stream, how many input bytes were read, and
// whether the stream was valid. window is the maximum match distance.
fn decode_window(src: u8[:], window: i64) -> u8[>..], i64, bool {
    if window < 1 || window > 32768 { abort("inflate: window"); }
    var out: u8[>..] = [];
    var c = Cur { acc: 0, n: 0, at: 0 };
    if !blocks(src, c, out, window) { return [], 0, false; }
    return out, c.at, true;
}

fn decode(src: u8[:]) -> u8[>..], bool {
    let out, used, ok = decode_window(src, 32768);
    if !ok || used < 0 { return [], false; }
    return out, true;
}
