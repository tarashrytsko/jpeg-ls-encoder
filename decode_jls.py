import imagecodecs
import numpy as np

with open('JPEG_ENC_8f.sim/output_block/output.jls', 'rb') as f:
    data = f.read()

# Find all SOI (FFD8) and EOI (FFD9) marker positions
soi = [i for i in range(len(data)-1) if data[i]==0xff and data[i+1]==0xd8]
eoi = [i for i in range(len(data)-1) if data[i]==0xff and data[i+1]==0xd9]
print(f'Found {len(soi)} chunks: SOI={soi}, EOI={eoi}')

chunks = []
for i, (s, e) in enumerate(zip(soi, eoi)):
    chunk_data = data[s:e+2]
    dec = imagecodecs.jpegls_decode(chunk_data)
    print(f'  Chunk {i}: {dec.shape}, min={dec.min()}, max={dec.max()}')
    chunks.append(dec)

# Arrange as 2x2 grid (row-major): [0,1] top, [2,3] bottom
top = np.hstack([chunks[0], chunks[1]])
bot = np.hstack([chunks[2], chunks[3]])
merged = np.vstack([top, bot])
print(f'Merged shape: {merged.shape}')

h, w = merged.shape[:2]
out_path = 'JPEG_ENC_8f.sim/output_block/output_decoded.pgm'
with open(out_path, 'wb') as f:
    f.write(f'P5\n{w} {h}\n255\n'.encode())
    f.write(merged.tobytes())
print(f'Saved {out_path} ({w}x{h})')
