#!/bin/bash

## This script requires SwiftDialog to be installed on the receiving machine and is intended to be deployed via Jamf Pro
## Created by: Trenton Cook
## https://www.github.com/Tc00k

#############################################
##                VARIABLES                ##
#############################################

scriptLog="/var/tmp/application_builder.log" ## Local log location
builderJSONFile=$( mktemp -u /var/tmp/builderJSONFile.XXX ) ## Temp file for JSON data that stores the request form
date=$( date "+%a %b %d" )

#############################################
##                 LOGGING                 ##
#############################################

## Function for updating the script log
function updateScriptLog() {
    echo -e "$( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

## Create log file if not found

if [[ ! -f "${scriptLog}" ]]; then
    touch "${scriptLog}"
else
    ## Create adequate spacer in log for readabilities sake
	updateScriptLog ""
    updateScriptLog "---=== $date ===---"
    updateScriptLog ""
fi

#############################################
##              Pre-Run Check              ##
#############################################

updateScriptLog "-- Grabbing Dialog binary..."
dialogBinary="/usr/local/bin/dialog"
noticeIcon=$( defaults read /Library/Preferences/com.jamfsoftware.jamf.plist self_service_app_path )

if [ -d /Applications/SwiftSetup ]; then
    updateScriptLog "-- SwiftSetup installed, continuing..."
else
    updateScriptLog "-- SwiftSetup not installed, prompting..."
    $dialogBinary --message "SwiftSetup Folder not found, build and continue?" --title "SwiftSetupBuilder" --style "alert" --button2text "No" --button1text "Yes" --icon "$noticeIcon" --ontop
    case $? in
        2)
        updateScriptLog "-- User opted out of installation..."
        exit
        ;;
    esac
    updateScriptLog "-- Creating folder dependancies..."
    mkdir /Applications/SwiftSetup
    mkdir /Applications/SwiftSetup/Logs
    mkdir /Applications/SwiftSetup/SetupAssistants
fi

updateScriptLog "-- Checking for Main Builder folder..."
if [ -d /Applications/SwiftSetup_Builder ]; then
    updateScriptLog "-- Folder exists, continuing..."
else
    updateScriptLog "-- Folder missing, creating..."
    mkdir /Applications/SwiftSetup_Builder
fi

#############################################
##                Main Page                ##
#############################################

## Page 1 Variables

updateScriptLog "-- Setting Main Page variables..."
page1button1text="Submit"
page1button2text="Cancel"
page1title="SwiftSetup Builder"
page1Icon=$( defaults read /Library/Preferences/com.jamfsoftware.jamf.plist self_service_app_path )
page1message="Create a name for the setup assistant, limit to one word. The PID Name can be multiple words, pick a name that has no other matches and only shows up when the target application is open"

## Page 1 Configuration

updateScriptLog "-- Writing Alert Data..."

mainPageConfig='
{
    "title" : "'"$page1title"'",
    "message" : "'"$page1message"'",
    "button1text" : "'"$page1button1text"'",
    "button2text" : "'"$page1button2text"'",
    "messagefont" : "size=18",
    "titlefont" : "size-38",
    "textfield" : [
        { "title" : "Product Name","required" : true,"prompt" : "Outlook, Webex, etc..." },
        { "title" : "PID Name","required" : true,"prompt" : "Program Process Name for PID search" }
    ],
    "icon" : "'"$page1Icon"'",
    "height" : "325",
    "position" : "center",
    "ontop" : "true"
}
'

updateScriptLog "-- Writing JSON data to temp file..."
echo "$mainPageConfig" > "$builderJSONFile"

answers=$( eval "${dialogBinary} --jsonfile ${builderJSONFile} --json" )

product=$( echo $answers | grep -o '"Product Name" *: *"[^"]*"' | awk -F'"' '{print $4}')
PID=$( echo $answers | grep -o '"PID Name" *: *"[^"]*"' | awk -F'"' '{print $4}')

