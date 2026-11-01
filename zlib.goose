// zlib wrapper (RFC 1950) around a raw DEFLATE stream.
// compress writes CMF 0x78 and FLG 0x01. That header is divisible by 31,
// has no preset dictionary, and records the fastest level.
// The trailer is Adler-32 of the uncompressed bytes, big-endian.
// A preset dictionary is rejected. Not constant-time.

import checksum;
import inflate;
import raw;

namespace zlib;

fn push_be32(out: u8[>..]&, v: u32) {
    out.push((v >> 24) as u8);
    out.push(((v >> 16) & 0xff) as u8);
    out.push(((v >> 8) & 0xff) as u8);
    out.push((v & 0xff) as u8);
}

fn be32(src: u8[:], at: i64) -> u32 {
    return (src[at] as u32) << 24
        | (src[at + 1] as u32) << 16
        | (src[at + 2] as u32) << 8
        | src[at + 3];
}

fn compress(data: u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    out.push(0x78);
    out.push(0x01);
    let body = raw::encode(data);
    out.append(body);
    push_be32(out, checksum::adler32(data));
    return out;
}

fn decompress(src: u8[:]) -> u8[>..], bool {
    if src.len < 6 { return [], false; }
    let cmf = src[0];
    let flg = src[1];
    if cmf & 0x0f != 8 { return [], false; }
    let cinfo: i64 = cmf >> 4;
    if cinfo > 7 { return [], false; }
    let pair = (cmf as i64) * 256 + flg;
    if pair % 31 != 0 { return [], false; }
    if flg & 0x20 != 0 { return [], false; }
    let window = 1 << (cinfo + 8);
    let out, used, ok = inflate::decode_window(src[2..], window);
    if !ok { return [], false; }
    if used < 0 || used + 4 != src.len - 2 { return [], false; }
    if checksum::adler32(out) != be32(src, 2 + used) { return [], false; }
    return out, true;
}
