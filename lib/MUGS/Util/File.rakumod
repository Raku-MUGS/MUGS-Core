# ABSTRACT: File management utilities

use MUGS::Core;

use YAMLish;


#| Base class for all MUGS-generated file-related exceptions
class X::MUGS::File is X::MUGS {
    has Str:D $.type is required;
    has       $.file;
}

#| Didn't even specify a file at all
class X::MUGS::File::Unspecified is X::MUGS::File {
    method message { "$.type.tclc() file is unspecified, null, or empty" }
}

#| File doesn't actually exist
class X::MUGS::File::Missing is X::MUGS::File {
    method message { "$.type.tclc() file '$.file' does not exist" }
}

#| File can't be read
class X::MUGS::File::Unreadable is X::MUGS::File {
    method message { "$.type.tclc() file '$.file' is not readable" }
}

#| File can't be parsed
class X::MUGS::File::Unparseable is X::MUGS::File {
    method message { "$.type.tclc() file '$.file' is not parseable" }
}

#| File can't be written
class X::MUGS::File::Unwritable is X::MUGS::File {
    method message { "$.type.tclc() file '$.file' is not writable" }
}

#| Dir containing file can't be written
class X::MUGS::File::DirUnwritable is X::MUGS::File {
    has $.dir;
    method message {
        "Directory '$.dir' containing $.type.lc() file '$.file' is not writable"
    }
}


#| Ensure a specified IO::Path exists and is readable
multi ensure-readable(Str:D $type, IO::Path:D $file, :$base-dir) is export {
    my $f = $base-dir ?? $file.absolute($base-dir).IO !! $file;
    X::MUGS::File::Missing.new(   :$type, :file($f)).throw unless $f.e;
    X::MUGS::File::Unreadable.new(:$type, :file($f)).throw unless $f.r;
}

#| Ensure a specified filename exists and is readable
multi ensure-readable(Str:D $type, $file, :$base-dir) is export {
    X::MUGS::File::Unspecified.new(:$type, :$file).throw unless $file;
    ensure-readable($type, $file.IO, :$base-dir);
}

#| Ensure a specified IO::Path either exists and is writable, or does not exist
#| and the parent is writable
multi ensure-writable(Str:D $type, IO::Path:D $file, :$base-dir) is export {
    my $f = $base-dir ?? $file.absolute($base-dir).IO !! $file;
    if $f.e {
        X::MUGS::File::Unwritable.new(:$type, :file($f)).throw unless $f.w;
    }
    else {
        my $dir = $f.parent;
        X::MUGS::File::DirUnwritable.new(:$type, :file($f.basename), :$dir).throw
             unless $dir.w;
    }
}

#| Ensure a specified filename either exists and is writable, or does not exist
#| and the parent is writable
multi ensure-writable(Str:D $type, $file, :$base-dir) is export {
    X::MUGS::File::Unspecified.new(:$type, :$file).throw unless $file;
    ensure-writable($type, $file.IO, :$base-dir);
}


# XXXX: YAMLish isn't thread-safe (https://github.com/Leont/yamlish/issues/19),
#       so manually lock it
my Lock $yaml-lock .= new;


#| Load a YAML file, either just the first doc (default) or all of them (:all)
multi load-yaml-file(Str:D $type, IO::Path:D $file, :$base-dir, :$all) is export {
    my $yaml-file = $base-dir ?? $file.absolute($base-dir).IO !! $file;
    ensure-readable($type, $yaml-file);

    my $yaml = slurp($yaml-file);
    (try $yaml-lock.protect: { $all ?? load-yamls($yaml) !! load-yaml($yaml) })
        or X::MUGS::File::Unparseable.new(:$type, :file($yaml-file)).throw;
}

multi load-yaml-file(Str:D $type, $file, :$base-dir, :$all) is export {
    X::MUGS::File::Unspecified.new(:$type, :$file).throw unless $file;
    load-yaml-file($type, $file.IO, :$base-dir, :$all);
}

#| Write a YAML file, made of one or more YAML documents
multi write-yaml-file(Str:D $type, IO::Path:D $file, **@documents, :$base-dir, Int() :$mode = 0o600) is export {
    my $yaml-file = $base-dir ?? $file.absolute($base-dir).IO !! $file;
    ensure-writable($type, $yaml-file);

    my $yaml = save-yamls(|@documents);
    spurt($yaml-file, $yaml);
    $yaml-file.chmod($mode);
}

multi write-yaml-file(Str:D $type, $file, **@documents, :$base-dir, Int() :$mode = 0o600) is export {
    X::MUGS::File::Unspecified.new(:$type, :$file).throw unless $file;
    write-yaml-file($type, $file.IO, |@documents, :$base-dir, :$mode);
}
