#!/bin/bash

################################################################################
# This script updates the failing tests recorded by defects4j projects to
# reflect Java 8-related failures. To do this, it runs `defects4j test` on
# each fixed version of each problem and updates d4j's failing test database
# respectively.
#
# This expects GNU parallel to be installed.
#
# USAGE: update_failing_tests.sh JAVA_HOME
#        JAVA_HOME: the location of the Java install (such as
#                   /usr/lib/jvm/openjdk-1.8.xxx)
################################################################################

source test.include

usage() {
    if [ "$1" ]
    then
        printf "\033[31;1m$1\033[0m\n"
    fi

    printf "\033[1musage:\033[0m $0 java8-home\n"
    exit 1
}

if [ -z $JAVA_HOME ]
then
    JAVA_HOME=$1
fi
if [ -z $JAVA_HOME ]
then
    usage "No java_home provided"
fi

export PATH="$JAVA_HOME/bin:$PATH"
export JAVA_HOME

# All projects
projects=(Chart Closure Lang Math Mockito Time)

export ANSI_ERROR="\033[91;1m"
export ANSI_INFO="\033[94;1m"
export ANSI_SUCCESS="\033[92;1m"
export ANSI_CLEAR="\033[0m"
export ANSI_GREEN="\033[32m"
export ANSI_BANNER=$ANSI_SUCCESS

echo "Running update_failing_tests.sh with JAVA_HOME=$JAVA_HOME"

function dtstring {
    date "+%T %D"
}

# Pretty print the log to stdout. Accepts an ansi code to prepend
function pplog {
    message="$1"
    code="$2"

    log "[$(date "+%T")] $message"
    printf "${code}${message}$ANSI_CLEAR\n"
}

function loginfo {
    pplog "$1" $ANSI_INFO
}

function logerr {
    pplog "$1" $ANSI_ERROR
}

function logsucc {
    pplog "$1" $ANSI_SUCCESS
}

function logbanner {
    message="$1"

    log "$message"
    printf "${ANSI_BANNER}--- ${message} ---$ANSI_CLEAR\n"
}

function lookup_hash_name {
    pid=$1
    v=$2
    work_dir=$3
    BUGGY_COMMIT_HASH=`sed "${v}q;d" "$BASE_DIR/framework/projects/$pid/commit-db" | cut -d, -f2`
    FIXED_COMMIT_HASH=`sed "${v}q;d" "$BASE_DIR/framework/projects/$pid/commit-db" | cut -d, -f3`
    pplog "Commit hash for $pid-$v (buggy): $BUGGY_COMMIT_HASH" $ANSI_GREEN
    pplog "Commit hash for $pid-$v (fixed): $FIXED_COMMIT_HASH" $ANSI_GREEN
}

function run_tests {
    export -f dtstring
    export -f run_test_on_pid
    export -f die
    export -f pplog
    export -f logbanner
    export -f logerr
    export -f loginfo
    export -f logsucc
    export -f lookup_hash_name
    export -f log
    export -f num_lines
    export -f num_triggers
    export script
    export TEST_DIR
    export BASE_DIR
    export TMP_DIR

    parallel   --jobs 16 --progress --bar  run_test_on_pid ::: "${projects[@]}"
}

function run_test_on_pid {
    pid=$1
    echo $pid

    # Create log file
    script_name=$(echo $script | sed 's/\.sh$//')
    LOG="$TEST_DIR/${script_name}$(printf '_%s_%s' $pid $$).log"
    loginfo "JAVA_HOME: $JAVA_HOME"

    logbanner "Working on $pid"
    # Reproduce all bugs (and log all results), regardless of whether errors occur
    HALT_ON_ERROR=0

    # Get number of bugs in pid
    num_bugs=$(num_lines $BASE_DIR/framework/projects/$pid/commit-db)
    BUGS="$(seq 1 1 $num_bugs)"

    test_dir="$TMP_DIR/run_tests"
    mkdir -p $test_dir

    work_dir="$test_dir/$pid"
    # Ensure a clean working directory
    rm -rf $work_dir

    loginfo "logging to $LOG"
    loginfo "num_bugs: $num_bugs"
    loginfo "test_dir: $test_dir"
    loginfo "work_dir: $work_dir"

    for bid in $(echo $BUGS); do
        rm -rf $work_dir
        vid="${bid}f"
        logbanner "Working on $pid-$vid ($bid of $num_bugs)"
        loginfo "[+] checking out project: pid=$pid vid=$vid work_dir=$work_dir"
        defects4j checkout -p $pid -v "$vid" -w "$work_dir" || die "checkout: $pid-$vid"
        loginfo "[+] compiling project: pid=$pid vid=$vid work_dir=$work_dir"
        defects4j compile -w "$work_dir" || die "compile: $pid-$vid"
        loginfo "[+] running tests: pid=$pid vid=$vid work_dir=$work_dir"
        defects4j test -w "$work_dir"    || die "run tests: $pid-$vid"

        triggers=$(num_triggers "$work_dir/failing_tests")

        loginfo "found $triggers triggering tests"
        # If there are failing tests, then add them to the defects4j repo
        if [ $triggers -ne 0 ] ; then
            lookup_hash_name $pid $bid $work_dir

            # Echo to failing_tests
            src="$work_dir/failing_tests"
            trg="$BASE_DIR/framework/projects/$pid/failing_tests/$FIXED_COMMIT_HASH"
            loginfo "updating failing tests: $src >> $trg"
            cat "$src" >> "$trg"
            rm -rf $work_dir

            # Rerun to sanity check that this worked
            loginfo "rerunning defects4j test -w $work_dir with appended failing tests"
            loginfo "[+] checking out project: pid=$pid vid=$vid work_dir=$work_dir"
            defects4j checkout -p $pid -v "$vid" -w "$work_dir" || die "checkout: $pid-$vid"
            loginfo "[+] compiling project: pid=$pid vid=$vid work_dir=$work_dir"
            defects4j compile -w "$work_dir" || die "compile: $pid-$vid"
            loginfo "[+] running tests: pid=$pid vid=$vid work_dir=$work_dir"
            defects4j test -w "$work_dir"    || die "run tests: $pid-$vid"

            triggers=$(num_triggers "$work_dir/failing_tests")
            if [ $triggers -ne 0 ] ; then
                logerr "[!!!] Tests still failing after updating project failing tests"
                return 1
            fi

            loginfo "   Tests succeeded"
#            for name in "all_tests" "failing_tests"
#            do
#                src="$work_dir/$name"
#                trg="$dirname/$name"
#                loginfo "   Moving $src--->$trg"
#                mv "$src" "$trg"
#            done

        fi


    done
}

run_tests


