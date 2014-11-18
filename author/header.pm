package GitLab::API::v3;

=head1 NAME

GitLab::API::v3 - GitLab API v3 client.

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

=cut

use GitLab::API::v3::RESTClient;

use Types::Standard -types;
use Types::Common::String -types;
use URI::Escape;
use Carp qw( croak );

use Moo;
use strictures 1;
use namespace::clean;

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

    my $rest = GitLab::API::v3::RESTClient->new(
        server => '' . $self->url(),
        type   => 'application/json',
    );

    $rest->set_persistent_header(
        'PRIVATE-TOKEN' => $self->token(),
    );

    return $rest;
}

