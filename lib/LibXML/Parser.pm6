unit class LibXML::Parser;

use LibXML::Config;
use LibXML::Native;
use LibXML::Enums;
use LibXML::Document;
use LibXML::PushParser;
use LibXML::Parser::Context;
use Method::Also;

constant config = LibXML::Config;

has Bool $.html is rw = False;
has Bool $.line-numbers is rw = False;
has UInt $.flags is rw = config.default-parser-flags();
has Str $.URI is rw;
has $.sax-handler is rw;
has xmlEncodingStr $.enc is rw;
has $.input-callbacks is rw = config.input-callbacks;
multi method input-callbacks is rw { $!input-callbacks }
multi method input-callbacks($!input-callbacks) {}

use LibXML::_Options;
constant %Opts = %( flat %LibXML::Parser::Context::Opts,
                    (:URI, :html, :line-numbers,
                     :sax-handler, :input-callbacks, :enc,)
                  );
also does LibXML::_Options[%Opts];

# Perl 5 compat
multi method recover is rw {
    Proxy.new(
        FETCH => { 
            my $recover = $.get-flag($!flags, 'recover');
            $recover && $.get-flag($!flags, 'suppress-errors') ?? 2 !! $recover;
        },
        STORE => -> $, UInt() $v {
            $.set-flag($!flags, 'recover', $v >= 1);
            $.set-flag($!flags, 'suppress-errors', $v >= 2);
        }
    );
}
multi method recover($v) { $.recover = $v }

method get-flags(:$html, *%opts) {
    my UInt $flags = $!flags;
    $.set-flag($flags, 'load-ext-dtd', False)
        if $html;
    $.set-flags($flags, |%opts);

    $flags;
}

method !make-handler(xmlParserCtxt :$native, *%opts) {
    my UInt $flags = self.get-flags(|%opts);
    LibXML::Parser::Context.new: :$native, :$flags, :$!line-numbers, :$!input-callbacks, :$.sax-handler;
}

method !publish(:$URI, LibXML::Parser::Context :$ctx!, xmlDoc :$native = $ctx.native.myDoc) {
    my LibXML::Document:D $doc .= new: :$ctx, :$native;
    $doc.URI = $_ with $URI;
    self.processXIncludes($doc, :$ctx)
        if $.expand-xinclude;

    with $!sax-handler {
        .publish($doc);
    }
    else {
        $doc;
    }
}

method processXIncludes (
    LibXML::Document $_,
    LibXML::Parser::Context:D :$ctx = self!make-handler(:native(xmlParserCtxt.new)),
    *%opts --> Int)
is also<process-xincludes> {
    my xmlDoc $doc = .native;
    my $flags = self.get-flags(|%opts);
    $ctx.try: { $doc.XIncludeProcessFlags($flags) }
}

proto method parse(|c) is also<load> {
    with self {return {*}} else { self.new.parse(|c) }
}

multi method parse(Str:D() :$string!,
                   Bool() :$html = $!html,
                   Str() :$URI = $!URI,
                   xmlEncodingStr :$enc = $!enc,
                   *%opts 
                  ) {

    my LibXML::Parser::Context $ctx = self!make-handler: :$html, |%opts;

    $ctx.try: {
        my xmlParserCtxt:D $native = $html
        ?? htmlMemoryParserCtxt.new: :$string
        !! xmlMemoryParserCtxt.new: :$string;

        $native.input.filename = $_ with $URI;
        $ctx.set-native: $native;
        $native.ParseDocument;
    };
    self!publish: :$ctx;
}

multi method parse(Blob:D :$buf!,
                   Bool() :$html = $!html,
                   Str() :$URI = $!URI,
                   xmlEncodingStr :$enc = $!enc,
                   *%opts,
                  ) {

    my xmlParserCtxt:D $native = $html
       ?? htmlMemoryParserCtxt.new(:$buf, :$enc)
       !! xmlMemoryParserCtxt.new(:$buf);

    $native.input.filename = $_ with $URI;

    my LibXML::Parser::Context $ctx = self!make-handler: :$native, :$html, |%opts;
    $ctx.try: { $native.ParseDocument };
    self!publish: :$ctx;
}

