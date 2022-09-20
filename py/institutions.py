import csv, sys

numeric_fields = ('Latitude', 'Longitude', 'AccuracyScore')
integer_fields = ('unitid_ipeds', 'opeid8')

reader = csv.reader(open(sys.argv[1]))
headers = next(reader)

print('DROP TABLE IF EXISTS institutions;')
print('CREATE TABLE INSTITUTIONS (')
for (i, col) in enumerate(headers):
    col = col.replace(' ', '_')
    if i > 0:
        print(',')
    if col in numeric_fields:
        sys.stdout.write('    {} NUMERIC'.format(col))
    elif col in integer_fields:
        sys.stdout.write('    {} INTEGER'.format(col))
    else:
        sys.stdout.write('    {} TEXT'.format(col))
print()
print(');')

for row in reader:
    sys.stdout.write('INSERT INTO institutions VALUES (')
    for (i, v) in enumerate(row):
        if i > 0:
            sys.stdout.write(',')
        if headers[i] in numeric_fields or headers[i] in integer_fields or len(v) == 0:
            if len(v) == 0:
                v = 'NULL'
            sys.stdout.write('{}'.format(v))
        else:
            sys.stdout.write('\'{}\''.format(v.replace('\'', '\'\'')))
    print(');')

print('ALTER TABLE institutions ADD COLUMN sector_code TEXT;')
replacements = [
    ('private', 'priv'),
    ('public', 'pub'),
    ('2-year', '2y'),
    ('4-year', '4y'),
    ('not-for-profit', 'nonprofit'),
    ('for-profit', 'forprofit'),
    (' ', '')
]
rep_str = 'LOWER(sector)'
for r in replacements:
    rep_str = 'REPLACE({}, \'{}\', \'{}\')'.format(rep_str, r[0], r[1])
print('UPDATE institutions SET sector_code={}'.format(rep_str))