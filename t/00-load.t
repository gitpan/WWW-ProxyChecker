#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 7;

BEGIN {
    use_ok('Carp');
    use_ok('LWP::UserAgent');
    use_ok('IO::Pipe');
    use_ok('Class::Data::Accessor');
	use_ok( 'WWW::ProxyChecker' );
}

diag( "Testing WWW::ProxyChecker $WWW::ProxyChecker::VERSION, Perl $], $^X" );

my $o = WWW::ProxyChecker->new;
isa_ok($o,'WWW::ProxyChecker');
can_ok($o,qw(    max_kids
    debug
    alive
    check_sites
    max_working_per_kid
    timeout
    agent
    new
    check
    _start_checker
    _check_proxy));