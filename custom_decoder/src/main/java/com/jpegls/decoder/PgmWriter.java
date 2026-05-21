package com.jpegls.decoder;

import java.io.*;

public class PgmWriter {

    public static void write(String path, byte[] pixels, int width, int height) throws IOException {
        try (FileOutputStream fos = new FileOutputStream(path)) {
            String header = "P5\n" + width + " " + height + "\n255\n";
            fos.write(header.getBytes());
            fos.write(pixels);
        }
    }
}
