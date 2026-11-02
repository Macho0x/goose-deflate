// Times this package. One untimed batch, then batches until the window
// elapses. The sink keeps the call alive.
// Build with clang on the revision before a change, then again after:
//   goose build -o deflate-bench bench.goose --cc clang
//   ./deflate-bench
// Row names stay fixed. TinyCC (goose bench.goose) is not a timing result.
// ponytail: a fixed window, not a sampled harness. Rows under a microsecond
// move from run to run; lengthen the window before trusting them.

import os;
import checksum;
import inflate;
import raw;
import zlib;
import gzip;

var rep: u8[4096] = [0x61; 4096];
var rnd: u8[4096] = [0; 4096];
var packed_rep: u8[>..] = [];
var packed_rnd: u8[>..] = [];
var zblob: u8[>..] = [];

fn mark(b: u8, ok: bool) -> u64 {
    if !ok { return 0; }
    let v: u64 = b;
    return v + 1;
}

fn time_batch<F>(batch: i64, ms: i64) -> i64, u64 {
    var sink: u64 = 0;
    var k = 0;
    while k < batch {
        sink += F();
        k += 1;
    }
    var n: i64 = 0;
    var dt: i64 = 0;
    let end = clock_ns() + ms * 1000000;
    while true {
        let t0 = clock_ns();
        k = 0;
        while k < batch {
            sink += F();
            k += 1;
        }
        dt += clock_ns() - t0;
        n += batch;
        if clock_ns() >= end { break; }
    }
    return dt / n, sink;
}

fn row<F>(name: u8[:], batch: i64, ms: i64) -> u64 {
    let ns, part = time_batch(batch, ms, F);
    var line: u8[>..] = [];
    format(line, name);
    while line.len < 28 { line.push(' '); }
    format_int(line, ns, 10, 12, ' ');
    format(line, "\n");
    write_stdout(line);
    return part;
}

fn crc_4k() -> u64 {
    rep[1] += 1;
    let c = checksum::crc32(rep);
    return mark((c & 255) as! u8, true);
}

fn adler_4k() -> u64 {
    rep[2] += 1;
    let c = checksum::adler32(rep);
    return mark((c & 255) as! u8, true);
}

fn enc_repeat() -> u64 {
    rep[3] += 1;
    let out = raw::encode(rep);
    if out.len == 0 { return 0; }
    return mark(out[0], true);
}

fn enc_stored() -> u64 {
    rnd[0] += 1;
    let out = raw::encode(rnd);
    if out.len < 6 { return 0; }
    return mark(out[0], true);
}

fn inf_repeat() -> u64 {
    let out, ok = inflate::decode(packed_rep);
    if !ok || out.len == 0 { return 0; }
    return mark(out[0], true);
}

fn inf_stored() -> u64 {
    let n = packed_rnd.len;
    packed_rnd[n - 1] += 1;
    let out, ok = inflate::decode(packed_rnd);
    if !ok || out.len == 0 { return 0; }
    return mark(out[out.len - 1], true);
}

fn zlib_enc() -> u64 {
    rnd[1] += 1;
    let out = zlib::compress(rnd);
    if out.len == 0 { return 0; }
    return mark(out[0], true);
}

fn zlib_dec() -> u64 {
    let out, ok = zlib::decompress(zblob);
    if !ok || out.len == 0 { return 0; }
    return mark(out[0], true);
}

fn gzip_enc() -> u64 {
    rnd[2] += 1;
    let out = gzip::compress(rnd);
    if out.len == 0 { return 0; }
    return mark(out[0], true);
}

fn ready() -> bool {
    if checksum::crc32("123456789") != 0xcbf43926 { return false; }
    if checksum::adler32("123456789") != 0x091e01de { return false; }
    let back, ok = inflate::decode(raw::encode("goose"));
    if !ok || back != "goose" { return false; }
    for i in 0..4096 { rnd[i] = ((i * 17 + 3) & 0xff) as! u8; }
    packed_rep = raw::encode(rep);
    packed_rnd = raw::encode(rnd);
    zblob = zlib::compress(rnd);
    if packed_rep.len == 0 || packed_rnd.len == 0 || zblob.len == 0 { return false; }
    let got, gok = inflate::decode(packed_rnd);
    return gok && got == rnd;
}

fn ::main() {
    if !ready() { print("bench FAIL"); exit(1); }
    write_stdout("operation                       ns/call\n");
    var sink: u64 = 0;
    sink += row("crc32 4KB", 16, 200, crc_4k);
    sink += row("adler32 4KB", 16, 200, adler_4k);
    sink += row("raw encode repeat", 4, 250, enc_repeat);
    sink += row("raw encode stored", 4, 250, enc_stored);
    sink += row("inflate repeat", 4, 250, inf_repeat);
    sink += row("inflate stored", 4, 250, inf_stored);
    sink += row("zlib compress 4KB", 4, 250, zlib_enc);
    sink += row("zlib decompress", 4, 250, zlib_dec);
    sink += row("gzip compress 4KB", 4, 250, gzip_enc);
    var tail: u8[>..] = [];
    format(tail, "sink ");
    format(tail, sink);
    format(tail, "\n");
    write_stdout(tail);
}
