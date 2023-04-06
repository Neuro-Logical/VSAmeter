# Kaldi alignment utilities

## Usage

Top level scripts (like align.sh) are located in this directory. 
The utility scripts are placed in `local`. 
Examples that can be ran without specifying any extra options are located in `examples`.

Example of alignment:

```bash
$ examples/run_align.sh
```

See script usage:
```
$ ./align.sh
Prepare data from Lhotse recording and supervision manifests and create alignments
using Kaldi's GMM-HMM model.
(...)

$ ./segment_long_recordings.sh
Compute the utterance-level segmentation in long recording data (e.g. lectures, videos,
conversations, etc.).
(...)

```

## Requirements

Install the required packages:
conda env create -f aligner_env.yml

Make sure that the following tools are installed: 
- sox
- ffmpeg
- swig


Make sure that:
- Kaldi is compiled.
- sequitur was installed (go to `tools` and run `extras/install_sequitur.sh`)
- `KALDI_ROOT` is appropriately set in `path.sh` file.
- the symlinks `utils` and `steps` are pointing to the right location (i.e., they are not broken -- which is true by default).