multi method parse(Str() :$file!,
                   Bool() :$html = $!html,
                   xmlEncodingStr :$enc = $!enc,
                   Str :$URI = $!URI,
                   *%opts,
                  ) {
    my LibXML::Parser::Context $ctx = self!make-handler: :$html, |%opts;

    $ctx.try: {
        my xmlParserCtxt $native = $html
           ?? htmlFileParserCtxt.new(:$file, :$enc)
           !! xmlFileParserCtxt.new(:$file);
        die "unable to load file: $file"
            without $native;
        $ctx.set-native: $native;
        $native.ParseDocument;
    };

    self!publish: :$URI, :$ctx;
}

multi method parse(UInt :$fd!,
                   Str :$URI = $!URI,
                   Bool() :$html = $!html,
                   xmlEncodingStr :$enc = $!enc,
                   *%opts,
                  ) {

    my LibXML::Parser::Context $ctx = self!make-handler: :$html, |%opts;
    my UInt $flags = self.get-flags(|%opts, :$html);
    my xmlDoc $doc;

    $ctx.try: {
        my xmlParserCtxt $native = $html
           ?? htmlParserCtxt.new
           !! xmlParserCtxt.new;
        $ctx.set-native: $native;
        $doc = $native.ReadFd($fd, $URI, $enc, $flags);
    };

    self!publish: :$ctx, :native($doc);
}

multi method parse(IO::Handle :$io!,
                   Str :$URI = $io.path.path,
                   |c) {
    my UInt:D $fd = $io.native-descriptor;
    self.parse( :$fd, :$URI, |c);
}

multi method parse(IO() :io($path)!, |c) {
    my IO::Handle $io = $path.open(:bin, :r);
    $.parse(:$io, |c);
}

multi method parse(Str() :location($file)!, |c) {
    $.parse(:$file, |c);
}

# parse from a Miscellaneous source
multi method parse(Any:D $src, |c) is default {
    my Pair $in = do with $src {
        when UInt       { :fd($_) }
        when IO::Handle
        |    IO::Path   { :io($_) }
        when Blob       { :buf($_) }
        when Str  { m:i:s/^ '<'/ ?? :string($_) !! :file($_) }
        default { fail "Unrecognised parser input: {.perl}"; }
    }
    $.parse( |$in, |c );
}

has LibXML::PushParser $!push-parser;
method init-push { $!push-parser = Nil }
multi method push(Str() $chunk) {
    with $!push-parser {
        .push($chunk);
    }
    else {
        $_ .= new: :$chunk, :$!html, :$!flags, :$!line-numbers, :$.sax-handler;
    }
}
multi method parse(:$chunk!, |c) {
   $.parse-chunk($chunk, |c);
}
multi method parse(:$terminate!, |c) {
   $.parse-chunk(:$terminate, |c);
}
multi method push(@chunks) is default { self.push($_) for @chunks }
method parse-chunk($chunk?, :$terminate, |c) {
    $.push($_) with $chunk;
    $.finish-push(|c)
        if $terminate;
}
method finish-push (
    Str :$URI = $!URI,
    Bool :$recover = $.recover,
)
{
    with $!push-parser {
        my $doc := .finish-push(:$URI, :$recover, :$!sax-handler);
        $_ = Nil;
        $doc;
    }
    else {
        die "no active push parser";
    }
}

method parse-balanced(Str() :$string!, LibXML::Document :$doc) {
    use LibXML::DocumentFragment;
    my LibXML::DocumentFragment $frag .= new: :$doc;
    $frag.parse: :balanced, :$string, :$.sax-handler, :$.keep-blanks;
    with $!sax-handler {
        .publish($frag);
    }
    else {
        $frag;
    }
}

# cheat's implementation of Perl 5's .generate function
# re-serializes, rather than rerunning SAX actions on the DOM
method reparse(LibXML::Document:D $doc!, |c) is also<generate> {
    # document DOM with the SAX handler
    my $string = $doc.Str;
    $.parse( :$string, |c );
}

