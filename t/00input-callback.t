use v6;
use Test;

# bootstrapping tests for Input callbacks

use NativeCall;
use LibXML;
use LibXML::InputCallback;

plan 19;

my $fh;
my %seen;

my LibXML::InputCallback $input-callbacks .= new: :callbacks{
        :match(sub ($f) {%seen<match>++; return $f.IO.e }),
        :open(sub ($f)  {%seen<open>++; $f.IO.open(:r) }),
        :read(sub ($fh, $bytes) {%seen<read>++; $fh.read($bytes)}),
        :close(sub ($fh) {%seen<close>++; $fh.close;}),
};

# low level callback checks on external API
my ($context) = $input-callbacks.make-contexts;
my $match = ($context.match)("example/test2.xml");
is-deeply $match, 1, "match callback when found";
$match = ($context.match)("example/does-not-exist.xml");
is-deeply $match, 0, "match callback when not found";
my $ptr := ($context.open)("example/test2.xml");
isa-ok $ptr, Pointer, 'open returns a pointer';
my ($handle, @guff) = $context.handles.values;
ok ($handle.defined && !@guff), 'Exactly one open handle';
isa-ok $handle.fh, IO::Handle, '$handle.fh';
my CArray[uint8] $buf .= new(0 xx 5);
my $n = ($context.read)($ptr, $buf, $buf.elems);
is $n, 5, 'read callback return value';
is $buf.map(*.chr).join, '<xsl>', 'return read buffer';
$n = ($context.close)($ptr);
is $n, 0, 'close callback return value';
ok !$context.handles, 'No longer have an open fh';
check-seen();

my $parser = LibXML.new: :$input-callbacks;

$parser.expand-xinclude = True;

my $dom;
lives-ok {$dom = $parser.parse: :file("example/test.xml")}, 'file parse';
check-seen();
is $dom.documentElement.firstChild.name, '#text', 'DOM sanity';

done-testing;

sub check-seen {
    ok %seen<match>, 'match callback called';
    ok %seen<open>, 'open callback called';
    ok %seen<read>, 'read callback called';
    ok %seen<close>, 'close callback called';
    %seen = ();
}
