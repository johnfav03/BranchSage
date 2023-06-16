# BranchSage
This is a script that's meant to improve workplace efficiency by connecting to the Jira API to maintain a local registry of active tickets and help automatically name branches. In addition, the goal was to automate company standard processes for using git, creating new branches, and more.
# Prerequisites
You'll need 2 pieces of information for the startup script - your email that Jira uses, which likely follows the format of first.last@energysage.com. The second piece you need is a Jira API Token. To get an API Token for your account, follow this link: [Jira API Tokens](https://id.atlassian.com/manage-profile/security/api-tokens). Then, click the 'Create API Token'. Give it a label, click 'Create', then click 'Copy'. Write this down for the setup!
# Setup
First, we need to make a navigate to the home directory, then pull the files from git.
```bash
$ cd ~
$ git clone git@github.com:johnfav03/BranchSage.git
```
Next, let's make some changes to our zshrc file so that we can use the 'egs' shortcut for the script.
```bash
$ echo 'egs() { source ~/BranchSage/main.sh $@; }' >> ~/.zshrc
$ source ~/.zshrc
```
Now, lets run the init script and input the relevant information. Email and Token are as detailed in ***Prerequisites***, and AWS Login is the profile you'd like to use for AWS, or leave it blank to select seperately each time. As of writing this, the options for AWS Login are 'es-site-standard', 'replica-db-connect', or 'es-site-dev'.
```bash
$ egs init
```
Congratulations, you're done! Now you can start running commands.
# Commands
If you've followed the previous steps, you can run any of the following commands by typing 'egs' followed by the 4-letter word in brackets. For example:
```bash
$ egs prep
```
Here are all the available commands:
- ***[prep]***
prep sets up your working environment for you; it navigates to the `es-site` directory, it opens your virtual environment, and it runs the AWS Login script if you aren't already logged in.
- ***[show]***
show lists out a basic list of the tickets considered 'active' and stored in the local registry. Alongside each ticket, it prints the current status of the ticket as displayed in Jira. As a note, this intentionally doesn't pull new tickets from Jira, only grow and trim do.
- ***[trim]***
trim helps automate your branches by pulling from Jira and updating the local registry by removing any tickets that are marked 'Done'. It then automatically looks for branches that follow the uppercase letters, hyphen, 4 digits, hyphen pattern and cannot be found in the local registry. If found, these branches are deleted.
- ***[grow]***
grow is the opposite of trim; it also pulls from Jira to update the local registry, and then for any tickets that don't have corresponding branches, it will create a new branch with a name generated automatically by the ticket name. As a note, it won't change existing branch names if they follow the EnergySage naming scheme. Remember to run sync first!
- ***[swap]***
swap is a tool to help facilitate quick navigation between branches that correspond to tickets; after using grow, branch names can get quite long. this command takes a parameter of a 4 digit number, or prints a prompt to ask for one if left blank. It then checks out the branch that matches that ticket number. By default, entering '.' as either the parameter or in the prompt will take you to the `develop` branch.
- ***[roll]***
roll is meant to make restoring files through git quicker; instead of typing the whole file path, this command prints all changed files indexed, then prints a prompt to take in an index. It then restores that file to it's state from the previous commit. By default, entering '.' in the prompt will restore all files.
- ***[sync]***
sync is meant to be run before making a new branch, as it synchronizes `develop` with the main codebase and runs `make update`.