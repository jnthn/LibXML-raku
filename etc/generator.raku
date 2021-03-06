#!env perl6
use v6;
use LibXML;
use LibXML::Document;
use LibXML::Element;

class Gen {
    class Type {
        has Str $.of;
        method Str {
            constant TypeMap = %(
                'char *' => 'Str',
                'char'   => 'byte',
                'const char *' => 'Str', # managed?
                'const xmlChar *' => 'xmlCharP', # managed?
                'xmlChar *' => 'xmlCharP',
                'double' => 'num64',
                'int' => 'int32',
                'unsigned int' => 'uint32',
                'int *' => 'Pointer[int32]',
                'const xmlChar * *' => 'Pointer[xmlCharP]', # managed?
                'void *' => 'Pointer',
                'void * *' => 'Pointer[Pointer]',
                'long' => 'long',
                'unsigned long' => 'ulong',
                'void' => Str,
            );

            do with $!of {
                s/'struct _'(.*)' *'/$0/;
                (TypeMap{$_}:exists)
                    ?? TypeMap{$_}
                    !! .subst(/'Ptr'$/, '');
            } // Str;
        }

    }
    class Field {
        has $.name;
        has Type $!type;
        method type { $!type.Str }
        has $.info;
        submethod TWEAK(:$type) { $!type .= new: :of($_) with $type }
    }

    multi sub abbrev($name where /^(xml|xslt|<[A..Z]><[a..z]>*)/, $base where /^($($0))[$|<!before [<[a..z]>]>]/) {
        my $n = $0.chars;
        abbrev($name.substr($n,*), $base.substr($n, *));
    }
    multi sub abbrev($name where /(<[A..Z]><[a..z]>*)$/, $base where /($($0))$/) {
        my $n = $0.chars;
        abbrev($name.substr(0, *-$n), $base.substr(0, *-$n) );
    }
    multi sub abbrev($name, $type) is default { $name }

    class Function {
        has $.name;
        has $.info;
        has Field $.return;
        has Field @.args;
        has $.lib = 'XML2';
        sub arg-str(Field:D $_) {
            .type.Str ~ ' $' ~ .name;
        }
        method Str(:$method) {
            my @args = @!args.clone;
            my $ret-type = .type with $!return;
            my $ret-str = do with $ret-type { " --> " ~ $_ } // '';
            my $info = $!info ?? " # " ~ $!info.trim !! '';
            my $type = $method ?? @args.shift.type !! $!return.type;

            my $short-name = do with $type { abbrev($!name, $_) } else { $!name };
            my $arg-str = @args.map(&arg-str).join: ', ';
            $short-name = $!name if !$method && $!name.chars - $short-name.chars <= 4;
            my $sym = $short-name eq $!name ?? ($method ?? '' !! " is export") !! " is symbol('$!name')";

            my $decl = $method ?? 'method' !! 'our sub';
            "$decl $short-name\({$arg-str}{$ret-str}\) is native\($!lib\)$sym \{*\}$info";
        }
    }

    class Struct {
        has $.name;
        has Field @.fields;
        has Function @.subs;
        has Function @.methods;
    }

    class File {
        has $.name;
        has $.summary;
        has $.description;
        has Hash %.enums;
        has Struct @.structs;
        has Function @.subs;
        constant Elem = LibXML::Element;
        my subset enumDef of Elem where .tagName = 'enum';
        method def($) is default { $*ERR.print('.') }
    }
}

my subset EnumDefElem of LibXML::Element where .tagName eq 'enum';
my subset FileDefElem of LibXML::Element where .tagName eq 'file';
my subset FieldDefElem of LibXML::Element where .tagName eq 'field';
my subset FunctionDefElem of LibXML::Element where .tagName eq 'function';
my subset StructDefElem of LibXML::Element where .tagName eq 'struct';

sub gen-dir(Str:D $ns) {
    with $*SPEC.catdir('etc', $ns, 'Native', 'Gen') {
        mkdir $_;
        $_;
    }
}

