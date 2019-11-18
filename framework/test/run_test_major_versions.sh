#!/bin/bash

################################################################################
# A convenience script to invoke test_major_versions.sh, passing the proper    #
# Java 7 and Java 8 install locations, the number of trials to run, and the    #
# amount of time to run before timing out (1 hour)                             #
################################################################################

./test_major_versions.sh /scratch/benku/jdk7/jdk1.7.0_80 /usr/lib/jvm/java-1.8.0 5 "12h"
