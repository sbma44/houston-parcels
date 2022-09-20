import sys, csv

writer = csv.writer(sys.stdout, delimiter='\t')
reader = csv.reader(sys.stdin, delimiter='\t')
header = next(reader)
pop = {}
line_size = None
for line in reader:
    if line_size is None:
        line_size = len(line)
    elif len(line) < line_size:
        continue
    pop[int(line[0])] = [float(x) for x in line[1:]]

pop_keys = list(pop.keys())
for i in range(0, len(pop)):
    for k in range(0, len(pop[pop_keys[i]])):
        for j in range(i + 1, len(pop)):
            pop[pop_keys[i]][k] += pop[pop_keys[j]][k]

writer.writerow(header)
for k in sorted(pop.keys()):
    writer.writerow([k] + pop[k])
