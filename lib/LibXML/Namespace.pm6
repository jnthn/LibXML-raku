unit class LibXML::Namespace;
use LibXML::Native;
has $.root;
has xmlNs $.ns handles <type prefix>;
method proxy-node(xmlNs $ns, :$root!) { with $ns { $?CLASS.new: :$ns, :$root} else { $?CLASS }; }
