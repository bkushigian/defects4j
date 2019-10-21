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
    if [ "$1" ]
    then
      printf "\033[31;1m$1\033[0m\n"
    fi

    printf "\033[1musage:\033[0m $0 java7-home java8-home [num-trials]\n"
    exit 1
}

java7_home=$1
java8_home=$2
num_trials=$3

if [ -z $java7_home ]
then
  usage "No java7_home provided"
fi

if [ -z $java8_home ]
then
  usage "No java8_home provided"
fi

if [ -z $num_trials ]
then
  num_trials=2
fi

# Ensure that num_trials is a number
re='^[0-9]+$'
if ! [[ $num_trials =~ $re ]] ; then
  echo "error: num_trials \"$num_trials\" is not a number. Setting to 2" >&2
  num_trials=2
fi

FRAMEWORK_DIR="${BASE_DIR}/frameworks"
MAJOR_BIN_DIR="${BASE_DIR}/major/bin"
export MAJOR_JAR="${BASE_DIR}/major.jar"
export BASE_DIR

# All projects
projects=(Chart Closure Lang Math Mockito Time)

# Which projects to test (default: all)
subjects=( "${projects[@]}" )

init

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

  OLDPATH=$PATH
  if $NEW_MAJOR
  then
    export JAVA_HOME=$java8_home
  else
    export JAVA_HOME=$java7_home
  fi

  export PATH="$JAVA_HOME/bin:$PATH"

  printf "\033[92mJAVA_HOME=\033[0m$JAVA_HOME\n"

  # Create a temporary directory for the results of this run
  TMP=`mktemp -d`   # Create Temporary Directory
  printf "\033[94m-- Created temporary directory $TMP\033[0m\n"
  RESULTS="$TMP/results"
  mkdir -p "$RESULTS"
  printf "\033[94m-- Created results directory $RESULTS\033[0m\n"

  for pid in "${projects[@]}"
  do
    if [ "Chart" == "$pid" ]
    then
      continue
    elif [ "Closure" == "$pid" ]
    then
      continue
    fi

    pid_batches="${batches[$pid]}"
    IFS=" " read -ra pid_batch_arr <<< "$pid_batches"
    for batch in "${pid_batch_arr[@]}"
    do
      run_major_on_batch $pid $batch
    done
  done

  # pid="Lang"

  # pid_batches="${batches[$pid]}"
  # IFS=" " read -ra pid_batch_arr <<< "$pid_batches"
  # for batch in "${pid_batch_arr[@]}"
  # do
  #   run_major_on_batch $pid $batch
  # done

  export PATH=$OLDPATH
}

function run_major_on_batch {
  pid=$1
  versions=$2
  if [[ ! "$versions" =~ ^[0-9]*\.\.[0-9]*$ ]]
  then
    echo "Invalid versioning: $versions"
    exit 1
  fi

  printf "\033[32;1m   Invoking parallel on $pid \033[0m\n"
  printf "   parallel run_d4j_on_version ::: $pid ::: `eval echo {$versions}`\n"
  export -f run_d4j_on_version
  export -f lookup_hash_name
  export -f num_triggers
  export TMP
  export RESULTS
  export num_trials
  parallel run_d4j_on_version ::: $pid ::: `eval echo {$versions}`

  # Pick one of the following two for loop heads:
  # for x in `eval echo $versions`
  # for x in `echo {1..2}`
  # do
  #   run_d4j_on_version $pid $x
  # done

}

function lookup_hash_name {
  pid=$1
  v=$2
  work_dir=$3
  BUGGY_COMMIT_HASH=`sed "${v}q;d" "$BASE_DIR/framework/projects/$pid/commit-db" | cut -d, -f2`
  FIXED_COMMIT_HASH=`sed "${v}q;d" "$BASE_DIR/framework/projects/$pid/commit-db" | cut -d, -f3`
  printf "\033[32mCommit hash for $pid-$v (buggy):\033[0m $BUGGY_COMMIT_HASH\n"
  printf "\033[32mCommit hash for $pid-$v (fixed):\033[0m $FIXED_COMMIT_HASH\n"
}

