#!/usr/bin/perl

use strict;
use Curses;
use vars qw(@msgs $current_mbox);
$current_mbox = './inbox';

$SIG{WINCH} = \&redraw_env;

&main;

sub redraw_env
{
	endwin();
	refresh();
}

sub main
{
	initscr(); cbreak(); noecho();
#	 nonl();
#	 intrflush(stdscr, FALSE);
#	 keypad(stdscr, TRUE);

	&parse_mbox($current_mbox);

	eval { keypad(1) };

	my $window = 'msglist';

	while (1)
	{
		my $newwindow;
		if ($window eq 'msglist')
		{
			$newwindow = &msglist;
		} elsif ($window eq 'compose') {
			$newwindow = &compose;
		} else {
			$newwindow = 'msglist';
		}
		$window = $newwindow;
		# clear the window so we can redraw from scratch
		endwin();
	}
}

sub compose
{
	clear();
	my $maxx = getmaxx();
	my $maxy = getmaxy();

	my @elements = (
		["To"],
		["Cc"],
		["Attchmnt"],
		["Subject"]
		);
	my $b = subwin(scalar @elements, $maxx, 0, 0);
	my $i;
	for ($i=0; $i<@elements; $i++)
	{
		addstr($b,$i,0,sprintf('%-*s',8,$elements[$i][0]).":");
	}
	refresh($b);
	addstr($i, 0, "---- Message Text ----");
	refresh();
	sleep 5;
	return 'msglist';
}

sub msglist
{
	clear();
	&draw_menu();
	my $curline = &draw_win(0);

	refresh();

	while (my $ch = getch())
	{
#		addstr(0,0,"YOU TYPED: ");
#		addch($ch);
#		refresh();
#		sleep 5;
		if ($ch eq "n") {
			$curline++;
			$curline = &draw_win($curline);
		} elsif ($ch eq "p") {
			$curline--;
			$curline = &draw_win($curline);
		} elsif ( ($ch eq " ") || ($ch eq KEY_NPAGE) ) {
			$curline += (getmaxy() - 3);
			$curline = &draw_win($curline);
		} elsif ( ($ch eq "-") || ($ch eq KEY_PPAGE) ) {
			$curline -= (getmaxy() - 3);
			$curline = &draw_win($curline);
		} elsif ($ch eq "q") {
			move($LINES - 1, 0);
			refresh();
			endwin();
			exit;
		} elsif ($ch eq "j") {
			my $t = &jump_window();
			$curline = $t if defined $t;
			$curline = &draw_win($curline);
		} elsif ($ch eq "|") {
			my $str = &prompt("Pipe msg to program: ",qr/./);
			endwin();
			my $msg = &get_msg($curline,$current_mbox);
			open(TMP,"> /tmp/oserp.$$") or die "can't make temp file";
			print TMP $msg;
			close(TMP);
			system("cat /tmp/oserp.$$ | $str");
			&prompt("System command returned.");
			refresh();
		} elsif ($ch eq "c") {
			return 'compose';
		} elsif ($ch eq "e") {
			my $str = &prompt("checkkey: ",qr/./);
			addstr(1,1,"   [$str]   ");
			if ($str eq "")
			{
				addstr(2,1,"    [yep]    ");
			} else {
				addstr(2,1,"    [nope]    ");
			}
			refresh();
			sleep 2;
		}
		refresh();
	}
}

sub get_msg
{
	my $msgid = shift;
	my $inbox = shift;
	my $count = 0;
	my $msg;
	open(INB,"< $inbox") or die "can't open inbox[$inbox]";
	MSG: while(<INB>)
	{
		next unless /^From\s/;
		if ($msgid == $count)
		{	# found message
			$msg .= $_;
			while(<INB>)
			{
				last MSG if /^From\s/;
				$msg .= $_;
			}
		}
		$count++;
	}
	close INB;
	return $msg;
}

sub jump_window
{
	my $str = &prompt("Message number to jump to: ",qr/^\d+$/);
	$str =~ s/\D//g;
	return $str ? $str : undef;
}

sub prompt
{
	my ($text,$regex) = @_;
	my $maxx = getmaxx();
	my $maxy = getmaxy();
	my $b = subwin(1, $maxx, $maxy - 3, 0);
	standout($b);

	my ($str,$found);
	until ($found)
	{
		addstr($b,0,0,$text . (" " x ($maxx - length($text))) );
		move($b,0, length($text)+1);
		echo();
		refresh($b);
		unless ($regex)
		{	# just prompt, then return
			sleep 2;
			standend($b); delwin($b);
			return undef;
		}
		my $str;
		getstr($b,$str);
		noecho();
		if ($str eq "")
		{	# hit escape
			standend($b); delwin($b);
			return undef;
		} elsif ($str =~ /$regex/) {
			standend($b); delwin($b);
			return $str;
		} else {
			addstr($b,0,0, " " x $maxx);
			addstr($b,0,0, "INVALID ENTRY");
			refresh($b);
			sleep 2
		}
	}
}

