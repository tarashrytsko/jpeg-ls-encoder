package com.jpegls.decoder;

import java.io.*;
import java.util.*;

public class JlsParser {

    public static class Segment {
        public byte[] data;
        public int width;
        public int height;
        public int precision;
        public int near;

        public Segment(byte[] data) {
            this.data = data;
            parseHeader();
        }

        private void parseHeader() {
            // FFD8 FFF7 000B 08 HH HL WH WL 01 01 11 00 FFDA 0008 01 01 00 00 00 NEAR
            if (data.length < 26) return;
            precision = data[6] & 0xFF;
            height = ((data[7] & 0xFF) << 8) | (data[8] & 0xFF);
            width = ((data[9] & 0xFF) << 8) | (data[10] & 0xFF);
            near = data[24] & 0xFF;
        }
    }

    public static List<Segment> parse(byte[] merged) {
        List<Segment> segments = new ArrayList<>();
        List<Integer> soiPositions = new ArrayList<>();

        for (int i = 0; i < merged.length - 1; i++) {
            if ((merged[i] & 0xFF) == 0xFF && (merged[i + 1] & 0xFF) == 0xD8) {
                soiPositions.add(i);
            }
        }

        for (int i = 0; i < soiPositions.size(); i++) {
            int start = soiPositions.get(i);
            int end = (i + 1 < soiPositions.size()) ? soiPositions.get(i + 1) : merged.length;
            if (end - start < 30) continue; // skip fragments (duplicate SOI markers)
            byte[] segData = Arrays.copyOfRange(merged, start, end);
            segments.add(new Segment(segData));
        }

        return segments;
    }

    public static List<Segment> parseFile(String path) throws IOException {
        byte[] data = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(path));
        return parse(data);
    }
}
