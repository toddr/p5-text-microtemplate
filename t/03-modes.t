use strict;
use warnings;
use Test::More tests => 13;
use Text::MicroTemplate qw(:all);

# escape_html

is(Text::MicroTemplate::escape_html('&') => '&amp;');
is(Text::MicroTemplate::escape_html('>') => '&gt;');
is(Text::MicroTemplate::escape_html('<') => '&lt;');
is(Text::MicroTemplate::escape_html('"') => '&quot;');
is(Text::MicroTemplate::escape_html("'") => '&#39;');

# comment
is render_mt(<<'...')->as_string, "aaa\nbbb\n";
aaa
?# 
bbb
?# 
...
is render_mt('aaa<?# a ?>bbb')->as_string, "aaabbb";

# expression and raw expression
do {
    is render_mt('<?= $_[0] ?>', 'foo<a')->as_string, 'foo&lt;a';
    my $rs = encoded_string('foo<a');
    is render_mt('<?= $_[0] ?>', $rs)->as_string, 'foo<a';

    # overload
    is $rs, 'foo<a';
    is render_mt('<?= $_[0] ?>', $rs), 'foo<a';
};
do {
    use utf8;
    is render_mt('あ<?= $_[0] ?>う', 'い<')->as_string, 'あい&lt;う';
    my $rs = encoded_string('い<');
    is render_mt('あ<?= $_[0] ?>う', $rs)->as_string, 'あい<う';
}
