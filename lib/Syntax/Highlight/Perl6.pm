package Syntax::Highlight::Perl6;

# core modules & directives
use 5.010;
use strict;
use warnings;
use Carp;

require Exporter;

# exports and version
our @EXPORT_OK = qw();
our $VERSION   = '0.81';

# filename constants
my $FILE_CSS    = 'p6_style.css';
my $FILE_ANSI   = 'p6_style.ansi';
my $FILE_JS     = 'p6_style.js';
my $FILE_JQUERY = 'jquery-1.4.2.min.js';


# my module variables
my @loc;

#find out the real path of the rsc directory
if ( !-f __FILE__ ) {
	croak 'Syntax::Highlight::Perl6 cannot see where it is installed';
}

require File::Basename;
require File::Spec;
require Cwd;

my $SHARED = Cwd::realpath( File::Spec->join( File::Basename::dirname(__FILE__), 'Perl6' ) );

#----------------------------------------------------------------
# Returns the syntax highlighting object. It needs a hash
# of options.
#----------------------------------------------------------------
sub new {
	my ( $class, %options ) = @_;
	$options{rule}             = $options{rule}             // 'TOP';
	$options{inline_resources} = $options{inline_resources} // 0;
	$options{resource_url}     = $options{resource_url}     // q{};
	$options{page_title}       = $options{page_title}       // q{};
	$options{utf8_decode}      = $options{utf8_decode}      // 1;
	$options{tmp_prefix}       = $options{tmp_prefix}       // q{};

	#is 'text' undefined?
	if ( !defined $options{text} ) {
		croak "'text' option is not found in $class->new";
	}

	my $self = bless \%options, $class;
	$self->{parser}        = 0;
	$self->{src_text}      = 0;
	$self->{parsed_lazily} = 0;
	return $self;
}

#----------------------------------------------------------------
# Lazily parses the source string using STD.pm6 (only once)
# (private)
#----------------------------------------------------------------
sub _lazy_parse {
	my $self = shift;

	if ( !$self->{parsed_lazily} ) {

		# utf8-decode if required
		require Encode;
		my $src_text =
			$self->{utf8_decode}
			? Encode::decode( 'utf8', $self->{text} )
			: $self->{text};

		#grow the loc array while checking for empty strings
		my $len = length $src_text;
		if ( $len == 0 ) {
			$src_text = q{ };
			$len      = 1;
		}
		$loc[ $len - 1 ] = [];

		#STD parse the text for the rule provided
		require STD;
		$self->{parser} = STD->parse(
			$src_text,
			rule             => $self->{rule},
			actions          => __PACKAGE__ . '::Actions',
			tmp_prefix       => $self->{tmp_prefix},
            syml_search_path => [$SHARED],
		);

		#we parsed it lazily...
		$self->{src_text} = $src_text;
		@{ $self->{loc} } = @loc;
		@loc = ();
		$self->{parsed_lazily} = 1;
	}
	return;
}


#---------------------------------------------------------------------
# Returns snippet htmls which can embedded without any side effects
# on your page
#---------------------------------------------------------------------
sub snippet_html {
	my $self = shift;
	my $str  = q{};

	$self->_lazy_parse();

	my %colors = _read_css_file();

	$str .= '<pre>';

	local *spit_snippet_html = sub {
		my ( $i, $buffer, $rule, $tree, $lineno ) = @_;
		$buffer = _escape_html($buffer);
		my $style = $colors{$rule};
		if ($rule) {
			$str .= qq{<span style="$style">$buffer</span>};
		} else {
			$str .= $buffer;
		}
	};
	$self->_redspans_traverse( \&spit_snippet_html, %colors );

	$str .= '</pre>';

	return $str;
}

