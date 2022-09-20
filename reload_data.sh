#!/bin/bash

set -eu -o pipefail

source "conf.sh"

mkdir -p "$TMP"

function do_parcels() {
    START="$(date '+%s')"
    COUNTY="$1"

    if [ "$(_jq ".${COUNTY}.active")" != 'true' ]; then
        echo "  - skipping ${COUNTY} county parcels (source not active)"
        return 0
    fi

    echo "  - loading ${COUNTY} county parcels"

    mkdir -p "${TMP}/${COUNTY}"
    download "$(_jq ".${COUNTY}.shp.url")"
    ITER=0
    while [ "$(_jq ".${COUNTY}.shp.zip[${ITER}]")" != "null" ]; do
        (cd "${TMP}/${COUNTY}" && unzip -q -j -o $(_jq ".${COUNTY}.shp.zip[${ITER}]"))
        ITER="$((ITER+1))"
    done
    BLDG=1
    if [ "$(_jq ".${COUNTY}.bldg.url")"  = "null" ]; then
        BLDG=0
    else
        download "$(_jq ".${COUNTY}.bldg.url")" &
    fi
    ogr2ogr -dim XY -t_srs EPSG:4326 -lco precision=NO -overwrite -nln parcels_${COUNTY} -nlt PROMOTE_TO_MULTI -f PostgreSQL PG:"dbname='$DB_NAME' host='$PG_HOST' port='5432' user='postgres' password='$PGPASSWORD'" "${TMP}/${COUNTY}/$(_jq ".${COUNTY}.shp.shp")"
    echo "ALTER TABLE parcels_${COUNTY} ADD COLUMN IF NOT EXISTS tax_id TEXT;" | $PSQL
    PADDING="$(_jq ".${COUNTY}.shp.id_pad")"
    if [ "${PADDING}" = "null" ]; then PADDING=20; fi
    UC_FIELD="$(_jq ".${COUNTY}.shp.use_code_field")"
    if [ "${UC_FIELD}" != "null" ]; then
        echo "ALTER TABLE parcels_${COUNTY} RENAME COLUMN ${UC_FIELD} TO use_code;" | $PSQL
    fi
    echo "UPDATE parcels_${COUNTY} SET tax_id=LPAD(REGEXP_REPLACE($(_jq ".${COUNTY}.shp.id_field"), '[^\d]', '', 'g'), $PADDING, '0');" | $PSQL
    wait
    if [ "${BLDG}" -eq 1 ]; then
        rm -f "${TMP}/${COUNTY}/${COUNTY}-buildings.sql"
        echo "ALTER TABLE parcels_${COUNTY} ADD COLUMN use_code TEXT;

            DROP TABLE IF EXISTS buildings_${COUNTY};
            CREATE TABLE buildings_${COUNTY} (tax_id TEXT, use_code TEXT, units NUMERIC);" >> "${TMP}/${COUNTY}/${COUNTY}-buildings.sql"
        ITER=0
        while [ "$(_jq ".${COUNTY}.bldg.zip[${ITER}]")" != "null" ]; do
            (cd "${TMP}/${COUNTY}" && unzip -q -j -o $(_jq ".${COUNTY}.bldg.zip[${ITER}]"))
            ITER="$((ITER+1))"
        done
        python3 py/buildings.py "${COUNTY}" "${TMP}/${COUNTY}" $(_jq ".${COUNTY}.bldg.py_args") >> "${TMP}/${COUNTY}/${COUNTY}-buildings.sql"
        $PV "${TMP}/${COUNTY}/${COUNTY}-buildings.sql" | $PSQL

        echo "INSERT INTO parcels
            SELECT b.tax_id, b.use_code, '${COUNTY}' as src, b.units, p.wkb_geometry as geom
            FROM parcels_${COUNTY} p INNER JOIN buildings_${COUNTY} b ON b.tax_id=p.tax_id;" | $PSQL
    else
        echo "INSERT INTO parcels
            SELECT tax_id, use_code, '${COUNTY}' as src, 1 AS units, wkb_geometry as geom
            FROM parcels_${COUNTY} WHERE UPPER(LEFT(TRIM(use_code), 1))='A' OR UPPER(LEFT(TRIM(use_code), 1))='B';" | $PSQL
    fi
    if [ "${RETAIN:-0}" -ne 1 ]; then
        echo "DROP TABLE parcels_${COUNTY}; DROP TABLE IF EXISTS buildings_${COUNTY};" | $PSQL
    fi
    echo "  - loaded ${COUNTY} county parcels in $(($(date '+%s')-${START}))s"
}

