import sys, os, csv, time, json
import requests

BING_API_KEY = os.environ.get('BING_API_KEY')
if not BING_API_KEY:
    raise Error('missing env var BING_API_KEY')

reader = csv.DictReader(open(sys.argv[1]))

for row in reader:
    waypoint = '{},{}'.format(row['Latitude'], row['Longitude'])
    for travel_mode in ('drive', 'walk'):
        out_file = '{}-{}-{}.geojson'.format(row['unitid_ipeds'], row['opeid8'], travel_mode)
        print(out_file)
        if os.path.exists('isochrones/bing/{}'.format(out_file)):
            continue

        resp = requests.get('http://dev.virtualearth.net/REST/v1/Routes/IsochronesAsync?waypoint={waypoint}&maxtime=1800&optimize=timeWithTraffic&dateTime=1/15/2020+20%3A30Z&travelMode={travel_mode}&key={BING_API_KEY}'.format(waypoint=waypoint, travel_mode=travel_mode, BING_API_KEY=BING_API_KEY))

        error = False
        ready = False
        resp_obj = {}
        while not ready:
            resp_obj = json.loads(resp.text)
            ready = resp_obj['resourceSets'][0]['resources'][0]['isCompleted']
            if not ready:
                print('sleeping...')
                callback_url = resp_obj['resourceSets'][0]['resources'][0]['callbackUrl']
                error_message = resp_obj['resourceSets'][0]['resources'][0]['errorMessage']
                if len(callback_url) == 0 and len(error_message) > 0:
                    print(error_message)
                    error = True
                    break
                time.sleep(3)
                resp = requests.get(callback_url)

        if error:
            continue

        resp = requests.get(resp_obj['resourceSets'][0]['resources'][0]['resultUrl'])
        result_obj = json.loads(resp.text)
        coords = [[x[1], x[0]] for x in result_obj['resourceSets'][0]['resources'][0]['polygons'][0]['coordinates'][0]]
        geo = {
            'type': 'Feature',
            'properties': {},
            'geometry': {
                'type': 'Polygon',
                'coordinates': [coords]
            }
        }
        with open('isochrones/bing/{}'.format(out_file), 'w') as f:
            json.dump(geo, f, indent=2)

        # http://dev.virtualearth.net/REST/v1/Routes/IsochronesAsyncCallback?key=AsQ5jrMDv98VuyY2NsmjK1nYPEjRTGhdnK92vcraJevQ8PQpdh0k8A5aiCj1MYU8&requestId=64fd8451-d56d-4b1b-b686-3e658edd9032