sub write-file(Gen::File:D $module, :$mod='LibXML', :$lib='XML2') {
    my $module-name = $module.name;
    my $path =  $*SPEC.catfile( gen-dir($mod), $module-name ~ '.pm6');
    {
        my $*OUT = open $path, :w;
        say 'use v6;';
        say "#  -- DO NOT EDIT --";
        say "# generated by: $*PROGRAM-NAME {@*ARGS}";
        say '';
        say "unit module {$mod}::Native::Gen::$module-name;";
        say "# $_:" with $module.summary;
        say "#    $_" with $module.description;
        if $mod eq 'LibXML' {
            say 'use ' ~ $mod ~ '::Native::Defs :$lib, :xmlCharP;';
        }
        else {
            say 'use LibXML::Native::Defs :xmlCharP;';
            say 'use ' ~ $mod ~ '::Native::Defs :$lib;';
        }

        for $module.enums.sort {
            my $name = .key;
            say '';
            say "enum $name is export (";
            for .value.pairs.sort {
                say "    {.key} => {.value},";
            }
            say ');';
        }

        for $module.structs {
            my $name = .name;
            my $repr = .fields ?? 'CStruct' !!  'CPointer';
            say '';
            say "class $name is repr('$repr') \{";
            for .fields {
                my $name = .name;
                my $type = .type;
                my $info = .Str.trim with .info;
                $info = ' # ' ~ $info if $info;
                say "    has $type \$\.$name;$info";
            }
            say '' if .fields && .subs;
            for .subs.sort(*.name).list {
                say "    " ~ .Str;
            }
            say '' if .subs && .methods;
            for .methods.sort(*.name).list {
                say "    " ~ .Str(:method);
            }
            say '}';
        }
        say '' if $module.subs;
        for $module.subs.list {
            say .Str;
        }
    }
    $*ERR.print: '!';

}

sub process-files(Str:D $xpath) {
    for $*Root{$xpath} -> FileDefElem $_ {
        my $name = .Str with .<@name>;
        my $summary = .<summary>[0].textContent;
        my $description = .<description>[0].textContent;
        my Gen::File $file .= new: :$name, :$summary, :$description;
        %*Files{$file.name} = $file;
        $*ERR.print('.');
    }
}

sub process-enums(Str:D $xpath) {
    for $*Root{$xpath} -> EnumDefElem $_ {
        my $name = .Str with .<@name>;
        my $type = .Str with .<@type>;
        my $file-name = .Str with .<@file>;
        my $value = .Str with .<@value>.Int;

        my $file = %*Files{$file-name} //= Gen::File.new: :name($file-name);
        $file.enums{$type}{$name} = $value;
        $*ERR.print('+');
    }
}

sub process-struct-fields(StructDefElem:D $_, Str:D $xpath, Gen::Struct :$struct!, ) {
    for .{$xpath} -> FieldDefElem $_ {
        my $name = .Str with .<@name>;
        my $type = .Str with .<@type>;
        my $info = .Str with .<@info>;

        my Gen::Field $field .= new: :$name, :$type, :$info;
        $struct.fields.push: $field;
        $*ERR.print('<');
    }
}

sub process-functions(Str:D $xpath, :$lib = 'XML2') {
    for $*Root{$xpath} -> FunctionDefElem $_ {
        my $name = .Str with .<@name>;
        my $type = .Str with .<@type>;
        my $file-name = .Str with .<@file>;
        my $info = .Str with .<info>;

        my Gen::Field ($return, @args);
        with .<return>[0] {
            my $type = .Str with .<@type>;
            my $info = .Str with .<@info>;
            $return .= new: :$type, :$info;
        }
        with .<arg> {
            @args = .map: {
                my $name = .Str with .<@name>;
                my $type = .Str with .<@type>;
                my $info = .Str with .<@info>;
                Gen::Field.new: :$name, :$type, :$info;
            }
        }

        my Gen::Function $function .= new: :$name, :$return, :$lib, :@args;

        my $method-type = .type with @args[0];
        my $return-type = .type with $return;
        my $method-struct = %*Structs{$_} with $method-type;
        my $return-struct = %*Structs{$_} with $return-type;
        with $method-struct {
            .methods.push: $function;
        }
        else {
            with $return-struct {
                .subs.push: $function;
            }
            else {
                my $file = %*Files{$file-name} //= Gen::File.new: :name($file-name);
                $file.subs.push: $function;
            }
        }
        $*ERR.print('>');
    }
}

sub process-structs(Str:D $xpath) {
    for $*Root{$xpath} -> StructDefElem $_ {
        my $name = .Str with .<@name>;
        my $file-name = .Str with .<@file>;

        my $file = %*Files{$file-name} //= Gen::File.new: :name($file-name);
        my Gen::Struct $struct .= new: :$name;
        process-struct-fields($_, 'field', :$struct);
        %*Structs{$name} //= $struct;
        $file.structs.push: $struct;
        $*ERR.print('*');
    }
}

sub MAIN(Str $api = "etc/libxml2-api.xml", Str :$mod='LibXML', Str :$lib='XML2') {
    my LibXML::Document:D $doc .= parse: :file($api);
    my LibXML::Element:D $*Root = $doc.root;
    my Gen::File %*Files;
    my Gen::Struct %*Structs;
    
    my %api = $*Root.childNodes.Hash;

    process-files('files/file');
    process-enums('symbols/enum');
    process-structs('symbols/struct');
    process-functions('symbols/function', :$lib);

    write-file($_, :$mod, :$lib) for %*Files.values.sort(*.name);
}
