# tools/make_strided_hex.py  —  python tools/make_strided_hex.py in.pgm out.hex N_H
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
    d=open(src,'rb').read(); i=0
    mg,i=token(d,i); assert mg==b'P5'
    w,i=token(d,i); h,i=token(d,i); mx,i=token(d,i); i+=1
    w,h=int(w),int(h); px=d[i:i+w*h]
    assert w % NH == 0, "width must be divisible by N_H"
    sw=w//NH
    with open(dst,'w') as f:
        for ys in range(h):
            for xs in range(sw):
                word=0
                for k in range(NH):
                    word |= px[ys*w + k*sw + xs] << (8*k)
                f.write("%032X\n" % word)
    print("wrote %d strided words (%dx%d, N_H=%d, stripW=%d) to %s"%(h*sw,w,h,NH,sw,dst))
if __name__=="__main__": main()
