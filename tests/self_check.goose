import deflate from "..";
import deflate.checksum;
import deflate.inflate;
import deflate.raw;
import deflate.zlib;
import deflate.gzip;
import .vectors;
import os;

fn go(name: u8[:], ok: bool) {
    var line: u8[>..] = [];
    line.append(name);
    if ok { line.append(" ok\n"); } else { line.append(" FAIL\n"); }
    write_stdout(line);
    if !ok { exit(1); }
}

// Same bytes as mixed() in goldens.py.
fn mixed() -> u8[>..] {
    let text = "Goose deflate block.\n";
    var d: u8[>..] = [];
    for i in 0..4096 {
        if i < 256 {
            d.push(text[i % text.len]);
        } else if i < 768 {
            d.push(0);
        } else {
            d.push(((i * 17 + (i >> 3)) & 0xff) as! u8);
        }
    }
    return d;
}

fn rising() -> u8[>..] {
    var d: u8[>..] = [];
    for i in 0..48 { d.push((160 + i) as! u8); }
    return d;
}

fn aaa() -> u8[>..] {
    var d: u8[>..] = [];
    for i in 0..100 { d.push('a'); }
    return d;
}

fn wide() -> u8[>..] {
    var d: u8[>..] = [];
    for i in 0..65546 {
        var z: u32 = (i as u32) * 0x9e3779b1;
        z = (z ^ (z >> 16)) * 0x85ebca6b;
        z = z ^ (z >> 13);
        d.push((160 + (z % 96)) as! u8);
    }
    return d;
}

fn round_raw(data: u8[:]) -> bool {
    let back, ok = inflate::decode(raw::encode(data));
    return ok && back == data;
}

fn round_zlib(data: u8[:]) -> bool {
    let back, ok = zlib::decompress(zlib::compress(data));
    return ok && back == data;
}

fn round_gzip(data: u8[:]) -> bool {
    let back, ok = gzip::decompress(gzip::compress(data));
    return ok && back == data;
}

fn ::main() {
    go("crc32 empty", checksum::crc32("") == 0);
    go("crc32 digits", checksum::crc32("123456789") == 0xcbf43926);
    go("adler32 empty", checksum::adler32("") == 1);
    go("adler32 digits", checksum::adler32("123456789") == 0x091e01de);

    let empty, eok = inflate::decode(vectors::RAW_EMPTY);
    go("inflate empty", eok && empty.len == 0);

    let short, sok = inflate::decode(vectors::RAW_SHORT);
    go("inflate short", sok && short == "goose");

    let mix = mixed();
    let mixed_out, mok = inflate::decode(vectors::RAW_MIXED);
    go("inflate mixed", mok && mixed_out == mix);

    let stored: u8[10] = [0x01, 0x05, 0x00, 0xfa, 0xff, 0x67, 0x6f, 0x6f, 0x73, 0x65];
    let stored_out, stok = inflate::decode(stored);
    go("inflate stored", stok && stored_out == "goose");

    let blocks: u8[12] = [
        0x00, 0x01, 0x00, 0xfe, 0xff, 0x61,
        0x01, 0x01, 0x00, 0xfe, 0xff, 0x62,
    ];
    let blocks_out, blok = inflate::decode(blocks);
    go("inflate blocks", blok && blocks_out == "ab");

    let rep = aaa();
    let rep_out, rok = inflate::decode(vectors::RAW_REPEAT);
    go("inflate repeat", rok && rep_out == rep);

    let cut = vectors::RAW_SHORT[..vectors::RAW_SHORT.len - 1];
    let trunc, tok = inflate::decode(cut);
    go("inflate truncated", !tok && trunc.len == 0);

    let bad: u8[1] = [0x07];
    let bad_out, bok = inflate::decode(bad);
    go("inflate bad block", !bok && bad_out.len == 0);

    let raw_empty = raw::encode("");
    let empty_fixed: u8[2] = [0x03, 0x00];
    go("raw empty", raw_empty == empty_fixed);

    go("raw short", round_raw("goose"));
    go("raw mixed", round_raw(mix));

    let inc = rising();
    let inc_enc = raw::encode(inc);
    let inc_back, iok = inflate::decode(inc_enc);
    go("raw stored", iok && inc_back == inc && inc_enc[0] == 1);

    go("raw repeat", round_raw(rep));

    let big = wide();
    let big_enc = raw::encode(big);
    let big_back, bigok = inflate::decode(big_enc);
    go("raw blocks", bigok && big_back == big && big_enc[0] == 0);

    let zempty, zeok = zlib::decompress(vectors::ZLIB_EMPTY);
    go("zlib empty", zeok && zempty.len == 0);
    let zshort, zsok = zlib::decompress(vectors::ZLIB_SHORT);
    go("zlib short", zsok && zshort == "goose");
    let zmixed, zmok = zlib::decompress(vectors::ZLIB_MIXED);
    go("zlib mixed", zmok && zmixed == mix);
    go("zlib roundtrip empty", round_zlib(""));
    go("zlib roundtrip short", round_zlib("goose"));
    go("zlib roundtrip mixed", round_zlib(mix));

    var zbad = copy(vectors::ZLIB_SHORT);
    zbad[zbad.len - 1] = zbad[zbad.len - 1] ^ 1;
    let zbad_out, zbadok = zlib::decompress(zbad);
    go("zlib bad checksum", !zbadok && zbad_out.len == 0);

    let zcut = vectors::ZLIB_SHORT[..vectors::ZLIB_SHORT.len - 1];
    let ztrunc, ztok = zlib::decompress(zcut);
    go("zlib truncated", !ztok && ztrunc.len == 0);

    let gempty, geok = gzip::decompress(vectors::GZIP_EMPTY);
    go("gzip empty", geok && gempty.len == 0);
    let gshort, gsok = gzip::decompress(vectors::GZIP_SHORT);
    go("gzip short", gsok && gshort == "goose");
    let gmixed, gmok = gzip::decompress(vectors::GZIP_MIXED);
    go("gzip mixed", gmok && gmixed == mix);
    go("gzip roundtrip empty", round_gzip(""));
    go("gzip roundtrip short", round_gzip("goose"));
    go("gzip roundtrip mixed", round_gzip(mix));

    var gbad = copy(vectors::GZIP_SHORT);
    gbad[gbad.len - 8] = gbad[gbad.len - 8] ^ 1;
    let gbad_out, gbadok = gzip::decompress(gbad);
    go("gzip bad crc", !gbadok && gbad_out.len == 0);

    let gcut = vectors::GZIP_SHORT[..vectors::GZIP_SHORT.len - 1];
    let gtrunc, gtok = gzip::decompress(gcut);
    go("gzip truncated", !gtok && gtrunc.len == 0);

    write_stdout("deflate ok\n");
}
