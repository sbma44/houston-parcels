import os, os.path
import hashlib
import sys

basenames = {}
for fn in os.listdir(sys.argv[1]):
    if fn.split('_')[0] in ('attainment', 'econ', 'population'):
        basenames['_'.join(os.path.basename(fn).split('_')[:-1])] = True

for fn in basenames:
    accum_times = []
    for t in (30, 45, 60):
        with open(os.path.join(sys.argv[1], '{}_{}.tsv'.format(fn, t))) as f:
            accum_times.append(len(f.readlines()))
    for i in range(len(accum_times) - 1):
        assert accum_times[i] <= accum_times[i+1]