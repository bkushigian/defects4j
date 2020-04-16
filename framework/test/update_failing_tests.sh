#!/bin/bash

################################################################################
# This script updates the failing tests recorded by defects4j projects to
# reflect new Java failures. To do this, it runs `defects4j test` on each fixed
# version of each problem and updates d4j's failing test database respectively.
#
# This expects GNU parallel to be installed.
#
# USAGE: update_failing_tests.sh [JAVA_HOME]
#        JAVA_HOME: the location of the Java install (such as
#                   /usr/lib/jvm/openjdk-1.8.xxx). This should either be
#                   provided by command line or be provided via an environment
#                   variable.
################################################################################

source test.include

usage() {
    if [ "$1" ]
    then
        echo "$1"
    fi

    printf "usage: %s java8-home\n"  "$0"
    exit 1
}

if [ -z "$JAVA_HOME" ]
then
    JAVA_HOME=$1
fi
if [ -z "$JAVA_HOME" ]
then
    usage "No JAVA_HOME provided"
fi
if [ ! -e "$JAVA_HOME" ] || [ ! -e "$JAVA_HOME/bin/javac" ]
then
  usage "JAVA_HOME doesn't exist: $JAVA_HOME"
fi

export PATH="$JAVA_HOME/bin:$PATH"
export JAVA_HOME

# All projects
projects=( Collections )

echo "Running update_failing_tests.sh with JAVA_HOME=$JAVA_HOME"

################################################################################
# dtstring: Get the current time and date as a string
################################################################################
function dtstring {
    date "+%T %D"
}

################################################################################
# Determine if bug id $bid is deprecated in $pid
################################################################################
function bid_deprecated_in_pid {
    bid="$1"
    pid="$2"
    ds=$(./deprecated "${pid}")
    [[ " ${ds[@]} " =~ " ${bid} " ]]
}

################################################################################
# Write a timestamped message to stdout as well as logging to file
################################################################################
function pplog {
    log "[$(date "+%T")] $1"
    echo "$1"
}

################################################################################
# Log a banner: --- My Message ---
################################################################################
function logbanner {
    log "$1"
    echo
    echo "  --- $1 ---"
    echo
}

################################################################################
# Log an error
################################################################################
function logerr {
    log "[$(date "+%T")] [Error] $1"
    echo "$1"
}


################################################################################
# lookup_bid_in_commit_db: get the entry for bid $bid in $pid's commit-db
#
# Arguments:
#    1. pid: the project id we care about (i.e., "Chart", "Math", etc)
#    2. bid: the bug id that we care about (i.e., "1", "2", etc)
#
# Prints the matching entry to stdout if it is found
# Returns:
#    0 on success (entry found)
#    1 on failure (no entry found)
################################################################################
function lookup_bid_in_commit_db {
    pid=$1
    bid=$2
    grep "^$bid," "$BASE_DIR/framework/projects/$pid/commit-db"
}

################################################################################
# lookup_hash_name: lookup hashes for buggy and fixed commits in the
# `framework/projects/$pid/commit-db` database. These are stored in global
# variables BUGGY_COMMIT_HASH and FIXED_COMMIT_HASH.
#
# Arguments:
#    1. pid: the project id that we care about (i.e., "Chart", "Math", etc)
#    2. bid: the bug id that we care about (i.e., "1", "2", etc)
#
# Returns: commit hashes of buggy and fixed versions of the program in global
# variables BUGGY_COMMIT_HASH and FIXED_COMMIT_HASH
################################################################################
function lookup_hash_name {
    pid=$1
    bid=$2
    BUGGY_COMMIT_HASH=$(lookup_bid_in_commit_db $pid $bid | cut -d, -f2)
    FIXED_COMMIT_HASH=$(lookup_bid_in_commit_db $pid $bid | cut -d, -f3)
    pplog "Commit hash for $pid-$bid (buggy): $BUGGY_COMMIT_HASH"
    pplog "Commit hash for $pid-$bid (fixed): $FIXED_COMMIT_HASH"
}

################################################################################
# Run tests on each pid in parallel
################################################################################
function run_tests {
    export -f dtstring
    export -f run_tests_on_pid
    export -f die
    export -f pplog
    export -f logerr
    export -f logbanner
    export -f pplog
    export -f pplog
    export -f lookup_hash_name
    export -f log
    export -f num_lines
    export -f num_triggers
    export -f lookup_bid_in_commit_db
    export script
    export TEST_DIR
    export BASE_DIR
    export TMP_DIR
    export -f bid_deprecated_in_pid

    parallel   --jobs 6 --progress --bar  run_tests_on_pid ::: "${projects[@]}"
}

