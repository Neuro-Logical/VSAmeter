#!/usr/bin/env bash

# Optional arguments
nj=1
stage=-1
stop_stage=100
unk_symbol="<UNK>"
merge_phones="all"
unit="phones"
exp_dir="exp"
data_dir="data"


echo "$0 $@"  # Print the command line for logging

. utils/parse_options.sh
. ./cmd.sh
. ./path.sh

log() {
    # This function is from espnet
    local fname=${BASH_SOURCE[1]##*/}
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

# Bash "strict" mode
set -eou pipefail

if [ $# -ne 4 ]; then
    echo "Prepare data from Lhotse recording and supervision manifests and create alignments"
    echo "using Kaldi's GMM-HMM model."
    echo "<gmm-dir> should have the following sub-directories:"
    echo "- conf (for mfcc config mfcc.conf)"
    echo "- dict (with the lexicon used to trained the GMM model)"
    echo "- gmm  (contains GMM model: final.mdl, cmvn_opts, final.mat, tree, etc)."
    echo "- g2p  (contains G2P sequitur model called g2p.model.4 from GigaSpeech."
    echo
    echo "Options:"
    echo "  --nj             # Number of parallel jobs."
    echo "  --stage          # At which stage to start processing."
    echo "  --unit           # Should we store 'senones' or 'phones' alignments."
    echo "  --merge-phones   # Should we merge phones: 'none' does nothing,"
    echo "                   # 'positions' merges position dependent phones,"
    echo "                   # 'all' merges position dependent phones and stress markers."
    echo
    echo "Usage:"
    echo "$0 [options] <gmm-dir> <recordings-manifest> <supervisions-manifest> <output-dir>"
    echo "Example: $0 /fsx/home/pzelasko/tri4b_gigaspeech recs.jsonl sups.jsonl exp/lhotse_ali"
    exit 1  
fi

gmmdir="$1"
recs="$2"
sups="$3"
outdir="$4"

mkdir -p $data_dir
mkdir -p $exp_dir
mkdir -p $outdir


if [ $stage -le -1 ] && [ $stop_stage -gt -1 ]; then
	log "Stage -1: Normalizing supervisions."
    mkdir -p $data_dir/local
    meaning normalize supervisions $sups $data_dir/local/normalized_supervisions.jsonl.gz
    sups=$data_dir/local/normalized_supervisions.jsonl.gz
fi

if [ $stage -le 0 ] && [ $stop_stage -gt 0 ]; then
	log "Stage 0: Converting Lhotse manifests to Kaldi data dir."
    lhotse kaldi export "$recs" "$sups" $data_dir/unaligned
    utils/utt2spk_to_spk2utt.pl $data_dir/unaligned/utt2spk > $data_dir/unaligned/spk2utt
    utils/fix_data_dir.sh $data_dir/unaligned
fi

if [ $stage -le 1 ] && [ $stop_stage -gt 1 ]; then
    log "Stage 1: Preparing Kaldi dict dir."
    if [ ! -f $gmmdir/g2p/g2p.model.4 ]; then
        log "Skipping G2P: G2P model was not found in $gmmdir"
        mkdir -p $data_dir/local
        cp -r $gmmdir/dict $data_dir/local/dict
    else
        log "Using G2P to extend the lexicon with OOVs from the transcripts."
        local/prepare_dict.sh \
            --cmd "$train_cmd" \
            --nj "$nj" \
            "$gmmdir/g2p/g2p.model.4" \
            $data_dir/unaligned \
            $data_dir/local/dict
    fi
fi

if [ $stage -le 2 ] && [ $stop_stage -gt 2 ]; then
	log "Stage 2: Preparing Kaldi lang dir."
    utils/prepare_lang.sh \
        $data_dir/local/dict \
        $unk_symbol \
        $data_dir/local/lang_tmp \
        $data_dir/lang
fi

if [ $stage -le 3 ] && [ $stop_stage -gt 3 ]; then
	log "Stage 3: Extracting MFCCs."
    steps/make_mfcc.sh \
        --mfcc-config $gmmdir/conf/mfcc.conf \
        --cmd $train_cmd \
        --nj $nj \
        $data_dir/unaligned
    steps/compute_cmvn_stats.sh $data_dir/unaligned
    utils/fix_data_dir.sh $data_dir/unaligned
fi

if [ $stage -le 4 ] && [ $stop_stage -gt 4 ]; then
	log "Stage 4: Aligning."
    steps/align_fmllr.sh --cmd $train_cmd --nj $nj \
        $data_dir/unaligned \
        $data_dir/lang \
        "$gmmdir/gmm" \
        $exp_dir/alis
fi

if [ $stage -le 5 ] && [ $stop_stage -gt 5 ]; then
    log "Stage 5: Converting alignments to Lhotse."
    set -x
    local/convert_ali_to_lhotse.py \
        --unit $unit \
        --merge-phones $merge_phones \
        "$sups" \
        $exp_dir/alis \
        "$outdir"
    set +x
fi
