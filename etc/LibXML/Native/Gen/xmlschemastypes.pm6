use v6;
#  -- DO NOT EDIT --
# generated by: etc/generator.p6 

unit module LibXML::Native::Gen::xmlschemastypes;
# implementation of XML Schema Datatypes:
#    module providing the XML Schema Datatypes implementation both definition and validity checking 
use LibXML::Native::Defs :LIB, :xmlCharP;

enum xmlSchemaWhitespaceValueType is export (
    XML_SCHEMA_WHITESPACE_COLLAPSE => 3,
    XML_SCHEMA_WHITESPACE_PRESERVE => 1,
    XML_SCHEMA_WHITESPACE_REPLACE => 2,
    XML_SCHEMA_WHITESPACE_UNKNOWN => 0,
)

sub xmlSchemaCleanupTypes() is native(LIB) is export {*};
sub xmlSchemaCollapseString(xmlCharP $value --> xmlCharP) is native(LIB) is export {*};
sub xmlSchemaInitTypes() is native(LIB) is export {*};
sub xmlSchemaWhiteSpaceReplace(xmlCharP $value --> xmlCharP) is native(LIB) is export {*};