package Oserp::GUI::Curses;

#########################################
# ncurses interface for oserp libraries #
#########################################

use 5.00503;
use strict;
use Carp;
use Curses;
use Curses::Widgets qw(:all);
use Mail::Box::Search::Grep;
use POSIX qw(:termios_h);
use vars qw($VERSION);

$VERSION = sprintf "%d.%03d", q$Revision: 1.11 $ =~ /(\d+)/g;

sub redraw_env
{
	endwin();
	refresh();
}

=head1 new()

creates a new gui object

Each screen called should do it's business and, when done, return the next screen the gui should go to (like if they hit 'compose' from a screen, it'd return 'compose').

For things that should return something else, pass a referance to a scalar in, and hae the gui method stick the data in it. For example, in message composition, it should return a hash with the message parts, which will then get turned into a message object in the main program.

=cut

sub new
{
	my ($this) = shift;
	my $class = ref($this) || $this;

	my $self = {};
	bless($self, $class);

	# handle redrawing the window when size changes:
	$SIG{WINCH} = \&redraw_env;
	# ignore CTRL-C so we can CTRL-C on a message, to cancel sending and shit
	{
		my $termio = POSIX::Termios->new;
		$termio->getattr(fileno(STDIN));
		my $intrid = $termio->getcc(VINTR);
		$self->{_saved_term} = $intrid;
		$termio->setcc(VINTR, '');
		$termio->setattr(fileno(STDIN),TCSANOW);
	}

	my $curs = new Curses;
	$self->{curs} = $curs;

	# TODO this should come from the config
	$self->{_check_mail_delay} = 10;

	initscr(); cbreak(); noecho();
	leaveok(1); # ok to leave cursor whereever, and not draw it
	raw(); # don't allow term to interpret CTRL-C and other escape chars
	# halfdelay is how long we'll wait in tenths of seconds for a
	# character to be entered before we loop out, and do things
	# like check for e-mail and stuff
	halfdelay(10); # set timeout, so widgets can call functions periodically
	eval { keypad(1) };

	return $self;
}

sub clear_win
{	# remove past screen contents. (this may not be needed in other guis)
	erase();
	refresh();
#	endwin();
	clear();
}

sub quit
{	# cleanup anything we have laying around
	ref(my $self = shift);
	clear();
	refresh();
	endwin();
	# restore CTRL-C
	{
		my $termio = POSIX::Termios->new;
		$termio->getattr(fileno(STDIN));
		if ( (ref($self)) && $self->{_saved_term} )
		{	# restore the SIGINT
			$termio->setcc(VINTR, $self->{_saved_term} );
		} else {	# restore SIGINT to CTRL-C
			$termio->setcc(VINTR, ord( '' ) );
		}
		$termio->setattr(fileno(STDIN),TCSANOW);
	}
}

sub _draw_menu
{
	# utility function - takes to array refs, and draws them across the screen
	ref(my $self = shift) or croak "instance variable needed";
	my $rows = shift;
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	my $b = subwin(2,$maxx,$maxy - 2, 0);

	my $big_length = (scalar(@{$rows->[0]}) > scalar(@{$rows->[1]})) ?
	                          scalar @{$rows->[0]} : scalar @{$rows->[1]};
	my @col_lengths;
	for (my $i = 0; $i < $big_length; $i++)
	{
		my $longest = (length($rows->[0][$i]) > length($rows->[1][$i])) ?
		              length($rows->[0][$i]) : length($rows->[1][$i]);
		$col_lengths[$i] = $longest;
	}
	foreach my $y (0,1)
	{
		my $printed_length;
		for (my $i = 0; $i < $big_length; $i++)
		{
			my @cd = ('',''); # cell data
			if ($rows->[$y][$i] =~ /^(\S+)(\s.*)/)
			{
				$cd[0] = $1; $cd[1] = $2;
			}
			standout($b) if $cd[0];
			if ($i == 0)
			{	# first element
				addstr($b,$y,0, sprintf('%-*s',1,$cd[0]) );
			} else {
				addstr($b, sprintf('%-*s',1,$cd[0]) );
			}
			standend($b) if $cd[0];
			addstr($b, sprintf('%-*s',$col_lengths[$i],$cd[1]) );
			$printed_length += $col_lengths[$i] + 1;
		}
		addstr($b, (" " x ($maxx - $printed_length)));
	}
	refresh($b);
}

sub clear_main_win
{
	ref(my $self = shift) or croak "instance variable needed";
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	my $b = subwin($maxy - 3, $maxx, 0, 0);
	erase($b);
	refresh($b);
}

