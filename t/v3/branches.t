#!/usr/bin/env perl
use strictures 1;

use Test::More;
use Types::Standard -types;
use List::Util qw( first );

use GitLab::API::v3;

my $url        = $ENV{GITLAB_V3_API_URL};
my $token      = $ENV{GITLAB_TOKEN};
my $project_id = $ENV{GITLAB_PROJECT_ID};

plan skip_all =>
    'Set the GITLAB_V3_API_URL, GITLAB_TOKEN, and GITLAB_PROJECT_ID env vars to run this test.'
    unless $url and $token and $project_id;

my $api = GitLab::API::v3->new(
    url   => $url,
    token => $token,
);

my $ArrayRefOfHashRefs = ArrayRef[ HashRef ];

my $branches = $api->branches( $project_id );
ok(
    $ArrayRefOfHashRefs->check($branches),
    'received an array ref of hash refs via branches()',
);

my $master_branch = $api->branch( $project_id, 'master' );
is(
    ref( $master_branch ), 'HASH',
    'received a hash ref via branch()',
);
is(
    $master_branch->{name}, 'master',
    'branch has name master',
);

my $test_branch = $api->branch( $project_id, 'gitlab-api-test' );
if ($test_branch) {
    $api->unprotect_branch( $project_id, 'gitlab-api-test' );
    $api->delete_branch( $project_id, 'gitlab-api-test' );
}

$test_branch = $api->create_branch(
    $project_id,
    branch_name => 'gitlab-api-test',
    ref         => 'master',
);
is(
    ref( $test_branch ), 'HASH',
    'received a hash ref via create_branch()',
);
is(
    $test_branch->{name}, 'gitlab-api-test',
    'branch has name gitlab-api-test',
);

$test_branch = $api->branch( $project_id, 'gitlab-api-test' );
is(
    ref( $test_branch ), 'HASH',
    'received hash ref via branch',
);
ok( (! $test_branch->{protected}), 'branch is not protected' );

$api->protect_branch( $project_id, 'gitlab-api-test' );
$test_branch = $api->branch( $project_id, 'gitlab-api-test' );
ok( $test_branch->{protected}, 'branch is now protected' );

$api->unprotect_branch( $project_id, 'gitlab-api-test' );
$test_branch = $api->branch( $project_id, 'gitlab-api-test' );
ok( (! $test_branch->{protected}), 'branch is now not protected' );

$api->delete_branch( $project_id, 'gitlab-api-test' );

$test_branch = $api->branch( $project_id, 'gitlab-api-test' );
is(
    $test_branch, undef,
    'received undef via branch (delete_branch worked)',
);

done_testing;
