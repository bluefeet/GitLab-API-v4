package GitLab::API::v4;

=encoding utf8

=head1 NAME

GitLab::API::v4 - A complete GitLab API v4 client.

=head1 SYNOPSIS

    use GitLab::API::v4;
    
    my $api = GitLab::API::v4->new(
        url           => $v4_api_url,
        private_token => $token,
    );
    
    my $branches = $api->branches( $project_id );

=head1 DESCRIPTION

This module provides a one-to-one interface with the GitLab
API v4.  Much is not documented here as it would just be duplicating
GitLab's own L<API Documentation|http://doc.gitlab.com/ce/api/README.html>.

Note that this distribution also includes the L<gitlab-api-v4> command-line
interface (CLI).

=head2 UPGRADING

If you are upgrading from L<GitLab::API::v3> make sure you read:

L<https://docs.gitlab.com/ce/api/v3_to_v4.html>

Also, review the C<Changes> file included in the distribution as it outlines
the changes made to convert the v3 module to v4:

L<https://github.com/bluefeet/GitLab-API-v4/blob/master/Changes>

Finally, be aware that many methods were added, removed, renamed, and/or altered.
If you want to review exactly what was changed you can use GitHub's compare tool:

L<https://github.com/bluefeet/GitLab-API-v4/compare/72e384775c9570f60f8ef68dee3a1eecd347fb69...master>

Or clone the repo and run this command:

C<git diff 72e384775c9570f60f8ef68dee3a1eecd347fb69..HEAD -- author/sections/>

=head2 CREDENTIALS

Authentication credentials may be defined by setting either the L</access_token>
or L</private_token> arguments.

If no credentials are supplied then the client will be anonymous and greatly
limited in what it can do with the API.

=head2 CONSTANTS

The GitLab API, in rare cases, uses a numeric value to represent a state.
To make life easier the L<GitLab::API::v4::Constants> module exposes
these states as named variables.

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

=cut

use GitLab::API::v4::RESTClient;
use GitLab::API::v4::Paginator;

use Types::Standard -types;
use Types::Common::String -types;
use Types::Common::Numeric -types;
use Class::Method::Modifiers qw( fresh );
use URI::Escape;
use Carp qw( croak );
use Log::Any qw( $log );
use Try::Tiny;

use Moo;
use strictures 2;
use namespace::clean;

sub BUILD {
    my ($self) = @_;

    $log->debugf( "An instance of %s has been created.", ref($self) );

    return;
}

sub _clone_args {
    my ($self) = @_;

    return {
        url         => $self->url(),
        retries     => $self->retries(),
        rest_client => $self->rest_client(),
        $self->_has_access_token() ? (access_token=>$self->access_token()) : (),
        $self->_has_private_token() ? (private_token=>$self->private_token()) : (),
    };
}

sub _clone {
    my $self = shift;

    my $class = ref $self;
    my $args = {
        %{ $self->_clone_args() },
        %{ $class->BUILDARGS( @_ ) },
    };

    return $class->new( $args );
}

sub _set_headers {
    my ($self) = @_;

    $self->rest_client->set_header(
        'Authorization' => 'Bearer ' . $self->access_token(),
    ) if $self->_has_access_token();

    $self->rest_client->set_header(
        'Private-Token' => $self->private_token(),
    ) if $self->_has_private_token();

    $self->rest_client->set_header(
        'Sudo' => $self->sudo_user(),
    ) if $self->_has_sudo_user();

    return;
}

sub _call_rest_method {
    my ($self, $method, @args) = @_;

    $self->_set_headers();

    my (@ret, $errored, $error);
    try { @ret = $self->rest_client->$method( @args ) }
    catch { ($errored,$error) = (1,$_) };

    $self->rest_client->clear_headers();
    die $error if $errored;

    return wantarray() ? @ret : $ret[0];
}

=head1 REQUIRED ARGUMENTS

=head2 url

The URL to your v4 API endpoint.  Typically this will be something
like C<http://git.example.com/api/v4>.

=cut

has url => (
    is       => 'ro',
    isa      => NonEmptySimpleStr,
    required => 1,
);

=head1 OPTIONAL ARGUMENTS

=head2 access_token

A GitLab API OAuth2 token.  If set then L</private_token> may not be set.

See L<https://docs.gitlab.com/ce/api/#oauth2-tokens>.

=cut

has access_token => (
    is        => 'ro',
    isa       => NonEmptySimpleStr,
    predicate => '_has_access_token',
);

=head2 private_token

A GitLab API personal token.  If set then L</access_token> may not be set.

See L<https://docs.gitlab.com/ce/api/#personal-access-tokens>.

=cut

has private_token => (
    is        => 'ro',
    isa       => NonEmptySimpleStr,
    predicate => '_has_private_token',
);

=head2 sudo_user

The user to execute API calls as.  You may find it more useful to use the
L</sudo> method instead.

See L<https://docs.gitlab.com/ce/api/#sudo>.

=cut

has sudo_user => (
    is        => 'ro',
    isa       => NonEmptySimpleStr,
    predicate => '_has_sudo_user',
);

=head2 retries

The number of times the request should be retried in case it does not succeed.
Defaults to C<0> (false), meaning that a failed request will not be retried.

=cut

has retries => (
    is      => 'ro',
    isa     => PositiveOrZeroInt,
    default => 0,
);

=head2 rest_client

An instance of L<GitLab::API::v4::RESTClient>.  Typically you will not
be setting this as it defaults to a new instance and customization
should not be necessary.

=cut

has rest_client => (
    is      => 'lazy',
    isa     => InstanceOf[ 'GitLab::API::v4::RESTClient' ],
);
sub _build_rest_client {
    my ($self) = @_;

    my $url = '' . $self->url();
    my $class = 'GitLab::API::v4::RESTClient';

    $log->debugf( 'Creating a %s instance pointed at %s.', $class, $url );

    my $rest = $class->new(
        server  => $url,
        type    => 'application/json',
        retries => $self->retries,
    );

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
and returns an array ref, this will return a L<GitLab::API::v4::Paginator>
object that will allow you to walk the records one page or one record
at a time.

=cut

sub paginator {
    my ($self, $method, @args) = @_;

    my $params = (ref($args[-1]) eq 'HASH') ? pop(@args) : {};

    return GitLab::API::v4::Paginator->new(
        api    => $self,
        method => $method,
        args   => \@args,
        params => $params,
    );
}

=head2 sudo

    $api->sudo('fred')->create_issue(...);

Returns a new instance of L<GitLab::API::v4> with the L</sudo_user> argument
set.

See L<https://docs.gitlab.com/ce/api/#sudo>.

=cut

sub sudo {
    my ($self, $user) = @_;

    return $self->_clone(
        sudo_user => $user,
    );
}

