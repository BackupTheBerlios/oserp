package Oserp::Config;

=head1 NAME

Oserp::Config

=head1 DESCRIPTION

Oserp config file utilities

=head1 TODO

This should be re-worked to support multiple config backends, so we can have a win32 registry type backend, etc.

=cut

use 5.00503;
use Carp;
use strict;
use File::Copy;
use AppConfig qw(:expand :argcount);
use vars qw($VERSION);

$VERSION = sprintf "%d.%03d", q$Revision: 1.2 $ =~ /(\d+)/g;

=head1 new()

Creates a new Oserp::Config object. Takes an array in that should be command line options (minus anything that oserp wants to handle itself). If there is a 'p' option passed in, it will be used instead of the default config.

=cut

sub new
{
	my ($this) = shift;
	my $class = ref($this) || $this;
	my %opts = @_;

	my $self = { };
	bless($self, $class);

	if ($opts{p})
	{	# use this config file
		$self->{cfg}->{file} = $opts{p};
	} else {
		$self->{cfg}->{file} = "$ENV{HOME}/.oserprc";
	}

	my $appconfig = AppConfig->new( {
		CASE	=> 0,
		ERROR	=> sub { my @arg = @_; }, # ignore errors
		GLOBAL  => {
			DEFAULT => "",
			ARGCOUNT    => ARGCOUNT_ONE,
			EXPAND  => EXPAND_ALL,
			VALIDATE    => '.*', # sub(varname,value) referance or regex
#			ACTION  => \&cfg_varchange, # passed (AppConfig::State object, varname, varvalue)
            }
		} );
	$self->{ac} = $appconfig;

	# setup defaults
	$self->set_defaults();

	# do overrides
	$self->{ac}->args( map { "-".$_ => $opts{$_} } keys %opts );

	return $self;
}

sub close
{
}

=head1 get()

Get's a value

=cut

sub get
{
	ref(my $self = shift) or croak "instance variable needed";
	return $self->{ac}->get(@_);
}

=head1 set()

Set's a value

=cut

sub set
{
	ref(my $self = shift) or croak "instance variable needed";
	$self->{ac}->set(@_);
}

=head1 set_defaults()

Sets up the defaults and defines all vars. Also uses the special *DATA filehandle to read in the default values form the bottom of this page.

=cut

