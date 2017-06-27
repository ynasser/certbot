BootstrapRpmCommon() {
  # Tested with:
  #   - Fedora 20, 21, 22, 23 (x64)
  #   - Centos 7 (x64: on DigitalOcean droplet)
  #   - CentOS 7 Minimal install in a Hyper-V VM
  #   - CentOS 6 (EPEL must be installed manually)

  if type dnf 2>/dev/null
  then
    tool=dnf
  elif type yum 2>/dev/null
  then
    tool=yum

  else
    echo "Neither yum nor dnf found. Aborting bootstrap!"
    exit 1
  fi

  if [ "$ASSUME_YES" = 1 ]; then
    yes_flag="-y"
  fi
  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG='--quiet'
  fi

  if ! $SUDO $tool list *virtualenv >/dev/null 2>&1; then
    echo "To use Certbot, packages from the EPEL repository need to be installed."
    if ! $SUDO $tool list epel-release >/dev/null 2>&1; then
      echo "Please enable this repository and try running Certbot again."
      exit 1
    fi
    if [ "$ASSUME_YES" = 1 ]; then
      /bin/echo -n "Enabling the EPEL repository in 3 seconds..."
      sleep 1s
      /bin/echo -ne "\e[0K\rEnabling the EPEL repository in 2 seconds..."
      sleep 1s
      /bin/echo -e "\e[0K\rEnabling the EPEL repository in 1 seconds..."
      sleep 1s
    fi
    if ! $SUDO $tool install $yes_flag $QUIET_FLAG epel-release; then
      echo "Could not enable EPEL. Aborting bootstrap!"
      exit 1
    fi
  fi

  pkgs="
    gcc
    augeas-libs
    openssl
    openssl-devel
    libffi-devel
    redhat-rpm-config
    ca-certificates
  "

  # Some distros and older versions of current distros use a "python27"
  # instead of "python" naming convention. Try both conventions.
  if $SUDO $tool list python >/dev/null 2>&1; then
    pkgs="$pkgs
      python
      python-devel
      python-virtualenv
      python-tools
      python-pip
    "
  else
    pkgs="$pkgs
      python27
      python27-devel
      python27-virtualenv
      python27-tools
      python27-pip
    "
  fi

  if $SUDO $tool list installed "httpd" >/dev/null 2>&1; then
    pkgs="$pkgs
      mod_ssl
    "
  fi

  if [ ! -z $configure_cron ]; then
    pkgs="$pkgs
      cronie
    "
  fi

  if ! $SUDO $tool install $yes_flag $QUIET_FLAG $pkgs; then
    echo "Could not install OS dependencies. Aborting bootstrap!"
    exit 1
  fi
}

ConfigureCronRpm(){
  if [ ! -z "$configure_cron" ]; then
    # when a normal user creates a crontab via `sudo`, it gets added to the root crontab
    root_crontab=/var/spool/cron/root

    if [ $SUDO -f "$root_crontab" ]; then
      # only grep if it exists
      cerbot_cron_exists=$($SUDO grep "certbot -q renew # generated by certbot" $root_crontab)
    fi

    if [ -z "$cerbot_cron_exists" ]; then
      random_wait=`awk -v max=3600 'BEGIN{srand(); print int(rand()*(max))}'`
      crontab_text="0 */12 * * * sleep random_wait ; certbot -q renew # generated by certbot\n"
      crontab_text=`echo "$crontab_text" | sed s/random_wait/$random_wait/g`
      tmp_cron_file=`mktemp`
      echo "$crontab_text" > $tmp_cron_file
      $SUDO crontab $tmp_cron_file
      rm $tmp_cron_file
      $SUDO service crond start
    else
      echo "Not adding a renewal cron job for certbot, as one already exists."
    fi
  fi
}
