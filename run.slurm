#!/bin/bash
#SBATCH --job-name=HPDBSCANJob
#SBATCH --nodes=4
#SBATCH --ntasks=4
# SBATCH default; override at submission time with --cpus-per-task
#SBATCH --cpus-per-task=32
#SBATCH --output=hpdbscan_output_%j.txt
#SBATCH --time=05:00:00
#SBATCH --mail-user=siepef@uni-marburg.de
#SBATCH --mail-type=END
#SBATCH --mem=128G
##SBATCH --exclusive
# You can override partition, qos, account etc. by editing the header or
# passing them to sbatch on the command line. Adjust nodes/ntasks-per-node
# to match the resources you need.

#############################################################################
# Usage
# sbatch run.slurm <dataset> <eps> <minPts> <num_partitions> <exp_dir> [out] [cpus_per_task]
#
# Notes:
# - This script runs the hpdbscan binary built by the project. It invokes it via
#   srun and forwards common CLI flags: -i <input> -e <epsilon> -m <minPoints>
#   -t <threads> -o <output>. If no explicit output path is provided the script
#   writes to a per-job scratch file and then (optionally) a parse script may be
#   used to move/generate metrics in <exp_dir>.
#############################################################################

# Positional args
DATASET="$1"
EPS="$2"
MINPTS="$3"
NUM_PARTITIONS="$4"
EXP_DIR="$5"
# optional: explicit output path
OUT_PATH="$6"

if [ -z "$DATASET" ] || [ -z "$EPS" ] || [ -z "$MINPTS" ] || [ -z "$NUM_PARTITIONS" ] || [ -z "$EXP_DIR" ]; then
  echo "Usage: sbatch run.slurm <dataset> <eps> <minPts> <num_partitions> <exp_dir> [out] [cpus_per_task]"
  exit 1
fi

# Change to submit directory where binary lives if available
if [ -n "$SLURM_SUBMIT_DIR" ]; then
  cd "$SLURM_SUBMIT_DIR" || exit 1
fi

echo "Starting HPDBSCAN job"
echo "Job id: $SLURM_JOB_ID"
echo "Nodes: $SLURM_JOB_NODELIST"
echo "Requested ranks: $NUM_PARTITIONS"
echo "Dataset: $DATASET"
echo "Eps: $EPS  MinPts: $MINPTS"


module purge
module load openmpi4

# Prepare a per-job scratch output file (so the compute nodes write to shared scratch)
# Default scratch base directory can be overridden by setting SCRATCH_BASE in the environment
SCRATCH_BASE="${SCRATCH_BASE:-/scratch_shared/siepef}"
SCRATCH_FILE="$SCRATCH_BASE/scratch-HPDBSCAN-${SLURM_JOB_ID}"

# Determine output file: prefer explicit OUT_PATH, otherwise write to per-job scratch
OUTFILE="${OUT_PATH:-$SCRATCH_FILE}"


# Determine threads to pass to the binary (use SLURM_CPUS_PER_TASK if available,
THREADS="${SLURM_CPUS_PER_TASK}"

# Export OpenMP environment variables so each MPI rank uses the configured
# local thread count. This makes the run a hybrid MPI+OpenMP execution.
export OMP_NUM_THREADS="$THREADS"
export OMP_PLACES=cores
export OMP_PROC_BIND=spread

echo "Setting OMP_NUM_THREADS=$OMP_NUM_THREADS"

# Run using srun (preferred on Slurm). Adjust --mpi or replace with mpirun if required.
# Pass --cpus-per-task to allocate the requested local hardware for each MPI rank
# Print command for logging/debugging
echo "Running hpdbscan with srun:"
echo "srun --mpi=pmix --nodes=$SLURM_NNODES --ntasks=$SLURM_NTASKS --cpus-per-task=$THREADS ./hpdbscan -i \"$DATASET\" -e \"$EPS\" -m \"$MINPTS\" -t \"$THREADS\" -o \"$OUTFILE\""
srun --mpi=pmix --nodes=$SLURM_NNODES --ntasks=$SLURM_NTASKS --cpus-per-task=$THREADS ./hpdbscan -i "$DATASET" -e "$EPS" -m "$MINPTS" -t "$THREADS" -o "$OUTFILE"

RET=$?
echo "run finished with exit code $RET"
  
# Attempt to parse the run log and generate metrics.json using parse_out.sh
PARSE_SCRIPT="${SLURM_SUBMIT_DIR:-.}/parse_out.sh"
PARSE_LOG="$EXP_DIR/run_${SLURM_JOB_ID}.log"
if [ -x "$PARSE_SCRIPT" ]; then
  echo "Parsing run log with $PARSE_SCRIPT -> $PARSE_LOG"
  "$PARSE_SCRIPT" "$PARSE_LOG" "$EXP_DIR" || echo "Warning: parse_out.sh failed" >&2
else
  echo "parse_out.sh not found or not executable at $PARSE_SCRIPT; skipping metrics generation" >&2
fi

exit $RET
