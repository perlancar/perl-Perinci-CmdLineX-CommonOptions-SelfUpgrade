package Perinci::CmdLineX::CommonOptions::SelfUpgrade;

# DATE
# VERSION

use 5.010001;
use strict 'subs', 'vars';
use warnings;

# currently this is crude, we'll be more proper after Perinci::Script and plugin
# system is developed.

sub apply_to_object {
    my ($class, $cmd) = @_;

    my $copts = $cmd->common_opts;

    # XXX use hook to check if meta (or other copt) uses -U (or --self-upgrade).
    # avoid using -U if meta uses -U.

    $copts->{self_upgrade} = {
        getopt  => "self-upgrade|U",
        summary => "Update program to latest version from CPAN",
        usage   => "--self-upgrade (or -U)",
        handler => sub {
            my ($go, $val, $r) = @_;
            $r->{action} = 'self_upgrade';
            $r->{skip_parse_subcommand_argv} = 1;
        },
    };
}

package # hide from PAUSE
    Perinci::CmdLine::Base;

sub action_self_upgrade {
    require File::Which;
    require HTTP::Tiny;
    require JSON::MaybeXS;

    my ($self, $r) = @_;

    unless (File::Which::which("cpanm")) {
        return [412, "Cannot upgrade: 'cpanm' program not available"];
    }

    my $url = $self->url;
    unless ($url =~ m!\A(?:pl:|riap://perl)?/(.+)/[^/]*\z!) {
        return [412, "Cannot upgrade: Unsupported Riap URL $url"];
    }

    (my $package = $1) =~ s!/!::!g;
    (my $package_pm = "$package.pm") =~ s!::!/!g;
    eval { require $package_pm };
    if ($@) {
        return [500, "Cannot upgrade: $@"];
    }
    my $local_version = ${"$package\::VERSION"};

    my $apiurl = "http://fastapi.metacpan.org/v1/module/$package?fields=version";
    my $apires = HTTP::Tiny->new->get($apiurl);
    unless ($apires->{success}) {
        return [500, "Cannot upgrade: Can't check latest version from $apiurl: $apires->{status} - $apires->{reason}"];
    }

    eval { $apires = JSON::MaybeXS::decode_json($apires->{content}) };
    if ($@) {
        return [500, "Cannot upgrade: Invalid API response from $apiurl: not valid JSON: $@"];
    }

    my $version_on_cpan;
    if ($apires->{message}) {
        if ($apires->{code} == 404) {
            return [412, "Cannot upgrade: Module $package is not on CPAN"];
        }
    }
    $version_on_cpan = $apires->{version};
    unless (defined $version_on_cpan) {
        return [412, "Cannot upgrade: Module $package's latest version on CPAN is undefined"];
    }

    if (defined $local_version &&
            version->parse($local_version) >= version->parse($version_on_cpan)) {
        return [304, "Local version ($local_version) already newest".
                    ($local_version ne $version_on_cpan ? " ($version_on_cpan)" : "")];
    }

    say "Updating to version $version_on_cpan ...";
    system "cpanm", "-n", $package;

    my $exit_code = $? < 0 ? $? : $? >> 8;

    if ($exit_code) {
        [500, "Cannot upgrade: cpanm failed (exit code $exit_code)"];
    } else {
        [200, "OK"];
    }
}

1;
# ABSTRACT: Add --self-upgrade (-U) common option to upgrade program to the latest version on CPAN

=for Pod::Coverage ^(.+)$

=head1 SYNOPSIS

 use Perinci::CmdLine::Lite; # or ::Classic, or ::Any
 use Perinci::CmdLineX::CommonOptions::SelfUpgrade;

 my $cmd = Perinci::CmdLine::Lite->new(...);
 Perinci::CmdLineX::CommonOptions::SelfUpgrade->apply_to_object($cmd);

 $cmd->run;


=cut
