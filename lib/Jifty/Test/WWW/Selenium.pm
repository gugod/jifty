package Jifty::Test::WWW::Selenium;
use strict;
use warnings;

use base 'Test::WWW::Selenium';

=head1 NAME

Jifty::Test::WWW::Selenium - Subclass of L<Test::WWW::Selenium> with
extra Jifty integration

=head1 SYNOPSIS

  use Jifty::Test::WWW::Selenium;
  my $server  = Jifty::Test->make_server;
  my $sel = Jifty::Test::WWW::Selenium->rc_ok( $server, lang => 'en_US.UTF-8' );
  my $URL = $server->started_ok;

  $sel->open_ok('/');

=head1 DESCRIPTION

L<Jifty::Test::WWW::Selenium> creates a L<Test::WWW::Selenium> object
associated with your jifty application to test.  In addition, it
starts selenium remote control for you, unless SELENIUM_RC_SERVER is
specified when the test is run.

=head2 rc_ok

When the selenium rc server is started by
L<Jifty::Test::WWW::Selenium>, the browser's language is default to
en_US, unless you pass C<lang> param to rc_ok.

=cut

sub rc_ok {
    my $class = shift;
    my $server = shift;
    my %args = @_;

    if ( $args{selenium_rc} ||= $ENV{SELENIUM_RC_SERVER} ) {
	@args{'host','port'} = split /:/, $args{selenium_rc}, 2;
    }
    else {
	@args{'host','port'} = eval { $class->_start_src(%args) };
	if ($@) { # Schwern: i want skip_rest
	    my $why = "No selenium: $@";
	    my $Tester = Test::Builder->new;
	    $Tester->skip($why);

	    unless ($Tester->{No_Plan}) {
		for (my $ct = $Tester->{Curr_Test};
		     $ct < $Tester->{Expected_Tests};
		     $ct++) {
		    $Tester->skip($why); # skip rest of the test
		}
	    }
	    exit(0);
	}
    }

    $args{browser_url} ||= 'http://localhost:'.$server->port;

    $args{browser} ||= $class->_get_default_browser;

    $SIG{CHLD} = \&_REAPER;

    my $try = 5;
    my $sel;
    while ($try--) {
	$sel = eval { Test::WWW::Selenium->new( %args, auto_stop => 0 ) };
	last if $sel;
	Test::More::diag "waiting for selenium rc...";
	sleep 3;
    }
    Test::More::isa_ok($sel, 'Test::WWW::Selenium');
    return $sel;
}

sub _REAPER {
    my $waitedpid = wait;
    # loathe sysV: it makes us not only reinstate
    # the handler, but place it after the wait
    $SIG{CHLD} = \&_REAPER;
}

sub _get_default_browser {
    my $class = shift;

    return '*firefox';
}

my @cleanup;

sub _start_src {
    my ($self, %args) = @_;
    eval 'require Alien::SeleniumRC; 1'
	or die 'requires Alien::SeleniumRC to start selenium-rc.';

    my $pid = fork();
    die if $pid == -1;
    if ($pid) {
	push @cleanup, $pid;
	return ('localhost', 4444);
    }
    else {
	require POSIX;
	POSIX::setsid();
	unless ($ENV{TEST_VERBOSE}) {
	    close *STDERR;
	    close *STDOUT;
	}
	$ENV{LANG} = $args{lang} || 'en_US.UTF-8';
	$ENV{PATH} = "$ENV{PATH}:/usr/lib/firefox";
	Test::More::diag "start selenium rc [$$]";
	local $SIG{CHLD} = \&_REAPER;
	local $SIG{TERM} = sub { exit 0 };
	Alien::SeleniumRC::start();
	Test::More::diag "selenium rc [$$] finished.";
	exit;
    }
}

END {
    kill(15, -$_) for @cleanup;
}


1;
