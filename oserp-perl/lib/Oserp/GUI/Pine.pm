package Oserp::GUI::Pine;

=head1 NAME

Oserp::GUI::Pine

=head1 DESCRIPTION

pine interface for oserp libraries

=cut

use 5.00503;
use strict;
use Carp;
use Curses;
use Curses::Widgets qw(:all);
use POSIX qw(:termios_h);
use vars qw($VERSION);

$VERSION = sprintf "%d.%03d", q$Revision: 1.2 $ =~ /(\d+)/g;

sub redraw_env
{
	endwin();
	refresh();
}

=head1 new()

Creates a new gui object.

When this exits, the program exits. This starts set's up the environment, and calls the main() loop.

=cut

sub new
{
	my ($this) = shift;
	my $class = ref($this) || $this;

	my $oserp = shift;
	die "Oserp object not passed in" unless $oserp;

	my $self = { oserp => $oserp };
	bless($self, $class);

	# TODO: might want to do config checks here

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
	{ # setup curses stuff
		my $curs = new Curses;
		$self->{curs} = $curs;
		initscr(); cbreak(); noecho();
		leaveok(1); # ok to leave cursor whereever, and not draw it
		raw(); # don't allow term to interpret CTRL-C and other escape chars
		# halfdelay is how long we'll wait in tenths of seconds for a
		# character to be entered before we loop out, and do things
		# like check for e-mail and stuff
		halfdelay(50); # set timeout, so widgets can call functions periodically
		eval { keypad(1) };
	}

	# do we need to do an initial config?
	unless ($self->{oserp}->config_get("alt-addresses"))
	{
		$self->initial_config();
	}

	$self->main();
	return $self;
}

=head1 initial_config()

prompts user for initial config

=cut

sub initial_config
{
	ref(my $self = shift) or croak "instance variable needed";
	$self->statustop("INITIAL CONFIGURATION","[none]","?");
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	my $b = subwin($maxy - 4, $maxx, 1, 1);
	addstr($b,1,2, "Welcome to Oserp");
	addstr($b,3,2, "Initial Configuration");
	addstr($b,5,2, "Please edit ~/.oserprc to configure oserp");
	refresh($b);
	my $rv = $self->prompt_chr("Press any key to continue : ", qr/^.$/);
#	my $from = $self->prompt_str("Press enter to continue : ", qr/^[A-Za-z0-9`~!\@#\$\%^\&\*()\[\]_\-=+\{\}\|\\;:'",\.\<\>\/\?\s^C]{2,}$/, 127);
#	$self->{oserp}->config_set("alt-addresses",$from);
	$self->clearprompt();
}

=head1 main()

Main loop in gui.

=cut

sub main
{
	ref(my $self = shift) or croak "instance variable needed";
	# we loop, setting curscreen to whatever screen we're going to next
	# TODO: will want to handle skipping ahead to message list, or 
	#       folder list, etc, based on oserp command line opts.
	my @curscreen = ('mainscreen');
	my $true = 1;
	while ($true)
	{
		my $nextscreen;
		if ($curscreen[0] eq 'mainscreen') {
			$nextscreen = $self->mainscreen();
		} elsif ($curscreen[0] eq 'compose') {
			my $statusmsg = $self->composemsg();
			$self->statusmsg($statusmsg);
			shift @curscreen;
			$nextscreen = shift @curscreen;
		} elsif ($curscreen[0] eq 'back') {
			shift @curscreen; shift @curscreen;
			$nextscreen = shift @curscreen;
		} elsif ($curscreen[0] eq 'list') {
			$nextscreen = $self->list_collections();
		} elsif ($curscreen[0] eq 'threadlist') {
		} elsif ($curscreen[0] eq 'addressbook') {
		} elsif ($curscreen[0] eq 'quit') {
			$self->quit();
			$true = 0;
		} else {
			$nextscreen = $self->mainscreen();
		}
		unshift(@curscreen,$nextscreen);
		# only keep X number of entries in the stack
		while (@curscreen > 20)
		{   # pop off entries into the nothingness
			pop(@curscreen);
		}
		# clear the window so we can redraw from scratch
		$self->clear_win();
	}
}

=head1 mainscreen()

Prints out the initial screen

=cut

