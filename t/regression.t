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

my $create_user = $api->create_user({'username'=>'maryp','email'=>'maryp@test.example.com','password'=>'d5fzHF7tfgh','name'=>'Mary Poppins'});
ok( 1, 'user created' );
my $found_user = $api->users({'username'=>'maryp'});
ok( $found_user, 'user found' );
my $user_id = $found_user->[0]->{'id'};
my $block_user = $api->block_user($user_id);
ok( $block_user eq 'true', 'user blocked' );
$block_user = $api->unblock_user($user_id);
ok( $block_user eq 'true', 'user unblocked' );
$api->delete_user($user_id);
ok( 1, 'user deleted' );

done_testing;
