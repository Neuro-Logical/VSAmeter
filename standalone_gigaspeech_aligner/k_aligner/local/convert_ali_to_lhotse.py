#!/usr/bin/env python

import re
from dataclasses import dataclass
from itertools import chain
from pathlib import Path
from typing import Dict

import click
import numpy as np
from cytoolz import groupby
from tqdm import tqdm
from kaldiio import open_like_kaldi, load_ark
from lhotse import NumpyHdf5Writer, SupervisionSet


@click.command()
@click.argument("supervisions", type=click.Path(exists=True))
@click.argument("ali_dir", type=click.Path(exists=True, file_okay=False))
@click.argument("output_dir", type=click.Path())
@click.option("--unit", type=click.Choice(["phones", "senones"]), default="phones")
@click.option(
    "--merge-phones",
    type=click.Choice(["none", "positions", "all"]),
    default="none",
    help="Should we reduce the phone set. "
    "'positions' option will merge position dependent phones (the B, I, E, S suffixes). "
    "'all' option will additionally merge phones by the accent marks (e.g., AH0, AH1, AH2 -> AH).",
)
def convert_ali_to_lhotse(
    supervisions: str,
    ali_dir: str,
    output_dir: str,
    unit: str,
    merge_phones: str,
):
    """
    Convert Kaldi's alignments in ALI_DIR (group of files ali.1.gz, ali.2.gz, etc.) to a custom
    format of alignments in Lhotse.

    It reads SUPERVISIONS, and uses alignment utterance keys to match them to supervision IDs.
    Then it stores the alignments in HDF5, and adds the fields "storage_type", "storage_key",
    and "storage_path" to the supervisions.

    The supervisions manifest with alignments is stored in OUTPUT_DIR together with the HDF5
    archive.
    """
    # Set up path operations, read input files
    ali_dir = Path(ali_dir)
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True, parents=True)
    supervisions = SupervisionSet.from_file(supervisions)

    # Prepare optional remapping tables for phones positions and stress markers
    remapping = make_phone_mapping(
        phones={
            k: int(v.strip())
            for k, v in map(
                str.split, (ali_dir / "phones.txt").read_text().splitlines()
            )
            if re.match(r"^#\d+$", k) is None
        },
        mode=merge_phones,
    )
    remapping.save_phones(output_dir / "phones.txt")
    click.echo(remapping)

    # Select the right command to get either senones or phones
    if unit == "phones":
        cmd = (
            f"gunzip -c {ali_dir}/ali.*.gz | "
            f"ali-to-phones --per-frame=true {ali_dir}/final.mdl ark:- ark,t:- |"
        )
    if unit == "senones":
        cmd = f"gunzip -c {ali_dir}/ali.*.gz |"

    # Main processing loop
    errs = 0
    ok = 0
    with open_like_kaldi(cmd, "rb",) as f, NumpyHdf5Writer(
        output_dir / "ali.h5"
    ) as storage, SupervisionSet.open_writer(
        output_dir / "supervisions.jsonl.gz", overwrite=True
    ) as writer:
        # Alignment format equals ark of IntVector
        g = load_ark(f)
        click.echo("Processing alignments...")
        for k, alivec in tqdm(g):
            # Check if we have a supervision for this alignment
            if k not in supervisions:
                errs += 1
                click.secho(f"WARNING: key {k} not found in supervisions.", fg="yellow")
            # If requested, we will perform phone ID re-mapping here
            if unit == "phones":
                alivec = [remapping.int2int[i] for i in alivec]
            alivec = np.array(alivec, dtype=np.int32)
            # Retrieve the corresponding supervision
            sup = supervisions[k]
            # Store the alignment in HDF
            storage_key = storage.write(k, alivec)
            # Update the supervision info
            if sup.custom is None:
                sup.custom = {}
            sup.custom.update(
                {
                    "storage_type": storage.name,
                    "storage_key": storage_key,
                    "storage_path": str(storage.storage_path),
                }
            )
            # Store the supervision
            writer.write(sup)
            ok += 1
    click.secho(
        f"Finished with {ok}/{len(supervisions)} utterances processed and stored in {output_dir}/supervisions.jsonl.gz"
    )
    if errs > 0:
        click.secho(
            f"We skipped {errs} utterances not present in alignments.",
            bold=True,
            fg="yellow",
        )


@dataclass
class Remapping:
    """Rules for mapping phone IDs from standard to reduced phone sets."""
    new_phones: Dict[str, int]
    sym2sym: Dict[str, str]
    int2int: Dict[int, int]

    def save_phones(self, path: str) -> None:
        with open(path, "w") as f:
            for sym, idx in sorted(self.new_phones.items(), key=lambda tpl: tpl[1]):
                print(f"{sym} {idx}", file=f)


def make_phone_mapping(phones: Dict[str, int], mode: str) -> Remapping:
    if mode == "none":
        return Remapping(
            new_phones=phones,
            sym2sym={k: k for k in phones},
            int2int={i: i for i in phones.values()},
        )

    sym2sym = groupby((lambda k: k.split("_")[0]), phones)
    new_phones = {sym: idx for idx, sym in enumerate(sym2sym)}
    int2int = {
        phones[old_phone]: new_phones[new_phone]
        for new_phone, old_phones in sym2sym.items()
        for old_phone in old_phones
    }
    remapping = Remapping(new_phones=new_phones, sym2sym=sym2sym, int2int=int2int)
    if mode == "positions":
        return remapping
    elif mode != "all":
        raise ValueError(f"Unknown phone merging mode: {mode}")

    sym2sym = groupby((lambda k: re.sub(r"\d", "", k)), remapping.new_phones)
    sym2sym = {
        new_phone: [
            older_phone
            for old_phone in old_phones
            for older_phone in remapping.sym2sym[old_phone]
        ]
        for new_phone, old_phones in sym2sym.items()
    }
    new_phones = {sym: idx for idx, sym in enumerate(sym2sym)}
    int2int = {
        phones[old_phone]: new_phones[new_phone]
        for new_phone, old_phones in sym2sym.items()
        for old_phone in old_phones
    }
    return Remapping(new_phones=new_phones, sym2sym=sym2sym, int2int=int2int)


if __name__ == "__main__":
    convert_ali_to_lhotse()
