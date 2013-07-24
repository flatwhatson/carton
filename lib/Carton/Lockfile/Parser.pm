package Carton::Lockfile::Parser;
use strict;
use Carton::Dist;
use Moo;

my $machine = {
    init => [
        {
            re => qr/^\# carton snapshot format: version ([\d\.]+)/,
            code => sub {
                my($stash, $lockfile, $ver) = @_;
                $lockfile->version($ver);
            },
            goto => 'section',
        },
        # TODO support pasing error and version mismatch etc.
    ],
    section => [
        {
            re => qr/^DISTRIBUTIONS$/,
            goto => 'dists',
        },
        {
            re => qr/^__EOF__$/,
            done => 1,
        },
    ],
    dists => [
        {
            re => qr/^  (\S+)$/,
            code => sub { $_[0]->{dist} = Carton::Dist->new(name => $1) },
            goto => 'distmeta',
        },
        {
            re => qr/^\S/,
            goto => 'section',
            redo => 1,
        },
    ],
    distmeta => [
        {
            re => qr/^    pathname: (.*)$/,
            code => sub { $_[0]->{dist}->pathname($1) },
        },
        {
            re => qr/^\s{4}provides:$/,
            code => sub { $_[0]->{property} = 'provides' },
            goto => 'properties',
        },
        {
            re => qr/^\s{4}requirements:$/,
            code => sub {
                $_[0]->{property} = 'requirements';
            },
            goto => 'properties',
        },
        {
            re => qr/^\s{0,2}\S/,
            code => sub {
                my($stash, $lockfile) = @_;
                $lockfile->add_distribution($stash->{dist});
                %$stash = (); # clear
            },
            goto => 'dists',
            redo => 1,
        },
    ],
    properties => [
        {
            re => qr/^\s{6}([0-9A-Za-z_:]+) (v?[0-9\._]+|undef)/,
            code => sub {
                my($stash, $lockfile, $module, $version) = @_;

                if ($stash->{property} eq 'provides') {
                    $stash->{dist}->provides->{$module} = { version => $version };
                } else {
                    $stash->{dist}->add_string_requirement($module, $version);
                }
            },
        },
        {
            re => qr/^\s{0,4}\S/,
            goto => 'distmeta',
            redo => 1,
        },
    ],
};

sub parse {
    my($self, $data, $lockfile) = @_;

    my @lines = split /\n/, $data;

    my $state = $machine->{init};
    my $stash = {};

    LINE:
    for my $line (@lines, '__EOF__') {
        last LINE unless @$state;

    STATE: {
            for my $trans (@{$state}) {
                if (my @match = $line =~ $trans->{re}) {
                    if (my $code = $trans->{code}) {
                        $code->($stash, $lockfile, @match);
                    }
                    if (my $goto = $trans->{goto}) {
                        $state = $machine->{$goto};
                        if ($trans->{redo}) {
                            redo STATE;
                        } else {
                            next LINE;
                        }
                    }

                    last STATE;
                }
            }

            die "SOMETHING IS WRONG $line";
        }

    }
}

1;
