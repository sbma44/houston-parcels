import sys, re, collections, json

offsets = collections.defaultdict(int)

quickrefids = ['16158', '12601', '19771', '21211', '61452', '13127', '14813', '14188', '15934', '61824', '61825', '62567', '64930']

with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        # sys.stderr.write(line + '\n')
        if not 'A1' in line:
            continue
        for qr in quickrefids:
            for pos in [m.start() for m in re.finditer(qr, line)]:
                offsets[pos + len(qr)] += 1

print(json.dumps(offsets, indent=2))

