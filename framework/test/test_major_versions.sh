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

function dtstring {
    date "+%T %D"
}

# Pretty print the log to stdout. Accepts an ansi code to prepend
function pplog {
    message="$1"
    code="$2"

    log "[$(date "+%T")] $message"
    printf "%s\n" "${code}${message}$ANSI_CLEAR"
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

function loggreen {
    pplog "$1" $ANSI_BANNER
}

function logbanner {
    message="$1"

    log "$message"
    printf "%s\n" "${ANSI_BANNER}--- ${message} ---$ANSI_CLEAR"
}

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

loginfo "JAVA7_HOME: $JAVA7_HOME"
loginfo "JAVA8_HOME: $JAVA8_HOME"
loginfo "num_trials: $num_trials"

# Ensure that num_trials is a number
re='^[0-9]+$'
if ! [[ $num_trials =~ $re ]] ; then
  echo "error: num_trials \"$num_trials\" is not a number. Setting to 2" >&2
  num_trials=2
fi

export FRAMEWORK_DIR="${BASE_DIR}/frameworks"
export MAJOR_BIN_DIR="${BASE_DIR}/major/bin"
export MAJOR_JAR="${BASE_DIR}/major.jar"
export BASE_DIR

# $SHARED_RESOURCES stores high-level resources such as test ordering that are
# shared between different runs of this script (say, between major1 and major2)
export SHARED_RESOURCES="/tmp/d4j"
if [ ! -e "$SHARED_RESOURCES" ]
then
  mkdir -p "$SHARED_RESOURCES"
fi

export D4J_TEST_ORDER="$SHARED_RESOURCES/test-orders"
if [ ! -e $D4J_TEST_ORDER ] 
then
  mkdir -p $D4J_TEST_ORDER
fi

# All projects
projects=(Chart Closure Lang Math Mockito Time)
loginfo "projects: ${projects[@]}"

init

# 1: Get program versions to test (all for now)

# 2: Split into batches
#    Each batch should be of the form "{$pid}{$lo}..{$hi}"

declare -A batches=(
  [Chart]="26"
  [Closure]="176"
  [Lang]="65"
  [Math]="106"
  [Mockito]="38"
  [Time]="27"
  )

function make_jobs_file {

  jobs_file="$1/jobs"
  loginfo "Creating jobs_file: $jobs_file"
  logs="$1/logs"
  mkdir -p "$logs"
  for pid in "${projects[@]}"
  do
    if [ "Chart" == "$pid" ]
    then
      continue
    elif [ "Closure" == "$pid" ]
    then
      continue
    fi

    versions="${batches[$pid]}"
    for v in `seq 1 1 $versions`
    do
      pid_log_file="$logs/$pid-$v.log"
      job="run_d4j_on_version $pid $v >> $pid_log_file 2>&1"
      loginfo "Creating job for pid $pid and vid $vid: $job"
      echo "$job" >> $jobs_file
    done
  done
}

function run_major {

  OLDPATH=$PATH
  if $NEW_MAJOR
  then
    export JAVA_HOME=$java8_home
  else
    export JAVA_HOME=$java7_home
  fi

  export PATH="$JAVA_HOME/bin:$PATH"

  loginfo "JAVA_HOME=$JAVA_HOME"
  loginfo "PATH=$PATH"


  # Create a temporary directory for the results of this run
  TMP=`mktemp -d`   # Create Temporary Directory
  loginfo "-- Created temporary director $TMP"

  RESULTS="$TMP/results"
  mkdir -p "$RESULTS"
  loginfo "-- Created results directory $RESULTS"

  mkdir -p "$TMP/logs"
  loginfo "-- Created log directory $TMP/logs"


  # The following are high-level log files for the analysis

  # STATUS_CSV: Keep track of explicit status of each trial---some may not
  # terminate normally and may not write here
  export STATUS_CSV="$TMP/status.csv"

  # STARTED_CSV: Keep track of all trials we start---even if they don't end
  # normally and aren't saved in STATUS_CSV their start will be tracked here
  export STARTED_CSV="$TMP/started.csv"

  # FAILED_CSV: Keep track of explicitly failed trails
  export FAILED_CSV="$TMP/failed.csv"

  # SUCCESS_CSV: Keep track of explicitly failed trails
  export SUCCESS_CSV="$TMP/success.csv"

  # COMPLETED_CSV: Keep track of successful trials
  export COMPLETED_CSV="$TMP/completed.csv"

  echo "pid,vid,trial,start_t,end_t,success?" >> "$STATUS_CSV"
  echo "pid,vid,trial" >> "$STARTED_CSV"
  echo "pid,vid,trial" >> "$FAILED_CSV"
  echo "pid,vid,trial" >> "$COMPLETED_CSV"
  echo "pid,vid,trial" >> "$SUCCESS_CSV"

  if $RUN_IN_PARALLEL
  then
    make_jobs_file "$TMP"
    loginfo "-- Created jobs file at $jobs_file"

    export -f run_d4j_on_version
    export -f lookup_hash_name
    export -f num_triggers

    export -f dtstring
    export -f die
    export -f pplog
    export -f logbanner
    export -f logerr
    export -f loginfo
    export -f logsucc
    export -f log
    export -f num_triggers
    export script
    export TMP
    export RESULTS
    export num_trials
    export TEST_DIR
    export BASE_DIR
    export TMP_DIR

    loginfo "   Invoking parallel"
    parallel -a $jobs_file --jobs 16 --progress --bar --ungroup
  else
    loginfo "Bypassing parallel: running all sequentially"
    run_all
  fi

  export PATH=$OLDPATH
}

# bypass parallel
function run_all {

  for pid in "${projects[@]}"
  do
    if [ "Chart" == "$pid" ] || [ "Closure" == "$pid" ]
    then
      continue
    fi

    versions="${batches[$pid]}"
    for v in `seq 1 1 $versions`
    do
      run_d4j_on_version $pid $v
    done
  done
}

function lookup_hash_name {
  pid=$1
  v=$2
  work_dir=$3
  BUGGY_COMMIT_HASH=`sed "${v}q;d" "$BASE_DIR/framework/projects/$pid/commit-db" | cut -d, -f2`
  FIXED_COMMIT_HASH=`sed "${v}q;d" "$BASE_DIR/framework/projects/$pid/commit-db" | cut -d, -f3`
  loginfo "Commit hash for $pid-$v (buggy): $BUGGY_COMMIT_HASH"
  loginfo "Commit hash for $pid-$v (fixed): $FIXED_COMMIT_HASH"
}

function run_d4j_on_version {
  pid=$1
  v=$2
  vid="${v}f"

  # 0-pad version number
  printf -v padded "%02d" $v

  work_dir="$TMP/$pid-$v"
  script_name=$(echo $script | sed 's/\.sh$//')

  # Determine major version for log file name
  major_version="major1"
  if $NEW_MAJOR
  then
    major_version="major2"
  fi
  LOG="$TMP/logs/${major_version}_${script_name}$(printf '_%s_%s' $pid $padded).log"

  loginfo "========================== $pid:$vid in $work_dir =========================="

  # Create a directory to store results of this run
  PID_VID_RESULTS="$RESULTS/$pid-$v"
  mkdir -p "$PID_VID_RESULTS"
  loginfo "-- Created results directory $PID_VID_RESULTS "
  loginfo "-- Running defects4j checkout -p $pid -v $vid -w $work_dir"
  defects4j checkout -p $pid -v $vid -w "$work_dir" || die "checkout: $pid-$vid"
  loginfo "-- Running defects4j compile -w $work_dir"
  defects4j compile -w $work_dir                    || die "compile: $pid-$vid"

  if [ $? -ne 0 ]
  then
    logerr "   Compile failed"
    return 1
  fi

  loginfo "-- Running defects4j test -w $work_dir"
  defects4j test -w $work_dir                       || die "run relevant tests: $pid-$vid"

  triggers=$(num_triggers "$work_dir/failing_tests")

  # Expected number of failing tests for each fixed version is 0
  if [ $triggers -ne 0 ] ; then
    logerr "    Found failing tests! Have your run \"update_failing_tests.sh\"?"
    return 1
  fi

  last_dir=$(pwd)

  loginfo "-- Running mutation trials (num_trials=$num_trials)"
  cd "$work_dir"
  loginfo "   CWD=$(pwd)"
  trials_dir="$PID_VID_RESULTS/trials"
  mkdir -p "$trials_dir"

  # For each trial, run mutation
  for k in $(seq $num_trials); do
    loginfo "   -- Running trial $k of $num_trials"
    loginfo "      Resetting git repo for clean trial"
    git reset --hard
    git clean -fd

    # We're ready to run d4j mutation...
    loginfo "      Running defects4j mutation -w $work_dir"

    loginfo "      Recording start of mutation at $STARTED_CSV"
    echo "$pid,$v,$k" >> $STARTED_CSV
    start_time=$(date "+%T")
    defects4j mutation -w $work_dir
    rescode=$?
    end_time=$(date "+%T")

    if [ $rescode -eq 0 ] # Mutation went well, lets copy results
    then
      loginfo "      Mutation successful. Logging to $SUCCESS_CSV, $STATUS_CSV, and $COMPLETED_CSV"
      echo "$pid,$v,$k" >> "$SUCCESS_CSV"
      echo "$pid,$v,$k,$start_time,$end_time,1" >> "$STATUS_CSV"
      echo "$pid,$v,$k" >> "$COMPLETED_CSV"
      loginfo "      Creating trial result dir \"$PID_VID_RESULTS/$k\""
      mkdir "$trials_dir/$k"
      for name in ".mutation.log" "mutants.log" "kill.csv" "testMap.csv" "summary.csv" "testMap.csv"
      do
        src="$work_dir/$name"
        trg="$trials_dir/$k/$name"
        if [ -e $src ]
        then
          loginfo "      Moving $src--->$trg"
          mv "$src" "$trg"
        fi
      done
    else          # Mutation failed
      logerr "      Mutation failed! Logging to $FAILED_CSV, $STATUS_CSV, and $COMPLETED_CSV"
      echo "$pid,$v,$k" >> "$FAILED_CSV"
      echo "$pid,$v,$k,$start_time,$end_time,0" >> "$STATUS_CSV"
      echo "$pid,$v,$k" >> "$COMPLETED_CSV"
    fi
  done
  cd "$last_dir"
  loginfo "   CWD=`pwd`"
  loginfo "   Removing working directory "$work_dir""
  rm -rf $work_dir
}


# pplog "   ---   Running new major   ---" $ANSI_BANNER
# pplog "         =================      " $ANSI_BANNER
# NEW_MAJOR=true run_major
# tmp_maj2=$TMP

pplog "   ---   Running old major   ---" $ANSI_BANNER
pplog "         =================      " $ANSI_BANNER
NEW_MAJOR=false run_major
tmp_maj1=$TMP

loginfo "Major 1 results in $tmp_maj1"
# loginfo "Major 2 results in $tmp_maj2"
