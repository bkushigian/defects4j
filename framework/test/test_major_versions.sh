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

    printf "\033[1musage:\033[0m $0 java_home\n"
    exit 1
}

java_home=$1

if [ -z $java_home ]
then
  usage "No java_home provided"
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
RESULTS="$TMP/results"
mkdir -p "$RESULTS"
printf "\033[94m-- Created results directory $RESULTS\033[0m\n"

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

function run_major {

  # Run for each pid
  export JAVA_HOME=$java_home
  export PATH="$JAVA_HOME/bin:$PATH"
  # for pid in "${projects[@]}"
  # do
  #   if [ "Chart" == "$pid" ]
  #   then
  #     continue
  #   fi

  #   echo "Running on $pid"

  #   pid_batches="${batches[$pid]}"
  #   IFS=" " read -ra pid_batch_arr <<< "$pid_batches"
  #   for batch in "${pid_batch_arr[@]}"
  #   do
  #     echo ".... batch $batch"
  #     run_major_on_batch $pid $batch
  #     exit 0
  #   done
  # done

  pid="Lang"
  echo "Running on $pid"

  pid_batches="${batches[$pid]}"
  IFS=" " read -ra pid_batch_arr <<< "$pid_batches"
  for batch in "${pid_batch_arr[@]}"
  do
    echo ".... batch $batch"
    run_major_on_batch $pid $batch
    exit 0
  done
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

  # for x in `eval echo $versions`
  for x in `echo {1..4}`
  do
    run_d4j_on_version $pid $x
  done

}

function run_d4j_on_version {
  echo "--- 0: $0 1: $1 2: $2 3: $3 ---"
  pid=$1
  v=$2
  vid="${v}f"
  work_dir="$TMP/$pid-$vid"
  printf "\033[94;1m========================== $pid:$vid in $work_dir ==========================\033[0m\n"
  rm -rf $work_dir

  export JAVA_HOME=$java_home
  export PATH
  printf "\033[32;1m-- Running defects4j checkout -p $pid -v $vid -w $work_dir \033[0m\n"
  defects4j checkout -p $pid -v $vid -w "$work_dir" || die "checkout: $pid-$vid"
  printf "\033[32;1m-- Running defects4j compile -w $work_dir \033[0m\n"
  defects4j compile -w $work_dir                    || die "compile: $pid-$vid"

  printf "\033[32;1m-- Running defects4j test -w $work_dir \033[0m\n"
  defects4j test -w $work_dir                       || die "run relevant tests: $pid-$vid"

  return 0

  triggers=$(num_triggers "$work_dir/failing_tests")
  # Expected number of failing tests for each fixed version is 0
  [ $triggers -eq 0 ] || return 1  # die "verify number of triggering tests: $pid-$vid (expected: 0, actual: $triggers)"

  printf "\033[32;1m-- Running defects4j mutation -w $work_dir \033[0m\n"
  defects4j mutation -w $work_dir
  if [ $? -eq 0 ] # Mutatino went well, lets copy results
  then
    prefix="$pid-$vid"
    for name in ".mutations.log" "mutants.log" "kill.csv" "summary.csv"
    do
      echo "Moving $work_dir/$name---->$RESULTS/$prefix-$name"
      mv "$work_dir/$name" "$RESULTS/$prefix-$name"
    done
    rm -rf $work_dir
  fi

}


run_major
