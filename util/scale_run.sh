#!/bin/bash

# Run scale tests for each Standard Ref Arch size on docs page
#   Ref: https://puppet.com/docs/pe/latest/hardware_requirements.html

##########
# Variables
##########

WORK_DIR="$HOME/gatling"

##########
# Function Definitions
##########

# Display usage help
usage () {
    echo "Usage: $0 [OPTION]... PE_VERSION"
    echo
    echo "Run scale testing on specified PE_VERSION."
    echo "  PE_VERSION in semver notation (e.g 2019.1.0)"
    echo
    echo "Mandatory arguments to long options are mandatory for short options too."
    echo "  -h|--help             show this help text"
    echo "  -d|--debug            debug mode: prints ENV values and commands to be executed, but does not run anything"
    echo
}

# Debug function to validate that bash subshells inherit
# expected environment variables.
function echo_env () {
    echo "============================================
In subshell for $test $run_type round $i
cmd=$cmd
BEAKER_INSTALL_TYPE=$BEAKER_INSTALL_TYPE
BEAKER_PE_DIR=$BEAKER_PE_DIR
BEAKER_PE_VER=$BEAKER_PE_VER
PUPPET_GATLING_SCALE_BASE_INSTANCES=$PUPPET_GATLING_SCALE_BASE_INSTANCES
PUPPET_GATLING_SCALE_ITERATIONS=$PUPPET_GATLING_SCALE_ITERATIONS
PUPPET_GATLING_SCALE_INCREMENT=$PUPPET_GATLING_SCALE_INCREMENT
PUPPET_GATLING_SCALE_SCENARIO=$PUPPET_GATLING_SCALE_SCENARIO
ABS_AWS_MOM_SIZE=$ABS_AWS_MOM_SIZE
============================================"
}

# Prepare checkout of puppet-gatling-load-test
function prep_gplt () {
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR" || exit 1
    mkdir "$1"
    cd "$1" || exit 1
    git clone git@github.com:puppetlabs/gatling-puppet-load-test
    cd gatling-puppet-load-test || exit 1
    bundle install --path vendor/bundle
}


##########
# Argument checking
##########

ARGS=()
while [ $# -gt 0 ]
do
    case "$1" in
        -h|--help)  usage
            exit 1
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        --) # end argument parsing
            shift
            break
            ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            exit 1
            ;;
        *) # preserve positional arguments
            ARGS+=("$1")
            shift
            ;;
        esac
done

# Ensure PE_VERSION is provided
if [ "${#ARGS[@]}" -le "0" ]; then
    echo "PE_VERSION not provided"
    echo
    usage
    exit 1
fi
PE_VERSION=${ARGS[0]}

# Ensure PE_VERSION is semver
# e.g. 2019.1.1-rc0-207-g4e47830
# Regex from: https://regexr.com/39s32
RE='[^0-9]*\([0-9]*\)[.]\([0-9]*\)[.]\([0-9]*\)\([0-9A-Za-z-]*\)'
PE_MAJOR=$(echo "$PE_VERSION" | sed -e "s#$RE#\1#")
PE_MINOR=$(echo "$PE_VERSION" | sed -e "s#$RE#\2#")
PE_PATCH=$(echo "$PE_VERSION" | sed -e "s#$RE#\3#")
PE_BUILD=$(echo "$PE_VERSION" | sed -e "s#$RE#\4#")
echo "PE_MAJOR=$PE_MAJOR"
echo "PE_MINOR=$PE_MINOR"
echo "PE_PATCH=$PE_PATCH"
echo "PE_BUILD=$PE_BUILD"
#if ! [[ $PE_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+((-[0-9a-zA-Z-]+)*)?$ ]]; then
if ! { [ "$PE_MAJOR" ] && [ "$PE_MINOR" ] && [ "$PE_PATCH" ]; }; then
    echo "Supplied PE_VERSION ($PE_VERSION) is malformed"
    echo
    usage
    exit 1
fi

# Ensure packages can be found for PE_VERSION
if [ "$PE_BUILD" ]; then
  URL=http://enterprise.delivery.puppetlabs.net/$PE_MAJOR.$PE_MINOR/ci-ready/
else
  URL=http://enterprise.delivery.puppetlabs.net/archives/releases/$PE_VERSION/
fi
echo "$URL"
curl "$URL" | grep "puppet-enterprise-$PE_VERSION-el-7-x86_64.tar" || \
    { echo "Error: Unable to find packages for $PE_VERSION.  Double check that $PE_VERSION is available."; exit 1; }


##########
# Main
##########

