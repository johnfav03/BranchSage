#!/usr/bin/env zsh

source ~/JiraHub/package.sh

if [[ $1 == 'work' ]]; then
    work $2
elif [[ $1 == 'show' ]]; then
    jira_show
elif [[ $1 == 'trim' ]]; then
    jira_updt
    git_trim
elif [[ $1 == 'grow' ]]; then
    jira_updt
    git_grow
elif [[ $1 == 'prep' ]]; then
    git_prep $2
elif [[ $1 == 'swap' ]]; then
    git_swap $2
elif [[ $1 == 'rest' ]]; then
    git_rest $2
elif [[ $1 == 'logo' ]]; then
    logo
else
    help
fi

