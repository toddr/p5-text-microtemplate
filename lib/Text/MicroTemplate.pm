# modified for NanoA by kazuho, some modified by tokuhirom
# based on Mojo::Template. Copyright (C) 2008, Sebastian Riedel.

package Text::MicroTemplate;

require Exporter;

use strict;
use warnings;
use constant DEBUG => $ENV{MICRO_TEMPLATE_DEBUG} || 0;

use Carp 'croak';

our $VERSION = '0.01';
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(as_html);
our %EXPORT_TAGS = (
    all => [ @EXPORT_OK ],
);

sub new {
    my $class = shift;
    return bless {
        code                => undef,
        comment_mark        => '#',
        expression_mark     => '=',
        raw_expression_mark => '=r',
        line_start          => '?',
        template            => '',
        tree                => [],
        tag_start           => '<?',
        tag_end             => '?>',
        escape_func         => 'Text::MicroTemplate::escape_html',
        ref($_[0]) ? %{$_[0]} : @_,
    }, $class;
}

sub code {
    my $self = shift;
    unless (defined $self->{code}) {
        $self->build();
    }
    $self->{code};
}

sub escape_func { shift->{escape_func} }

sub build {
    my $self = shift;
    
    my $escape_func = $self->{escape_func} || '';
    
    # Compile
    my @lines;
    for my $line (@{$self->{tree}}) {

        # New line
        push @lines, '';
        for (my $j = 0; $j < @{$line}; $j += 2) {
            my $type  = $line->[$j];
            my $value = $line->[$j + 1];

            # Need to fix line ending?
            my $newline = chomp $value;

            # Text
            if ($type eq 'text') {

                # Quote and fix line ending
                $value = quotemeta($value);
                $value .= '\n' if $newline;

                $lines[-1] .= "\$_MT .= \"" . $value . "\";";
            }

            # Code
            if ($type eq 'code') {
                $lines[-1] .= "$value;";
            }

            # Expression
            if ($type eq 'expr') {
                $lines[-1] .= "\$_MT_T = scalar $value; \$_MT .= ref \$_MT_T eq 'Text::MicroTemplate::RawString' ? \$\$_MT_T : $escape_func(\$_MT_T);";
            }

            # Raw Expression
            if ($type eq 'raw_expr') {
                
                $lines[-1] .= "\$_MT_T = $value; \$_MT .= ref \$_MT_T eq q(Text::MicroTemplate::RawString) ? \$\$_MT_T : \$_MT_T;";
            }
        }
    }

    # Wrap
    $lines[0] ||= '';
    $lines[0]   = q/sub { my $_MT = ''; my $_MT_T = '';/ . $lines[0];
    $lines[-1] .= q/return $_MT; }/;

    $self->{code} = join "\n", @lines;
    return $self;
}