if [ "$product" == "" ]; then
    exit 0
fi

#############################################
##          Folder Structure Creation      ##
#############################################

if [ -d /Applications/SwiftSetup/Logs/$product ]; then
    updateScriptLog "-- /Applications/SwiftSetup/Logs/$product already exists..."
else
    updateScriptLog "-- Creating SetupAssistant Logging Directory..."
    mkdir /Applications/SwiftSetup/Logs/$product
fi

if [ $product = "" ]; then
    updateScriptLog "-- Product Name field cannot be empty..."
else
    if [ -d /Applications/SwiftSetup/SetupAssistants/${product}Assistant ]; then
        updateScriptLog "-- /Applications/SwiftSetup/SetupAssistants/${product}assistant already exists..."
    else
        updateScriptLog "-- Creating Setup Assistant Directory..."
        mkdir /Applications/SwiftSetup/SetupAssistants/${product}assistant
    fi
fi

if [ -d /Applications/SwiftSetup/SetupAssistants/${product}Assistant ]; then
    mkdir /Applications/SwiftSetup/SetupAssistants/${product}Assistant/Resources
    mkdir /Applications/SwiftSetup/SetupAssistants/${product}Assistant/Resources/Tmp
    mkdir /Applications/SwiftSetup/SetupAssistants/${product}Assistant/Resources/Video
else
    updateScriptLog "-- Setup Assistant folder does not exist, cannot create dependencies..."
fi

#############################################
##              VARIABLES PT 2             ##
#############################################

activationScript="/Applications/SwiftSetup_Builder/${product}_script.bash"
plist="/Applications/SwiftSetup_Builder/${product}plistCreation.bash"
touch_trigger="/Applications/SwiftSetup/SetupAssistants/${product}Assistant/${product}_Trigger"
touch $touch_trigger
touch /Applications/SwiftSetup/SetupAssistants/${product}Assistant/TouchTarget
chmod +x /Applications/SwiftSetup/SetupAssistants/${product}Assistant/TouchTarget
chmod +x $touch_trigger

#############################################
##         Setup Assistant Script          ##
#############################################

cat <<EOF > $activationScript
#!/bin/bash

###########################################
## Check to see if Dialog is already running            
###########################################

dialogCheck() {
    isItBlocked=\$( pgrep -l "Dialog")
    if [ "\$isItBlocked" != "" ]; then
        echo "Dialog is blocked, waiting..."
        sleep 2
        dialogCheck
    else
        echo "Dialog is unblocked, continuing..."
    fi
}

dialogCheck

launchctl remove ${product}Touch
dialogBinary="/usr/local/bin/dialog"
page1JSONFile=\$( mktemp -u /Applications/SwiftSetup/SetupAssistants/${product}Assistant/Resources/tmp/${product}JSONFile.XXX )
if [ -f "/var/tmp/declined.txt" ]; then
	declinedPrevious="true"
else
	declinedPrevious="false"
fi

##########################################
## DOCK DETECTION
##########################################

docked=\$(system_profiler SPPowerDataType | grep "Connected" | awk '{print\$NF}')
charging=\$(system_profiler SPPowerDataType | grep "ID" | grep -v "appPID" | awk '{print\$NF}')

if [ "\$docked" == "Yes" ] && [ "\$charging" == "0x0000" ]; then
    result="Docked"
fi
if [ "\$docked" == "No" ] && [ "\$charging" == "" ]; then
    result="Undocked"
fi
if [ "\$docked" == "Yes" ] && [ "\$charging" != "0x0000" ]; then
    result="Charging/Undocked"
fi

echo "Machine is: \$result"

##########################################
## Logging Function and Variables
##########################################

## Script log location
scriptLogone="/Applications/SwiftSetup/Logs/$product/${product}SetupAssistant.log"

## Function for updating the script log
function updateScriptLog() {
    echo -e "\$( date +%Y-%m-%d\ %H:%M:%S ) - \${1}" | tee -a "\$scriptLogone"
}

## Create log file if not found

