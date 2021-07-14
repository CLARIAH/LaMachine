#!/bin/bash

# THIS FILE IS MANAGED BY LAMACHINE, DO NOT EDIT IT! (it will be overwritten on update)

bold=$(tput bold)
boldred=${bold}$(tput setaf 1) #  red
boldgreen=${bold}$(tput setaf 2) #  green
boldblue=${bold}$(tput setaf 4) #  blue
normal=$(tput sgr0)

export LC_ALL=en_US.UTF_8
export ANSIBLE_FORCE_COLOR=true
echo "${bold}=====================================================================${normal}"
echo "           ,              ${bold}LaMachine v{{lamachine_version}}${normal} - ${boldblue}UPDATER${normal}"
echo "          ~)                     (http://proycon.github.io/LaMachine)"
echo "           (----/         "
echo "            /| |\         CLST, Radboud University Nijmegen &"
echo "           / / /|	        KNAW Humanities Cluster           (funded by CLARIAH)"
echo "${bold}=====================================================================${normal}"

if [ -e "{{lm_path}}" ]; then
  cd "{{lm_path}}"
else
  echo "The LaMachine control directory was not found.">&2
  echo "this generally means this lamachine installation is externally managed.">&2
  exit 2
fi
if ! touch .lastupdate; then
  echo "Insufficient permission to update">&2
  exit 2
fi
if [ -d .git ]; then
    git pull
else
    echo "${boldred}WARNING: Unable to update LaMachine controller, not a git repository! Proceeding anyway in 10s (CTRL-C to abort)...${normal}">&2
    sleep 10
fi
FIRST=1
INTERACTIVE=1
OPTS=""
i=0
for arg in "$@"; do
    i=$((i+1))
    if [ "$arg" = "--help" ] || [ "$arg" = "-h" ]; then
        echo "lamachine-update updates your LaMachine installation"
        echo "USAGE: lamachine-update [options] [variables]"
        echo "OPTIONS:"
        echo "--edit            Opens a text editor to edit the configuration and installation manifest prior to update."
        echo "--editonly        Opens a text editor to edit the configuration and installation manifest, does not update."
        echo "--noninteractive  Do not query to user to input at any point."
        echo "--only [package]  Update only the specified package (or comma seperated list of multiple) "
        echo "                  Note that this tries to leave most dependencies as-is (but no guarantees!)."
        echo "--debug           Extra debug"
        echo "VARIABLES:"
        echo "force=1        Force recompilation of all sources"
        echo "force=2        Delete all sources prior to update"
        exit 0
    fi
    if [ "$arg" = "--edit" ] || [ "$arg" = "--editonly" ]; then
        if [ -z "$EDITOR" ]; then
          export EDITOR=nano
        fi
        if [ -e "host_vars/{{hostname}}.yml" ]; then
            #LaMachine v2.1.0+
            $EDITOR "host_vars/{{hostname}}.yml"
            cp -f "host_vars/{{hostname}}.yml" "host_vars/localhost.yml"
        elif [ -e "host_vars/localhost.yml" ]; then
            #fallback
            $EDITOR "host_vars/localhost.yml"
        elif [ -e "host_vars/lamachine-$LM_NAME.yml" ]; then
            #LaMachine v2.0.0
            $EDITOR "host_vars/lamachine-$LM_NAME.yml"
        fi
        if [ -e "hosts.{{conf_name}}" ]; then
            #LaMachine v2.0.0
            $EDITOR "install-{{conf_name}}.yml"
        else
            #LaMachine v2.1.0+
            $EDITOR "install.yml"
        fi
        FIRST=$((i+1))
    elif [ "$arg" = "--noninteractive" ]; then
        INTERACTIVE=0
        FIRST=$((i+1))
    elif [ "$arg" = "--only" ]; then
        j=$((i+1))
        ONLY="${!j}"
        FIRST=$((i+2))
    fi
    if [ "$arg" = "--editonly" ]; then
        exit 0
    fi
    if [ "$arg" = "--debug" ]; then
        OPTS="$OPTS -v -v"
    fi
done
if [[ {{root|int}} -eq 1 ]] && [[ $INTERACTIVE -eq 1 ]]; then
 OPTS="$OPTS --ask-become-pass"
fi
D=$(date +%Y%m%d_%H%M%S)
if [ ! -z "$PYTHONPATH" ]; then
    OLDPYTHONPATH="$PYTHONPATH"
    export PYTHONPATH=""
fi
if [ -e "hosts.{{conf_name}}" ]; then
    #LaMachine v2.0.0
    ansible-playbook -i "hosts.{{conf_name}}" "install-{{conf_name}}.yml" -v $OPTS --extra-vars "ansible_python_interpreter='$(which python3)' ${*:$FIRST}" 2>&1 | tee "lamachine-{{conf_name}}-$D.log"
    rc=${PIPESTATUS[0]}
else
    #LaMachine v2.1.0+
    if [ -z "$ONLY" ]; then
        ansible-playbook -i "hosts.ini" "install.yml" -v $OPTS --extra-vars "ansible_python_interpreter=$(which python3) ${*:$FIRST}" 2>&1 | tee "lamachine-{{conf_name}}-$D.log"
        rc=${PIPESTATUS[0]}
    else
        echo "---" > "install.tmp.yml"
        grep "hosts:" install.yml >> "install.tmp.yml"
        echo "  roles: [ lamachine-core, $ONLY ]"  >> "install.tmp.yml"
        ansible-playbook -i "hosts.ini" "install.tmp.yml" -v $OPTS --skip-tags fullrunonly --extra-vars "ansible_python_interpreter='$(which python3)' ${*:$FIRST}" 2>&1 | tee "lamachine-{{conf_name}}-$D.log"
        rc=${PIPESTATUS[0]}
    fi
fi
#rerun all activation scripts
for f in $LM_PREFIX/bin/activate.d/*.sh; do
    if [ ! -z "$f" ]; then
        source $f
    fi
done
echo "======================================================================================"
if [ $rc -eq 0 ]; then
        echo "${boldgreen}The LaMachine update completed succesfully!${normal}"
        echo " - Log file: $(pwd)/lamachine-{{conf_name}}-$D.log"
else
        echo "${boldred}The LaMachine update failed!${normal} You have several options:"
        echo " - Retry a forced update (lamachine-update force=1), this forces recompilation even if software seems up to date"
        echo "   and may be necessary in certain circumstances. You can also try the even stronger option force=2, which deletes"
        echo "   all sources prior to update."
        echo " - Retry the update, possibly tweaking configuration and installation options (lamachine-update --edit)"
        echo " - If you got the error 'fragment_class is None', this was due to an ansible upgrade! Simply rerun the update!"
        echo " - File a bug report on https://github.com/proycon/LaMachine/issues/"
        echo "   The log file has been written to $(pwd)/lamachine-{{conf_name}}-$D.log (include it with any bug report)"
fi
if [ ! -z "$OLDPYTHONPATH" ]; then
    export PYTHONPATH="$OLDPYTHONPATH"
fi
exit $rc
