
##### Link::C will automatically link your C libraries for you. #####
use v6;
unit module Link::C;

##### TODO: figure out where to get this information #####
constant @HEADER_DIRS = <. /usr/include>, @*INC;
constant @LIBRARY_DIRS = <. /lib /usr/lib>, @*INC;
constant @LIBRARY_EXTS = '', <.so .so.0>;

 # Syntax ported to the best of my ability from the official C11 spec at
 # http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf
grammar C-grammar {
 ##### Identifiers #####
    token identifier { <.identifier-nondigit> [<.identifier-nondigit> | <.digit>]* }
     # TODO: unicode
    token identifier-nondigit { <.alpha> | <.universal-character-name> }

 ##### Universal character names #####
    token universal-character-name {
        | '\u' $<four> = <.xdigit> ** 4
        | '\U' $<eight> = <.xdigit> ** 8
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
        | $<simple-escape-sequence> = \' | '"' | '?' | '\\' | 'a' | 'b' | 'f' | 'n' | 'r' | 't' | 'v'
        | $<octal-escape-sequence> = [0..7] ** 1..3
        | $<hexadecimal-escape-sequence> = 'x' <xdigit>+
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
        | $<list> = '(' ~ ')' <type-name> '{' ~ '}' [<initializer-list> ','?]
        ] <postfix>*
    }
    rule postfix {
        | $<index> = '[' ~ ']' <expression>
        | $<call> = '(' ~ ')' <argument-expression-list>?
        | $<dot> = '.' <identifier>
        | $<arrow> = '->' <identifier>
        | $<inc> = '++'
        | $<dec> = '--'
    }
    rule argument-expression-list {
        <assignment-expression>+ % ','
    }
    rule unary-expression {
        <prefix>* [
            | <postfix-expression>
            | $<sizeof-t> = sizeof '(' ~ ')' <type-name>
            | $<alignof> = _Alignof '(' ~ ')' <type-name>
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
        | <declaration-specifiers> <init-declarator-list> ';'
        | <static_assert-declaration>
    }
    rule declaration-specifiers {
        [
        | <storage-class-specifier>
        | <type-specifier>
        | <type-qualifier>
        | <function-specifier>
        | <alignment-specifier>
        ]*
    }
    rule init-declarator-list {
        <init-declarator>+ % ','
    }
    rule init-declarator {
        <declarator> ['=' <initializer>]?
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
        | <struct-or-union> <identifier>? '{' ~ '}' <struct-declaration-list>
        | <struct-or-union> <identifier>
    }
    rule struct-or-union { struct | union }
     # The spec indicates a + here instead of a * here, but I think that's incorrect
    rule struct-declaration-list { <struct-declaration>* }
    rule struct-declaration {
        | <specifier-qualifier-list> <struct-declarator-list>? ';'
        | <static_assert-declaration>
    }
    rule specifier-qualifier-list {
        [<type-specifier>|<type-qualifier>] <specifier-qualifier-list>?
    }
    rule struct-declarator-list {
        <struct-declarator>+ % ','
    }
    rule struct-declarator {
        <declarator> | <declarator>? ':' <constant-expression>
    }
    rule enum-specifier {
        | enum <identifier>? '{' ~ '}' [<enumerator-list> ','?]
        | enum <identifier>
    }
    rule enumerator-list {
        <enumerator>+ % ','
    }
    rule enumerator {
        <enumeration-constant> ['=' <constant-expression>]?
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
    rule declarator { <pointer>? <direct-declarator> }
    rule direct-declarator {
        [ <identifier>
        | '(' ~ ')' <declarator>
        ] <direct-declarator-postfix>*
    }
    rule direct-declarator-postfix {
        | $<array> = '[' ~ ']'
            ['static'? <type-qualifier-list>? 'static'? <assignment-expression>? | <type-qualifier-list>? '*']
        | $<function> = '(' ~ ')' [<parameter-type-list>|<identifier-list>]?
    }
    rule pointer {
        '*' <type-qualifier-list>? <pointer>?
    }
    rule type-qualifier-list { <type-qualifier>+ }
    rule parameter-type-list { <parameter-list> [',' '...']? }
    rule parameter-list { <parameter-declaration>+ % ',' }
    rule parameter-declaration {
        <declaration-specifiers> [<declarator>|<abstract-declarator>]?
    }
    rule identifier-list {
        <identifier>+ % ','
    }
    rule type-name {
        <specifier-qualifier-list> <abstract-declarator>?
    }
    rule abstract-declarator {
        <pointer> | <pointer>? <direct-abstract-declarator>
    }
    rule direct-abstract-declarator {
        [ '(' ~ ')' <abstract-declarator> ] <direct-abstract-declarator-postfix>*
    }
    rule direct-abstract-declarator-postfix {
        | $<array> = '[' ~ ']'
            ['static'? <type-qualifier-list>? 'static'? <assignment-expression>? | <type-qualifier-list>? '*']
        | $<function> = '(' ~ ')' <parameter-type-list>?
    }
     # TODO: recognize only previously-declared typedef names
    rule typedef-name { <!> }
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
        | <identifier> ':' <statement>
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
            [$<pre> = [<expression> | <declaration>]]? ';'
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
    rule translation-unit { <external-declaration>+ }
    rule external-declaration { <function-definition> | <declaration> }
    rule function-definition {
        <declaration-specifiers> <declarator> <declaration>* <compound-statement>
    }
 
 ##### Extensions

    rule attribute { __attribute__ '((' ~ '))' .*? }

    token TOP { <translation-unit> }
}

say 0;
say C-grammar.parse('int main () { return 0; }').gist;
