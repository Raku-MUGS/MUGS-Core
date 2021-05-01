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
        else {
            X::MUGS::InvalidStructure.new(:$type, :path(path), :data(data),
                                          :error("must be {schema.raku}")).throw
                unless data ~~ schema;
        }
    }

    validate($data, $schema, $path)
}
