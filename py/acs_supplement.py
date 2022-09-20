import csv, sys

f = open(sys.argv[1])
reader = csv.DictReader(f)
cols = []
tracts = {}
for (i, row) in enumerate(reader):
    # check for duplicates
    tract = row['geo_id'].split('US')[-1]
    if tract in tracts.keys():
        raise Exception('duplicate tract! {}'.format(tract))
    tracts[tract] = row

    # do ALTER TABLE on first row
    if i == 0:
        for k in row:
            if k.strip() in ('geo_id', 'tract'):
                continue
            print('ALTER TABLE census ADD COLUMN IF NOT EXISTS {} NUMERIC;'.format(k.strip()))
        print()

        print('DROP TABLE IF EXISTS census_tmp; CREATE TABLE census_tmp (')
        sys.stdout.write('   tract TEXT PRIMARY KEY')
        for k in row:
            if k.strip() in ('geo_id', 'tract'):
                continue
            print(',')
            sys.stdout.write('{} NUMERIC'.format(k.strip()))
            cols.append(k.strip())
        print(');')

    # standardize on 'pct'
    row2 = {}
    for k in row:
        row2[k] = row[k]
        if k.startswith('percent_') or k.startswith('pct_'):
            new_k = k.replace('percent_', 'pct_')
            row2[new_k] = row2[k]
            del row2[k]
    row = row2

    sys.stdout.write('INSERT INTO census_tmp (tract, {}) VALUES (\'{}\', '.format(', '.join(cols), tract))
    first = True
    for k in row:
        v = row[k].strip()
        if k.strip() in ('geo_id', 'tract'):
            continue
        elif v == '250,000+':
            v = 250000
        elif v == '2,500-':
            v = 2500
        elif v.strip() == '-':
            v = 'NULL'
        elif k.startswith('pct'):
            v = float(v.replace('%', '')) / 100.0
        elif '$' in row[k]:
            v = float(v.replace('$', '').replace(',', ''))

        if not first:
            sys.stdout.write(', ')
        else:
            first = False

        sys.stdout.write(str(v))
    print(');')

print('UPDATE census c SET')
for (i,c) in enumerate(cols):
    if i != 0:
        print(',')
    sys.stdout.write('{}=t.{}'.format(c, c))
print('\nFROM census_tmp t WHERE c.tract=t.tract;')
print('DROP TABLE census_tmp;')