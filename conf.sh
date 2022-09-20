PG_HOST="${PG_HOST:-127.0.0.1}"
DB_NAME="${DB_NAME:-houston_parcels}"
PGPASSWORD="${PGPASSWORD:-}"
export PGPASSWORD

# in case you have civilians poking around in qgis
VIEWER_NAME="${VIEWER_NAME:-houston_viewer}"
VIEWER_PASSWORD="${VIEWER_PASSWORD:-}"

PSQL="psql -q -U postgres -d ${DB_NAME} -h ${PG_HOST}"
TMP="/tmp/houston-parcels"

# EDIT THESE IF YOU WISH TO GENERATE NEW ISOCHRONES
export BING_API_KEY='abc'
export TRAVELTIME_API_KEY='def'
export TRAVELTIME_APP_ID='ghi'
export MAPBOX_ACCESS_TOKEN='pk.jkl'

MAX_ISOCHRONE_TIME=30

# location of parcel & tax roll data
export S3_BUCKET='s3.tomlee.wtf'
S3_BUCKET_ROOT_URL="https://s3.amazonaws.com/${S3_BUCKET}/houston-gis"

function download() {
    if [ ! -f "${TMP}/${1}" ]; then
        curl -s "${S3_BUCKET_ROOT_URL}/${1}" > "${TMP}/${1}"
    fi
}

PV="$(which pv)"
if [ -z "$PV" ]; then PV='cat'; fi

function _jq() {
    echo $(jq -r $1 < "${DIR}/parcel-conf.json" | sed -E -e 's/^\s*"//' -e 's/",?\s*$//' -e 's/"//')
}
export -f _jq

DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)"
