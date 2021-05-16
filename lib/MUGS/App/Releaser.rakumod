# ABSTRACT: Tool for releasing a MUGS repo


use MUGS::App::LocalTool;


#| A standard three-part version
my regex version { ^ $<major>=[\d+] '.' $<minor>=[\d+] '.' $<patch>=[\d+] $ }

subset Version  of Str where &version;  #= Improves output of USAGE
subset Codename of Any where Bool|Str;  #= Improves output of USAGE


class MUGS::App::Releaser is MUGS::App::LocalTool {

    #| Do basic startup prep
    method prep(Version:D $version) {
        %*ENV<NEXT_MUGS_VERSION> = $version;

        self.ensure-at-repo-root;
    }

    #| Check whether repo is in good shape to release
    method check(Version:D $version) {
        self.prep($version);

        my $today        = ~Date.today;
        my $escaped-dots = $version.subst('.', "\\.", :g);

        self.run-or-exit($_, :force) for
            « mi6 test »,
            « fez checkbuild »,
            « grep $escaped-dots Changes »,
            « grep "$escaped-dots\\s\\+$today" Changes »,
            ;

        self.all-success;
    }

    #| Perform automated release steps on the current repo
    method release(Version:D :$version, Codename:D :$codename, Bool :$force = False) {
        self.prep($version);

        self.run-or-exit($_, :$force) for
            « git tag -a "v$version" -m "Release $version" »,
           (« git tag -a "$codename" -m "Codename: $codename" » if $codename ~~ Str:D),
            « git push »,
            « git push --tags »,
            « zef install . »,
            « fez upload »,
            ;

        $force ?? self.all-success
               !! self.error-out('All release commands SKIPPED without --force !!!');
    }
}


#| Check whether repo is in good shape to release
multi MAIN(
    'check',
    Version :$version!,  #= Standard three-part version string (A.B.C)
) is export {
    MUGS::App::Releaser.new.check($version)
}


#| Perform automated release steps on the current repo
multi MAIN(
    Version  :$version!,   #= Standard three-part version string (A.B.C)
    Codename :$codename!,  #= Code name (or --/codename to not use one)
    Bool     :$force,      #= Actually execute commands (instead of just print them)
) is export {
    MUGS::App::Releaser.new.release(:$version, :$codename, :$force);
}
