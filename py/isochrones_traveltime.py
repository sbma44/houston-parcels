# https://docs.traveltime.com/api/reference/time-map#single-origin-with-departure-time
import sys, os, csv, time, json
import requests

TRAVELTIME_API_KEY = os.environ.get('TRAVELTIME_API_KEY')
if not TRAVELTIME_API_KEY:
    raise Error('missing env var TRAVELTIME_API_KEY')
TRAVELTIME_APP_ID = os.environ.get('TRAVELTIME_APP_ID')
if not TRAVELTIME_APP_ID:
    raise Error('missing env var TRAVELTIME_APP_ID')

reader = csv.DictReader(open(sys.argv[1]))

for row in reader:
    for travel_mode in ('public_transport', 'driving', 'walking'):
        travel_mode_friendly = travel_mode
        if travel_mode_friendly == 'public_transport':
            travel_mode_friendly = 'transit'
        elif travel_mode_friendly == 'driving':
            travel_mode_friendly = 'drive'
        elif travel_mode_friendly == 'walking':
            travel_mode_friendly = 'walk'
        out_file = '{}-{}-{}.geojson'.format(row['unitid_ipeds'], row['opeid8'], travel_mode_friendly)
        print(out_file)
        if os.path.exists('isochrones/traveltime/{}'.format(out_file)):
            continue

        headers = {
            'X-Application-Id': TRAVELTIME_APP_ID,
            'X-Api-Key': TRAVELTIME_API_KEY,
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }
        data = json.dumps({
            "departure_searches": [
                {
                "id": out_file.split('.')[0],
                "coords": {
                    "lat": float(row['Latitude']),
                    "lng": float(row['Longitude'])
                },
                "transportation": {
                    "type": travel_mode
                },
                "departure_time": "2020-09-02T20:30:00Z",
                "travel_time": 1800
                }
            ]
        })
        resp = requests.post('https://api.traveltimeapp.com/v4/time-map', data=data, headers=headers)
        if resp.status_code != 200:
            print(resp.text)
            time.sleep(3)
            continue

        geometry = json.loads(resp.text)['results'][0]['shapes'][0]['shell']
        geometry = [[x['lng'], x['lat']] for x in geometry]
        geo = {
            'type': 'Feature',
            'geometry': {
                'type': 'Polygon',
                'coordinates': [geometry]
            }
        }

        with open('isochrones/traveltime/{}'.format(out_file), 'w') as f:
            json.dump(geo, f, indent=2)

        time.sleep(3)