method load-catalog(Str:D $filename) {
    xmlLoadCatalog($filename);
}

submethod TWEAK(Str :$catalog, :html($), :line-numbers($), :flags($) = 0, :URI($), :sax-handler($), :build-sax-handler($), :input-callbacks($), *%opts) {
    self.load-catalog($_) with $catalog;
    $!flags = self.get-flags(|%opts);
}

method FALLBACK($key, |c) is rw {
    $.option-exists($key)
        ?? $.option($key, |c)
        !! die X::Method::NotFound.new( :method($key), :typename(self.^name) );
}

=begin pod
=head1 NAME

LibXML::Parser - Parsing XML Data with LibXML

=head1 SYNOPSIS



  use LibXML;

  # Parser constructor
  
  my LibXML $parser .= new: |%opts;
  
  # Parsing XML
  
  $dom = LibXML.parse(
      location => $file-or-url,
      # parser options ...
    );
  $dom = LibXML.parse(
      file => $file-or-url,
      # parser options ...
    );
  $dom = LibXML.parse(
      string => $xml-string,
      # parser options ...
    );
  $dom = LibXML.parse(
      io => $perl-file-handle,
      # parser options ...
    );
  # dispatch to above depending on type
  $dom = $parser.parse($src ...);
  			  
  # Parsing HTML
  
  $dom = LibXML.parse(..., :html);
  $dom = $parser.parse(..., :html);
  $parser.html = True; $parser.parse(...);
  			  
  # Parsing well-balanced XML chunks
  			       
  my LibXML::DocumentFragment $chunk = $parser.parse-balanced( string => $wbxml);
  
  # Processing XInclude
  
  $parser.process-xincludes( $doc );
  $parser.processXIncludes( $doc );
  
  # Push parser
  			    
  $parser.parse-chunk($string, :$terminate);
  $parser.init-push();
  $parser.push(@strings);
  $doc = $parser.finish-push( :$recover );
  
  # Set/query parser options
                      
  $parser.option-exists($name);
  $parser.get-option($name);
  $parser.set-option($name,$value);
  $parser.set-options(name => $value, ...);
  
  # XML catalogs
                      
  $parser.load-catalog( $catalog-file );

=head1 PARSING

An XML document is read into a data structure such as a DOM tree by a piece of
software, called a parser. LibXML currently provides four different parser
interfaces:

=item1 * A DOM Pull-Parser

=item1 * A DOM Push-Parser

=item1 * A SAX Parser

=item1 * A DOM based SAX Parser.


=head2 Creating a Parser Instance

LibXML provides an OO interface to the libxml2 parser functions.

=begin item1
new

  
  my LibXML $parser .= new();
  my LibXML $parser .= new: :$opt1, :$opt2, ...;

Create a new XML and HTML parser instance. Each parser instance holds default
values for various parser options. Optionally, one can pass options to override
default.

=end item1


=head2 DOM Parser

One of the common parser interfaces of LibXML is the DOM parser. This parser
reads XML data into a DOM like data structure, so each tag can get accessed and
transformed.

LibXML's DOM parser is not only capable to parse XML data, but also (strict)
HTML files. There are three ways to parse documents - as a string, as a Perl
filehandle, or as a filename/URL. The return value from each is a L<<<<<< LibXML::Document >>>>>> object, which is a DOM object.

All of the functions listed below will throw an exception if the document is
invalid. To prevent this causing your program exiting, wrap the call in a
try {} block

=begin item1
parse

  my LibXML::Document::HTML $dom;

  $dom = LibXML.parse(
      location => $file-or-url,
      :$html, :$URI, :$enc,
      # parser options ...
    );
  $dom = LibXML.parse(
      string => $xml-string,
      :$html, :$URI, :$enc,
      # parser options ...
    );
  $dom = LibXML.parse(
      io => $perl-path-or-file-handle,
      :$html, :$URI, :$enc,
      # parser options ...
    );
  $dom = LibXML.parse(
      buf => $perl-blob-or-buf,
      :$html, :$URI, :$enc,
      # parser options ...
    );
  $dom = LibXML.parse(
      fd => $file-descriptor-num,
      :$html, :$URI, :$enc,
      # parser options ...
    );
  $dom = LibXML.parse( $src, :$html, :$URI, :$enc,
      # parser options ...
  );
  $dom = $parser.parse(...);
  			  

