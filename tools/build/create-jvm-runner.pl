#!/usr/bin/perl
# Copyright (C) 2013, The Perl Foundation.

use strict;
use warnings;
use 5.008;
use File::Spec;
use File::Copy 'cp';
use Cwd 'abs_path';

my $USAGE = "Usage: $0 <type> <destdir> <prefix> <nqp-home> <rakudo-home> <third party jars>\n";

my ($type, $destdir, $prefix, $static_nqp_home, $static_rakudo_home, $thirdpartyjars) = @ARGV
    or die $USAGE;

my $relocatable = $static_nqp_home eq '' && $static_rakudo_home eq '';

my $debugger = 0;
if ($type =~ /^(\w+)\-debug$/) {
    $type = $1;
    $debugger = 1;
}

die "Invalid target type $type" unless $type eq 'dev' || $type eq 'install';

my $cpsep     = $^O eq 'MSWin32' ? ';'    : ':';
my $bat       = $^O eq 'MSWin32' ? '.bat' : '';
my $nqplibdir = $^O eq 'MSWin32' ? File::Spec->catfile($static_nqp_home, 'lib') : File::Spec->catfile('${NQP_HOME}', 'lib');

my $nqpjars;
if ($^O eq 'MSWin32') {
    $nqpjars = $thirdpartyjars;
}
else {
    # The following is a workaround turning the third-party JARS into relative
    # paths. The clean solution would be to pass in relative paths and only
    # prefix those with ${NQP_HOME} here.
    my @thirdpartyjars = map { abs_path($_) } split($cpsep, $thirdpartyjars);
    my $nqp_home       = File::Spec->catdir(abs_path($prefix), 'share', 'nqp');
    @thirdpartyjars    = map { $_ =~ s,$nqp_home,\${NQP_HOME},; $_ } @thirdpartyjars;
    $nqpjars           = join($cpsep, @thirdpartyjars);
}

my $bindir = $type eq 'install' ? File::Spec->catfile($prefix, 'bin') : $prefix;
my $jardir = $type eq 'install' ? File::Spec->catfile($^O eq 'MSWin32' ? $static_rakudo_home : '${RAKUDO_HOME}', 'runtime') : $prefix;
my $libdir = $type eq 'install' ? File::Spec->catfile($^O eq 'MSWin32' ? $static_rakudo_home : '${RAKUDO_HOME}', 'lib') : 'blib';
my $sharedir = File::Spec->catfile(
    ($type eq 'install' && $^O ne 'MSWin32' ? '${RAKUDO_HOME}' : File::Spec->catfile($prefix, 'share', 'perl6') ),
    'site', 'lib');
my $rakudo_jars = join( $cpsep,
    $^O eq 'MSWin32' ? $nqpjars : '${NQP_JARS}',
    File::Spec->catfile($jardir, 'rakudo-runtime.jar'),
    File::Spec->catfile($jardir, $debugger ? 'rakudo-debug.jar' : 'rakudo.jar'));

my $NQP_LIB = $type eq 'install' ? '' : ': ${NQP_LIB:="blib"}';

my $preamble_unix = <<'EOS';
#!/bin/sh

