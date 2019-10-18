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

subtest reqres => sub{
    my $api = GitLab::API::v4::Mock->new();

    is( $api->rest_client->http_tiny_request(), undef, 'no request' );
    is( $api->rest_client->http_tiny_response(), undef, 'no response' );

    $api->users();

    is(
        $api->rest_client->http_tiny_request(),
        [ 'GET', 'https://example.com/api/v4/users', {headers=>{}} ],
        'recorded request arrayref looks great',
    );
    is(
        $api->rest_client->http_tiny_response(),
        { success=>1, status=>200, content=>'[]' },
        'recorded response hashref looks great',
    );
};

done_testing;