sub set_defaults
{
	ref(my $self = shift) or croak "instance variable needed";

	$self->{ac}->define(
		'personal-name',
		'user-domain'	=> { DEFAULT => 'domain.com' },
		'smtp-server' => { DEFAULT => 'localhost' },
		'nntp-server',
		'inbox-path' => { DEFAULT => "/var/spool/mail/$ENV{USER}" },
		'incoming-archive-folders',
		'pruned-folders',
		'default-fcc',
		'default-saved-msg-folder',
		'postponed-folder',
		'read-message-folder',
		'form-letter-folder',
		'literal-signature',
		'signature-file',
#		'feature-list'	=> { ARGCOUNT => ARGCOUNT_LIST },
		'feature-list',
		'initial-keystroke-list',
		'default-composer-hdrs',
		'customized-hdrs',
		'viewer-hdrs',
		'saved-msg-name-rule',
		'fcc-name-rule',
		'sort-key',
		'addrbook-sort-rule',
		'folder-sort-rule',
		'goto-default-rule',
		'incoming-startup-rule',
		'pruning-rule',
		'character-set',
		'editor',
		'speller',
		'composer-wrap-column',
		'reply-indent-string',
		'reply-leadin',
		'empty-header-message',
		'image-view',
		'use-only-domain-name',
		'display-filters',
		'sending-filters',
		'alt-addresses',
		'addressbook-formats',
		'index-format',
		'viewer-overlap',
		'scroll-margin',
		'status-message-delay',
		'mail-check-interval',
		'newsrc-path',
		'news-active-file-path',
		'news-spool-directory',
		'upload-command',
		'upload-command-prefix',
		'download-command',
		'download-command-prefix',
		'mailcap-search-path',
		'mimetype-search-path',
		'url-viewers',
#		'incoming-folders'	=> { ARGCOUNT => ARGCOUNT_LIST },
		'incoming-folders',
#		'folder-collections'	=> { ARGCOUNT => ARGCOUNT_LIST },
		'folder-collections',
		'news-collections',
		'address-book',
		'global-address-book',
		'last-time-prune-questioned',
		'last-version-used',
		'sendmail-path',
		'operating-dir',
		'user-input-timeout',
		'tcp-open-timeout',
		'tcp-read-warning-timeout',
		'tcp-write-warning-timeout',
		'tcp-query-timeout',
		'rsh-command',
		'rsh-path',
		'rsh-open-timeout',
		'ssh-command',
		'ssh-path',
		'ssh-open-timeout',
		'new-vewsion-threshold',
		'disable-these-drivers',
		'disable-these-authenticators',
		'remote-abook-metafile',
		'remote-abook-history',
		'remote-abook-validity',
		'printer',
		'personal-print-command',
		'personal-print-category',
#		'pattern-roles'	=> { ARGCOUNT => ARGCOUNT_LIST },
		'pattern-roles',
		'patterns-filters',
		'patterns-scores',
		'patterns-indexcolors',
		'color-style',
		'normal-foreground-color',
		'normal-background-color',
		'reverse-foreground-color',
		'reverse-background-color',
		'title-foreground-color',
		'title-background-color',
		'status-foreground-color',
		'status-background-color',
		'keylabel-foreground-color',
		'keylabel-background-color',
		'keyname-foreground-color',
		'keyname-background-color',
		'selectable-item-foreground-color',
		'selectable-item-background-color',
		'quote1-foreground-color',
		'quote1-background-color',
		'quote2-foreground-color',
		'quote2-background-color',
		'quote3-foreground-color',
		'quote3-background-color',
		'prompt-foreground-color',
		'prompt-background-color',
		'index-to-me-foreground-color',
		'index-to-me-background-color',
		'index-important-foreground-color',
		'index-important-background-color',
		'index-deleted-foreground-color',
		'index-deleted-background-color',
		'index-answered-foreground-color',
		'index-answered-background-color',
		'index-new-foreground-color',
		'index-new-background-color',
		'index-recent-foreground-color',
		'index-recent-background-color',
		'index-unseen-foreground-color',
		'index-unseen-background-color',
		'viewer-hdr-colors',
		'ldap-servers',
		'patterns-other',
		'current-indexline-style',
		'threading-display-style',
		'threading-index-style',
		'threading-indicator-character',
		'threading-expanded-character',
		'threading-lastreply-character',
		'debug-memory',
		'patterns-filters2',
		'patterns-scores2',
		'titlebar-color-style',
		);
	unless (-e $self->{cfg}->{file})
	{
		open(CFG,"> $self->{cfg}->{file}") or die "can't open config file: $self->{cfg}->{file}\n";
		while(<DATA>)
		{
			print CFG $_;
		}
		close CFG;
	}
	$self->{ac}->file($self->{cfg}->{file});
}

1;

__DATA__
#
# Oserp configuration file
#
# This file sets the configuration options used by Oserp and PC-Oserp. These
# options are usually set from within Oserp or PC-Oserp. There may be a
# system-wide configuration file which sets the defaults for some of the
# variables. On Unix, run oserp -conf to see how system defaults have been set.
# For variables that accept multiple values, list elements are separated by
# commas. A line beginning with a space or tab is considered to be a
# continuation of the previous line. For a variable to be unset its value must
# be blank. To set a variable to the empty string its value should be "".
# You can override system defaults by setting a variable to the empty string.
# Lines beginning with "#" are comments, and ignored by Oserp.

# Over-rides your full name from Unix password file. Required for PC-Oserp.
personal-name = 

# Sets domain part of From: and local addresses in outgoing mail.
user-domain = domain.com

# List of SMTP servers for sending mail. If blank: Unix Oserp uses sendmail.
smtp-server = localhost

# NNTP server for posting news. Also sets news-collections for news reading.
nntp-server = 

# Path of (local or remote) INBOX, e.g. ={mail.somewhere.edu}inbox
# Normal Unix default is the local INBOX (usually /usr/spool/mail/$USER).
inbox-path = ~/mail/inbox

# List of folder pairs; the first indicates a folder to archive, and the
# second indicates the folder read messages in the first should
# be moved to.
incoming-archive-folders = 

# List of context and folder pairs, delimited by a space, to be offered for
# pruning each month.  For example: {host1}mail/[] mumble
pruned-folders = 

# Over-rides default path for sent-mail folder, e.g. =old-mail (using first
# folder collection dir) or ={host2}sent-mail or ="" (to suppress saving).
# Default: sent-mail (Unix) or SENTMAIL.MTX (PC) in default folder collection.
default-fcc = 

