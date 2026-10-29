#!/bin/sh
# Prove the Jenkinsfile has the stages we want, nested the way we want: the clusters stage holds unums, whose us and them lanes each
# have an up and a test of their own, then across, so a failure shows which act broke, and in which Unum, from the stage alone.
# Usage: test/stages.sh. It reads the stage names and how far each is indented, so it needs the Jenkinsfile's layout to stay put.
set -e

actual=$(grep -E "^ *stage\('" Jenkinsfile | sed -E "s/^( *)stage\('([^']*)'\).*/\1|\2/" | awk -F'|' '{print length($1) " " $2}')

expected="8 lint
8 test
8 clusters
16 tools
16 unums
24 us
32 up
32 test
24 them
32 up
32 test
16 across
8 tag"

test "$actual" = "$expected" || { echo "the Jenkinsfile stages are not what we want. Got:"; echo "$actual"; echo "Wanted:"; echo "$expected"; exit 1; }

echo "stages are as wanted"
