#!/usr/bin/env perl
use strictures 1;

use Test::More;
use Types::Standard -types;
use List::Util qw( first );
use Log::Any::Adapter 'TAP';

use GitLab::API::v3;
use GitLab::API::v3::Constants qw( :all );

my $url   = $ENV{GITLAB_API_V3_URL};
my $token = $ENV{GITLAB_API_V3_TOKEN};

plan skip_all =>
    'Set the GITLAB_API_V3_URL and GITLAB_API_V3_TOKEN env vars to run this test.'
    unless $url and $token;

my $api = GitLab::API::v3->new(
    url   => $url,
    token => $token,
);

my $ArrayRefOfHashRefs = ArrayRef[ HashRef ];

my ($project) = (
    first { $_->{namespace}->{owner_id} }
    sort { $a->{name} cmp $b->{name} }
    grep { $_->{visibility_level} == $GITLAB_VISIBILITY_LEVEL_PRIVATE }
    @{ $api->owned_projects() }
);

plan skip_all =>
    'Could not find a private project owned by the tokened user.'
    if !$project;

my $project_id = $project->{id};
my $branch_name = 'gitlab-api-test';

my $branches = $api->branches( $project_id );
ok(
    $ArrayRefOfHashRefs->check($branches),
    'received an array ref of hash refs from branches()',
);

my $default_branch = $api->branch( $project_id, $project->{default_branch} );
is(
    ref( $default_branch ), 'HASH',
    'received a hash ref from branch()',
);

is(
    $default_branch->{name}, $project->{default_branch},
    'branch has correct name',
);

my $test_branch = $api->branch( $project_id, $branch_name );
if ($test_branch) {
    $api->unprotect_branch( $project_id, $branch_name );
    $api->delete_branch( $project_id, $branch_name );
}

$test_branch = $api->create_branch(
    $project_id,
    {
        branch_name => $branch_name,
        ref         => $project->{default_branch},
    },
);
is(
    ref( $test_branch ), 'HASH',
    'received a hash ref from create_branch()',
);
is(
    $test_branch->{name}, $branch_name,
    'branch has name gitlab-api-test',
);

$test_branch = $api->branch( $project_id, $branch_name );
is(
    ref( $test_branch ), 'HASH',
    'received hash ref from branch()',
);
ok( (! $test_branch->{protected}), 'branch is not protected' );

$api->protect_branch( $project_id, $branch_name );
$test_branch = $api->branch( $project_id, $branch_name );
ok( $test_branch->{protected}, 'branch is now protected' );

$api->unprotect_branch( $project_id, $branch_name );
$test_branch = $api->branch( $project_id, $branch_name );
ok( (! $test_branch->{protected}), 'branch is now not protected' );

$api->delete_branch( $project_id, $branch_name );

$test_branch = $api->branch( $project_id, $branch_name );
is(
    $test_branch, undef,
    'received undef from branch() (delete_branch worked)',
);

done_testing;