# --- BEGIN INSTITUTIONS
# create table, load data
python3 ${DIR}/py/institutions.py "${DIR}/src/2021.01.04_institutions.csv" > "$TMP/institutions.sql"
$PV "$TMP/institutions.sql" | $PSQL

# add columns & indices
echo "ALTER TABLE institutions ADD COLUMN geom GEOMETRY(Point, 4326); \
    UPDATE institutions SET geom=ST_SetSRID(ST_MakePoint(Longitude, Latitude), 4326);

    ALTER TABLE institutions ADD COLUMN zip5 TEXT;
    UPDATE institutions SET zip5=LEFT(zip, 5) WHERE zip IS NOT NULL;

    CREATE INDEX institutions_geom_idx ON institutions USING GIST(geom);

    CREATE INDEX institutions_unitid_ipeds_idx ON institutions(unitid_ipeds);
    CREATE INDEX institutions_opeid8_idx ON institutions(opeid8);
    CREATE INDEX institutions_zip5 ON institutions(zip5);" | $PSQL
echo "- loaded institutions"
# --- END INSTITUTIONS

# --- BEGIN COUNTIES
download 'Texas_County_Boundaries_Detailed-shp.zip'
(cd "${TMP}" && unzip -j -q -o "${TMP}/Texas_County_Boundaries_Detailed-shp.zip")
ogr2ogr -t_srs EPSG:4326 -lco precision=NO -overwrite -nln tx_counties -nlt PROMOTE_TO_MULTI -f PostgreSQL PG:"dbname='$DB_NAME' host='$PG_HOST' port='5432' user='postgres' password='$PGPASSWORD'" "$TMP/County.shp"
# --- END COUNTIES

# --- BEGIN CENSUS
# load census data
# source: https://catalog.data.gov/dataset/tiger-line-shapefile-2019-state-texas-current-census-tract-state-based

download 'tl_2019_48_tract.zip'
(cd "${TMP}" && unzip -j -q -o "${TMP}/tl_2019_48_tract.zip")
ogr2ogr -t_srs EPSG:4326 -lco precision=NO -overwrite -nln census -f PostgreSQL PG:"dbname='$DB_NAME' host='$PG_HOST' port='5432' user='postgres' password='$PGPASSWORD'" "$TMP/tl_2019_48_tract.shp"

# make indexes/rename geom column
echo "ALTER TABLE census RENAME COLUMN wkb_geometry TO geom;
    ALTER TABLE census RENAME geoid TO tract;
    CREATE INDEX census_geom_idx ON census USING GIST(geom);
    CREATE INDEX census_tract_idx ON census(tract);" | $PSQL

# add ACS data
python3 "${DIR}/py/acs_supplement.py" "${DIR}/src/2020.09.29 ACS Demographic, Ed Attainment, Median Income, and Poverty Status Data in Texas Census Tracts.csv" > "${TMP}/acs_supplemental.sql"
$PV "${TMP}/acs_supplemental.sql" | $PSQL

echo "- loaded census"
# --- END CENSUS

