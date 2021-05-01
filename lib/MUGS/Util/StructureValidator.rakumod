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
    return if $schema ~~ Optional && !$data.defined;

    given $schema {
        when Positional {
            X::MUGS::InvalidStructure.new(:$type, :$path, :$data,
                                          :error('must be Positional')).throw
                unless $data ~~ Positional;
            for $data.kv -> $i, $v {
                validate-structure($type, $v, $schema[0], "$path/$i")
            }
        }
        when Associative {
            X::MUGS::InvalidStructure.new(:$type, :$path, :$data,
                                          :error('must be Associative')).throw
                unless $data ~~ Associative;
            for $schema.kv -> $k, $s {
                validate-structure($type, $data{$k}, $s, "$path/$k")
            }
        }
        default {
            X::MUGS::InvalidStructure.new(:$type, :$path, :$data,
                                          :error("must be {$schema.raku}")).throw
                unless $data ~~ $schema;
        }
    }
}
