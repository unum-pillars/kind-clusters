#!/bin/sh
# Prove the Jenkinsfile is one-for-one: every step runs exactly one make command, and the stages group them by function, nested the way
# we want, so a red row is one command, in one stage, in one Unum. The stages are clone (what gets the code into an empty workspace),
# within (everything that needs no cluster, and the tools the clusters need), clusters (unums with an us and a them lane, then across)
# and tag. The only steps that aren't a make command are in clone (a docker run that removes what a run left in the workspace, which
# would stop the checkout, and the checkout), the cleanup after the clusters, and the tag. Usage: test/stages.sh. It reads the
# Jenkinsfile as laid out, so the layout has to stay put.
set -e

actual=$(grep -E "^ *stage\('" Jenkinsfile | sed -E "s/^( *)stage\('([^']*)'\).*/\1|\2/" | awk -F'|' '{print length($1) " " $2}')

expected="8 clone
8 within
8 clusters
16 unums
24 us
24 them
16 across
8 tag"

test "$actual" = "$expected" || { echo "the Jenkinsfile stages are not what we want. Got:"; echo "$actual"; echo "Wanted:"; echo "$expected"; exit 1; }

# The make commands, in order, one for each step.
steps=$(grep -E "^ *sh 'make [^;]*'$" Jenkinsfile | sed -E "s/^ *sh '(.*)'$/\1/")

wanted="make lint
make test-add
make test-version
make test-context
make test-stages
make tools
make down NAME=us
make ci NAME=us
make test NAME=us
make down NAME=them
make ci NAME=them
make test NAME=them
make test-cross
make test-route
make test-write"

test "$steps" = "$wanted" || { echo "the make commands in the Jenkinsfile are not what we want. Got:"; echo "$steps"; echo "Wanted:"; echo "$wanted"; exit 1; }

# And nothing else is run: the sh steps that aren't a make command are the clean, the cleanup after the clusters, and the tag.
others=$(grep -E "^ *sh " Jenkinsfile | grep -vE "^ *sh 'make [^;]*'$" | grep -vE "docker run --rm -v|^ *sh '''$" || true)

test -z "$others" || { echo "the Jenkinsfile runs commands that aren't make commands:"; echo "$others"; exit 1; }

# And the tag gets the repo's URL from git, because checkout scm as a step leaves GIT_URL unset in the shell, and the push goes to https:///
! grep -q 'GIT_URL' Jenkinsfile || { echo "the Jenkinsfile uses GIT_URL, which is empty after checkout scm. Use git remote get-url origin"; exit 1; }
grep -q 'git remote get-url origin' Jenkinsfile || { echo "the tag stage doesn't read the URL from git remote get-url origin"; exit 1; }

echo "stages are as wanted, one make command for each step"