# Over-rides default path for saved-msg folder, e.g. =saved-messages (using 1st
# folder collection dir) or ={host2}saved-mail or ="" (to suppress saving).
# Default: saved-messages (Unix) or SAVEMAIL.MTX (PC) in default collection.
default-saved-msg-folder = 

# Over-rides default path for postponed messages folder, e.g. =pm (which uses
# first folder collection dir) or ={host4}pm (using home dir on host4).
# Default: postponed-msgs (Unix) or POSTPOND.MTX (PC) in default fldr coltn.
postponed-folder = 

# If set, specifies where already-read messages will be moved upon quitting.
read-message-folder = 

# If set, specifies where form letters should be stored.
form-letter-folder = 

# Contains the actual signature contents as opposed to the signature filename.
# If defined, this overrides the signature-file. Default is undefined.
literal-signature = 

# Over-rides default path for signature file. Default is ~/.signature
signature-file = 

# List of features; see Oserp's Setup/options menu for the current set.
# e.g. feature-list= select-without-confirm, signature-at-bottom
# Default condition for all of the features is no-.
feature-list = 

# Oserp executes these keys upon startup (e.g. to view msg 13: i,j,1,3,CR,v)
initial-keystroke-list = 

# Only show these headers (by default) when composing messages
default-composer-hdrs = 

# Add these customized headers (and possible default values) when composing
customized-hdrs = 

# When viewing messages, include this list of headers
viewer-hdrs = 

# Determines default folder name for Saves...
# Choices: default-folder, by-sender, by-from, by-recipient, last-folder-used.
# Default: "default-folder", i.e. "saved-messages" (Unix) or "SAVEMAIL" (PC).
saved-msg-name-rule = 

# Determines default name for Fcc...
# Choices: default-fcc, by-recipient, last-fcc-used.
# Default: "default-fcc" (see also "default-fcc=" variable.)
fcc-name-rule = 

# Sets presentation order of messages in Index. Choices:
# subject, from, arrival, date, size. Default: "arrival".
sort-key = 

# Sets presentation order of address book entries. Choices: dont-sort,
# fullname-with-lists-last, fullname, nickname-with-lists-last, nickname
# Default: "fullname-with-lists-last".
addrbook-sort-rule = 

# Sets presentation order of folder list entries. Choices: ,
# 
# Default: "alpha-with-directories-last".
folder-sort-rule = 

# Sets the default folder and collectionoffered at the Goto Command's prompt.
goto-default-rule = 

# Sets message which cursor begins on. Choices: first-unseen, first-recent,
# first-important, first-important-or-unseen, first-important-or-recent,
# first, last. Default: "first-unseen".
incoming-startup-rule = 

# Allows a default answer for the prune folder questions. Choices: yes-ask,
# yes-no, no-ask, no-no, ask-ask, ask-no. Default: "ask-ask".
pruning-rule = 

# Reflects capabilities of the display you have. Default: US-ASCII.
# Typical alternatives include ISO-8859-x, (x is a number between 1 and 9).
character-set = 

# Specifies the program invoked by ^_ in the Composer,
# or the "enable-alternate-editor-implicitly" feature.
editor = /bin/vi

# Specifies the program invoked by ^T in the Composer.
speller = /usr/local/bin/ispell

# Specifies the column of the screen where the composer should wrap.
composer-wrap-column = 

# Specifies the string to insert when replying to a message.
reply-indent-string = 

# Specifies the introduction to insert when replying to a message.
reply-leadin = 

# Specifies the string to use when sending a  message with no to or cc.
empty-header-message = 

# Program to view images (e.g. GIF or TIFF attachments).
image-viewer = 

# If "user-domain" not set, strips hostname in FROM address. (Unix only)
use-only-domain-name = 

# This variable takes a list of programs that message text is piped into
# after MIME decoding, prior to display.
display-filters = 

# This defines a program that message text is piped into before MIME
# encoding, prior to sending
sending-filters = 

# A list of alternate addresses the user is known by
alt-addresses = 

# This is a list of formats for address books.  Each entry in the list is made
# up of space-delimited tokens telling which fields are displayed and in
# which order.  See help text
addressbook-formats = 

# This gives a format for displaying the index.  It is made
# up of space-delimited tokens telling which fields are displayed and in
# which order.  See help text
index-format = 

# The number of lines of overlap when scrolling through message text
viewer-overlap = 

# Number of lines from top and bottom of screen where single
# line scrolling occurs.
scroll-margin = 

# The number of seconds to sleep after writing a status message
status-message-delay = 

