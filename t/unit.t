#!/usr/bin/env perl
use strictures 2;

{
    package MockRESTClient;

    use URI;
    use JSON;

    use Moo;
    use strictures 2;
    use namespace::clean;

    extends 'GitLab::API::v4::RESTClient';

    has _mocks => (
        is       => 'ro',
        default  => sub{ [] },
        init_arg => undef,
    );

    sub mock_endpoints {
        my $self = shift;

        while (@_) {
            my $method = shift;
            my $path_re = shift;
            my $sub = shift;

            push @{ $self->_mocks() }, [ $method, $path_re, $sub ];
        }

        return;
    }

    sub _http_tiny_request {
        my ($self, $req_method, $req) = @_;

        die "req_method may only be 'request' at this time"
            if $req_method ne 'request';

        my ($method, $url, $options) = @$req;

        my $path = URI->new( $url )->path();
        $path =~ s{^.*api/v4/}{};

        foreach my $mock (@{ $self->_mocks() }) {
            my ($handler_method, $path_re, $sub) = @$mock;

            next if $method ne $handler_method;

            my @captures = ($path =~ $path_re);
            next if !@captures; # No captures still returns a 1.

            my ($status, $content) = $sub->( [$method,$url,$options], @captures );
            $content = encode_json( $content ) if ref $content;

            return {
                status => $status,
                success => ($status =~ m{^2\d\d$}) ? 1 : 0,
                defined( $content ) ? (content=>$content) : (),
            };
        }

        die "No mock endpoint matched the $method '$path' endpoint";
    }
}

use Test2::V0;
use GitLab::API::v4;
use JSON;

subtest users => sub{
    my @users = ();
    my $next_id = 1;

    my $api = new_client();

    $api->rest_client->mock_endpoints(
        GET => qr{^users$} => sub{ 200, \@users },
        POST => qr{^users$} => sub{
            my ($req) = @_;
            my $user = decode_json( $req->[2]->{content} );
            $user->{id} = $next_id;
            $next_id++;
            push @users, $user;
            return 204;
        },
        GET => qr{^user/(\d+)$} => sub{
            my ($req, $id) = @_;
            foreach my $user (@users) {
                next if $user->{id} != $id;
                return 200, $user;
            }
            return 404;
        },
        PUT => qr{^users/(\d+)$} => sub{
            my ($req, $id) = @_;
            my $data = decode_json( $req->[2]->{content} );
            foreach my $user (@users) {
                next if $user->{id} != $id;
                %$user = (
                    %$user,
                    %$data,
                );
                return 204;
            }
            return 404;
        },
        DELETE => qr{^users/(\d+)$} => sub{
            my ($req, $id) = @_;
            my @new;
            foreach my $user (@users) {
                next if $user->{id} == $id;
                push @new, $user;
            }
            return 404 if @new == @users;
            @users = @new;
            return 204;
        },
    );

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

sub new_client {
    return GitLab::API::v4->new(
        url => 'https://example.com/api/v4',
        rest_client_class => 'MockRESTClient',
    );
}

1;