#---------------------------------------------------------------
# Returns the Perl 6 highlighted HTML string
# (without the JavaScript stuff).
#---------------------------------------------------------------
sub simple_html {
	my $self = shift;
	my $str  = q{};

	$self->_lazy_parse();

	my %colors = _read_css_file();

	# slurp css inline it
	my $css;
	if ( $self->{inline_resources} ) {
		$css = _slurp( _shared($FILE_CSS) )
			or croak "Error while slurping file: $!\n";
		$css = qq{<style type="text/css">\n$css\n</style>};
	} else {
		my $prefix = $self->{resource_url};
		$css = qq{<link href="$prefix$FILE_CSS" rel="stylesheet" type="text/css">};
	}
	my $page_title = $self->{page_title};
	my $timestamp  = localtime;
	$str .= <<"HTML";
<html>
<head>
    <title>$page_title</title>
<!--
     Generated by $0 at $timestamp
-->
    $css
</head>
<body>
    <pre>
HTML

	local *spit_simple_html = sub {
		my ( $i, $buffer, $rule, $tree, $lineno ) = @_;
		$buffer = _escape_html($buffer);
		if ($rule) {
			$str .= qq{<span class="$rule">$buffer</span>};
		} else {
			$str .= $buffer;
		}
	};

	$self->_redspans_traverse( \&spit_simple_html, %colors );

	$str .= <<'HTML';
    </pre>
</body>
</html>
HTML

	return $str;
}

#-------------------------------------------------------------------
# Returns the Perl 6 highlighted HTML string. The HTML consists of a
# JavaScript Parse Tree Viewer along with CSS-styling.
#-------------------------------------------------------------------
sub full_html {
	my $self = shift;
	my $str  = q{};

	$self->_lazy_parse();

	# slurp libraries and JavaScript to inline them
	my %colors = _read_css_file();
	my ( $jquery_js, $js, $css );
	if ( $self->{inline_resources} ) {
		my $contents;
		$contents = _slurp( _shared($FILE_JQUERY) )
			or croak "Error while slurping file: $!\n";
		$jquery_js = qq{<script type="text/javascript">\n$contents\n</script>};
		$contents  = _slurp( _shared($FILE_JS) )
			or croak "Error while slurping file: $!\n";
		$js       = qq{<script type="text/javascript">\n$contents\n</script>};
		$contents = _slurp( _shared($FILE_CSS) )
			or croak "Error while slurping file: $!\n";
		$css = qq{<style type="text/css">\n$contents\n</style>};
	} else {
		my $prefix = $self->{resource_url};
		$jquery_js = qq{<script type="text/javascript" src="$prefix$FILE_JQUERY"></script>};
		$js        = qq{<script type="text/javascript" src="$prefix$FILE_JS"></script>};
		$css       = qq{<link href="$prefix$FILE_CSS" rel="stylesheet" type="text/css">};
	}

	my $page_title = $self->{page_title};
	my $timestamp  = localtime;
	$str .= <<"HTML";
<html>
<head>
    <title>$page_title</title>
<!--
    Generated by $0 at $timestamp
-->
    $css
    $jquery_js
    $js
</head>
<body>
    <div id="parse_tree">
        <button id="parse_tree_expand">Show Syntax Tree</button>
        <button id="parse_tree_collapse">Hide it</button>
        <button id="parse_tree_help">Help</button>
        <div id="parse_tree_output"></div>
    </div>
    <pre>
HTML

	local *spit_full_html = sub {
		my ( $i, $buffer, $rule, $tree, $lineno ) = @_;
		$buffer = _escape_html($buffer);
		$str .= qq{<span id="tree_$i" style="display:none;">$tree</span>};
		if ($rule) {
			$str .= qq{<span id="node_$i" class="$rule">$buffer</span>};
		} else {
			$str .= $buffer;
		}
	};

	$self->_redspans_traverse( \&spit_full_html, %colors );

	$str .= <<'HTML';
    </pre>
</body>
</html>
HTML

	return $str;
}

#---------------------------------------------------------------
# Returns a Perl highlighted ANSI escape color string.
#---------------------------------------------------------------
sub ansi_text {
	my $self = shift;
	my $str  = q{};

	$self->_lazy_parse();

	my %colors = _read_ansi_file();

	require Term::ANSIColor;
	local *spit_ansi_text = sub {
		my ( $i, $buffer, $rule, $tree, $lineno ) = @_;
		if ($rule) {
			my $color = $colors{$rule};
			$str .= Term::ANSIColor::color($color) . $buffer . Term::ANSIColor::color('reset');
		} else {
			$str .= $buffer;
		}
	};

	$self->_redspans_traverse( \&spit_ansi_text, %colors );

	return $str;
}