This function provides an interface
to the XML parser that parses given file (or URL), string, or input stream to a
DOM tree. The function can be called as a class method or an object method. In
both cases it internally creates a new parser instance passing the specified
parser options; if called as an object method, it clones the original parser
(preserving its settings) and additionally applies the specified options to the
new parser. See the constructor C<<<<<< new >>>>>> and L<<<<<< Parser Options >>>>>> for more information. 

=end item1

=begin item1
parse: :html


  use LibXML::Document :HTML;  
  my HTML $dom = LibXML.parse: :html, ...;
  my HTML $dom = $parser.parse: :html, ...;
  			  

The :html option provides an interface to the HTML parser.

=end item1

Parsing HTML may cause problems, especially if the ampersand ('&') is used.
This is a common problem if HTML code is parsed that contains links to
CGI-scripts. Such links cause the parser to throw errors. In such cases libxml2
still parses the entire document as there was no error, but the error causes
LibXML to stop the parsing process. However, the document is not lost. Such
HTML documents should be parsed using the I<<<<<< recover >>>>>> flag. By default recovering is deactivated.

The functions described above are implemented to parse well formed documents.
In some cases a program gets well balanced XML instead of well formed documents
(e.g. an XML fragment from a database). With LibXML it is not required to wrap
such fragments in the code, because LibXML is capable even to parse well
balanced XML fragments.

=begin item1
parse-balanced

  my LibXML::DocumentFragment $chunk = $parser.parse-balanced( string => $wbxml );

This function parses a well balanced XML string into a L<<<<<< LibXML::DocumentFragment >>>>>>. The string argument contains the input XML string.

=end item1

By default LibXML does not process XInclude tags within an XML Document (see
options section below). LibXML allows one to post-process a document to expand
XInclude tags.

=begin item1
process-xincludes

  $parser.process-xincludes( $doc );

After a document is parsed into a DOM structure, you may want to expand the
documents XInclude tags. This function processes the given document structure
and expands all XInclude tags (or throws an error) by using the flags and
callbacks of the given parser instance.

Note that the resulting Tree contains some extra nodes (of type
XML_XINCLUDE_START and XML_XINCLUDE_END) after successfully processing the
document. These nodes indicate where data was included into the original tree.
if the document is serialized, these extra nodes will not show up.

Remember: A Document with processed XIncludes differs from the original
document after serialization, because the original XInclude tags will not get
restored!

If the parser flag "expand-xinclude" is set to True, you need not to post process
the parsed document.

=end item1

=begin item1
processXIncludes

  $parser.processXIncludes( $doc );

This is an alias to process-xincludes, but through a JAVA like function name.

=end item1

=begin item1
parse: :file

  $doc = $parser.parse: :file( $xmlfilename );

The :file option parses an XML document from a file or network; $xmlfilename can be either a filename or an URL.

=end item1

=begin item1
parse: :io

  $doc = $parser.parse: :io( $io-fh );

parse: :io parses an IO::Handle object.

=end item1

=begin item1
parse: :string

  $doc = $parser.parse: :string( $xmlstring);

This function parses an XML document that is
available as a single string in memory. You can pass an optional base URI string to the function.



  my $doc = $parser.parse: :string($xmlstring);
  my $doc = $parser.parse: :string($xmlstring), :$URI;

=end item1

=begin item1
parse: :html

  use LibXML::Document :HTML;
  my HTML $doc;
  $doc = $parser.parse: :html, :file( $htmlfile) , |%opts;
  $doc = $parser.parse: :html, :io($io-fh), |%opts;
  $doc = $parser.parse: :html: :string($htmlstring), |%opts;
  # etc..