sub main_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my @menu = (
		['? Help','','P PrevCmd','R RelNotes'],
		['O OTHER CMDS','> [ListFlds]','N NextCmd','K KBLock']
		);
	$self->_draw_menu(\@menu);
}
sub main
{
	ref(my $self = shift) or croak "instance variable needed";
	$self->clear_main_win();
	$self->main_menu();
	my @buttons = (
		'?     HELP               - Get help using oserp            ',
		'C     COMPOSE MESSAGE    - Compose and send a message      ',
		'I     MESSAGE INDEX      -  View messages in current folder',
		'L     FOLDER LIST        -  Select a folder to view        ',
		'A     ADDRESS BOOK       -  Update address book            ',
		'S     SETUP              -  Configure Pine Options         ',
		'Q     QUIT               -  Leave the Pine program         '
		);

	my ($key,$button) = buttons(
		'window'	=> $self->{curs},
		'buttons'	=> \@buttons,
		'active_button'	=> 3,
		'ypos'	=> 2,
		'xpos'	=> 10,
		'vertical'	=> 1,
		'regex'	=> qr/[\?CcIiLlAaSsQq\n]/
		);
	$self->{curs}->erase();
	if ($key eq "\n")
	{	# did they select via arrows, or letters
		my %buttons = (
			0	=> 'help',
			1	=> 'compose',
			2	=> 'list',
			3	=> 'list',
			4	=> 'addressbook',
			5	=> 'setup',
			6	=> 'quit'
			);
		return $buttons{$button};
	} else {
		my %keys = (
			'?'	=> 'help',
			c	=> 'compose',
			i	=> 'list',
			l	=> 'list',
			a	=> 'addressbook',
			s	=> 'setup',
			q	=> 'quit'
			);
		return $keys{lc($key)};
	}
}

sub yn_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my @menu = (
		[	['','Y Yes'],
			['^C Cancel','N [No]'] ]
		);
	$self->_draw_menu(\@{$menu[0]});
}

sub composemsg
{
	ref(my $self = shift) or croak "instance variable needed";
	my $msg_ref = {};
	my $rv = $self->compose($msg_ref);
	if ($rv eq 'back')
	{	# they canceled. Save the messge to dead.letter
		# TODO: actually save it
		return "[Message cancelled and copied to \"dead.letter\" file]";
	} else {
		my $message = Mail::Message->build( %{$msg_ref} );
		if ($message->send())
		{
			# TODO: save to saved folder
			return "[Message sent and copied to \"sent-mail\".]";
		} else {
			return "[Message send failed!]";
		}
	}
}

