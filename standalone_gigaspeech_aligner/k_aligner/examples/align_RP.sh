#!/usr/bin/env bash

source ~/.bashrc
conda activate aligner_kg
stage=0
nj=10

. utils/parse_options.sh

./align.sh \
    --stage $stage \
    --nj $nj \
    --unit phones \
    --merge-phones all \
    ../ckpts/tri4b_gigaspeech \
    /home/tcao7/rp_16k_updated/recordings_rp.json \
    /home/tcao7/rp_16k_updated/supervisions_rp.json \
    exp/lhotse_ali

mkdir align_rp_updated
mv data align_rp_updated/
mv exp align_rp_updated/