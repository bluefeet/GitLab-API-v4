#!/usr/bin/env perl
use strictures 2;

use Test2::V0;
use Log::Any::Adapter 'TAP';

use GitLab::API::v4;

my $url   = $ENV{GITLAB_API_V4_URL};
my $token = $ENV{GITLAB_API_V4_PRIVATE_TOKEN};

plan skip_all =>
    'Set the GITLAB_API_V4_URL and GITLAB_API_V4_PRIVATE_TOKEN env vars to run this test.'
    unless $url and $token;

my $api = GitLab::API::v4->new(
    url           => $url,
    private_token => $token,
);

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
