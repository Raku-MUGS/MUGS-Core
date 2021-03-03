# ABSTRACT: Credential storage for identity authentication, fake (ephemeral in-memory) driver

use MUGS::Authentication;
use MUGS::Server::Storage::Credentials;


#| User credential storage for a server, fake (ephemeral in-memory) driver
class MUGS::Server::Storage::Driver::Fake::Credentials
 does MUGS::Server::Storage::Credentials {
    has %!credentials;

    method add-credential(::?CLASS:D: Str:D :$username,
                          MUGS::Authentication::Credential:D :$credential) {
        %!credentials{$username}.append($credential);
    }

    multi method credentials-for-username(::?CLASS:D: Str:D $username, Str:D :$auth-type!) {
        (%!credentials{$username} // Empty).grep: { .enabled && .auth-type eq $auth-type };
    }

    multi method credentials-for-username(::?CLASS:D: Str:D $username) {
        (%!credentials{$username} // Empty).grep(*.enabled);
    }
}
