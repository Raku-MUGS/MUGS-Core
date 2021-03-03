# ABSTRACT: Authentication credentials

use MUGS::Util::ImplementationRegistry;

use Crypt::SodiumPasswordHash;


class MUGS::Authentication { ... }


#| Credential for a single auth method for a single user
role MUGS::Authentication::Credential {
    has Bool:D $.enabled = True;

    method auth-type { ... }
    method verify    { ... }
    method to-blob   { ... }
    method from-blob { ... }

    method register() {
        MUGS::Authentication.register-implementation(self.auth-type, self.WHAT);
    }
}


#| Registry for authentication credential implementations
class MUGS::Authentication
 does MUGS::Util::ImplementationRegistry[MUGS::Authentication::Credential] { }


#| Password credentials
class MUGS::Authentication::Password does MUGS::Authentication::Credential {
    has Str $!hashed-password;

    method auth-type { 'password' }

    method new(Str:D :$password!, |c) {
        self.bless(:hashed-password(sodium-hash($password)), |c)
    }

    submethod BUILD(Str:D :$!hashed-password!) { }

    method verify(Str:D $password) {
        $.enabled && sodium-verify($!hashed-password, $password);
    }

    method to-blob() {
        $!hashed-password.encode
    }

    method from-blob(Blob:D $blob, |c) {
        self.bless(:hashed-password($blob.decode), |c)
    }
}


# Register valid credential implementation classes
MUGS::Authentication::Password.register;