# Sourced from https://stackoverflow.com/a/29835459/1975049
rreadlink() (
  target=$1 fname= targetDir= CDPATH=
  { \unalias command; \unset -f command; } >/dev/null 2>&1
  [ -n "$ZSH_VERSION" ] && options[POSIX_BUILTINS]=on
  while :; do
      [ -L "$target" ] || [ -e "$target" ] || { command printf '%s\n' "ERROR: '$target' does not exist." >&2; return 1; }
      command cd "$(command dirname -- "$target")"
      fname=$(command basename -- "$target")
      [ "$fname" = '/' ] && fname=''
      if [ -L "$fname" ]; then
        target=$(command ls -l "$fname")
        target=${target#* -> }
        continue
      fi
      break
  done
  targetDir=$(command pwd -P)
  if [ "$fname" = '.' ]; then
    command printf '%s\n' "${targetDir%/}"
  elif  [ "$fname" = '..' ]; then
    command printf '%s\n' "$(command dirname -- "${targetDir}")"
  else
    command printf '%s\n' "${targetDir%/}/$fname"
  fi
)

EXEC=$(rreadlink "$0")
DIR=$(dirname -- "$EXEC")

EOS

my $preamble;
if ($^O eq 'MSWin32') {
    $preamble = '@';
}
elsif ($type eq 'install') {
    if ($relocatable) {
        $preamble = join("\n",
            $preamble_unix,
            ": \${NQP_HOME:=\"\$DIR/../share/nqp\"}",
            ": \${NQP_JARS:=\"$nqpjars\"}",
            ": \${RAKUDO_HOME:=\"\$PERL6_HOME\"}",
            ": \${RAKUDO_HOME:=\"\$DIR/../share/perl6\"}",
            ": \${RAKUDO_JARS:=\"$rakudo_jars\"}",
            "exec "
        );
    }
    else {
        $preamble = join("\n",
            $preamble_unix,
            ": \${NQP_HOME:=\"$static_nqp_home\"}",
            ": \${NQP_JARS:=\"$nqpjars\"}",
            ": \${RAKUDO_HOME:=\"\$PERL6_HOME\"}",
            ": \${RAKUDO_HOME:=\"$static_rakudo_home\"}",
            ": \${RAKUDO_JARS:=\"$rakudo_jars\"}",
            "exec "
        );
    }
}
else {
    $preamble = join("\n",
        $preamble_unix,
        "$NQP_LIB",
        ": \${NQP_HOME:=\"$static_nqp_home\"}",
        ": \${NQP_JARS:=\"$nqpjars\"}",
        ": \${RAKUDO_HOME:=\"$prefix\"}",
        ": \${RAKUDO_JARS:=\"$rakudo_jars\"}",
        "exec "
    );
}

my $postamble = $^O eq 'MSWin32' ? ' %*' : ' "$@"';

sub install {
    my ($name, $command) = @_;

    my $install_to = $destdir
        ? File::Spec->catfile($destdir, $bindir, "$name$bat")
        : File::Spec->catfile($bindir, "$name$bat");

    #print "Creating '$install_to'\n";
    open my $fh, ">", $install_to or die "open: $!";
    print $fh $preamble, $command, $postamble, "\n" or die "print: $!";
    close $fh or die "close: $!";

    chmod 0755, $install_to if $^O ne 'MSWin32';
}

my $classpath = join($cpsep, ($rakudo_jars, $jardir, $libdir, $nqplibdir));
my $jopts = '-noverify -Xms100m'
          . ' -cp ' . ($^O eq 'MSWin32' ? '"%CLASSPATH%";' : '$CLASSPATH:') . $classpath
          . ' -Dperl6.prefix=' . ($type eq 'install' && $^O ne 'MSWin32' ? '$DIR/..' : $prefix)
          . ' -Djna.library.path=' . $sharedir
          . ($^O eq 'MSWin32' ? ' -Dperl6.execname="%~dpf0"' : ' -Dperl6.execname="$EXEC"');
my $jdbopts = '-Xdebug -Xrunjdwp:transport=dt_socket,address=' 
            . ($^O eq 'MSWin32' ? '8000' : '${RAKUDO_JDB_PORT:=8000}') 
            . ',server=y,suspend=y';

if ($debugger) {
    install "rakudo-debug-j", "java $jopts rakudo-debug";
    install "perl6-debug-j", "java $jopts rakudo-debug";
}
else {
    install "rakudo-j", "java $jopts perl6";
    install "perl6-j", "java $jopts perl6";
    install "rakudo-jdb-server", "java $jdbopts $jopts perl6";
    install "perl6-jdb-server", "java $jdbopts $jopts perl6";
    install "rakudo-eval-server", "java -Xmx3000m $jopts org.raku.nqp.tools.EvalServer";
    install "perl6-eval-server", "java -Xmx3000m $jopts org.raku.nqp.tools.EvalServer";
}

# vim: expandtab sw=4
