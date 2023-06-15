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
    prnl fetching ticket status
    while IFS= read -r tick; do 
        blob=$(curl -s -u $uname:$token -X GET -H "Content-Type: application/json" https://energysage.atlassian.net/rest/api/3/issue/$tick)
        stat=$(jq -r '.fields.status.name' <<< $blob)
        echo $tick: $stat
    done <<< $ticks
}

#### UPDT #### // not an opt anymore
# UPDATES REGISTRY IN curr.txt WITH ACTIVE TICKETS
jira_updt() {
    token=$(read_token)
    uname=$(read_uname)
    ticks=$(read_ticks)
    encod=$(printf "%s" $uname | jq -s -R @uri)
    prnl updating local ticket registry
	blob=$(curl -s -u $uname:$token -X GET -H "Content-Type: application/json" "https://energysage.atlassian.net/rest/api/3/search?jql=assignee=$encod")
    keys=$(jq -r '.issues[] | select(.fields.status.name != "Done") | .key' <<< $blob)
    echo $keys > ~/JiraHub/curr.txt
}

#### TRIM ####
# REMOVES REMAINING BRANCHES FOR COMPLETED TICKETS
git_trim() {
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
    blob=$(curl -s -u $token:$uname -X GET -H "Content-Type: application/json" https://energysage.atlassian.net/rest/api/3/issue/$1)
	desc=$(jq -r '.fields.summary' <<< $blob)
	name=$(echo $desc | tr '[:upper:]' '[:lower:]')
	name=$(echo $name | tr ' ' '-')
    name=$(echo $name | tr -cd '[:alnum:]')
	echo $name
}

#### PREP ####
# PREPS DEVELOP FOR NEW BRANCH USING EGS PROCESS
git_prep() {
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
		source ~/Dev/es-dev-utils/aws_login.sh es-site-dev
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
    opts=$(git branch --format='%(refname:short)' | sed '/^develop$/d')
	idx=$1
	if [ -z $idx ]; then
        git_opts
        prsl "issue # >>>  "
        read idx
	fi
    if [[ $idx == '.' ]]; then
        line=develop
    else
        line=$(echo $opts | grep -E "$idx" | sed 's/^[[:blank:]]*//')
    fi
    git checkout $line
}
git_opts() { # PRINTS BRANCH OPTS
    opts=$(git branch | sed '/^develop$/d')
    prnl available branches:
	echo $opts
}

#### REST ####
# TAKES FILE IDX OR PRINTS PROMPT TO RESTORE FILE
git_rest() {
    idx=$1
    if [ -z $1 ]; then
        git_diff
        if [ -z "$(git status -s)" ]; then
            return
        fi
        prsl "file # >>>  "
        read idx
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
git_diff() { # PRINTS CHANGED FILES, INDEXED
    opts=$(git status -s | sed 's/^[^[:space:]]*[[:space:]]*[^[:space:]]*[[:space:]]*//')
    if [[ -n $opts ]]
    then
        opts=$(echo $opts | nl -w1 -s": " -)
        prnl changed files:
        echo $opts
    fi
}

logo() {

}

# BASIC FUNCTIONS
read_token() { echo $(cat ~/JiraHub/auth.txt | sed -n '1p'); }
read_uname() { echo $(cat ~/JiraHub/auth.txt | sed -n '2p'); }
read_ticks() { cat ~/JiraHub/curr.txt; }
prnl() { echo $fg[$txtcolor]$@$reset_color; }
prsl() { echo -n $fg[$txtcolor]$@$reset_color; }

#### HELP ####
help() {
    prnl these are the available commands:
    prnl
    prnl 
}