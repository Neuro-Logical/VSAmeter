#!/usr/bin/env bash

stage=0
nj=2

. utils/parse_options.sh

./align.sh \
    --stage $stage \
    --nj $nj \
    --unit phones \
    --merge-phones all \
    ../ckpts/tri4b_gigaspeech \
    /fsx/resources/gigaspeech/gigaspeech_recordings_XS.jsonl.gz \
    /fsx/resources/gigaspeech/gigaspeech_supervisions_XS.jsonl.gz \
    exp/lhotse_ali
