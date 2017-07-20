#!/bin/bash -x

# $PUBLIC_IP $PRIVATE_IP $PUBLIC_HOSTNAME $BOULDER_URL are dynamically set at execution

# with curl, instance metadata available from EC2 metadata service:
#public_host=$(curl -s http://169.254.169.254/2014-11-05/meta-data/public-hostname)
#public_ip=$(curl -s http://169.254.169.254/2014-11-05/meta-data/public-ipv4)
#private_ip=$(curl -s http://169.254.169.254/2014-11-05/meta-data/local-ipv4)

cd letsencrypt
export PATH="$PWD/letsencrypt-auto-source:$PATH"
letsencrypt-auto --os-packages-only --debug --version
letsencrypt-auto certonly --no-self-upgrade -v --standalone --debug \
                   --text --agree-dev-preview --agree-tos \
                   --renew-by-default --redirect \
                   --register-unsafely-without-email \
                   --domain $PUBLIC_HOSTNAME --server $BOULDER_URL

# we have to jump through some hoops to cope with relative paths in renewal
# conf files ...
# 1. be in the right directory
cd tests/letstest/testdata/

# 2. refer to the config with the same level of relativity that it itself
# contains :/
OUT=`letsencrypt-auto certificates --config-dir sample-config -v --no-self-upgrade`
TEST_CERTS=`echo "$OUT" | grep TEST_CERT | wc -l`
REVOKED=`echo "$OUT" | grep REVOKED | wc -l`

if [ "$TEST_CERTS" != 2 ] ; then
    echo "Did not find two test certs as expected ($TEST_CERTS)"
    exit 1
fi

if [ "$REVOKED" != 1 ] ; then
    echo "Did not find one revoked cert as expected ($REVOKED)"
    exit 1
fi

###############################
## Tests for setting up cron ##
###############################

cd ../../../letsencrypt

common(){
    letsencrypt-auto --os-packages-only --debug --version
    letsencrypt-auto certonly --no-self-upgrade -v --standalone --debug \
                   --text --agree-dev-preview --agree-tos \
                   --renew-by-default --redirect \
                   --register-unsafely-without-email \
                   --domain $PUBLIC_HOSTNAME --server $BOULDER_URL \
                   --force-cron
}

cleanup(){
    letsencrypt-auto --delete --cert-name $PUBLIC_HOSTNAME
}

CronTests() {
    test_str="certbot -q renew # generated by certbot"

    # Test to add a crontab if there's no existing one.
    crontab -r # TODO: I hope these EC2 instances don't have cronjobs.
    common
    out=`crontab -l`
    if [ ! echo "$out" | grep "$test_str"]; then
        echo "crontab was not properly written"
        exit 1
    fi

    # Test for if there's an existing crontab, our stuff just gets appended, doesn't overwrite anything.
    crontab -r
    tmp_file=`mktemp`
    echo "* * * * * echo" > $tmp_file
    crontab $tmp_file
    common
    out=`crontab -l`
    if [ ! echo "$out" | grep "$test_str"]; then
        echo "crontab was not properly written"
        exit 1
    fi
    if [ wc -l "$tmp_file" != 2 ]; then
        echo "crontab was not properly written"
        exit 1
    fi

    # Test for no duplicate cronjobs being added
    crontab -r
    common
    common
    out=`"crontab -l"`
    count=`echo "$out" | wc -l `
    if [ $count != 1 ]; then
        echo "crontab was not properly written"
        exit 1
    fi
}

if [ -f /etc/debian_version ]; then
    CronTests
    # Test to not add anything if packaged certbot's crontab is detected.
    crontab -r
    cleanup
    if [ ! -d /etc/cron.d ]; then
        mkdir /etc/cron.d
    fi
    touch /etc/cron.d/certbot
    OUT=`common`
    TEST_COUNT=`echo "$OUT" | grep "or systemd timer already exists. Nothing to do."`
    if [ $TEST_COUNT = 0 ]; then
        echo "Something's wrong! Code to check if system is compatible with cron isn't being triggered."
        exit 1
    fi
elif [ -f /etc/redhat-release ]; then
    CronTests
elif [ -f /etc/os-release ] && `grep -q openSUSE /etc/os-release` ; then
    CronTests
else
    OUT=`common`
    TEST_COUNT=`echo "$OUT" | grep "Generating cron jobs for your system is not yet supported."`
    if [ $TEST_COUNT = 0 ]; then
        echo "Something's wrong! Code to check if system is compatible with cron isn't being triggered."
        exit 1
    fi
fi