if [[ ! -f "\$scriptLogone" ]]; then
    touch "\$scriptLogone"
else
	updateScriptLog "---==========================================---"
fi

##########################################
## Initial Alert Variables
##########################################

updateScriptLog "-- Initiating remote run of $product Swift Setup..."
updateScriptLog "-- Setting Alert Variables..."
alertbutton1text="Yes"
alertbutton2text="No"
alerttitle="Swift Setup"
alertmessage="Would you like help setting up $product?"
alertIcon=\$( defaults read /Library/Preferences/com.jamfsoftware.jamf.plist self_service_app_path )

# Determine width/height based off dock status

if [ "\$result" == "Docked" ]; then
    page1Width="1000"
    page1Height="750"
else
    page1Width="600"
    page1Height="450"
fi

##########################################
## Initial Alert Configuration
##########################################

updateScriptLog "-- Writing Alert Data..."
alertConfig="\$dialogBinary \
--title \"\$alerttitle\" \
--message \"\$alertmessage\" \
--button1text \"\$alertbutton1text\" \
--button2text \"\$alertbutton2text\" \
--messagefont 'size=18' \
--titlefont 'size=38' \
--height '235' \
--icon \"\$alertIcon\" \
--style \"alert\" \
--position \"center\" \
--ontop \
"

##########################################
## Page 1 Configuration
##########################################

updateScriptLog "-- Writing Page 1 Data..."
page1Config='
{
    "quitkey" : "k",
    "title" : "Setting up ${product}",
    "iconsize" : "150",
    "infobox" : "### Still need help? \n\n### Contact:",
    "ontop" : "false",
    "autoplay" : "true",
    "button1text" : "Close",
    "moveable" : "true",
    "height" : "'\$page1Height'",
    "width" : "'\$page1Width'",
    "video" : "/Applications/SwiftSetup/SetupAssistants/${product}Assistant/Resources/Video/video.mp4",
    "videocaption" : ""
}
'

##########################################
## Opt Screen Variables
##########################################

updateScriptLog "-- Setting Alert Variables..."
optbutton1text="Okay"
optbutton2text="Open Self Service"
opttitle="Reminder"
optmessage="You can always relaunch this Setup Assistant under the SwiftSetup category in Self Service"
optIcon=\$( defaults read /Library/Preferences/com.jamfsoftware.jamf.plist self_service_app_path )

##########################################
## Opt Screen Configuration
##########################################

updateScriptLog "-- Writing Opt Data..."
optConfig="\$dialogBinary \
--title \"\$opttitle\" \
--message \"\$optmessage\" \
--button1text \"\$optbutton1text\" \
--button2text \"\$optbutton2text\" \
--messagefont 'size=20' \
--icon \"\$optIcon\" \
--style \"alert\" \
--position \"center\" \
--ontop \
--quitkey \"k\" \
"

cleanup(){
    rm -rf /Library/LaunchDaemons/${product}Watch.plist
    rm -rf /Library/LaunchDaemons/${product}Touch.plist
    rm -rf \${page1JSONFile}
    launchctl remove ${product}Watch
    exit 0
}

## Applies above JSON to temp JSON file for execution
echo \$page1Config > \$page1JSONFile
chmod 644 "\$page1JSONFile"

##########################################
## Display Alert
##########################################

## Run the dialog for Alert
updateScriptLog ""
updateScriptLog "-- Running Dialog for Alert..."
updateScriptLog "-- Waiting for input..."
## Launches dialog with alert configurations
eval "\${alertConfig}"

