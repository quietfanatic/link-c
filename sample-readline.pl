use v6;
use Link::C;
Link::C::link <libreadline readline/readline.h>, :link(<rl_initialize readline>), :import(*);

rl_initialize;
while my $line = readline "Flip: " {
	say $line.flip;
}
