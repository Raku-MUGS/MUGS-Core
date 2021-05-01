# ABSTRACT: Messages, serialization, message status, message-related exceptions

use JSON::Fast;
use MUGS::Core;
use MUGS::Util::StructureValidator;


#| Invalid message, base class
class X::MUGS::Message is X::MUGS { }

#| Invalid message, undecodable
class X::MUGS::Message::Undecodable is X::MUGS::Message {
    method message { "Received undecodable message" }
}

#| Invalid message, refers to invalid entity
class X::MUGS::Message::InvalidEntity is X::MUGS::Message {
    has $.type is required;
    has $.id   is required;

    method message { "{$.type.tclc} '$.id' is unknown" }
}

#| Invalid message, missing required data field
class X::MUGS::Message::MissingData is X::MUGS::Message {
    has $.field is required;

    method message { "Missing required data field '$.field'" }
}

#| Invalid message, field data has wrong type
class X::MUGS::Message::InvalidDataType is X::MUGS::Message {
    has $.field is required;
    has $.type  is required;

    method message { "Data field '$.field' has wrong type (should be {$.type.^name})" }
}


#| Invalid request
class X::MUGS::Request is X::MUGS::Message { }

#| Invalid request, unstructured version
class X::MUGS::Request::AdHoc is X::MUGS::Request {
    has $.message is required;
}

#| Invalid request, missing action type
class X::MUGS::Request::MissingAction is X::MUGS::Request {
    method message { "No action type specified" }
}

#| Invalid request, invalid action type
class X::MUGS::Request::InvalidAction is X::MUGS::Request {
    method message { "Action type is not valid" }
}


#| Response invalid or had errors
class X::MUGS::Response is X::MUGS::Message { }

#| Response status unknown
class X::MUGS::Response::UnknownStatus is X::MUGS::Response {
    has $.status is required;

    method message { "Received a response with unknown status '$.status'" }
}

#| Response without matching request
class X::MUGS::Response::NoMatchingRequest is X::MUGS::Response {
    has $.request-id is required;

    method message { "Received a response claiming request ID '{ $.request-id // 'UNKNOWN' }' with no matching request" }
}

#| Responder says request was invalid or had a semantic error
class X::MUGS::Response::InvalidRequest is X::MUGS::Response {
    has $.error   is required;
    has $.request is required;

    method message { "Request invalid: { $.error || 'UNKNOWN ERROR' }" }
}

#| Server had an internal error
class X::MUGS::Response::ServerError is X::MUGS::Response {
    has $.error is required;

    method message { "Server had an internal error: { $.error || 'UNKNOWN ERROR' }" }
}


#| Base class for client <-> server messages
class MUGS::Message {
    has $.id      = NEXT-ID;
    has $.created = now;
    has %.data;

    # Subclasses only need to convert from/to simple structures, and Message
    # automatically handles serialization from/to JSON or other wire formats
    method to-json(::?CLASS:D: --> Str)     { to-json self.to-struct }
    method from-json(::?CLASS:U: Str $json) { self.from-struct: from-json $json }

    #| Validate %!data against a schema and return validated Map
    method validated-data(::?CLASS:D: %schema) {
        validate-structure('message', %!data, %schema);
        %!data
    }
}


#| A request packet, optionally acting on a successful response
class MUGS::Message::Request is MUGS::Message {
    has $.type is required;
    has &.on-success;
    has $.on-failure;

    # Convert Request objects to/from serializable structures
    method to-struct(::?CLASS:D: --> Hash) {
        { :$.id, :$.type, :%.data }
    }

    method from-struct(::?CLASS:U: $struct) {
        return unless $struct       ~~ Map:D
                   && $struct<id>   ~~ Int:D
                   && $struct<type> ~~ Str:D
                   && $struct<data> ~~ Map:D;

        my %settable := hash($struct< id type data >:kv);
        try self.new: |%settable
    }
}


#| A request packet sent by a character in the context of a particular game
class MUGS::Message::Request::InGame is MUGS::Message::Request {
    has GameID:D $.game-id        is required;
    has Str:D    $.character-name is required;

    # Convert Request::InGame objects to/from serializable structures
    method to-struct(::?CLASS:D: --> Hash) {
        { :$.id, :$.type, :$.game-id, :$.character-name, :%.data }
    }

    method from-struct(::?CLASS:U: $struct) {
        return unless $struct                 ~~ Map:D
                   && $struct<id>             ~~ Int:D
                   && $struct<type>           ~~ Str:D
                   && $struct<game-id>        ~~ GameID:D
                   && $struct<character-name> ~~ Str:D
                   && $struct<data>           ~~ Map:D;

        my %settable := hash($struct< id type game-id character-name data >:kv);
        try self.new: |%settable
    }
}


#| A response packet, carrying request status and request ID
class MUGS::Message::Response is MUGS::Message {
    has $.request-id      is required;
    has Status:D $.status is required;

    # Convert Response objects to/from serializable structures
    method to-struct(::?CLASS:D: --> Hash) {
        { :$.id, :$.request-id, :%.data,  :status($.status.Int) }
    }

    method from-struct(::?CLASS:U: $struct) {
        return unless $struct             ~~ Map:D
                   && $struct<id>         ~~ Int:D
                   && $struct<request-id> ~~ Int:D
                   && $struct<status>     ~~ Int:D
                   && $struct<data>       ~~ Map:D;

        my %settable := hash($struct< id request-id data >:kv);
        %settable<status> = Status($struct<status>);
        try self.new: |%settable
    }
}


#| An in-game push packet, not expecting a response
class MUGS::Message::Push is MUGS::Message {
    has Str:D    $.type           is required;

    # Convert Push objects to/from serializable structures
    method to-struct(::?CLASS:D: --> Hash) {
        { :$.id, :$.type, :%.data }
    }

    method from-struct(::?CLASS:U: $struct) {
        return unless $struct                 ~~ Map:D
                   && $struct<id>             ~~ Int:D
                   && $struct<type>           ~~ Str:D
                   && $struct<data>           ~~ Map:D;

        my %settable := hash($struct< id type data >:kv);
        try self.new: |%settable
    }
}
