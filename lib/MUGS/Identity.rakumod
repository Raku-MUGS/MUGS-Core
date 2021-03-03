# ABSTRACT: Identities: account, user, player, persona, character, etc.

use MUGS::Core;


role MUGS::Persona { ... }
role MUGS::Account { ... }


#| A security entity (can be added to ACLs and be wallet for login/security credentials)
role MUGS::User {
    method username { ... }
    method account  { ... }

    method Str(::?CLASS:D:) { $.username }

    method can-use-persona(::?CLASS:D: MUGS::Persona:D $persona) {
        $.account.user-can-use-persona(self, $persona)
    }

    method available-personas(::?CLASS:D:) {
        $.account.personas-for-user(self)
    }

    method default-persona(::?CLASS:D:) {
        self.available-personas[0] // MUGS::Persona
    }
}


#| A playable game entity
role MUGS::Character {
    method screen-name { ... }
    method persona     { ... }
}


#| A distinct player persona, with its own screen name and character roster
role MUGS::Persona {
    method screen-name       { ... }

    # A Character must belong to exactly one Persona at any given time
    method characters        { ... }

    # Both User and Persona must also be in the same Account, as defense
    # in depth against accidental ACL leaks; see Account.user-can-use-persona
    method authorized-users  { ... }

    method default-character { ... }
}


#| A collection for managing users and personas
role MUGS::Account {
    method users                { ... }
    method personas             { ... }
    method user-can-use-persona { ... }
    method personas-for-user    { ... }
}
