#!/usr/bin/env bash
# parse_out.sh - simple Bash parser for hpdbscan output
# Usage: parse_out.sh <logfile> <exp_dir>


set -eu

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <logfile> <exp_dir> [datasetName algoName eps minPts]" >&2
    exit 1
fi

LOGFILE=$1
EXPDIR=$2
# optional additional args describing dataset and clustering parameters
DATASET_NAME=${3:-}
ALG_NAME=${4:-}
EPS=${5:-}
MINPTS=${6:-}

if [ ! -f "$LOGFILE" ]; then
    echo "Log file not found: $LOGFILE" >&2
    exit 2
fi

mkdir -p "$EXPDIR"

# Target directory: <exp_dir>/<dataset>/<algo>/<eps>_<minPts>/metrics.json
if [ -n "$DATASET_NAME" ] && [ -n "$ALG_NAME" ] && [ -n "$EPS" ] && [ -n "$MINPTS" ]; then
    TARGET_DIR="$EXPDIR/$DATASET_NAME/$ALG_NAME/${EPS}_${MINPTS}"
else
    # fallback to writing directly into expdir
    TARGET_DIR="$EXPDIR"
fi

mkdir -p "$TARGET_DIR"
METRICS_FILE="$TARGET_DIR/metrics.json"

total_time=""
declare -a step_json
declare -a summary_json
declare -a step_times

# Extract total time (seconds)
if grep -qE "^\s*Total time:" "$LOGFILE"; then
    total_time=$(grep -E "^\s*Total time:" "$LOGFILE" | tail -n1 | sed -E 's/[^0-9.]*([0-9]+\.?[0-9]*).*/\1/')
fi

# Extract per-step times and build JSON fragments
while IFS= read -r line; do
    if [[ $line =~ \[OK\]\ in[[:space:]]*([0-9]+\.?[0-9]*) ]]; then
        time="${BASH_REMATCH[1]}"
        name="${line%%\[OK\]*}"
        name=$(echo "$name" | sed -E 's/[.[:space:]]*$//')
        name=$(echo "$name" | sed -E 's/[[:space:]]+/ /g')
        name=$(printf '%s' "$name" | sed 's/"/\\"/g')
        step_json+=("\"$name\": $time")
        step_times+=("$time")
    fi
done < <(grep "\[OK\] in" "$LOGFILE" || true)

# Extract summary numbers
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*Clusters:[[:space:]]*([0-9]+) ]]; then
        summary_json+=("\"clusters\": ${BASH_REMATCH[1]}")
    elif [[ $line =~ ^[[:space:]]*Cluster[[:space:]]points:[[:space:]]*([0-9]+) ]]; then
        summary_json+=("\"cluster_points\": ${BASH_REMATCH[1]}")
    elif [[ $line =~ ^[[:space:]]*Noise[[:space:]]points:[[:space:]]*([0-9]+) ]]; then
        summary_json+=("\"noise_points\": ${BASH_REMATCH[1]}")
    elif [[ $line =~ ^[[:space:]]*Core[[:space:]]points:[[:space:]]*([0-9]+) ]]; then
        summary_json+=("\"core_points\": ${BASH_REMATCH[1]}")
    fi
done < <(grep -E "^(\s*)(Clusters|Cluster points|Noise points|Core points):" "$LOGFILE" || true)

# If no total_time, try summing step_times
if [ -z "$total_time" ] && [ ${#step_times[@]} -gt 0 ]; then
    sum=0
    for t in "${step_times[@]}"; do
        # use awk for float addition
        sum=$(awk -v a="$sum" -v b="$t" 'BEGIN{printf "%f", a + b}')
    done
    total_time="$sum"
fi

# Compute algoTimeMs (integer milliseconds) if we have a total_time
algoTimeMs=""
if [ -n "$total_time" ]; then
    algoTimeMs=$(awk -v t="$total_time" 'BEGIN{printf "%d", t * 1000}')
fi

# Build final JSON matching requested schema
{
    echo '{'
    echo "  \"algo\": \"${ALG_NAME:-HPDBSCAN}\"," 
    if [ -n "$algoTimeMs" ]; then
        echo "  \"algoTimeMs\": $algoTimeMs,"
    fi
    # clusterParameters
    echo "  \"clusterParameters\": {"
    if [ -n "$EPS" ]; then
        # print eps as number
        printf '    "eps": %s' "$EPS"
        echo ','
    else
        echo '    "eps": null,'
    fi
    if [ -n "$MINPTS" ]; then
        echo "    \"minPts\": $MINPTS"
    else
        echo '    "minPts": null'
    fi
    echo '  },'

    # datasetParameters
    echo '  "datasetParameters": {'
    if [ -n "$DATASET_NAME" ]; then
        echo "    \"datasetName\": \"$DATASET_NAME\""
    else
        echo '    "datasetName": null'
    fi
    echo '  }'

    # append steps and summary if present; print commas only when needed
    if [ ${#step_json[@]} -gt 0 ]; then
        echo ','
        echo '  "steps": {'
        for i in "${!step_json[@]}"; do
            entry="${step_json[$i]}"
            printf '    %s' "$entry"
            if [ $i -lt $((${#step_json[@]} - 1)) ]; then
                echo ','
            else
                echo
            fi
        done
        echo -n '  }'
    fi

    if [ ${#summary_json[@]} -gt 0 ]; then
        echo ','
        echo '  "summary": {'
        for i in "${!summary_json[@]}"; do
            entry="${summary_json[$i]}"
            printf '    %s' "$entry"
            if [ $i -lt $((${#summary_json[@]} - 1)) ]; then
                echo ','
            else
                echo
            fi
        done
        echo -n '  }'
    fi

    echo
    echo '}'
} > "$METRICS_FILE"

echo "Wrote metrics to $METRICS_FILE"