## Run commands based off button returns (Alert)
case \$? in 
    ## Button 1 Return
    0)
    updateScriptLog "-- User pressed \$alertbutton1text --"
    assist="Yes"
    updateScriptLog "-- User has accepted Setup Assistant prompt..."
    updateScriptLog ""
    ;;
    ## Button 2 Return
    2)
    updateScriptLog "-- User pressed \$alertbutton2text --"
    updateScriptLog "-- User has opted out of Setup Assistant..."
    updateScriptLog "-- Running Opt screen..."
    if [ "\$declinedPrevious" == "false" ]; then
        eval "\${optConfig}"
        touch "/var/tmp/declined.txt"
        case \$? in
            ## Button 1 Return
            0)
            updateScriptLog "-- User pressed \$optbutton1text --"
            updateScriptLog "-- Running Cleanup..."
            cleanup
            exit 0
            ;;
            ## Button 2 Return
            2)
            updateScriptLog "--User pressed \$optbutton2text --"
            updateScriptLog "-- Launching Self Service..."
            open "/Applications/Self Service.app"
            updateScriptLog "-- Running cleanup and closing..."
            cleanup
            exit 0
        esac
    else
        cleanup
    fi
    ;;
esac


if [ "\$optOut" != "Yes" ]; then
    ##########################################
    ## Display Page 1
    ##########################################

    ## Run the dialog for Page 1
    updateScriptLog ""
    updateScriptLog "-- Running Dialog for Page 1..."
    updateScriptLog "-- Waiting for input..."
    ## Launches dialog with page 1 configurations
    page1ResponseFull=\$("\$dialogBinary" --jsonfile "\$page1JSONFile")

    ## Run commands based off button returns (Alert)
    case $? in 
        ## Button 1 Return
        0)
        updateScriptLog "-- User pressed Close --"
        cleanup
        ;;
    esac
fi

exit 0
EOF

#############################################
##         PLIST Creation Script           ##
#############################################

cat <<EOF > $plist
#!/bin/bash

## Script log location

if [ ! -f /Applications/SwiftSetup/Logs/Core ]; then
    mkdir /Applications/SwiftSetup/Logs/Core
fi

scriptLog="/Applications/SwiftSetup/Logs/Core/PLIST_CREATION.log"

## Function for updating the script log
function updateScriptLog() {
    echo -e "\$( date +%Y-%m-%d\ %H:%M:S ) -\${1}" | tee -a "\${scriptLog}" 
}

## Create log file if not found
if [[ ! -f "\${scriptLog}" ]]; then
    touch "\${scriptLog}"
else
	updateScriptLog "---==========================================---"
fi

## Pull the logged in username and report it to the log for debugging
loggedInUser=\$( /bin/echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil | /usr/bin/awk '/Name :/ { print \$3 }' )
updateScriptLog "Logged in user: \$loggedInUser"

################################ $product ################################

${product}plist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDS/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>com.swiftsetup.watch$product</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
		<string>/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/usr/local/sbin:/opt/local/bin</string>
    </dict>
    <key>Label</key>
    <string>${product}Watch</string>
    <key>LaunchOnlyOnce</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/jamf/bin/jamf</string>
        <string>policy</string>
        <string>-id</string>
        <string>temp</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>WatchPaths</key>
    <array>
        <string>/Applications/SwiftSetup/SetupAssistants/${product}Assistant/TouchTarget</string>
    </array>
</dict>
</plist>"
updateScriptLog "-- Declared $product Part 1 Plist content..."

${product}Touchplist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>EvironmentVariables</key>
    <dict>
        <key>PATH</key>
		<string>/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/usr/local/sbin:/opt/local/bin</string>
    </dict>
    <key>Label</key>
    <string>${product}Touch</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>exec /Applications/SwiftSetup/SetupAssistants/${product}Assistant/${product}_Trigger</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>2</integer>
</dict>
</plist>"
updateScriptLog "-- Declared $product Part 2 Plist content..."

######################
## PLIST CREATION
######################

## Check for LaunchDaemons Folder
if [ -d /Library/LaunchDaemons ]; then
    launchDaemon="true"
    updateScriptLog "-- LaunchDaemon folder has been found, proceeding..."
else
    updateScriptLog "-- LaunchDaemon folder is missing, it will be provided..."
fi

################################ $product ################################

