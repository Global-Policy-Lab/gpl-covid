#! /bin/bash
# from https://gist.github.com/pschumm/b967dfc7f723507ac4be
# Wrapper for "stata -b" which issues an informative error msg and appropriate
# (i.e., non-zero) return code

# The basic idea for this script (including grepping the log file to determine
# whether there was an error) was taken from a similar script posted by Brendan
# Halpin on his blog at http://teaching.sociology.ul.ie/bhalpin/wordpress/?p=122

args=$#  # number of args

cmd=""
if [ "$1" = "do" ] && [ "$args" -gt 1 ]
then
    log="`basename -s .do "$2"`.log"
    # mimic Stata's behavior (stata-mp -b do "foo bar.do" -> foo.log)
    log=${log/% */.log}
# Stata requires explicit -do- command, but we relax this to permit just the
# name of a single do-file
elif [ "$args" -eq 1 ] && [ "${1##*.}" = "do" ] && [ "$1" != "do" ]
then
    cmd="do"
    log="`basename -s .do "$1"`.log"
    log=${log/% */.log}
else
    # else Stata interprets it as a command and logs to stata.log
    log="stata.log"    
fi

# in batch mode, nothing sent to stdout (is this guaranteed?)
stderr=`stata-mp -b $cmd "$@" 2>&1`
rc=$?
if [ -n "$stderr" ]  # typically usage info
then
    echo "$stderr"
    exit $rc
elif [ $rc != "0" ]
then
    exit $rc
else
    # use --max-count to avoid matching final line ("end of do-file") when
    # do-file terminates with error
    if egrep --before-context=1 --max-count=1 "^r\([0-9]+\);$" "$log"
    then
        exit 1
    fi
fi