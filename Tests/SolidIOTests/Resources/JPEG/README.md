# JPEG interoperability fixtures

These small fixtures exercise the JPEG forms accepted at the PostScript DCT filter boundary.

- The grayscale, RGB, progressive, separate-scan, and restart fixtures were produced by `cjpeg` 3.1.4.1. The direct RGB fixture contains Adobe APP14 transform 0.
- The YCCK fixture was converted with LittleCMS `jpgicc` 3.4 and contains Adobe APP14 transform 2.
- The CMYK fixture was produced by ImageIO and contains Adobe APP14 transform 0.

Four-component expectations were cross-checked against libjpeg-turbo CMYK output after applying the Adobe component inversion. The tests allow a two-byte tolerance for YCCK IDCT rounding and do not link libjpeg-turbo.

The fixtures are committed so the test suite has no dependency on those tools.
