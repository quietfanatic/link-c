
##### Link::C will automatically link your C libraries for you. #####
use v6;
use NativeCall;
unit module Link::C;

##### TODO: figure out where to get this information #####
constant @HEADER_DIRS = infix:<,>(|<. /usr/include>, map { $0 if /^file'#'(.*)/ }, @*INC);

class Declaration { ... }

class Type {
    has Bool $.const = False;
    has Bool $.volatile = False;
    has Bool $.restrict = False;
    method gist-qualifiers (Str $s) {
        return join ' ',
            ('const' if $.const),
            ('volatile' if $.volatile),
            ('restrict' if $.restrict),
            $s;
    }
    method p6-type () { die "No equivalent type yet defined to $.gist"; }
}

enum Width <
    char unsigned-char signed-char
    unsigned-short signed-short
    unsigned-int signed-int
    unsigned-long signed-long
    unsigned-long-long signed-long-long
>;

class Type::Integer is Type {
    has Width $.width = signed-int;
    multi method gist (Type::Integer:D:) {
        self.gist-qualifiers((given $.width {
            when char { 'char' }
            when unsigned-char { 'unsigned char' }
            when signed-char { 'signed char' }
            when unsigned-short { 'unsigned short' }
            when signed-short { 'short' }
            when unsigned-int { 'unsigned int' }
            when signed-int { 'int' }
            when unsigned-long { 'unsigned long' }
            when signed-long { 'long' }
            when unsigned-long-long { 'unsigned long long' }
            when signed-long-long { 'long long' }
        }))
    }
    method p6-type () {
         # TODO: proper machine widths
        given $.width {
            when char { uint8 }  # Not really sure
            when unsigned-char { uint8 }
            when signed-char { int8 }
            when unsigned-short { uint16 }
            when signed-short { int16 }
            when unsigned-int { uint32 }
            when signed-int { int32 }
            when unsigned-long { uint64 }
            when signed-long { int64 }
            when unsigned-long-long { uint64 }
            when signed-long-long { int64 }
        }
    }
}
class Type::Struct is Type {
    has Str $.name;
    multi method gist (Type::Struct:D:) { self.gist-qualifiers("struct $.name") }
}
class Type::Union is Type {
    has Str $.name;
    multi method gist (Type::Union:D:) { self.gist-qualifiers("union $.name") }
}
class Type::Typedef is Type {
    has Str $.name;
    multi method gist (Type::Typedef:D:) { self.gist-qualifiers("$.name (AKA <typedef lookup NYI>)") }
}
class Type::Pointer is Type {
    has Type $.base;
    multi method gist (Type::Pointer:D:) { self.gist-qualifiers($.base.gist ~ '*') }
    method p6-type () { Pointer }
}
class Type::Array is Type {
    has Type $.base;
    has uint $.size;
    multi method gist (Type::Array:D:) { self.gist-qualifiers($.base.gist ~ "[$.size]") }
}
class Type::Function is Type {
    has Type $.base;
    has Declaration @.parameters;  # Ignoring parameter names
    has Bool $.variadic = False;  # Not really sure what to do with this
    multi method gist (Type::Function:D:) {
        self.gist-qualifiers($.base.gist ~ '(' ~
            (@.parameters.map(*.gist), ('...' if $.variadic)).join(', ')
        ~ ')')
    }
}

sub add-qualifiers (Type $type, @words) {
    return $type.clone(
        const => ?@words.grep('const'),
        volatile => ?@words.grep('volatile'),
        restrict => ?@words.grep('restrict')
    );
}

sub build-base-type (@words) {
    my Bool $unsigned = ?@words.grep('unsigned');
    my Bool $signed = ?@words.grep('signed');
    if $unsigned and $signed {
        warn "Both signed and unsigned found in {@words.join: ' '}";
        $unsigned = False;
    }
    my Bool $char = ?@words.grep('char');
    my Bool $short = ?@words.grep('short');
    my Int $longs = +@words.grep('long');
    if $short and $longs {
        warn "Both short and long found in {@words.join: ' '}";
        $short = False;
    }
    my $width = $char       ?? $unsigned ?? unsigned-char !! $signed ?? signed-char !! char
             !! $short      ?? $unsigned ?? unsigned-short !! signed-short
             !! $longs == 1 ?? $unsigned ?? unsigned-long !! signed-long
             !! $longs == 2 ?? $unsigned ?? unsigned-long-long !! signed-long-long
             !!                $unsigned ?? unsigned-int !! signed-int;
    return add-qualifiers(Type::Integer.new(:$width), @words);
}

