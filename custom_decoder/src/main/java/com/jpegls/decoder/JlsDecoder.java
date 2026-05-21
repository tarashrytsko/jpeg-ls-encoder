package com.jpegls.decoder;

/**
 * Pure Java JPEG-LS decoder for 8-bit grayscale, NEAR=0 (lossless).
 * Implements ITU-T T.87 / ISO 14495-1.
 */
public class JlsDecoder {

    private static final int MAXVAL = 255;
    private static final int RANGE = MAXVAL + 1;
    private static final int NEAR = 0;
    private static final int RESET = 64;
    private static final int T1 = 3, T2 = 7, T3 = 21;
    private static final int LIMIT = 127; // 2*(bpp + max(8,bpp)) for bpp=8

    private int[] N = new int[367];
    private int[] A = new int[367];
    private int[] B = new int[367];
    private int[] C = new int[367];
    private int[] Nn = new int[2]; // for run mode

    private int RUNindex = 0;
    private static final int[] J = {
        0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,5,5,6,6,7,7,8,9,10,11,12,13,14,15
    };

    private byte[] input;
    private int bitPos;
    private int bytePos;
    private int curByte;
    private int nextByte;

    public byte[] decode(byte[] jlsData, int width, int height) {
        byte[] pixels = new byte[width * height];
        initState();

        // Skip header (26 bytes: SOI+SOF+SOS)
        bytePos = 26;
        bitPos = 0;
        curByte = jlsData[bytePos] & 0xFF;
        nextByte = (bytePos + 1 < jlsData.length) ? (jlsData[bytePos + 1] & 0xFF) : 0;
        input = jlsData;

        int[] prevLine = new int[width + 1];
        int[] curLine = new int[width + 1];

        for (int row = 0; row < height; row++) {
            for (int col = 0; col < width; col++) {
                int Ra = (col > 0) ? curLine[col - 1] : prevLine[col];
                int Rb = prevLine[col];
                int Rc = (col > 0) ? prevLine[col - 1] : prevLine[col];
                int Rd = (col < width - 1) ? prevLine[col + 1] : prevLine[col];

                int D1 = Rd - Rb;
                int D2 = Rb - Rc;
                int D3 = Rc - Ra;

                int ctx = getContext(D1, D2, D3);
                int sign = 0;

                if (ctx < 0) {
                    ctx = -ctx;
                    sign = 1;
                }

                if (ctx == 0 && Math.abs(D1) <= 0 && Math.abs(D2) <= 0 && Math.abs(D3) <= 0) {
                    // Run mode
                    int val = decodeRun(Ra, curLine, col, width, prevLine, row);
                    curLine[col] = val;
                    if (col >= width) {
                        col = width - 1;
                    }
                    continue;
                }

                // Regular mode
                int Px = predict(Ra, Rb, Rc);
                Px = Px + (sign == 0 ? C[ctx] : -C[ctx]);
                Px = clamp(Px);

                int k = computeK(ctx);
                int Errval = decodeGolomb(k, LIMIT);

                if (sign == 1) Errval = -Errval;

                // Dequantize and reconstruct
                int Rx = (Px + Errval);
                Rx = (Rx + RANGE) % RANGE;
                if (Rx < 0) Rx += RANGE;
                if (Rx > MAXVAL) Rx = Rx % (MAXVAL + 1);
                curLine[col] = Rx;

                // Update context
                B[ctx] += Errval;
                A[ctx] += Math.abs(Errval);
                if (N[ctx] == RESET) {
                    A[ctx] >>= 1;
                    B[ctx] >>= 1;
                    N[ctx] >>= 1;
                }
                N[ctx]++;

                if (B[ctx] <= -N[ctx]) {
                    B[ctx] += N[ctx];
                    if (C[ctx] > -128) C[ctx]--;
                    if (B[ctx] <= -N[ctx]) B[ctx] = -N[ctx] + 1;
                } else if (B[ctx] > 0) {
                    B[ctx] -= N[ctx];
                    if (C[ctx] < 127) C[ctx]++;
                    if (B[ctx] > 0) B[ctx] = 0;
                }
            }

            // Copy curLine to pixels
            for (int col = 0; col < width; col++) {
                pixels[row * width + col] = (byte) curLine[col];
            }

            // Swap lines
            int[] tmp = prevLine;
            prevLine = curLine;
            curLine = tmp;
            java.util.Arrays.fill(curLine, 0);
        }

        return pixels;
    }

    private void initState() {
        for (int i = 0; i < 367; i++) {
            N[i] = 1;
            A[i] = 4;
            B[i] = 0;
            C[i] = 0;
        }
        Nn[0] = 1;
        Nn[1] = 1;
        RUNindex = 0;
    }

