#!/usr/bin/env bash

source ~/.bashrc
conda activate aligner_k
stage=0
nj=2

. utils/parse_options.sh

./align.sh \
    --stage $stage \
    --nj $nj \
    --unit phones \
    --merge-phones all \
    ../ckpts/tri4b_gigaspeech \
    /export/c10/lmorove1/Parkinsonics_analysis/manifests_RP_manual/recordings.jsonl.gz \
    /export/c10/lmorove1/Parkinsonics_analysis/manifests_RP_manual/segments.jsonl.gz \
    exp/lhotse_ali