tune=false
# Global settings
export BEAKER_INSTALL_TYPE=pe
export BEAKER_PE_DIR=http://enterprise.delivery.puppetlabs.net/archives/releases/2019.1.0
export BEAKER_PE_VER=$PE_VERSION
export PUPPET_GATLING_SCALE_TUNE=$tune
# export PUPPET_GATLING_SCALE_TUNE_FORCE=true



echo "========================================================================"
echo "Testing Ref Arch 1: Monolithic deploy for 10 or fewer nodes"

    export PUPPET_GATLING_SCALE_BASE_INSTANCES=100
    export PUPPET_GATLING_SCALE_ITERATIONS=1
    export PUPPET_GATLING_SCALE_SCENARIO="Scale.json"
    export ABS_AWS_MOM_SIZE="m5.large"

    run_type="cold"
    ec2=$ABS_AWS_MOM_SIZE
    test="slv-414-ref1-$ec2"
    cmd="bundle exec rake autoscale_$run_type > \"$test-$run_type.log\""
    if [ -z $DEBUG ]; then
        prep_gplt "$test"
        (bundle exec rake autoscale_$run_type > "$test-$run_type.log") &
    else
        (echo_env) &
    fi


echo "========================================================================"
echo "Testing Ref Arch 2: Monolithic deploy for up to 4,000 nodes"

    export PUPPET_GATLING_SCALE_ITERATIONS=15
    export PUPPET_GATLING_SCALE_INCREMENT=100
    export PUPPET_GATLING_SCALE_SCENARIO="Scale.json"

    run_type="cold"
    declare -a ec2_types=("c5.xlarge" "c5.2xlarge" "c5.4xlarge")
    for i in {0..4}; do
        wait
        [[ $i = 0 ]] && task="autoscale_$run_type" || task="autoscale_provisioned_$run_type"
        for ec2 in "${ec2_types[@]}"; do
            if [[ $ec2 == "c5.xlarge" ]]; then
                if [[ $tune == "false" ]]; then
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=2000
                else
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=2000
                fi
            elif [[ $ec2 == "c5.2xlarge" ]]; then
                if [[ $tune == "false" ]]; then
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=3800
                else
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=4100
                fi
            elif [[ $ec2 == "c5.4xlarge" ]]; then
                if [[ $tune == "false" ]]; then
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=4100
                else
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=3800
                fi
            else
                export PUPPET_GATLING_SCALE_BASE_INSTANCES=3800
            fi
            export ABS_AWS_MOM_SIZE="$ec2"
            test="slv-414-ref2-$ec2-tune-$tune"
            cmd="bundle exec rake $task > \"$test-$run_type-$i.log\""
            if [ -z $DEBUG ]; then
                prep_gplt "$test"
                (bundle exec rake $task > "$test-$run_type-$i.log") &
            else
                (echo_env) &
            fi
        done
    done

    wait
    run_type="warm"
    for i in {0..4}; do
        wait
        task=autoscale_provisioned_$run_type
        for ec2 in "${ec2_types[@]}"; do
            if [[ $ec2 == "c5.xlarge" ]]; then
                if [[ $tune == "false" ]]; then
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=1800
                else
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=1800
                fi
            elif [[ $ec2 == "c5.2xlarge" ]]; then
                if [[ $tune == "false" ]]; then
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=3800
                else
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=5000
                fi
            elif [[ $ec2 == "c5.4xlarge" ]]; then
                if [[ $tune == "false" ]]; then
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=4000
                else
                    export PUPPET_GATLING_SCALE_BASE_INSTANCES=6000
                fi
            else
                export PUPPET_GATLING_SCALE_BASE_INSTANCES=3800
            fi
            export ABS_AWS_MOM_SIZE="$ec2"
            test="slv-414-ref2-$ec2-tune-$tune"
            cmd="bundle exec rake $task > \"$test-$run_type-$i.log\""
            if [ -z $DEBUG ]; then
                cd "$WORK_DIR/$test/gatling-puppet-load-test" || exit 1
                (bundle exec rake $task > "$test-$run_type-$i.log") &
            else
                (echo_env) &
            fi
        done
    done

echo "========================================================================"
echo "NOT IN SCOPE: Ref Arch 3: Monolithic with Compiler deploy for up to 20,000 nodes"
echo "========================================================================"

# Create report from data
# for i in $(ls -d PERF_SCALE_*); do ; cat $i/PERF_SCALE_*.csv| sed 's/,/|/g' | sed 's/^/|/' | sed 's/$/|/' >> unified_results.txt ; done