=end item1

=head2 Push Parser

LibXML provides a push parser interface. Rather than pulling the data from a
given source the push parser waits for the data to be pushed into it.

Please see L<LibXML::PushParser> for more details.

For Perl 5 compatibilty, the following methods are available to invoke a push-parser from a LibXML::Parser object.

=begin item1
init-push

  $parser.init-push();

Initializes the push parser.

=end item1

=begin item1
push

  $parser.push(@chunks);

This function pushes the data stored inside the array to libxml2's parser. Each
entry in @chunks may be a string or blob! This method can be called repeatedly.

=end item1

=begin item1
finish-push

  $doc = $parser.finish-push( :$URI, :$recover );

This function returns the result of the parsing process. If this function is
called without a parameter it will complain about non well-formed documents. If
:$recover is True, the push parser can be used to restore broken or non well formed (XML) documents.

=end item1


=head2 Pull Parser (Reader)

LibXML also provides a pull-parser interface similar to the XmlReader interface
in .NET. This interface is almost streaming, and is usually faster and simpler
to use than SAX. See L<<<<<< LibXML::Reader >>>>>>.


=head2 Direct SAX Parser

LibXML provides a direct SAX parser in the L<<<<<< LibXML::SAX >>>>>> module.


=head2 DOM based SAX Parser

LibXML also provides a DOM based SAX parser. The SAX parser is defined in the
module LibXML::SAX::Parser. As it is not a stream based parser, it parses
documents into a DOM and traverses the DOM tree instead.

The API of this parser is exactly the same as any other Perl SAX2 parser. See
XML::SAX::Intro for details.

Aside from the regular parsing methods, you can access the DOM tree traverser
directly, using the reparse() method:



  my LibXML::Document $doc = build-yourself-a-document();
  my $saxparser = $LibXML::SAX::Parser.new( ... );
  $parser.reparse( $doc );

This is useful for serializing DOM trees, for example that you might have done
prior processing on, or that you have as a result of XSLT processing.

I<<<<<< WARNING >>>>>>

This is NOT a streaming SAX parser. This parser reads the
entire document into a DOM and serialises it. If you want a streaming SAX
parser look at the L<<<<<< LibXML::SAX >>>>>> man page


=head1 SERIALIZATION

LibXML provides some functions to serialize nodes and documents. The
serialization functions are described on the L<<<<<< LibXML::Node >>>>>> or the L<<<<<< LibXML::Document >>>>>> documentation. LibXML checks three global flags that alter the serialization process:

=item1 * skip-xml-declaration

=item1 * skip-dtd

=item1 * tag-expansion

of that three functions only `tag-expansion` is available for all
serialization functions.

Because LibXML does these flags not itself, one has to define them locally as
the following example shows:



  temp LibXML.skip-xml-declaration = True;
  temp LibXML.skip-dtd = True;
  tmep LibXML.tag-expansion = False;

If skip-xml-declaration is True, the XML declaration is omitted
during serialization.

If skip-dtd is defined is True, an existing DTD would not be serialized with
the document.

If tag-expansion is True empty tags are displayed as open
and closing tags rather than the shortcut. For example the empty tag I<<<<<< foo >>>>>> will be rendered as I<<<<<< &lt;foo&gt;&lt;/foo&gt; >>>>>> rather than I<<<<<< &lt;foo/&gt; >>>>>>.


=head1 PARSER OPTIONS

Handling of libxml2 parser options has been unified and improved in LibXML
1.70. You can now set default options for a particular parser instance by
passing them to the constructor as C<<<<<< LibXML-&gt;new({name=&gt;value, ...}) >>>>>> or C<<<<<< LibXML-&gt;new(name=&gt;value,...) >>>>>>. The options can be queried and changed using the following methods (pre-1.70
interfaces such as C<<<<<< $parser-&gt;load-ext-dtd(0) >>>>>> also exist, see below): 

=begin item1
option-exists

  $parser.option-exists($name);