sub draw_win
{
	my $curline = shift;
	my $maxx = getmaxx();
	my $maxy = getmaxy();
	my $display_maxy = $maxy - 3;

	my $b = subwin($display_maxy, $maxx, 0, 0);
	my $beginline = 0;
	my $max_msgid = @msgs;
	if ($curline >= $max_msgid)
	{
		$curline = $max_msgid - 1;
	} elsif ($curline <= 0) {
		$curline = 0;
	}
	if ($curline >= $display_maxy)
	{
		$beginline = $curline - $display_maxy + 1;
	}
	for (my $i = 0; $i < $display_maxy; $i++)
	{
		my ($mon,$day,$status,$from,$subject) = @{$msgs[$i + $beginline]};
		my $marker = ($curline == ($i+$beginline)) ? "->" : "  ";
#		addstr($b,$i,0,$marker ."[$i][$beginline][$curline][$display_maxy]");
		addstr($b,$i,0,$marker);
		addstr($b,sprintf('%-*s',3,$status));
		addstr($b,sprintf('%*s',(length($max_msgid)),$i + $beginline)." ");
		addstr($b,sprintf('%-*s',4,$mon));
		addstr($b,sprintf('%*s',2,$day)." ");
		addstr($b, substr(sprintf('%-*s',20,$from),0,20) . " " );
#		addstr( "(".substr(sprintf('%-*s',6,$size),0,6).")" );
		my $restlength = $maxx - (2+3+length($max_msgid)+1+4+3+20);
		$restlength--;
		addstr($b, substr(sprintf('%-*s',$restlength,$subject),0,$restlength) );
	}
	refresh($b);
	return $curline;
}

sub draw_menu
{
	my $maxx = getmaxx();
	my $maxy = getmaxy();
	my $b = subwin(2, $maxx, $maxy - 2, 0);

	standout($b); addstr($b,0,0,"?"); standend($b);
	addstr($b," Help       ");
	standout($b); addstr($b,"<"); standend($b);
	addstr($b," FldrList  ");
	standout($b); addstr($b,"P"); standend($b);
	addstr($b," PrevMsg ");
	standout($b); addstr($b,"  -"); standend($b);
	addstr($b," PrevPage ");
	standout($b); addstr($b,"D"); standend($b);
	addstr($b," Delete   ");
	standout($b); addstr($b,"R"); standend($b);
	addstr($b," Replay  ");

	standout($b); addstr($b,1,0,"O"); standend($b);
	addstr($b," OTHER CMDS ");
	standout($b); addstr($b,">"); standend($b);
	addstr($b," [ViewMsg] ");
	standout($b); addstr($b,"N"); standend($b);
	addstr($b," NextMsg ");
	standout($b); addstr($b,"Spc"); standend($b);
	addstr($b," NextPage ");
	standout($b); addstr($b,"U"); standend($b);
	addstr($b," Undelete ");
	standout($b); addstr($b,"F"); standend($b);
	addstr($b," Forward");

	refresh($b);
#? Help       < FldrList   P PrevMsg       - PrevPage D Delete     R Reply      
#O OTHER CMDS > [ViewMsg]  N NextMsg     Spc NextPage U Undelete   F Forward   
}


sub parse_mbox
{
	my $inbox = shift;
	open(INB,"< $inbox") or die "can't open inbox[$inbox]";
	my ($msgnum);
	MSG: while(<INB>)
	{
		if (/^From\s/)
		{
			my ($mon,$day,$status,$from,$subject);
			while (<INB>)
			{
				if (/^$/)
				{
					$msgs[$msgnum] = [$mon,$day,$status,$from,$subject];
					$msgnum++;
					next MSG;
				} elsif (/^Date:\s+\D*(\d+)\s+(\S+)/i) {
					$day = $1; $mon = $2;
				} elsif (/^From:\s+(\S.+)$/i) {
					$from = $1; chomp($from);
				} elsif (/^Subject:\s(\S.*)$/i) {
					$subject = $1; chomp($subject);
				} elsif (/^Status:\s(\S.*)$/i) {
					$status = $1; chomp($status);
				}
			}
		}
	}
	close(INB);
}

END {
	# restore tty state to normal
	endwin();
}
