package GitLab::API::v3::RESTClient;

=head1 NAME

GitLab::API::v3::RESTClient - GitLab API v3 REST client.

=head2 DESCRIPTION

This module provides the actual REST communication with the GitLab
server and is powered by L<Role::REST::Client>.

The various HTTP verb methods are wrapped so that they throw an
exception if an unexpected response is received, except for GET
requests that respond with a 404 code; these return C<undef>
instead.

If the request was successful then the response data is returned
rather than the response object itself.

=cut

use Carp qw( confess );
use Data::Dumper qw();

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
                'Error %sing %s from %s (HTTP %s): %s %s',
                uc($method), $path, $self->server(), $res->code(), $res->error(),
                _dump_one_line( $res->data() ),
            );
        }

        return $res->data();
    };
}

# Stolen and modified from Log::Any::Adapter::Core.
sub _dump_one_line {
    my ($value) = @_;

    return '<undef>' if !defined $value;

    return Data::Dumper->new( [$value] )->Indent(0)->Sortkeys(1)->Quotekeys(0)
        ->Terse(1)->Dump() if ref($value);

    $value =~ s{\s+}{ }g;
    return $value;
}

around _call => sub {
    my $orig = shift;
    my $self = shift;

    my $res = $self->$orig(@_);

    # Disable serialization when response is an octest stream
    # Annoyingly, this cannot be done using the Role::REST::Client API
    my $type = $res->response->headers->{'content-type'};
    if ($type =~ qr{\b(?:json|xml|yaml|x-www-form-urlencoded)\b}) {
        return $res;
    }
    else {
      use Role::REST::Client::Response;
      return Role::REST::Client::Response->new(
          code     => $res->code,
          response => $res->response,
          data     => sub { $res->response->content },
          (defined $res->error) ? ( error => $res->error ) : (),
      );
    }
};

1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeetE<64>gmail.com>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

