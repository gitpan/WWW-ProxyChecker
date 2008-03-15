use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'WWW::ProxyChecker',
    license             => 'perl',
    dist_author         => 'Zoffix Znet <zoffix@cpan.org>',
    dist_version_from   => 'lib/WWW/ProxyChecker.pm',
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'Carp'                  => 1.04,
        'LWP::UserAgent'        => 2.036,
        'IO::Pipe'              => 1.13,
        'Class::Data::Accessor' => 0.04001,
    },
    add_to_cleanup      => [ 'WWW-ProxyChecker-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