sub forward_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my $menu = shift;
	my @menu = (
		[	['<CR> [accept]'],
			['^C Cancel'] ],
		);
	$self->_draw_menu(\@{$menu[$menu]});
}
sub forward
{
	ref(my $self = shift) or croak "instance variable needed";
	my $message = shift;
	$self->forward_menu(0);
	my $forwardto = $self->prompt_str("Forward message to: ", qr/^[A-Za-z0-9`~!\@#\$\%^\&\*()\[\]_\-=+\{\}\|\\;:'",\.\<\>\/\?\s]{2,}$/, 127);
	if ($forwardto =~ //)
	{	# forward canceled
		return "[Forward canceled]";
	}
	$self->clearprompt();

	my $forward = $message->forward(To => $forwardto);
	# TODO: body currently handled bad

	my $msg_ref = {};
	my $rv = $self->compose($msg_ref,$forward);
	if ($rv eq 'back')
	{
		# TODO: actually save it to dead.letter
		return "[Message cancelled and copied to \"dead.letter\" file]";
	} else {
		my $newhead = $forward->head()->clone();
		my %body_and_files;
		# TODO: must verify we have nice data, and required fields filled
		foreach my $key (keys %{$msg_ref})
		{	# set the headers (all that begin w/ upper case letters)
			my $value = defined $msg_ref->{$key} ? $msg_ref->{$key} : "";
			if ($key =~ /^[A-Z]/)
			{
				$newhead->set($key, $value);
			} else {
				$body_and_files{$key} = $value;
			}
		}
		my $newforward = Mail::Message->build(
			head	=> $newhead,
			%body_and_files
			);
		if ($newforward->send())
		{
			# TODO: save to saved folder
			return "[Message sent and copied to \"sent-mail\".]";
		} else {
			return "[Message send failed!]";
		}
	}
}

sub reply
{
	ref(my $self = shift) or croak "instance variable needed";
	my $message = shift;
	$self->yn_menu();
	my $group_reply = $self->prompt_chr("Reply to all recipients? ",qr/^[yn]/i);
	$self->clearprompt();
	if ($group_reply =~ //)
	{	# reply canceled
		return "[Reply canceled]";
	}
	my $gr = ($group_reply =~ /^y/i) ? 1 : 0;
	# TODO quote character should come from config, as well as other parts here
	my $quote_char = "> ";
	my $sig = undef; # sig can !!!NOT!!! be an empty string ("").
	my $strip_sig = qr/^--\s/; # regex, string, code
	my $inc_message = 'INLINE'; # 'NO'|'INLINE'|'ATTACH'

	# let Mail::Box create the reply
	my $reply = $message->reply(
		group_reply	=> $gr,
		quote	=> $quote_char,
		signature	=> $sig,
		strip_signature	=> $strip_sig,
		include	=> $inc_message
		);
	# TODO: body currently handled bad

	my $msg_ref = {};
	my $rv = $self->compose($msg_ref,$reply);
	if ($rv eq 'back')
	{
		# TODO: actually save it to dead.letter
		return "[Message cancelled and copied to \"dead.letter\" file]";
	} else {
		my $newhead = $reply->head()->clone();
		my %body_and_files;
		# TODO: must verify we have nice data, and required fields filled
		foreach my $key (keys %{$msg_ref})
		{	# set the headers (all that begin w/ upper case letters)
			my $value = defined $msg_ref->{$key} ? $msg_ref->{$key} : "";
			if ($key =~ /^[A-Z]/)
			{
				$newhead->set($key, $value);
			} else {
				$body_and_files{$key} = $value;
			}
		}
		my $newreply = Mail::Message->build(
			head	=> $newhead,
			%body_and_files
			);
		if ($newreply->send())
		{
			# TODO: save to saved folder
			return "[Message sent and copied to \"sent-mail\".]";
		} else {
			return "[Message send failed!]";
		}
	}
}

sub search_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my $menu = shift;
	my @menu = (
		[	['^G Help','^X Select Matches','^Y First Msg'],
			['^C Cancel','Ret Accept','^V Last Msg'] ],
		);
	$self->_draw_menu(\@{$menu[$menu]});
}
sub list_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my $menu = shift;
	my @menu = (
		[	['? Help','< FldrList','P PrevMsg','- PrevPage','D Delete','R Reply'],
			['O OTHER CMDS','> [curfunc]','N NextMsg','Spc Next Page','U Undelete','F Forward'] ],
		[	['? Help','M Main Menu','C Compose','Tab NextNew','% Print','S Save'],
			['O OTHER CMDS','Q Quit oserp','G GotoFldr','W WhereIs','T TakeAddr','E Export'] ],
		);
	$self->_draw_menu(\@{$menu[$menu]});
}
sub list
{
	ref(my $self = shift) or croak "instance variable needed";
	my $folder = shift;
	my $menu = $_[0] ? $_[0] : 0;
	my $max_menu = 1;
	$self->{_current_folder} = $folder;
	$self->{_last_mail_check} = time();

	$self->list_menu($menu);

	refresh();

	my $last_msg = (scalar $folder->messages) - 1;
	my $curline = $self->draw_list($last_msg,1);
	my $cursearch;
	my @searchlist;

	while (my $ch = getch())
	{
		if ((lc($ch) eq 'n') || ($ch eq KEY_DOWN)) { # NEXT
			$curline++;
			$curline = $self->draw_list($curline);
		} elsif ((lc($ch) eq 'p') || ($ch eq KEY_UP)) { # PREV
			$curline--;
			$curline = $self->draw_list($curline);
		} elsif ( ($ch eq " ") || ($ch eq KEY_NPAGE) ) { # N_PAGE
			$curline += ($self->{curs}->getmaxy() - 3);
			$curline = $self->draw_list($curline);
		} elsif ( ($ch eq "-") || ($ch eq KEY_PPAGE) ) { # P_PAGE
			$curline -= ($self->{curs}->getmaxy() - 3);
			$curline = $self->draw_list($curline);
		} elsif (lc($ch) eq 'd') { # DELETE
			$folder->message($curline)->deleted(1);
			$curline++;
			$curline = $self->draw_list($curline);
		} elsif (lc($ch) eq 'q') { # QUIT
			return 'quit';
		} elsif (lc($ch) eq 'o') { # OTHER MENU
			$menu = ($menu >= $max_menu) ? 0 : ($menu + 1);
			$self->list_menu($menu);
		} elsif (lc($ch) eq 'j') { # JUMP
			my $rv = $self->prompt_str("Message number to jump to : ",qr/^\d+$/,10);
			$curline = $rv if defined $rv;
			$curline = $self->draw_list($curline);
		} elsif ( ($ch eq '<') || ($ch eq ',') ) { # BACK
			return 'back';
		} elsif ( ($ch eq "\n") || (lc($ch) eq 'v') || ($ch eq '.') ) { # VIEW
			my $nextline = $self->view($curline);
			if ($nextline eq 'compose')
			{	# COMPOSE
				my $statusmsg = $self->composemsg();
				$self->list_menu($menu);
				$curline = $self->draw_list($curline);
				$self->statusmsg($statusmsg);
			}
			$curline = $self->draw_list($nextline);
		} elsif (lc($ch) eq 'c') { # COMPOSE
			my $statusmsg = $self->composemsg();
			$self->clear_win();
			$self->list_menu($menu);
			$curline = $self->draw_list($curline);
			$self->statusmsg($statusmsg);
		} elsif (lc($ch) eq 'r') { # REPLY
			my $statusmsg = $self->reply($folder->message($curline));
			$self->clear_win();
			$self->list_menu($menu);
			$curline = $self->draw_list($curline);
			$self->statusmsg($statusmsg);
		} elsif (lc($ch) eq 'f') { # FORWARD
			my $statusmsg = $self->forward($folder->message($curline));
			$self->clear_win();
			$self->list_menu($menu);
			$curline = $self->draw_list($curline);
			$self->statusmsg($statusmsg);
		} elsif ($ch eq "") { # SEARCH
			$self->search_menu(0);
			my $searchstring = $self->prompt_str("Word to search for [$cursearch] : ", qr/^[A-Za-z0-9`~!\@#\$\%^\&\*()\[\]_\-=+\{\}\|\\;:'",\.\<\>\/\?\s]{1,}$/, 127,"");
			$self->list_menu($menu);
			if ($searchstring eq "")
			{	# cancel search
				$self->statusmsg("[Search cancelled]");
			} elsif ($searchstring =~ //) {	# BEGINING
				$curline = $self->draw_list(0,1);
			} elsif ($searchstring =~ //) {	# END
				$curline = $self->draw_list($last_msg,1);
			} elsif ($searchstring =~ //) {	# HELP
				# TODO: the help
				$self->statusmsg("--help not implemented yet--");
			} else {	# SEARCH
				my $tag = 0;
				if ($searchstring =~ //)	# TAG
				{
					$tag = 1;
					$searchstring =~ s///g;
				}
				my $found;
				$searchstring = $cursearch unless $searchstring;
				if ($searchstring)
				{	# get new search list
					my $next_curline = $self->list_search($searchstring,$curline,$tag);
					$found++ if ($next_curline != $curline);
					$curline = $next_curline;
					$cursearch = $searchstring;
				}
				$curline = $self->draw_list($curline);
				if ($tag)
				{
					$self->statusmsg("[Messages flagged]");
				} else {
					$self->statusmsg("[Word found]") if $found;
					$self->statusmsg("[No match found]") unless $found;
				}
			}
		} elsif ( (time() - $self->{_last_mail_check}) > $self->{_check_mail_delay}) {
			$self->{_last_mail_check} = time();
			$folder->update();
			my $new_last_msg = (scalar $folder->messages) - 1;
			if ($new_last_msg != $last_msg)
			{
				beep();
				#$self->statusmsg("[New mail to you! From Josh Miller as to test]");
				$curline = $self->draw_list($curline);
				$self->statusmsg("[New mail to you!]");
				$last_msg = $new_last_msg;
			}
		}
		refresh();
	}
}
sub list_search
{
	ref(my $self = shift) or croak "instance variable needed";
	my ($searchstring,$curline,$tag) = @_;

	my %tag = ();
	if ($tag)
	{
		# TODO figure out how flags work
#		$tag{label} = 'selected'; # to flag messages that matched
		$tag{label} = 'flagged'; # to flag messages that matched
#		$tag{logical} = 'OR'; # when labeling, what to do.
			                  # see Mail::Box::Search
	}

	my $folder = $self->{_current_folder};
	my $filter;
	if ($folder->type =~ /imap/i)
	{	# search using imap
		# TODO: NOT IMPLEMENTED IN Mail::Box YET!!!
		if (0) {
		$filter = Mail::Box::Search::IMAP->new(
			decode	=> 0, # true by defualt, but shouldn't matter, cause
			              # we're only looking at headers
			deleted	=> 1, # look at all messages
			field	=> qr/(Subject|From|To|Cc|Date)/i,
			in	=> 'HEAD',# only look in the headers
			multiparts	=> '0',
			match	=> $searchstring,
			%tag
			);
		}
	} else {
		# search using grep
		$filter = Mail::Box::Search::Grep->new(
			decode	=> 0, # true by defualt, but shouldn't matter, cause
			              # we're only looking at headers
			deleted	=> 1, # look at all messages
			field	=> qr/(Subject|From|To|Cc|Date)/i,
			in	=> 'HEAD',# only look in the headers
			multiparts	=> '0',
			match	=> $searchstring,
			%tag
			);
	}
	my $next_match = $curline;
	if ($filter && $tag)
	{
		foreach my $message ($filter->search($folder))
		{
			$message->labelsToStatus();
		}
	} else {
		my $last_msg = (scalar $folder->messages) - 1;
		$curline = $last_msg if ($curline > $last_msg);
		SEARCH: for (my $i=($curline +1); $i!=$curline; $i++)
		{
			$i = 0 if ($i > $last_msg); # loop
			if ($filter->search($folder->message($i)) )
			{
				$next_match = $i;
				last SEARCH;
			}
		}
	}
	return $next_match;
}
sub draw_list
{
	ref(my $self = shift) or croak "instance variable needed";
	my $curline = shift;
	my $first_view = shift;
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();

	my $folder = $self->{_current_folder};
	my $msgs_per_page = $maxy - 3;
	my $num_of_msgs = $self->{_current_folder}->messages;

	# don't display warning prompts if we just opened the message
	if ($curline >= $num_of_msgs)
	{
		$curline = $num_of_msgs - 1;
		$self->statusmsg("[No more messages.  Press TAB for next folder.]") unless $first_view;
	} elsif ($curline < 0) {
		$curline = 0;
		$self->statusmsg("[Already on first message]") unless $first_view;
	} else {
			$self->clearprompt()
	}

	my $page;
	FINDPAGE: for (my $i = 1; $i < (($num_of_msgs / $msgs_per_page) + 1); $i++)
	{
		if ( ($msgs_per_page * $i) > $curline)
		{
			$page = $i;
			last FINDPAGE;
		}
	}
	my $beginline = ($page - 1) * $msgs_per_page;

	my $b = subwin($msgs_per_page, $maxx, 0, 0);
	for (my $i = 0; $i < $msgs_per_page; $i++)
	{
		my $message;
		unless ($message = $folder->message($i+$beginline))
		{
			addstr($b,$i,0,(" " x $maxx));
			next;
		}
		# TODO: need to get my to_addr from ENV or config
		my $labels = $message->labels();
		my $myaddr = $ENV{USER}."\@domain.com";
		my $flag;
		if ($message->to() =~ /$myaddr/i)
		{
			$flag = '+';
		} elsif ($labels->{'draft'}) {
			# used for important flag
			$flag = '*';
		} elsif ($labels->{'flagged'}) {
			$flag = 'X';
		} else {
			$flag = ($curline == ($i+$beginline)) ? '-' : ' ';
		}
		my $marker = ($curline == ($i+$beginline)) ? $flag.'>' : $flag.' ';
		addstr($b,$i,0,$marker);
		my $status;
		if ($message->deleted)
		{
			$status = 'D';
		} elsif ($labels->{'replied'}) {
			$status = 'A';
		} elsif (! $labels->{'seen'}) {
			$status = 'N';
		}
		addstr($b,sprintf('%-*s',2,$status));
		# msg number
		addstr($b,sprintf('%*s',(length($num_of_msgs)),$i + $beginline)." ");
		my $date = $message->date;
		my ($mon,$day);
		if ($date =~ /^[A-Za-z]+,\s(\d+)\s+(\S+)/)
		{
			$day = $1; $mon = $2;
		}
		# month
		addstr($b,sprintf('%-*s',4,$mon));
		# day
		addstr($b,sprintf('%*s',2,$day)." ");
		addstr($b, substr(sprintf('%-*s',20,
			$message->get('From')),0,20) . " " );
		my $size = $self->_bytes_to_readable($message->body->size);
		addstr($b, substr(sprintf('%*s',8,"(".$size.")"),0,8)." " );
		my $restlength = $maxx - (2+3+length($num_of_msgs)+1+4+3+20+9);
		$restlength--;
		addstr($b, substr(sprintf('%-*s',$restlength,
			$message->subject),0,$restlength) );
	}
	refresh($b);
	return $curline;
}

sub _bytes_to_readable
{
	ref(my $self = shift) or croak "instance variable needed";
	my $bytes = shift;
	my @extension = ('','K','M','G','T');
	my $ext_id;
	while ($bytes > 999) # not doing exact 1024, because we're making a float
	{
		$bytes /= 1024;
		$ext_id++;
	}
	if ($ext_id)
	{	# only float it if it's bigger than a few bytes
		$bytes = sprintf('%.1f',$bytes);
	} else {
		$bytes = int($bytes);
	}
	return $bytes.$extension[$ext_id];
}

sub view_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my $menu = shift;
	my @menu = (
		[	['? Help','< FldrList','P PrevMsg','- PrevPage','D Delete','R Reply'],
			['O OTHER CMDS','> [curfunc]','N NextMsg','Spc Next Page','U Undelete','F Forward'] ],
		[	['? Help','M Main Menu','C Compose','Tab NextNew','% Print','S Save'],
			['O OTHER CMDS','Q Quit oserp','G GotoFldr','W WhereIs','T TakeAddr','E Export'] ],
		);
	$self->_draw_menu(\@{$menu[$menu]});
}
sub view
{
	ref(my $self = shift) or croak "instance variable needed";
	my $msgnum = shift;
	my $menu = $_[0] ? $_[0] : 0;
	my $max_menu = 1;
	my $folder = $self->{_current_folder};
	my $last_msg = (scalar $folder->messages) - 1;
	if ($msgnum > $last_msg)
	{
		$msgnum = $last_msg;
		$self->statusmsg("[Already on last message]");
	} elsif ($msgnum < 0) {
		$msgnum = 0;
		$self->statusmsg("[Already on first message]");
	} else {
		$self->clearprompt();
	}

	my $message = $folder->message($msgnum);
	# update 'seen' flag
	$message->label('seen' => 1);
	$message->labelsToStatus();
	my $date = $message->date;
	my $from = $message->get('From');
	my @to = split(/\n/,  join(",\n          ",
	                           map { $_->format() } $message->to
	              )           );
	my @cc = split(/\n/,  join(",\n          ",
	                           map { $_->format() } $message->cc
	              )           );
	my $subject = $message->subject;

	$self->view_menu($menu);

	refresh();

	$self->{_current_view_buffer} = [];
	push(@{$self->{_current_view_buffer}},"Date    : $date");
	push(@{$self->{_current_view_buffer}},"From    : $from");

	push(@{$self->{_current_view_buffer}},"To      : ". shift @to);
	push(@{$self->{_current_view_buffer}},@to);
	push(@{$self->{_current_view_buffer}},"Cc      : ". shift @cc);
	push(@{$self->{_current_view_buffer}},@cc);

	push(@{$self->{_current_view_buffer}},"Subject : $subject");
	if ($message->isMultipart || $message->isNested)
	{	# add in the parts listing
		push(@{$self->{_current_view_buffer}},"Parts/Attachments:");
		my ($text_parts,$attchlist) = $self->list_attachments($message);
		push(@{$self->{_current_view_buffer}},@{$attchlist});
		push(@{$self->{_current_view_buffer}},("-" x 40));
		push(@{$self->{_current_view_buffer}},"");
		foreach my $part (@{$text_parts})
		{
			push(@{$self->{_current_view_buffer}},$part->decoded->lines);
			push(@{$self->{_current_view_buffer}},("","","-------- END PART --------",""));
		}
	} else {
		push(@{$self->{_current_view_buffer}},"");
		push(@{$self->{_current_view_buffer}},$message->decoded->lines);
	}
	my $curline = $self->draw_view(0,1);

	while (my $ch = getch())
	{
		if (lc($ch) eq 'n') {
			$msgnum++;
			return $self->view($msgnum);
		} elsif (lc($ch) eq 'p') {
			$msgnum--;
			return $self->view($msgnum);
		} elsif (($ch eq KEY_DOWN) || ($ch eq "\n")) {
			$curline++;
			$curline = $self->draw_view($curline);
		} elsif ($ch eq KEY_UP) {
			$curline--;
			$curline = $self->draw_view($curline);
		} elsif ( ($ch eq " ") || ($ch eq KEY_NPAGE) ) {
			$curline += ($self->{curs}->getmaxy() - 3);
			$curline = $self->draw_view($curline);
		} elsif ( ($ch eq "-") || ($ch eq KEY_PPAGE) ) {
			$curline -= ($self->{curs}->getmaxy() - 3);
			$curline = $self->draw_view($curline);
		} elsif (lc($ch) eq 'q') {
			return $msgnum;
		} elsif (lc($ch) eq 'o') {
			$menu = ($menu >= $max_menu) ? 0 : ($menu + 1);
			$self->view_menu($menu);
		} elsif ( ($ch eq '<') || ($ch eq ',') ) {
			return $msgnum;
		} elsif (lc($ch) eq 'c') {
			my $statusmsg = $self->composemsg();
			$self->clear_win();
			$self->view_menu($menu);
			$curline = $self->draw_view($curline);
			$self->statusmsg($statusmsg);
		} elsif (lc($ch) eq 'r') {
			my $statusmsg = $self->reply($message);
			$self->clear_win();
			$self->view_menu($menu);
			$curline = $self->draw_view($curline);
			$self->statusmsg($statusmsg);
		} elsif (lc($ch) eq 'f') {
			my $statusmsg = $self->forward($message);
			$self->clear_win();
			$self->view_menu($menu);
			$curline = $self->draw_view($curline);
			$self->statusmsg($statusmsg);
		}
		refresh();
	}
}
sub list_attachments
{
	ref(my $self = shift) or croak "instance variable needed";
	my $message = shift;
	my $partnum = 0;
	my @ret_lines;
	my @text_parts; # part we'll display as the body
	foreach my $part ($message->parts('RECURSE'))
	{
		$partnum++;
		my ($shown, $size, $type);
		if ($part->body->mimeType =~ /^text/i)
		{
			$shown = "Shown"; $type = "Text";
			push(@text_parts,$part);
		} else {
			$shown = "     "; $type = $part->get('Content-Type');
		}
		$size = $self->_bytes_to_readable($part->body->size);
		push(@ret_lines, sprintf('%4s',$partnum)." ".$shown.sprintf('%13s',$size)." ".$type);
	}
	return (\@text_parts,\@ret_lines);
}
sub list_attachments_old
{
	ref(my $self = shift) or croak "instance variable needed";
	my $message = shift;
	my $recurse_count = shift || 1; # avoid infinite loop parts
	my $partnum = shift || 0;
	return ("   XXX - Multipart recurse level exceeded") if ($recurse_count > 500);
	$recurse_count++;
	my @ret_lines;
	foreach my $part ($message->parts)
	{
		$partnum++;
		my ($shown, $size, $type);
		if ($part->body->mimeType =~ /text\/plain/i)
		{
			$shown = "Shown"; $type = "Text";
		} elsif ($part->isMultipart || $message->isNested) {
			$partnum--;
			my @newlines = $self->list_attachments($part,$recurse_count,$partnum);
			$partnum += scalar @newlines;
			push(@ret_lines,@newlines);
			next;
		} else {
			$shown = "     "; $type = $part->get('Content-Type');
		}
		$size = $self->_bytes_to_readable($part->body->size);
		push(@ret_lines, sprintf('%4s',$partnum)." ".$shown.sprintf('%13s',$size)." ".$type);
	}
	return @ret_lines;
}
sub draw_view
{
	ref(my $self = shift) or croak "instance variable needed";
	my $topline = shift;
	my $first_view = shift;
	my $lines = @{$self->{_current_view_buffer}};

	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	# don't display warning prompts if we just opened the message
	unless ($first_view)
	{
		if ($topline >= $lines)
		{
			$topline = $lines - 1;
			$self->statusmsg("[Already at end of message]");
		} elsif ($topline < 0) {
			$topline = 0;
			$self->statusmsg("[Already at start of message]");
		} elsif ($topline == 0) {
			$self->statusmsg("[Start of message]");
		} else {
			$self->clearprompt()
		}
	}

	my $b = subwin($maxy - 3, $maxx, 0, 0);
	for (my $i = 0; $i < ($maxy - 3); $i++)
	{
		my $curline = $i + $topline;
		if ($curline >= $lines)
		{
			addstr($b,$i,0,(" " x $maxx));
			next;
		}
		addstr($b,$i,0, substr( sprintf('%-*s',
		       $maxx,$self->{_current_view_buffer}[$curline]),0,$maxx) );
	}
	refresh($b);
	return $topline;
}

