#!/usr/bin/env bash
################################################################################
#
# This script verifies that Major 7 and Major 8's behavior is the same on all
# bugs. This includes front-end mutant generation and ant back-end mutant
# killing.
#
################################################################################
# Import helper subroutines and variables, and init Defects4J
source test.include

# Print usage message and exit
usage() {
    #     local known_pids=$(cd "$BASE_DIR"/framework/core/Project && ls *.pm | sed -e 's/\.pm//g')
    #     echo "usage: $0 -p <project id> [-b <bug id> ... | -b <bug id range> ... ]"
    #     echo "Project ids:"
    #     for pid in $known_pids; do
    #         echo "  * $pid"
    #     done
    if [ -z "$1" ]
    then
      printf "\033[31;1m$1\033[0m\n"
    fi

    printf "\033[1musage:\033[0m $0 [java7_home [java8_home]]\n"
    exit 1
}

java7_home=$1
java8_home=$2

if [ -z $java7_home ]
then
  printf "Looking for java-7 install..."
  java7_home=`find /usr/lib/jvm/java-1.7.*` || usage "Couldn't find java7 home"
  printf "Found $java7_home\n"
fi

if [ -z $java8_home ]
then
  printf "Looking for java-8 install..."
  java8_home=`find /usr/lib/jvm/java-1.8.*` || usage "Couldn't find java8 home"
  printf "Found $java8_home\n"
fi

FRAMEWORK_DIR="${BASE_DIR}/frameworks"
MAJOR_BIN_DIR="${BASE_DIR}/major/bin"

# All projects
projects=(Chart Closure Lang Math Mockito Time)

# Which projects to test (default: all)
subjects=( "${projects[@]}" )

init
TMP=`mktemp -d`   # Create Temporary Directory
printf "\033[94m-- Created temporary directory $TMP\033[0m\n"

# 1: Get program versions to test (all for now)

# 2: Split into batches
#    Each batch should be of the form "{$pid}{$lo}..{$hi}"

declare -A batches=(
  [Chart]="1..26"
  [Closure]="1..176"
  [Lang]="1..65"
  [Math]="1..106"
  [Mockito]="1..38"
  [Time]="1..27"
  )

function run_major7 {
  # Copy current version of major and mmlc to tmp
  mv "$MAJOR_BIN_DIR/major" "$TMP/major.old"
  mv "$MAJOR_BIN_DIR/mmlc" "$TMP/mmlc.old"

  # Move major7 and mmlc7 to major bin dir
  cp "$TEST_DIR/resources/major-versions/major7" "$MAJOR_BIN_DIR/major"
  cp "$TEST_DIR/resources/major-versions/mmlc7" "$MAJOR_BIN_DIR/mmlc"

  # Run for each pid
  export JAVA_HOME="$java7_home"
  for pid in "${projects[@]}"
  do
    if [ "Chart" == "$pid" ]
    then
      continue
    fi

    echo "Running on $pid"

    pid_batches="${batches[$pid]}"
    IFS=" " read -ra pid_batch_arr <<< "$pid_batches"
    for batch in "${pid_batch_arr[@]}"
    do
      echo ".... batch $batch"
      run_major_on_batch $pid $batch
      exit 0
    done
  done

  # Restore Major and MMLC Scripts
  mv "$TMP/major.old" "$MAJOR_BIN_DIR/major"
  mv "$TMP/mmlc.old" "$MAJOR_BIN_DIR/mmlc"
}

function run_major_on_batch {
  pid=$1
  versions=$2
  if [[ ! "$versions" =~ ^[0-9]*\.\.[0-9]*$ ]]
  then
    echo "Invalid versioning: $versions"
    exit 1
  fi

  # printf "Invoking parallel on $pid $vid\n"
  # printf "parallel run_d4j_on_version ::: $pid ::: `eval echo {$versions}`"
  # export -f run_d4j_on_version
  # export TMP
  # export -f num_triggers
  # parallel run_d4j_on_version ::: $pid ::: `eval echo {1..3}` # {$versions}`
  for x in `echo {1..3}`
  do
    echo "RUNNING d4j on $pid $x"
    run_d4j_on_version $pid $x
  done

}

function run_d4j_on_version {
  echo "--- 0: $0 1: $1 2: $2 3: $3 ---"
  pid=$1
  v=$2
  vid="${v}f"
  work_dir="$TMP/$pid-$vid-major7"
  printf "\033[94;1m========================== $pid:$vid in $work_dir ==========================\033[0m\n"
  rm -rf $work_dir

  printf "\033[32;1m-- Running defects4j checkout -p $pid -v $vid -w $work_dir \033[0m\n"
  defects4j checkout -p $pid -v $vid -w "$work_dir" || die "checkout: $pid-$vid"
  printf "\033[32;1m-- Running defects4j compile -w $work_dir \033[0m\n"
  defects4j compile -w $work_dir                    || die "compile: $pid-$vid"
  printf "\033[32;1m-- Running defects4j test -w $work_dir \033[0m\n"
  defects4j test -r -w $work_dir                    || die "run relevant tests: $pid-$vid"

  triggers=$(num_triggers "$work_dir/failing_tests")
  # Expected number of failing tests for each fixed version is 0
  [ $triggers -eq 0 ] || return 1  # die "verify number of triggering tests: $pid-$vid (expected: 0, actual: $triggers)"

  printf "\033[32;1m-- Running defects4j mutation -w $work_dir \033[0m\n"
  defects4j mutation -w $work_dir

}

function run_major8 {
  # Copy current version of major and mmlc to tmp
  mv "$MAJOR_BIN_DIR/major" "$TMP/major.old"
  mv "$MAJOR_BIN_DIR/mmlc" "$TMP/mmlc.old"

  # Move major7 and mmlc7 to major bin dir
  cp "$TEST_DIR/resources/major-versions/major8" "$MAJOR_BIN_DIR/major"
  cp "$TEST_DIR/resources/major-versions/mmlc8" "$MAJOR_BIN_DIR/mmlc"

  export JAVA_HOME="$java8_home"
  # Run for each pid
  for pid in "${projects[@]}"
  do
    if [ "Chart" == "$pid" ]
    then
      continue
    fi

    echo "Running Major 8 on $pid"

    pid_batches="${batches[$pid]}"
    IFS=" " read -ra pid_batch_arr <<< "$pid_batches"
    for batch in "${pid_batch_arr[@]}"
    do
      echo ".... batch $batch"
      run_major_on_batch $pid $batch
    done
  done

  # Restore Major and MMLC Scripts
  mv "$TMP/major.old" "$MAJOR_BIN_DIR/major"
  mv "$TMP/mmlc.old" "$MAJOR_BIN_DIR/mmlc"
}


run_major7
run_major8
