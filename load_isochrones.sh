#!/bin/bash

set -eu -o pipefail

source "$(dirname $0)/conf.sh"

for mode in walk drive transit; do
    provider='otp'
    if [ $mode = 'drive' ]; then
        provider='mapbox'
    fi
    for mins in $(seq ${MAX_ISOCHRONE_TIME} -15 1); do
        rm -f "$TMP/$provider-$mode-$mins.sql"

        TABLE_EXISTS="$(echo "SELECT COUNT(*) FROM information_schema.columns WHERE table_name='institutions' AND column_name='isochrone_${provider}_${mode}_${mins}';" | $PSQL -q -t | tr -d '[[:space:]]')"
        if [ "$TABLE_EXISTS" -eq 0 ]; then
            echo "ALTER TABLE institutions ADD COLUMN isochrone_${provider}_${mode}_${mins} GEOMETRY(MultiPolygon, 4326);" >> "$TMP/$provider-$mode-$mins.sql"
        fi
        if [ "$(find isochrones/${provider} -name '*.geojson' -type f | grep "\-${mode}-${mins}\.geojson" | wc -l)" -gt 0 ]; then
            for iso in isochrones/${provider}/*-${mode}-${mins}.geojson; do
                FN="$(basename $iso .geojson)"
                IPEDS="$(echo $FN | cut -d '-' -f 1)"
                OPE="$(echo $FN | cut -d '-' -f 2)"

                echo "UPDATE institutions SET \
                    isochrone_${provider}_${mode}_${mins}=ST_SetSRID(ST_Multi(ST_GeomFromGeoJSON('$(cat "$iso" | jq -r .geometry | tr -d ' \t\n')')), 4326) \
                WHERE \
                    unitid_ipeds=${IPEDS} AND \
                    opeid8=${OPE};" >> "$TMP/$provider-$mode-$mins.sql"
            done
        else
            echo "UPDATE institutions SET isochrone_${provider}_${mode}_${mins}=NULL;" >> "$TMP/$provider-$mode-$mins.sql"
        fi
        if [ "$TABLE_EXISTS" -eq 0 ]; then
            echo "CREATE INDEX institutions_isochrone_${provider}_${mode}_${mins}_idx ON institutions USING GIST(isochrone_${provider}_${mode}_${mins});"  >> "$TMP/$provider-$mode-$mins.sql"
        fi

        echo "  - loading $provider-$mode-$mins"
        $PV "$TMP/$provider-$mode-$mins.sql" | $PSQL
    done
done