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

=head2 CONSTANTS

Several values in the GitLab API require looking up the numeric value
for a meaning (such as C<access_level> and C<visibility_level>).
Instead of doing that, you can use L<GitLab::API::v3::Constants>.

=head2 EXCEPTIONS

The API methods will all throw (hopefully) useful exception if
an unsuccesful response is received from the API.  That is except for
C<GET> requests that return a C<404> response - these will return undef
for methods that return a value.

If you'd like to catch and handle these exceptions consider using
L<Try::Tiny>.

=head2 LOGGING

This module uses L<Log::Any> and produces some debug messages here
and there, but the most useful bits are the info messages produced
just before each API call.

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

=head1 USER METHODS

See L<http://doc.gitlab.com/ce/api/users.html>.

=head2 users

    my $users = $api->users(
        \%params,
    );

Sends a C<GET> request to C</users> and returns the decoded/deserialized response body.

=cut

sub users {
    my $self = shift;
    croak 'users must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to users must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/users', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 user

    $api->user(
        $user_id,
    );

Sends a C<GET> request to C</users/:user_id>.

=cut

sub user {
    my $self = shift;
    croak 'user must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($user_id) to user must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/users/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    $self->get( $path );
    return;
}

=head2 create_user

    $api->create_user(
        \%params,
    );

Sends a C<POST> request to C</users>.

=cut

sub create_user {
    my $self = shift;
    croak 'create_user must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_user must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/users', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 edit_user

    $api->edit_user(
        $user_id,
        \%params,
    );

Sends a C<PUT> request to C</users/:user_id>.

=cut

sub edit_user {
    my $self = shift;
    croak 'edit_user must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to edit_user must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to edit_user must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/users/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    $self->put( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 delete_user

    my $user = $api->delete_user(
        $user_id,
    );

Sends a C<DELETE> request to C</users/:user_id> and returns the decoded/deserialized response body.

=cut

sub delete_user {
    my $self = shift;
    croak 'delete_user must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($user_id) to delete_user must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/users/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    return $self->delete( $path );
}

=head2 current_user

    my $user = $api->current_user();

Sends a C<GET> request to C</user> and returns the decoded/deserialized response body.

=cut

sub current_user {
    my $self = shift;
    croak "The current_user method does not take any arguments" if @_;
    my $path = sprintf('/user', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 current_user_ssh_keys

    my $keys = $api->current_user_ssh_keys();

Sends a C<GET> request to C</user/keys> and returns the decoded/deserialized response body.

=cut

sub current_user_ssh_keys {
    my $self = shift;
    croak "The current_user_ssh_keys method does not take any arguments" if @_;
    my $path = sprintf('/user/keys', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 user_ssh_keys

    my $keys = $api->user_ssh_keys(
        $user_id,
    );

Sends a C<GET> request to C</users/:user_id/keys> and returns the decoded/deserialized response body.

=cut

sub user_ssh_keys {
    my $self = shift;
    croak 'user_ssh_keys must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($user_id) to user_ssh_keys must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/users/%s/keys', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 user_ssh_key

    my $key = $api->user_ssh_key(
        $key_id,
    );

Sends a C<GET> request to C</user/keys/:key_id> and returns the decoded/deserialized response body.

=cut

sub user_ssh_key {
    my $self = shift;
    croak 'user_ssh_key must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($key_id) to user_ssh_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/user/keys/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_current_user_ssh_key

    $api->create_current_user_ssh_key(
        \%params,
    );

Sends a C<POST> request to C</user/keys>.

=cut

sub create_current_user_ssh_key {
    my $self = shift;
    croak 'create_current_user_ssh_key must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_current_user_ssh_key must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/user/keys', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 create_user_ssh_key

    $api->create_user_ssh_key(
        $user_id,
        \%params,
    );

Sends a C<POST> request to C</users/:user_id/keys>.

=cut

sub create_user_ssh_key {
    my $self = shift;
    croak 'create_user_ssh_key must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to create_user_ssh_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_user_ssh_key must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/users/%s/keys', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 delete_current_user_ssh_key

    $api->delete_current_user_ssh_key(
        $key_id,
    );

Sends a C<DELETE> request to C</user/keys/:key_id>.

=cut

sub delete_current_user_ssh_key {
    my $self = shift;
    croak 'delete_current_user_ssh_key must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($key_id) to delete_current_user_ssh_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/user/keys/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head2 delete_user_ssh_key

    $api->delete_user_ssh_key(
        $user_id,
        $key_id,
    );

Sends a C<DELETE> request to C</users/:user_id/keys/:key_id>.

=cut

sub delete_user_ssh_key {
    my $self = shift;
    croak 'delete_user_ssh_key must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($user_id) to delete_user_ssh_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($key_id) to delete_user_ssh_key must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/users/%s/keys/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head1 SESSION METHODS

See L<http://doc.gitlab.com/ce/api/session.html>.

=head2 session

    $api->session(
        \%params,
    );

Sends a C<POST> request to C</session>.

=cut

sub session {
    my $self = shift;
    croak 'session must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to session must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/session', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head1 PROJECT METHODS

See L<http://doc.gitlab.com/ce/api/projects.html>.

=head2 projects

    my $projects = $api->projects(
        \%params,
    );

Sends a C<GET> request to C</projects> and returns the decoded/deserialized response body.

=cut

sub projects {
    my $self = shift;
    croak 'projects must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to projects must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 owned_projects

    my $projects = $api->owned_projects();

Sends a C<GET> request to C</projects/owned> and returns the decoded/deserialized response body.

=cut

sub owned_projects {
    my $self = shift;
    croak "The owned_projects method does not take any arguments" if @_;
    my $path = sprintf('/projects/owned', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 all_projects

    my $projects = $api->all_projects();

Sends a C<GET> request to C</projects/all> and returns the decoded/deserialized response body.

=cut

sub all_projects {
    my $self = shift;
    croak "The all_projects method does not take any arguments" if @_;
    my $path = sprintf('/projects/all', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 project

    my $project = $api->project(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id> and returns the decoded/deserialized response body.

=cut

sub project {
    my $self = shift;
    croak 'project must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 project_events

    my $events = $api->project_events(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id/events> and returns the decoded/deserialized response body.

=cut

sub project_events {
    my $self = shift;
    croak 'project_events must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to project_events must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/events', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_project

    $api->create_project(
        \%params,
    );

Sends a C<POST> request to C</projects>.

=cut

sub create_project {
    my $self = shift;
    croak 'create_project must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_project must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 create_project_for_user

    $api->create_project_for_user(
        $user_id,
        \%params,
    );

Sends a C<POST> request to C</projects/user/:user_id>.

=cut

sub create_project_for_user {
    my $self = shift;
    croak 'create_project_for_user must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to create_project_for_user must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_project_for_user must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/user/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 fork_project

    $api->fork_project(
        $project_id,
    );

Sends a C<POST> request to C</pojects/fork/:project_id>.

=cut

sub fork_project {
    my $self = shift;
    croak 'fork_project must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to fork_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/pojects/fork/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, undef );
    $self->post( $path );
    return;
}

=head2 delete_project

    $api->delete_project(
        $project_id,
    );

Sends a C<DELETE> request to C</projects/:project_id>.

=cut

sub delete_project {
    my $self = shift;
    croak 'delete_project must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to delete_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head2 project_members

    my $members = $api->project_members(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C</projects/:project_id/members> and returns the decoded/deserialized response body.

=cut

sub project_members {
    my $self = shift;
    croak 'project_members must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_members must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_members must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/members', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 project_member

    my $member = $api->project_member(
        $project_id,
        $user_id,
    );

Sends a C<GET> request to C</project/:project_id/members/:user_id> and returns the decoded/deserialized response body.

=cut

sub project_member {
    my $self = shift;
    croak 'project_member must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to project_member must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/project/%s/members/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 add_project_member

    $api->add_project_member(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/members>.

=cut

sub add_project_member {
    my $self = shift;
    croak 'add_project_member must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to add_project_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to add_project_member must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/members', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 edit_project_member

    $api->edit_project_member(
        $project_id,
        $user_id,
        \%params,
    );

Sends a C<PUT> request to C</projects/:project_id/members/:user_id>.

=cut

sub edit_project_member {
    my $self = shift;
    croak 'edit_project_member must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_project_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to edit_project_member must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_project_member must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/members/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    $self->put( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 remove_project_member

    $api->remove_project_member(
        $project_id,
        $user_id,
    );

Sends a C<DELETE> request to C</projects/:project_id/members/:user_id>.

=cut

sub remove_project_member {
    my $self = shift;
    croak 'remove_project_member must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to remove_project_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to remove_project_member must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/members/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head2 project_hooks

    my $hooks = $api->project_hooks(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id/hooks> and returns the decoded/deserialized response body.

=cut

sub project_hooks {
    my $self = shift;
    croak 'project_hooks must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to project_hooks must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/hooks', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 project_hook

    my $hook = $api->project_hook(
        $project_id,
        $hook_id,
    );

Sends a C<GET> request to C</project/:project_id/hooks/:hook_id> and returns the decoded/deserialized response body.

=cut

sub project_hook {
    my $self = shift;
    croak 'project_hook must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($hook_id) to project_hook must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/project/%s/hooks/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_project_hook

    $api->create_project_hook(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/hooks>.

=cut

sub create_project_hook {
    my $self = shift;
    croak 'create_project_hook must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_project_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_project_hook must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/hooks', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 edit_project_hook

    $api->edit_project_hook(
        $project_id,
        $hook_id,
        \%params,
    );

Sends a C<PUT> request to C</projects/:project_id/hooks/:hook_id>.

=cut

sub edit_project_hook {
    my $self = shift;
    croak 'edit_project_hook must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_project_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($hook_id) to edit_project_hook must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_project_hook must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/hooks/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    $self->put( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 delete_project_hook

    my $hook = $api->delete_project_hook(
        $project_id,
        $hook_id,
    );

Sends a C<DELETE> request to C</projects/:project_id/hooks/:hook_id> and returns the decoded/deserialized response body.

=cut

sub delete_project_hook {
    my $self = shift;
    croak 'delete_project_hook must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_project_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($hook_id) to delete_project_hook must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/hooks/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    return $self->delete( $path );
}

=head2 set_project_fork

    $api->set_project_fork(
        $project_id,
        $forked_from_id,
    );

Sends a C<POST> request to C</projects/:project_id/fork/:forked_from_id>.

=cut

sub set_project_fork {
    my $self = shift;
    croak 'set_project_fork must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to set_project_fork must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($forked_from_id) to set_project_fork must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/fork/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, undef );
    $self->post( $path );
    return;
}

=head2 clear_project_fork

    $api->clear_project_fork(
        $project_id,
    );

Sends a C<DELETE> request to C</projects/:project_id/fork>.

=cut

sub clear_project_fork {
    my $self = shift;
    croak 'clear_project_fork must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to clear_project_fork must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/fork', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head2 search_projects_by_name

    my $projects = $api->search_projects_by_name(
        $query,
        \%params,
    );

Sends a C<GET> request to C</projects/search/:query> and returns the decoded/deserialized response body.

=cut

sub search_projects_by_name {
    my $self = shift;
    croak 'search_projects_by_name must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($query) to search_projects_by_name must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to search_projects_by_name must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/search/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head1 SNIPPET METHODS

See L<http://doc.gitlab.com/ce/api/project_snippets.html>.

=head2 snippets

    my $snippets = $api->snippets(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id/snippets> and returns the decoded/deserialized response body.

=cut

sub snippets {
    my $self = shift;
    croak 'snippets must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to snippets must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/snippets', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 snippet

    my $snippet = $api->snippet(
        $project_id,
        $snippet_id,
    );

Sends a C<GET> request to C</projects/:project_id/snippets/:snippet_id> and returns the decoded/deserialized response body.

=cut

sub snippet {
    my $self = shift;
    croak 'snippet must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to snippet must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/snippets/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_snippet

    $api->create_snippet(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/snippets>.

=cut

sub create_snippet {
    my $self = shift;
    croak 'create_snippet must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_snippet must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/snippets', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 edit_snippet

    $api->edit_snippet(
        $project_id,
        $snippet_id,
        \%params,
    );

Sends a C<PUT> request to C</projects/:project_id/snippets/:snippet_id>.

=cut

sub edit_snippet {
    my $self = shift;
    croak 'edit_snippet must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to edit_snippet must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_snippet must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/snippets/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    $self->put( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 delete_snippet

    $api->delete_snippet(
        $project_id,
        $snippet_id,
    );

Sends a C<DELETE> request to C</projects/:project_id/snippets/:snippet_id>.

=cut

sub delete_snippet {
    my $self = shift;
    croak 'delete_snippet must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to delete_snippet must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/snippets/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head2 raw_snippet

    my $content = $api->raw_snippet(
        $project_id,
        $snippet_id,
    );

Sends a C<GET> request to C</projects/:project_id/snippets/:snippet_id/raw> and returns the decoded/deserialized response body.

=cut

sub raw_snippet {
    my $self = shift;
    croak 'raw_snippet must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to raw_snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to raw_snippet must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/snippets/%s/raw', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head1 REPOSITORY METHODS

See L<http://doc.gitlab.com/ce/api/repositories.html>.

=head2 tags

    my $tags = $api->tags(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id/repository/tags> and returns the decoded/deserialized response body.

=cut

sub tags {
    my $self = shift;
    croak 'tags must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to tags must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/repository/tags', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_tag

    $api->create_tag(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/repository/tags>.

=cut

sub create_tag {
    my $self = shift;
    croak 'create_tag must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_tag must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_tag must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/tags', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 tree

    my $tree = $api->tree(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C</projects/:project_id/repository/tree> and returns the decoded/deserialized response body.

=cut

sub tree {
    my $self = shift;
    croak 'tree must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to tree must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to tree must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/tree', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 blob

    my $blob = $api->blob(
        $project_id,
        $ref,
        \%params,
    );

Sends a C<GET> request to C</projects/:project_id/repository/blobs/:ref> and returns the decoded/deserialized response body.

=cut

sub blob {
    my $self = shift;
    croak 'blob must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to blob must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($ref) to blob must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to blob must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/blobs/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 raw_blob

    my $raw_blob = $api->raw_blob(
        $project_id,
        $blob_sha,
    );

Sends a C<GET> request to C</projects/:project_id/repository/raw_blobs/:blob_sha> and returns the decoded/deserialized response body.

=cut

sub raw_blob {
    my $self = shift;
    croak 'raw_blob must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to raw_blob must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($blob_sha) to raw_blob must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/repository/raw_blobs/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 archive

    my $archive = $api->archive(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C</projects/:project_id/repository/archive> and returns the decoded/deserialized response body.

=cut

sub archive {
    my $self = shift;
    croak 'archive must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to archive must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to archive must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/archive', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 compare

    my $comparison = $api->compare(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C</projects/:project_id/repository/compare> and returns the decoded/deserialized response body.

=cut

sub compare {
    my $self = shift;
    croak 'compare must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to compare must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to compare must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/compare', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 contributors

    my $contributors = $api->contributors(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id/repository/contributors> and returns the decoded/deserialized response body.

=cut

sub contributors {
    my $self = shift;
    croak 'contributors must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to contributors must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/repository/contributors', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head1 FILE METHODS

See L<http://doc.gitlab.com/ce/api/repository_files.html>.

=head2 file

    my $file = $api->file(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C</projects/:project_id/repository/files> and returns the decoded/deserialized response body.

=cut

sub file {
    my $self = shift;
    croak 'file must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to file must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/files', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 create_file

    $api->create_file(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/repository/files>.

=cut

sub create_file {
    my $self = shift;
    croak 'create_file must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_file must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/files', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 edit_file

    $api->edit_file(
        $project_id,
        \%params,
    );

Sends a C<PUT> request to C</projects/:project_id/repository/files>.

=cut

sub edit_file {
    my $self = shift;
    croak 'edit_file must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to edit_file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to edit_file must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/files', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    $self->put( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 delete_file

    $api->delete_file(
        $project_id,
        \%params,
    );

Sends a C<DELETE> request to C</projects/:project_id/repository/files>.

=cut

sub delete_file {
    my $self = shift;
    croak 'delete_file must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to delete_file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to delete_file must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/files', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, $params );
    $self->delete( $path, ( defined($params) ? $params : () ) );
    return;
}

=head1 COMMIT METHODS

See L<http://doc.gitlab.com/ce/api/commits.html>.

=head2 commits

    my $commits = $api->commits(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C</projects/:project_id/repository/commits> and returns the decoded/deserialized response body.

=cut

sub commits {
    my $self = shift;
    croak 'commits must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to commits must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to commits must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/commits', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 commit

    my $commit = $api->commit(
        $project_id,
        $commit_sha,
    );

Sends a C<GET> request to C</projects/:project_id/repository/commits/:commit_sha> and returns the decoded/deserialized response body.

=cut

sub commit {
    my $self = shift;
    croak 'commit must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to commit must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to commit must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/repository/commits/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 commit_diff

    my $diff = $api->commit_diff(
        $project_id,
        $commit_sha,
    );

Sends a C<GET> request to C</projects/:project_id/repository/commits/:commit_sha/diff> and returns the decoded/deserialized response body.

=cut

sub commit_diff {
    my $self = shift;
    croak 'commit_diff must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to commit_diff must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to commit_diff must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/repository/commits/%s/diff', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 commit_comments

    my $comments = $api->commit_comments(
        $project_id,
        $commit_sha,
    );

Sends a C<GET> request to C</projects/:project_id/repository/commits/:commit_sha/comments> and returns the decoded/deserialized response body.

=cut

sub commit_comments {
    my $self = shift;
    croak 'commit_comments must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to commit_comments must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to commit_comments must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/repository/commits/%s/comments', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 add_commit_comment

    $api->add_commit_comment(
        $project_id,
        $commit_sha,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/repository/commits/:commit_sha/comments>.

=cut

sub add_commit_comment {
    my $self = shift;
    croak 'add_commit_comment must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to add_commit_comment must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to add_commit_comment must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to add_commit_comment must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/commits/%s/comments', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head1 BRANCH METHODS

See L<http://doc.gitlab.com/ce/api/branches.html>.

=head2 branches

    my $branches = $api->branches(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id/repository/branches> and returns the decoded/deserialized response body.

=cut

sub branches {
    my $self = shift;
    croak 'branches must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to branches must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/repository/branches', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 branch

    my $branch = $api->branch(
        $project_id,
        $branch_name,
    );

Sends a C<GET> request to C</projects/:project_id/repository/branches/:branch_name> and returns the decoded/deserialized response body.

=cut

sub branch {
    my $self = shift;
    croak 'branch must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($branch_name) to branch must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/repository/branches/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 protect_branch

    $api->protect_branch(
        $project_id,
        $branch_name,
    );

Sends a C<PUT> request to C</projects/:project_id/repository/branches/:branch_name/protect>.

=cut

sub protect_branch {
    my $self = shift;
    croak 'protect_branch must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to protect_branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($branch_name) to protect_branch must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/repository/branches/%s/protect', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, undef );
    $self->put( $path );
    return;
}

=head2 unprotect_branch

    $api->unprotect_branch(
        $project_id,
        $branch_name,
    );

Sends a C<PUT> request to C</projects/:project_id/repository/branches/:branch_name/unprotect>.

=cut

sub unprotect_branch {
    my $self = shift;
    croak 'unprotect_branch must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to unprotect_branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($branch_name) to unprotect_branch must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/repository/branches/%s/unprotect', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, undef );
    $self->put( $path );
    return;
}

=head2 create_branch

    my $branch = $api->create_branch(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/repository/branches> and returns the decoded/deserialized response body.

=cut

sub create_branch {
    my $self = shift;
    croak 'create_branch must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_branch must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/repository/branches', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    return $self->post( $path, ( defined($params) ? $params : () ) );
}

=head2 delete_branch

    $api->delete_branch(
        $project_id,
        $branch_name,
    );

Sends a C<DELETE> request to C</projects/:project_id/repository/branches/:branch_name>.

=cut

sub delete_branch {
    my $self = shift;
    croak 'delete_branch must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($branch_name) to delete_branch must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/repository/branches/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head1 MERGE REQUEST METHODS

See L<http://doc.gitlab.com/ce/api/merge_requests.html>.

=head2 merge_requests

    my $merge_requests = $api->merge_requests(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id/merge_requests> and returns the decoded/deserialized response body.

=cut

sub merge_requests {
    my $self = shift;
    croak 'merge_requests must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to merge_requests must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/merge_requests', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 merge_request

    my $merge_request = $api->merge_request(
        $project_id,
        $merge_request_id,
    );

Sends a C<GET> request to C</projects/:project_id/merge_request/:merge_request_id> and returns the decoded/deserialized response body.

=cut

sub merge_request {
    my $self = shift;
    croak 'merge_request must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_id) to merge_request must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/merge_request/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_merge_request

    my $merge_request = $api->create_merge_request(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/merge_requests> and returns the decoded/deserialized response body.

=cut

sub create_merge_request {
    my $self = shift;
    croak 'create_merge_request must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_merge_request must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/merge_requests', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    return $self->post( $path, ( defined($params) ? $params : () ) );
}

=head2 edit_merge_request

    my $merge_request = $api->edit_merge_request(
        $project_id,
        $merge_request_id,
        \%params,
    );

Sends a C<PUT> request to C</projects/:project_id/merge_requests/:merge_request_id> and returns the decoded/deserialized response body.

=cut

sub edit_merge_request {
    my $self = shift;
    croak 'edit_merge_request must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_id) to edit_merge_request must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_merge_request must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/merge_requests/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    return $self->put( $path, ( defined($params) ? $params : () ) );
}

=head2 accept_merge_request

    $api->accept_merge_request(
        $project_id,
        $merge_request_id,
        \%params,
    );

Sends a C<PUT> request to C</projects/:project_id/merge_requests/:merge_request_id/merge>.

=cut

sub accept_merge_request {
    my $self = shift;
    croak 'accept_merge_request must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to accept_merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_id) to accept_merge_request must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to accept_merge_request must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/merge_requests/%s/merge', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    $self->put( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 add_merge_request_comment

    $api->add_merge_request_comment(
        $project_id,
        $merge_request_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/merge_requests/:merge_request_id/comments>.

=cut

sub add_merge_request_comment {
    my $self = shift;
    croak 'add_merge_request_comment must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to add_merge_request_comment must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_id) to add_merge_request_comment must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to add_merge_request_comment must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/merge_requests/%s/comments', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 merge_request_comments

    my $comments = $api->merge_request_comments(
        $project_id,
        $merge_request_id,
    );

Sends a C<GET> request to C</projects/:project_id/merge_requests/:merge_request_id/comments> and returns the decoded/deserialized response body.

=cut

sub merge_request_comments {
    my $self = shift;
    croak 'merge_request_comments must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to merge_request_comments must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_id) to merge_request_comments must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/merge_requests/%s/comments', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head1 ISSUE METHODS

See L<http://doc.gitlab.com/ce/api/issues.html>.

=head2 all_issues

    my $issues = $api->all_issues(
        \%params,
    );

Sends a C<GET> request to C</issues> and returns the decoded/deserialized response body.

=cut

sub all_issues {
    my $self = shift;
    croak 'all_issues must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to all_issues must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/issues', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 issues

    my $issues = $api->issues(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C</projects/:project_id/issues> and returns the decoded/deserialized response body.

=cut

sub issues {
    my $self = shift;
    croak 'issues must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to issues must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to issues must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/issues', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, $params );
    return $self->get( $path, ( defined($params) ? $params : () ) );
}

=head2 issue

    my $issue = $api->issue(
        $project_id,
        $issue_id,
    );

Sends a C<GET> request to C</projects/:project_id/issues/:issue_id> and returns the decoded/deserialized response body.

=cut

sub issue {
    my $self = shift;
    croak 'issue must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to issue must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_id) to issue must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/issues/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_issue

    my $issue = $api->create_issue(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/issues> and returns the decoded/deserialized response body.

=cut

sub create_issue {
    my $self = shift;
    croak 'create_issue must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_issue must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_issue must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/issues', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    return $self->post( $path, ( defined($params) ? $params : () ) );
}

=head2 edit_issue

    my $issue = $api->edit_issue(
        $project_id,
        $issue_id,
        \%params,
    );

Sends a C<PUT> request to C</projects/:project_id/issues/:issue_id> and returns the decoded/deserialized response body.

=cut

sub edit_issue {
    my $self = shift;
    croak 'edit_issue must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_issue must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_id) to edit_issue must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_issue must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/issues/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    return $self->put( $path, ( defined($params) ? $params : () ) );
}

=head1 LABEL METHODS

See L<http://doc.gitlab.com/ce/api/labels.html>.

=head2 labels

    my $labels = $api->labels(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id/labels> and returns the decoded/deserialized response body.

=cut

sub labels {
    my $self = shift;
    croak 'labels must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to labels must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/labels', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_label

    my $label = $api->create_label(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/labels> and returns the decoded/deserialized response body.

=cut

sub create_label {
    my $self = shift;
    croak 'create_label must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_label must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_label must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/labels', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    return $self->post( $path, ( defined($params) ? $params : () ) );
}

=head2 delete_label

    $api->delete_label(
        $project_id,
        \%params,
    );

Sends a C<DELETE> request to C</projects/:project_id/labels>.

=cut

sub delete_label {
    my $self = shift;
    croak 'delete_label must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to delete_label must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to delete_label must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/labels', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, $params );
    $self->delete( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 edit_label

    my $label = $api->edit_label(
        $project_id,
        \%params,
    );

Sends a C<PUT> request to C</projects/:project_id/labels> and returns the decoded/deserialized response body.

=cut

sub edit_label {
    my $self = shift;
    croak 'edit_label must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to edit_label must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to edit_label must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/labels', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    return $self->put( $path, ( defined($params) ? $params : () ) );
}

=head1 MILESTONE METHODS

See L<http://doc.gitlab.com/ce/api/milestones.html>.

=head2 milestones

    my $milestones = $api->milestones(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id/milestones> and returns the decoded/deserialized response body.

=cut

sub milestones {
    my $self = shift;
    croak 'milestones must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to milestones must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/milestones', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 milestone

    my $milestone = $api->milestone(
        $project_id,
        $milestone_id,
    );

Sends a C<GET> request to C</projects/:project_id/milestones/:milestone_id> and returns the decoded/deserialized response body.

=cut

sub milestone {
    my $self = shift;
    croak 'milestone must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to milestone must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($milestone_id) to milestone must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/milestones/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_milestone

    $api->create_milestone(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/milestones>.

=cut

sub create_milestone {
    my $self = shift;
    croak 'create_milestone must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_milestone must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_milestone must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/milestones', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 edit_milestone

    $api->edit_milestone(
        $project_id,
        $milestone_id,
        \%params,
    );

Sends a C<PUT> request to C</projects/:project_id/milestones/:milestone_id>.

=cut

sub edit_milestone {
    my $self = shift;
    croak 'edit_milestone must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_milestone must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($milestone_id) to edit_milestone must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_milestone must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/milestones/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    $self->put( $path, ( defined($params) ? $params : () ) );
    return;
}

=head1 NOTE METHODS

See L<http://doc.gitlab.com/ce/api/notes.html>.

=head2 notes

    my $notes = $api->notes(
        $project_id,
        $note_type,
        $merge_request_id,
    );

Sends a C<GET> request to C</projects/:project_id/:note_type/:merge_request_id/notes> and returns the decoded/deserialized response body.

=cut

sub notes {
    my $self = shift;
    croak 'notes must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to notes must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($note_type) to notes must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($merge_request_id) to notes must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $path = sprintf('/projects/%s/%s/%s/notes', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 note

    my $note = $api->note(
        $project_id,
        $note_type,
        $merge_request_id,
        $note_id,
    );

Sends a C<GET> request to C</projects/:project_id/:note_type/:merge_request_id/notes/:note_id> and returns the decoded/deserialized response body.

=cut

sub note {
    my $self = shift;
    croak 'note must be called with 4 arguments' if @_ != 4;
    croak 'The #1 argument ($project_id) to note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($note_type) to note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($merge_request_id) to note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($note_id) to note must be a scalar' if ref($_[3]) or (!defined $_[3]);
    my $path = sprintf('/projects/%s/%s/%s/notes/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_note

    $api->create_note(
        $project_id,
        $note_type,
        $merge_request_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/:note_type/:merge_request_id/notes>.

=cut

sub create_note {
    my $self = shift;
    croak 'create_note must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to create_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($note_type) to create_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($merge_request_id) to create_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to create_note must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/%s/%s/notes', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head1 DEPLOY KEY METHODS

See L<http://doc.gitlab.com/ce/api/deploy_keys.html>.

=head2 deploy_keys

    my $keys = $api->deploy_keys(
        $project_id,
    );

Sends a C<GET> request to C</projects/:project_id/keys> and returns the decoded/deserialized response body.

=cut

sub deploy_keys {
    my $self = shift;
    croak 'deploy_keys must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to deploy_keys must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/projects/%s/keys', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 deploy_key

    my $key = $api->deploy_key(
        $project_id,
        $key_id,
    );

Sends a C<GET> request to C</projects/:project_id/keys/:key_id> and returns the decoded/deserialized response body.

=cut

sub deploy_key {
    my $self = shift;
    croak 'deploy_key must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to deploy_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($key_id) to deploy_key must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/keys/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_deploy_key

    $api->create_deploy_key(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C</projects/:project_id/keys>.

=cut

sub create_deploy_key {
    my $self = shift;
    croak 'create_deploy_key must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_deploy_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_deploy_key must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/keys', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 delete_deploy_key

    $api->delete_deploy_key(
        $project_id,
        $key_id,
    );

Sends a C<DELETE> request to C</projects/:project_id/keys/:key_id>.

=cut

sub delete_deploy_key {
    my $self = shift;
    croak 'delete_deploy_key must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_deploy_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($key_id) to delete_deploy_key must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/keys/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head1 SYSTEM HOOK METHODS

See L<http://doc.gitlab.com/ce/api/system_hooks.html>.

=head2 hooks

    my $hooks = $api->hooks();

Sends a C<GET> request to C</hooks> and returns the decoded/deserialized response body.

=cut

sub hooks {
    my $self = shift;
    croak "The hooks method does not take any arguments" if @_;
    my $path = sprintf('/hooks', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_hook

    $api->create_hook(
        \%params,
    );

Sends a C<POST> request to C</hooks>.

=cut

sub create_hook {
    my $self = shift;
    croak 'create_hook must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_hook must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/hooks', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 test_hook

    my $hook = $api->test_hook(
        $hook_id,
    );

Sends a C<GET> request to C</hooks/:hook_id> and returns the decoded/deserialized response body.

=cut

sub test_hook {
    my $self = shift;
    croak 'test_hook must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($hook_id) to test_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/hooks/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 delete_hook

    $api->delete_hook(
        $hook_id,
    );

Sends a C<DELETE> request to C</hooks/:hook_id>.

=cut

sub delete_hook {
    my $self = shift;
    croak 'delete_hook must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($hook_id) to delete_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/hooks/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head1 GROUP METHODS

See L<http://doc.gitlab.com/ce/api/groups.html>.

=head2 groups

    my $groups = $api->groups();

Sends a C<GET> request to C</groups> and returns the decoded/deserialized response body.

=cut

sub groups {
    my $self = shift;
    croak "The groups method does not take any arguments" if @_;
    my $path = sprintf('/groups', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 group

    my $group = $api->group(
        $group_id,
    );

Sends a C<GET> request to C</groups/:group_id> and returns the decoded/deserialized response body.

=cut

sub group {
    my $self = shift;
    croak 'group must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($group_id) to group must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/groups/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 create_group

    $api->create_group(
        \%params,
    );

Sends a C<POST> request to C</groups>.

=cut

sub create_group {
    my $self = shift;
    croak 'create_group must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_group must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/groups', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 transfer_project

    $api->transfer_project(
        $group_id,
        $project_id,
    );

Sends a C<POST> request to C</groups/:group_id/projects/:project_id>.

=cut

sub transfer_project {
    my $self = shift;
    croak 'transfer_project must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to transfer_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($project_id) to transfer_project must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/groups/%s/projects/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, undef );
    $self->post( $path );
    return;
}

=head2 delete_group

    $api->delete_group(
        $group_id,
    );

Sends a C<DELETE> request to C</groups/:group_id>.

=cut

sub delete_group {
    my $self = shift;
    croak 'delete_group must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($group_id) to delete_group must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/groups/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head2 group_members

    my $members = $api->group_members(
        $group_id,
    );

Sends a C<GET> request to C</groups/:group_id/members> and returns the decoded/deserialized response body.

=cut

sub group_members {
    my $self = shift;
    croak 'group_members must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($group_id) to group_members must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $path = sprintf('/groups/%s/members', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'GET', $path, undef );
    return $self->get( $path );
}

=head2 add_group_member

    $api->add_group_member(
        $group_id,
        \%params,
    );

Sends a C<POST> request to C</groups/:group_id/members>.

=cut

sub add_group_member {
    my $self = shift;
    croak 'add_group_member must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to add_group_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to add_group_member must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/groups/%s/members', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'POST', $path, $params );
    $self->post( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 remove_group_member

    $api->remove_group_member(
        $group_id,
        $user_id,
    );

Sends a C<DELETE> request to C</groups/:group_id/members/:user_id>.

=cut

sub remove_group_member {
    my $self = shift;
    croak 'remove_group_member must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to remove_group_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to remove_group_member must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/groups/%s/members/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

=head1 SERVICE METHODS

See L<http://doc.gitlab.com/ce/api/services.html>.

=head2 edit_project_service

    $api->edit_project_service(
        $project_id,
        $service_name,
        \%params,
    );

Sends a C<PUT> request to C</projects/:project_id/services/:service_name>.

=cut

sub edit_project_service {
    my $self = shift;
    croak 'edit_project_service must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_project_service must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($service_name) to edit_project_service must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_project_service must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = pop;
    my $path = sprintf('/projects/%s/services/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'PUT', $path, $params );
    $self->put( $path, ( defined($params) ? $params : () ) );
    return;
}

=head2 delete_project_service

    $api->delete_project_service(
        $project_id,
        $service_name,
    );

Sends a C<DELETE> request to C</projects/:project_id/services/:service_name>.

=cut

sub delete_project_service {
    my $self = shift;
    croak 'delete_project_service must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_project_service must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($service_name) to delete_project_service must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $path = sprintf('/projects/%s/services/%s', (map { uri_escape($_) } @_));
    $log->infof( 'Making %s request against %s with params %s.', 'DELETE', $path, undef );
    $self->delete( $path );
    return;
}

1;
__END__

=head2 SEE ALSO

L<Net::GitLab> reports to provide an interface to the GitLab API, but
it is hard to tell due to a complete lack of documentation.

=head2 CONTRIBUTING

This module is auto-generated from a set of YAML files defining the
interface of GitLab's API.  If you'd like to contribute to this module
then please feel free to make a
L<fork on GitHub|https://github.com/bluefeet/GitLab-API-v3>
and submit a pull request, just make sure you edit the files in the
C<authors/> directory instead of C<lib/GitLab/API/v3.pm> directly.

Please see
L<https://github.com/bluefeet/GitLab-API-v3/blob/master/author/README.pod>
for more information.

=head1 AUTHOR

Aran Clary Deltac <bluefeet@gmail.com>

=head1 ACKNOWLEDGEMENTS

Thanks to L<ZipRecruiter|https://www.ziprecruiter.com/>
for encouraging their employees to contribute back to the open
source ecosystem.  Without their dedication to quality software
development this distribution would not exist.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

