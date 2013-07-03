# = Definition: bind::zone
#
# Creates a valid Bind9 zone.
#
# Arguments:
#  *$is_slave*: Boolean. Is your zone a slave or a master? Default false
#  *$zone_ttl*: Time period. Time to live for your zonefile (master only)
#  *$zone_contact*: Valid contact record (master only)
#  *$zone_serial*: Integer. Zone serial (master only)
#  *$zone_refresh*: Time period. Time between each slave refresh (master only)
#  *$zone_retry*: Time period. Time between each slave retry (master only)
#  *$zone_expiracy*: Time period. Slave expiracy time (master only)
#  *$zone_ns*: Valid NS for this zone (master only)
#  *$zone_xfers*: IPs. Valid xfers for zone (master only)
#  *$zone_masters*: IPs. Valid master for this zone (slave only)
#  *$zone_origin*: The origin of the zone
#
define bind::zone (
  $ensure        = present,
  $is_dynamic    = false,
  $is_slave      = false,
  $allow_update  = [],
  $zone_ttl      = '',
  $zone_contact  = '',
  $zone_serial   = '%%SERIAL%%',
  $zone_refresh  = '3h',
  $zone_retry    = '1h',
  $zone_expiracy = '1w',
  $zone_ns       = '',
  $zone_xfers    = '',
  $zone_masters  = '',
  $zone_origin   = '',
) {

  validate_string($ensure)
  validate_re($ensure, ['present', 'absent'],
              "\$ensure must be either 'present' or 'absent', got '${ensure}'")

  validate_bool($is_dynamic)
  validate_bool($is_slave)
  validate_array($allow_update)
  validate_string($zone_ttl)
  validate_string($zone_contact)
  validate_string($zone_serial)
  validate_string($zone_refresh)
  validate_string($zone_retry)
  validate_string($zone_expiracy)
  validate_string($zone_ns)
  validate_string($zone_origin)

  if ($is_slave and $is_dynamic) {
    fail "Zone '${name}' cannot be slave AND dynamic!"
  }

  concat::fragment {"named.local.zone.${name}":
    ensure  => $ensure,
    target  => '/etc/bind/named.conf.local',
    content => "include \"/etc/bind/zones/${name}.conf\";\n",
    notify  => Exec['reload bind9'],
    require => Package['bind9'],
  }

  case $ensure {
    present: {
      concat {"/etc/bind/zones/${name}.conf":
        owner  => root,
        group  => root,
        mode   => '0644',
        notify => Exec['reload bind9'],
      }
      concat::fragment {"bind.zones.${name}":
        ensure  => $ensure,
        target  => "/etc/bind/zones/${name}.conf",
        notify  => Exec['reload bind9'],
        require => Package['bind9'],
      }

      if $is_slave {
        Concat::Fragment["bind.zones.${name}"] {
          content => template('bind/zone-slave.erb'),
        }
## END of slave
      } else {
        validate_re($zone_contact, '^\S+$', "Wrong contact value for ${name}!")
        validate_re($zone_ns, '^\S+$', "Wrong ns value for ${name}!")
        validate_re($zone_serial, '^\d+$', "Wrong serial value for ${name}!")
        validate_re($zone_ttl, '^\d+$', "Wrong ttl value for ${name}!")

        file { "/etc/bind/tmp":
          ensure => directory
        }

        $conf_file = $is_dynamic? {
          true    => "/etc/bind/tmp/dynamic_${name}.conf",
          default => "/etc/bind/tmp/pri_${name}.conf",
        }

        $conf_real_file = $is_dynamic? {
          true    => "/etc/bind/dynamic/${name}.conf",
          default => "/etc/bind/pri/${name}.conf",
        }

        $require = $is_dynamic? {
          true    => Bind::Key[$allow_update],
          default => undef,
        }

        concat {$conf_file:
          owner   => root,
          group   => bind,
          mode    => '0664',
          #notify  => Exec['reload bind9'],
	  notify  => Exec["Replace SERIAL ${conf_file}"],
          require => [File['/etc/bind/tmp'], Package['bind9']],
        }

        Concat::Fragment["bind.zones.${name}"] {
          content => template('bind/zone-master.erb'),
        }

        concat::fragment {"00.bind.${name}":
          ensure  => $ensure,
          target  => $conf_file,
          content => template('bind/zone-header.erb'),
          require => $require,
        }

        file { $conf_real_file:
          ensure => $ensure
        }

        file {"/etc/bind/pri/${name}.conf.d":
          ensure  => absent,
        }

        exec { "Replace SERIAL ${conf_file}":
          path        => '/bin:/sbin:/usr/sbin:/usr/bin',
          command     => "sed \"s/%%SERIAL%%/`date +%s`/g\" ${conf_file} > ${conf_real_file}",
          notify      => Exec['reload bind9'],
          refreshonly => true
        }
      }
    }
    absent: {
      file {"/etc/bind/pri/${name}.conf":
        ensure => absent,
      }
      file {"/etc/bind/zones/${name}.conf":
        ensure => absent,
      }
    }
    default: {}
  }
}