function run_d4j_on_version {
  pid=$1
  v=$2
  vid="${v}f"
  work_dir="$TMP/$pid-$vid"
  printf "\033[94;1m========================== $pid:$vid in $work_dir ==========================\033[0m\n"
  rm -rf $work_dir

  # Create a directory to store results of this run
  dirname="$RESULTS/$pid-$vid"
  mkdir "$dirname"
  printf "\033[32;1m-- Created results directory $dirname \033[0m\n"
  printf "\033[32;1m-- Running defects4j checkout -p $pid -v $vid -w $work_dir \033[0m\n"
  defects4j checkout -p $pid -v $vid -w "$work_dir" || die "checkout: $pid-$vid"
  printf "\033[32;1m-- Running defects4j compile -w $work_dir \033[0m\n"
  defects4j compile -w $work_dir                    || die "compile: $pid-$vid"

  if [ $? -ne 0 ]
  then
    printf "\033[31;1m   Compile failed \033[0m\n"
    return 1
  fi

  printf "\033[32;1m-- Running defects4j test -w $work_dir \033[0m\n"
  defects4j test -w $work_dir                       || die "run relevant tests: $pid-$vid"

  triggers=$(num_triggers "$work_dir/failing_tests")

  if [ $triggers -ne 0 ] ; then

    lookup_hash_name $pid $v $work_dir

    ## Echo to failing_tests
    printf "\033[32;1m-- Updating failing tests:\033[0m $work_dir/failing_tests >> $BASE_DIR/framework/projects/$pid/failing_tests/$FIXED_COMMIT_HASH\n"
    cat "$work_dir/failing_tests" >> "$BASE_DIR/framework/projects/$pid/failing_tests/$FIXED_COMMIT_HASH"
    rm "$work_dir/all_tests" "$work_dir/failing_tests"
    printf "\033[32;1m-- Rerunning defects4j test -w $work_dir with appended failing tests\033[0m\n"
    defects4j test -w $work_dir                       || die "run relevant tests: $pid-$vid"

    triggers=$(num_triggers "$work_dir/failing_tests")
    if [ $triggers -ne 0 ] ; then
      printf "\033[31;1m[!!!] Tests still failing after updating project failing tests\033[0m\n"
      return 1
    fi


    printf "\033[34;1m   Tests succeeded \033[0m\n"
    for name in "all_tests" "failing_tests"
    do
      src="$work_dir/$name"
      trg="$dirname/$name"
      printf "\033[34;1m   Moving $src--->$trg\033[0m\n"
      mv "$src" "$trg"
    done


  fi

  # Expected number of failing tests for each fixed version is 0
  [ $triggers -eq 0 ] || return 1  # die "verify number of triggering tests: $pid-$vid (expected: 0, actual: $triggers)"


  last_dir=`pwd`

  printf "\033[32;1m-- Running mutation trials (num_trials=$num_trials) \033[0m\n"
  cd "$work_dir"
  printf "\033[34;1m   CWD=`pwd` \033[0m\n"

  # For each trial, run mutation
  for k in $(seq $num_trials); do
    printf "\033[34;1m   -- Running trial $k of $num_trials\033[0m\n"
    printf "\033[34;1m      Resetting git repo for clean trial\033[0m\n"
    git reset --hard
    git clean -fd
    printf "\033[34;1m      Running defects4j mutation -w $work_dir \033[0m\n"
    defects4j mutation -w $work_dir
    if [ $? -eq 0 ] # Mutation went well, lets copy results
    then
      printf "\033[34;1m      Creating trial result dir \"$dirname/$k\" \033[0m\n"
      mkdir "$dirname/$k"
      for name in ".mutation.log" "mutants.log" "kill.csv" "testMap.csv" "summary.csv"
      do
        src="$work_dir/$name"
        trg="$dirname/$k/$name"
        printf "\033[34;1m      Moving $src--->$trg\033[0m\n"
        mv "$src" "$trg"
      done
    fi
  done
  cd "$last_dir"
  printf "\033[34;1m   CWD=`pwd` \033[0m\n"
  printf "\033[34;1m   Removing working directory "$work_dir" \033[0m\n"
  rm -rf $work_dir
}


printf "\n\033[92m   ---   Running new major   ---\033[0m\n"
printf "\033[92m         =================      \033[0m\n\n"
NEW_MAJOR=true run_major
tmp_maj2=$TMP

printf "\n\033[92m   ---   Running old major   ---\033[0m\n"
printf "\033[92m         =================      \033[0m\n\n"
NEW_MAJOR=false run_major
tmp_maj1=$TMP

echo "Major 1 results in $tmp_maj1"
echo "Major 2 results in $tmp_maj2"
