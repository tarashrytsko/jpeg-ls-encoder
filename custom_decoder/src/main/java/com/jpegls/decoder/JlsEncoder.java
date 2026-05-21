package com.jpegls.decoder;

import java.io.*;

/**
 * Pure Java JPEG-LS encoder for 8-bit grayscale, NEAR=0 (lossless).
 * Produces a single-scan JLS file from raw pixel data.
 */
public class JlsEncoder {

    private static final int MAXVAL = 255;
    private static final int RANGE = MAXVAL + 1;
    private static final int NEAR = 0;
    private static final int RESET = 64;
    private static final int T1 = 3, T2 = 7, T3 = 21;
    private static final int LIMIT = 127;

    private int[] N = new int[367];
    private int[] A = new int[367];
    private int[] B = new int[367];
    private int[] C = new int[367];

    private int RUNindex = 0;
    private static final int[] J = {
        0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,5,5,6,6,7,7,8,9,10,11,12,13,14,15
    };

    private ByteArrayOutputStream output;
    private int bitBuffer;
    private int bitsInBuffer;

    public byte[] encode(byte[] pixels, int width, int height) {
        output = new ByteArrayOutputStream();
        bitBuffer = 0;
        bitsInBuffer = 0;
        initState();

        writeHeader(width, height);

        int[] prevLine = new int[width + 1];
        int[] curLine = new int[width + 1];

        for (int row = 0; row < height; row++) {
            for (int col = 0; col < width; col++) {
                curLine[col] = pixels[row * width + col] & 0xFF;
            }

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

                int Rx = curLine[col];

                // Regular mode
                int Px = predict(Ra, Rb, Rc);
                Px = Px + (sign == 0 ? C[ctx] : -C[ctx]);
                Px = clamp(Px);

                int Errval = Rx - Px;
                if (sign == 1) Errval = -Errval;

                // Modulo reduction
                if (Errval < -(RANGE / 2)) Errval += RANGE;
                if (Errval >= (RANGE / 2)) Errval -= RANGE;

                int k = computeK(ctx);
                int mappedErr = mapError(Errval, k, ctx);
                encodeGolomb(mappedErr, k, LIMIT);

                // Update context (use original error before mapping)
                int origErr = (sign == 1) ? -Errval : Errval;
                B[ctx] += origErr;
                A[ctx] += Math.abs(origErr);
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

            System.arraycopy(curLine, 0, prevLine, 0, width);
        }

        flushBits();
        writeFooter();
        return output.toByteArray();
    }

    private void initState() {
        for (int i = 0; i < 367; i++) {
            N[i] = 1;
            A[i] = 4;
            B[i] = 0;
            C[i] = 0;
        }
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
        int k = 0;
        while ((N[ctx] << k) < A[ctx] && k < 8) k++;
        return k;
    }

    private int mapError(int Errval, int k, int ctx) {
        if (Errval >= 0) return 2 * Errval;
        return -2 * Errval - 1;
    }

    private void encodeGolomb(int val, int k, int limit) {
        int unary = val >> k;
        if (unary < limit - 1) {
            // Write unary zeros + 1
            for (int i = 0; i < unary; i++) writeBit(0);
            writeBit(1);
            // Write k-bit remainder
            int remainder = val & ((1 << k) - 1);
            writeBits(remainder, k);
        } else {
            // Write (limit-1) zeros + 1 + bpp-bit value
            for (int i = 0; i < limit - 1; i++) writeBit(0);
            writeBit(1);
            writeBits(val, 8);
        }
    }

    private void writeBit(int bit) {
        bitBuffer = (bitBuffer << 1) | (bit & 1);
        bitsInBuffer++;
        if (bitsInBuffer == 8) {
            emitByte(bitBuffer);
            bitBuffer = 0;
            bitsInBuffer = 0;
        }
    }

    private void writeBits(int val, int count) {
        for (int i = count - 1; i >= 0; i--) {
            writeBit((val >> i) & 1);
        }
    }

    private void emitByte(int b) {
        output.write(b & 0xFF);
        // JPEG-LS byte stuffing: after 0xFF, insert 0x00
        if ((b & 0xFF) == 0xFF) {
            output.write(0x00);
        }
    }

    private void flushBits() {
        if (bitsInBuffer > 0) {
            bitBuffer <<= (8 - bitsInBuffer);
            emitByte(bitBuffer);
            bitBuffer = 0;
            bitsInBuffer = 0;
        }
    }

    private void writeHeader(int width, int height) {
        // SOI
        output.write(0xFF); output.write(0xD8);
        // SOF (JPEG-LS)
        output.write(0xFF); output.write(0xF7);
        output.write(0x00); output.write(0x0B); // length=11
        output.write(0x08);                      // precision=8
        output.write((height >> 8) & 0xFF); output.write(height & 0xFF);
        output.write((width >> 8) & 0xFF); output.write(width & 0xFF);
        output.write(0x01);                      // ncomp=1
        output.write(0x01); output.write(0x11); output.write(0x00); // comp1: id=1, samp=11, table=0
        // SOS
        output.write(0xFF); output.write(0xDA);
        output.write(0x00); output.write(0x08); // length=8
        output.write(0x01);                      // ncomp=1
        output.write(0x01); output.write(0x00); // comp1: id=1, table=0
        output.write(0x00); output.write(0x00); // unused
        output.write(NEAR);                      // NEAR + interleave
    }

    private void writeFooter() {
        output.write(0xFF); output.write(0xD9);
    }
}
