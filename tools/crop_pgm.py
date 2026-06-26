# tools/crop_pgm.py  —  usage: python tools/crop_pgm.py in.pgm out.pgm CW CH
import sys
def token(d, i):
    while d[i:i+1].isspace(): i += 1
    if d[i:i+1] == b'#':
        while d[i:i+1] != b'\n': i += 1
        return token(d, i)
    j = i
    while not d[j:j+1].isspace(): j += 1
    return d[i:j], j
def main():
    src, dst, CW, CH = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    d = open(src, "rb").read()
    i = 0
    mg, i = token(d, i); assert mg == b'P5'
    w, i = token(d, i); h, i = token(d, i); mx, i = token(d, i); i += 1
    w, h = int(w), int(h)
    px = d[i:i + w*h]
    crop = bytearray()
    for r in range(CH):
        crop.extend(px[r*w : r*w + CW])
    open(dst, "wb").write(("P5\n%d %d\n255\n" % (CW, CH)).encode() + bytes(crop))
    print("cropped %dx%d -> %s (%d bytes)" % (CW, CH, dst, len(crop)))
if __name__ == "__main__":
    main()
