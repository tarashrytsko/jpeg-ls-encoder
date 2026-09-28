#!/usr/bin/env python3
"""Count SEU-sensitive (essential) configuration bits from Vivado .ebd files (Req 8).

The .ebd is written by write_bitstream with BITSTREAM.SEU.ESSENTIALBITS=YES: after a short
text header, one 32-character '0'/'1' line per configuration word; '1' marks a bit whose
upset can change the implemented circuit ("essential"). The first frame of the readback
image is a pad frame, so totals are reported as seen in the file.

Usage: python tools/count_essential_bits.py eval/seu/*.ebd
"""
import sys, re


def count(path):
    ones = words = 0
    with open(path) as f:
        for line in f:
            s = line.strip()
            if len(s) == 32 and set(s) <= {'0', '1'}:
                words += 1
                ones += s.count('1')
    return ones, words * 32


if __name__ == '__main__':
    for p in sys.argv[1:]:
        ones, tot = count(p)
        print('%s essential=%d of %d config bits (%.3f %%)' % (p, ones, tot, 100.0 * ones / tot))
