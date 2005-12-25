use warnings;
use strict;

package Jifty::Test;
use base qw/Test::More/;

use Jifty::Everything;
use Jifty::Server;
use Jifty::Script::Schema;
use Email::LocalDelivery;
use Email::Folder;
use Hook::LexWrap;

=head2 import_extra

Called by L<Test::More>'s C<import> code when L<Jifty::Test> is first
C<use>'d, it calls L</setup>, and asks Test::More to export its
symbols to the namespace that C<use>'d this one.

=cut

sub import_extra {
    my $class = shift;
    $class->setup;
    Test::More->export_to_level(2);
}

=head2 setup

Merges the L</test_config> into the default configuration, resets the
database, and resets the fake "outgoing mail" folder.  This is the
method to override if you wish to do custom setup work.

=cut

sub setup {
    my $class = shift;

    $Jifty::Config::postload = sub {
        my $self = shift;
        $self->stash(Hash::Merge::merge($self->stash, $class->test_config($self)));
    };

    Jifty->new( no_handle => 1 );

    my $schema = Jifty::Script::Schema->new;
    $schema->{drop_database} =
      $schema->{create_database} =
        $schema->{create_all_tables} = 1;
    $schema->run;

    Jifty->new();
    $class->setup_mailbox;
}

=head2 test_config

Returns a hash which overrides parts of the application's
configuration for testing.  By default, this changes the database name
by appending a 'test', as well as setting the port to a random port
between 10000 and 15000.

It is passed the current configuration.

=cut

sub test_config {
    my $class = shift;
    my ($config) = @_;

    return {
        framework => {
            Database => {
                Database => $config->framework('Database')->{Database} . "test",
            },
            Web => {
                Port => int(rand(5000) + 10000),
            },
            Mailer => 'Jifty::Test',
            MailerArgs => [],
        }
    };
}

=head2 make_server

Creates a new L<Jifty::Server> which C<ISA>
L<Test::HTTP::Server::Simple> and returns it.

=cut

sub make_server {
    my $class = shift;

    require Test::HTTP::Server::Simple;
    unshift @Jifty::Server::ISA, 'Test::HTTP::Server::Simple';

    my $server = Jifty::Server->new;

    return $server;
} 

=head2 mailbox

A mailbox used for testing mail sending.

=cut

sub mailbox {
    return Jifty::Util->absolute_path("t/mailbox");
}

=head2 setup_mailbox

Clears the mailbox.

=cut

sub setup_mailbox {
    open my $f, ">", mailbox();
    close $f;
} 

=head2 is_available

Informs L<Email::Send> that L<Jifty::Test> is always available as a mailer.

=cut

sub is_available { 1 }

=head2 send

Should not be called manually, but is
automatically called by L<Email::Send> when using L<Jifty::Test> as a mailer.

(Note that it is a class method.)

=cut

sub send {
    my $class = shift;
    my $message = shift;

    Email::LocalDelivery->deliver($message->as_string, mailbox());
}

=head2 messages

Returns the messages in the test mailbox, as a list of L<Email::Simple> objects.

=cut

sub messages {
    return Email::Folder->new(mailbox())->messages;
} 

END {
    unlink mailbox();
}

1;
