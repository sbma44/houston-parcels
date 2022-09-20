#!/bin/bash

set -eu -o pipefail

source "conf.sh"

echo "- creating population totals"

# compile population totals for counties
FIPS_SQL=''
for fips in $(jq -r ".[]|if .msa == true then .fips else \"\" end" < ${DIR}/parcel-conf.json | grep .); do
    if [ -n "$FIPS_SQL" ]; then FIPS_SQL="${FIPS_SQL},"; fi
    FIPS_SQL="${FIPS_SQL}'${fips}'"
done
FIPS_SQL="(${FIPS_SQL})"

POPULATION_TOTAL_WHITE="$(echo "SELECT SUM(demog_pop_18_to_64_white) FROM census WHERE (statefp || countyfp) IN ${FIPS_SQL};" | $PSQL -t | grep .)"
POPULATION_TOTAL_BLACK="$(echo "SELECT SUM(demog_pop_18_to_64_black) FROM census WHERE (statefp || countyfp) IN ${FIPS_SQL};" | $PSQL -t | grep .)"
POPULATION_TOTAL_LATINX="$(echo "SELECT SUM(demog_pop_18_to_64_latinx) FROM census WHERE (statefp || countyfp) IN ${FIPS_SQL};" | $PSQL -t | grep .)"
POPULATION_TOTAL_ALL="$(echo "SELECT SUM(demog_pop_18_to_64_all) FROM census WHERE (statefp || countyfp) IN ${FIPS_SQL};" | $PSQL -t | grep .)"

echo '- generating institution population breakdowns'
echo 'opeid8,mode,provider,time,demog_pop_18_to_64_latinx,demog_pop_18_to_64_white,demog_pop_18_to_64_black,demog_pop_18_to_64_all' | tr ',' '\t' > tsv/institution_pop.tsv
echo "all,all,all,99999,${POPULATION_TOTAL_LATINX},${POPULATION_TOTAL_WHITE},${POPULATION_TOTAL_BLACK},${POPULATION_TOTAL_ALL}" | tr ',' '\t' >> tsv/institution_pop.tsv
echo "SELECT DISTINCT opeid8 FROM institutions ORDER BY opeid8 ASC;" | $PSQL -t | grep . | while read OPEID; do
    for MODE in walk drive transit; do
        for TIME in 30; do
            PROVIDER='otp'
            if [ "$MODE" = 'drive' ]; then
                PROVIDER='mapbox'
            fi
            echo "SELECT
                ${OPEID},
                '${MODE}',
                '${PROVIDER}',
                ${TIME},
                SUM(p.tract_pct * c.demog_pop_18_to_64_latinx) AS pop_18_to_64_latinx,
                SUM(p.tract_pct * c.demog_pop_18_to_64_white) pop_18_to_64_white,
                SUM(p.tract_pct * c.demog_pop_18_to_64_black) AS pop_18_to_64_black,
                SUM(p.tract_pct * c.demog_pop_18_to_64_all) AS pop_18_to_64_all
            FROM
                parcels p
                INNER JOIN census c ON p.tract=c.tract
                WHERE p.parcel_id IN (SELECT parcel_id FROM parcels, institutions WHERE institutions.opeid8=${OPEID} AND ST_Contains(isochrone_${PROVIDER}_${MODE}_${TIME}, ctr));" | $PSQL -t | grep . | tr '|' '\t' | tr -d ' ' >> tsv/institution_pop.tsv
            echo "  - generated population counts for OPEID ${OPEID}/${MODE}"
        done
    done
done