# --- BEGIN PARCELS
if [ "${PARCELS:-0}" -eq 1 ]; then
    START="$(date '+%s')"
    echo '- loading parcels'
    echo "
    DROP TABLE IF EXISTS parcels;
    CREATE TABLE parcels (
        tax_id TEXT,
        use_code TEXT,
        src TEXT,
        units NUMERIC DEFAULT 1,
        geom Geometry(MultiPolygon, 4326)
    );
    CREATE INDEX parcels_tax_id_idx ON parcels(tax_id);
    CREATE INDEX parcels_use_code_idx ON parcels(use_code);
    CREATE INDEX parcels_geom_idx ON parcels USING GIST(geom);" | $PSQL

    for county in $(_jq '.|keys' | sed -E -e 's/\[//' -e 's/\]//'); do
        do_parcels "$county"
    done

    echo "- loaded parcels in $(($(date '+%s')-${START}))s"

    # --- BEGIN DEDUPLICATION
    START="$(date '+%s')"
    echo "- deleting duplicate parcels"
    echo "ALTER TABLE parcels ADD COLUMN parcel_id SERIAL;
    CREATE INDEX parcel_id_idx ON parcels(parcel_id);
    DELETE FROM parcels a USING parcels b WHERE
        a.parcel_id > b.parcel_id
        AND a.tax_id = b.tax_id
        AND ST_Geohash(a.geom) = ST_Geohash(b.geom);" | $PSQL
    echo "- deleted duplicate parcels in $(($(date '+%s')-${START}))s"
    # --- END DEDUPLICATION

    # -- DELETE IMPLAUSIBLY LARGE NON-MULTIFAMILY PARCELS
    echo "- deleting improbably large parcels"
    echo "SELECT DISTINCT src FROM parcels;" | $PSQL -t | sort | grep . | while read COUNTY; do
        BEFORE="$(echo "SELECT COUNT(*) FROM parcels WHERE src='${COUNTY}';" | $PSQL -t | grep .)"
        echo "DELETE FROM parcels WHERE src='${COUNTY}' AND ST_AREA(geom) > 0.00003 AND use_code NOT LIKE 'B%';" | $PSQL
        AFTER="$(echo "SELECT COUNT(*) FROM parcels WHERE src='${COUNTY}';" | $PSQL -t | grep .)"
        echo "  - deleted $(($BEFORE-$AFTER)) $COUNTY county parcels"
    done
    # -- END DELETION OF IMPLAUSIBLY LARGE PARCELS

    # --- BEGIN APPORTIONMENT
    START="$(date '+%s')"
    echo "- beginning parcel/tract apportionment"
    echo "ALTER TABLE parcels ADD COLUMN ctr Geometry(Point, 4326);
        UPDATE parcels SET ctr=ST_Centroid(ST_Buffer(ST_MakeValid(geom), 0));
        UPDATE parcels SET ctr=ST_PointOnSurface(ST_MakeValid(geom)) WHERE ctr IS NULL;
        CREATE INDEX idx_parcels_ctr ON parcels USING GIST(ctr);" | $PSQL

    echo "ALTER TABLE parcels ADD COLUMN tract TEXT;
        ALTER TABLE parcels ADD COLUMN tract_pct NUMERIC;
        ALTER TABLE census ADD COLUMN tract_residential_area NUMERIC;
        CREATE INDEX idx_parcels_tract ON parcels(tract);" | $PSQL

    echo "UPDATE parcels p SET tract=c.tract FROM census c WHERE ST_Intersects(c.geom, p.ctr);
        UPDATE census c SET tract_residential_area=t.total_area FROM (SELECT tract, SUM(ST_Area(geom)) AS total_area FROM parcels GROUP BY tract) t WHERE c.tract=t.tract;
        UPDATE parcels p SET tract_pct=ST_Area(p.geom)/c.tract_residential_area FROM census c WHERE p.tract=c.tract;" | $PSQL
    echo "- finished parcel/tract apportionment in $(($(date '+%s')-${START}))s"
    # -- END APPORTIONMENT
else
    echo "x skipping all parcel tasks"
fi
# --- END PARCELS

# --- BEGIN ISOCHRONES
if [ "${ISOCHRONES:-0}" -eq 1 ]; then
    START="$(date '+%s')"
    echo "- loading isochrones"
    source "load_isochrones.sh"
    echo "- loaded isochrones in $(($(date '+%s')-${START}))s"
else
    echo "x skipped isochrones"
fi
# --- END ISOCHRONES

# --- BEGIN ANALYSIS
if [ "${ANALYSIS:-0}" -eq 1 ]; then
    START="$(date '+%s')"
    echo "- running analysis"
    source "analysis.sh"
    echo "- ran analysis in $(($(date '+%s')-${START}))s"
else
    echo "x skipped analysis"
fi
# --- END ANALYSIS

# --- BEGIN GRANT
for tn in $(echo "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'" | $PSQL -t); do
    echo "GRANT SELECT ON ${tn} TO ${VIEWER_NAME};" | $PSQL
done
echo "- granted SELECT on all tables to ${VIEWER_NAME}"
# --- END GRANT
