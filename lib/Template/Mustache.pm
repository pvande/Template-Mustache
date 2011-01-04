# Template::Mustache is an implementation of the fabulous Mustache templating
# language for Perl 5.8 and later.
#
# Information about the design and syntax of Mustache can be found
# [here](http://mustache.github.com).
package Template::Mustache;
use strict;
use warnings;

use CGI ();

# Constructs a new regular expression, to be used in the parsing of Mustache
# templates.
# @param [String] $otag The tag opening delimiter.
# @param [String] $ctag The tag closing delimiter.
# @return [Regex] A regular expression that will match tags with the specified
#   delimiters.
# @api private
sub build_pattern {
    my ($otag, $ctag) = @_;
    return qr/
        ((?:.|\n)*?)                # Capture the pre-tag content
        ([ \t]*)                    # Capture the pre-tag whitespace
        (?:\Q$otag\E \s*)           # Match the opening of the tag
        (?:
            (=)   \s* (.+?) \s* = | # Capture Set Delimiters
            ({)   \s* (.+?) \s* } | # Capture Triple Mustaches
            (\W?) \s* ((?:.|\n)+?)  # Capture everything else
        )
        (?:\s* \Q$ctag\E)           # Match the closing of the tag
    /xm;
}

sub parse {
    my ($tmpl, $delims, $section, $start) = @_;
    my @buffer;

    $delims ||= [qw'{{ }}'];
    my $pattern = build_pattern(@$delims);

    my $pos = pos($tmpl) = $start ||= 0;

    while ($tmpl =~ m/\G$pattern/gc) {
        my ($content, $whitespace) = ($1, $2);
        my $type = $3 || $5 || $7;
        my $tag  = $4 || $6 || $8;

        my $eoc = $pos + length($content) - 1;
        $pos = pos($tmpl);

        my $is_standalone = (substr($tmpl, $eoc, 1) || "\n") eq "\n" &&
                            (substr($tmpl, $pos, 1) || "\n") eq "\n";

        push @buffer, $content;

        if ($is_standalone && ($type !~ /^[\{\&]?$/)) {
            $pos += 1;
        } elsif ($whitespace) {
            $eoc += length($whitespace);
            push @buffer, $whitespace;
            $whitespace = '';
        }

        if ($type eq '!') {
            # Do nothing...
        } elsif ($type eq '{' || $type eq '&' || $type eq '') {
            push @buffer, [$type, $tag];
        } elsif ($type eq '#' || $type eq '^') {
            (my $raw, $pos) = parse($tmpl, $delims, $tag, $pos);
            push @buffer, [ $type, $tag, [$raw, $delims] ];
        } elsif ($type eq '/') {
            return (substr($tmpl, $start, $eoc + 1 - $start), $pos);
        } elsif ($type eq '>') {
            push @buffer, [ $type, $tag, $whitespace ];
        } elsif ($type eq '=') {
            $pattern = build_pattern(@{$delims = [ split(/\s+/, $tag) ]});
        }

        pos($tmpl) = $pos
    }

    push @buffer, substr($tmpl, $pos);

    return \@buffer;
}

sub generate {
    my ($parse_tree, $partials, @context) = @_;

    my $build = sub {
        my $value = pop(@_);
        return generate(parse(@_), $partials, @context, $value);
    };

    my @parts;
    for my $part (@$parse_tree) {
        push(@parts, $part) and next unless ref $part;
        my ($type, $tag, $data) = @$part;
        my ($ctx, $value) = lookup($tag, @context);

        if ($type eq '{' || $type eq '&' || $type eq '') {
            if (ref $value eq 'CODE') {
                $value = $build->($value->(), undef);
                $ctx->{$tag} = $value;
            }
            $value = CGI::escapeHTML($value) unless $type;
            push @parts, $value;
        } elsif ($type eq '#') {
            next unless $value;
            if (ref $value eq 'ARRAY') {
                push @parts, $build->(@$data, $_) for @$value;
            } elsif (ref $value eq 'CODE') {
                push @parts, $build->($value->($data->[0]), $data->[1], undef);
            } else {
                push @parts, $build->(@$data, $value);
            }
        } elsif ($type eq '^') {
            next if ref $value eq 'ARRAY' ? @$value : $value;
            push @parts, $build->(@$data, undef);
        } elsif ($type eq '>') {
            my $partial = $partials->($tag);
            $partial =~ s/^(.)/${data}${1}/gm;
            push @parts, $build->($partial, undef);
        }
    }

    return join '', @parts;
}

sub lookup {
    my ($field, @context) = @_;
    my $ctx;
    my $value = '';

    for my $index (reverse 0..$#{[@context]}) {
        $ctx = $context[$index];
        if (ref $ctx eq 'HASH') {
            next unless exists $ctx->{$field};
            $value = $ctx->{$field};
            last;
        } else {
            next unless UNIVERSAL::can($ctx, $field);
            $value = UNIVERSAL::can($ctx, $field)->();
            last;
        }
    }

    return ($ctx, $value);
}

# Renders a template with the given data.
#
# @param [String] $tmpl The template to render.
# @param [Hash,Class,Object] $data Data to interpolated into the template.
# @param [Hash,Class,Object,Code] $partials A context element to fetch partials
#   from, or a code reference that will return the appropriate partial given a
#   partial name.
# @return [String] The fully rendered template.
sub render {
    my ($receiver, $tmpl, $data, $partials) = @_;

    my $part = $partials;
    $part = sub { lookup(shift, $partials) } unless ref $partials eq 'CODE';

    my $parsed = parse($tmpl);
    return generate($parsed, $part, $data);
}

1;
