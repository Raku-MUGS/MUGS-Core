# ABSTRACT: Tool for releasing a MUGS repo


use Terminal::ANSIColor;


# Use subcommand MAIN args
%PROCESS::SUB-MAIN-OPTS = :named-anywhere;


# A standard three-part version
my regex version { ^ $<major>=[\d+] '.' $<minor>=[\d+] '.' $<patch>=[\d+] $ }

subset Version  of Str where &version;
subset Codename of Any where Bool|Str;


#| Quote command in shell-like fashion
sub quote-command(@cmd) {
    my @quoted = @cmd.map: {
        my $escaped = .subst('"', '\\"', :g);
        $escaped ~~ /^ '-'**^3 '/'? \w+ $/ ?? $escaped !! qq{"$escaped"}
    };
}


#| Run a command successfully or error out and exit
sub run-or-exit(@cmd, :$force) {
    put colored('=== ' ~ quote-command(@cmd).join(' '), 'yellow');
    return unless $force;

    unless run @cmd {
        note '!!! Command execution failed, exiting.';
        exit 1;
    }

    put '';
}


#| Perform automated release steps on the current repository
multi MAIN(
    Version  :$version!,   #= Standard three-part version string (A.B.C)
    Codename :$codename!,  #= Code name (or --/codename to not use one)
    Bool     :$force,      #= Actually execute commands (instead of just print them)
) is export {
    %*ENV<NEXT_MUGS_VERSION> = $version;

    run-or-exit($_, :$force) for
        « git tag -a "v$version" -m "Release $version" »,
       (« git tag -a "$codename" -m "Codename: $codename" » if $codename),
        « git push »,
        « git push --tags »,
        « zef install . »,
        « fez upload »,
        ;

    put $force ?? colored('--> All release commands executed successfully.', 'bold blue')
               !! colored('!!! All release commands SKIPPED without --force !!!', 'red')
}