#---------------------------------------------------------------
# Returns a Perl 5 array containing parse tree records.
# The array consists of one or more of the following record:
#   ($last_pos, $buffer, $rule, $tree)
#---------------------------------------------------------------
sub tokens {
	my $self = shift;

	$self->_lazy_parse();

	my %colors = _read_ansi_file();
	my @tokens = ();
	local *spit_parse_tree = sub {
		push @tokens,
			{
			'last_pos' => $_[0],
			'buffer'   => $_[1],
			'rule'     => $_[2],
			'tree'     => $_[3],
			'lineno'   => $_[4],
			};
	};
	$self->_redspans_traverse( \&spit_parse_tree, %colors );

	return @tokens;
}


#--------------------------------------------------------------------
# Reads the css file and return a hash of colors
#--------------------------------------------------------------------
sub _read_css_file {

	my %colors   = ();
	my $filename = _shared($FILE_CSS);
	my $fh       = IO::File->new($filename)
		or croak "Could not open $filename: $!\n";
	my $line;
	while ( $line = <$fh> ) {
		if ($line =~ /^\s*           # <whitespace>
                    \.(\w+)\s*      # .<css class>
                    {\s*(.+?)\s*}   # { <css style>* }
                    /x
			)
		{
			$colors{$1} = $2;
		}
	}
	close $fh
		or croak "Could not close $filename";

	return %colors;
}

#--------------------------------------------------------------
# Reads an ANSI rule-name=color property file and stores
# the color values in a hash of rule-name,color
#--------------------------------------------------------------
sub _read_ansi_file {
	my %colors   = ();
	my $filename = _shared($FILE_ANSI);
	my $fh       = IO::File->new($filename)
		or croak "Could not open $filename: $!\n";
	my $line;
	while ( $line = <$fh> ) {
		if ($line =~ m{^(\w+)     # <start> <rule-name>
                    =(.+)$      # <=> <ansi-color> <end>
                    }x
			)
		{
			$colors{$1} = $2;
		}
	}
	close $fh
		or croak "Could not close $filename";

	return %colors;
}


#---------------------------------------------------------------
#    Helper private method that traverses STD.pm6's parse
# tree array. It needs a callback process_buffer and a
# colors hash.
#---------------------------------------------------------------
sub _redspans_traverse {
	my ( $self, $process_buffer, %colors ) = @_;
	my @loc = @{ $self->{loc} };
	my ( $last_tree, $buffer, $last_type ) = ( q{}, q{}, q{} );
	my $parser = $self->{parser};
	my $len    = length $self->{src_text};
	for my $i ( 0 .. $len - 1 ) {
		if ( not defined $loc[$i] ) {
			next;
		}
		my $c = substr $self->{src_text}, $i, 1;
		my $tree = q{};
		for my $action_ref ( @{ $loc[$i] } ) {
			$tree .= ${$action_ref} . q{ };
		}
		if ( $tree ne $last_tree ) {
			my $rule_to_color = 0;
			my @rules         = ();
			if ( $last_tree ne q{} ) {
				@rules = reverse split / /, $last_tree;
			}
			for my $rule (@rules) {
				if ( $rule eq 'unv' ) {
					$rule_to_color = '_comment';
					last;
				} elsif ( $colors{$rule} && $buffer ne q{} ) {
					$rule_to_color = $rule;
					last;
				}
			}
			if ($rule_to_color) {
				if ( $last_tree =~ /\sidentifier/x ) {
					if ( $last_type ne q{} ) {
						$rule_to_color = $last_type;
						$last_type     = q{};
					}
				} elsif ( $last_tree =~ /\ssigil/x ) {
					given ($buffer) {
						when ('$') { $last_type = '_scalar'; }
						when ('@') { $last_type = '_array'; }
						when ('%') { $last_type = '_hash'; }
						default    { $last_type = q{}; }
					};
					if ( $last_type ne q{} ) {
						$rule_to_color = $last_type;
					}
				}
			}

			#now delegate printing to a callback
			#HACK to prevent parser->lineof(position) from breaking. lineof should be called in the same dynamic scope of parsing
			$::ORIG = $self->{src_text};  
			$process_buffer->( $i, $buffer, $rule_to_color, $last_tree, $parser->lineof($i) );
			$buffer = $c;
		} else {
			$buffer .= $c;
		}
		$last_tree = $tree;
	}
	return;
}