Returns True if the current LibXML version supports the option C<<<<<< $name >>>>>>, otherwise returns False (note that this does not necessarily mean that the option
is supported by the underlying libxml2 library).

=end item1

=begin item1
get-option

  $parser.get-option($name);

Returns the current value of the parser option C<<<<<< $name >>>>>>.

=end item1

=begin item1
set-option

  $parser.set-option($name,$value);
  $parser.option($name) = $value;
  $parser."$name"() = $value;

Sets option C<<<<<< $name >>>>>> to value C<<<<<< $value >>>>>>.

=end item1

=begin item1
set-options

  $parser.set-options: |%options;

Sets multiple parsing options at once.

=end item1

Each of the flags listed below is labeled

=begin item1
/parser/

if it can be used with a C<<<<<< LibXML >>>>>> parser object (i.e. passed to C<<<<<< LibXML-&gt;new >>>>>>, C<<<<<< LibXML-&gt;set-option >>>>>>, etc.) 

=end item1

=begin item1
/html/

if it is applicable to HTML parsing

=end item1

=begin item1
/reader/

if it can be used with the C<<<<<< LibXML::Reader >>>>>>.

=end item1

Unless specified otherwise, the default for boolean valued options is False. 

The available options are:

=begin item1
dtd

/parser, html, reader/ (Introduced with the Perl 6 port)

This enables dtd loading and validation, as well as entity expansion. It should only be set in a secure enviroment that has trusted inputs.

This is a bundled option. Setting `$parser.dtd = True` is equivalent to setting: `$parser.load-ext-dtd = True; $parser.validation = True; $parser.network = True; $parser.expand-entities = True`.

=end item1

=begin item1
URI

/parser, html, reader/

In case of parsing strings or file handles, LibXML doesn't know about the base
uri of the document. To make relative references such as XIncludes work, one
has to set a base URI, that is then used for the parsed document.

=end item1

=begin item1
line-numbers

/parser/

If this option is activated, libxml2 will store the line number of each element
node in the parsed document. The line number can be obtained using the C<<<<<< line-number() >>>>>> method of the C<<<<<< LibXML::Node >>>>>> class (for non-element nodes this may report the line number of the containing
element). The line numbers are also used for reporting positions of validation
errors. 

IMPORTANT: Due to limitations in the libxml2 library line numbers greater than
65535 will be returned as 65535. Please see L<<<<<< http://bugzilla.gnome.org/show_bug.cgi?id=325533 >>>>>> for more details. 

=end item1

=begin item1
enc

/parser(*), html, reader(*)/

character encoding of the input.

(*) This is applicable to all HTML parsing modes and XML parsing from files, or file descriptors.
(*) C<:enc> is a read-only Reader option.

=end item1

=begin item1
recover

/parser, html, reader/

recover from errors; possible values are 0, 1, and 2

A True value turns on recovery mode which allows one to parse broken XML or
HTML data. The recovery mode allows the parser to return the successfully
parsed portion of the input document. This is useful for almost well-formed
documents, where for example a closing tag is missing somewhere. Still, LibXML
will only parse until the first fatal (non-recoverable) error occurs, reporting
recoverable parsing errors as warnings. To suppress even these warnings, use
recover=>2.

Note that validation is switched off automatically in recovery mode.

=end item1

=begin item1
expand-entities

/parser, reader/

substitute entities; default is False

Note that although this flag disables entity substitution, it does not prevent
the parser from loading external entities; when substitution of an external
entity is disabled, the entity will be represented in the document tree by an
XML_ENTITY_REF_NODE node whose subtree will be the content obtained by parsing
the external resource; Although this nesting is visible from the DOM it is
transparent to XPath data model, so it is possible to match nodes in an
unexpanded entity by the same XPath expression as if the entity were expanded.
See also L<LibXML::Config>.external-entity-loader. 

=end item1

=begin item1
load-ext-dtd

/parser, reader/

load the external DTD subset while parsing. Unless
specified, LibXML sets this option to False.

This flag is also required for DTD Validation, to provide complete attribute,
and to expand entities, regardless if the document has an internal subset. Thus
switching off external DTD loading, will disable entity expansion, validation,
and complete attributes on internal subsets as well.

