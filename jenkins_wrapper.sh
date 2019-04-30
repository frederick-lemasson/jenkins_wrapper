#!/bin/bash
# Wrapper for sending the results of an arbitrary script/command to Jenkins for
# monitoring. 
#
# Usage: 
#   jenkins_wrapper <job> <script>
#
#   e.g. jenkins_wrapper testjob /path/to/script.sh
#        jenkins_wrapper testjob 'sleep 2 && ls -la'
#
#   example with authentication:
#        CURL_AUTH_OPTS="--user myuser:pass" jenkins_wrapper http://jenkins.myco.com:8080 testjob /path/to/script.sh
#
# Requires:
#   - curl
#   - bc
#
# Runs <script>, capturing its stdout, stderr, and return code, then sends all
# that info to Jenkins under a Jenkins job named <job>.
#
# Recent changes - joeym@joeym.net:
#  1) If a job doesn't exist in Jenkins, it will automatically be created
#  2) Job names with whitespace are now supported (eg: "My Job #1")
#
# Forked for minor corrections (was almost perfect) from :
#   http://github.com/joemiller/hudson_wrapper
#
#  Jenkins configuration : create the user JENKINS_WRAPPER_USER :  Configurer la sécurité globale / CSRF Protection off 

if [ $# -lt 2 ]; then
    echo "Not enough args!"
    echo "Usage: $0 JENKINS_JOB_NAME SCRIPT"
    exit 1
fi


#JENKINS_URL=$1; shift
JENKINS_URL="http://localhost:8080"
#JENKINS_WRAPPER_USER="jen"
JENKINS_WRAPPER_USER="admin"
#SECRETPASSWORD="barber"
SECRETPASSWORD="4b7959ebb25d4673a840abf9cb34b285"
JOB_NAME=$1; shift
SCRIPT="$@"
CURL_AUTH_OPS="--user $JENKINS_WRAPPER_USER:$SECRETPASSWORD"
CURL_AUTH_OPTS=${CURL_AUTH_OPTS:="--user $JENKINS_WRAPPER_USER:$SECRETPASSWORD"}


# check if jenkins is running
if curl -s --head --user $JENKINS_WRAPPER_USER:$SECRETPASSWORD $JENKINS_URL | grep "HTTP/1.1 200 OK" > /dev/null 2>&1
    then
		echo "Jenkins on $JENKINS_URL is OK :) ... lets go on ..."
    else
		echo "Jenkins on $JENKINS_URL is KO :( ... run the job locally anyway ..."
		$SCRIPT 
		exit $?
fi

# this option gets passed directly to curl.  Use it to specify credentials if your jenkins
# requires it.  Otherwise, leave it blank (CURL_AUTH_OPTS="").  You can also override this
# by setting it in your environment before calling this script

#CURL_AUTH_OPTS=${CURL_AUTH_OPTS:="--user $JENKINS_WRAPPER_USER:$SECRETPASSWORD"}
#CURL_AUTH_OPTS=""

HOSTNAME=$(hostname)

echo Encode any whitespace in the job name for URLs
JOB_NAME=$(echo $HOSTNAME"_"$JOB_NAME | sed -e 's/[        ][      ]*/%20/g')

OUTFILE=$(mktemp -t jenkins_wrapper.XXXXXX)
echo "Temp file is    : $OUTFILE"   >> $OUTFILE
echo "Jenkins job name : $JOB_NAME"  >> $OUTFILE
echo "Script being run: $SCRIPT"    >> $OUTFILE
echo "Host            : $HOSTNAME"  >> $OUTFILE
echo "" >> $OUTFILE

echo Execute the given script, capturing the result and how long it takes.

START_TIME=$(date +"%s.%N")
START_TIME_NICE=$(date)
eval $SCRIPT >> $OUTFILE 2>&1
RESULT=$?
END_TIME=$(date +"%s.%N")
END_TIME_NICE=$(date)
ELAPSED_MS=$(echo "($END_TIME - $START_TIME) * 1000 / 1" | bc)
echo "" >> $OUTFILE
echo "Start time: $START_TIME_NICE     ($START_TIME)" >> $OUTFILE
echo "End time  : $END_TIME_NICE     ($END_TIME)" >> $OUTFILE
echo "Elapsed ms: $ELAPSED_MS"  >> $OUTFILE

echo Post the results of the command to Jenkins.
CURLTEMP=$(mktemp -t jenkins_wrapper_curl.XXXXXXXX)
echo "<run><log encoding=\"hexBinary\">$(od -v -t xC $OUTFILE | sed '$d; s/^[0-9]* //' | tr -d ' \n\r')</log><result>${RESULT}</result><duration>${ELAPSED_MS}</duration></run>" > $CURLTEMP

echo Create job if it does not exist
http_code=$(curl -s -o /dev/null -w'%{http_code}' -X POST ${CURL_AUTH_OPTS} ${JENKINS_URL}/job/${JOB_NAME})

if [ "${http_code}" = "404" ]; then
        # create a new external job named '$JOB_NAME' on the jenkins server

        temp_create=$(mktemp -t jenkins_wrapper_curl-createjob.XXXXXXXX)

        cat >${temp_create} <<-EOF
<?xml version='1.0' encoding='UTF-8'?>
<hudson.model.ExternalJob>
  <actions/>
  <description>command: '$SCRIPT' , running from host: $HOSTNAME </description>
  <logRotator class="hudson.tasks.LogRotator">
    <daysToKeep>2</daysToKeep>
    <numToKeep>-1</numToKeep>
    <artifactDaysToKeep>-1</artifactDaysToKeep>
    <artifactNumToKeep>-1</artifactNumToKeep>
  </logRotator>
  <keepDependencies>false</keepDependencies>
  <properties/>
</hudson.model.ExternalJob>
EOF
        curl -s -X POST -d @${temp_create} ${CURL_AUTH_OPTS} -H "Content-Type: text/xml" "${JENKINS_URL}/createItem?name=${JOB_NAME}"
        #echo "Curl Result Job Create :" $?
        ## sleep then try to hit the job.  I noticed this was necessary otherwise
        ## the /postBuildResult step would fail
        sleep 1
        curl -s -o /dev/null ${CURL_AUTH_OPTS} "${JENKINS_URL}/job/${JOB_NAME}/"
        rm $temp_create
        sleep 1
fi

### post results to jenkins
#echo curl -s -X POST -d @${CURLTEMP} ${CURL_AUTH_OPTS} "${JENKINS_URL}/job/${JOB_NAME}/postBuildResult"
curl -s -X POST -d @${CURLTEMP} ${CURL_AUTH_OPTS} "${JENKINS_URL}/job/${JOB_NAME}/postBuildResult"
#echo "curl result:"$?


### Clean up our temp files and we're done.

#cat $CURLTEMP
#cat $OUTFILE
rm $CURLTEMP
rm $OUTFILE
