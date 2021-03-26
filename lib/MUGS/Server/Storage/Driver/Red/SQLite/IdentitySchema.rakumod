# ABSTRACT: Red model definitions for SQLite identity tables

unit module MUGS::Server::Storage::Driver::Red::SQLite::IdentitySchema;

use MUGS::Identity;

use Red;


my sub model-ref($model) {
    (:model($?PACKAGE.^name ~ '::' ~ $model), :require($?PACKAGE.^name)).Slip
}

# XXXX: Created (Datetime .= now), deleted, enabled, updated, desc ...

model Identity is table<mugs_identities> is export {
    has Int $.id            is id;
    has Str $.deconfused    is column{ :unique };
    has Str $.identity-type is column;
    has Str $.name          is column;
}

model Account is table<mugs_accounts> does MUGS::Account is export {
    has Int $.id          is id;
    has     @.users       is relationship( *.account-id, model-ref('User')    );
    has     @.personas    is relationship( *.account-id, model-ref('Persona') );

    method user-can-use-persona($user, $persona) {
           $user.account-id eq $persona.account-id eq self.id
        && $persona.authorized.grep(*.user-id eq $user.id).so
    }

    method personas-for-user($user) {
        $user.account-id eq self.id
            ?? $user.authorized-personas.grep(*.account-id eq self.id)
            !! ()
    }
}


model User is table<mugs_users> does MUGS::User is export {
    has Int $.id          is id;
    has Int $.account-id  is referencing{  :column<id>,  model-ref('Account')        };
    has Str $.username    is column{ :unique };
    has     $.account     is relationship( *.account-id, model-ref('Account')        );
    has     @.credentials is relationship( *.user-id,    model-ref('Credential')     );
    has     @.authorized  is relationship( *.user-id,    model-ref('AuthorizedUser') );

    method authorized-personas { @.authorized.map(*.persona) }
}


model Persona is table<mugs_personas> does MUGS::Persona is export {
    has Int $.id          is id;
    has Int $.account-id  is referencing{  :column<id>,  model-ref('Account')        };
    has Str $.screen-name is column{ :unique };
    has     $.account     is relationship( *.account-id, model-ref('Account')        );
    has     @.characters  is relationship( *.persona-id, model-ref('Character')      );
    has     @.authorized  is relationship( *.persona-id, model-ref('AuthorizedUser') );

    method authorized-users  { @.authorized.map(*.user) }
    method default-character { @.characters[0] // MUGS::Character }
    method add-authorized-users(*@users) {
        self.authorized.create(:persona-id(self.id), :user-id($_.id)) for @users;
    }
}


model Character is table<mugs_characters> does MUGS::Character is export {
    has Int $.id          is id;
    has Int $.persona-id  is referencing{  :column<id>,  model-ref('Persona') };
    has Str $.screen-name is column{ :unique };
    has     $.persona     is relationship( *.persona-id, model-ref('Persona') );
}


model AuthorizedUser is table<mugs_authorized_users> is export {
    has Int $.id          is id;
    has Int $.persona-id  is referencing{  :column<id>,  model-ref('Persona') };
    has Int $.user-id     is referencing{  :column<id>,  model-ref('User')    };
    has     $.persona     is relationship( *.persona-id, model-ref('Persona') );
    has     $.user        is relationship( *.user-id,    model-ref('User')    );
}


model Credential is table<mugs_credentials> is export {
    has Int  $.id         is id;
    has Int  $.user-id    is referencing{  :column<id>, model-ref('User') };
    has Int  $.enabled    is column;
    has Str  $.auth-type  is column;
    has Blob $.data-blob  is column;
    has      $.user       is relationship( *.user-id,   model-ref('User') );
}
