# tools/pgm_to_hex.py  —  usage: python tools/pgm_to_hex.py in.pgm out.hex
import sys
def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, "rb") as f:
        data = f.read()
    # parse P5 header: magic, (comments), "W H", maxval, then raw bytes
    idx = 0
    def token(i):
        while data[i:i+1].isspace(): i += 1
        if data[i:i+1] == b'#':
            while data[i:i+1] != b'\n': i += 1
            return token(i)
        j = i
        while not data[j:j+1].isspace(): j += 1
        return data[i:j], j
    magic, idx = token(idx); assert magic == b'P5', magic
    w, idx = token(idx); h, idx = token(idx); mx, idx = token(idx)
    idx += 1  # single whitespace after maxval
    w, h = int(w), int(h)
    px = data[idx:idx + w*h]
    with open(dst, "w") as f:
        for b in px:
            f.write("%02X\n" % b)
    print("wrote %d bytes (%dx%d) to %s" % (len(px), w, h, dst))
if __name__ == "__main__":
    main()
