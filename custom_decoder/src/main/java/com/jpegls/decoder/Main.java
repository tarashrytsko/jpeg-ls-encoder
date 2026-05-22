package com.jpegls.decoder;

import java.io.*;
import java.nio.file.*;
import java.util.*;

/**
 * JPEG-LS Merger Tool
 * Usage: java -cp . com.jpegls.decoder.Main <merged.jls> <output.pgm> [--decoder path/to/JPEGLSdec.exe]
 *
 * Parses a concatenated multi-segment JLS file, decodes each segment using
 * the reference decoder (JPEGLSdec.exe), stitches into a full image, and
 * outputs a single PGM file.
 */
public class Main {

    private static String decoderPath = "JPEGLSdec.exe";

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.out.println("Usage: java -cp . com.jpegls.decoder.Main <merged.jls|folder> <output.pgm> [--decoder path]");
            System.exit(1);
        }

        String inputPath = args[0];
        String outputPath = args[1];
        for (int i = 2; i < args.length - 1; i++) {
            if (args[i].equals("--decoder")) decoderPath = args[i + 1];
        }

        File inputFile = new File(inputPath);
        if (inputFile.isDirectory()) {
            runFolderMode(inputFile, outputPath);
        } else {
            runMergedMode(inputPath, outputPath);
        }
    }

    private static void runMergedMode(String inputPath, String outputPath) throws Exception {
        System.out.println("Parsing: " + inputPath);
        List<JlsParser.Segment> segments = JlsParser.parseFile(inputPath);
        System.out.println("Found " + segments.size() + " segments");

        if (segments.isEmpty()) {
            System.err.println("ERROR: No JLS segments found");
            System.exit(1);
        }

        int blockWidth = segments.get(0).width;
        int blockHeight = segments.get(0).height;
        int cols = 3;
        int swaths = segments.size() / cols;
        System.out.printf("Grid: %d cols x %d swaths, block %dx%d%n", cols, swaths, blockWidth, blockHeight);

        Path tempDir = Files.createTempDirectory("jpegls_merge_");
        byte[][] blocks = decodeSegments(segments, blockWidth, blockHeight, tempDir);
        cleanupAndWrite(blocks, cols, swaths, blockWidth, blockHeight, outputPath, tempDir);
    }

    private static void runFolderMode(File folder, String outputPath) throws Exception {
        System.out.println("Folder mode: " + folder.getAbsolutePath());

        // Discover enc*.jls files and determine grid dimensions
        File[] jlsFiles = folder.listFiles(f -> f.getName().matches("enc\\d+[a-z]\\.jls"));
        if (jlsFiles == null || jlsFiles.length == 0) {
            System.err.println("ERROR: No enc*.jls files found in folder");
            System.exit(1);
        }

        int maxEnc = 0;
        char maxLetter = 'a';
        for (File f : jlsFiles) {
            String name = f.getName(); // enc{N}{letter}.jls
            int enc = Integer.parseInt(name.substring(3, name.length() - 5));
            char letter = name.charAt(name.length() - 5);
            if (enc > maxEnc) maxEnc = enc;
            if (letter > maxLetter) maxLetter = letter;
        }
        int cols = maxEnc + 1;
        int swaths = (maxLetter - 'a') + 1;
        System.out.printf("Detected grid: %d cols x %d swaths (%d segments)%n", cols, swaths, cols * swaths);

        // Build ordered list of segments: swath-major (letter), then col (encoder index)
        List<JlsParser.Segment> segments = new ArrayList<>();
        List<String> labels = new ArrayList<>();
        for (int sw = 0; sw < swaths; sw++) {
            char letter = (char) ('a' + sw);
            for (int col = 0; col < cols; col++) {
                String fname = String.format("enc%d%c.jls", col, letter);
                File f = new File(folder, fname);
                if (!f.exists()) {
                    System.err.printf("  WARNING: %s not found, using blank block%n", fname);
                    segments.add(null);
                } else {
                    byte[] data = Files.readAllBytes(f.toPath());
                    segments.add(new JlsParser.Segment(data));
                }
                labels.add(fname);
            }
        }

        int blockWidth = 0, blockHeight = 0;
        for (JlsParser.Segment s : segments) {
            if (s != null) { blockWidth = s.width; blockHeight = s.height; break; }
        }
        System.out.printf("Block size: %dx%d%n", blockWidth, blockHeight);

        Path tempDir = Files.createTempDirectory("jpegls_merge_");
        byte[][] blocks = new byte[segments.size()][];
        for (int i = 0; i < segments.size(); i++) {
            JlsParser.Segment seg = segments.get(i);
            if (seg == null) {
                blocks[i] = new byte[blockWidth * blockHeight];
                continue;
            }
            Path jlsFile = tempDir.resolve("seg" + i + ".jls");
            Path pgmFile = tempDir.resolve("seg" + i + ".pgm");

            byte[] data = stripDuplicateSoi(seg.data);
            Files.write(jlsFile, data);

            ProcessBuilder pb = new ProcessBuilder(decoderPath, jlsFile.toString(), pgmFile.toString());
            pb.redirectErrorStream(true);
            Process p = pb.start();
            p.getInputStream().readAllBytes();
            p.waitFor();

            if (Files.exists(pgmFile) && Files.size(pgmFile) > 0) {
                blocks[i] = readPgmPixels(pgmFile);
                System.out.printf("  %s: %dx%d decoded (%d bytes)%n", labels.get(i), seg.width, seg.height, blocks[i].length);
            } else {
                System.err.printf("  ERROR: Failed to decode %s%n", labels.get(i));
                blocks[i] = new byte[blockWidth * blockHeight];
            }
        }

        cleanupAndWrite(blocks, cols, swaths, blockWidth, blockHeight, outputPath, tempDir);
    }

    private static byte[][] decodeSegments(List<JlsParser.Segment> segments,
            int blockWidth, int blockHeight, Path tempDir) throws Exception {
        byte[][] blocks = new byte[segments.size()][];
        for (int i = 0; i < segments.size(); i++) {
            JlsParser.Segment seg = segments.get(i);
            Path jlsFile = tempDir.resolve("seg" + i + ".jls");
            Path pgmFile = tempDir.resolve("seg" + i + ".pgm");

            byte[] data = stripDuplicateSoi(seg.data);
            Files.write(jlsFile, data);

            ProcessBuilder pb = new ProcessBuilder(decoderPath, jlsFile.toString(), pgmFile.toString());
            pb.redirectErrorStream(true);
            Process p = pb.start();
            p.getInputStream().readAllBytes();
            p.waitFor();

            if (Files.exists(pgmFile) && Files.size(pgmFile) > 0) {
                blocks[i] = readPgmPixels(pgmFile);
                System.out.printf("  Segment %d: %dx%d decoded (%d bytes)%n", i, seg.width, seg.height, blocks[i].length);
            } else {
                System.err.printf("  ERROR: Failed to decode segment %d%n", i);
                blocks[i] = new byte[blockWidth * blockHeight];
            }
        }
        return blocks;
    }

    private static void cleanupAndWrite(byte[][] blocks, int cols, int swaths,
            int blockWidth, int blockHeight, String outputPath, Path tempDir) throws Exception {
        ImageStitcher stitcher = new ImageStitcher(cols, swaths, blockWidth, blockHeight);
        byte[] fullImage = stitcher.stitch(blocks);
        int fullWidth = stitcher.getFullWidth();
        int fullHeight = stitcher.getFullHeight();

        PgmWriter.write(outputPath, fullImage, fullWidth, fullHeight);
        System.out.printf("Output: %s (%dx%d, %d bytes)%n", outputPath, fullWidth, fullHeight, Files.size(Paths.get(outputPath)));

        for (File f : tempDir.toFile().listFiles()) f.delete();
        tempDir.toFile().delete();
    }

    private static byte[] stripDuplicateSoi(byte[] data) {
        if (data.length > 4 && data[0] == (byte)0xFF && data[1] == (byte)0xD8
                && data[2] == (byte)0xFF && data[3] == (byte)0xD8) {
            byte[] fixed = new byte[data.length - 2];
            System.arraycopy(data, 2, fixed, 0, fixed.length);
            return fixed;
        }
        return data;
    }

    private static byte[] readPgmPixels(Path pgmPath) throws IOException {
        try (InputStream is = Files.newInputStream(pgmPath)) {
            // Skip P5 header
            is.read(); is.read(); is.read(); // "P5\n"
            // Read dimensions line (skip until newline)
            int b;
            while ((b = is.read()) != '\n') {} // width height\n
            // Read maxval line
            while ((b = is.read()) != '\n') {} // 255\n
            // Rest is pixel data
            return is.readAllBytes();
        }
    }
}