sub main_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my $menu = shift;
	my @menu = (
		[	['? Help','','P PrevCmd','R RelNotes'],
			['O OTHER CMDS','> [ListFlds]','N NextCmd','K KBLock']  ],
		[	['? Help','Q Quit Oserp','L ListFldrs','I Index','S Setup','# Role'],
			['O OTHER CMDS','C Compose','G GotoFldr','J Journal','A AddrBook']   ],
		);
	$self->_draw_menu($menu[$menu]);
}
sub mainscreen
{
	ref(my $self = shift) or croak "instance variable needed";
	$self->clear_win();
	my @buttons = (
		'?     HELP               - Get help using oserp            ',
		'C     COMPOSE MESSAGE    - Compose and send a message      ',
		'I     MESSAGE INDEX      -  View messages in current folder',
		'L     FOLDER LIST        -  Select a folder to view        ',
		'A     ADDRESS BOOK       -  Update address book            ',
		'S     SETUP              -  Configure Oserp Options         ',
		'Q     QUIT               -  Leave the Oserp program         '
		);

	my $cur_opt = 3;
	my $cur_menu = 0;
	my $loop = 1;
	while ($loop)
	{
		$self->main_menu($cur_menu);
		$self->statustop("MAIN MENU","[none]","?");
		my ($key,$button) = buttons(
			'window'	=> $self->{curs},
			'buttons'	=> \@buttons,
			'active_button'	=> $cur_opt,
			'ypos'	=> 3,
			'xpos'	=> 8,
			'vertical'	=> 1,
			'regex'	=> qr/[\?PpRrOo\>\.NnKkQqLlIiSs\#CcGgJjAa\n]/
			);
		$self->{curs}->erase();
		if (($key eq "\n") || ($key =~ /[\>\.]/)) # ENTER OPTION
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
		} elsif (lc($key) eq 'o') { # NEXT MENU
			$cur_menu = ($cur_menu >= 1) ? 0 : 1;
		} elsif (lc($key) =~ /[grkas#i]/i) { # NOT IMPLEMENTED
			$self->statusmsg("Key[$key] not implemented yet.");
		} elsif (lc($key) eq 'p') { # PREV
			$cur_opt--;
			$cur_opt = ($cur_opt <= 0) ? 0 : $cur_opt;
		} elsif (lc($key) eq "n") {	# NEXT
			$cur_opt++;
			$cur_opt = ($cur_opt >= scalar(@buttons)) ?
			                     (scalar(@buttons) - 1) :
			                     $cur_opt;
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
	return 'quit';
}

=head1 list_collections()

Lists all folder collections Oserp knows about

=cut

sub list_collections_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my $menu = shift;
	my @menu = (
		[	['? Help','< Main Menu','P PrevCltn','- PrevPage'],
			['O OTHER CMDS','> [View Cltn]','N NextCltn','Spc NextPage','W WhereIs']  ],
		[	['? Help','Q Quit Oserp','I CurIndex','% Print'],
			['O OTHER CMDS','G GotoFldr','C Compose','# Role']  ]
		);
	$self->_draw_menu($menu[$menu]);
}
sub list_collections
{
	ref(my $self = shift) or croak "instance variable needed";

	$self->clear_win();

	my $folders = $self->{oserp}->folders();
	my @buttons;
	for (my $i=0; $i<@{$folders}; $i++)
	{
		push(@buttons,"$folders->[$i]{collection_name}\n    $folders->[$i]{collection_description}");
	}
	# TODO: buttons() widget doesn't like multiline buttons.
	#       we should come up with our own widgets.
	push(@buttons,"");

	my $cur_opt = 0;
	my $cur_menu = 0;
	my $loop = 1;
	while ($loop)
	{
		$self->list_collections_menu($cur_menu);
		$self->statustop("COLLECTIONS LIST","[none]","?");
		my ($key,$button) = buttons(
			'window'	=> $self->{curs},
			'buttons'	=> \@buttons,
			'active_button'	=> $cur_opt,
			'ypos'	=> 3,
			'xpos'	=> 4,
			'vertical'	=> 1,
			'regex'	=> qr/[\n\?\<\,Pp\-Oo\>\.Nn\ WwQqIi\%GgCc\#]/
			);
		$self->{curs}->erase();
		if (($key eq "\n") || ($key =~ /[\>\.]/)) # ENTER FOLDER
		{	# did they select via arrows, or letters
			my $rv = $self->list_folders($button);
			$self->clear_win();
			return $rv if ($rv eq 'quit');
			return $rv if ($rv eq 'main');
		} else {
			if (lc($key) eq "n")
			{	# NEXT
				$cur_opt++;
				$cur_opt = ($cur_opt >= scalar(@buttons)) ?
				                     (scalar(@buttons) - 1) :
				                     $cur_opt;
				$self->clearprompt();
			} elsif (lc($key) eq "p") { # PREV
				$cur_opt--;
				$cur_opt = ($cur_opt <= 0) ? 0 : $cur_opt;
				$self->clearprompt();
			} elsif ($key =~ /[\<\,]/) { # BACK
				$loop = 0;
			} elsif (lc($key) eq "q") { # QUIT
				return 'quit';
			} elsif (lc($key) eq "o") { # NEXT MENU
				$self->clearprompt();
				$cur_menu = ($cur_menu >= 1) ? 0 : 1;
			} elsif ($key =~ /[\ \-wgi\%\#]/i) { # NOT IMPLEMENTED YET
				$self->statusmsg("Key[$key] not implemented yet.");
			} elsif (lc($key) eq "c") {
				my $statusmsg = $self->composemsg();
				$self->clear_win();
				$self->statusmsg($statusmsg);
			}
		}
	}
	return 'back';
}

=head1 list_folders()

Lists all folders in a given folder collection

=cut

sub list_folders_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my $menu = shift;
	my @menu = (
		[	['? Help','< ClctnList','P PrevFldr','- PrevPage','A Add','R Rename'],
			['O OTHER CMDS','> [View Fldr]','N NextFldr','Spc NextPage','D Delete','W WhereIs']  ],

		[	['? Help','Q Quit Oserp','I CurIndex','% Print','; Select'],
			['O OTHER CMDS','M Main Menu','G GotoFldr','C Compose','Z ZoomMode',': SelectCur']  ],

		[	['? Help','$ Shuffle'],
			['O OTHER CMDS','# Role']  ]
		);
	$self->_draw_menu($menu[$menu]);
}
sub list_folders
{
	ref(my $self = shift) or croak "instance variable needed";
	my $folder_nr = shift;

	$self->clear_win();

	my $folders = $self->{oserp}->folders();
	my @folder_names;
	for (my $i=0; $i<@{$folders->[$folder_nr]{folders}}; $i++)
	{
		push(@folder_names, $folders->[$folder_nr]{folders}[$i]{folder_name});
	}

	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();

	my $title_full;
	{
		my $collection_name = $folders->[$folder_nr]{collection_name};
		my $title_lpad = " " x int(($maxx - length($collection_name))/2);
		my $title_rpad = " " x ($maxx - length($collection_name) - length($title_lpad));
		$title_full = $title_lpad.$collection_name.$title_rpad;
	}

	my $cur_menu = 0;
	my $max_menu = 2;

	my $loop = 1;
	while ($loop)
	{
		$self->list_folders_menu($cur_menu);
		$self->statustop("FOLDERS LIST","[none]","?");
		# add collection name title
		addstr(2,0,$title_full);
		addstr(3,0,("-" x $maxx));
		my ($key,$button) = &flow_buttons(
			curs	=> $self->{curs},
			height	=> ($maxy - 8),
			width	=> $maxx,
			y	=> 5,
			x	=> 0,
			list	=> \@folder_names,
			selected	=> 0,
			'next'	=> 'nN',
			'prev'	=> 'pP',
			regex	=> "\nQqOo<>,.",
			);
		if (lc($key) eq 'q') # QUIT
		{
			return 'quit';
		} elsif ( ($key eq '<') || ($key eq ',') ) { # BACK
			$loop = 0;
		} elsif (lc($key) eq 'o') { # MENU CHANGE
			$self->clearprompt();
			$cur_menu = ($cur_menu >= $max_menu) ? 0 : ($cur_menu +1);
		} elsif (lc($key) eq 'm') { # MAIN MENU
			return 'main';
		} elsif (lc($key) eq 'c') { # COMPOSE
			my $statusmsg = $self->composemsg();
			$self->clear_win();
			$self->statusmsg($statusmsg);
		} elsif (lc($key) =~ /\?adrwi\%zg\$\#/i) { # NOT IMPLEMENTED
			$self->statusmsg("Key[$key] not implemented yet.");
		} elsif (($key eq "\n") || ($key eq '>') || ($key eq '.')) { # MESSAGE LIST
			$self->list_messages($folder_nr,$button); # (collection,folder)
			$self->clear_win();
		}
	}
	return 'back';
}

=head1 list_messages()

Lists all messages in a folder.

Options: 

    folder => 'folder to list', # required
    msgnum => 'message number to select/starton',

=cut

sub list_messages
{
	ref(my $self = shift) or croak "instance variable needed";
}

sub list_messages_draw
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


=head1 composemsg()

The message composer screen for new messages. This calles compose($msg_ref) to do most of the work, and sends off the message after it get's that back.

=cut

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
		if ($self->{oserp}->send_msg($msg_ref))
		{
			return "[Message sent and copied to \"sent-mail\".]";
		} else {
			return "[Message send failed!]";
		}
	}
}


=head1 clear_win()

remove past screen contents.

=cut

sub clear_win
{
	ref(my $self = shift) or croak "instance variable needed";
	clear($self->{curs});
    refresh($self->{curs});
#   endwin();
}

=head1 quit()

cleanup anything we have laying around and clear the screen.

=cut

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
			$termio->setcc(VINTR, ord( '^C' ) );
		}
		$termio->setattr(fileno(STDIN),TCSANOW);
	}
}

