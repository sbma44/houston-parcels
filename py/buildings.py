import sys, csv, re, os, urllib.parse

def valid_use_code(c, county):
    c = c.upper().strip()
    if '--debug' in sys.argv:
        print(c)
    if county == 'washington':
        return c[0] in ('A', 'B', 'M')
    else:
        return c and len(c) > 0 and ((c[0] in ('A', 'B')) or (c in ('F1M', 'M1', 'M3')))

county = sys.argv[1].lower().strip()

if county == 'harris':
    # handle building_other file -- includes units
    print('INSERT INTO buildings_{} (tax_id, use_code, units) VALUES'.format(county))
    with open(os.path.join(sys.argv[2], urllib.parse.unquote(sys.argv[3])), encoding='windows_1252') as building_other:
        record_count = 0
        for line in building_other:
            row = [x.strip() for x in line.split('\t')]
            if len(row) != 37:
                continue
            use_code = row[1].upper()
            if not valid_use_code(use_code, county):
                continue

            if record_count > 0:
                print(',')
            else:
                print()

            tax_id = re.sub(r'[^\d]', '', row[0]).zfill(13)
            units = 1
            try:
                units = int(row[-5])
            except:
                pass
            sys.stdout.write('(\'{tax_id}\', \'{use_code}\', {units})'.format(tax_id=tax_id, use_code=use_code, units=units))
            record_count = record_count + 1
    print(';')

    print('INSERT INTO buildings_{} (tax_id, use_code, units) VALUES'.format(county))
    with open(os.path.join(sys.argv[2], urllib.parse.unquote(sys.argv[4])), encoding='windows_1252') as building_res:
        record_count = 0
        for line in building_res:
            row = [x.strip() for x in line.split('\t')]
            if len(row) != 31:
                continue
            use_code = row[1].upper()
            if not valid_use_code(use_code, county):
                continue

            if record_count > 0:
                print(',')
            else:
                print()

            tax_id = re.sub(r'[^\d]', '', row[0]).zfill(13)
            units = 1

            sys.stdout.write('(\'{tax_id}\', \'{use_code}\', {units})'.format(tax_id=tax_id, use_code=use_code, units=units))
            record_count = record_count + 1
    print(';')

elif county in ('montgomery', 'chambers', 'washington', 'wharton', 'grimes', 'austin'):
    print('INSERT INTO buildings_{} (tax_id, use_code, units) VALUES'.format(county))

    pn = 'PropertyNumber'
    sc = 'StateCode'
    zf = 13
    if county == 'chambers':
        pn = 'Parcel_ID'
        sc = 'Primary_Category_Code'
    elif county in ('washington', 'grimes'):
        pn = 'QuickRefID'
    elif county == 'wharton':
        sc = 'V_LAND_SPTD_CDX'
        pn = 'ACCOUNT_NUM'
    elif county == 'austin':
        sc = 'Primary_Category_Code'
        pn = 'Parcel_ID'

    with open(os.path.join(sys.argv[2], urllib.parse.unquote(sys.argv[3]))) as f:
        reader = csv.DictReader(f)
        record_count = 0
        units = 1
        for row in reader:
            use_code = row.get(sc)
            tax_id = re.sub(r'[^\d]', '', row.get(pn)).zfill(zf)
            if valid_use_code(use_code, county):
                if record_count > 0:
                    print(',')
                else:
                    print()
                sys.stdout.write('(\'{tax_id}\', \'{use_code}\', {units})'.format(tax_id=tax_id, use_code=use_code, units=units))
                record_count = record_count + 1
    print(';')

elif county == 'galveston':
    print('INSERT INTO buildings_{} (tax_id, use_code, units) VALUES'.format(county))
    with open(os.path.join(sys.argv[2], urllib.parse.unquote(sys.argv[3]))) as f:
        record_count = 0
        units = 1
        for row in f:
            use_code = row[2741:2751].strip()
            tax_id = re.sub(r'[^\d]', '', row[546:596]).zfill(13)
            if valid_use_code(use_code, county):
                if record_count > 0:
                    print(',')
                else:
                    print()
                sys.stdout.write('(\'{tax_id}\', \'{use_code}\', {units})'.format(tax_id=tax_id, use_code=use_code, units=units))
                record_count = record_count + 1
    print(';')

elif county == 'matagorda':
    print('INSERT INTO buildings_{} (tax_id, use_code, units) VALUES'.format(county))
    with open(os.path.join(sys.argv[2], urllib.parse.unquote(sys.argv[3]))) as f:
        record_count = 0
        units = 1
        current_parcel_id = None
        re_sc = re.compile(r'State Codes: (.*?)\sMap ID:')
        for line in f:
            if 'Effective Acres' in line and 'Imp HS:' in line and 'Market:' in line:
                line_parts = [x.strip() for x in re.split(r'\s+', line.strip())]
                current_parcel_id = line_parts[0]
            else:
                m = re_sc.search(line)
                if not m or current_parcel_id is None:
                    continue

                state_codes = [x.strip().upper() for x in m.group(1).strip().split(',') if len(x.strip()) > 0]
                any_match = False
                for sc in state_codes:
                    if valid_use_code(sc, county):
                        use_code = sc
                        tax_id = re.sub(r'[^\d]', '', str(current_parcel_id)).zfill(13)
                        if record_count > 0:
                            print(',')
                        else:
                            print()
                        sys.stdout.write('(\'{tax_id}\', \'{use_code}\', {units})'.format(tax_id=tax_id, use_code=use_code, units=units))
                        record_count = record_count + 1
                        current_parcel_id = None
    print(';')

elif county in ('sanjacinto', 'walker', 'liberty', 'colorado', 'waller'):
    print('INSERT INTO buildings_{} (tax_id, use_code, units) VALUES'.format(county))
    with open(os.path.join(sys.argv[2], urllib.parse.unquote(sys.argv[3]))) as f:
        record_count = 0
        units = 1
        for line in f:
            tax_id = re.sub(r'[^\d]', '', str(line[0:12])).zfill(13)
            use_code = line[63:65].upper()
            if valid_use_code(use_code, county):
                if record_count > 0:
                    print(',')
                else:
                    print()
                sys.stdout.write('(\'{tax_id}\', \'{use_code}\', {units})'.format(tax_id=tax_id, use_code=use_code, units=units))
                record_count = record_count + 1
    print(';')
