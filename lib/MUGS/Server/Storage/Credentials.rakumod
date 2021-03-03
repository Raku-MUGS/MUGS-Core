# ABSTRACT: Credential storage for identity authentication

use MUGS::Authentication;


#| User credential storage for a server
role MUGS::Server::Storage::Credentials {
    # Update: Add a credential to a user
    method add-credential(::?CLASS:D: Str:D :$username,
                          MUGS::Authentication::Credential:D :$credential) { ... }

    # Read: Queries by username
    multi method credentials-for-username(::?CLASS:D: Str:D $username,
                                          Str:D :$auth-type!) { ... }
    multi method credentials-for-username(::?CLASS:D: Str:D $username) { ... }
}
