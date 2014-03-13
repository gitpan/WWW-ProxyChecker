package WWW::ProxyChecker;

use warnings;
use strict;

our $VERSION = '1.001001'; # VERSION

use Carp;
use LWP::UserAgent;
use IO::Pipe;
use base 'Class::Accessor::Grouped';
__PACKAGE__->mk_group_accessors(simple => qw/
    max_kids
    debug
    alive
    check_sites
    max_working_per_kid
    timeout
    agent
/);

sub new {
    my $self = bless {}, shift;
    croak "Must have even number of arguments to new()"
        if @_ & 1;

    my %args = @_;
    $args{ +lc } = delete $args{ $_ } for keys %args;

    %args = (
        timeout       => 5,
        max_kids      => 20,
        check_sites   => [ qw(
                http://google.com
                http://microsoft.com
                http://yahoo.com
                http://digg.com
                http://facebook.com
                http://myspace.com
            )
        ],
        agent   => 'Mozilla/5.0 (X11; U; Linux x86_64; en-US; rv:1.8.1.12)'
                    .' Gecko/20080207 Ubuntu/7.10 (gutsy) Firefox/2.0.0.12',

        %args,
    );

    $self->$_( $args{ $_ } ) for keys %args;

    return $self;
}

sub check {
    my ( $self, $proxies_ref ) = @_;

    $self->alive(undef);

    print "About to check " . @$proxies_ref . " proxies\n"
        if $self->debug;

    my $working_ref = $self->_start_checker( @$proxies_ref );

    print @$working_ref . ' out of ' . @$proxies_ref
            . " seem to be alive\n" if $self->debug;

    return $self->alive( $working_ref);
}

sub _start_checker {
    my ( $self, @proxies ) = @_;

    my $n = $self->max_kids;
    $n > @proxies and $n = @proxies;
    my $mod = @proxies / $n;
    my %prox;
    for ( 1 .. $n ) {
        $prox{ $_ } = [ splice @proxies, 0,$mod ]
    }
    push @{ $prox{ $n } }, @proxies; # append any left over addresses

    $SIG{CHLD} = 'IGNORE';
    my @children;
    for my $num ( 1 .. $self->max_kids ) {
        my $pipe = new IO::Pipe;

        if ( my $pid = fork ) { # parent
            $pipe->reader;
            push @children, $pipe;
        }
        elsif ( defined $pid ) { # kid
            $pipe->writer;

            my $ua = LWP::UserAgent->new(
                timeout => $self->timeout,
                agent   => $self->agent,
            );

            my $check_sites_ref = $self->check_sites;
            my $debug = $self->debug;
            my @working;
            for my $proxy ( @{ $prox{ $num } } ) {
                print "Checking $proxy in kid $num\n"
                    if $debug;

                if ( $self->_check_proxy($ua, $proxy, $check_sites_ref) ) {
                    push @working, $proxy;

                    last
                        if defined $self->max_working_per_kid
                            and @working >= $self->max_working_per_kid;
                }
            }
            print $pipe "$_\n" for @working;
            exit;
        }
        else { # error
            carp "Failed to fork kid number $num ($?)";
        }

    }

    my @working_proxies;
    for my $num ( 0 .. $#children ) {
        my $fh = $children[$num];
        while (<$fh>) {
            chomp;
            push @working_proxies, $_;
        }
    }

    return \@working_proxies;
}

