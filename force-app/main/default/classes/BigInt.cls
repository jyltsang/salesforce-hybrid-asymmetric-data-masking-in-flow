public with sharing class BigInt {

    public class BigIntException extends Exception {}

    private static final String HEX = '0123456789abcdef';
    private static final Decimal CHUNK = Decimal.valueOf(4294967296L);   // 2^32

    private Decimal v;   // non-negative integer, scale 0

    public BigInt(String text, Integer radix) {
        if (radix != 16) throw new BigIntException('Only radix 16 is supported.');
        String s = (text == null) ? '' : text.trim().toLowerCase();
        if (s.startsWith('0x')) s = s.substring(2);
        if (s.length() == 0) throw new BigIntException('Empty number string.');

        Decimal acc = 0;
        Integer i = 0;
        Integer first = Math.mod(s.length(), 8);
        if (first > 0) {
            acc = hexToLong(s.substring(0, first));
            i = first;
        }
        while (i < s.length()) {
            acc = acc * CHUNK + hexToLong(s.substring(i, i + 8));
            i += 8;
        }
        v = acc;
    }

    private BigInt(Decimal value) { v = value; }

    public String toHex() {
        if (v == 0) return '0';
        List<String> parts = new List<String>();   // least significant chunk first
        Decimal x = v;
        while (x > 0) {
            Decimal q = x.divide(CHUNK, 0, System.RoundingMode.DOWN);
            Decimal r = x - q * CHUNK;
            parts.add(longToHex8(r.longValue()));
            x = q;
        }
        String out = '';
        for (Integer i = parts.size() - 1; i >= 0; i--) out += parts[i];
        return out.replaceFirst('^0+(?=.)', '');
    }

    // this^exponent mod modulus
    public BigInt modPow(BigInt exponent, BigInt modulus) {
        Decimal n = modulus.v;
        if (n <= 1) throw new BigIntException('Modulus must be greater than 1.');
        Decimal base = mulmod(this.v, 1, n);
        Decimal res = 1;

        String eh = exponent.toHex();
        for (Integer i = 0; i < eh.length(); i++) {
            Integer nib = HEX.indexOf(eh.substring(i, i + 1));
            for (Integer b = 3; b >= 0; b--) {
                res = mulmod(res, res, n);
                if (((nib >> b) & 1) == 1) res = mulmod(res, base, n);
            }
        }
        return new BigInt(res);
    }

    // ---------- helpers ----------

    private static Decimal mulmod(Decimal a, Decimal b, Decimal n) {
        Decimal p = a * b;
        Decimal q = p.divide(n, 0, System.RoundingMode.DOWN);
        return p - q * n;
    }

    private static Long hexToLong(String h) {
        Long r = 0L;
        for (Integer i = 0; i < h.length(); i++) {
            Integer d = HEX.indexOf(h.substring(i, i + 1));
            if (d < 0) throw new BigIntException('Invalid hex character: ' + h.substring(i, i + 1));
            r = r * 16 + d;
        }
        return r;
    }

    private static String longToHex8(Long n) {
        String s = '';
        Long x = n;
        for (Integer i = 0; i < 8; i++) {
            Integer nib = Integer.valueOf(x & 15L);
            s = HEX.substring(nib, nib + 1) + s;
            x = x >> 4;
        }
        return s;
    }
}