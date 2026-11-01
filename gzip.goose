// gzip wrapper (RFC 1952) around a raw DEFLATE stream.
// compress writes a 10-byte header with no file name, mtime 0, and OS 255.
// The trailer is CRC-32 and the uncompressed size modulo 2^32, both
// little-endian. decompress reads one member. Not constant-time.

import checksum;
import inflate;
import raw;

namespace gzip;

fn push_le32(out: u8[>..]&, v: u32) {
    out.push((v & 0xff) as u8);
    out.push(((v >> 8) & 0xff) as u8);
    out.push(((v >> 16) & 0xff) as u8);
    out.push(((v >> 24) & 0xff) as u8);
}

fn le32(src: u8[:], at: i64) -> u32 {
    return src[at]
        | (src[at + 1] as u32) << 8
        | (src[at + 2] as u32) << 16
        | (src[at + 3] as u32) << 24;
}

fn low32(n: i64) -> u32 {
    return ((n as u64) & 0xffffffff) as u32;
}

fn skip_zero(src: u8[:], at: i64) -> i64, bool {
    var i = at;
    while i < src.len {
        if src[i] == 0 { return i + 1, true; }
        i += 1;
    }
    return 0, false;
}

fn compress(data: u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    out.push(0x1f);
    out.push(0x8b);
    out.push(8);
    out.push(0);
    out.push(0);
    out.push(0);
    out.push(0);
    out.push(0);
    out.push(0);
    out.push(255);
    let body = raw::encode(data);
    out.append(body);
    push_le32(out, checksum::crc32(data));
    push_le32(out, low32(data.len));
    return out;
}

fn decompress(src: u8[:]) -> u8[>..], bool {
    if src.len < 18 { return [], false; }
    if src[0] != 0x1f || src[1] != 0x8b || src[2] != 8 { return [], false; }
    let flg = src[3];
    if flg & 0xe0 != 0 { return [], false; }
    var at: i64 = 10;
    if flg & 4 != 0 {
        if at + 2 > src.len { return [], false; }
        let xlen = src[at] | ((src[at + 1] as i64) << 8);
        at += 2;
        if xlen < 0 || at + xlen > src.len { return [], false; }
        at += xlen;
    }
    if flg & 8 != 0 {
        let next, ok = skip_zero(src, at);
        if !ok { return [], false; }
        at = next;
    }
    if flg & 16 != 0 {
        let next, ok = skip_zero(src, at);
        if !ok { return [], false; }
        at = next;
    }
    if flg & 2 != 0 {
        if at + 2 > src.len { return [], false; }
        at += 2;
    }
    if at > src.len { return [], false; }
    let out, used, ok = inflate::decode_window(src[at..], 32768);
    if !ok { return [], false; }
    if used < 0 || at + used + 8 != src.len { return [], false; }
    if checksum::crc32(out) != le32(src, at + used) { return [], false; }
    if low32(out.len) != le32(src, at + used + 4) { return [], false; }
    return out, true;
}
