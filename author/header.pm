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

=head1 CREDENTIALS

Authentication credentials may be defined by setting either the L</token>,
the L</login> and L</password>, or the L</email> and L</password> arguments.

When the object is constructed the L</login>, L</email>, and L</password>
arguments are used to call L</session> to generate a token.  The token is
saved in the L</token> attribute, and the login/email/password arguments
are discarded.

If no credentials are supplied then the client will be anonymous and greatly
limited in what it can do with the API.

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

around BUILDARGS => sub{
    my $orig = shift;
    my $class = shift;

    my $args = $class->$orig( @_ );

    my $session_args = {};
    foreach my $key (qw( login email password )) {
        next if !exists $args->{$key};
        $session_args->{$key} = delete $args->{$key};
    }

    if (%$session_args) {
        my $api = $class->new( $args );
        my $session = $api->session( $session_args );
        $args->{token} = $session->{private_token};
    }

    return $args;
};

sub BUILD {
    my ($self) = @_;

    $log->debugf( "An instance of %s has been created.", ref($self) );

    $self->rest_client->set_persistent_header(
        'PRIVATE-TOKEN' => $self->token(),
    ) if $self->has_token();

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

A GitLab API token.
If set then neither L</login> or L</email> may be set.
Read more in L</CREDENTIALS>.

=cut

has token => (
    is        => 'ro',
    isa       => NonEmptySimpleStr,
    predicate => 'has_token',
);

=head2 login

A GitLab user login name.
If set then L</password> must be set.
Read more in L</CREDENTIALS>.

=head2 email

A GitLab user email.
If set then L</password> must be set.
Read more in L</CREDENTIALS>.

=head2 password

A GitLab user password.
This must be set if either L</login> or L</email> are set.
Read more in L</CREDENTIALS>.

=cut

# The above three args are virtual and get stripped out in BUILDARGS.

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
        server  => $url,
        type    => 'application/json',
        retries => $self->retries,
    );

    return $rest;
}

=head2 retries

The number of times the request should be retried in case it does not succeed.
Defaults to 0, meaning that a failed request will not be retried.

=cut

has retries => (
    is      => 'ro',
    isa     => Int,
    lazy    => 1,
    default => 0,
);

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