## Write the plist content to the file
if \$launchDaemon == "true" ; then
    updateScriptLog "-- Folder Present: Copying $product Plist content to Daemon..."
    echo "\$${product}plist_content" > /Library/LaunchDaemons/${product}Watch.plist
    echo "\$${product}Touchplist_content" > /Library/LaunchDaemons/${product}Touch.plist
else
    updateScriptLog "-- Folder Missing: Creating Folder..."
    mkdir /Library/LaunchDaemons
    updateScriptLog "-- Folder Present: Copying $product Plist content to Daemon..."
    echo "\$${product}plist_content" > /Library/LaunchDaemons/${product}Watch.plist
    echo "\$${product}Touchplist_content" > /Library/LaunchDaemons/${product}Touch.plist
fi

## edit ownership
updateScriptLog "-- Changing ownership and loading newly created Daemon..."
chmod 644 /Library/LaunchDaemons/${product}Watch.plist
chmod 644 /Library/LaunchDaemons/${product}Touch.plist
chown root:wheel /Library/LaunchDaemons/${product}Watch.plist
chown root:wheel /Library/LaunchDaemons/${product}Touch.plist
sleep 1
launchctl load /Library/LaunchDaemons/${product}Watch.plist
sleep 1
launchctl load /Library/LaunchDaemons/${product}Touch.plist

################################ Finalize ################################

## $product
if [[ -f /Library/LaunchDaemons/${product}Watch.plist ]]; then
    ${product}PlistPresent="Installed"
else
    ${product}PlistPresent="Failed"
fi
if [[ -f /Library/LaunchDaemons/${product}Touch.plist ]]; then
    ${product}TouchPresent="Installed"
else
    ${product}TouchPresent="Failed"
fi

## Display Results

updateScriptLog "$product Plist: "\$${product}PlistPresent""
updateScriptLog "$product Touch: "\$${product}TouchPresent""
EOF

#############################################
##          Touch Trigger Script           ##
#############################################

cat <<EOF > $touch_trigger
#!/bin/bash

## Set the variables used to track $product launch status
application_Name="$product"
file_Path="/Applications/SwiftSetup/SetupAssistants/${product}Assistant/TouchTarget"
isItBlocked=\$( pgrep -l "Dialog")
is_It_Running=\$( pgrep -l "$PID" )
ping -c 1 8.8.8.8 > /dev/null 2>&1
internetConnection=\$?

## Script log location for local runs since I won't have JAMF logs available.
scriptLog="/Applications/SwiftSetup/Logs/${product}/${product}_Trigger.log"

## Function for updating the script log
function updateScriptLog() {
    echo -e "\$( date +%Y-%m-%d\ %H:%M:%S ) - \${1}" | tee -a "\${scriptLog}"
}

## Check to see if log file is there, then what size it is and if it needs to be removed
if [ -f "\${scriptLog}" ]; then
    ## Check log file size and delete previous if above specified size
    max_size="2000000"
    current_size=\$( ls -l \${scriptLog} | awk '{print \$5}' )
    updateScriptLog "Log File Current Size: \${current_size} bytes"

    if [ "\$current_size" -gt "\$max_size" ]; then
        updateScriptLog "Log File Current Size exceeds \${max_size} bytes, removing..."
        rm -rf "\${scriptLog}"
    fi
fi

## Create log file if not found
if [[ ! -f "\${scriptLog}" ]]; then
    touch "\${scriptLog}"
fi

if [ "\$is_It_Running" != "" ] && [ "\$internetConnection" -eq 0 ] && [ "\$isItBlocked" == "" ]; then
    touch "\$file_Path"
    updateScriptLog "$product found to be running, triggering Daemon..."
elif [ "\$is_It_Running" != "" ] && [ "\$isItBlocked" != "" ]; then
    updateScriptLog "$product is running, waiting for previous assistant to close..."
elif [ "\$is_It_Running" == "" ]; then
    updateScriptLog "$product is not running..."
fi
EOF

## Cleanup the temp file
rm -rf $builderJSONFile
