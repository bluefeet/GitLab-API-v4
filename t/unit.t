#!/usr/bin/env perl
use strictures 2;

use Test2::V0;

use GitLab::API::v4::Mock;

subtest users => sub{
    my @users = ();
    my $next_id = 1;

    my $api = GitLab::API::v4::Mock->new();

    my @expected;
    is( $api->users(), \@expected, 'users is empty' );

    $api->create_user({});
    push @expected, {id=>1};
    is( $api->users(), \@expected, 'one user created' );

    $api->create_user({});
    push @expected, {id=>2};
    $api->create_user({});
    push @expected, {id=>3};
    is( $api->users(), \@expected, 'two more users created' );

    $api->edit_user( 3, {name=>'foo'});
    $expected[2]->{name} = 'foo';
    is( $api->users(), \@expected, 'user was updated' );

    $api->delete_user( 2 );
    splice @expected, 1, 1;
    is( $api->users(), \@expected, 'user was deleted' );
};

done_testing;

1;