#------------------------------------------------------------------
# R E D S P A N S
# STD.pm6 calls this method when you call STD->parse(...)
# and we populate @loc with action references and parse trees...
#------------------------------------------------------------------
{

	package Syntax::Highlight::Perl6::Actions;

	our $AUTOLOAD;

	my %action_refs = ();

	sub AUTOLOAD {
		my $self = shift;
		my $C    = shift;
		my $F    = $C->{_from};
		my $P    = $C->{_pos};
		$AUTOLOAD =~ s/^Syntax::Highlight::Perl6::Actions:://x;
		if ( $loc[$P] ) {

			# in case we backtracked to here
			$loc[$P] = [];
		}
		my $action     = $AUTOLOAD;
		my $action_ref = $action_refs{$action};
		if ( !$action_ref ) {
			$action_refs{$action} = $action_ref = \$action;
		}
		for ( $F .. $P - 1 ) {
			unshift @{ $loc[$_] }, $action_ref;
		}
		return;
	}

	sub stdstopper  { }
	sub terminator  { }
	sub unitstopper { }
	sub comp_unit   { }
}

#---------------------------------------------------------------
# Private method to converts characters to their equivalent
# html entities.
#----------------------------------------------------------------
sub _escape_html {
	my $str = shift;
	my %esc = (
		'<' => '&lt;',
		'>' => '&gt;',
		'"' => '&quot;',
		'&' => '&amp;',
	);
	my $re = join '|', map {quotemeta} keys %esc;
	$str =~ s/($re)/$esc{$1}/g;
	return $str;
}

#-----------------------------------------------------
# convert to shared package real resource path
#-----------------------------------------------------
sub _shared {
	return File::Spec->join( $SHARED, shift );
}

#-----------------------------------------------------
# Load file into a scalar without File::Slurp
# see perlfaq5
#-----------------------------------------------------
sub _slurp {
	my $filename = shift;
	my $fh       = IO::File->new($filename)
		or croak "Could not open $filename for reading";
	local $/ = undef; #enable localized slurp mode
	my $contents = <$fh>;
	close $fh
		or croak "Could not close $filename";
	return $contents;
}

1;

#------------------ T H E   E N D --------------------

__END__

=head1 NAME

Syntax::Highlight::Perl6 - Perl 6 Syntax Highlighter

=head1 SYNOPSIS

    ### NOTE: This is needed and will be removed in future releases
    use STD;
    use Syntax::Highlight::Perl6;

    # Creates the Perl6 syntax highlighter object
    my $p = Syntax::Highlight::Perl6->new(
        text => 'my $foo;'
    );

    # Prints html that can be embedded in your pages
    print $p->snippet_html;

    # Prints html with css (useful for full pages)
    print $p->simple_html;

    # Prints html that has a JavaScript node viewer
    print $p->full_html;

    # Prints ANSI escaped color sequences (useful for console and IRC output)
    print $p->ansi_text;

    # Prints an array of token records (useful for other libraries)
    print $p->tokens;

=head1 DESCRIPTION

C<Syntax::Highlight::Perl6> parses Perl 6 source code using an embedded STD.pm6. 
It matches parse tree nodes to colors then returns them in different output formats.
It can be used to create web pages with colorful source code samples in its
simple and snippet html modes, or it can be used as a learning tool in examining
STD.pm6's output using the JavaScript node viewer in its full html mode. Or you can
use its parse tree Perl 5 records to build your next great idea.

The available output formats are:

=over

=item *
    HTML (snippet,simple and full)

=item *
    ANSI escaped color sequences

=item *
    Perl 5 array of parse trees

=back

=head1 SUBROUTINES/METHODS

This is an object-oriented module. The following methods are available:

=head2 new(options)

Returns the syntax highlighting object. It needs a hash of options.
The following options are available:

=over 4

=item * text

I<This is a required option.>
This is where you should provide the Perl 6 code.

=item * rule

parse rule name for STD.pm6 to parse against (default: TOP)

=item * inline_resources

Flag to enable/disable CSS/JavaScript HTML inlining. (default: 0 (Disabled))

=item * resource_url

HTML resource url that will be appended when resource inlining is disabled.

