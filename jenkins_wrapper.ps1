# Jenkins Wrapper for Windows in powershell
# Wrapper for sending the results of an arbitrary script to Jenkins for
# monitoring. 
# freely inspired/translated from the GNU/Linux version : http://github.com/joemiller/hudson_wrapper
# Fred
# 20-05-2014


if ($Args.Count -lt 2) {
    echo "Not enough args !"
    echo "Usage: $0 JENKINS_JOB_NAME SCRIPT"
    exit 1
}

$error.clear()

#Variables
$JENKINS_URL="http://myjenkinsfqdn::8080"
$SCRIPT=$Args[1..$Args.Length] -join " "
$CURL="D:\Tools\curl\curl.exe"
$HOSTNAME=hostname
$CURL_AUTH_OPTS='--user JENKINS_WRAPPER_USER:SECRETPASSWORD'
$JOB_NAME=$HOSTNAME+'_'+$Args[0]

## encode any whitespace in the job name for URLs
Add-Type -AssemblyName System.Web
$JOB_NAME=[System.Web.HttpUtility]::UrlEncode($JOB_NAME)

$OUTFILE=[IO.Path]::GetTempFileName()
#echo "OUTFILE : " $OUTFILE

$JobHeader=@"

Jenkins job name : $JOB_NAME
Script being run : $SCRIPT
Host             : $HOSTNAME


"@ 

### Execute the given script, capturing the result and how long it takes.
$JobTimer=[Diagnostics.Stopwatch]::StartNew()
$START_TIME=$(get-date -format "u")

Invoke-Expression "$SCRIPT 2>&1" >> $OUTFILE
$RESULT=$LASTEXITCODE

$ErrorCount=$error.Count

#Exit code / Catch non blocking errors
#if ($ErrorCount -gt $RESULT){
	#$RESULT=$ErrorCount
#}

if ($ErrorCount -gt 0){
	$ErrorDescription="`nError :`n"+(($error[0]) -join "`n")
}else{
	$ErrorDescription="`n"
}

$CmdOutput=(Get-Content $OUTFILE) -join "`n"
#$CmdOutput=Get-Content $OUTFILE
#$CmdOutput = [string]::join("`r`n",$CmdOutput)



$JobTimer.Stop()
$END_TIME=$(get-date -format "u")
$ELAPSED_MS=$JobTimer.Elapsed.TotalMilliseconds.ToString().Split(",")[0]


$JobFooter=@"


Start time    : $START_TIME
End time      : $END_TIME
Elapsed ms    : $ELAPSED_MS
Error Count   : $ErrorCount
Cmd Exit Code : $RESULT


"@

#Eviter d'envoyer un rapport trop long ce qui fait planter l'encodage/le post
$MaxCmdOutputLength=8192
if($CmdOutput.length -gt $MaxCmdOutputLength){
#echo "reducing output"
$CmdOutput=$CmdOutput.substring($CmdOutput.length - $MaxCmdOutputLength,$MaxCmdOutputLength)
}

$data = $JobHeader + $CmdOutput + $ErrorDescription + $JobFooter
#echo $data


### Post the results of the command to Jenkins.

# We build up our XML payload this helps avoid 'argument list
# too long' issues.

$ans=""
[System.Text.Encoding]::UTF8.GetBytes($data) | % { $ans += "{0:X2}" -f $_ }

#XML payload :
$CmdResult = @"
<run><log encoding='hexBinary'>$ans</log><result>$RESULT</result><duration>$ELAPSED_MS</duration></run> 
"@

### create job if it does not exist

$CurlCmd=@"
$CURL -s -w "%{http_code}" -X POST $CURL_AUTH_OPTS $JENKINS_URL/job/$JOB_NAME
"@
#echo $CurlCmd
$http_reply=Invoke-Expression $CurlCmd

if (@($http_reply |Select-String "HTTP ERROR 404").Count -gt 0){
        echo "Creating a new external job named $JOB_NAME on the jenkins server $JENKINS_URL"
		
$PostData = @"
<?xml version='1.0' encoding='UTF-8'?>
<hudson.model.ExternalJob>
  <actions/>
  <description>command: '$SCRIPT' , running from host: $HOSTNAME </description>
  <logRotator class="'hudson.tasks.LogRotator'>"     <daysToKeep>2</daysToKeep>
	<numToKeep>-1</numToKeep>
	<artifactDaysToKeep>-1</artifactDaysToKeep>
	<artifactNumToKeep>-1</artifactNumToKeep>
  </logRotator>
  <keepDependencies>false</keepDependencies>
  <properties/>
</hudson.model.ExternalJob>
"@

$CurlCmd=@"
$CURL -s -X POST $CURL_AUTH_OPTS -d "$PostData" -H "Content-Type: text/xml" "$JENKINS_URL/createItem?name=$JOB_NAME"
"@
	#echo "CurlCmd : "$CurlCmd
        Invoke-Expression $CurlCmd
        #echo "Curl Result Job Create :" $?
        ## sleep then try to hit the job.  I noticed this was necessary otherwise
        ## the /postBuildResult step would fail
        sleep 1
        Invoke-Expression "$CURL -s $CURL_AUTH_OPTS ""$JENKINS_URL/job/$JOB_NAME/"""
        #rm $CurlJob
        sleep 1
}

### post results to jenkins
$CurlCmd=@"
$CURL -s -X POST $CURL_AUTH_OPTS -d "$CmdResult" $JENKINS_URL/job/$JOB_NAME/postBuildResult
"@

Invoke-Expression $CurlCmd

### Clean up our temp files and we're done.
rm $OUTFILE

exit $RESULT
