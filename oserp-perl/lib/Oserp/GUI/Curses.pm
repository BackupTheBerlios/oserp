package Oserp::GUI::Curses;

#########################################
# ncurses interface for oserp libraries #
#########################################

use 5.00503;
use strict;
use Carp;
use Curses;
use Curses::Widgets qw(:all);
use POSIX qw(:termios_h);
use vars qw($VERSION);

$VERSION = sprintf "%d.%03d", q$Revision: 1.4 $ =~ /(\d+)/g;

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
	my $termio = POSIX::Termios->new;
	$termio->getattr(fileno(STDIN));
	my $intrid = $termio->getcc(VINTR);
	$self->{_saved_term} = $intrid;
	$termio->setcc(VINTR, '');
	$termio->setattr(1,TCSANOW);

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
	endwin();
	clear();
}

sub quit
{	# cleanup anything we have laying around
	# TODO need to somehow restore VINTR, cause this isn't working
	ref(my $self = shift);
	my $termio = POSIX::Termios->new;
	$termio->getattr(fileno(STDIN));
	if ( (ref($self)) && $self->{_saved_term} )
	{	# restore the SIGINT
		$termio->setcc(VINTR, ord( $self->{_saved_term} ) );
	} else {	# restore SIGINT to CTRL-C
		$termio->setcc(VINTR, ord( '' ) );
	}
	$termio->setattr(1,TCSANOW);
	clear();
	refresh();
	endwin();
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

	while (my $ch = getch())
	{
		if ((lc($ch) eq 'n') || ($ch eq KEY_DOWN)) {
			$curline++;
			$curline = $self->draw_list($curline);
		} elsif ((lc($ch) eq 'p') || ($ch eq KEY_UP)) {
			$curline--;
			$curline = $self->draw_list($curline);
		} elsif ( ($ch eq " ") || ($ch eq KEY_NPAGE) ) {
			$curline += ($self->{curs}->getmaxy() - 3);
			$curline = $self->draw_list($curline);
		} elsif ( ($ch eq "-") || ($ch eq KEY_PPAGE) ) {
			$curline -= ($self->{curs}->getmaxy() - 3);
			$curline = $self->draw_list($curline);
		} elsif (lc($ch) eq 'q') {
			return 'quit';
		} elsif (lc($ch) eq 'o') {
			$menu = ($menu >= $max_menu) ? 0 : ($menu + 1);
			$self->list_menu($menu);
		} elsif (lc($ch) eq 'j') {
			my $rv = $self->prompt("Message number to jump to : ",qr/^\d+$/);
			$curline = $rv if defined $rv;
			$curline = $self->draw_list($curline);
		} elsif ( ($ch eq '<') || ($ch eq ',') ) {
			return 'back';
		} elsif ( ($ch eq "\n") || (lc($ch) eq 'v') || ($ch eq '.') ) {
			my $nextline = $self->view($curline);
			return 'compose' if ($nextline eq 'compose');
			$curline = $self->draw_list($nextline);
		} elsif (lc($ch) eq 'c') {
			return 'compose';
		} elsif ( (time() - $self->{_last_mail_check}) > $self->{_check_mail_delay}) {
			# TODO need a way to check for new messages.
			# I don't know how to do it with Mail::Box
			# return "checkmail";
		}
		refresh();
	}
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
		my $marker = ($curline == ($i+$beginline)) ? "->" : "  ";
		my $message;
		unless ($message = $folder->message($i+$beginline))
		{
			addstr($b,$i,0,(" " x $maxx));
			next;
		}
		addstr($b,$i,0,$marker);
		my $status;
		addstr($b,sprintf('%-*s',3,$status));
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
#		addstr( "(".substr(sprintf('%-*s',6,$size),0,6).")" );
		my $restlength = $maxx - (2+3+length($num_of_msgs)+1+4+3+20);
		$restlength--;
		addstr($b, substr(sprintf('%-*s',$restlength,
			$message->subject),0,$restlength) );
	}
	refresh($b);
	return $curline;
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
	my $date = $message->date;
	my $from = $message->get('From');
#	my @to = $message->to;
#	my @tos = map { $_->format() } @to;
	my @to = split(/\n/,  join(",\n          ",
	                           map { $_->format() } $message->to
	              )           );
#	my @cc = $message->cc;
#	my @ccs = map { $_->format() } @cc;
	my @cc = split(/\n/,  join(",\n          ",
	                           map { $_->format() } $message->cc
	              )           );
	my $subject = $message->subject;

	$self->view_menu($menu);

	refresh();

	$self->{_current_view_buffer} = [];
	push(@{$self->{_current_view_buffer}},"Date    : $date");
	push(@{$self->{_current_view_buffer}},"From    : $from");

#	my $init_toline = "To      : ". shift @tos;
#	$init_toline .= "," if @tos;
#	push(@{$self->{_current_view_buffer}},$init_toline);
#	push(@{$self->{_current_view_buffer}},"          $_") foreach @tos;

#	my $init_ccline = "Cc      : ". shift @ccs;
#	$init_ccline .= "," if @ccs;
#	push(@{$self->{_current_view_buffer}},$init_ccline);
#	push(@{$self->{_current_view_buffer}},"          $_") foreach @ccs;

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
			return 'compose';
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
		$size = int($part->body->size / 1024) . " K    ";
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
		$size = int($part->body->size / 1024) . " K    ";
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

	$msg_ref->{'fields'} = [qw(From To Cc Attchmnt Subject data)];
	$msg_ref->{'values'} = [];
	my $cur_field = 0;

	my @field_to_menu = (0,0,0,1,2,3);
	my $tot_fields = @{$msg_ref->{fields}};

	$self->compose_menu($field_to_menu[$cur_field]);
	while ( my ($rv,$text) = $self->draw_compose($msg_ref,$cur_field) )
	{
		$msg_ref->{'values'}[ $cur_field ] = $text;
		if ($rv eq "")
		{
			my $rv = &prompt("Cancel message (answering \"Yes\" will abandon your mail message) ?",qr/^[yn]/i);
			if ($rv =~ /^y/i)
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

sub prompt
{
	ref(my $self = shift) or croak "instance variable needed";
	my ($text,$regex) = @_;
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	my $b = subwin(1, $maxx, $maxy - 3, 0);

	standout($b);
	addstr($b,0,0,$text);
	standend($b);
	addstr($b, (" " x ($maxx - length($text))) );
	# put cursor at the right possition
	move($b,0, (length($text) +1) );
	echo();
	refresh($b);

	unless ($regex)
	{   # just prompt, then return
		noecho();
		print "\b";
		delwin($b);
		refresh($b);
		return undef;
	}
	my $str;
	getnstr($b,$str,10);
	noecho();
	if ($str eq "")
	{   # hit escape
		delwin($b);
		return undef;
	} elsif ($str =~ /$regex/) {
		delwin($b);
		return $str;
	} else {
		beep();
		delwin($b);
		$self->clearprompt();
		$self->statusmsg("INVALID ENTRY.");
	}
}

sub error
{
	ref(my $self = shift) or croak "instance variable needed";
	my $errmsg = shift;
	msg_box( 'message'	=> $errmsg, 'title' => 'Error', 'border' => 'red' );
}

1;
