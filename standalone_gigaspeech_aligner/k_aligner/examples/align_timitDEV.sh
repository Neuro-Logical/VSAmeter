#!/usr/bin/env bash

source ~/.bashrc
conda activate parrotron
stage=0
nj=10

. utils/parse_options.sh

./align.sh \
    --stage $stage \
    --nj $nj \
    --unit phones \
    --merge-phones all \
    ../ckpts/tri4b_gigaspeech \
    /export/c10/lmorove1/timit/manifests/recordings_DEV.json \
    /export/c10/lmorove1/timit/manifests/supervisions_DEV_text.json \
    exp/lhotse_ali

mkdir align_timit_dev
mv data align_timit_dev/
mv exp align_timit_dev/
