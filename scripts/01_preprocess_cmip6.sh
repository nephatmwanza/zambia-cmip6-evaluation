#!/usr/bin/env bash
#
# Bring 29 CMIP6 models onto the same footing as the CHIRPS observations.
#
# Companion to the observational rainfall study at
#   https://github.com/nephatmwanza/zambia-rainfall-extremes
# whose CHIRPS record is the benchmark everything here is measured against.
#
# THREE THINGS THIS FIXES, each of which silently corrupts the comparison if skipped:
#
#   1. UNITS. CMIP6 stores precipitation as a flux in kg m-2 s-1. Multiplying by 86400
#      gives mm/day. Forget it and every value is 86,400x too small - and because the
#      spatial pattern still looks sensible in relative terms, the error survives a
#      casual glance at a map.
#
#   2. LATITUDE ORIENTATION. These files run north-to-south (yinc = -0.25) because they
#      were remapped against ERA5, while CHIRPS and the province mask run south-to-north.
#      Applied unchecked the mask is mirrored and every province is assigned the wrong
#      half of the country, with no error raised.
#
#   3. GRID ALIGNMENT. The models sit on .25/.75 cell centres, CHIRPS on .125/.625, so a
#      bounding-box selection cannot line them up - the cells genuinely do not coincide.
#      remapcon (first-order conservative) is used rather than bilinear because it
#      preserves area totals, which is the property that matters for rainfall.
#
# PERIOD
#   The historical files run 1984-2014, so the complete ONDJFM seasons shared with CHIRPS
#   are 1984/85 through 2013/14 - exactly 30 seasons. The future files are SSP5-8.5,
#   2030-2060, and are processed here but not used until models have passed evaluation.
#
# CALENDARS
#   The ensemble mixes proleptic_gregorian, gregorian, standard, 365_day and 360_day.
#   The four 360-day models (M5, M14, M25, M27) have 180-day ONDJFM seasons against
#   everyone else's 182, so raw seasonal totals make them look ~1% drier for purely
#   calendar reasons. Nothing is done about it here; it is handled in the index step by
#   comparing rates (mm/day, % of days) rather than totals. M6 is also offset by one day.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# Both inputs are large and are not committed. Either place them at these paths or
# point the environment variables somewhere else:
#   CMIP6_SRC   directory holding Historical/M*_Hist.nc and SSP585/M*_fut85.nc
#   CHIRPS_NC   the Zambia-clipped CHIRPS daily file, from the companion rainfall study
SRC=${CMIP6_SRC:-data/raw/cmip6}
CHIRPS=${CHIRPS_NC:-data/raw/chirps_zambia_daily.nc}
OUT=data/processed
TMP=data/processed/tmp
mkdir -p "$OUT/hist" "$OUT/ssp585" "$TMP"

run() { cdo -s "$@" 2> >(grep -vE 'HDF5-DIAG|^ +#[0-9]{3}:|major:|minor:|Warning' >&2 || true); }

if [ ! -f "$CHIRPS" ]; then
  echo "ERROR: CHIRPS reference not found at $CHIRPS" >&2
  echo "Set CHIRPS_NC to its location, or clone the rainfall study first." >&2
  exit 1
fi

echo "=== Target grid, taken from the CHIRPS observations ==="
run griddes "$CHIRPS" > "$TMP/target_grid.txt"
grep -E '^(xsize|ysize|xfirst|yfirst|xinc|yinc)' "$TMP/target_grid.txt" | sed 's/^/    /'

process() {          # $1 = source file, $2 = destination
  # right-to-left: convert flux to mm/day, flip latitude, then conservatively regrid
  run -f nc4c -z zip -remapcon,"$TMP/target_grid.txt" -invertlat -mulc,86400 "$1" "$2"
  run setattribute,pr@units=mm/day "$2" "$2.tmp" && mv "$2.tmp" "$2"
}

echo "=== Historical (1984-2014), 29 models ==="
for i in $(seq 1 29); do
  src="$SRC/Historical/M${i}_Hist.nc"
  dst="$OUT/hist/M${i}.nc"
  [ -f "$src" ] || { echo "    M$i: source missing, skipped"; continue; }
  [ -f "$dst" ] && { echo "    M$i: already done"; continue; }
  process "$src" "$dst"
  printf '    M%-3s -> %s\n' "$i" "$dst"
done

echo "=== SSP5-8.5 (2030-2060), 29 models ==="
for i in $(seq 1 29); do
  src="$SRC/SSP585/M${i}_fut85.nc"
  dst="$OUT/ssp585/M${i}.nc"
  [ -f "$src" ] || { echo "    M$i: source missing, skipped"; continue; }
  [ -f "$dst" ] && { echo "    M$i: already done"; continue; }
  process "$src" "$dst"
  printf '    M%-3s -> %s\n' "$i" "$dst"
done

echo
echo "Done."
du -sh "$OUT/hist" "$OUT/ssp585"
echo "Grid check on one output:"
run griddes "$OUT/hist/M1.nc" | grep -E '^(xsize|ysize|xfirst|yfirst|xinc|yinc)' | sed 's/^/    /'