=end item1

=begin item1
complete-attributes

/parser, reader/

create default DTD attributes; type Bool

=end item1

=begin item1
validation

/parser, reader/

validate with the DTD; type Bool

=end item1

=begin item1
suppress-errors

/parser, html, reader/

suppress error reports; type Bool

=end item1

=begin item1
suppress-warnings

/parser, html, reader/

suppress warning reports; type Bool

=end item1

=begin item1
pedantic-parser

/parser, html, reader/

pedantic error reporting; type Bool

=end item1

=begin item1
blanks

/parser, html, reader/

keep blank nodes; default true

=end item1

=begin item1
defdtd

/html/

add a default DOCTYPE  DTD when the input html lacks one; default is True

=end item1

=begin item1
expand-xinclude

/parser, reader/

Implement XInclude substitution; type Bool

Expands XInclude tags immediately while parsing the document. Note that the
parser will use the URI resolvers installed via C<<<<<< LibXML::InputCallback >>>>>> to parse the included document (if any).

=end item1

=begin item1
xinclude-nodes

/parser, reader/

do not generate XINCLUDE START/END nodes; default True

=end item1

=begin item1
network

/parser, html, reader/

Enable network access; default False

All attempts to fetch non-local resources (such as DTD or
external entities) will fail unless set to True (or custom callbacks are defined).

It may be necessary to use the flag C<<<<<< recover >>>>>> for processing documents requiring such resources while networking is off. 

=end item1

=begin item1
clean-namespaces

/parser, reader/

remove redundant namespaces declarations during parsing; type Bool

=end item1

=begin item1
cdata

/parser, html, reader/

merge CDATA as text nodes; default True

=end item1

=begin item1
base-fix

/parser, reader/

fixup XINCLUDE xml#base URIS; default True

=end item1

=begin item1
huge

/parser, html, reader/

relax any hardcoded limit from the parser; type Bool. Unless
specified, LibXML sets this option to False.

Note: the default value for this option was changed to protect against denial
of service through entity expansion attacks. Before enabling the option ensure
you have taken alternative measures to protect your application against this
type of attack.

=end item1


The following obsolete methods trigger parser options in some special way:

=begin item1
recover-silently



  $parser.recover-silently = True;

If called without an argument, returns true if the current value of the C<<<<<< recover >>>>>> parser option is 2 and returns false otherwise. With a true argument sets the C<<<<<< recover >>>>>> parser option to 2; with a false argument sets the C<<<<<< recover >>>>>> parser option to 0. 

=end item1

=head1 XML CATALOGS

C<<<<<< libxml2 >>>>>> supports XML catalogs. Catalogs are used to map remote resources to their local
copies. Using catalogs can speed up parsing processes if many external
resources from remote addresses are loaded into the parsed documents (such as
DTDs or XIncludes). 

Note that libxml2 has a global pool of loaded catalogs, so if you apply the
method C<<<<<< load-catalog >>>>>> to one parser instance, all parser instances will start using the catalog (in
addition to other previously loaded catalogs). 

Note also that catalogs are not used when a custom external entity handler is
specified. At the current state it is not possible to make use of both types of
resolving systems at the same time.

=begin item1
load-catalog

  $parser.load-catalog( $catalog-file );

Loads the XML catalog file $catalog-file.



  # Global external entity loader (similar to ext-ent-handler option
  # but this works really globally, also in XML::LibXSLT include etc..)
  
  LibXML::externalEntityLoader(\&my-loader);

=end item1


=head1 ERROR REPORTING

LibXML throws exceptions during parsing, validation or XPath processing (and
some other occasions). These errors can be caught by using `try` or `CATCH` blocks.

LibXML throws errors as they occur. If the `try` is omitted, LibXML will always halt your script
by throwing an exception.

=head1 COPYRIGHT

2001-2007, AxKit.com Ltd.

2002-2006, Christian Glahn.

2006-2009, Petr Pajas.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=end pod
