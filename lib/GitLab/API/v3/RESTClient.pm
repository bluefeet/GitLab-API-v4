package # Hide from the CPAN indexer.
    GitLab::API::v3::RESTClient;

use Carp qw( confess );

use Moo;
use strictures 1;
use namespace::clean;

with 'Role::REST::Client';

foreach my $method (qw( post get head put delete options )) {
    around $method => sub{
        my $orig = shift;
        my $self = shift;
        my $path = shift;

        my $res = $self->$orig( "/$path", @_ );

        return undef if $res->code() eq '404' and $method eq 'get';

        if ($res->failed()) {
            local $Carp::Internal{ 'GitLab::API::v3::RESTClient' } = 1;

            confess sprintf(
                'Error %sing %s from %s (HTTP %s): %s',
                uc($method), $path, $self->server(), $res->code(), $res->error() // 'undef',
            );
        }

        return $res->data();
    };
}

1;
