# ABSTRACT: Registries for tracking implementation classes


#| Registry for UI-agnostic implementation subclasses
role MUGS::Util::ImplementationRegistry[::Constraint] {
    my %implementation;

    method register-implementation(Str:D $moniker, Constraint:U $class) {
        %implementation{$moniker} = $class;
    }

    method implementation-class(Str:D $moniker) {
        %implementation{$moniker}
    }

    method implementation-exists(Str:D $moniker) {
        %implementation{$moniker}:exists
    }

    method known-implementations() {
        %implementation.keys
    }
}


#| Registry for UI-specific implementation subclasses
role MUGS::Util::UIRegistry[::Constraint] {
    my %ui-class;

    method register-ui(Str:D $ui, Str:D $moniker, Constraint:U $class) {
        %ui-class{$ui}{$moniker} = $class;
    }

    method ui-class(Str:D $ui, Str:D $moniker) {
        %ui-class{$ui}{$moniker}
    }

    method ui-exists(Str:D $ui, Str:D $moniker) {
        %ui-class{$ui}{$moniker}:exists
    }

    multi method known-games(Str:D $ui) {
        my %for-ui := %ui-class{$ui} || {};
        %for-ui.keys.sort
    }

    multi method known-uis() {
        %ui-class.keys.sort
    }

    multi method known-uis(Str:D $moniker) {
        %ui-class.keys.sort.grep({ %ui-class{$_}{$moniker}:exists })
    }
}
