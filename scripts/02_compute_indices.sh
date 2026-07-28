#!/usr/bin/env bash
#
# ONDJFM rainfall indices for the 29 CMIP6 models and for CHIRPS, computed identically.
#
# SEASONS
#   1984/85 through 2013/14 - the 30 complete October-March seasons the models and the
#   observations share. Labelled by start year, as in the observational study.
#
# WHY THESE FIVE INDICES
#   The point is not just "is the model too wet or too dry". A model can produce roughly
#   the right seasonal total while getting there in entirely the wrong way, and the
#   classic failure of global climate models over the tropics is exactly that: they
#   drizzle. Rain falls on far too many days, at far too low an intensity, and the two
#   errors partly cancel in the total.
#
#   Separating frequency from intensity is what exposes it:
#
#     prmean     mean rainfall per day of the season          mm/day     total signal
#     r1mm_pct   share of days that are wet (>= 1 mm)         % of days  FREQUENCY
#     sdii       mean rainfall on wet days only               mm/wet day INTENSITY
#     cdd        longest run of consecutive dry days          days       dry spells
#     prcptot    season total                                 mm         context only
#
#   A model that is right on prmean but too high on r1mm_pct and too low on sdii is
#   drizzling, and would badly mislead any dry-spell or flood application built on it -
#   which is precisely what this evaluation exists to detect.
#
# CALENDARS
#   The ensemble mixes 360_day, 365_day and several Gregorian variants, so ONDJFM is 180
#   days for four models and 182 for the rest. Every index above except prcptot is a RATE
#   and is therefore unaffected. prcptot is reported for context but must not be used to
#   rank models: the 360-day models would look ~1% drier for calendar reasons alone.
#
# WHY eca_* IS SAFE HERE
#   Every eca_ operator reduces its whole input to a single timestep rather than grouping
#   by calendar year. Each file below holds exactly one season, so eca_cdd and eca_sdii
#   return one value spanning that season - which is what is wanted, and it sidesteps the
#   December/January split entirely without needing a synthetic time axis.
#
set -euo pipefail
cd "$(dirname "$0")/.."

CHIRPS=${CHIRPS_NC:-/home/corban/Zambia_Climate_Extremes/data/processed/chirps_zambia_1981_present.nc}
IN=data/processed
OUT=data/processed/indices
TMP=data/processed/tmp
mkdir -p "$OUT" "$TMP"

FIRST=1984
LAST=2013           # season 2013/14 is the last complete one shared with the models

run() { cdo -s "$@" 2> >(grep -vE 'HDF5-DIAG|^ +#[0-9]{3}:|major:|minor:|Warning' >&2 || true); }

# $1 = daily input file, $2 = output label
season_indices() {
  local src="$1" label="$2"
  local dst="$OUT/${label}.nc"
  [ -f "$dst" ] && { echo "    $label: already done"; return; }
  rm -f "$TMP"/s_*.nc

  for y in $(seq $FIRST $LAST); do
    local y2=$((y+1))
    local real="$TMP/r.nc"
    local stamp="setdate,${y}-10-01 -settime,00:00:00"
    run seldate,${y}-10-01,${y2}-03-31 "$src" "$real"

    run $stamp -setname,prmean   -timmean "$real"                    "$TMP/s_prmean_${y}.nc"
    run $stamp -setname,prcptot  -timsum  "$real"                    "$TMP/s_prcptot_${y}.nc"
    run $stamp -setname,r1mm_pct -mulc,100 -timmean -gec,1 "$real"   "$TMP/s_r1mm_pct_${y}.nc"
    run $stamp -setname,cdd  -selname,consecutive_dry_days_index_per_time_period \
        -eca_cdd "$real"                                             "$TMP/s_cdd_${y}.nc"
    run $stamp -setname,sdii -eca_sdii "$real"                       "$TMP/s_sdii_${y}.nc"
    rm -f "$real"
  done

  for v in prmean prcptot r1mm_pct cdd sdii; do
    run mergetime "$TMP"/s_${v}_*.nc "$TMP/m_${v}.nc"
  done
  run -f nc4c -z zip merge "$TMP"/m_{prmean,prcptot,r1mm_pct,cdd,sdii}.nc "$dst"
  rm -f "$TMP"/s_*.nc "$TMP"/m_*.nc
  echo "    $label -> $dst"
}

echo "=== Observations (CHIRPS), the benchmark ==="
season_indices "$CHIRPS" "OBS"

echo "=== 29 CMIP6 models, historical ==="
for i in $(seq 1 29); do
  f="$IN/hist/M${i}.nc"
  [ -f "$f" ] || { echo "    M$i: missing, skipped"; continue; }
  season_indices "$f" "M${i}"
done

echo
echo "Done."
ls -lh "$OUT" | head -5
echo "variables: $(run showname "$OUT/OBS.nc")"
echo "seasons  : $(run showyear "$OUT/OBS.nc" | wc -w)"
