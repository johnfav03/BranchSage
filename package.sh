#!/usr/bin/env zsh
autoload -U colors && colors
txtcolor=yellow


#### SHOW ####
# PRINTS ACTIVE TICKET KEYS AND THEIR STATUSES
jira_show() {
    1pass_load
    ticks=$(read_ticks)
    token=$JIRA_TOKEN
    uname=$JIRA_UNAME
    ghtok=$GITHUB_TOKEN
    currs=""
    while IFS= read -r tick; do 
        prsl $tick': '
        blob=$(curl -s -u $uname:$token -X GET -H "Content-Type: application/json" https://energysage.atlassian.net/rest/api/3/issue/$tick)
        stat=$(jq -r '.fields.status.name' <<< $blob)
        if [[ $stat == "Awaiting Deployment" ]]; then
            opts=$(git branch --format='%(refname:short)' | sed '/^develop$/d')
            line=$(echo $opts | grep -E "$tick" | sed 's/^[[:blank:]]*//')
            if [[ -n $line ]]; then
                resp=$(curl -s -X GET -H "Authorization: token $ghtok" --url "https://api.github.com/repos/EnergySage/es-site/pulls?state=closed&per_page=100&head=EnergySage:$line")
                open=$(jq -r '.[].state' --jsonargs <<< $resp)
                if [[ -n $open ]]; then
                    stat='Merged'
                fi
            fi
        elif [[ $stat == "Code Review" ]]; then
            opts=$(git branch --format='%(refname:short)' | sed '/^develop$/d')
            line=$(echo $opts | grep -E "$tick" | sed 's/^[[:blank:]]*//')
            if [[ -n $line ]]; then
                resp=$(curl -s -X GET -H "Authorization: token $ghtok" --url "https://api.github.com/repos/EnergySage/es-site/pulls?state=open&per_page=100&head=EnergySage:$line")
                indx=$(jq -r '.[].number' --jsonargs <<< $resp)
                resp=$(curl -s -X GET -H "Authorization: token $ghtok" --url "https://api.github.com/repos/EnergySage/es-site/issues/$indx/comments")
                ncom=$(echo $resp | jq 'map(select(.user.login != "swarmia[bot]")) | length')
                resp=$(curl -s -X GET -H "Authorization: token $ghtok" --url "https://api.github.com/repos/EnergySage/es-site/pulls/$indx/reviews")
                nres=$(echo $resp | jq 'length')
                stat+=' ('$(($ncom + $nres))')'
            fi
        fi
        echo $stat
    done <<< $ticks
}


# UPDATES REGISTRY IN curr.txt WITH ACTIVE TICKETS
jira_pull() {
    1pass_load
    token=$JIRA_TOKEN
    uname=$JIRA_UNAME
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
        if [[ -z $(git status -s) ]]; then
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
    while IFS= read -r tick; do
        if [[ $brans != *"$tick"* ]]; then
            if [[ $(git branch --show-current) != "develop" ]]; then
                git restore .
            fi
            if [[ $count == 0 ]]; then
                git_sync
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
    1pass_load
    token=$JIRA_TOKEN
    uname=$JIRA_UNAME
    blob=$(curl -s -u $uname:$token -X GET -H "Content-Type: application/json" https://energysage.atlassian.net/rest/api/3/issue/$1)
    tags=$(jq -r '.key' <<< $blob)
    desc=$(jq -r '.fields.summary' <<< $blob)
	name=$(echo $desc | tr '[:upper:]' '[:lower:]')
	name=$(echo $name | tr ' ' '-')
    name=$(echo $name | tr -cd '[:alnum:]-')
    name=$(echo $name | sed 's/-$//')
    tags+='-'$name
	echo $tags
}


#### SYNC ####
# PREPS DEVELOP FOR NEW BRANCH USING EGS PROCESS
git_sync() {
    1pass_load
    awsid=$AWS_PREF
    if [[ -n $(git status -s) ]]; then
        prnl stash or commit changes
        return
    fi
    cd ~/Dev/es-project/es-site/es
    prnl pulling upstream
	git pull --ff-only
	if aws sts get-caller-identity 2>&1 | grep -q "Unable to locate"; then
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
        opts=$(git branch --format='%(refname:short)' | sed '/develop/d')
        prsl "issue # >>>  "
        read idx
        if [ -z $idx ]; then
            return
        fi
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
# PRINTS BRANCH OPTS
git_opts() { 
    opts=$(git branch | sed -e '/develop$/d')
    prnl available branches:
	echo $opts
}


# PRINTS CHANGED FILES, INDEXED
git_file() { 
    opts=$(git status -s | sed 's/^[^[:space:]]*[[:space:]]*[^[:space:]]*[[:space:]]*//')
    if [[ -n $opts ]]
    then
        opts=$(echo $opts | nl -w1 -s": " -)
        prnl changed files:
        echo $opts
    fi
}
#### REST ####
# TAKES FILE IDX OR PRINTS PROMPT TO RESTORE FILE
git_rest() {
    if [ -z "$(git status -s)" ]; then
        return
    fi
    git_file
    prsl "file # >>>  "
    read idx
    if [ -z $idx ]; then
        return
    fi
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
#### DIFF ####
# TODO
git_diff() {
    if [ -z "$(git status -s)" ]; then
        return
    fi
    git_file
    prsl "file # >>>  "
    read idx
    if [ -z $idx ]; then
        return
    fi
    opts=$(git status -s | sed 's/^[^[:space:]]*[[:space:]]*[^[:space:]]*[[:space:]]*//')
    line=$(echo $opts | sed "$idx q;d")
    name=$(echo $line | sed 's|.*/||')
    prnl opening $name
    git diff $line
}


# TODO
1pass_load() {
    if [[ -z $(echo $JIRA_UNAME) ]]; then
        prnl sign in to 1password
        export JIRA_UNAME=$(op item get 'BranchSage Credentials' --fields label=jirausername)
        export JIRA_TOKEN=$(op item get 'BranchSage Credentials' --fields label=jiratoken)
        export GITHUB_TOKEN=$(op item get 'BranchSage Credentials' --fields label=githubtoken)
        export AWS_PREF=$(op item get 'BranchSage Credentials' --fields label=awspref)
    fi
}


#### PREP ####
# SETS UP DIRECTORY, VENV, AND AWS
prep() {
    awsid=$AWS_PREF
    prnl opening directory
	cd ~/Dev/es-project/es-site/es
	prnl starting virtual env
	source ~/Dev/es-project/venv/bin/activate
	if aws sts get-caller-identity 2>&1 | grep -q "Unable to locate"; then
		prnl login to aws
		source ~/Dev/es-dev-utils/aws_login.sh $awsid
	fi
}
#### LOGO ####
# PRINTS ASCII ART OF THE ENERGYSAGE LOGO
logo() {
    prnl '****************************************'
    prnl '*****************=.  .=*****************'
    prnl '**************+-   ::   -+**************'
    prnl '************+-   :+**+:   -+************'
    prnl '***********=   :+******+:   =***********'
    prnl '*********=.  :+*****:****+:  .=*********'
    prnl '*******+:  .+******:  *****+.  :+*******'
    prnl '******+.  -*******- = -******-   =******'
    prnl '*****=  .+*******= -= =*******+.  =*****'
    prnl '****=  .+*******+ :*= +********+.  =****'
    prnl '***+   +*******= -**=::: :******+.  +***'
    prnl '***-  -*******+ :=****=: +*******-  -***'
    prnl '***-  =*******: :::=**- =********=  -***'
    prnl '***+  :**********+ =*: +*********:  +***'
    prnl '****.  =*********= =- =*********=  .****'
    prnl '****+   =********- = -*********=   +****'
    prnl '*****+.  :+*******  :********+:  .+*****'
    prnl '*******=   :=******:*******=:   =*******'
    prnl '*********=.   .:-=++++=-:.   .=*********'
    prnl '***********+=:.          .:=+***********'
    prnl '****************++-  -++****************'
    prnl '******************=  =******************'
    prnl '******************=  =******************'
    prnl '****************************************'
}
#### INIT ####
# LOGS RELEVANT DATA TO 1password
init() {
    if [[ -z $(op item get 'BranchSage Credentials' 2>/dev/null) ]]; then
        prnl creating new 1password item
        op item create --category apicredential --title 'BranchSage Credentials' --vault 'Private'
    fi
    prsl "Jira Email >>>  "
    read email
    if [[ -n $email ]]; then
        op item edit 'BranchSage Credentials' jirausername=$email > /dev/null
        export JIRA_USERNAME=$email
    fi
    prsl "Jira API Token >>>  "
    read token
    if [[ -n $token ]]; then
        op item edit 'BranchSage Credentials' jiratoken=$token > /dev/null
        export JIRA_TOKEN=$token
    fi
    prsl "Github API Token >>>  "
    read gttok
    if [[ -n $token ]]; then
        op item edit 'BranchSage Credentials' githubtoken=$gttok > /dev/null
        export GITHUB_TOKEN=$gttok
    fi
    prsl "AWS Login Preference (optional) >>>  "
    read awsid
    if [[ -n $awsid ]]; then
        op item edit 'BranchSage Credentials' awspref=$awsid > /dev/null
        export AWS_PREF=$awsid
    fi
    op item get 'BranchSage Credentials' | tail -n 4
}
#### HELP ####
help() {
    echo to use this tool, type egs followed by a command.
    echo you can find a full list here: https://github.com/johnfav03/BranchSage
    prnl try running 'egs logo' for a fun surprise!
}

# BASIC FUNCTIONS
read_ticks() { cat ~/BranchSage/curr.txt; }
prnl() { echo $fg[$txtcolor]$@$reset_color; }
prsl() { echo -n $fg[$txtcolor]$@$reset_color; }