echo '- running analysis (this will take a while)'
for CAMPUS_TYPE in 'branch' 'main' 'all'; do
    echo "SELECT 'all' UNION SELECT '4yr' UNION SELECT DISTINCT sector_code FROM institutions;" | $PSQL -t | grep . | while read SECTOR; do
        SECTOR_WHERE=''
        if [ "${SECTOR}" != 'all' ]; then
            if [ "${SECTOR}" == '4yr' ]; then
                SECTOR_WHERE="(institutions.sector_code='privnonprofit4y' OR institutions.sector_code='pub4y') AND"
            else
                SECTOR_WHERE="institutions.sector_code='${SECTOR}' AND"
            fi
        fi

        if [ "${CAMPUS_TYPE}" != 'all' ]; then
            SECTOR_WHERE="${SECTOR_WHERE} LOWER(institutions.campus_type)='${CAMPUS_TYPE}' AND"
        fi

        for MODE in walk drive transit; do
            for TIME in 30; do
                PROVIDER='otp'
                if [ "$MODE" = 'drive' ]; then
                    PROVIDER='mapbox'
                fi
                START="$(date '+%s')"

                DIM="${SECTOR}_${CAMPUS_TYPE}_${MODE}_${TIME}"

                echo "
                ALTER TABLE parcels ADD COLUMN IF NOT EXISTS accessibility_${DIM}_inst_count NUMERIC DEFAULT 0;
                UPDATE parcels p SET accessibility_${DIM}_inst_count=(SELECT COUNT(*) FROM institutions WHERE ${SECTOR_WHERE} ST_Intersects(p.ctr, institutions.isochrone_${PROVIDER}_${MODE}_${TIME}));" | $PSQL
                echo "  - calculated accessibility/${SECTOR}/${CAMPUS_TYPE}/${MODE}/${TIME}m in $(($(date '+%s')-$START))s"

                echo "SELECT
                    accessibility_${DIM}_inst_count AS institution_count,
                    SUM(p.tract_pct * c.demog_pop_18_to_64_latinx)::decimal  / ${POPULATION_TOTAL_LATINX} AS pct_pop_18_to_64_latinx,
                    SUM(p.tract_pct * c.demog_pop_18_to_64_white)::decimal  / ${POPULATION_TOTAL_WHITE} AS pct_pop_18_to_64_white,
                    SUM(p.tract_pct * c.demog_pop_18_to_64_black)::decimal  / ${POPULATION_TOTAL_BLACK} AS pct_pop_18_to_64_black,
                    SUM(p.tract_pct * c.demog_pop_18_to_64_all)::decimal  / ${POPULATION_TOTAL_ALL} AS pct_pop_18_to_64_all
                FROM parcels p
                INNER JOIN census c ON p.tract=c.tract
                WHERE c.demog_pop_18_to_64_all > 0
                GROUP BY p.accessibility_${DIM}_inst_count
                ORDER BY p.accessibility_${DIM}_inst_count ASC;" | $PSQL | grep -v '\-\-\-\-' | grep -v 'rows)' | grep . | tr '|' '\t' | tr -d ' ' > tsv/population_${DIM}.tsv
                echo "  - generated population counts for accessibility/${SECTOR}/${CAMPUS_TYPE}/${MODE}/${TIME}m"

                echo "SELECT
                    accessibility_${DIM}_inst_count AS institution_count,
                    ROUND(SUM(p.tract_pct * c.povertylevel_50percent) / SUM(p.tract_pct * c.poverty_pop_all), 3) AS povertylevel_50percent,
                    ROUND(SUM(p.tract_pct * c.povertylevel_125percent) / SUM(p.tract_pct * c.poverty_pop_all), 3) AS povertylevel_125percent,
                    ROUND(SUM(p.tract_pct * c.povertylevel_150percent) / SUM(p.tract_pct * c.poverty_pop_all), 3) AS povertylevel_150percent,
                    ROUND(SUM(p.tract_pct * c.povertylevel_185percent) / SUM(p.tract_pct * c.poverty_pop_all), 3) AS povertylevel_185percent,
                    ROUND(SUM(p.tract_pct * c.povertylevel_200percent) / SUM(p.tract_pct * c.poverty_pop_all), 3) AS povertylevel_200percent,
                    ROUND(SUM(p.tract_pct * c.povertylevel_300percent) / SUM(p.tract_pct * c.poverty_pop_all), 3) AS povertylevel_300percent,
                    ROUND(SUM(p.tract_pct * c.povertylevel_400percent) / SUM(p.tract_pct * c.poverty_pop_all), 3) AS povertylevel_400percent,
                    ROUND(SUM(p.tract_pct * c.povertylevel_500percent) / SUM(p.tract_pct * c.poverty_pop_all), 3) AS povertylevel_500percent,
                    ROUND(SUM(p.tract_pct * c.povertylevel_over500percent) / SUM(p.tract_pct * c.poverty_pop_all), 3) AS povertylevel_over500percent,
                    ROUND(SUM(p.tract_pct * c.poverty_pop_all) / SUM(p.tract_pct * c.poverty_pop_all), 3) AS pct_totpop
                FROM parcels p
                INNER JOIN census c ON p.tract=c.tract
                WHERE c.poverty_pop_all > 0
                GROUP BY p.accessibility_${DIM}_inst_count
                ORDER BY p.accessibility_${DIM}_inst_count ASC;" | $PSQL | grep -v '\-\-\-\-' | grep -v 'rows)' | grep . | tr '|' '\t' | tr -d ' ' > tsv/econ_${DIM}.tsv
                echo "  - generated economic analysis for accessibility/${SECTOR}/${CAMPUS_TYPE}/${MODE}/${TIME}m"

                echo "SELECT
                    accessibility_${DIM}_inst_count AS institution_count,
                    ROUND(SUM(p.tract_pct * c.attainm_bach_to_higher_latinx) / SUM(p.tract_pct * c.attainm_pop_25_to_over_all), 3) AS attainm_bach_to_higher_latinx,
                    ROUND(SUM(p.tract_pct * c.attainm_bach_to_higher_white) / SUM(p.tract_pct * c.attainm_pop_25_to_over_all), 3) AS attainm_bach_to_higher_white,
                    ROUND(SUM(p.tract_pct * c.attainm_bach_to_higher_black) / SUM(p.tract_pct * c.attainm_pop_25_to_over_all), 3) AS attainm_bach_to_higher_black,
                    ROUND(SUM(p.tract_pct * c.attainm_bach_to_higher_all) / SUM(p.tract_pct * c.attainm_pop_25_to_over_all), 3) AS attainm_bach_to_higher_all
                FROM parcels p
                INNER JOIN census c ON p.tract=c.tract
                WHERE c.attainm_pop_25_to_over_all > 0
                GROUP BY p.accessibility_${DIM}_inst_count
                ORDER BY p.accessibility_${DIM}_inst_count ASC;" | $PSQL | grep -v '\-\-\-\-' | grep -v 'rows)' | grep . | tr '|' '\t' | tr -d ' ' > tsv/attainment_${DIM}.tsv
                echo "  - generated attainment analysis for accessibility/${SECTOR}/${CAMPUS_TYPE}/${MODE}/${TIME}m"
            done
        done
    done
done

# accumulate values in population files
for f in tsv/population_*.tsv; do
    python3 py/pop_accum.py < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

# copy files to S3
(cd tsv && ls | grep -v index > index.txt)
#(cd tsv && for f in *; do aws s3 cp --acl=public-read "$f" "s3://${S3_BUCKET}/tsv/"; done)
