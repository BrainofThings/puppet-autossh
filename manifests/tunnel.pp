# == Class: autossh::tunnel
#
# Defines an ssh tunnel resource.  This class is run on the node that
# 'initiates' the ssh tunnel and
#   * creates the 'autossh' configuration file
#   * creates a system 'init' script.
#   * starts/restarts the service as required.
#
# === Parameters
#
# $user:            The user account to use to run the ssh tunnel
# $tunnel_type:     The tunnel direction. (forward --> local port to
#                   remote port, backward = remote port --> local port)
# $port:            The local port to be used for the tunnel.
# $hostport:        The remote port to be used for the tunnel.
# $remote_ssh_host: The remote host to connect to.
# $remote_ssh_port: The remote ssh port to connect to.
# $monitor_port:    Used by autossh to test the state of connections
#                   via an echo.
# $enable:          Enable/Disable this service.
# $pubkey:          The public key to be used for this service.
#                   (installed on remote host via exported resource)
# $enable_host_ssh_config: enable host specific configs
# $ssh_reuse_established_connections  =  $enable_ssh_reuse: default enable
#                   reuse of already established ssh connections, if any.
#                   Requires openssh > 5.5.
# $ssh_enable_compression = enable/disable compression
# $ssh_ciphers      = set chiper path from lest to most expensive
# ssh_stricthostkeychecking = enable/disable strict host key checking
# $ssh_tcpkeepalives: enable/disable tcp keepalives
#
# === Variables
#
#
# === Examples
#
#  autossh::tunnel  { 'testtunnel':
#    user            => 'autossh',
#    tunnel_type     => 'backward',
#    port            => '25',
#    hostport        => '25',
#    remote_ssh_host => 'server1.foo.bar',
#    remort_ssh_port => '22',
#    monitor_port    => '0',
#    enable          => true,
#    pubkey          => 'ssh-dss IOUEOWDOQ...'
#  }
#
# === Authors
#
# Jason Ball <jason@ball.net>
# Aimon Bustardo -- forked from https://github.com/aimonb/puppet-autossh.git
#
# === Copyright
#
# Copyright 2014 Jason Ball.
#
define autossh::tunnel(
  $port,
  $hostport,
  $remote_ssh_host,
  $remote_ssh_user  = $autossh::params::remote_ssh_user,
  $bind             = $autossh::params::bind,
  $forward_host     = $autossh::params::forward_host,
  $user             = $autossh::params::user,
  $tunnel_type      = $autossh::params::tunnel_type,
  $remote_ssh_port  = $autossh::params::remote_ssh_port,
  $monitor_port     = $autossh::params::monitor_port,
  $enable           = $autossh::params::enable,
  $pubkey           = $autossh::params::pubkey,
  $enable_host_ssh_config = false,
  $ssh_reuse_established_connections =
    $autossh::params::ssh_reuse_established_connections,
  $ssh_enable_compression = $autossh::params::ssh_enable_compression,
  $ssh_ciphers            = $autossh::params::ssh_ciphers,
  $ssh_stricthostkeychecking = $autossh::params::ssh_stricthostkeychecking,
  $ssh_tcpkeepalives = $autossh::params::ssh_tcpkeepalives,
){
  $tun_name     = $title

  #
  # User sysV or systemd init depending on the OS
  #
  case $::osfamily {
    /RedHat/: {
      $tunnel_args  = $tunnel_type ? {
        'reverse' => "-M ${monitor_port} -f -N -R",
        'forward' => "-M ${monitor_port} -f -N -L"
      }
      case $::operatingsystemmajrelease {
        /5|6/: {
          file{"autossh-${tun_name}-init":
            ensure  => 'present',
            path    => "/etc/init.d/autossh-${tun_name}",
            mode    => '0750',
            owner   => 'root',
            group   => 'root',
            content => template('autossh/autossh.init.sysv.erb'),
            notify  => Service["autossh-${tun_name}"],
          }
        } # case rhel 5|6

        /7/: {
          file{"systemd-service-${tun_name}":
            ensure  => 'present',
            path    => "/etc/systemd/system/autossh-${tun_name}.service",
            mode    => '0750',
            owner   => 'root',
            group   => 'root',
            content => template('autossh/autossh.service.erb'),
            notify  => Service["autossh-${tun_name}"],
          }
        }

        default: {
        }
      }
    } # case Redhat
    /Debian/: {
      case $::operatingsystemmajrelease {
        /16.04/: {
          file{"systemd-service-${tun_name}":
            ensure  => 'present',
            path    => "/etc/systemd/system/autossh-${tun_name}.service",
            mode    => '0750',
            owner   => 'root',
            group   => 'root',
            content => template('autossh/autossh.service.erb'),
            notify  => Service["autossh-${tun_name}"],
          }
        }
        default: {
        }
      }
    }  

    /Debian/: {
      $tunnel_args  = $tunnel_type ? {
        'reverse' => "-M ${monitor_port} -N -R",
        'forward' => "-M ${monitor_port} -N -L"
      }
      file{ "autossh-${tun_name}-upstart":
        ensure  => 'present',
        path    => "/etc/init/autossh-${tun_name}.conf",
        mode    => '0644',
        owner   => 'root',
        group   => 'root',
        content => template('autossh/autossh.init.upstart.erb'),
        notify  => Service["autossh-${tun_name}"],
      }
    }

    default: {
    } # default
  } # end case osfamily

  file{"autossh-${tun_name}_conf":
    ensure  => 'present',
    path    => "/etc/autossh/autossh-${tun_name}.conf",
    mode    => '0660',
    owner   => $user,
    group   => $user,
    content => template('autossh/autossh.conf.erb'),
    notify  => Service["autossh-${tun_name}"],
  }

  service{"autossh-${tun_name}":
    ensure  =>  $enable,
    enable  =>  $enable,
    require => Package['autossh']
  }

  $endpoint_port = $tunnel_type ? {
    'reverse' => $port,
    'forward' => $hostport
  }

  ## Define remote endpoints
  @@autossh::tunnel_endpoint {
    "tunnel-enpoint-${remote_ssh_host}-${port}":
    user         => $user,
    port         => $endpoint_port,
    monitor_port => $monitor_port,
    host         => $remote_ssh_host,
    pubkey       => $pubkey,
    enable       => $enable,
  }

  ##
  ## Host Settings -- only the first declaraion applies...
  ## as the filter is host specific, not host_port match...
  ##
  if $enable_host_ssh_config {
    if ! defined(Concat::Fragment["home_${user}_ssh_config_${remote_ssh_host}"])
    {
      concat::fragment { "home_${user}_ssh_config_${remote_ssh_host}":
        target  => "/home/${user}/.ssh/config",
        content => template('autossh/config.erb'),
        order   => 1,
      }
    }
  }
}
