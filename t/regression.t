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

subtest projects => sub{
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
    pass 'project deleted';
};

subtest users => sub{
    my $create_user = $api->create_user({'username'=>'maryp','email'=>'maryp@test.example.com','password'=>'d5fzHF7tfgh','name'=>'Mary Poppins'});
    pass 'user created';
    my $found_user = $api->users({'username'=>'maryp'});
    ok( $found_user, 'user found' );
    my $user_id = $found_user->[0]->{'id'};

    ok( $api->block_user($user_id), 'user blocked' );
    ok( (!$api->block_user($user_id)), 'user cannot be blocked again' );
    ok( $api->unblock_user($user_id), 'user unblocked' );
    ok( (!$api->unblock_user($user_id)), 'user cannot be unblocked again' );
    $api->delete_user($user_id);
    pass 'user deleted';
};

subtest failures => sub{
    is( $api->user( 12345678 ), undef, 'GETing an unknown entity returns undef' );
    my $err_re = qr{^Error PUTing \S+/users/12345678 \(HTTP 404\): Not Found \{"message":"404 User Not Found"\}};
    like( dies{ $api->edit_user( 12345678, {} ) }, $err_re, 'POSTing an unknown entity throws a specific exception' );
};

done_testing;
