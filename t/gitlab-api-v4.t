#!/usr/bin/env perl
use strictures 2;

use Test2::Require::AuthorTesting;
use Test2::V0;

use IPC::Cmd qw();
use JSON qw();

my $json = JSON->new->allow_nonref();

my $project = run('create-project', 'name:test-gitlab-api-v4');
run('delete-project', $project->{id});

ok( 1, 'made it to the end' );

done_testing;

sub run {
    my($ok, $error, $full, $stdout, $stderr) =
        IPC::Cmd::run( command => [$^X, '-I', 'lib', 'script/gitlab-api-v4', @_] );

    if ($ok) {
        $stdout = join('',@$stdout);
        return $json->decode( $stdout );
    }

    die join('', @$stderr) . $error;
}

1;