sub compose_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my $menu = shift;
	my @menu = (
		[	['^G Get Help','^X Send','^R Rich Hdr','^Y PrvPg/Top','^K Cut Line','^O Postpone'],
			['^C Cancel','^D Del Char','^J Attach','^V NxtPg/End','^U UnDel Line','^T To AddrBk'] ],
		[	['^G Get Help','^X Send','^R Rich Hdr','^Y PrvPg/Top','^K Cut Line','^O Postpone'],
			['^C Cancel','^D Del Char','^J Attach','^V NxtPg/End','^U UnDel Line','^T To Files'] ],
		[	['^G Get Help','^X Send','^R Rich Hdr','^Y PrvPg/Top','^K Cut Line','^O Postpone'],
			['^C Cancel','^D Del Char','^J Attach','^V NxtPg/End','^U UnDel Line'] ],
		[	['^G Get Help','^X Send','^R Rich Hdr','^Y Prev Pg','^K Cut Text','^O Postpone'],
			['^C Cancel','^D Del Char','^_ Alt Edit','^V Next Pg','^U UnCut Text','^T To Spell'] ],
		);
	$self->_draw_menu(\@{$menu[$menu]});
}
sub compose
{
	ref(my $self = shift) or croak "instance variable needed";
	my $msg_ref = shift;
	my $base_message = shift;

	$self->clear_win();

	$msg_ref->{'fields'} = [qw(From To Cc Attchmnt Subject data)];
	$msg_ref->{'values'} = [];
	my $cur_field = 0;

	# setup default values based on the passed in message, if available
	if (ref $base_message)
	{
		for (my $i=0; $i < @{$msg_ref->{'fields'}}; $i++)
		{
			my $field = $msg_ref->{'fields'}[$i];
			if ($field eq 'Attchmnt')
			{	# handled differently (not sure how to do this)
			} elsif ($field =~ /^[A-Z]/) {
				# header field (just getting first header field to match)
				my $v = $base_message->head()->get($field);
				$msg_ref->{'values'}[$i] = $v if $v;
			} elsif ($field eq 'data') {
				# body
				$msg_ref->{'values'}[$i] = join '', $base_message->body->lines;
			}
		}
	}

	my @field_to_menu = (0,0,0,1,2,3);
	my $tot_fields = @{$msg_ref->{fields}};

	$self->compose_menu($field_to_menu[$cur_field]);
	while ( my ($rv,$text) = $self->draw_compose($msg_ref,$cur_field) )
	{
		$msg_ref->{'values'}[ $cur_field ] = $text;
		if ($rv eq "")
		{
			$self->yn_menu();
			my $rv2 = $self->prompt_chr("Cancel message (answering \"Yes\" will abandon your mail message) ? ",qr/^[yn]/i);
			$self->clearprompt();
			if ($rv2 =~ /^y/i)
			{	# return to last screen
				return 'back';
			}
		} elsif ($rv eq "") {
			$self->build_msg_hash($msg_ref);
			return 'send';
		} elsif ( ($rv eq KEY_UP) ) {
			if ($cur_field <= 0)
			{
				$cur_field = 0;
			} else {
				$cur_field--;
			}
		} elsif ( ($rv eq KEY_DOWN) || ($rv eq "\n") || ($rv eq "\t") ) {
			if ($cur_field == ($tot_fields - 1))
			{
				$cur_field = 0;
			} else {
				$cur_field++;
			}
		} else {
		}
		$self->compose_menu($field_to_menu[$cur_field]);
	}
}
sub build_msg_hash
{
	ref(my $self = shift) or croak "instance variable needed";
	my $msg_ref = shift;

	# make the new hash
	my %msg;
	for (my $i=0; $i< @{$msg_ref->{fields}}; $i++)
	{
		if ($msg_ref->{fields}[$i] eq 'Attchmnt')
		{	# special handling...
			push(@{$msg{files}},$_) foreach
					split /,/, $msg_ref->{'values'}[$i];
		} else {
			$msg{$msg_ref->{fields}[$i]} = $msg_ref->{'values'}[$i];
		}
	}
	# delete all old keys
	delete $msg_ref->{$_} foreach keys %{$msg_ref};
	# copy stuff in %msg to $msg_ref
	$msg_ref->{$_} = $msg{$_} foreach keys %msg;
}
sub draw_compose
{
	ref(my $self = shift) or croak "instance variable needed";
	my $msg_ref = shift;
	my $cur_field = shift;
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	my $tot_fields = @{$msg_ref->{fields}};

	my $b = subwin( ($tot_fields +1), $maxx, 0, 0);
	my ($rv,$content);
	for (my $i=0; $i<$tot_fields; $i++)
	{
		my $draw_only = ($cur_field == $i) ? 0 : 1;
		# skip drawing the window that get's the focus
		next unless $draw_only;
		if ($msg_ref->{fields}[$i] eq 'data')
		{
			standout($b);
			addstr($b,$i,0,"----- Message Text -----");
			standend($b);
			($rv,$content) = txt_field(
				'window'	=> $self->{curs},
				'xpos'  	=> 0,
				'ypos'  	=> ($i + 2),
				'lines' 	=> ($maxy - $tot_fields - 6),
				'cols'  	=> $maxx,
				'edit'  	=> 0,
				'draw_only'	=> 1,
				'content'	=> $msg_ref->{'values'}[$i],
				'cursor_disable'	=> 1,
				'decorations'	=> 0
				);
		} else {
			addstr($b,$i,0, sprintf('%-8s',$msg_ref->{fields}[$i] ).':');
			addstr($b, " ".$msg_ref->{'values'}[$i].
				(" "x($maxx - length($msg_ref->{'values'}[$i]) - 10)) );
		}
	}

	if ($msg_ref->{fields}[$cur_field] eq 'data')
	{
		standout($b);
		addstr($b,$cur_field,0,"----- Message Text -----");
		standend($b);
		refresh($b);
		($rv,$content) = txt_field(
			'window'	=> $self->{curs},
			'xpos'  	=> 0,
			'ypos'  	=> ($cur_field + 2),
			'lines' 	=> ($maxy - $tot_fields - 5),
			'cols'  	=> $maxx,
#			'edit'  	=> $edit,
			'content'	=> $msg_ref->{'values'}[$cur_field],
			'cursor_disable'	=> 1,
			'regex' 	=> "\t",
			'decorations'	=> 0
			);
	} else {
		addstr($b,$cur_field,0, sprintf('%-8s',$msg_ref->{fields}[$cur_field] ).':');
		refresh($b);
		($rv,$content) = txt_field(
			'window'	=> $self->{curs},
			'xpos'  	=> 10,
			'ypos'  	=> $cur_field,
			'lines' 	=> 1,
			'cols'  	=> $maxx - 13,
			'hz_scroll'	=> 1,
#			'edit'  	=> $edit,
			'content'	=> $msg_ref->{'values'}[$cur_field],
			'cursor_disable'	=> 1,
			'regex' 	=> "\t\n",
			'decorations'	=> 0
			);
	}


	refresh();

	return ($rv,$content);
}

