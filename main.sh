#!/usr/bin/env zsh

source ~/BranchSage/package.sh

if [[ $1 == 'help' ]]; then
    help
elif [[ $1 == 'init' ]]; then
    init
elif [[ $1 == 'logo' ]]; then
    logo
elif [[ $1 == 'prep' ]]; then
    prep
elif [[ $1 == 'show' ]]; then
    jira_show
elif [[ $1 == 'trim' ]]; then
    jira_pull
    git_trim
elif [[ $1 == 'grow' ]]; then
    jira_pull
    git_grow
elif [[ $1 == 'sync' ]]; then
    git_sync
elif [[ $1 == 'swap' ]]; then
    git_swap $2
elif [[ $1 == 'rest' ]]; then
    git_rest
elif [[ $1 == 'diff' ]]; then
    git_diff
else
    echo run help to see all commands
fi
