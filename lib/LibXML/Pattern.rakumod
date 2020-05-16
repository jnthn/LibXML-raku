#| interface to libxml2 XPath patterns
unit class LibXML::Pattern;

=begin pod

    =head2 Synopsis

      =begin code :lang<raku>
      use LibXML;
      my LibXML::Pattern $pattern = complie('/x:html/x:body//x:div', :ns{ 'x' => 'http://www.w3.org/1999/xhtml' });
      # test a match on an LibXML::Node $node

      if $pattern.matchesNode($node) { ... }
      if $node ~~ $pattern { ... }

      # or on an LibXML::Reader

      if $reader.matchesPattern($pattern) { ... }

      # or skip reading all nodes that do not match

      print $reader.nodePath while $reader.nextPatternMatch($pattern);

      my LibXML::Pattern $pattern .= new( pattern, :ns{prefix => namespace_URI} );
      my Bool $matched = $pattern.matchesNode($node);
      =end code

    =head2 Description

    This is a Raku interface to libxml2's pattern matching support I<<<<<< http://xmlsoft.org/html/libxml-pattern.html >>>>>>. This feature requires recent versions of libxml2.

    Patterns are a small subset of XPath language, which is limited to
    (disjunctions of) location paths involving the child and descendant axes in
    abbreviated form as described by the extended BNF given below: 


      =begin code :lang<bnf>
      Selector ::=     Path ( '|' Path )*
      Path     ::=     ('.//' | '//' | '/' )? Step ( '/' Step )*
      Step     ::=     '.' | NameTest
      NameTest ::=     QName | '*' | NCName ':' '*'
      =end code
    For readability, whitespace may be used in selector XPath expressions even
    though not explicitly allowed by the grammar: whitespace may be freely added
    within patterns before or after any token, where

      =begin code :lang<bnf>
      token     ::=     '.' | '/' | '//' | '|' | NameTest
      =end code
    Note that no predicates or attribute tests are allowed.

    Patterns are particularly useful for stream parsing provided via the L<<<<<< LibXML::Reader >>>>>> interface.

    =head2 Methods
=end pod

use LibXML::Enums;
use LibXML::Native;
use LibXML::Node;
use LibXML::_Options;
use NativeCall;
use LibXML::ErrorHandling;
use Method::Also;

enum Flags (
    PAT_FROM_ROOT => 1 +< 8,
    PAT_FROM_CUR  => 1 +< 9
);

also does LibXML::_Options[
    %(
        :default(XML_PATTERN_DEFAULT),
        :xpath(XML_PATTERN_XPATH),
        :xssel(XML_PATTERN_XSSEL),
        :xsfield(XML_PATTERN_XSFIELD),
        :from-root(PAT_FROM_ROOT),
        :from-cur(PAT_FROM_CUR),
    )
];

has xmlPattern $!native;
method native { $!native }
has UInt $.flags;

submethod TWEAK(Str:D :$pattern!, :%ns, *%opts) {
    self.set-flags($!flags, |%opts);
    my CArray[Str] $ns .= new: |(%ns.kv.sort), Str;
    $!native .= new(:$pattern, :$!flags, :$ns)
        // die X::LibXML::OpFail.new(:what<Pattern>, :op<Compile>);
}

method compile(Str:D $pattern, |c) {
    self.new: :$pattern, |c;
}

=begin pod
    =head3 method new
    =begin code :lang<raku>
    method new( Str :$pattern!, Str :%ns, *%opts) returns LibXML::Pattern
    =end code
    The constructors of a pattern takes a pattern expression (as described by the
    BNF grammar above) and an optional Hash mapping prefixes to namespace
    URIs. The methods return a compiled pattern object. 

    Note that if the document has a default namespace, it must still be given an
    prefix in order to be matched (as demanded by the XPath 1.0 specification). For
    example, to match an element `<a xmlns="http://foo.bar"/>`, one should use a pattern like this: 

    =begin code :lang<raku>
    my LibXML::Pattern $pattern .= compile( 'foo:a', :ns(foo => 'http://foo.bar') );
    =end code

    =head3 method compile
    =begin code :lang<raku>
    method new( Str $pattern!, Str :%ns, *%opts) returns LibXML::Pattern
    =end code
    `LibXML::Pattern.compile($pattern)` is equivalent to `LibXML::Pattern.new(:$pattern)`.
=end pod

submethod DESTROY {
    .Free with $!native;
}

method !try-bool(Str:D $op, |c) {
    my $rv := $!native."$op"(|c);
    fail X::LibXML::OpFail.new(:what<Pattern>, :$op)
        if $rv < 0;
    $rv > 0;
}

multi method matchesNode(LibXML::Node $node) {
     self!try-bool('Match', $node.native);
}

multi method matchesNode(anyNode $node) {
    self!try-bool('Match', $node);
}

multi method ACCEPTS(LibXML::Pattern:D: LibXML::Node:D $node) {
    self.matchesNode($node);
}

=begin pod
=head3 method matches (alias ACCEPTS)
  =begin code :lang<raku>
  method matches(LibXML::Node:D $node) returns Bool
  my Bool $matched = $node ~~ $compiled-pattern;
  =end code
Given an LibXML::Node object, returns True if the value is matched by the
compiled pattern expression.
=end pod

method FALLBACK($key, |c) is rw {
    $.option-exists($key)
        ?? $.option($key, |c)
        !! die X::Method::NotFound.new( :method($key), :typename(self.^name) );
}

=begin pod

=head2 See Also

L<<<<<<LibXML::Reader>>>>>> for other methods involving compiled patterns.

=head2 Copyright

2001-2007, AxKit.com Ltd.

2002-2006, Christian Glahn.

2006-2009, Petr Pajas.

=head2 License

This program is free software; you can redistribute it and/or modify it under
the terms of the Artistic License 2.0 L<http://www.perlfoundation.org/artistic_license_2_0>.

=end pod