sub clearprompt
{
	ref(my $self = shift) or croak "instance variable needed";
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	my $b = subwin(1, $maxx, $maxy - 3, 0);
	addstr($b,0,0,(" " x $maxx) );
	refresh($b);
}

sub statusmsg
{
	ref(my $self = shift) or croak "instance variable needed";
	my $text = shift;
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	my $b = subwin(1, $maxx, $maxy - 3, 0);

	my ($str,$found);
	until($found)
	{
		my $leftpad = int(($maxx - length($text)) / 2);
		my $rightpad = $leftpad + (($maxx - length($text)) % 2);
		addstr($b,0,0, (" " x $leftpad));
		standout($b);
		addstr($b,$text);
		standend($b);
		addstr($b," " x $rightpad);
		print "\b";
		delwin($b);
		refresh($b);
		return undef;
	}
}

sub prompt_str
{
	ref(my $self = shift) or croak "instance variable needed";
	# Usage: $self->prompt_str("Text Message: ",
	#                          $regexmatch,
	#                          $optionallength,
	#                          $extra_escapechars );
	return $self->prompt($_[0],$_[1],'str',$_[2],$_[3]);
}
sub prompt_chr
{
	ref(my $self = shift) or croak "instance variable needed";
	return $self->prompt($_[0],$_[1],'chr');
}
sub prompt
{
	ref(my $self = shift) or croak "instance variable needed";
	my ($text,$regex,$str_or_chr,$c_limit,$extra_escape_char) = @_;
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	my $b = subwin(1, $maxx, $maxy - 3, 0);
	unless ( ($c_limit =~ /^\d+$/) && ($c_limit > 0) )
	{
		$c_limit = 1;
	}
	$c_limit = 1 if ($str_or_chr eq 'chr');

	standout($b);
	addstr($b,0,0,$text);
	standend($b);
	addstr($b, (" " x ($maxx - length($text))) );
	# put cursor at the right possition
	move($b,0, (length($text) +1) );
	refresh($b);

	unless ($regex)
	{   # just prompt, then return
		beep();
		delwin($b);
		refresh($b);
		return undef;
	}
	my ($rv,$str);
	if ($str_or_chr eq 'chr')
	{	# just grab first character
		until($str =~ /$regex/)
		{
			beep() unless $str == -1;
			$str = getch();
		}
		addstr($b,0, (length($text) +1), $str );
	} else { # grab a string up to <CR>
		($rv,$str) = txt_field(
			window	=> $self->{curs},
			xpos	=> (length($text) +1),
			ypos	=> ($maxy -3),
			lines	=> 1,
			cols	=> ($maxx - length($text) -1),
			hz_scroll	=> 1,
			cursor_disable	=> 1,
			regex	=> "\n$extra_escape_char",
			c_limit	=> $c_limit,
			decorations	=> 0
			);
	}
	chomp($str);
	if (($rv eq "") || ($str =~ //)) {
		delwin($b);
		return "";
	} elsif (length($extra_escape_char) && ($rv =~ /[$extra_escape_char]/)) {
		delwin($b);
		return $str.$rv;
	} elsif ($str =~ /$regex/) {
		delwin($b);
		return $str;
	} else {
		beep();
		delwin($b);
		$self->clearprompt();
		$self->statusmsg("INVALID ENTRY.");
		return undef;
	}
}

sub log
{	# very simple method to log to file ERR in localdir
	ref(my $self = shift) or croak "instance variable needed";
	my $msg = shift;
	my ($pkg,$file,$line) = caller;
	open(MYERR,">> ERR") or die "can't open logfile ERR";
	print MYERR "pkg[$pkg] file[$file] line[$line] $msg\n";
	close MYERR;
}

sub error
{
	ref(my $self = shift) or croak "instance variable needed";
	my $errmsg = shift;
	msg_box( 'message'	=> $errmsg, 'title' => 'Error', 'border' => 'red' );
}

1;