# The approximate number of seconds between checks for new mail
mail-check-interval = 

# Full path and name of NEWSRC file
newsrc-path = 

# Path and filename of news configation's active file.
# The default is typically "/usr/lib/news/active".
news-active-file-path = 

# Directory containing system's news data.
# The default is typically "/usr/spool/news"
news-spool-directory = 

# Path and filename of the program used to upload text from your terminal
# emulator's into Oserp's composer.
upload-command = 

# Text sent to terminal emulator prior to invoking the program defined by
# the upload-command variable.
# Note: _FILE_ will be replaced with the temporary file used in the upload.
upload-command-prefix = 

# Path and filename of the program used to download text via your terminal
# emulator from Oserp's export and save commands.
download-command = 

# Text sent to terminal emulator prior to invoking the program defined by
# the download-command variable.
# Note: _FILE_ will be replaced with the temporary file used in the downlaod.
download-command-prefix = 

# Sets the search path for the mailcap configuration file.
# NOTE: colon delimited under UNIX, semi-colon delimited under DOS/Windows/OS2.
mailcap-search-path = 

# Sets the search path for the mimetypes configuration file.
# NOTE: colon delimited under UNIX, semi-colon delimited under DOS/Windows/OS2.
mimetype-search-path = 

# List of programs to open Internet URLs (e.g. http or ftp references).
url-viewers = 

# List of incoming msg folders. This should be single mail folders
# eg. an mh folder, maildir folder, mbox filename, etc
# Syntax: optnl-label type://[server]/dir/folder
# Types: mh, md (maildir), mbox, imap4, pop3, dbx (outlook)
incoming-folders = inbox mbox:///home/${USER}/mail/inbox

# List of directories where saved-messages folders may be.
# Example: Mail mh:///home/${USER}/mh/mail/,
#               MB2 mbox:///home/${USER}/mail/
# Syntax: optnl-label type://[server]/dir/folder[]
# Types: mh, md (maildir), mbox, imap4, pop3, dbx (outlook)
folder-collections = Mail mbox:///home/${USER}/mail/[]

# List, only needed if nntp-server not set, or news is on a different host
# than used for NNTP posting. Examples: News *[] or News *{host3/nntp}[]
# Syntax: optnl-label *{news-host/protocol}[]
news-collections = 

# List of file or path names for personal addressbook(s).
# Default: ~/.addressbook (Unix) or \PINE\ADDRBOOK (PC)
# Syntax: optnl-label path-name
address-book = 

# List of file or path names for global/shared addressbook(s).
# Default: none
# Syntax: optnl-label path-name
global-address-book = 

# Set by Oserp; controls beginning-of-month sent-mail pruning.
last-time-prune-questioned = 104.3

# Set by Oserp; controls display of "new version" message.
last-version-used = 4.53

# This names the path to an alternative program, and any necessary arguments,
# to be used in posting mail messages.  Example:
#                    /usr/lib/sendmail -oem -t -oi
# or,
#                    /usr/local/bin/sendit.sh
# The latter a script found in Oserp distribution's contrib/util directory.
# NOTE: The program MUST read the message to be posted on standard input,
#       AND operate in the style of sendmail's "-t" option.
sendmail-path = 

# This names the root of the tree to which the user is restricted when reading
# and writing folders and files.  For example, on Unix ~/work confines the
# user to the subtree beginning with their work subdirectory.
# (Note: this alone is not sufficient for preventing access.  You will also
# need to restrict shell access and so on, see Oserp Technical Notes.)
# Default: not set (so no restriction)
operating-dir = 

# If no user input for this many hours, Oserp will exit if in an idle loop
# waiting for a new command.  If set to zero (the default), then there will
# be no timeout.
user-input-timeout = 

# Sets the time in seconds that Oserp will attempt to open a network
# connection.  The default is 30, the minimum is 5, and the maximum is
# system defined (typically 75).
tcp-open-timeout = 

# Network read warning timeout. The default is 15, the minimum is 5, and the
# maximum is 1000.
tcp-read-warning-timeout = 

# Network write warning timeout. The default is 0 (unset), the minimum
# is 5 (if not 0), and the maximum is 1000.
tcp-write-warning-timeout = 

# If this much time has elapsed at the time of a tcp read or write
# timeout, oserp will ask if you want to break the connection.
# Default is 60 seconds, minimum is 5, maximum is 1000.
tcp-query-timeout = 

