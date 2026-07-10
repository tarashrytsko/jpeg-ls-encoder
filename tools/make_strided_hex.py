# tools/make_strided_hex.py  —  python tools/make_strided_hex.py in.pgm out.hex N_H [N_V]
# Emits one N_E-byte word per cycle (ys outer, xs inner). Byte k = lane k's pixel,
# lane k at block (bx=k%N_H, by=k//N_H); full-image coord (bx*sw+xs, by*sh+ys).
# N_V defaults to 1 (column-strided / vertical) for back-compat.
import sys
def token(d,i):
    while d[i:i+1].isspace(): i+=1
    if d[i:i+1]==b'#':
        while d[i:i+1]!=b'\n': i+=1
        return token(d,i)
    j=i
    while not d[j:j+1].isspace(): j+=1
    return d[i:j],j
def main():
    src,dst,NH = sys.argv[1], sys.argv[2], int(sys.argv[3])
    NV = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    d=open(src,'rb').read(); i=0
    mg,i=token(d,i); assert mg==b'P5'
    w,i=token(d,i); h,i=token(d,i); mx,i=token(d,i); i+=1
    w,h=int(w),int(h); px=d[i:i+w*h]
    assert w % NH == 0, "width must be divisible by N_H"
    assert h % NV == 0, "height must be divisible by N_V"
    sw=w//NH; sh=h//NV; NE=NH*NV
    with open(dst,'w') as f:
        for ys in range(sh):
            for xs in range(sw):
                word=0
                for k in range(NE):
                    bx=k%NH; by=k//NH
                    word |= px[(by*sh+ys)*w + (bx*sw+xs)] << (8*k)
                f.write("%0*X\n" % (NE*2, word))   # NE bytes -> NE*2 hex digits (32 for N_E=16)
    print("wrote %d words (%dx%d N_H=%d N_V=%d sw=%d sh=%d N_E=%d) to %s"%(sw*sh,w,h,NH,NV,sw,sh,NE,dst))
if __name__=="__main__": main()