=head1 Internal methods

These just help out with repetitive opperations

    _draw_menu( \@rows );
	yn_menu()
	_bytes_to_readable()
	statusmsg()
	clearprompt()
    prompt_str()
    prompt_chr()
	prompt()
	error()
=cut

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

sub yn_menu
{
	ref(my $self = shift) or croak "instance variable needed";
	my @menu = (
		[   ['','Y Yes'],
		    ['^C Cancel','N [No]'] ]
		);
	$self->_draw_menu(\@{$menu[0]});
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

	my $leftpad = int(($maxx - length($text)) / 2);
	my $rightpad = $leftpad + (($maxx - length($text)) % 2);
	addstr($b,0,0, (" " x $leftpad));
	standout($b);
	addstr($b,$text);
	standend($b);
	addstr($b," " x $rightpad);
	beep();
	delwin($b);
	refresh($b);
	return undef;
}

sub statustop
{
	ref(my $self = shift) or croak "instance variable needed";
	my ($section,$folder,$messages) = @_;
	my $maxx = $self->{curs}->getmaxx();
	my $b = subwin(1, $maxx, 0, 0);

	my $firststr = " Oserp ".$self->{oserp}->VERSION." ";
	my $laststr = " Folder: $folder $messages Messages ";
	my $m_len = $maxx - length($firststr) - length($laststr);
	my $middlestr;
	if ($m_len)
	{
		$middlestr = substr( sprintf('%-*s',$m_len,$section), 0, $m_len);
	}

	standout($b);
	addstr($b,0,0,$firststr.$middlestr.$laststr);
	standend($b);
	delwin($b);
	refresh($b);
	return undef;
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
	# Usage: my $chr = $self->prompt_chr("Text Message: ",
	#                                    $regexmatch);
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
		$str = -1;
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
		$self->error("Invalid Entry.");
		return undef;
	}
}

