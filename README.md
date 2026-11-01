# goose-deflate

Version 0.1.

DEFLATE in [Goose](https://github.com/aardappel/goose), as specified by [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951), with the [zlib](https://www.rfc-editor.org/rfc/rfc1950) and [gzip](https://www.rfc-editor.org/rfc/rfc1952) wrappers.

`inflate::decode` reads stored, fixed Huffman, and dynamic Huffman blocks. `raw::encode` writes one fixed Huffman block or stored blocks of at most 65535 bytes. The encoder output is not a miniz compression level. See `PORTING.md`.

Copyright 2026 Macho0x. Licensed under Apache-2.0, the same license as Goose.

## Check

Install the Goose compiler, then from this directory:

```sh
goose tests/self_check.goose
```

A good run prints `deflate ok`.

`deflate.goose` is the package entry. Importing the package does not load an algorithm. `import deflate.inflate` loads `inflate.goose` from the package root.

```goose
import deflate from "../deflate";
import deflate.raw;
import deflate.inflate;

fn main() {
    let packed = raw::encode("goose");
    let back, ok = inflate::decode(packed);
    print(ok);
    print(back);
}
```

## Modules

| Module | What it does |
| --- | --- |
| `checksum` | CRC-32, starting at 0, and Adler-32, starting at 1 |
| `inflate` | Raw DEFLATE decoder. Returns the bytes and false on a truncated or illegal stream |
| `raw` | Raw DEFLATE encoder |
| `zlib` | CMF, FLG, the raw stream, and an Adler-32 trailer |
| `gzip` | A 10-byte header, the raw stream, CRC-32, and ISIZE |

`zlib::decompress` and `gzip::decompress` return false when the wrapper or the stream is rejected. Checksums are not constant-time.
