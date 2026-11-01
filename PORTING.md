# Porting

goose-deflate is a Goose implementation of RFC 1951, RFC 1950, and RFC 1952. The inflater follows the shape of puff. A bit buffer, then a canonical Huffman table of code counts and symbols, then one loop for literal and length codes. Stored, fixed, and dynamic blocks share that loop.

## Encoder

`raw::encode` is one compressor. It counts the bits of a single final fixed Huffman block, using a 12-bit hash and one match candidate, and writes that block when the result is shorter than stored blocks. Otherwise it writes stored blocks of at most 65535 bytes. Empty input is the two-byte fixed block `03 00`.

Output bytes are not required to match a particular miniz level. They are also not required to match zlib's default compressor or flate2's compressor. There is no level argument, no lazy match, and no dynamic Huffman encoder.

## Decoder

`inflate::decode` must accept the raw DEFLATE streams embedded in `tests/vectors.goose`. `goldens.py` builds those streams with Python's zlib:

- raw DEFLATE is `zlib.compressobj(level=6, wbits=-15)`
- the zlib wrapper is `zlib.compress`
- gzip is `gzip.compress(mtime=0)`

Python checks that each stream decompresses to the original bytes before the file is written. `goose tests/self_check.goose` then checks that this package's inflater returns those same bytes. The embedded raw streams are what a flate2 raw inflater is specified to accept. This workspace did not run the flate2 crate.

The stored vector in the test is built from the RFC, two stored blocks for `ab` and one stored block for `goose`. The reserved block type `0x07` is the bad-block vector.

## Limits

- The distance window is 32768 bytes. zlib's CINFO selects a window from 256 to 32768, and a longer distance is rejected.
- A zlib preset dictionary is rejected.
- `gzip::compress` writes no file name, mtime 0, XFL 0, and OS 255. `gzip::decompress` reads one member and rejects bytes after it.
- There is no streaming API and no output-size cap. A hostile stream can grow until the data stack stops it.
- Checksums, matching, and Huffman decoding follow the input. They are not constant-time.
- Failure is a trailing bool. `abort` is reserved for a broken internal invariant, such as the fixed Huffman table failing to build. Those aborts in `inflate.goose` stay. A cast in the wrappers is checked. A masked byte still fits.
