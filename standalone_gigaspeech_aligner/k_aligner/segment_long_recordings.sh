#!/usr/bin/env bash

log() {
    # This function is from espnet
    local fname=${BASH_SOURCE[1]##*/}
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

stage=-10
stop_stage=100
nj=4
unk_symbol="<UNK>"
merge_phones="all"
unit="phones"

echo "$0 $@"  # Print the command line for logging

. utils/parse_options.sh
. path.sh
. cmd.sh

if [ $# -ne 4 ]; then
    echo "Compute the utterance-level segmentation in long recording data (e.g. lectures, videos,"
    echo "conversations, etc.)."
    echo "The inputs are Lhotse recording and supervision manfiests."
    echo "The supervisions should be as long as the recording and contain the full transcript "
    echo "as a single segment (even if it is very long, e.g., 1 hour)."
    echo "The ouput is a directory with re-segmented recording and supervision manifests,"
    echo "a phones.txt file, and a HDF5 file with the alignment for the segmented data. "
    echo "This script uses a Kaldi GMM-HMM model."
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
    echo "Example: $0 /fsx/home/pzelasko/tri4b_gigaspeech recs.jsonl sups.jsonl exp/segmented-data"
    exit 1  
fi

gmmdir="$1"
recs="$2"
sups="$3"
outdir="$4"

mkdir -p data
mkdir -p exp
mkdir -p $outdir

# Assume that all recordings have the same sampling rate.
sampling_rate="$(gunzip -c $recs | head -1 | jq '.sampling_rate')"
log "Detected sampling rate: $sampling_rate"

set -eou pipefail  # bash strict mode

# Note: we step at the stage 4, i.e. before the alignments.
# This script effectively just prepares the Kaldi data dir,
# dict and lang directories, and extracts the MFCCs.
./align.sh \
    --stage $stage \
    --stop-stage 4 \
    --nj $nj \
    --unk-symbol $unk_symbol \
    $gmmdir \
    $recs \
    $sups \
    exp/local/tmp # unused

# This stage uses a GMM model to decode long recordings
# and try to segment them into shorter utterances.
# See the script for details.
if [ $stage -le 4 ] && [ $stop_stage -gt 4 ]; then
    log "Stage 4: Segmenting long utterances."
    steps/cleanup/segment_long_utterances.sh \
        --nj $nj \
        "$gmmdir/gmm" \
        data/lang \
        data/unaligned \
        data/segmented_long \
        exp/segmentation_tmp
fi

# We compute the alignments for the recordings after
# the initial segmentation. They are needed for the next
# cleanup step.
if [ $stage -le 5 ] && [ $stop_stage -gt 5 ]; then
	log "Stage 5: Aligning the segments."
    steps/compute_cmvn_stats.sh data/segmented_long
    steps/align_fmllr.sh --cmd $train_cmd --nj $nj \
        data/segmented_long \
        data/lang \
        "$gmmdir/gmm" \
        exp/alis_segmented_long
fi

# Get the intermediate cleaned-up data manifests.
if [ $stage -le 6 ] && [ $stop_stage -gt 6 ]; then
    log "Stage 6: Converting alignments to Lhotse (1st stage cleanup)."
    set -x
    local/datadir_to_lhotse_with_alis.py \
        --unit $unit \
        --merge-phones $merge_phones \
        --sampling-rate $sampling_rate \
        data/segmented_long \
        exp/alis_segmented_long \
        "$outdir/1st_stage"
    set +x
fi

# This step tries to remove bad segments
# and further split some segments into shorter ones.
if [ $stage -le 7 ] && [ $stop_stage -gt 7 ]; then
    log "Stage 7: Refining the segmentation with clean_and_segment_data.sh"
    steps/cleanup/clean_and_segment_data.sh \
        data/segmented_long \
        data/lang \
        exp/alis_segmented_long \
        exp/segmented_long_cleanup \
        data/segmented_long_clean
fi

# We recompute the alignments for the recordings after
# the second pass of segmentation. 
if [ $stage -le 8 ] && [ $stop_stage -gt 8 ]; then
	log "Stage 8: Aligning the segments."
    steps/compute_cmvn_stats.sh data/segmented_long_clean
    steps/align_fmllr.sh --cmd $train_cmd --nj $nj \
        data/segmented_long_clean \
        data/lang \
        "$gmmdir/gmm" \
        exp/alis_segmented_long_cleanup
fi

# Get the final cleaned-up data manifests.
if [ $stage -le 9 ] && [ $stop_stage -gt 9 ]; then
    log "Stage 9: Converting alignments to Lhotse (2nd stage cleanup)."
    set -x
    local/datadir_to_lhotse_with_alis.py \
        --unit $unit \
        --merge-phones $merge_phones \
        --sampling-rate $sampling_rate \
        data/segmented_long_clean \
        exp/alis_segmented_long_cleanup \
        "$outdir/2nd_stage"
    set +x
fi

# Voila!
