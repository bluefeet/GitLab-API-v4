package GitLab::API::v3;

=head1 NAME

GitLab::API::v3 - A complete GitLab API v3 client.

=head1 SYNOPSIS

    use GitLab::API::v3;
    
    my $api = GitLab::API::v3->new(
        url   => $v3_api_url,
        token => $token,
    );
    
    my $branches = $api->branches( $project_id );

=head1 DESCRIPTION

This module provides a one-to-one interface with the GitLab
API v3.  Much is not documented here as it would just be duplicating
GitLab's own L<API Documentation|http://doc.gitlab.com/ce/api/README.html>.

=head2 CONSTANTS

Several values in the GitLab API require looking up the numeric value
for a meaning (such as C<access_level> and C<visibility_level>).
Instead of doing that, you can use L<GitLab::API::v3::Constants>.

=head2 EXCEPTIONS

The API methods will all throw (hopefully) a useful exception if
an unsuccessful response is received from the API.  That is except for
C<GET> requests that return a C<404> response - these will return C<undef>
for methods that return a value.

If you'd like to catch and handle these exceptions consider using
L<Try::Tiny>.

=head2 LOGGING

This module uses L<Log::Any> and produces some debug messages here
and there, but the most useful bits are the info messages produced
just before each API call.

=head2 PROJECT ID

Note that many API calls require a C<$project_id>.  This can be
specified as either a numeric project C<ID>, or as a
C<NAMESPACE_PATH/PROJECT_PATH> in many cases.  Perhaps even
all cases, but the GitLab documentation on this point is vague.

=head2 RETURN VALUES

Many of this module's methods should return a value but do not
currently.  This is due to the fact that this module was built
as a strict representation of GitLab's own documentation which
is often inconsistent.

If you find a method that should provide a return value, but
doesn't currently, please verify that GitLab actually does
return a value and then submit a pull request or open an issue.
See L</CONTRIBUTING> for more info.

=cut

use GitLab::API::v3::RESTClient;

use Types::Standard -types;
use Types::Common::String -types;
use URI::Escape;
use Carp qw( croak );
use Log::Any qw( $log );

use Moo;
use strictures 1;
use namespace::clean;

sub BUILD {
    my ($self) = @_;

    $log->debugf( "An instance of %s has been created.", ref($self) );

    $self->rest_client->set_persistent_header(
        'PRIVATE-TOKEN' => $self->token(),
    );

    return;
}

=head1 REQUIRED ARGUMENTS

=head2 url

The URL to your v3 API endpoint.  Typically this will be something
like C<http://git.example.com/api/v3>.

=cut

has url => (
    is       => 'ro',
    isa      => NonEmptySimpleStr,
    required => 1,
);

=head2 token

A GitLab API token.

=cut

has token => (
    is       => 'ro',
    isa      => NonEmptySimpleStr,
    required => 1,
);

=head1 OPTIONAL ARGUMENTS

=head2 rest_client

An instance of L<GitLab::API::v3::RESTClient>.  Typically you will not
be setting this as it defaults to a new instance and customization
should not be necessary.

=cut

has rest_client => (
    is      => 'lazy',
    isa     => InstanceOf[ 'GitLab::API::v3::RESTClient' ],
    handles => [qw( post get head put delete options )],
);
sub _build_rest_client {
    my ($self) = @_;

    my $url = '' . $self->url();
    my $class = 'GitLab::API::v3::RESTClient';

    $log->debugf( 'Creating a %s instance pointed at %s.', $class, $url );

    my $rest = $class->new(
        server => $url,
        type   => 'application/json',
    );

    return $rest;
}

