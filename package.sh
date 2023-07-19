#!/bin/zsh

autoload -U colors && colors
txtcolor=yellow

#### SHOW ####
# PRINTS ACTIVE TICKET KEYS AND THEIR STATUSES
_jira_show() {
    if _1pass_load; then
        return
    fi
    ticks=$(_read_ticks)
    token=$JIRA_TOKEN
    uname=$JIRA_UNAME
    ghtok=$GITHUB_TOKEN
    while IFS= read -r tick; do
        stat=$(_print_tick $tick &)
        echo $stat
    done <<< $ticks
    wait
}
_print_tick() {
    tick=$1
    _prsl $tick': '
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
                if [ -z $indx ]; then
                    stat+=" (no PR)"
                else
                    resp=$(curl -s -X GET -H "Authorization: token $ghtok" --url "https://api.github.com/repos/EnergySage/es-site/issues/$indx/comments")
                    ncom=$(echo $resp | jq 'map(select(.user.login != "swarmia[bot]")) | length')
                    resp=$(curl -s -X GET -H "Authorization: token $ghtok" --url "https://api.github.com/repos/EnergySage/es-site/pulls/$indx/reviews")
                    nres=$(echo $resp | jq 'length')
                    stat+=' ('$(($ncom + $nres))')'
                fi
            fi
        fi
    echo $stat
}


