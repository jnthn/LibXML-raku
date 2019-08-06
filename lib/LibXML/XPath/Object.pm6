use v6;
unit class LibXML::XPath::Object;

use LibXML::Native;
use LibXML::Node :iterate-set, :NodeSetElem;
use LibXML::Node::Set;

has xmlXPathObject:D $.native is required handles<type>;
method native { with self { $!native } else { xmlXPathObject } }

my subset XPathRange is export(:XPathRange) where Bool|Numeric|Str|LibXML::Node::Set;
my subset XPathDomain is export(:XPathDomain) where XPathRange|LibXML::Node;

method coerce(XPathDomain $content is copy) {
    if $content ~~ LibXML::Node|LibXML::Node::Set {
        $content .= native;
        # node-sets can't be multiply referenced
        $content .= copy if $content ~~ xmlNodeSet;
    }

    my xmlXPathObject:D $native = xmlXPathObject.coerce($content);
    self.new: :$native;
}

method value(Bool :$literal,  --> XPathRange) {
    given $!native.value {
        when xmlNodeSet {
            given iterate-set(NodeSetElem, .copy) {
                $literal ?? .to-literal !! $_;
            }
        }
        default { $_ }
    }
}

submethod TWEAK { $!native.Reference }
submethod DESTROY { $!native.Unreference }
