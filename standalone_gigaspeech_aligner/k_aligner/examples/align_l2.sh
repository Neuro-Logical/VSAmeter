#!/usr/bin/env bash
#SBATCH --job-name=aligns2s_make_sources
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --output=logs/log_%A_%a.txt
#SBATCH --error=logs/err_%A_%a.txt
#SBATCH --array=0-5
#SBATCH  --export=ALL


SOURCES=(
  train-Arabic
  train-Chinese
  train-Hindi
  train-Korean
  train-Spanish
  train-Vietnamese
)

ROOT=/fsx/resources/data-repository/l2arctic/${SOURCES[$SLURM_ARRAY_TASK_ID]}
CKPT=tri4b_gigaspeech
ALIGNED=$ROOT/aligned/kaldi_$CKPT
mkdir -p logs

stage=-1
nj=2

. utils/parse_options.sh

./align.sh \
    --stage $stage \
    --nj $nj \
    --unit phones \
    --merge-phones all \
    --exp-dir exp/${SOURCES[$SLURM_ARRAY_TASK_ID]} \
    --data-dir data/${SOURCES[$SLURM_ARRAY_TASK_ID]} \
    ../ckpts/$CKPT \
    $ROOT/recordings.jsonl.gz \
    $ROOT/supervisions.jsonl.gz \
    $ALIGNED

# filter recordings to contain the same items as aligned supervisions
lhotse fix \
    $ROOT/recordings.jsonl.gz \
    $ALIGNED/supervisions.jsonl.gz \
    $ALIGNED

# make cutset
lhotse cut simple $ALIGNED/cuts.jsonl.gz \
    -r $ALIGNED/recordings.jsonl.gz \
    -s $ALIGNED/supervisions.jsonl.gz

# re-map cutset ids to match original cutset ids
meaning cut match-ids \
  $ALIGNED/cuts.jsonl.gz \
  $ROOT/cuts.jsonl.gz \
  $ALIGNED/cuts.jsonl.gz