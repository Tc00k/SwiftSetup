# SwiftSetup

Created by: Trenton Cook

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Building Setup Assistants](#building-setup-assistants)
  - [Cancellation Message](#cancellation-message)
- [Creating Multiple Setup Assistants](#creating-multiple-setup-assistants)


## Introduction

SwiftSetup is a custom made solution for guiding users through first time login and setup after a SetupYourMac run (https://github.com/dan-snelson/Setup-Your-Mac)

## Features

- 📋 Local logging & JAMF logging
- 😄 User friendly GUI
- 💻 Made specifically for a Jamf Pro environment

## Getting Started

Follow the below steps to get SwiftSetup setup and running

### Prerequisites

Make sure you have the following:

- Jamf Instance with the target computer(s) added
- SwiftDialog installed on the target computer(s) (https://github.com/swiftDialog/swiftDialog)
- The SwiftSetup_Builder.pkg installed on your machine

### Building Setup Assistants

1. Open your Applications folder and navigate to the SwiftSetup_Builder folder
2. Run assistant_builder as sudo
3. When/if prompted to build the SwiftSetup folder select "Yes"
4. Find the PID name of the process you are building a setup assistant for (pgrep -l "Process Name" in terminal)
5. Enter a Name for the Setup Assistant in the first field and the PID Name for that application in the second field, be sure to limit the first field to one word. Ex. "MicrosoftOutlook" | "CiscoWebex" and not "Microsoft Outlook" | "Cisco Webex"
6. Double check that the SwiftSetup folder has been created correctly in /Applications
7. Double check that there is a Log folder and Setup Assistant folder for your new Setup Assistant in /Applications/SwiftSetup
8. Upload the $product_script.bash to your Jamf instance and create an accompanying policy with that script attached. Scope this policy to any machine that will be utilizing this setup assistant *** Be sure to copy down this new policies ID number ***
9. Adjust the $productplistcreation.bash script to launch your $product_scripts policy ID (Default line 51)
10. Upload the adjusted $productplistcreation.bash to your Jamf instance and create an accompanying policy with that script attached. Scope this policy to any machine that will be utilizing this setup assistant. Create a custom trigger for this to attach it to your SetupYourMac instance, or find another way to install the trigger PLISTs at enrollment
11. Test a run of the $productplistcreation policy (Be sure the application you chose for the Setup Assistant is NOT running)
12. You should now see two LaunchDaemons in /Library/LaunchDaemons ( $productwatch && $producttouch )
13. If you run sudo launchctl list | grep $product in a terminal you should also see that these launchdaemons are loaded
14. Launch the application that you are creating the Setup Assistant for
15. If you check /Applications/SwiftSetup/Logs/$product you should now see a trigger log that will state "Application found to be running, triggering daemon..."
16. This should now trigger the policy id number for your $productscript policy in Jamf, thus launching the Setup Assistant
17. By default this Setup Assistant has no content and will simply be a notice and two blank images in the SetupAssistant portion visit [Adding Photos](#adding-photos) to see how to customize this content
18. When you exit out of the Setup Assistant you can check the following:
  - sudo launchctl list | grep $product to confirm that both launchdaemons were successfully unloaded
  - /Library/LaunchDaemons to confirm that both $product.plist files were deleted correctly
  - /Applications/SwiftSetup/Logs/$product to check that the setupassistant log was populated correctly
  - The $productscript policy logs to confirm that they were also populated correctly





## Customization

Follow the below steps to customize your newly created Setup Assistant

  ### Adding Photos
  
  By default when you launch a newly created Setup Assistant it will have no images on two blank slides, in order to setup customized steps with photos please follow the below instructions
  
  - Open /Applications/SwiftSetup/SetupAssistants/$productAssistant/Resources/Images
  - Open your $productscript script in Jamf or your favorite script editing program
  - Under line 62 (By default) there is an images array built out in swiftDialog, this is where we will add links to each of our images and adjust the captions as needed
  - By default the image naming scheme is simply "Page1 | Page2 | Etc" Take screenshots of you setting up your application and add them to /Applications/SwiftSetup/SetupAssistants/$productAssistant/Resources/Images and name them according to this scheme
  - You can have as many images as SwiftDialog will support in the carousel format, but for each image over the default of two you will need to add another line in the array under line 62. You can easily copy paste the lines there already and adjust the "Page2.png" --> "Page3.png" and so forth.
  - Anything you type in the empty quotes by "Caption" : "" will be displayed under the images in your setup assistant
  
  ### Titles and Message Content
  
  You can adjust all Titles and messages under line sections 27 & 47 (by default) please check the swiftDialog GitHub page linked above for more details on adjusting the dialog values
  
  Title - What is displayed at the very top of the dialog window when it appears
  Message - The main text body for the dialog window
  Icon - as default is set to your Self Service icon, however can be set to any file path or image address on the internet
  Infobox - Body of text off to the left in the main dialog window
  Ontop - Forces the dialog window to be above all other windows on the screen (Off by default)
  Moveable - Allows the dialog window to be moved (On by default)
  
  ### Cancellation Message
  
  The user that receives the Setup Assistant prompt has the ability to close out of it and set up the application on their own if they so choose. In our environment we have it set so that all Setup Assistants can be called from any time in their own section of "Self Service" you can adjust or remove this message entirely under lines 70/81/120





## Creating Multiple Setup Assistants

You can use the Setup Builder tool to create more than one Setup Assistant and have all of them install after enrollment with just a few tweaks if you wish.

If you already have one Setup Assistant created and running smoothly, adding a second one is a relatively pain free process, follow the steps below to get started.

1. Follow steps 1-8 under [Building Setup Assistants](#building-setup-assistants) above to create a second Setup Assistant
2. Open the $productplistcreation.bash script for your newly created Setup Assistant
3. Copy the plist variable declaration section from your new script and add it to your original plistcreation script (lines 27 - 88 in the new script)
4. There should now be a plist_content and touchplist_content variable for all of your Setup Assistants in the original script
5. Copy the ## Write the plist content to the file and ## edit ownership sections from your new plist creation script (lines 102 - 126) and add it to your original plist creation script
6. Copy the ## Test section from your new plist creation script (lines 130 - 140) and add it to your original plist creation script
7. Copy the ## Display Results section from your new plist creation script (lines 144 & 145) and add it to your original plist creation script
8. Save your original script with all the changes and reupload it to JAMF
9. When it is ran at enrollment it will now install plists for both your Setup Assistants and adjust the permissions
  