sub wrap-type (Type $base, @wrappers) {
     # Work around bug where reduce returns a list if given one item
    if @wrappers == 0 { return $base }
    reduce { $^wrapper.clone(:$^base) }, $base, |@wrappers;
}

enum Storage <
    auto extern static _Thread_local typedef
>;

class Declaration {
    has Storage $.storage;
    has Type $.type;
    has Str $.name;
     # Right now we don't care, so let's just stuff it in a string
    has Str $.definition;
    multi method gist (Declaration:D:) {
        ($.storage, "($.type.gist())", $.name // Empty, $.definition // Empty).join(' ');
    }
}

sub get-storage (*@words) {
       @words.grep('extern') ?? extern
    !! @words.grep('static') ?? static
    !! @words.grep('_Thread_local') ?? _Thread_local
    !! @words.grep('typedef') ?? typedef
    !!                           auto;
}

 # TODO: actually evaluate ast
sub eval-const-expr (Str $expr) {
    return +$expr;
}

 # Syntax ported to the best of my ability from the official C11 spec at
 # http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf
grammar C-grammar {
 ##### Identifiers #####
    token identifier { <.identifier-nondigit> [<.identifier-nondigit> | <.digit>]* }
     # TODO: unicode
    token identifier-nondigit { <.alpha> | <.universal-character-name> }

 ##### Universal character names #####
    token universal-character-name {
        | '\u' $<four> = [<.xdigit> ** 4]
        | '\U' $<eight> = [<.xdigit> ** 8]
    }

 ##### Constants #####
    token constant {
        | <integer-constant>
        | <floating-constant>
        | <enumeration-constant>
        | <character-constant>
    }
    token integer-constant {
        [ <decimal-constant>
        | <octal-constant>
        | <hexadecimal-constant>
        ] <integer-suffix>?
    }
    token decimal-constant { <[1..9]><[0..9]>* }
    token octal-constant { 0<[0..7]>* }
    token hexadecimal-constant { [0x|0X]<xdigit>+ }
    token integer-suffix {
        | $<unsigned-suffix> = [u|U]
        | $<long-suffix> = [l|L]
        | $<long-long-suffix> = [ll|LL]
    }
    token floating-constant {
        | <decimal-floating-constant>
        | <hexadecimal-floating-constant>
    }
    token decimal-floating-constant {
        | <fractional-constant> <exponent-part>? <floating-suffix>?
        | <digit>+ <exponent-part> <floating-suffix>?
    }
    token hexadecimal-floating-constant {
        [0x|0X] [<hexadecimal-fractional-constant> | <xdigit>+] <floating-suffix>?
    }
    token fractional-constant {
        | <digit>* '.' <digit>+
        | <digit>+ '.'
    }
    token exponent-part {
        [e|E] $<sign> = ['+'|'-']? <digit>+
    }
    token hexadecimal-fractional-constant {
        | <xdigit>* '.' <xdigit>+
        | <xdigit>+ '.'
    }
    token binary-exponent-part {
        [p|P] $<sign> = ['+'|'-']? <xdigit>+
    }
    token floating-suffix {
        | $<float-suffix> = [f|F]
        | $<double-suffix> = [l|L]
    }
    token enumeration-constant { <identifier> }
    token character-constant {
        $<prefix> = [L|u|U]?
        \' ~ \' <c-char>+
    }
    token c-char {
        <-[\\']>
        | <escape-sequence>
    }
    token escape-sequence { '\\' [  # Factored the \ out, different from the spec
        | $<simple-escape-sequence> = [\' | '"' | '?' | '\\' | 'a' | 'b' | 'f' | 'n' | 'r' | 't' | 'v']
        | $<octal-escape-sequence> = [[0..7] ** 1..3]
        | $<hexadecimal-escape-sequence> = ['x' <xdigit>+]
    ] }

 ##### String literals #####
    token string-literal {
        <encoding-prefix>? '"' ~ '"' <s-char>*
    }
    token encoding-prefix { u8 | u | U | L }

 ##### Expressions #####
    rule primary-expression {
        | <identifier>
        | <constant>
        | <string-literal>
        | '(' ~ ')' <expression>
        | <generic-selection>
    }
    rule generic-selection {
        _Generic '(' ~ ')' [<assignment-expression> ',' <generic-association>+]
    }
    rule generic-association {
        [<type-name> | default] ':' <assignment-expression>
    }
    rule postfix-expression {
        [ <primary-expression>
        | $<list> = ['(' ~ ')' <type-name> '{' ~ '}' [<initializer-list> ','?]]
        ] <postfix>*
    }
    rule postfix {
        | $<index> = ['[' ~ ']' <expression>]
        | $<call> = ['(' ~ ')' [<assignment-expression>* % ',']]
        | $<dot> = ['.' <identifier>]
        | $<arrow> = ['->' <identifier>]
        | $<inc> = '++'
        | $<dec> = '--'
    }
    rule unary-expression {
        <prefix>* [
            | <postfix-expression>
            | $<sizeof-t> = [sizeof '(' ~ ')' <type-name>]
            | $<alignof> = [_Alignof '(' ~ ')' <type-name>]
        ]
    }
    rule prefix {
        | $<inc> = '++'
        | $<dec> = '--'
        | $<op> = <unary-operator>
        | $<sizeof-e> = sizeof
    }
    token unary-operator { '&' | '*' | '+' | '-' | '~' | '!' }
    rule cast-expression {
        ['(' ~ ')' <type-name>]* <unary-expression>
    }
    rule multiplicative-expression {
        <cast-expression>+ % [ $<op> = '*' | '/' | '%' ]
    }
    rule additive-expression {
        <multiplicative-expression>+ % [ $<op> = '+' | '-' ]
    }
    rule shift-expression {
        <additive-expression>+ % [ $<op> = '<<' | '>>' ]
    }
    rule relational-expression {
        <shift-expression>+ % [ $<op> = '<' | '>' | '<=' | '>=' ]
    }
    rule equality-expression {
        <relational-expression>+ % [ $<op> = '==' | '!=' ]
    }
    rule and-expression {
        <equality-expression>+ % '&'
    }
    rule exclusive-or-expression {
        <and-expression>+ % '^'
    }
    rule inclusive-or-expression {
        <exclusive-or-expression>+ % '|'
    }
    rule logical-and-expression {
        <inclusive-or-expression>+ % '&&'
    }
    rule logical-or-expression {
        <logical-and-expression>+ % '||'
    }
    rule conditional-expression {
        [<logical-or-expression> '?' <expression> ':']* <logical-or-expression>
    }
    rule assignment-expression {
        [<unary-expression> <assignment-operator>]* <conditional-expression>
    }
    rule assignment-operator {
        '=' | '*=' | '/=' | '%=' | '+=' | '-=' | '<<=' | '>>=' | '&=' | '^=' | '|='
    }
    rule expression {
        <assignment-expression>+ % ','
    }
    rule constant-expression { <conditional-expression> }

 ##### Declarations #####
    rule declaration {
        | <declaration-specifiers> <init-declarator>+ % ',' ';'
            { $/.make: $<init-declarator>.map({
                Declaration.new(
                    storage => get-storage($<declaration-specifiers>.made),
                    type => wrap-type(build-base-type($<declaration-specifiers>.made), $_.made<wrappers>),
                    name => $_.made<name>,
                    definition => $_.made<definition> // Str
                )
            }) }
        | <static_assert-declaration> { $/.make: Empty }
    }
    rule declaration-specifiers {
        (
        | <storage-class-specifier> { $/.make: trim ~$<storage-class-specifier> }
        | <type-specifier> { $/.make: trim ~$<type-specifier> }
        | <type-qualifier> { $/.make: trim ~$<type-qualifier> }
        | <function-specifier> { $/.make: Empty }
        | <alignment-specifier> { $/.make: Empty }
        | <.attribute> { $/.make: Empty }
        )* { $/.make: $0>>.made }
    }
    rule init-declarator {
        <declarator> ['=' <initializer>]?
        { $/.make: {
            name => $<declarator>.made<name>,
            wrappers => $<declarator>.made<wrappers>,
            (definition => trim $<initializer> if $<initializer>)
        } }
    }
    rule storage-class-specifier {
        typedef | extern | static | _Thread_local | auto | register
    }
    rule type-specifier {
        | void | char | short | int | long | float | double
        | signed | unsigned | _Bool | _Complex
        | <atomic-type-specifier>
        | <struct-or-union-specifier>
        | <enum-specifier>
        | <typedef-name>
    }
    rule struct-or-union-specifier {
        | <struct-or-union> <.attribute>* <identifier>? '{' ~ '}' <struct-declaration>* <.attribute>*
        | <struct-or-union> <identifier>
    }
    rule struct-or-union { struct | union }
     # The spec indicates a + here instead of a * here, but I think that's incorrect
    rule struct-declaration {
        | <specifier-qualifier-list> <struct-declarator>* % ',' ';'
        | <static_assert-declaration>
    }
    rule specifier-qualifier-list {
        [<type-specifier>|<type-qualifier>]+
    }
    rule struct-declarator {
        <declarator> | <declarator>? ':' <constant-expression>
    }
    rule enum-specifier {
        | enum <identifier>? '{' ~ '}' [<enumerator>+ % ',' ','?]
        | enum <identifier>
    }
    rule enumerator {
        <enumeration-constant> <.attribute>* ['=' <constant-expression>]?
    }
    rule atomic-type-specifier {
        _Atomic '(' ~ ')' <type-name>
    }
    rule type-qualifier {
        const | restrict | volatile | _Atomic
    }
    rule function-specifier {
        inline | _Noreturn
    }
    rule alignment-specifier {
        _Alignas '(' ~ ')' [<type-name>|<constant-expression>]
    }
    rule declarator {
        <pointer>? <direct-declarator> <.attribute>*
        { $/.make: {
            name => $<direct-declarator>.made<name>,
            wrappers => infix:<,>(|($<pointer>.made if $<pointer>), |$<direct-declarator>.made<wrappers>)
        } }
    }
    rule direct-declarator {
        [ <identifier> { $/.make: {name => ~$<identifier>, wrappers => Empty} }
        | '(' ~ ')' <declarator> { $/.make: $<declarator>.made }
        ] <direct-declarator-postfix>*
        { $/.make: {
            name => $/.made<name>,
            wrappers => infix:<,>(|$/.made<wrappers>, |$<direct-declarator-postfix>>>.made)
        } }
    }
    rule direct-declarator-postfix {
        | '[' ~ ']' ['static'? <type-qualifier>* 'static'? <assignment-expression>? | <type-qualifier>* '*']
            { $/.make: add-qualifiers(Type::Array.new(size => eval-const-expr(~$<assignment-expression>)), ~<<$<type-qualifier>) }
        | '(' ~ ')' [<parameter-declaration>+ % ',' (',' '...')?]?  # Leaving out old-fashioned typeless parameters
            { $/.make: Type::Function.new(parameters => $<parameter-declaration>>>.made, variadic => ?$0)}
    }
    rule pointer {
        '*' <type-qualifier>* <pointer>?
        { $/.make: infix:<,>(add-qualifiers(Type::Pointer.new, ~<<$<type-qualifier>), |($<pointer>.made if $<pointer>)) }
    }
    rule parameter-declaration {
        <declaration-specifiers> [<declarator>|<abstract-declarator>]?
        {   my $wrappers = $<declarator> ?? $<declarator>.made<wrappers>
                        !! $<abstract-declarator> ?? $<abstract-declarator>.made
                        !! Empty;
            $/.make: Declaration.new(
                storage => auto,
                type => wrap-type(build-base-type($<declaration-specifiers>.made), $wrappers),
                name => $<declarator> ?? $<declarator>.made<name> !! Str,
            )
        }
    }
    rule type-name {
        <specifier-qualifier-list> <abstract-declarator>?
    }
    rule abstract-declarator {
        <pointer> | <pointer>? <direct-abstract-declarator>
        { $/.make: (infix:<,>(
            |($<pointer>.made if $<pointer>),
            |($<direct-abstract-declarator>.made if $<direct-abstract-declarator>)
        )) }

    }
    rule direct-abstract-declarator {
        [ '(' ~ ')' <abstract-declarator> { $/.make: $<abstract-declarator>.made }
        ]?
        <direct-abstract-declarator-postfix>*
        { $/.make: (infix:<,>(|$/.made, |$<direct-abstract-declarator-postfix>>>.made)) }
    }
    rule direct-abstract-declarator-postfix {
        | '[' ~ ']' ['static'? <type-qualifier>* 'static'? <assignment-expression>? | <type-qualifier>* '*']
            { $/.make: add-qualifiers(Type::Array.new(size => eval-const-expr($<assignment-expression>)), ~<<$<type-qualifier>) }
        | '(' ~ ')' [<parameter-declaration>+ % ',' (',' '...')?]?  # Leaving out old-fashioned typeless parameters
            { $/.make: Type::Function.new(parameters => $<parameter-declaration>>>.made, variadic => ?$0)}
    }
    rule typedef-name { <!> }  # TODO: typedefs
    rule initializer {
        | <assignment-expression>
        | '{' ~ '}' [<initializer-list> ','?]
    }
    rule initializer-list { [<designation>? <initializer>]+ % ',' }
    rule designation { <designator>+ '=' }
    rule designator {
        | '[' ~ ']' <constant-expression>
        | '.' <identifier>
    }
    rule static_assert-declaration {
        _Static_assert '(' ~ ')' [<constant-expression> ',' <string-literal>] ';'
    }

 ##### Statements #####
    rule statement {
        | <labeled-statement>
        | <compound-statement>
        | <expression-statement>
        | <selection-statement>
        | <iteration-statement>
        | <jump-statement>
    }
    rule labeled-statement {
        | <identifier> ':' <.attribute>* <statement>
        | $<case> = case <constant-expression> ':' <statement>
        | $<default> = default ':' <statement>
    }
    rule compound-statement { '{' ~ '}' <block-item>* }
    rule block-item { <declaration> | <statement> }
    rule expression-statement { <expression>? ';' }
    rule selection-statement {
        | $<if> = if '(' ~ ')' <expression> <statement> [else <statement>]?
        | $<switch> = switch '(' ~ ')' <statement>
    }
    rule iteration-statement {
        | $<while> = while '(' ~ ')' <expression> <statement>
        | $<do-while> = do <statement> while '(' ~ ')' <expression>
        | $<for> = for '(' ~ ')' [
           .[$<pre> = [<expression> | <declaration>]]? ';'
            [$<check> = <expression>]? ';'
            [$<iterate> = <expression>]?
        ]
    }
    rule jump-statement {
        | $<goto> = goto <identifier> ';'
        | $<continue> = continue ';'
        | $<break> = break ';'
        | $<return> = return <expression>? ';'
    }

 ##### External definitions #####
    rule translation-unit { <external-declaration>+ { $/.make: $<external-declaration>>>.made } }
    rule external-declaration {
        | <function-definition> { $/.make: $<function-definition>.made }
        | <declaration> { $/.make: $<declaration>.made }
    }
    rule function-definition {
        <declaration-specifiers> <declarator> <declaration>* <compound-statement>
        {
            $<declaration> == 0
                or fail "Old-style function parameter declarations not supprted, sorry";
            $/.make: Declaration.new(
                storage => get-storage($<declaration-specifiers>.made),
                type => wrap-type(build-base-type($<declaration-specifiers>.made), $<declarator>.made<wrappers>),
                name => $<declarator>.made<name>,
                definition => ~$<compound-statement>
            )
        }
    }

 ##### Extensions #####

     # Ignore preprocessor declarations
    token ws { <!ww> [\s | '#' \N* \n]* }

    rule attribute { __attribute__ '((' ~ '))' <.attribute_contents> }
    token attribute_contents { ['(' ~ ')' <.attribute_contents> | <-[()]>]* }

    rule TOP { ^ <translation-unit> $ { $/.make: $<translation-unit>.made } }
}

sub link ($header is copy, $lib, *%opts) is export {
    if $header !~~ /^\// {
        my $found = False;
            for @HEADER_DIRS -> $d {
            say "Searching for $d/$header...";
            if "$d/$header".IO.e {
                $header = "$d/$header";
                $found = True;
            }
        }
        $found or die "Could not find $header in any of <{join ' ', @HEADER_DIRS}>";
    }
    my $esc_ = $header.subst("'", "'\\''", :g);
    my $text = qqx/cpp '$esc_'/;
    my @decls = C-grammar.parse($text).made;
    for @decls {
        if (.type ~~ Type::Function) {
            my $return = .map: *.type.base.p6-type.^name;
            my @params = .type.parameters.map: *.type.p6-type.^name;
            my $s = "
                &C::$_.name() = sub $_.name() ({join ', ', @params}) returns $return is native('$lib') \{ * }
            ";
            say $s;
            EVAL $s;
        }
    }
}

link |@*ARGS;
say C::timestwo(54);