    private int predict(int Ra, int Rb, int Rc) {
        if (Rc >= Math.max(Ra, Rb)) return Math.min(Ra, Rb);
        if (Rc <= Math.min(Ra, Rb)) return Math.max(Ra, Rb);
        return Ra + Rb - Rc;
    }

    private int clamp(int val) {
        if (val < 0) return 0;
        if (val > MAXVAL) return MAXVAL;
        return val;
    }

    private int getContext(int D1, int D2, int D3) {
        int Q1 = quantize(D1);
        int Q2 = quantize(D2);
        int Q3 = quantize(D3);

        if (Q1 < 0 || (Q1 == 0 && Q2 < 0) || (Q1 == 0 && Q2 == 0 && Q3 < 0)) {
            return -(Q1 * 81 + Q2 * 9 + Q3);
        }
        return Q1 * 81 + Q2 * 9 + Q3;
    }

    private int quantize(int D) {
        if (D <= -T3) return -4;
        if (D <= -T2) return -3;
        if (D <= -T1) return -2;
        if (D < -NEAR) return -1;
        if (D <= NEAR) return 0;
        if (D < T1) return 1;
        if (D < T2) return 2;
        if (D < T3) return 3;
        return 4;
    }

    private int computeK(int ctx) {
        int Nv = N[ctx];
        int Av = A[ctx];
        int k = 0;
        while ((Nv << k) < Av && k < 8) k++;
        return k;
    }

    private int decodeGolomb(int k, int limit) {
        // Read unary part
        int unary = 0;
        while (readBit() == 0) {
            unary++;
            if (unary >= limit - 1) break;
        }

        int val;
        if (unary < limit - 1) {
            // Read k bits
            int remainder = readBits(k);
            val = (unary << k) | remainder;
        } else {
            // Read full value
            val = readBits(8); // bpp bits
        }

        // Map from non-negative to signed
        if ((val & 1) == 0)
            return val >> 1;
        else
            return -((val + 1) >> 1);
    }

    private int decodeRun(int Ra, int[] curLine, int col, int width, int[] prevLine, int row) {
        // Simplified run mode — read run length then interruption
        int runLen = 0;
        while (col + runLen < width) {
            if (RUNindex < 32 && readBit() == 1) {
                runLen += (1 << J[RUNindex]);
                if (RUNindex < 31) RUNindex++;
            } else {
                break;
            }
        }

        // Fill run pixels
        for (int i = 0; i < runLen && col + i < width; i++) {
            curLine[col + i] = Ra;
        }

        if (col + runLen < width) {
            // Run interruption
            int Rb = prevLine[col + runLen];
            int Ix = (Math.abs(Ra - Rb) <= 0) ? 1 : 0;
            int k = computeRunK(Ix);
            int Errval = decodeGolomb(k, LIMIT);
            int Px = (Ix == 1) ? Ra : Rb;
            int Rx = (Px + Errval + RANGE) % RANGE;
            curLine[col + runLen] = clamp(Rx);
            if (RUNindex > 0) RUNindex--;
        }

        return curLine[col];
    }

    private int computeRunK(int Ix) {
        int idx = 365 + Ix;
        int Av = A[idx] + (N[idx] >> 1);
        int Nv = N[idx];
        int k = 0;
        while ((Nv << k) < Av) k++;
        return k;
    }

    private int readBit() {
        int bit = (curByte >> (7 - bitPos)) & 1;
        bitPos++;
        if (bitPos >= 8) {
            advanceByte();
        }
        return bit;
    }

    private int readBits(int count) {
        int val = 0;
        for (int i = 0; i < count; i++) {
            val = (val << 1) | readBit();
        }
        return val;
    }

    private void advanceByte() {
        bytePos++;
        bitPos = 0;
        if (bytePos < input.length) {
            curByte = input[bytePos] & 0xFF;
            // JPEG-LS byte stuffing: after 0xFF, skip 0x00
            if (curByte == 0xFF && bytePos + 1 < input.length) {
                int peek = input[bytePos + 1] & 0xFF;
                if (peek == 0x00) {
                    // Stuffed byte — use 0xFF as data, skip the 0x00
                    bytePos++; // skip the 0x00
                    bitPos = 1; // JPEG-LS: after FF, only 7 bits in next byte
                    if (bytePos + 1 < input.length) {
                        curByte = input[bytePos + 1] & 0xFF;
                    }
                }
            }
        } else {
            curByte = 0;
        }
    }
}
