use v6;
use Link::C;
Link::C::link <libcrypt.so crypt.h>;
say C::crypt 'Password', '$1$Salt';
