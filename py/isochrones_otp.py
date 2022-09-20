# http://dev.opentripplanner.org/apidoc/1.0.0/resource_LIsochrone.html
import sys, os, csv, json
import requests

reader = csv.DictReader(open(sys.argv[1]))

for row in reader:
    for travel_mode in ('TRANSIT,WALK', 'WALK'):
        for time in range(15, 135, 15):
            travel_mode_friendly = travel_mode
            if travel_mode_friendly == 'TRANSIT,WALK':
                travel_mode_friendly = 'transit'
            elif travel_mode_friendly == 'WALK':
                travel_mode_friendly = 'walk'
            out_file = '{}-{}-{}-{}.geojson'.format(row['unitid_ipeds'], row['opeid8'], travel_mode_friendly, time)
            print(out_file)
            if os.path.exists('isochrones/otp/{}'.format(out_file)):
                continue

            cutoffsec = time * 60
            resp = requests.get('http://localhost:8080/otp/routers/houston-20200110/isochrone?fromPlace={lat},{lng}&mode={mode}&time=4:30pm&date=01-15-2020&cutoffSec={cutoffsec}'.format(lng=row['Longitude'], lat=row['Latitude'], mode=travel_mode, cutoffsec=cutoffsec))
            if resp.status_code != 200:
                print(resp.text)
                continue

            geom = json.loads(resp.text)
            with open('isochrones/otp/{}'.format(out_file), 'w') as f:
                json.dump(geom['features'][0], f, indent=2)