sub _check_proxy {
    my ( $self, $ua, $proxy, $sites_ref ) = @_;

    $ua->proxy( [ 'http', 'https', 'ftp', 'ftps' ], $proxy);
    my $response = $ua->get( $sites_ref->[rand @$sites_ref] );
    if ( $response->is_success ) {
        return 1;
    }
    else {
        printf "Failed on $proxy (%s)\n", $response->status_line
            if $self->debug;

        my $response_code = $response->code;
        return 0
            if grep { $response_code eq $_ } qw(407 502 503 403);

        ( my $proxy_no_scheme = $proxy ) =~ s{(?:ht|f)tps?://}{}i;
        return $response->status_line
        =~ /^500 read timeout$|\Q$proxy_no_scheme/ ? 0 : 1;
    }
}

1;
__END__

=head1 NAME

WWW::ProxyChecker - check whether or not proxy servers are alive

=head1 SYNOPSIS

    use strict;
    use warnings;
    use WWW::ProxyChecker;

    my $checker = WWW::ProxyChecker->new( debug => 1 );

    my $working_ref= $checker->check( [ qw(
                http://221.139.50.83:80
                http://111.111.12.83:8080
                http://111.111.12.183:3218
                http://111.111.12.93:8080
            )
        ]
    );

    die "No working proxies were found\n"
        if not @$working_ref;

    print "$_ is alive\n"
        for @$working_ref;

=head1 DESCRIPTION

The module provides means to check whether or not HTTP proxies are alive.
The module was designed more towards "quickly scanning through to get a few"
than "guaranteed or your money back" therefore there is no 100% guarantee
that non-working proxies are actually dead and that all of the reported
working proxies are actually good.

=head1 CONSTRUCTOR

=head2 new

    my $checker = WWW::ProxyChecker->new;

    my $checker_juicy = WWW::ProxyChecker->new(
        timeout       => 5,
        max_kids      => 20,
        max_working_per_child => 2,
        check_sites   => [ qw(
                http://google.com
                http://microsoft.com
                http://yahoo.com
                http://digg.com
                http://facebook.com
                http://myspace.com
            )
        ],
        agent   => 'Mozilla/5.0 (X11; U; Linux x86_64; en-US; rv:1.8.1.12)'
                    .' Gecko/20080207 Ubuntu/7.10 (gutsy) Firefox/2.0.0.12',
        debug => 1,
    );

Bakes up and returns a new WWW::ProxyChecker object. Takes a few arguments
I<all of which are optional>. Possible arguments are as follows:

=head3 timeout

    ->new( timeout => 5 );

B<Optional>. Specifies timeout in seconds to give to L<LWP::UserAgent>
object which
is used for checking. If a connection to the proxy times out the proxy
is considered dead. The lower the value, the faster the check will be
done but also the more are the chances that you will throw away good
proxies. B<Defaults to:> C<5> seconds

=head3 agent

    ->new( agent => 'ProxeyCheckerz' );

B<Optional>. Specifies the User Agent string to use while checking proxies. B<By default> will be set to mimic Firefox.

=head3 check_sites

    ->new( check_sites => [ qw( http://some_site.com http://other.com ) ] );

B<Optional>. Takes an arrayref of sites to try to connect to through a
proxy. Yes! It's evil, saner ideas are more than welcome. B<Defaults to:>

    check_sites   => [ qw(
                http://google.com
                http://microsoft.com
                http://yahoo.com
                http://digg.com
                http://facebook.com
                http://myspace.com
            )
        ],

=head3 max_kids

    ->new( max_kids => 20 );

B<Optional>. Takes a positive integer as a value.
The module will fork up maximum of C<max_kids> processes to check proxies
simultaneously. It will fork less if the total number of proxies to check
is less than C<max_kids>. Technically, setting this to a higher value
might speed up the overall process but keep in mind that it's the number
of simultaneous connections that you will have open. B<Defaults to:> C<20>

=head3 max_working_per_child

    ->new( max_working_per_child => 2 );

B<Optional>. Takes a positive integer as a value. Specifies how many
working proxies each sub process should find before aborting (it will
also abort if proxy list is exhausted). In other words, setting C<20>
C<max_kids> and C<max_working_per_child> to C<2> will give you 40 working
proxies at most, no matter how many are in the original list. Specifying
C<undef> will get rid of limit and make each kid go over the entire sub
list it was given. B<Defaults to:> C<undef> (go over entire sub list)

=head3 debug

    ->new( debug => 1 );

B<Optional>. When set to a true value will make the module print out
some debugging information (which proxies failed and how, etc).
B<By default> not specifies (debug is off)

=head1 METHODS

=head2 check

    my $working_ref = $checker->check( [ qw(
                http://221.139.50.83:80
                http://111.111.12.83:8080
                http://111.111.12.183:3218
                http://111.111.12.93:8080
            )
        ]
    );

Instructs the object to check several proxies. Returns a (possibly empty)
array ref of addresses which the object considers to be alive and working.
Takes an arrayref of proxy addresses. The elements of this arrayref will
be passed to L<LWP::UserAgent>'s C<proxy()> method as:

    $ua->proxy( [ 'http', 'https', 'ftp', 'ftps' ], $proxy );

so you can read the docs for L<LWP::UserAgent> and maybe think up something
creative.

=head2 alive

    my $last_alive = $checker->alive;

Must be called after a call to C<check()>. Takes no arguments, returns
the same arrayref last C<check()> returned.

=head1 ACCESSORS/MUTATORS

The module provides an accessor/mutator for each of the arguments in
the constructor (new() method). Calling any of these with an argument
will set a new value. All of these return a currently set value:

    max_kids
    check_sites
    max_working_per_kid
    timeout
    agent
    debug

See C<CONSTRUCTOR> section for more information about these.

=head1 REPOSITORY

=for html  <div style="display: table; height: 91px; background: url(http://zoffix.com/CPAN/Dist-Zilla-Plugin-Pod-Spiffy/icons/section-github.png) no-repeat left; padding-left: 120px;" ><div style="display: table-cell; vertical-align: middle;">

Fork this module on GitHub:
L<https://github.com/zoffixznet/WWW-ProxyChecker>

=for html  </div></div>

=head1 BUGS

=for html  <div style="display: table; height: 91px; background: url(http://zoffix.com/CPAN/Dist-Zilla-Plugin-Pod-Spiffy/icons/section-bugs.png) no-repeat left; padding-left: 120px;" ><div style="display: table-cell; vertical-align: middle;">

To report bugs or request features, please use
L<https://github.com/zoffixznet/WWW-ProxyChecker/issues>

If you can't access GitHub, you can email your request
to C<bug-WWW-ProxyChecker at rt.cpan.org>

=for html  </div></div>

=head1 AUTHOR

=for html  <div style="display: table; height: 91px; background: url(http://zoffix.com/CPAN/Dist-Zilla-Plugin-Pod-Spiffy/icons/section-author.png) no-repeat left; padding-left: 120px;" ><div style="display: table-cell; vertical-align: middle;">

=for html   <span style="display: inline-block; text-align: center;"> <a href="http://metacpan.org/author/ZOFFIX"> <img src="http://www.gravatar.com/avatar/328e658ab6b08dfb5c106266a4a5d065?d=http%3A%2F%2Fwww.gravatar.com%2Favatar%2F627d83ef9879f31bdabf448e666a32d5" alt="ZOFFIX" style="display: block; margin: 0 3px 5px 0!important; border: 1px solid #666; border-radius: 3px; "> <span style="color: #333; font-weight: bold;">ZOFFIX</span> </a> </span>

=for text Zoffix Znet <zoffix at cpan.org>

=for html  </div></div>

=head1 LICENSE

You can use and distribute this module under the same terms as Perl itself.
See the C<LICENSE> file included in this distribution for complete
details.

=cut