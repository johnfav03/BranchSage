#!/usr/bin/env zsh
autoload -U colors && colors
txtcolor=yellow

#### SHOW ####
# PRINTS ACTIVE TICKET KEYS AND THEIR STATUSES
jira_show() {
    ticks=$(read_ticks)
    token=$(read_token)
    uname=$(read_uname)
    currs=""
    while IFS= read -r tick; do 
        prnl reading $tick
        blob=$(curl -s -u $uname:$token -X GET -H "Content-Type: application/json" https://energysage.atlassian.net/rest/api/3/issue/$tick)
        stat=$(jq -r '.fields.status.name' <<< $blob)
        echo $tick: $stat
    done <<< $ticks
}

# UPDATES REGISTRY IN curr.txt WITH ACTIVE TICKETS
jira_pull() {
    token=$(read_token)
    uname=$(read_uname)
    ticks=$(read_ticks)
    encod=$(printf "%s" $uname | jq -s -R @uri)
    prnl updating local ticket registry
	blob=$(curl -s -u $uname:$token -X GET -H "Content-Type: application/json" "https://energysage.atlassian.net/rest/api/3/search?jql=assignee=$encod")
    keys=$(jq -r '.issues[] | select(.fields.status.name != "Done") | .key' <<< $blob)
    echo $keys > ~/BranchSage/curr.txt
}

#### TRIM ####
# REMOVES REMAINING BRANCHES FOR COMPLETED TICKETS
git_trim() {
    ticks=$(read_ticks)
    brans=$(git branch --format='%(refname:short)' | sed '/^[A-Z]\{1,\}-[0-9]\{4\}-.*$/!d')
    count=0
    if [[ $(git branch --show-current) != "develop" ]]; then
        if [ -z $(git status -s) ]; then
            prnl switching to develop
            git checkout develop
        else
            prnl stash or commit changes
            return
        fi
    fi
    while IFS= read -r bran; do
        key=$(echo $bran | awk -F'-' '{print $1 "-" $2}')
        if [[ $ticks != *"$key"* ]]; then
            git branch --delete $bran
            ((count++))
        fi
    done <<< $brans
    if [[ $count -gt 0 ]]; then
        prnl branches trimmed!
    else
        prnl no branches to trim
    fi
}

#### GROW ####
# CREATES BRANCHES FOR ACTIVE TICKETS WITHOUT THEM
git_grow () {
    ticks=$(read_ticks)
    brans=$(git branch --format='%(refname:short)' | sed '/^develop$/d')
    count=0
    if [[ $(git branch --show-current) != "develop" ]]; then
        if [ -z $(git status -s) ]; then
            prnl switching to develop
            git checkout develop
        else
            prnl stash or commit changes
            return
        fi
    fi
    if [[ -n $(git status -s) ]]; then
        prnl stash or commit changes
        return
    fi
    if [[ -n $(git status -uno | grep "Your branch is behind") ]]; then
        prnl run prep on develop
        return
    fi
    while IFS= read -r tick; do
        if [[ $brans != *"$tick"* ]]; then
            if [[ $(git branch --show-current) != "develop" ]]; then
                git restore .
            fi
            name=$(jira_name $tick)
            prnl creating branch $name
            git checkout -b $name
            git push -u origin HEAD
            ((count++))
        fi
    done <<< $ticks
    if [[ $count -gt 0 ]]; then
        prnl branches grown!
    else
        prnl no branches to grow
    fi
}
jira_name() { # CREATES NAME FROM TICKET
    token=$(read_token)
    uname=$(read_uname)
    blob=$(curl -s -u $uname:$token -X GET -H "Content-Type: application/json" https://energysage.atlassian.net/rest/api/3/issue/$1)
    desc=$(jq -r '.fields.summary' <<< $blob)
	name=$(echo $desc | tr '[:upper:]' '[:lower:]')
	name=$(echo $name | tr ' ' '-')
    name=$(echo $name | tr -cd '[:alnum:]-')
    name=$(echo $name | sed 's/-$//')
	echo $name
}

#### SYNC ####
# PREPS DEVELOP FOR NEW BRANCH USING EGS PROCESS
git_sync() {
    awsid=$(read_awsid)
    if [[ $(git branch --show-current) != "develop" ]]; then
        if [ -z $(git status -s) ]; then
            prnl checking out develop
            git checkout develop
        else
            prnl stash or commit changes
            return
        fi
    fi
    if [[ -n $(git status -s) ]]; then
        prnl stash or commit changes
        return
    fi
    cd ~/Dev/es-project/es-site/es
    prnl pulling upstream
	git pull --ff-only
	if [ -z $(echo $AWS_PROFILE) ]; then
		prnl login to aws
		source ~/Dev/es-dev-utils/aws_login.sh $awsid
	fi
    prnl running make update
	make update
}

#### SWAP ####
# TAKES ISSUE IDX OR PRINTS PROMPT TO SWITCH BRANCH
git_swap() {
    if [[ -n $(git status -s) ]]; then
        prnl stash or commit changes
        return
    fi
	idx=$1
	if [ -z $idx ]; then
        git_opts
        opts=$(git branch --format='%(refname:short)' | sed '/^develop$/d')
        prsl "issue # >>>  "
        read idx
	fi
    if [[ $idx == '.' ]]; then
        line=develop
    else
        line=$(echo $opts | grep -E "$idx" | sed 's/^[[:blank:]]*//')
        if [ -z $line ]; then
            prnl branch not found
            return
        fi
    fi
    git checkout $line
}
git_opts() { # PRINTS BRANCH OPTS
    opts=$(git branch | sed -e '/^develop$/d' -e '/^\* develop$/d')
    prnl available branches:
	echo $opts
}

#### ROLL ####
# TAKES FILE IDX OR PRINTS PROMPT TO RESTORE FILE
git_rest() {
    if [ -z "$(git status -s)" ]; then
        return
    fi
    git_diff
    prsl "file # >>>  "
    read idx
    if [[ $idx == '.' ]]; then
        line=.
        name=all
    else
        opts=$(git status -s | sed 's/^[^[:space:]]*[[:space:]]*[^[:space:]]*[[:space:]]*//')
        line=$(echo $opts | sed "$idx q;d")
        name=$(echo $line | sed 's|.*/||')
    fi
    prnl restoring $name
    git restore $line
}
git_diff() { # PRINTS CHANGED FILES, INDEXED
    opts=$(git status -s | sed 's/^[^[:space:]]*[[:space:]]*[^[:space:]]*[[:space:]]*//')
    if [[ -n $opts ]]
    then
        opts=$(echo $opts | nl -w1 -s": " -)
        prnl changed files:
        echo $opts
    fi
}

#### PREP ####
# SETS UP DIRECTORY, VENV, AND AWS
prep() {
    awsid=$(read_awsid)
    prnl opening directory
	cd ~/Dev/es-project/es-site/es
	prnl starting virtual env
	source ~/Dev/es-project/venv/bin/activate
	if [ -z $(echo $AWS_PROFILE) ]; then
		prnl login to aws
		source ~/Dev/es-dev-utils/aws_login.sh $awsid
	fi
}

#### LOGO ####
# PRINTS ASCII ART OF THE ENERGYSAGE LOGO
logo() {
    echo
    prnl '****************************************'
    prnl '*****************=.  .=*****************'
    prnl '***************-   ::   -+**************'
    prnl '*************-   :+**+:   -+************'
    prnl '***********=   :+******+:   =***********'
    prnl '*********=.  :+*****:****+:  .=*********'
    prnl '*******+:  .+******:  *****+.  :+*******'
    prnl '******+.  -*******- = -******-   =******'
    prnl '*****=  .+*******= -= =*******+.  =*****'
    prnl '****=  .+*******+ :*= +********+.  =****'
    prnl '***+   +*******= -**=::: :******+.  +***'
    prnl '***-  -*******+ :=****=: +*******-  -***'
    prnl '***-  -*******: :::=**- =********=  -***'
    prnl '***+  .**********+ =*: +*********:  +***'
    prnl '****:  =*********= =- =*********=  .****'
    prnl '****+.  =********- = -*********=   +****'
    prnl '*****+:  :+*******  :********+:  .+*****'
    prnl '*******=   :=******:*******=:   -*******'
    prnl '*********=.   .:-=++++=-:.   .-*********'
    prnl '***********+=:.          .:=+***********'
    prnl '****************++-  -++****************'
    prnl '******************=  -******************'
    prnl '******************+  =******************'
    prnl '****************************************'
    echo
}

#### INIT ####
# LOGS RELEVANT DATA TO auth.txt
init() {
    > ~/BranchSage/auth.txt
    prsl "Jira Email >>>  "
    read email
    echo $email >> ~/BranchSage/auth.txt
    prsl "Jira API Token >>>  "
    read token
    echo $token >> ~/BranchSage/auth.txt
    prsl "AWS Login Preference (optional) >>>  "
    read awsid
    echo $awsid >> ~/BranchSage/auth.txt
}

# BASIC FUNCTIONS
read_token() { echo $(cat ~/BranchSage/auth.txt | sed -n '1p'); }
read_uname() { echo $(cat ~/BranchSage/auth.txt | sed -n '2p'); }
read_awsid() { echo $(cat ~/BranchSage/auth.txt | sed -n '3p'); }
read_ticks() { cat ~/BranchSage/curr.txt; }
prnl() { echo $fg[$txtcolor]$@$reset_color; }
prsl() { echo -n $fg[$txtcolor]$@$reset_color; }

#### HELP ####
help() {
    prnl the following commands are available to use
    prnl to run them, type egs followed by the word in brackets
    echo
    echo '[prep]: nagivates to the appropriate directory, then activates the virtual'
    echo 'environment and runs the aws login script, if not already logged in.'
    echo 
    echo '[show]: prints out the numbers of all of your active tickets, followed by'
    echo 'the ticket status for each one.'
    echo
    echo '[trim]: searches through branches and deletes any that correspond to tickets'
    echo 'that have been marked as Done in Jira.'
    echo
    echo '[grow]: searches through all active of your active Jira tickets, and creates'
    echo 'new branches for any that dont yet have local branches.'
    echo
    echo '[swap]: now that your branch names are long, this takes a parameter, or if'
    echo 'not given one, prints a prompt, and then uses the 4 number code for the ticket'
    echo "to checkout the corresponding branch. '.' will checkout the develop branch."
    echo
    echo '[roll]: a shortcut for restoring changed files that you dont want changed: if'
    echo 'no parameter is given, it will print a prompt with the changed files indexed,'
    echo "then uses your input to restore that file. '.' will restore everything."
    echo
    echo '[sync]: pulls from the remote repository and runs make update on the develop'
    echo 'branch, which prepares it for new branches. run this before running [grow].'
    echo
    prnl enjoy, and try '[logo]' for a fun surprise!
}