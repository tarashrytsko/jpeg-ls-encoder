package com.jpegls.decoder;

/**
 * Stitches 12 decoded blocks (500x375 each) into a full 1500x1500 image.
 * Layout: 3 columns x 4 swaths.
 * Order: enc0a,enc1a,enc2a (swath0), enc3a,enc4a,enc5a (swath1),
 *         enc0b,enc1b,enc2b (swath2), enc3b,enc4b,enc5b (swath3)
 */
public class ImageStitcher {

    private final int cols;
    private final int swaths;
    private final int blockWidth;
    private final int blockHeight;
    private final int fullWidth;
    private final int fullHeight;

    public ImageStitcher(int cols, int swaths, int blockWidth, int blockHeight) {
        this.cols = cols;
        this.swaths = swaths;
        this.blockWidth = blockWidth;
        this.blockHeight = blockHeight;
        this.fullWidth = cols * blockWidth;
        this.fullHeight = swaths * blockHeight;
    }

    /**
     * @param blocks array of decoded pixel blocks in order:
     *   [swath0_col0, swath0_col1, swath0_col2, swath1_col0, ..., swath3_col2]
     */
    public byte[] stitch(byte[][] blocks) {
        byte[] image = new byte[fullWidth * fullHeight];

        for (int seg = 0; seg < blocks.length; seg++) {
            int swath = seg / cols;
            int col = seg % cols;
            int xOff = col * blockWidth;
            int yOff = swath * blockHeight;

            byte[] block = blocks[seg];
            for (int y = 0; y < blockHeight; y++) {
                System.arraycopy(block, y * blockWidth, image,
                    (yOff + y) * fullWidth + xOff, blockWidth);
            }
        }

        return image;
    }

    public int getFullWidth() { return fullWidth; }
    public int getFullHeight() { return fullHeight; }
}
