#!/bin/bash

cd letsencrypt
export PATH="$PWD/letsencrypt-auto-source:$PATH"

###############################
## Tests for setting up cron ##
###############################
CRONTAB_BACKUP="/opt/eff.org/certbot/crontab.bak"

letsencrypt-auto --os-packages-only --debug --version &> /dev/null

Common(){
    letsencrypt-auto --force-cron certonly --no-self-upgrade -v --standalone --debug \
                   --text --agree-dev-preview --agree-tos \
                   --renew-by-default --redirect \
                   --register-unsafely-without-email \
                   --domain "$PUBLIC_HOSTNAME" --server "$BOULDER_URL"
}

Cleanup() {
    letsencrypt-auto --delete --cert-name "$PUBLIC_HOSTNAME" --no-self-upgrade
}

CronTests() {
    test_str="certbot -q renew # generated by certbot"

    echo "Test to add a crontab if there's no existing one & that back-ups are properly written"
    sudo crontab -r
    if [ -e "$CRONTAB_BACKUP" ]; then
        sudo rm $CRONTAB_BACKUP
    fi
    Common
    out=$(sudo crontab -l)
    TEST_CRONTAB_WRITTEN=$(echo "$out" | grep "$test_str")
    if [ -z "$TEST_CRONTAB_WRITTEN" ]; then
        echo "crontab was not properly written" "$(sudo crontab -l)"
        exit 1
    fi

    echo "Test for if there's an existing crontab, our stuff just gets appended, doesn't overwrite anything."
    sudo crontab -r
    tmp_file=$(mktemp)
    echo "* * * * * echo" > "$tmp_file"
    sudo crontab "$tmp_file"
    out=$(sudo crontab -l)
    echo "crontab before: $out"
    Common
    out=$(sudo crontab -l)
    crontab_backup_out=$(sudo cat $CRONTAB_BACKUP)
    if [ -z "$crontab_backup_out" ]; then
        echo "crontab backup was not properly written"
        exit 1
    fi
    TEST_CRONTAB_WRITTEN=$(echo "$out" | grep "$test_str")
    if [ -z "$TEST_CRONTAB_WRITTEN" ]; then
        echo "appending new jobs to the existing crontab did not work"
        exit 1
    fi

    TEST_CRONTAB_LENGTH=$(echo "$out" | wc -l)
    if [ "$TEST_CRONTAB_LENGTH" != 2 ]; then
        echo "crontab was not properly written: # of line should be 2, is $TEST_CRONTAB_LENGTH"
        cat "$out"
        exit 1
     fi

    echo "Test for no duplicate cronjobs being added"
#    sudo crontab -r
#    Common
    Common
    out=$(sudo crontab -l)
    count=$(echo "$out" | wc -l)
    if [ "$count" != 2 ]; then
        echo "crontab was not properly written"
        exit 1
    fi
}

if [ -f "/etc/debian_version" ]; then
    CronTests
    # Test to not add anything if packaged certbot's crontab is detected.
    sudo crontab -r
    Cleanup
    if [ ! -d /etc/cron.d ]; then
        mkdir /etc/cron.d
    fi
    sudo touch /etc/cron.d/certbot
    OUT=$(Common)
    TEST_COUNT=$(echo "$OUT" | grep "or systemd timer already exists. Nothing to do.")
    echo "TEST_COUNT is $TEST_COUNT"
    if [ -z "$TEST_COUNT" ]; then
        echo "Something's wrong! Code to check if system is compatible with cron isn't being triggered."
        exit 1
    fi
    echo "Debian tests finished successfully :)"
elif [ -f /etc/redhat-release ]; then
    CronTests
    echo "Redhat tests finished successfully :)"
elif [ -f /etc/os-release ] && `grep -q openSUSE /etc/os-release` ; then
    CronTests
    echo "Opensuse tests finished successfully :)"
else
    OUT=$(Common)
    TEST_COUNT=$(echo "$OUT" | grep "Generating cron jobs for your system is not yet supported.")
    if [ "$TEST_COUNT" = 0 ]; then
        echo "Something's wrong! Code to check if system is compatible with cron isn't being triggered."
        exit 1
    fi
    echo "Non-compatability tests (mostly AWS) finished successfully :)
fi

