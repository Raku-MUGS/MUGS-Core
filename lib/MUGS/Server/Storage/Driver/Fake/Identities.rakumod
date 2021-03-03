# ABSTRACT: Backing storage for server-side identities, fake (ephemeral in-memory) driver

# XXXX: Thread safety?

unit module MUGS::Server::Storage::Driver::Fake;

use MUGS::Message;
use MUGS::Identity;
use MUGS::Server::Storage::Identities;


#| A security entity (can be added to ACLs and be wallet for login/security credentials)
class User does MUGS::User {
    has Str:D           $.username is required;
    has MUGS::Account:D $.account  is required;
}


#| A playable game entity
class Character does MUGS::Character {
    has Str:D           $.screen-name is required;
    has MUGS::Persona:D $.persona     is required;
}


#| A distinct player persona, with its own screen name and character roster
class Persona does MUGS::Persona {
    has Str:D             $.screen-name is required;
    has MUGS::User:D      @.authorized-users;
    has MUGS::Character:D @.characters;

    method add-authorized-users(::?CLASS:D: *@users) {
        @!authorized-users.append(@users);
    }

    method add-character(::?CLASS:D: MUGS::Character:D $character) {
        @!characters.push($character);
    }

    method default-character(::?CLASS:D:) {
        @!characters[0]
    }
}


#| A collection for managing users and personas
class Account does MUGS::Account {
    has MUGS::User:D    @.users;
    has MUGS::Persona:D @.personas;

    method add-user(::?CLASS:D: MUGS::User:D $user) {
        @!users.push($user);
    }

    method add-persona(::?CLASS:D: MUGS::Persona:D $persona) {
        @!personas.push($persona);
    }

    method user-can-use-persona(::?CLASS:D: MUGS::User:D $user,
                                MUGS::Persona:D $persona) {
           $user ∈ @!users && $persona ∈ @!personas
        && $user ∈ $persona.authorized-users
    }

    method personas-for-user(::?CLASS:D: MUGS::User:D $user) {
        $user ∈ @!users ?? @!personas.grep: { $user ∈ .authorized-users }
                        !! ()
    }
}


#| Identity storage for a server, fake (ephemeral in-memory) driver
class Identities
 does MUGS::Server::Storage::Identities {
    has @!accounts;
    has %!user;
    has %!persona;
    has %!character;

    method new-account(::?CLASS:D:) {
        my $account = Account.new;
        @!accounts.push: $account;
        $account
    }

    method new-user(::?CLASS:D: Str:D :$username!, MUGS::Account:D :$account!) {
        my $user = User.new(:$username, :$account);
        $account.add-user($user);
        %!user{$username} = $user
    }

    method new-persona(::?CLASS:D: Str:D :$screen-name!, MUGS::Account:D :$account!) {
        my $persona = Persona.new(:$screen-name);
        $account.add-persona($persona);
        %!persona{$screen-name} = $persona
    }

    method new-character(::?CLASS:D: Str:D :$screen-name!, MUGS::Persona:D :$persona!) {
        my $character = Character.new(:$screen-name, :$persona);
        $persona.add-character($character);
        %!character{$screen-name} = $character
    }

    method user-by-name(::?CLASS:D: Str:D $username) {
        %!user{$username} or self.invalid-username($username)
    }

    method persona-by-name(::?CLASS:D: Str:D $screen-name) {
        %!persona{$screen-name} or self.invalid-persona($screen-name)
    }

    method character-by-name(::?CLASS:D: Str:D $screen-name) {
        %!character{$screen-name} or self.invalid-character($screen-name)
    }
}
