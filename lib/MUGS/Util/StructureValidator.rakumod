# ABSTRACT: Validate basic data structures against a simple schema

use MUGS::Core;


class X::MUGS::InvalidStructure is X::MUGS {
    has Mu    $.data  is required;
    has Str:D $.type  is required;
    has Str:D $.path  is required;
    has Str:D $.error is required;

    method message() { "$.type.tclc() structure invalid at $.path: $.error (got {$.data.^name})" }
}


role Optional is export {
    method ACCEPTS(Mu $other) { self.^mixin_base.ACCEPTS($other) }
}

sub validate-structure($type, $data, $schema, $path = 'root') is export {
    use nqp;

    my &validate = -> \data, \schema, \path {
        if nqp::istype(schema, Optional) && !data.defined {
            # Optional matches undefined
        }
        elsif nqp::istype(schema, Positional) {
            X::MUGS::InvalidStructure.new(:$type, :path(path), :data(data),
                                          :error('must be Positional')).throw
                unless nqp::istype(data, Positional);

            if schema && schema.elems {
                my $s := schema[0];
                validate(data[$_], $s, path ~ "/$_") for data.keys;
            }
            elsif nqp::istype(schema, array) {
                X::MUGS::InvalidStructure.new(:$type, :path(path), :data(data),
                                              :error("must be {schema.raku}")).throw
                    unless nqp::istype(data, schema);
            }
        }
        elsif nqp::istype(schema, Associative) {
            X::MUGS::InvalidStructure.new(:$type, :path(path), :data(data),
                                          :error('must be Associative')).throw
                unless nqp::istype(data, Associative);

            validate(data{$_}, schema{$_}, path ~ "/$_") for schema.keys;
        }
        elsif nqp::istype(schema, Junction) {
            my str $jtype = nqp::getattr(nqp::decont(schema), Junction, '$!type');
            my $jstates  := nqp::getattr(nqp::decont(schema), Junction, '$!eigenstates');

            my $path = path ~ "/$jtype\(…)";
            if $jtype eq 'any' {
                for $jstates -> $state {
                    try validate(data, $state, $path);
                    last unless $!;
                }
                X::MUGS::InvalidStructure.new(:$type, :$path, :data(data),
                                              :error('no matching any junction variant')).throw if $!;
            }
            elsif $jtype eq 'all' {
                validate(data, $_, $path) for $jstates;
            }
            elsif $jtype eq 'none' {
                for $jstates -> $state {
                    try validate(data, $state, $path);
                    X::MUGS::InvalidStructure.new(:$type, :$path, :data(data),
                                                  :error('matched a none junction variant')).throw unless $!;
                }
            }
            elsif $jtype eq 'one' {
                my int $count = 0;
                for $jstates -> $state {
                    try validate(data, $state, $path);
                    X::MUGS::InvalidStructure.new(:$type, :$path, :data(data),
                                                  :error('matched too many one junction variants')).throw if !$! && $count++;
                }
                X::MUGS::InvalidStructure.new(:$type, :$path, :data(data),
                                              :error('no matching one junction variant')).throw;
            }
            else {
                X::MUGS::InvalidStructure.new(:$type, :$path, :data(data),
                                              :error("schema uses unknown Junction type '$jtype'")).throw;
            }
        }
        else {
            X::MUGS::InvalidStructure.new(:$type, :path(path), :data(data),
                                          :error("must be {schema.raku}")).throw
                unless schema.ACCEPTS(data);
        }
    }

    validate($data, $schema, $path)
}
