#!/usr/bin/env perl
use strictures 2;

use Test2::V0;

BEGIN {
    plan skip_all =>
        'Set the AUTHOR_TESTING env var to run this test.'
        unless $ENV{AUTHOR_TESTING};
}

use Log::Any::Adapter 'TAP';

use GitLab::API::v4;
use GitLab::API::v4::Config;

my $config = GitLab::API::v4::Config->new();
my $api = GitLab::API::v4->new( $config->args() );

my $stamp = time();
my $project_name = "tester-$stamp";

my $created_project = $api->create_project(
    { name=>$project_name },
);
ok( $created_project, 'project created' );

my $project_id = $created_project->{id};
my $found_project = $api->project( $project_id );
ok( $found_project, 'project found' );

$api->delete_project( $project_id );
my $tries = 0;
while ($api->project( $project_id )) {
    $tries ++;
    die 'Timed out waiting for project to delete' if $tries > 10;
    sleep 1;
}
ok( 1, 'project deleted' );

done_testing;
