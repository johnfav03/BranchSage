#!/bin/zsh

source ~/BranchSage/package.sh

if [[ $1 == 'help' ]]; then
    _egs_help
elif [[ $1 == 'init' ]]; then
    _egs_init
elif [[ $1 == 'logo' ]]; then
    _egs_logo
elif [[ $1 == 'prep' ]]; then
    _egs_prep
elif [[ $1 == 'show' ]]; then
    _jira_show
elif [[ $1 == 'trim' ]]; then
    _jira_pull
    _git_trim
elif [[ $1 == 'grow' ]]; then
    _jira_pull
    _git_grow
elif [[ $1 == 'sync' ]]; then
    _git_sync
elif [[ $1 == 'swap' ]]; then
    _git_swap $2
elif [[ $1 == 'rest' ]]; then
    _git_rest $2
elif [[ $1 == 'diff' ]]; then
    _git_diff
elif [[ $1 == 'repo' ]]; then
    _egs_repo
else
    echo run help to see all commands
fi

return