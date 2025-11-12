#!/usr/bin/env bash
# Get dataset, eps, minPts, num_partitions and exp_dir from command line arguments
DATASET=${1}
EPS=${2}
MINPTS=${3}
NUM_PARTITIONS=${4}
EXP_DIR=${5}


# Check if required arguments are provided
if [ -z "$DATASET" ] || [ -z "$EPS" ] || [ -z "$MINPTS" ] || [ -z "$NUM_PARTITIONS" ] || [ -z "$EXP_DIR" ]; then
  echo "Usage: $0 <dataset> <eps> <minPts> <num_partitions> <exp_dir> [out] [cpus_per_task]"
  echo "Note: This wrapper submits a hybrid MPI+OpenMP job. Set cpus_per_task to the number of OpenMP threads per MPI rank (optional)."
  exit 1
fi

sbatch run.slurm "$DATASET" "$EPS" "$MINPTS" "$NUM_PARTITIONS" "$EXP_DIR"

exit 0