sub flow_buttons
{
	my %opts = @_;
	$opts{selected} = 0 unless ($opts{selected} =~ /^\d+$/);
	$opts{selected} = @{$opts{list}} if (scalar(@{$opts{list}}) < $opts{selected});
	my $nextkeys = $opts{'next'};
	my $prevkeys = $opts{'prev'};
	my $escape = $opts{regex};

	my $win = subwin($opts{height},$opts{width},$opts{y},$opts{x});

	my $max_button_length;
	foreach my $label (@{$opts{list}})
	{
		$max_button_length = length($label) if (length($label) > $max_button_length);
	}
	my $columns = int($opts{width} / ($max_button_length +1));
	$columns = 1 unless $columns; # catch the overflow
	my $maxw = ($max_button_length > $opts{width}) ? $opts{width} : $max_button_length;
	my $padding = (($opts{width} - ($columns * $maxw)) / $columns);

	my $key = -1;
	while ($key == -1)
	{
		my $row = 0; my $col = 0;
		for (my $i=0; $i<@{$opts{list}}; $i++)
		{
			my $label = substr($opts{list}->[$i], 0, $maxw);
			my $extrapadding = $maxw - length($label);
			standout($win) if $opts{selected} == $i;
			addstr($win,$row,$col,$label);
			standend($win) if $opts{selected} == $i;
			addstr($win, (" " x ($extrapadding + $padding)) );
			$col += ($max_button_length + $padding);
			if ( ($col + $max_button_length) > $opts{width}) 
			{	# next button goes on next row
				$row++;
				$col = 0;
			}
			last if ($row > $opts{height}); # too many rows
		}
		refresh($win);

		$key = getch();

		next if ($key == '-1');

		# Hack for broken termcaps
		$key = KEY_BACKSPACE if ($key eq "\x7f");
		if ($key eq "\x1b") {
			$key .= $win->getch();
			$key .= $win->getch();
		}
		$key = KEY_HOME if ($key eq "\x1bOH");
		$key = KEY_END if ($key eq "\x1bOF");

		if ( ($key eq KEY_RIGHT) || ($key eq KEY_DOWN) || ($key =~ /[$nextkeys]/) ) { # NEXT
			$opts{selected}++;
			$opts{selected} = (scalar(@{$opts{list}}) -1) if ( (scalar(@{$opts{list}}) -1) < $opts{selected});
		} elsif ( ($key eq KEY_LEFT) || ($key eq KEY_UP) || ($key =~ /^[$prevkeys]$/) ) { # PREV
			$opts{selected}--;
			$opts{selected} = 0 if ($opts{selected} < 0);
		} elsif ( $key =~ /^[$escape]$/ ) {
			clear($win);
			refresh($win);
			delwin($win);
			return ($key,$opts{selected});
		}
		$key = -1;
	}
}



sub error
{
	ref(my $self = shift) or croak "instance variable needed";
	my $errmsg = shift;
	msg_box( 'message'  => $errmsg, 'title' => 'Error', 'border' => 'red' );
}

1;
