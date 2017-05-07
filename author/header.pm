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

Note that this distribution also includes the L<gitlab-api-v3> command-line
interface (CLI).

=head2 AUTHENTICATION

There are two ways to authenticate with GitLab - the first is via the
L</token> argument as seen in the L</SYNOPSIS>, and the second is by
first creating an anonymous object and calling L</login> on it.

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
use GitLab::API::v3::Paginator;

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

=head1 OPTIONAL ARGUMENTS

=head2 token

A GitLab API token.  If this is not set then API access will be severely limited.

=cut

has token => (
    is        => 'ro',
    isa       => NonEmptySimpleStr,
    predicate => 'has_token',
);

=head2 rest_client_class

The class to use when constructing the L</rest_client>.

Defaults to C<GitLab::API::v3::RESTClient>.

=cut

has rest_client_class => (
    is      => 'ro',
    isa     => NonEmptySimpleStr,
    default => 'GitLab::API::v3::RESTClient',
);

=head1 ATTRIBUTES

=head2 rest_client

An instance of L</rest_client_class>.

=cut

has rest_client => (
    is       => 'lazy',
    isa      => InstanceOf[ 'GitLab::API::v3::RESTClient' ],
    init_arg => undef,
    handles  => [qw( post get head put delete options )],
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

    $rest->set_persistent_header(
        'PRIVATE-TOKEN' => $self->token(),
    ) if $self->has_token();

    return $rest;
}

=head1 UTILITY METHODS

=head2 paginator

    my $paginator = $api->paginator( $method, @method_args );
    
    my $members = $api->paginator('group_members', $group_id);
    while (my $member = $members->next()) {
        ...
    }
    
    my $users_pager = $api->paginator('users');
    while (my $users = $users_pager->next_page()) {
        ...
    }
    
    my $all_open_issues = $api->paginator(
        'issues',
        $project_id,
        { state=>'opened' },
    )->all();

Given a method who supports the C<page> and C<per_page> parameters,
and returns an array ref, this will return a L<GitLab::API::v3::Paginator>
object that will allow you to walk the records one page or one record
at a time.

=cut

sub paginator {
    my ($self, $method, @args) = @_;

    my $params = (ref($args[-1]) eq 'HASH') ? pop(@args) : {};

    return GitLab::API::v3::Paginator->new(
        api    => $self,
        method => $method,
        args   => \@args,
        params => $params,
    );
}

=head2 login

This is a thin wrapper around L</session> which allows for normal GitLab
authentication to be used to generate an API token.  This method returns
a new, authenticated, L<GitLab::API::v3> object and does not modify the
original.

    my $api = GitLab::API::v3->new( url=>... )->login(
        login    => $username,
        password => $pass,
    );

This method accepts whatever parameters L</session> supports which means you
can specify C<login> or C<email>, along with C<password>.

=cut

sub login {
    my $self = shift;

    my $session = $self->session({ @_ });

    return ref($self)->new(
        url               => $self->url(),
        rest_client_class => $self->rest_client_class(),
        token             => $session->{private_token},
    );
}

