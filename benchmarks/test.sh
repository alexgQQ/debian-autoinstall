#!/usr/bin/env sh

set -eu

NAME=$1
RANDSEED=$2
THREADS=$(nproc)
OUTPUTDIR="${3:-$(pwd)}"

sysbench cpu --threads=$THREADS --validate=on --rand-seed=$RANDSEED run > "$OUTPUTDIR/$NAME-cpu-test"
sysbench memory --threads=$THREADS --memory-total-size=100G --validate=on --rand-seed=$RANDSEED run > "$OUTPUTDIR/$NAME-memory-test"
# The total file size should be much larger than ram to avoid caching stuff
# and do a random read/write test to get a more common baseline
sysbench fileio --threads=$THREADS --file-total-size=10G --validate=on --rand-seed=$RANDSEED prepare >/dev/null
sysbench fileio --threads=$THREADS --file-total-size=10G --validate=on --rand-seed=$RANDSEED --file-test-mode=rndrw run > "$OUTPUTDIR/$NAME-fileio-test"
sysbench fileio --threads=$THREADS --file-total-size=10G --validate=on --rand-seed=$RANDSEED cleanup >/dev/null