# Sets the format of the command used to open a UNIX remote
# shell connection.  The default is "%s %s -l %s exec /etc/r%sd"
# NOTE: the 4 (four) "%s" entries MUST exist in the provided command
# where the first is for the command's path, the second is for the
# host to connnect to, the third is for the user to connect as, and the
# fourth is for the connection method (typically "imap")
rsh-command = 

# Sets the name of the command used to open a UNIX remote shell connection.
# The default is tyically /usr/ucb/rsh.
rsh-path = 

# Sets the time in seconds that Oserp will attempt to open a UNIX remote
# shell connection.  The default is 15, min is 5, and max is unlimited.
# Zero disables rsh altogether.
rsh-open-timeout = 0

# Sets the format of the command used to open a UNIX secure
# shell connection.  The default is "%s %s -l %s exec /etc/r%sd"
# NOTE: the 4 (four) "%s" entries MUST exist in the provided command
# where the first is for the command's path, the second is for the
# host to connnect to, the third is for the user to connect as, and the
# fourth is for the connection method (typically "imap")
ssh-command = 

# Sets the name of the command used to open a UNIX secure shell connection.
# Tyically this is /usr/local/bin/ssh.
ssh-path = 

# Sets the time in seconds that Oserp will attempt to open a UNIX secure
# shell connection.  The default is 15, min is 5, and max is unlimited.
# Zero disables ssh altogether.
ssh-open-timeout = 

# Sets the version number Oserp will use as a threshold for offering
# its new version message on startup.
new-version-threshold = 

# List of mail drivers to disable.
disable-these-drivers = 

# List of SASL authenticators to disable.
disable-these-authenticators = 

# Set by Oserp; contains data for caching remote address books.
remote-abook-metafile = 

# How many extra copies of remote address book should be kept. Default: 3
remote-abook-history = 

# Minimum number of minutes between checks for remote address book changes.
# 0 means never check except when opening a remote address book.
# -1 means never check. Default: 5
remote-abook-validity = 

# Your default printer selection
printer = 

# List of special print commands
personal-print-command = 

# Which category default print command is in
personal-print-category = 

# Patterns and their actions are stored here.
patterns-roles = 

# Patterns and their actions are stored here.
patterns-filters = 

# Patterns and their actions are stored here.
patterns-scores = 

# Patterns and their actions are stored here.
patterns-indexcolors = 

# Controls display of color
color-style = 

# Choose: black, blue, green, cyan, red, magenta, yellow, or white.
normal-foreground-color = 
normal-background-color = 
reverse-foreground-color = 
reverse-background-color = 
title-foreground-color = 
title-background-color = 
status-foreground-color = 
status-background-color = 
keylabel-foreground-color = 
keylabel-background-color = 
keyname-foreground-color = 
keyname-background-color = 
selectable-item-foreground-color = 
selectable-item-background-color = 
quote1-foreground-color = 
quote1-background-color = 
quote2-foreground-color = 
quote2-background-color = 
quote3-foreground-color = 
quote3-background-color = 
prompt-foreground-color = 
prompt-background-color = 
index-to-me-foreground-color = 
index-to-me-background-color = 
index-important-foreground-color = 
index-important-background-color = 
index-deleted-foreground-color = 
index-deleted-background-color = 
index-answered-foreground-color = 
index-answered-background-color = 
index-new-foreground-color = 
index-new-background-color = 
index-recent-foreground-color = 
index-recent-background-color = 
index-unseen-foreground-color = 
index-unseen-background-color = 

# When viewing messages, these are the header colors
viewer-hdr-colors = 

# LDAP servers for looking up addresses.
ldap-servers = 

# Patterns and their actions are stored here.
patterns-other = 

# Controls display of color for current index line
current-indexline-style = 

# Style that MESSAGE INDEX is displayed in when threading.
threading-display-style = 

# Style of THREAD INDEX or default MESSAGE INDEX when threading.
threading-index-style = 

# When threading, character used to indicate collapsed messages underneath.
threading-indicator-character = 

# When threading, character used to indicate expanded messages underneath.
threading-expanded-character = 

# When threading, character used to indicate this is the last reply
# to the parent of this message.
threading-lastreply-character = 

# This many btyes of memory is used for holding recent status messages and
# debugging output. Default is 500,000.
debug-memory = 

# Patterns and their actions are stored here.
patterns-filters2 = 

# Patterns and their actions are stored here.
patterns-scores2 = 

# Controls display of color for the titlebar at top of screen
titlebar-color-style = 
