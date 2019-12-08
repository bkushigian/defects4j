#!/bin/bash

################################################################################
# A convenience script to invoke test_major_versions.sh, passing the proper    #
# Java 7 and Java 8 install locations, the number of trials to run, and the    #
# amount of time to run before timing out (1 hour)                             #
################################################################################

# ./test_major_versions.sh /scratch/benku/jdk7/jdk1.7.0_80 /usr/lib/jvm/java-1.8.0 15 "2.5h"
TRIALS="$1"
TIMEOUT="$2"
if [ -z $TRIALS ] ; then
  TRIALS=5
fi

if [ -z $TIMEOUT ] ; then
  TIMEOUT="2h"
fi

./test_major_versions.sh /usr/lib/jvm/java-1.8.0 /usr/lib/jvm/java-1.8.0 15 "2.5h"
