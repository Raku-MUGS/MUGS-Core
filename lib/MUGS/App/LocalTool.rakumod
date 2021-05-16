# ABSTRACT: Common logic used by local tools (admin, dev, release, etc.)


use Terminal::ANSIColor;


# Use subcommand MAIN args
%PROCESS::SUB-MAIN-OPTS = :named-anywhere;


#| Base class for local tool programs
class MUGS::App::LocalTool {

    #| Quote a command in shell-like fashion (for display, not security)
    method quote-command(@cmd) {
        my @quoted = @cmd.map: {
            my $escaped = .subst('"', '\\"', :g);
            $escaped ~~ /^ '-'**^3 '/'? \w+ $/ ?? $escaped !! qq{"$escaped"}
        };
    }

    #| Show a command before executing it
    method show-command(@cmd) {
        put colored("\n=== " ~ self.quote-command(@cmd).join(' '), 'yellow');
    }

    #| Indicate all done successfully
    method all-success() {
        put colored("\n--> All commands executed successfully.", 'bold blue');
    }

    #| Highlight an error message and then exit with status 1
    method error-out(Str:D $error) {
        note colored("\n!!! $error\n", 'red');
        exit 1;
    }

    #| Ensure a condition is true, or exit with an error message
    method ensure(&condition, Str:D $error) {
        condition() || self.error-out($error)
    }

    #| Error and exit unless current directory looks like a MUGS repo root
    method ensure-at-repo-root() {
        self.ensure: { 'META6.json'.IO.e && '.git'.IO.d && 'lib/MUGS'.IO.d },
                     'Must run this command from a MUGS repo checkout root.';
    }

    #| Error and exit unless launched from parent dir of MUGS repo checkouts
    method ensure-at-repo-parent() {
        self.ensure: { dir('.', test => { "$_/.git".IO.d && "$_/lib/MUGS".IO.d }).elems },
                     "Must run this command from the {colored('parent', 'bold')} dir of the MUGS repo checkouts.";
    }

    #| Print a command, and if :force is set, run it successfully or error and exit
    method run-or-exit(@cmd, :$force) {
        self.show-command(@cmd);
        return unless $force;

        self.ensure: { run @cmd }, 'Command execution failed, exiting.';
    }
}
