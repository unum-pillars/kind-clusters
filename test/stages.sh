#!/bin/sh
# Prove the Jenkinsfile is one-for-one: every stage runs exactly one command, and the stages are the ones we want, nested the way we
# want (the clusters stage holds tools, then unums with an us and a them lane that each have a down, an up and a test, then the cross
# and route tests), so a red bubble is one act, in one Unum, and nothing else. Usage: test/stages.sh. It reads the stage names and how
# far each is indented, so it needs the Jenkinsfile's layout to stay put.
set -e

actual=$(grep -E "^ *stage\('" Jenkinsfile | sed -E "s/^( *)stage\('([^']*)'\).*/\1|\2/" | awk -F'|' '{print length($1) " " $2}')

expected="8 lint
8 checks
16 test-add
16 test-version
16 test-context
16 test-stages
8 clusters
16 tools
16 unums
24 us
32 down
32 up
32 test
24 them
32 down
32 up
32 test
16 test-cross
16 test-route
16 test-write
8 tag"

test "$actual" = "$expected" || { echo "the Jenkinsfile stages are not what we want. Got:"; echo "$actual"; echo "Wanted:"; echo "$expected"; exit 1; }

# Each steps block runs one sh, not two.
many=$(awk '
    /^ *steps \{/ { match($0, /^ */); depth = RLENGTH; count = 0; inside = 1; start = NR; next }
    inside && /^ *sh / { count++ }
    inside && match($0, /^ *\}/) && RLENGTH == depth + 1 && substr($0, depth + 1, 1) == "}" { if (count != 1) print "line " start ": " count " sh steps"; inside = 0 }
' Jenkinsfile)

test -z "$many" || { echo "a stage runs more or less than one command:"; echo "$many"; exit 1; }

echo "stages are as wanted, one command each"