################################################################################
# run tests on a single pid, updating failing tests. This function
# 1. identifies the bugids for the given project id
# 2. for each bug id, this:
#    - sets up a clean working directory
#    - checks out the project at the fixed version of bid via
#      `defects4j checkout -v "${bid}f" ...`
#    - compiles the checked out version of the project
#    - runs tests on the checked out version of the project
#    - if there are triggering tests, updates d4j's database of failing tests via
#
#            src="$work_dir/failing_tests"
#            trg=framework/projects/$pid/failing_tests/$FIXED_COMMIT_HASH
#            cat $src >> $trg
#
#    - runs a sanity check to ensure that this addition to the failing test
#      database stops `defects4j test` from running the failing tests again; in
#      particular, after a clean checkout of the same bug, running
#      `defects4j test` should yield 0 triggering tests. If this fails, report
#      an error and exit with non-zero status
# Arguments:
#     - pid: the project id (i.e., "Chart", "Math", etc)
################################################################################
function run_tests_on_pid {
    local pid
    local script_name
    local num_bugs
    local test_dir
    local vid
    local triggers

    pid=$1

    # Create log file
    script_name=$(echo "$script" | sed 's/\.sh$//')
    LOG="$TEST_DIR/${script_name}$(printf '_%s_%s' "$pid" $$).log"

    logbanner "Running tests on $pid"
    # Reproduce all bugs (and log all results), regardless of whether errors occur
    export HALT_ON_ERROR=0

    # Compute $BUGS as a sequence of each bug id
    BUGS="$(ls "$BASE_DIR/framework/projects/$pid/relevant_tests" | sort -n)"
    num_bugs=$(echo $BUGS | wc -w)

    test_dir="$TMP_DIR/run_tests"
    mkdir -p "$test_dir"

    work_dir="$test_dir/$pid"
    # Ensure a clean working directory
    rm -rf "$work_dir"

    pplog "logging to $LOG"
    pplog "all_bugs: $num_bugs"
    pplog "test_dir: $test_dir"
    pplog "work_dir: $work_dir"

    for bid in $BUGS
    do
        if bid_deprecated_in_pid $bid $pid ; then
            echo "bug $bid deprecated in $pid"
            continue
        fi


        rm -rf "$work_dir"
        vid="${bid}f"
        logbanner "Working on $pid-$vid ($bid of $num_bugs)"
        pplog "[+] checking out project: pid=$pid vid=$vid work_dir=$work_dir"
        defects4j checkout -p $pid -v "$vid" -w "$work_dir" || die "checkout: $pid-$vid"
        pplog "[+] compiling project: pid=$pid vid=$vid work_dir=$work_dir"
        defects4j compile -w "$work_dir" || die "compile: $pid-$vid"
        pplog "[+] running tests: pid=$pid vid=$vid work_dir=$work_dir"
        defects4j test -w "$work_dir"    || die "run tests: $pid-$vid"

        triggers=$(num_triggers "$work_dir/failing_tests")
        pplog "found $triggers triggering tests"

        # If there are failing tests, then add them to the defects4j repo
        if [ "$triggers" -ne 0 ] ; then
            lookup_hash_name "$pid" "$bid" "$work_dir"

            # Echo to failing_tests
            src="$work_dir/failing_tests"
            pid_failing_tests="$BASE_DIR/framework/projects/$pid/failing_tests"
            trg="$pid_failing_tests/$FIXED_COMMIT_HASH"
            if [ ! -d "$pid_failing_tests" ]
            then
                pplog "Directory $pid_failing_tests doesn't exist"
                pplog "Making directory $pid_failing_tests"
                mkdir -p "$pid_failing_tests"
            else
                pplog "Directory $pid_failing_tests exists...continuing"
            fi
            pplog "updating failing tests: $src >> $trg"
            cat "$src" >> "$trg"
            rm -rf "$work_dir"

            # Rerun to sanity check that this worked
            pplog "rerunning defects4j test -w $work_dir with appended failing tests"
            pplog "[+] checking out project: pid=$pid vid=$vid work_dir=$work_dir"
            defects4j checkout -p $pid -v "$vid" -w "$work_dir" || die "checkout: $pid-$vid"
            pplog "[+] compiling project: pid=$pid vid=$vid work_dir=$work_dir"
            defects4j compile -w "$work_dir" || die "compile: $pid-$vid"
            pplog "[+] running tests: pid=$pid vid=$vid work_dir=$work_dir"
            defects4j test -w "$work_dir"    || die "run tests: $pid-$vid"

            triggers=$(num_triggers "$work_dir/failing_tests")
            if [ "$triggers" -ne 0 ] ; then
                logerr "[!!!] Tests still failing after updating project failing tests"
                return 1
            fi

            pplog "   Tests succeeded"
        fi


    done
}

run_tests


