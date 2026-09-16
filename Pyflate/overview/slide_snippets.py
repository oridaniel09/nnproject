"""Code snippets for the presentation slides.

Trimmed copies of the two pyflate optimizations, and the original code they
replace, with the long explanatory comments cut down so each block fits on a
slide and screenshots cleanly. Nothing imports or runs this file.

The real code lives in:
    Pyflate/src/run_benchmark.py            optimized
      build_decode_table()   line 222       limit / base / perm tables
      find_next_symbol()     line 249       length walk, inlined bit access
      move_to_front()        line 338       in-place rotation
    Pyflate/src/run_benchmark.baseline.py   unmodified pyperformance original
      find_next_symbol()     line 224
      move_to_front()        line 289
"""

# ---------- 1. Build the tables: once per Huffman table ----------

def build_decode_table(self):
    limit = [-1] * (self.max_bits + 1)
    base = [0] * (self.max_bits + 1)
    perm = []
    for index, x in enumerate(self.table):
        perm.append(x.code)
        if limit[x.bits] < 0:
            base[x.bits] = x.symbol - index
        limit[x.bits] = x.symbol
    self.limit, self.base, self.perm = limit, base, perm


# ---------- 2. Decode one symbol: walk lengths, no function calls ----------

def find_next_symbol(self, field, reversed=True):
    if not reversed and self.perm is not None:
        limit = self.limit
        n = self.min_bits
        if field.bits < n:
            field.needbits(n)
        v = (field.bitfield >> (field.bits - n)) & ((1 << n) - 1)
        while v > limit[n]:                      # not a complete code yet
            n += 1                               # take one more bit
            if field.bits < n:
                field.needbits(n)
            v = (field.bitfield >> (field.bits - n)) & ((1 << n) - 1)
        remaining = field.bits - n               # consume the n bits
        field.bits = remaining
        field.bitfield &= (1 << remaining) - 1
        return self.perm[v - self.base[n]]


# ---------- 3. Move-to-front: rotate in place ----------

def move_to_front(l, c):
    if c:
        l.insert(0, l.pop(c))


# ---------- the original, for a before/after slide ----------

def find_next_symbol_ORIGINAL(self, field, reversed=True):
    cached_length = -1
    cached = None
    for x in self.table:
        if cached_length != x.bits:
            cached = field.snoopbits(x.bits)
            cached_length = x.bits
        if (reversed and x.reverse_symbol == cached) or (not reversed and x.symbol == cached):
            field.readbits(x.bits)
            return x.code


def move_to_front_ORIGINAL(l, c):
    l[:] = l[c:c + 1] + l[0:c] + l[c + 1:]