=item * page_title

HTML page title for C<simple_html> and C<full_html> (default: q{})

=item * utf8_decode

Flag to enable/disable utf8 decoding. (default: 1 (Enabled))

=item * tmp_prefix

STD temporary files directory prefix. (default: q{})

=back

=head2 snippet_html

Returns the Perl 6 highlighted HTML string that can be embedded.
No CSS or JavaScript is inside.

=head2 simple_html

Returns the Perl 6 highlighted HTML string. The HTML code is the same
as C<full_html> but lacks a JavaScript Parse Tree Viewer.

=head2 full_html

Returns the Perl 6 highlighted HTML string. The HTML consists of a
JavaScript Parse Tree Viewer along with CSS-styling.
It can inlined if C<inline_resources> option is 1.

=head2 ansi_text

Returns a Perl highlighted ANSI escape color string.

=head2 tokens

Returns an array of hashes containing parsed token records.
The hash record is structured as:

    +-----------+---------+-----------+------------+---------+
    | Matched   | Matched | Matched   | Parse tree | Matched |
    | Last      | string  | rule      | separated  | Line    |
    | Position  | buffer  | name      | by spaces  | Number  |
    |           |         |           |            |         |
    | $last_pos | $buffer | $rule     | $tree      | $lineno |
    +-----------+---------+-----------+------------+---------+

An example of the C<tokens> method in action:

    use Data::Dumper;
    print Dumper($p->tokens);

The shortened output looks like:

    $VAR1 = {
      'tree' => '',
      'rule' => 0,
      'buffer' => '',
      'last_pos' => 0
    };
    $VAR2 = {
      'tree' => 'statementlist statement statement_modexpr statement_expr EXPR termish noun value number integer ',
      'rule' => 'number',
      'buffer' => '1',
      'last_pos' => 1
    };
    $VAR3 = {
      'tree' => 'statementlist eat_terminator ',
      'rule' => 0,
      'buffer' => ';',
      'last_pos' => 2
    };

=head1 INCOMPATIBILITIES

This module is dependent on Perl 5.10 features namely the regex engine 
and state variables (for STD.pm6). So Perl 5.8.x support will NOT be available
for now.

=head1 SEE ALSO

Discussion about this module and STD.pm6 is usually in #perl6
(irc://irc.freenode.net/perl6). This module lives in 
http://svn.perlide.org/padre/trunk/Syntax-Highlight-Perl6 . Larry Wall's 
C<STD.pm6> lives in http://svn.pugscode.org/pugs/src/perl6 . 

=head1 BUGS AND LIMITATIONS

If you find any bugs, please submit them to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=Syntax::Highlight::Perl6. Thanks.

These are the bugs that i am currently aware of:

=over 4

=item * Can't call method "bless" on an undefined value at STD.pm6 line 5269.

You have to put "use STD;" before using this module.

    use STD; # this must be first for now
    use Syntax::Highlight::Perl6;

=item * Directory 'lex' is created when using this module.

STD.pm6 caches digraphs and the matched rules in there.
So this is Pretty Voodoo Stuff. Otherwise it will be pretty slow.

=item * Slow startup when using the module for the first time

That is related to the creation of the cached 'lex'ing directory by STD.pm6.
I<This happens only once.>

=back

=head1 AUTHOR

Written by Ahmad M. Zawawi C<< <ahmad.zawawi at gmail.com> >> 
(C<azawawi> in C<#perl6>).

The project idea was inspired by Moritz Lenz (moritz) -
http://www.nntp.perl.org/group/perl.perl6.users/2008/07/msg788.html .
Larry Wall's C<gimme5>-generated Perl5 C<STD.pmc> is included to parse Perl 6 code.
The initial STD tree traversal code was written by Paweł Murias (pmurias).
It was replaced afterwards for performance reasons with Larry Wall's
C<redspans> traversal code. C<redspans> stands for C<red> for reductions,
and C<spans> from the "from/to span calculations".

Thanks guys. I could not have done it without you ;-)

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2008-2010 by Ahmad Zawawi

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

This library also includes the following libraries:

STD.pm6 by Larry Wall (Artistic License 2.0)

JQuery by John Resig (dual licensed under the MIT and GPL licenses).
