package Oserp::Backend;

=head1 NAME

Oserp::Backend

=head1 DESCRIPTION

Oserp backend for mail sending, mailbox parsing, message reading, etc.

=head1 TODO

This should be re-worked to support multiple backends.

=cut

use 5.00503;
use Carp;
use strict;
use Mail::Box;

use vars qw($VERSION);

$VERSION = sprintf "%d.%03d", q$Revision: 1.2 $ =~ /(\d+)/g;

# TODO: we're just inheriting everything for now, redesign as we go.
use base qw(Mail::Box);

=head1 new()

Creates a new Oserp::Backend object. Passes this off to Mail::Box::Manager.

=cut

sub new
{
	my ($this) = shift;
	my $class = ref($this) || $this;

	my $mgr = Mail::Box::Manager->new;

	my $self = {
		_mgr	=> $mgr,
		};
	bless($self, $class);
}

=head1 quit()

Closes open folders. Currently passes it off to Mail::Box::Manager->closeAllFolders(@_)

=cut

sub quit
{
	ref(my $self = shift) or croak "instance variable needed";
	$self->{_mgr}->closeAllFolders(@_) if ref $self->{_mgr};
}

=head1 build_msg

Takes a hash ref as the option, builds a message, returns it.

=cut

sub build_msg
{
	ref(my $self = shift) or croak "instance variable needed";
	my $class = ref($self);
	my $msg_ref = shift;

	my $message = Mail::Message->build( %{$msg_ref} );
	bless($message, $class);
}

=head1 send_msg

Takes a message object as an option, and sends it.

=cut

sub send_msg
{
	ref(my $self = shift) or croak "instance variable needed";
	my $message = shift;
	return $message->send();
}

sub closeAllFolders
{
	ref(my $self = shift) or croak "instance variable needed";
	$self->{_mgr}->closeAllFolders(@_);
}

1;
