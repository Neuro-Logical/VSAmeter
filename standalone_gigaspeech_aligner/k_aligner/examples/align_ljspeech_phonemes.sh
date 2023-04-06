#!/usr/bin/env bash

set -e -o pipefail

stage=-1
nj=1

. utils/parse_options.sh

ROOT=/fsx/resources/data-repository/LJSpeech-1.1/ljspeech
CKPT=tri4b_gigaspeech
ALIGNED=$ROOT/aligned/kaldi_$CKPT

mkdir -p data

./align.sh \
    --stage $stage \
    --nj $nj \
    --unit phones \
    --merge-phones all \
    ../ckpts/$CKPT \
    $ROOT/recordings.jsonl.gz \
    $ROOT/supervisions.jsonl.gz \
    $ALIGNED/

# filter recordings to contain the same items as aligned supervisions
lhotse fix \
    $ROOT/recordings.jsonl.gz \
    $ALIGNED/supervisions.jsonl.gz \
    $ALIGNED/

# make cutset
lhotse cut simple $ALIGNED/cuts.jsonl.gz \
    -r $ALIGNED/recordings.jsonl.gz \
    -s $ALIGNED/supervisions.jsonl.gz

# re-map cutset ids to match original cutset ids
meaning cut match-ids \
  $ALIGNED/cuts.jsonl.gz \
  $ROOT/cuts.jsonl.gz \
  $ALIGNED/cuts.jsonl.gz