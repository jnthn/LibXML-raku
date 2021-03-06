#include "xml6_reader.h"
#include <assert.h>

DLLEXPORT int
xml6_reader_next_sibling(xmlTextReaderPtr self) {
    int rv = xmlTextReaderNextSibling(self);
    if (rv == -1) {
        int depth = xmlTextReaderDepth(self);
	rv = xmlTextReaderRead(self);
        while (rv == 1 && xmlTextReaderDepth(self) > depth) {
	    rv = xmlTextReaderNext(self);
        }
        if (rv == 1) {
	    if (xmlTextReaderDepth(self) != depth) {
                rv = 0;
	    } else if (xmlTextReaderNodeType(self) == XML_READER_TYPE_END_ELEMENT) {
                rv = xmlTextReaderRead(self);
	    }
        }
    }
    return rv;
}

static int match_element(xmlTextReaderPtr self, char *name, char *URI) {
    return (xmlTextReaderNodeType(self) == XML_READER_TYPE_ELEMENT)
    && ((!URI && !name)
        || (!URI && xmlStrcmp((const xmlChar*)name, xmlTextReaderConstName(self) ) == 0 )
        || (URI && xmlStrcmp((const xmlChar*)URI, xmlTextReaderConstNamespaceUri(self)) == 0
            && (!name || xmlStrcmp((const xmlChar*)name, xmlTextReaderConstLocalName(self)) == 0)));
}

DLLEXPORT int
xml6_reader_next_element(xmlTextReaderPtr self, char *name, char *URI) {
    int rv;

    if (name && *name == 0) name = NULL;
    if (URI && *URI == 0) URI = NULL;

    do {
        rv = xmlTextReaderRead(self);
        if (match_element(self, name, URI)) {
	    break;
        }
    } while (rv == 1);

    return rv;
}

DLLEXPORT int
xml6_reader_next_sibling_element(xmlTextReaderPtr self, char *name, char *URI) {
    int rv;

    if (name && *name == 0) name = NULL;
    if (URI && *URI == 0) URI = NULL;

    do {
        rv = xml6_reader_next_sibling(self);
        if (match_element(self, name, URI)) {
	    break;
        }
    } while (rv == 1);

    return rv;
}

DLLEXPORT int
xml6_reader_skip_siblings(xmlTextReaderPtr self) {
    int depth = xmlTextReaderDepth(self);
    int rv = -1;
    if (depth > 0) {
        do {
            rv = xmlTextReaderNext(self);
        } while (rv == 1 && xmlTextReaderDepth(self) >= depth);
        if (xmlTextReaderNodeType(self) != XML_READER_TYPE_END_ELEMENT) {
	    rv = -1;
        }
    }
    return rv;
}

DLLEXPORT int
xml6_reader_finish(xmlTextReaderPtr self) {
    int rv;

    for (rv = 1; rv == 1; rv = xmlTextReaderNext(self))
        ;

    rv++; /* we want 0 - fail, 1- success */
    return rv;
}

DLLEXPORT int
xml6_reader_next_pattern_match(xmlTextReaderPtr self, xmlPatternPtr compiled) {
    xmlNodePtr node = NULL;
    int rv;

    assert(compiled != NULL);

    do {
        rv = xmlTextReaderRead(self);
        node = xmlTextReaderCurrentNode(self);
        if (node == NULL || xmlPatternMatch(compiled, node)) {
	    break;
        }
    } while (rv == 1);

    return rv;
}
