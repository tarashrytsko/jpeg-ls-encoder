package com.jpegls.decoder;

import java.io.*;
import java.nio.file.*;
import java.util.List;

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
            System.out.println("Usage: java -cp . com.jpegls.decoder.Main <merged.jls> <output.pgm> [--decoder path]");
            System.exit(1);
        }

        String inputPath = args[0];
        String outputPath = args[1];
        for (int i = 2; i < args.length - 1; i++) {
            if (args[i].equals("--decoder")) decoderPath = args[i + 1];
        }

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

        // Create temp directory for intermediate files
        Path tempDir = Files.createTempDirectory("jpegls_merge_");

        // Write each segment to a temp file and decode with reference decoder
        byte[][] blocks = new byte[segments.size()][];
        for (int i = 0; i < segments.size(); i++) {
            JlsParser.Segment seg = segments.get(i);
            Path jlsFile = tempDir.resolve("seg" + i + ".jls");
            Path pgmFile = tempDir.resolve("seg" + i + ".pgm");

            // Write segment (strip duplicate SOI if present)
            byte[] data = seg.data;
            if (data.length > 4 && data[0] == (byte)0xFF && data[1] == (byte)0xD8
                && data[2] == (byte)0xFF && data[3] == (byte)0xD8) {
                // Strip first 2 bytes (duplicate SOI)
                byte[] fixed = new byte[data.length - 2];
                System.arraycopy(data, 2, fixed, 0, fixed.length);
                data = fixed;
            }
            Files.write(jlsFile, data);

            // Decode with reference decoder
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
                blocks[i] = new byte[blockWidth * blockHeight]; // fill with zeros
            }
        }

        // Stitch
        ImageStitcher stitcher = new ImageStitcher(cols, swaths, blockWidth, blockHeight);
        byte[] fullImage = stitcher.stitch(blocks);
        int fullWidth = stitcher.getFullWidth();
        int fullHeight = stitcher.getFullHeight();

        // Write output PGM
        PgmWriter.write(outputPath, fullImage, fullWidth, fullHeight);
        System.out.printf("Output: %s (%dx%d, %d bytes)%n", outputPath, fullWidth, fullHeight, Files.size(Paths.get(outputPath)));

        // Cleanup temp files
        for (File f : tempDir.toFile().listFiles()) f.delete();
        tempDir.toFile().delete();
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
