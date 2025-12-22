package PVE::LXC::Setup::Slackware;

use strict;
use warnings;

use File::Path 'make_path';

use PVE::LXC::Setup::Base;
use PVE::LXC::Tools;

use base qw(PVE::LXC::Setup::Base);

sub new {
    my ($class, $conf, $rootdir, $os_release) = @_;

    my $version = $os_release->{VERSION_ID};

    die "Unsupported Slackware vesion $version\n" if $version < 15;

    my $self = { conf => $conf, rootdir => $rootdir, version => $version };

    $conf->{ostype} = "slackware";

    return bless $self, $class;
}

sub update_etc_hosts {
    my ($self, $hostip, $oldname, $newname, $searchdomains) = @_;

    my $hosts_fn = '/etc/hosts';
    return if $self->ct_is_file_ignored($hosts_fn);

    my $namepart = ($newname =~ s/\..*$//r);

    my $all_names = '';
    if ($newname =~ /\./) {
	$all_names .= "$newname $namepart";
    } else {
	foreach my $domain (PVE::Tools::split_list($searchdomains)) {
	    $all_names .= ' ' if $all_names;
	    $all_names .= "$newname.$domain";
	}
	$all_names .= ' ' if $all_names;
	$all_names .= $newname;
    }

    # Prepare section:
    my $section = '';

    my $lo4 = "127.0.0.1 localhost.localnet localhost\n";
    my $lo6 = "::1 localhost.localnet localhost\n";
    if ($self->ct_file_exists($hosts_fn)) {
	my $data = $self->ct_file_get_contents($hosts_fn);
	# don't take localhost entries within our hosts sections into account
	$data = $self->remove_pve_sections($data);

	# check for existing localhost entries
	$section .= $lo4 if $data !~ /^\h*127\.0\.0\.1\h+/m;
	$section .= $lo6 if $data !~ /^\h*::1\h+/m;
    } else {
	$section .= $lo4 . $lo6;
    }

    if (defined($hostip)) {
	$section .= "$hostip $all_names\n";
    } elsif ($namepart ne 'localhost') {
	$section .= "127.0.1.1 $all_names\n";
    } else {
	$section .= "127.0.1.1 $namepart\n";
    }

    $self->ct_modify_file($hosts_fn, $section);
}

sub set_dns_DISABLED {
    my ($self, $conf) = @_;

    my ($searchdomains, $nameserver) = $self->lookup_dns_conf($conf);
    print "DEBUG: set_dns(): ($searchdomains) | ($nameserver)\n";
    my $data = "";

    $data .= "search " . join(' ', PVE::Tools::split_list($searchdomains)) . "\n"
	if $searchdomains;

    foreach my $ns (PVE::Tools::split_list($nameserver)) {
	$data .= "nameserver $ns\n";
	print "DEBUG: set_dns(): nameserver $ns\n";
    }

    print "1)\n$data\n" if $self->ct_file_exists("/etc/resolv.conf");
    $self->ct_modify_file("/etc/resolv.conf", $data, replace => 1);

    if ($self->ct_file_exists("/etc/resolv.conf")) {
	my $resolvconf_content = $self->ct_file_get_contents("/etc/resolv.conf");
	print "DEBUG: [ $resolvconf_content ]\n";
    }
}

sub template_fixup {
    my ($self, $conf) = @_;
}

sub setup_network {
    my ($self, $conf) = @_;

    foreach my $k (keys %$conf) {
        next if $k !~ m/^net(\d+)$/;
        my $d = PVE::LXC::Config->parse_lxc_network($conf->{$k});
        next if !$d->{name};

        my $filename = "/etc/rc.d/rc.inet1.conf";
	
        if ($self->ct_file_exists($filename)) {
            my $data = $self->ct_file_get_contents($filename);
            # $data =~ s|^(exec /sbin/mingetty)(?!.*--nohangup) (.*)$|$1 --nohangup $2|gm;
	
	    if ($d->{ip} && $d->{ip} ne 'manual') {
		if ($d->{ip} eq 'auto') {
		    $data =~ s|^USE_SLAAC\[0\].*|USE_SLAAC\[0\]\=\"yes\"|m;
		    print "Setup IP Address with auto\n";
		} elsif ($d->{ip} eq 'dhcp') {
		    $data =~ s|^USE_DHCP\[0\].*|USE_DHCP\[0\]\=\"yes\"|m;
		    print "Setup IP Address using DHCP\n";
		} else {
		    my $usedhcp = 'USE_DHCP[0]="no"';
		    $data =~ s|^USE_DHCP\[0\]\=\"yes\"|USE_DHCP\[0\]=\"\"|m;
		    my $ipaddr = 'IPADDRS[0]="'.$d->{ip}."\"\n";
		    $data =~ s|^IPADDRS\[0\]\=\"\"|IPADDRS\[0\]=\"$d->{ip}\"|m;
		    print "Setup IP Address to ".$d->{ip}."\n";
		
		    if (defined($d->{gw})) {
			$data =~ s|^GATEWAY\=\"\"|GATEWAY\=\"$d->{gw}\"|m;
			print "Setup default gateway to ".$d->{gw}."\n";
		    }
		}
	    }
	
	    if ($d->{ip6} && $d->{ip6} ne 'manual') {
		if ($d->{ip6} eq 'auto') {
		    $data =~ s|^USE_SLAAC6\[0\].*|USE_SLAAC6\[0\]\=\"yes\"|m;
		    print "Setup IP6 Address with auto\n";
		} elsif ($d->{ip6} eq 'dhcp') {
		    $data =~ s|^USE_DHCP6\[0\].*|USE_DHCP6\[0\]\=\"yes\"|m;
		    print "Setup IP6 Address using DHCP\n";
		} else {
		    $data =~ s|^USE_DHCP6\[0\].*$|USE_DHCP6\[0\]\=\"\"|m;
		    $data =~ s|^IPADDRS6\[0\]\=\"\"$|IPADDRS6\[0\]\=\"$d->{ip6}\"|m;
		    print "Setup IP6 Address to ".$d->{ip6}."\n";

		    if (defined($d->{gw6})) {
			$data =~ s|^GATEWAY6\=\"\"|GATEWAY6\=\"$d->{gw6}\"|m;
			print "Setup default gateway to ".$d->{gw6}."\n";
		    }
		}
	    }
	    #print "DEBUG: \"$data\"\n";
            $self->ct_file_set_contents($filename, $data);
        } else {
	    my $data = "# /etc/rc.d/rc.inet1.conf\n#\n# This file contains the configuration settings for network interfaces.\n#\n\n";
	    $data   .= "# .\n";
	    $data   .= "# This file contains the configuration settings for network interfaces.\n";
	    $data   .= "#\n\n";
	    
	    if ($d->{ip} && $d->{ip} ne 'manual') {
		if ($d->{ip} eq 'auto') {
		    $data .= "USE_SLAAC[0]=\"yes\"\n";
		} elsif ($d->{ip} eq 'dhcp') {
		    $data .= "USE_DHCP[0]=\"yes\"\n";
		} else {
		    $data .= "IPADDRS[0]=\"$d->{ip}\"\n";
		    
		    if (defined($d->{gw})) {
			$data .= "GATEWAY=\"$d->{gw}\"\n";
		    }
		}
	    }
	    
	    if ($d->{ip6} && $d->{ip6} ne 'manual') {
		if ($d->{ip6} eq 'auto') {
		    $data .= "USE_SLAAC6[0]=\"yes\"\n";
		} elsif ($d->{ip6} eq 'dhcp') {
		    $data .= "USE_DHCP6[0]=\"yes\"\n";
		} else {
		    $data .= "IPADDRS6[0]=\"$d->{ip6}\"\n";
		    
		    if (defined($d->{gw6})) {
			$data .= "GATEWAY6=\"$d->{gw6}\"\n";
		    }
		}
	    }
	
            $self->ct_file_set_contents($filename, $data);
        }

    }

}

sub set_hostname {
    my ($self, $conf) = @_;

    # Redhat wants the fqdn in /etc/sysconfig/network's HOSTNAME
    my $hostname = $conf->{hostname} || 'localhost';

    my $hostname_fn = "/etc/hostname";
    my $system_hostname = "/etc/HOSTNAME";

    my $oldname;
    if ($self->ct_file_exists($hostname_fn)) {
	$oldname = $self->ct_file_read_firstline($hostname_fn) || 'localhost';
    } else {
	my $data = $self->ct_file_get_contents($system_hostname);
	if ($data =~ m/^LXC_NAME$/m) {
	    $oldname = $1;
	}
    }

    my ($ipv4, $ipv6) = PVE::LXC::get_primary_ips($conf);
    my $hostip = $ipv4 || $ipv6;

    my ($searchdomains) = $self->lookup_dns_conf($conf);

    $self->update_etc_hosts($hostip, $oldname, $hostname, $searchdomains);

    # Always write /etc/hostname, even if it does not exist yet
    $self->ct_file_set_contents($hostname_fn, "$hostname\n");

    if ($self->ct_file_exists($system_hostname)) {
	my $data = $self->ct_file_get_contents($system_hostname);
	if ($data !~ s|^LXC_NAME$|$hostname|m) {
	    $data = "$hostname\n";
	}
	$self->ct_file_set_contents($system_hostname, $data);
    }
}

sub set_timezone {
    my ($self, $conf) = @_;
}

sub setup_init {
    my ($self, $conf) = @_;
}


1;
