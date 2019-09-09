unit module LibXML::Native::Defs;

use GTK::Simple::NativeLib;
constant LIB is export(:LIB) = $*VM.config<dll> ~~ /dll/ ?? xml-lib() !! 'xml2';
constant BIND-LIB is export(:BIND-LIB) =  %?RESOURCES<libraries/xml6>;
constant Opaque is export(:Opaque) = 'CPointer';
constant xmlCharP is export(:xmlCharP) = Str;
my constant XML_XMLNS_NS is export(:XML_XMLNS_NS) = 'http://www.w3.org/2000/xmlns/';
my constant XML_XML_NS is export(:XML_XML_NS) = 'http://www.w3.org/XML/1998/namespace';