# I am so smart! I am so smart! S-M-R-T! I mean S-M-A-R-T...
sub parse {
    my ($self, $tmpl) = @_;
    $self->{template} = $tmpl;

    # Clean start
    delete $self->{tree};

    # Tags
    my $line_start    = quotemeta $self->{line_start};
    my $tag_start     = quotemeta $self->{tag_start};
    my $tag_end       = quotemeta $self->{tag_end};
    my $cmnt_mark     = quotemeta $self->{comment_mark};
    my $expr_mark     = quotemeta $self->{expression_mark};
    my $raw_expr_mark = quotemeta $self->{raw_expression_mark};

    # Tokenize
    my $state = 'text';
    my $multiline_expression = 0;
    for my $line (split /\n/, $tmpl) {

        # Perl line without return value
        if ($line =~ /^$line_start\s+(.+)$/) {
            push @{$self->{tree}}, ['code', $1];
            $multiline_expression = 0;
            next;
        }

        # Perl line with return value
        if ($line =~ /^$line_start$expr_mark\s+(.+)$/) {
            push @{$self->{tree}}, ['expr', $1];
            $multiline_expression = 0;
            next;
        }

        # Perl line with raw return value
        if ($line =~ /^$line_start$raw_expr_mark\s+(.+)$/) {
            push @{$self->{tree}}, ['raw_expr', $1];
            $multiline_expression = 0;
            next;
        }

        # Comment line, dummy token needed for line count
        if ($line =~ /^$line_start$cmnt_mark\s+(.+)$/) {
            push @{$self->{tree}}, [];
            $multiline_expression = 0;
            next;
        }

        # Escaped line ending?
        if ($line =~ /(\\+)$/) {
            my $length = length $1;

            # Newline escaped
            if ($length == 1) {
                $line =~ s/\\$//;
            }

            # Backslash escaped
            if ($length >= 2) {
                $line =~ s/\\\\$/\\/;
                $line .= "\n";
            }
        }

        # Normal line ending
        else { $line .= "\n" }

        # Mixed line
        my @token;
        for my $token (split /
            (
                $tag_start$raw_expr_mark # Raw Expression
            |
                $tag_start$expr_mark     # Expression
            |
                $tag_start$cmnt_mark     # Comment
            |
                $tag_start               # Code
            |
                $tag_end                 # End
            )
        /x, $line) {

            # Garbage
            next unless $token;

            # End
            if ($token =~ /^$tag_end$/) {
                $state = 'text';
                $multiline_expression = 0;
            }

            # Code
            elsif ($token =~ /^$tag_start$/) { $state = 'code' }

            # Comment
            elsif ($token =~ /^$tag_start$cmnt_mark$/) { $state = 'cmnt' }

            # Raw Expression
            elsif ($token =~ /^$tag_start$raw_expr_mark$/) {
                $state = 'raw_expr';
            }

            # Expression
            elsif ($token =~ /^$tag_start$expr_mark$/) {
                $state = 'expr';
            }

            # Value
            else {

                # Comments are ignored
                next if $state eq 'cmnt';

                # Multiline expressions are a bit complicated,
                # only the first line can be compiled as 'expr'
                $state = 'code' if $multiline_expression;
                $multiline_expression = 1 if $state eq 'expr';

                # Store value
                push @token, $state, $token;
            }
        }
        push @{$self->{tree}}, \@token;
    }

    return $self;
}

sub _context {
    my ($self, $text, $line) = @_;

    $line     -= 1;
    my $nline  = $line + 1;
    my $pline  = $line - 1;
    my $nnline = $line + 2;
    my $ppline = $line - 2;
    my @lines  = split /\n/, $text;

    # Context
    my $context = (($line + 1) . ': ' . $lines[$line] . "\n");

    # -1
    $context = (($pline + 1) . ': ' . $lines[$pline] . "\n" . $context)
      if $lines[$pline];

    # -2
    $context = (($ppline + 1) . ': ' . $lines[$ppline] . "\n" . $context)
      if $lines[$ppline];

    # +1
    $context = ($context . ($nline + 1) . ': ' . $lines[$nline] . "\n")
      if $lines[$nline];

    # +2
    $context = ($context . ($nnline + 1) . ': ' . $lines[$nnline] . "\n")
      if $lines[$nnline];

    return $context;
}

# Debug goodness
sub _error {
    my ($self, $error) = @_;

    # No trace in production mode
    return undef unless DEBUG;

    # Line
    if ($error =~ /at\s+\(eval\s+\d+\)\s+line\s+(\d+)/) {
        my $line  = $1;
        my $delim = '-' x 76;

        my $report = "\nTemplate error around line $line.\n";
        my $template = $self->_context($self->{template}, $line);
        $report .= "$delim\n$template$delim\n";

        # Advanced debugging
        if (DEBUG >= 2) {
            my $code = $self->_context($self->code, $line);
            $report .= "$code$delim\n";
        }

        $report .= "$error\n";
        return $report;
    }

    # No line found
    return "Template error: $error";
}

# create raw string (that does not need to be escaped)
sub raw_string {
    my $s = shift;
    bless \$s, 'Text::MicroTemplate::RawString';
}

sub escape_html {
    my $str = shift;
    return $$str
        if ref $str eq 'Text::MicroTemplate::raw_string';
    $str =~ s/&/&amp;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&#39;/g;
    return $str;
}

sub as_html {
    my $t = shift;
    my $mt = Text::MicroTemplate->new;
    $mt->parse($t);
    '((' . $mt->code . ')->())';
}

1;
__END__