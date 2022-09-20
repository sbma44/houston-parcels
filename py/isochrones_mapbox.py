# http://dev.opentripplanner.org/apidoc/1.0.0/resource_LIsochrone.html
import sys, os, csv, json
import requests

MAPBOX_ACCESS_TOKEN = os.environ.get('MAPBOX_ACCESS_TOKEN')
if not MAPBOX_ACCESS_TOKEN:
    raise Exception('missing env var MAPBOX_ACCESS_TOKEN')

reader = csv.DictReader(open(sys.argv[1]))

for row in reader:
    for time in range(15, 75, 15):
        out_file = '{}-{}-drive-{}.geojson'.format(row['unitid_ipeds'], row['opeid8'], time)
        print(out_file)
        if os.path.exists('isochrones/mapbox/{}'.format(out_file)):
            continue

        resp = requests.get('https://api.mapbox.com/isochrone/v1/mapbox/driving/{lng},{lat}.json?contours_minutes={time}&access_token={MAPBOX_ACCESS_TOKEN}&polygons=true'.format(lng=row['Longitude'], lat=row['Latitude'], time=time, MAPBOX_ACCESS_TOKEN=MAPBOX_ACCESS_TOKEN))
        if resp.status_code != 200:
            print(resp.text)
            continue

        geom = json.loads(resp.text)
        with open('isochrones/mapbox/{}'.format(out_file), 'w') as f:
            geom['features'][0]['properties'] = {}
            json.dump(geom['features'][0], f, indent=2)