# Custom JPEG-LS Decoder / Merger

Parses a concatenated multi-segment JLS file (produced by the parallel FPGA encoder), decodes each segment, stitches blocks into the full image, and outputs a single PGM.

## Build

```bash
javac -d target/classes src/main/java/com/jpegls/decoder/*.java
```

## Usage

```bash
java -cp target/classes com.jpegls.decoder.Main <merged.jls> <output.pgm> --decoder <path/to/JPEGLSdec.exe>
```

**Example:**
```bash
java -cp target/classes com.jpegls.decoder.Main \
  ../JPEG_ENC_8f.sim/output_block/merged.jls \
  ../JPEG_ENC_8f.sim/output_block/output.pgm \
  --decoder "C:/Users/admin/Downloads/Shared with VM/FPGA-JPEG-LS-encoder/SIM/JPEGLSdec.exe"
```

## What it does

1. Parses `merged.jls` — splits on SOI (FFD8) markers, skips fragments < 30 bytes
2. Decodes each segment (500×375) using the reference `JPEGLSdec.exe`
3. Stitches 12 blocks into 1500×1500 (3 columns × 4 swaths)
4. Writes output as P5 PGM

## Segment layout

The merged file contains 12 JLS segments in this order:

| Segment | Encoder | Swath | Position |
|---------|---------|-------|----------|
| 0 | enc0a | 0 | col 0, rows 0–374 |
| 1 | enc1a | 0 | col 1, rows 0–374 |
| 2 | enc2a | 0 | col 2, rows 0–374 |
| 3 | enc3a | 1 | col 0, rows 375–749 |
| 4 | enc4a | 1 | col 1, rows 375–749 |
| 5 | enc5a | 1 | col 2, rows 375–749 |
| 6 | enc0b | 2 | col 0, rows 750–1124 |
| 7 | enc1b | 2 | col 1, rows 750–1124 |
| 8 | enc2b | 2 | col 2, rows 750–1124 |
| 9 | enc3b | 3 | col 0, rows 1125–1499 |
| 10 | enc4b | 3 | col 1, rows 1125–1499 |
| 11 | enc5b | 3 | col 2, rows 1125–1499 |

## Notes

- The `--decoder` path must point to `JPEGLSdec.exe` (SPMG reference decoder)
- Some "b" segments have a duplicate SOI byte (FFD8 FFD8) which is automatically stripped
- The tool uses temp files for intermediate decode; they are cleaned up on exit
