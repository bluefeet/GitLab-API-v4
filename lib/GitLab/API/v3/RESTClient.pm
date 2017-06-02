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
use Role::REST::Client::Response;

use Moo;
use Try::Tiny;
use strictures 1;
use namespace::clean;
use Log::Any qw( $log );
use Types::Standard qw( Int );

has retries => (
  is => 'ro',
  isa => Int,
  default => 0,
);

with 'Role::REST::Client';

foreach my $method (qw( post get head put delete options )) {
    around $method => sub{
        my $orig = shift;
        my $self = shift;
        my $path = shift;

        my $res;
        my $retry = $self->retries;
        do {
          $log->infof( 'Making %s request against %s', uc($method), $path );
          $res = $self->$orig( "/$path", @_ );

          if ($res->code =~ /^5/) {
            $log->warn('Request failed. Retrying...') if $retry;
          }
          else {
            $retry = 0;
          }
        } while --$retry >= 0;

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

1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeetE<64>gmail.com>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

