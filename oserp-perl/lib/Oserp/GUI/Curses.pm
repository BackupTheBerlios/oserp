package Oserp::GUI::Curses;

#########################################
# ncurses interface for oserp libraries #
#########################################

use 5.00503;
use strict;
use Carp;
use Curses;
use Curses::Widgets qw(:all);
use vars qw($VERSION);

$VERSION = sprintf "%d.%03d", q$Revision: 1.1 $ =~ /(\d+)/g;

# handle redrawing the window when size changes:
$SIG{WINCH} = \&redraw_evn;

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

	my $curs = new Curses;
	$self->{curs} = $curs;

	initscr(); cbreak(); noecho();
	halfdelay(5); # set timeout, so widgets can call functions periodically
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
		}
	}
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

	$self->list_menu($menu);

	refresh();

	my $last_msg = (scalar $folder->messages) - 1;
	my $curline = $self->draw_list($last_msg);

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
		} elsif ( ($ch eq '<') || ($ch eq ',') ) {
			return 'back';
		} elsif ( ($ch eq "\n") || (lc($ch) eq 'v') || ($ch eq '.') ) {
			my $nextline = $self->view($curline);
			$curline = $self->draw_list($nextline);
		}
		refresh();
	}
}

sub draw_list
{
	ref(my $self = shift) or croak "instance variable needed";
	my $curline = shift;
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();

	my $folder = $self->{_current_folder};
	my $msgs_per_page = $maxy - 3;
	my $num_of_msgs = $self->{_current_folder}->messages;
	if ($curline >= $num_of_msgs)
	{
		$curline = $num_of_msgs - 1;
	} elsif ($curline <= 0) {
		$curline = 0;
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
		unless ($folder->message($i+$beginline))
		{
			addstr($b,$i,0,(" " x $maxx));
			next;
		}
		addstr($b,$i,0,$marker);
		my $status;
		addstr($b,sprintf('%-*s',3,$status));
		# msg number
		addstr($b,sprintf('%*s',(length($num_of_msgs)),$i + $beginline)." ");
		my $date = $folder->message($i+$beginline)->date;
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
			$folder->message($i+$beginline)->get('From')),0,20) . " " );
#		addstr( "(".substr(sprintf('%-*s',6,$size),0,6).")" );
		my $restlength = $maxx - (2+3+length($num_of_msgs)+1+4+3+20);
		$restlength--;
		addstr($b, substr(sprintf('%-*s',$restlength,
			$folder->message($i+$beginline)->subject),0,$restlength) );
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
		$self->prompt("[Already on last message]");
	} elsif ($msgnum < 0) {
		$msgnum = 0;
		$self->prompt("[Already on first message]");
	}

	my $message = $folder->message($msgnum);
	my $date = $message->date;
	my $from = $message->get('From');
	my @to = $message->to;
	my @tos = map { $_->format() } @to;
	my $to = join(',',@tos);
	my @cc = $message->cc;
	my @ccs = map { $_->format() } @cc;
	my $cc = join(',',@ccs);
	my $subject = $message->subject;

	$self->view_menu($menu);

	refresh();

	$self->{_current_view_buffer} = [];
	push(@{$self->{_current_view_buffer}},"Date: $date");
	push(@{$self->{_current_view_buffer}},"From: $from");
	push(@{$self->{_current_view_buffer}},"To: $to");
	push(@{$self->{_current_view_buffer}},"Cc: $cc");
	push(@{$self->{_current_view_buffer}},"Subject: $subject");
	push(@{$self->{_current_view_buffer}},"");
	push(@{$self->{_current_view_buffer}},$message->decoded->lines);
	my $curline = $self->draw_view(0);

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
		}
		refresh();
	}
}
sub draw_view
{
	ref(my $self = shift) or croak "instance variable needed";
	my $topline = shift;
	my $lines = @{$self->{_current_view_buffer}};
	open(TMP,"> /tmp/test$$");
	foreach my $line (@{$self->{_current_view_buffer}})
	{
		print TMP $line . "\n";
	}
	close(TMP);
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	if ($topline >= $lines)
	{
		$topline = $lines - 1;
		$self->prompt("[Already at end of message]");
	} elsif ($topline < 0) {
		$topline = 0;
		$self->prompt("[Already at start of message]");
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

sub prompt
{
	ref(my $self = shift) or croak "instance variable needed";
	my ($text,$regex) = @_;
	my $maxx = $self->{curs}->getmaxx();
	my $maxy = $self->{curs}->getmaxy();
	my $b = subwin(1, $maxx, $maxy - 3, 0);
	standout($b);

	my ($str,$found);
	until($found)
	{
		addstr($b,0,0,$text . (" " x ($maxx - length($text))) );
		move($b,0, length($text)+1);
		echo();
		refresh($b);
		unless ($regex)
		{   # just prompt, then return
			noecho();
			sleep 2;
			print "\b";
			standend($b); delwin($b);
			return undef;
		}
		my $str;
		getstr($b,$str);
		noecho();
		if ($str eq "^[")
		{   # hit escape
			standend($b); delwin($b);
			return undef;
		} elsif ($str =~ /$regex/) {
			standend($b); delwin($b);
			return $str;
		} else {
			print "\b";
			addstr($b,0,0, " " x $maxx);
			addstr($b,0,0, "INVALID ENTRY");
			refresh($b);
			sleep 2;
		}
	}
}

sub error
{
	ref(my $self = shift) or croak "instance variable needed";
	my $errmsg = shift;
	msg_box( 'message'	=> $errmsg, 'title' => 'Error', 'border' => 'red' );
}

1;
