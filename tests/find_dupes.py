import os, os.path
import hashlib
import sys

hashes = {}
for fn in os.listdir(sys.argv[1]):
    with open(os.path.join(sys.argv[1], fn)) as f:
        h = hashlib.md5(f.read().encode('utf-8')).hexdigest()
    if h in hashes:
        print('collision! {}'.format(hashes[h]))
    else:
        hashes[h] = fn

print('checked {} files'.format(len(hashes)))