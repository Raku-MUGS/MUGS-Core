# ABSTRACT: Identities: account, user, player, persona, character, etc.

use MUGS::Core;

role MUGS::Identity { }

role MUGS::Persona { ... }
role MUGS::Account { ... }


#| A security entity (can be added to ACLs and be wallet for login/security credentials)
role MUGS::User does MUGS::Identity {
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
role MUGS::Character does MUGS::Identity {
    method screen-name { ... }
    method persona     { ... }
}


#| A distinct player persona, with its own screen name and character roster
role MUGS::Persona does MUGS::Identity {
    method screen-name       { ... }

    # A Character must belong to exactly one Persona at any given time
    method characters        { ... }

    # Both User and Persona must also be in the same Account, as defense
    # in depth against accidental ACL leaks; see Account.user-can-use-persona
    method authorized-users  { ... }

    method default-character { ... }
}


#| A collection for managing users and personas
role MUGS::Account does MUGS::Identity {
    method users                { ... }
    method personas             { ... }
    method user-can-use-persona { ... }
    method personas-for-user    { ... }
}


#| Name folding and validation semantics
role MUGS::Identity::NameFolding {
    # NOTE: The following were informed by RFC 8264 (PRECIS), and its
    #       applications in RFC 8265 (PRECIS for usernames and passwords) and
    #       RFC 8266 (PRECIS for nicknames).  Notwithstanding the warnings in
    #       https://tools.ietf.org/html/rfc8264#section-5.1, I made slightly
    #       different decisions given the differing intended use cases in MUGS,
    #       but those are good background reading for related issues.

    #| Apply one pass of MUGS-specific name folding in PRECIS-specified order
    method fold-name-once(Str:D $name) {
        # Foldcase used instead of lowercase so that the folded result can be
        # used in general identity searches
        my $stripped   = $name.trim.subst(/\s+/, ' ', :g);
        my $unmarked   = $stripped.samemark(' ');
        my $folded     = $unmarked.fc;
        my $compatible = $folded.NFKD.Str;
    }

    #| Iterate fold-name-once until it stabilizes, or 4 iterations max
    method fold-name(Str:D $name is copy) {
        my $folded = $name;
        repeat {
            $name   = $folded;
            $folded = self.fold-name-once($name);
        } until $name eq $folded || ++$ >= 4;

        $folded;
    }

    #| Determine if a name is baseline valid (mostly PRECIS rules),
    #| before any additional restrictions based on use case
    method is-valid-name(Str:D $name, Bool:D $id = False,
                         UInt:D $max-chars = 63 --> Bool:D) {
        # Codepoint category sets
        my constant $old-hangul-jamo     = < L V T >.Set;
        my constant $control             = < Cc Cf >.Set;
        my constant $letter-digits       = < Ll Lu Lo Nd Lm Mn Mc >.Set;
        my constant $other-letter-digits = < Lt Nl No Me >.Set;
        my constant $spaces              = < Zs >.Set;
        my constant $symbols             = < Sm Sc Sk So >.Set;
        my constant $punctuation         = < Pc Pd Ps Pe Pi Pf Po >.Set;
        my constant $freeform-valid      = [[&infix:<∪>]]
                                           $other-letter-digits, $spaces,
                                           $symbols, $punctuation;

        # PRECIS codepoint category tests
        for $name.ords -> $ord {
            # XXXX: RFC 5892 Exceptions (https://tools.ietf.org/html/rfc5892#section-2.6)

            # Reject unassigned characters
            my $category = uniprop($ord);
            return False if $category eq 'Cn';

            # Allow ASCII7 (https://tools.ietf.org/html/rfc8264#section-9.11)
            next if 0x21 <= $ord <= 0x7E;

            # XXXX: RFC 8264 JoinControl (https://tools.ietf.org/html/rfc8264#section-9.8)

            # Reject OldHangulJamo
            return False if uniprop($ord, 'Hangul_Syllable_Type') ∈ $old-hangul-jamo;

            # Reject ignorables
            return False if uniprop($ord, 'Default_Ignorable_Code_Point')
                         || uniprop($ord, 'Noncharacter_Code_Point');

            # Reject Control characters
            # XXXX: RFC 8264 Control (https://tools.ietf.org/html/rfc8264#section-9.12)
            #       is unclear about additional Control subtypes
            return False if $category ∈ $control;

            # Reject compatible-mapped characters
            return False if $ord.chr.NFKC.list.join(' ') ne $ord;

            # Allow LetterDigits that have made it this far
            next if $category ∈ $letter-digits;

            # Reject anything else if in IdentifierClass context
            return False if $id;

            # Reject unless one of the FreeformClass valid categories
            return False unless $category ∈ $freeform-valid;
        }

        # 4 foldings reach full stability, and folded result is non-empty
        my $folded = self.fold-name($name);
        return False unless $folded && $folded eq self.fold-name-once($folded);

        # Reasonable length
        return False if $folded.chars > $max-chars
                     || $name.chars   > $max-chars;

        True;
    }

    #| Determine if a name is valid for the screen name use case
    method is-valid-screen-name(Str:D $name --> Bool:D) {
        # Any generally valid name is a valid screen name
        self.is-valid-name($name)
    }

    #| Determine if a name is valid for the username use case
    method is-valid-username(Str:D $name --> Bool:D) {
        # Does not contain spaces
        return False if $name ~~ /\s/;

        # Is an otherwise valid name in identifier context
        self.is-valid-name($name, :id)
    }

}
