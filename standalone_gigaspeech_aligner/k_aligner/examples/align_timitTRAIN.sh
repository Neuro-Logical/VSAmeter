#!/usr/bin/env bash

source ~/.bashrc
conda activate parrotron
stage=0
nj=32

. utils/parse_options.sh

./align.sh \
    --stage $stage \
    --nj $nj \
    --unit phones \
    --merge-phones all \
    ../ckpts/tri4b_gigaspeech \
    /export/c10/lmorove1/timit/manifests/recordings_TRAIN.json \
    /export/c10/lmorove1/timit/manifests/supervisions_TRAIN_text.json \
    exp/lhotse_ali

mkdir align_timit_train
mv data align_timit_train/
mv exp align_timit_train/