# UPDATES REGISTRY IN curr.txt WITH ACTIVE TICKETS
_jira_pull() {
    if _1pass_load; then
        return
    fi
    token=$JIRA_TOKEN
    uname=$JIRA_UNAME
    encod=$(printf "%s" $uname | jq -s -R @uri)
    _prnl updating local ticket registry
	blob=$(curl -s -u $uname:$token -X GET -H "Content-Type: application/json" "https://energysage.atlassian.net/rest/api/3/search?jql=assignee=$encod")
    keys=$(jq -r '.issues[] | select(.fields.status.name != "Done") | .key' <<< $blob)
    echo $keys > ~/BranchSage/curr.txt
}
#### TRIM ####
# REMOVES REMAINING BRANCHES FOR COMPLETED TICKETS
_git_trim() {
    ticks=$(_read_ticks)
    brans=$(git branch --format='%(refname:short)' | sed '/^[A-Z]\{1,\}-[0-9]\{4\}-.*$/!d')
    count=0
    if [[ $(git branch --show-current) != "develop" ]]; then
        if [[ -z $(git status -s) ]]; then
            _prnl switching to develop
            git checkout develop
        else
            _prnl stash or commit changes
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
        _prnl branches trimmed!
    else
        _prnl no branches to trim
    fi
}
#### GROW ####
# CREATES BRANCHES FOR ACTIVE TICKETS WITHOUT THEM
_git_grow () {
    ticks=$(_read_ticks)
    brans=$(git branch --format='%(refname:short)' | sed '/^develop$/d')
    count=0
    if [[ $(git branch --show-current) != "develop" ]]; then
        if [ -z $(git status -s) ]; then
            _prnl switching to develop
            git checkout develop
        else
            _prnl stash or commit changes
            return
        fi
    fi
    if [[ -n $(git status -s) ]]; then
        _prnl stash or commit changes
        return
    fi
    while IFS= read -r tick; do
        if [[ $brans != *"$tick"* ]]; then
            if [[ $(git branch --show-current) != "develop" ]]; then
                git restore .
            fi
            if [[ $count == 0 ]]; then
                _git_sync
            fi
            name=$(_jira_name $tick)
            _prnl creating branch $name
            git checkout -b $name
            git push -u origin HEAD
            ((count++))
        fi
    done <<< $ticks
    if [[ $count -gt 0 ]]; then
        _prnl branches grown!
    else
        _prnl no branches to grow
    fi
}
_jira_name() { # CREATES NAME FROM TICKET
    if _1pass_load; then
        return
    fi
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
_git_sync() {
    if _1pass_load; then
        return
    fi
    awsid=$AWS_PREF
    if [[ -n $(git status -s) ]]; then
        _prnl stash or commit changes
        return
    fi
    cd ~/Dev/es-project/es-site/es
    _prnl pulling upstream
	git pull --ff-only
	if aws sts get-caller-identity 2>&1 | grep -q -e "Unable to locate\|Token has expired"; then
		_prnl login to aws
		source ~/Dev/es-dev-utils/aws_login.sh $awsid
	fi
    _prnl running make update
	make update
}


#### SWAP ####
# TAKES ISSUE IDX OR PRINTS PROMPT TO SWITCH BRANCH
_git_swap() {
    if [[ -n $(git status -s) ]]; then
        _prnl stash or commit changes
        return
    fi
	idx=$1
	if [ -z $idx ]; then
        _git_opts
        opts=$(git branch --format='%(refname:short)' | sed '/develop/d')
        _prsl "issue # >>>  "
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
            _prnl branch not found
            return
        fi
    fi
    git checkout $line
}
# PRINTS BRANCH OPTS
_git_opts() { 
    opts=$(git branch | sed -e '/develop$/d')
    _prnl available branches:
	echo $opts
}


# PRINTS CHANGED FILES, INDEXED
_git_file() { 
    opts=$(git status -s | sed 's/^[^[:space:]]*[[:space:]]*[^[:space:]]*[[:space:]]*//')
    if [[ -n $opts ]]
    then
        opts=$(echo $opts | nl -w1 -s": " -)
        _prnl changed files:
        echo $opts
    fi
}
#### REST ####
# TAKES FILE IDX OR PRINTS PROMPT TO RESTORE FILE
_git_rest() {
    if [ -z "$(git status -s)" ]; then
        return
    fi
    idx=$1
    if [ -z $idx ]; then
        _git_file
        _prsl "file # >>>  "
        read idx
        if [ -z $idx ]; then
            return
        fi
    fi
    if [[ $idx == '.' ]]; then
        line=.
        name=all
    else
        opts=$(git status -s | sed 's/^[^[:space:]]*[[:space:]]*[^[:space:]]*[[:space:]]*//')
        line=$(echo $opts | sed "$idx q;d")
        name=$(echo $line | sed 's|.*/||')
    fi
    _prnl restoring $name
    git restore $line
}
#### DIFF ####
# TODO
_git_diff() {
    if [ -z "$(git status -s)" ]; then
        return
    fi
    _git_file
    _prsl "file # >>>  "
    read idx
    if [ -z $idx ]; then
        return
    fi
    opts=$(git status -s | sed 's/^[^[:space:]]*[[:space:]]*[^[:space:]]*[[:space:]]*//')
    line=$(echo $opts | sed "$idx q;d")
    name=$(echo $line | sed 's|.*/||')
    _prnl opening $name
    git diff $line
}


# TODO
_1pass_load() {
    if [[ -z $(echo $JIRA_UNAME) ]]; then
        _prnl sign in to 1password
        export JIRA_UNAME=$(op item get 'BranchSage Credentials' --fields label=jirausername)
        if [[ -z $(echo $JIRA_UNAME) ]]; then
            return 0
        fi
        export JIRA_TOKEN=$(op item get 'BranchSage Credentials' --fields label=jiratoken)
        export GITHUB_TOKEN=$(op item get 'BranchSage Credentials' --fields label=githubtoken)
        export AWS_PREF=$(op item get 'BranchSage Credentials' --fields label=awspref)
    fi
    return 1
}


#### PREP ####
# SETS UP DIRECTORY, VENV, AND AWS
_egs_prep() {
    if _1pass_load; then
        return
    fi
    awsid=$AWS_PREF
    _prnl opening directory
	cd ~/Dev/es-project/es-site/es
	_prnl starting virtual env
	source ~/Dev/es-project/venv/bin/activate
	if aws sts get-caller-identity 2>&1 | grep -q "Unable to locate\|Token has expired"; then
		_prnl login to aws
		source ~/Dev/es-dev-utils/aws_login.sh $awsid
	fi
}
#### LOGO ####
# PRINTS ASCII ART OF THE ENERGYSAGE LOGO
_egs_logo() {
    _prnl '****************************************'
    _prnl '*****************=.  .=*****************'
    _prnl '**************+-   ::   -+**************'
    _prnl '************+-   :+**+:   -+************'
    _prnl '***********=   :+******+:   =***********'
    _prnl '*********=.  :+*****:****+:  .=*********'
    _prnl '*******+:  .+******:  *****+.  :+*******'
    _prnl '******+.  -*******- = -******-   =******'
    _prnl '*****=  .+*******= -= =*******+.  =*****'
    _prnl '****=  .+*******+ :*= +********+.  =****'
    _prnl '***+   +*******= -**=::: :******+.  +***'
    _prnl '***-  -*******+ :=****=: +*******-  -***'
    _prnl '***-  =*******: :::=**- =********=  -***'
    _prnl '***+  :**********+ =*: +*********:  +***'
    _prnl '****.  =*********= =- =*********=  .****'
    _prnl '****+   =********- = -*********=   +****'
    _prnl '*****+.  :+*******  :********+:  .+*****'
    _prnl '*******=   :=******:*******=:   =*******'
    _prnl '*********=.   .:-=++++=-:.   .=*********'
    _prnl '***********+=:.          .:=+***********'
    _prnl '****************++-  -++****************'
    _prnl '******************=  =******************'
    _prnl '******************=  =******************'
    _prnl '****************************************'
}
#### INIT ####
# LOGS RELEVANT DATA TO 1password
_egs_init() {
    if [[ -z $(op item get 'BranchSage Credentials' 2>/dev/null) ]]; then
        _prnl creating new 1password item
        op item create --category apicredential --title 'BranchSage Credentials' --vault 'Private'
    fi
    _prsl "Jira Email >>>  "
    read email
    if [[ -n $email ]]; then
        op item edit 'BranchSage Credentials' jirausername=$email > /dev/null
        export JIRA_UNAME=$email
    fi
    _prsl "Jira API Token >>>  "
    read token
    if [[ -n $token ]]; then
        op item edit 'BranchSage Credentials' jiratoken=$token > /dev/null
        export JIRA_TOKEN=$token
    fi
    _prsl "Github API Token >>>  "
    read gttok
    if [[ -n $gttok ]]; then
        op item edit 'BranchSage Credentials' githubtoken=$gttok > /dev/null
        export GITHUB_TOKEN=$gttok
    fi
    _prsl "AWS Login Preference (optional) >>>  "
    read awsid
    if [[ -n $awsid ]]; then
        op item edit 'BranchSage Credentials' awspref=$awsid > /dev/null
        export AWS_PREF=$awsid
    fi
    op item get 'BranchSage Credentials' | tail -n 4
}
#### HELP ####
_egs_help() {
    echo to use this tool, type egs followed by a command.
    echo you can find a full list here: https://github.com/johnfav03/BranchSage
    _prnl try running 'egs logo' for a fun surprise!
}

# BASIC FUNCTIONS
_read_ticks() { cat ~/BranchSage/curr.txt; }
_prnl() { echo $fg[$txtcolor]$@$reset_color; }
_prsl() { echo -n $fg[$txtcolor]$@$reset_color; }