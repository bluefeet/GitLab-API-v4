package GitLab::API::v4;
our $VERSION = '0.26';

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

=head2 Upgrading

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

=head2 Credentials

Authentication credentials may be defined by setting either the L</access_token>
or L</private_token> arguments.

If no credentials are supplied then the client will be anonymous and greatly
limited in what it can do with the API.

Extra care has been taken to hide the token arguments behind closures.  This way,
if you dump your api object, your tokens won't accidentally leak into places you
don't want them to.

=head2 Constants

The GitLab API, in rare cases, uses a hard-coded value to represent a state.
To make life easier the L<GitLab::API::v4::Constants> module exposes
these states as named variables.

=head2 Exceptions

The API methods will all throw a useful exception if
an unsuccessful response is received from the API.  That is except for
C<GET> requests that return a C<404> response - these will return C<undef>
for methods that return a value.

If you'd like to catch and handle these exceptions consider using
L<Try::Tiny>.

=head2 Logging

This module uses L<Log::Any> and produces some debug messages here
and there, but the most useful bits are the info messages produced
just before each API call.

=head2 Project ID

Note that many API calls require a C<$project_id>.  This can be
specified as a numeric project C<ID> or, in many cases, maybe all cases,
as a C<NAMESPACE_PATH/PROJECT_PATH> string.  The GitLab documentation on
this point is vague.

=cut

use Carp qw( croak );
use GitLab::API::v4::Paginator;
use GitLab::API::v4::RESTClient;
use Log::Any qw( $log );
use Types::Common::Numeric -types;
use Types::Common::String -types;
use Types::Standard -types;

use Moo;
use strictures 2;
use namespace::clean;

sub BUILD {
    my ($self) = @_;

    # Ensure any token arguments get moved into their closure before we return
    # the built object.
    $self->access_token();
    $self->private_token();

    $log->debugf( "An instance of %s has been created.", ref($self) );

    return;
}

sub _call_rest_client {
    my ($self, $verb, $path, $path_vars, $options) = @_;

    $options->{headers} = $self->_auth_headers();

    return $self->rest_client->request(
        $verb, $path, $path_vars, $options,
    );
}

sub _auth_headers {
    my ($self) = @_;
    my $headers = {};

    $headers->{'authorization'} = 'Bearer ' . $self->access_token()
        if defined $self->access_token();
    $headers->{'private-token'} = $self->private_token()
        if defined $self->private_token();
    $headers->{'sudo'} = $self->sudo_user()
        if defined $self->sudo_user();

    return $headers;
}

sub _clone_args {
    my ($self) = @_;

    return {
        url         => $self->url(),
        retries     => $self->retries(),
        rest_client => $self->rest_client(),
        (defined $self->access_token()) ? (access_token=>$self->access_token()) : (),
        (defined $self->private_token()) ? (private_token=>$self->private_token()) : (),
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

# Little utility method that avoids any ambiguity in whether a closer is
# causing circular references.  Don't ever pass it a ref.
sub _make_safe_closure {
    my ($ret) = @_;
    return sub{ $ret };
}

=head1 REQUIRED ARGUMENTS

=head2 url

The URL to your v4 API endpoint.  Typically this will be something
like C<https://git.example.com/api/v4>.

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

has _access_token_arg => (
    is        => 'ro',
    isa       => NonEmptySimpleStr,
    init_arg  => 'access_token',
    clearer   => '_clear_access_token_arg',
);

has _access_token_closure => (
    is       => 'lazy',
    isa      => CodeRef,
    init_arg => undef,
    builder  => '_build_access_token_closure',
);
sub _build_access_token_closure {
    my ($self) = @_;
    my $token = $self->_access_token_arg();
    $self->_clear_access_token_arg();
    return _make_safe_closure( $token );
}

sub access_token {
    my ($self) = @_;
    return $self->_access_token_closure->();
}

=head2 private_token

A GitLab API personal token.  If set then L</access_token> may not be set.

See L<https://docs.gitlab.com/ce/api/#personal-access-tokens>.

=cut

has _private_token_arg => (
    is        => 'ro',
    isa       => NonEmptySimpleStr,
    init_arg  => 'private_token',
    clearer   => '_clear_private_token_arg',
);

has _private_token_closure => (
    is       => 'lazy',
    isa      => CodeRef,
    init_arg => undef,
    builder  => '_build_private_token_closure',
);
sub _build_private_token_closure {
    my ($self) = @_;
    my $token = $self->_private_token_arg();
    $self->_clear_private_token_arg();
    return _make_safe_closure( $token );
}

sub private_token {
    my ($self) = @_;
    return $self->_private_token_closure->();
}

=head2 retries

The number of times the request should be retried in case it fails (5XX HTTP
response code).  Defaults to C<0> (false), meaning that a failed request will
not be retried.

=cut

has retries => (
    is      => 'ro',
    isa     => PositiveOrZeroInt,
    default => 0,
);

=head2 sudo_user

The user to execute API calls as.  You may find it more useful to use the
L</sudo> method instead.

See L<https://docs.gitlab.com/ce/api/#sudo>.

=cut

has sudo_user => (
    is  => 'ro',
    isa => NonEmptySimpleStr,
);

=head2 rest_client

An instance of L<GitLab::API::v4::RESTClient> (or whatever L</rest_client_class>
is set to).  Typically you will not be setting this as it defaults to a new
instance and customization should not be necessary.

=cut

has rest_client => (
    is  => 'lazy',
    isa => InstanceOf[ 'GitLab::API::v4::RESTClient' ],
);
sub _build_rest_client {
    my ($self) = @_;

    return $self->rest_client_class->new(
        base_url => $self->url(),
        retries  => $self->retries(),
    );
}

=head2 rest_client_class

The class to use when constructing the L</rest_client>.
Defaults to L<GitLab::API::v4::RESTClient>.

=cut

has rest_client_class => (
    is  => 'lazy',
    isa => NonEmptySimpleStr,
);
sub _build_rest_client_class {
    return 'GitLab::API::v4::RESTClient';
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

=head1 API METHODS

=head2 Award Emoji

See L<https://docs.gitlab.com/ce/api/award_emoji.html>.

=over

=item issue_award_emojis

    my $award_emojis = $api->issue_award_emojis(
        $project_id,
        $issue_iid,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/award_emoji> and returns the decoded response content.

=cut

sub issue_award_emojis {
    my $self = shift;
    croak 'issue_award_emojis must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to issue_award_emojis must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_award_emojis must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to issue_award_emojis must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/award_emoji', [@_], $options );
}

=item merge_request_award_emojis

    my $award_emojis = $api->merge_request_award_emojis(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/award_emoji> and returns the decoded response content.

=cut

sub merge_request_award_emojis {
    my $self = shift;
    croak 'merge_request_award_emojis must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to merge_request_award_emojis must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_award_emojis must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to merge_request_award_emojis must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/award_emoji', [@_], $options );
}

=item snippet_award_emojis

    my $award_emojis = $api->snippet_award_emojis(
        $project_id,
        $merge_request_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_id/award_emoji> and returns the decoded response content.

=cut

sub snippet_award_emojis {
    my $self = shift;
    croak 'snippet_award_emojis must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to snippet_award_emojis must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_id) to snippet_award_emojis must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to snippet_award_emojis must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_id/award_emoji', [@_], $options );
}

=item issue_award_emoji

    my $award_emoji = $api->issue_award_emoji(
        $project_id,
        $issue_iid,
        $award_id,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/award_emoji/:award_id> and returns the decoded response content.

=cut

sub issue_award_emoji {
    my $self = shift;
    croak 'issue_award_emoji must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to issue_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($award_id) to issue_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/award_emoji/:award_id', [@_], $options );
}

=item merge_request_award_emoji

    my $award_emoji = $api->merge_request_award_emoji(
        $project_id,
        $merge_request_iid,
        $award_id,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/award_emoji/:award_id> and returns the decoded response content.

=cut

sub merge_request_award_emoji {
    my $self = shift;
    croak 'merge_request_award_emoji must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to merge_request_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($award_id) to merge_request_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/award_emoji/:award_id', [@_], $options );
}

=item snippet_award_emoji

    my $award_emoji = $api->snippet_award_emoji(
        $project_id,
        $snippet_id,
        $award_id,
    );

Sends a C<GET> request to C<projects/:project_id/snippets/:snippet_id/award_emoji/:award_id> and returns the decoded response content.

=cut

sub snippet_award_emoji {
    my $self = shift;
    croak 'snippet_award_emoji must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to snippet_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to snippet_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($award_id) to snippet_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/snippets/:snippet_id/award_emoji/:award_id', [@_], $options );
}

=item create_issue_award_emoji

    my $award_emoji = $api->create_issue_award_emoji(
        $project_id,
        $issue_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/award_emoji> and returns the decoded response content.

=cut

sub create_issue_award_emoji {
    my $self = shift;
    croak 'create_issue_award_emoji must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_issue_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to create_issue_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_issue_award_emoji must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/award_emoji', [@_], $options );
}

=item create_merge_request_award_emoji

    my $award_emoji = $api->create_merge_request_award_emoji(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/award_emoji> and returns the decoded response content.

=cut

sub create_merge_request_award_emoji {
    my $self = shift;
    croak 'create_merge_request_award_emoji must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_merge_request_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to create_merge_request_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_merge_request_award_emoji must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/award_emoji', [@_], $options );
}

=item create_snippet_award_emoji

    my $award_emoji = $api->create_snippet_award_emoji(
        $project_id,
        $snippet_id,
    );

Sends a C<POST> request to C<projects/:project_id/snippets/:snippet_id/award_emoji> and returns the decoded response content.

=cut

sub create_snippet_award_emoji {
    my $self = shift;
    croak 'create_snippet_award_emoji must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to create_snippet_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to create_snippet_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/snippets/:snippet_id/award_emoji', [@_], $options );
}

=item delete_issue_award_emoji

    my $award_emoji = $api->delete_issue_award_emoji(
        $project_id,
        $issue_id,
        $award_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/issues/:issue_id/award_emoji/:award_id> and returns the decoded response content.

=cut

sub delete_issue_award_emoji {
    my $self = shift;
    croak 'delete_issue_award_emoji must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to delete_issue_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_id) to delete_issue_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($award_id) to delete_issue_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'DELETE', 'projects/:project_id/issues/:issue_id/award_emoji/:award_id', [@_], $options );
}

=item delete_merge_request_award_emoji

    my $award_emoji = $api->delete_merge_request_award_emoji(
        $project_id,
        $merge_request_id,
        $award_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/merge_requests/:merge_request_id/award_emoji/:award_id> and returns the decoded response content.

=cut

sub delete_merge_request_award_emoji {
    my $self = shift;
    croak 'delete_merge_request_award_emoji must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to delete_merge_request_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_id) to delete_merge_request_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($award_id) to delete_merge_request_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'DELETE', 'projects/:project_id/merge_requests/:merge_request_id/award_emoji/:award_id', [@_], $options );
}

=item delete_snippet_award_emoji

    my $award_emoji = $api->delete_snippet_award_emoji(
        $project_id,
        $snippet_id,
        $award_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/snippets/:snippet_id/award_emoji/:award_id> and returns the decoded response content.

=cut

sub delete_snippet_award_emoji {
    my $self = shift;
    croak 'delete_snippet_award_emoji must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to delete_snippet_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to delete_snippet_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($award_id) to delete_snippet_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'DELETE', 'projects/:project_id/snippets/:snippet_id/award_emoji/:award_id', [@_], $options );
}

=item issue_note_award_emojis

    my $award_emojis = $api->issue_note_award_emojis(
        $project_id,
        $issue_iid,
        $note_id,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/notes/:note_id/award_emoji> and returns the decoded response content.

=cut

sub issue_note_award_emojis {
    my $self = shift;
    croak 'issue_note_award_emojis must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to issue_note_award_emojis must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_note_award_emojis must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to issue_note_award_emojis must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/notes/:note_id/award_emoji', [@_], $options );
}

=item issue_note_award_emoji

    my $award_emoji = $api->issue_note_award_emoji(
        $project_id,
        $issue_iid,
        $note_id,
        $award_id,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/notes/:note_id/award_emoji/:award_id> and returns the decoded response content.

=cut

sub issue_note_award_emoji {
    my $self = shift;
    croak 'issue_note_award_emoji must be called with 4 arguments' if @_ != 4;
    croak 'The #1 argument ($project_id) to issue_note_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_note_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to issue_note_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($award_id) to issue_note_award_emoji must be a scalar' if ref($_[3]) or (!defined $_[3]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/notes/:note_id/award_emoji/:award_id', [@_], $options );
}

=item create_issue_note_award_emoji

    my $award_emoji = $api->create_issue_note_award_emoji(
        $project_id,
        $issue_iid,
        $note_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/notes/:note_id/award_emoji> and returns the decoded response content.

=cut

sub create_issue_note_award_emoji {
    my $self = shift;
    croak 'create_issue_note_award_emoji must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to create_issue_note_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to create_issue_note_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to create_issue_note_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to create_issue_note_award_emoji must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/notes/:note_id/award_emoji', [@_], $options );
}

=item delete_issue_note_award_emoji

    my $award_emoji = $api->delete_issue_note_award_emoji(
        $project_id,
        $issue_iid,
        $note_id,
        $award_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/issues/:issue_iid/notes/:note_id/award_emoji/:award_id> and returns the decoded response content.

=cut

sub delete_issue_note_award_emoji {
    my $self = shift;
    croak 'delete_issue_note_award_emoji must be called with 4 arguments' if @_ != 4;
    croak 'The #1 argument ($project_id) to delete_issue_note_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to delete_issue_note_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to delete_issue_note_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($award_id) to delete_issue_note_award_emoji must be a scalar' if ref($_[3]) or (!defined $_[3]);
    my $options = {};
    return $self->_call_rest_client( 'DELETE', 'projects/:project_id/issues/:issue_iid/notes/:note_id/award_emoji/:award_id', [@_], $options );
}

=item merge_request_note_award_emojis

    my $award_emojis = $api->merge_request_note_award_emojis(
        $project_id,
        $merge_request_iid,
        $note_id,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id/award_emoji> and returns the decoded response content.

=cut

sub merge_request_note_award_emojis {
    my $self = shift;
    croak 'merge_request_note_award_emojis must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to merge_request_note_award_emojis must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_note_award_emojis must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to merge_request_note_award_emojis must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id/award_emoji', [@_], $options );
}

=item merge_request_note_award_emoji

    my $award_emoji = $api->merge_request_note_award_emoji(
        $project_id,
        $merge_request_iid,
        $note_id,
        $award_id,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id/award_emoji/:award_id> and returns the decoded response content.

=cut

sub merge_request_note_award_emoji {
    my $self = shift;
    croak 'merge_request_note_award_emoji must be called with 4 arguments' if @_ != 4;
    croak 'The #1 argument ($project_id) to merge_request_note_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_note_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to merge_request_note_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($award_id) to merge_request_note_award_emoji must be a scalar' if ref($_[3]) or (!defined $_[3]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id/award_emoji/:award_id', [@_], $options );
}

=item create_merge_request_note_award_emoji

    my $award_emoji = $api->create_merge_request_note_award_emoji(
        $project_id,
        $merge_request_iid,
        $note_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id/award_emoji> and returns the decoded response content.

=cut

sub create_merge_request_note_award_emoji {
    my $self = shift;
    croak 'create_merge_request_note_award_emoji must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to create_merge_request_note_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to create_merge_request_note_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to create_merge_request_note_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to create_merge_request_note_award_emoji must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id/award_emoji', [@_], $options );
}

=item delete_merge_request_note_award_emoji

    my $award_emoji = $api->delete_merge_request_note_award_emoji(
        $project_id,
        $merge_request_iid,
        $note_id,
        $award_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id/award_emoji/:award_id> and returns the decoded response content.

=cut

sub delete_merge_request_note_award_emoji {
    my $self = shift;
    croak 'delete_merge_request_note_award_emoji must be called with 4 arguments' if @_ != 4;
    croak 'The #1 argument ($project_id) to delete_merge_request_note_award_emoji must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to delete_merge_request_note_award_emoji must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to delete_merge_request_note_award_emoji must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($award_id) to delete_merge_request_note_award_emoji must be a scalar' if ref($_[3]) or (!defined $_[3]);
    my $options = {};
    return $self->_call_rest_client( 'DELETE', 'projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id/award_emoji/:award_id', [@_], $options );
}

=back

=head2 Branches

See L<https://docs.gitlab.com/ce/api/branches.html>.

=over

=item branches

    my $branches = $api->branches(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/branches> and returns the decoded response content.

=cut

sub branches {
    my $self = shift;
    croak 'branches must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to branches must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to branches must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/branches', [@_], $options );
}

=item branch

    my $branch = $api->branch(
        $project_id,
        $branch_name,
    );

Sends a C<GET> request to C<projects/:project_id/repository/branches/:branch_name> and returns the decoded response content.

=cut

sub branch {
    my $self = shift;
    croak 'branch must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($branch_name) to branch must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/branches/:branch_name', [@_], $options );
}

=item create_branch

    my $branch = $api->create_branch(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/repository/branches> and returns the decoded response content.

=cut

sub create_branch {
    my $self = shift;
    croak 'create_branch must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_branch must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/repository/branches', [@_], $options );
}

=item delete_branch

    $api->delete_branch(
        $project_id,
        $branch_name,
    );

Sends a C<DELETE> request to C<projects/:project_id/repository/branches/:branch_name>.

=cut

sub delete_branch {
    my $self = shift;
    croak 'delete_branch must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($branch_name) to delete_branch must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/repository/branches/:branch_name', [@_], $options );
    return;
}

=item delete_merged_branches

    $api->delete_merged_branches(
        $project_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/repository/merged_branches>.

=cut

sub delete_merged_branches {
    my $self = shift;
    croak 'delete_merged_branches must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to delete_merged_branches must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/repository/merged_branches', [@_], $options );
    return;
}

=back

=head2 Broadcast Messages

See L<https://docs.gitlab.com/ce/api/broadcast_messages.html>.

=over

=item broadcast_messages

    my $messages = $api->broadcast_messages(
        \%params,
    );

Sends a C<GET> request to C<broadcast_messages> and returns the decoded response content.

=cut

sub broadcast_messages {
    my $self = shift;
    croak 'broadcast_messages must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to broadcast_messages must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'broadcast_messages', [@_], $options );
}

=item broadcast_message

    my $message = $api->broadcast_message(
        $message_id,
    );

Sends a C<GET> request to C<broadcast_messages/:message_id> and returns the decoded response content.

=cut

sub broadcast_message {
    my $self = shift;
    croak 'broadcast_message must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($message_id) to broadcast_message must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'broadcast_messages/:message_id', [@_], $options );
}

=item create_broadcast_message

    my $message = $api->create_broadcast_message(
        \%params,
    );

Sends a C<POST> request to C<broadcast_messages> and returns the decoded response content.

=cut

sub create_broadcast_message {
    my $self = shift;
    croak 'create_broadcast_message must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_broadcast_message must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'broadcast_messages', [@_], $options );
}

=item edit_broadcast_message

    my $message = $api->edit_broadcast_message(
        $message_id,
        \%params,
    );

Sends a C<PUT> request to C<broadcast_messages/:message_id> and returns the decoded response content.

=cut

sub edit_broadcast_message {
    my $self = shift;
    croak 'edit_broadcast_message must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($message_id) to edit_broadcast_message must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to edit_broadcast_message must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'broadcast_messages/:message_id', [@_], $options );
}

=item delete_broadcast_message

    $api->delete_broadcast_message(
        $message_id,
    );

Sends a C<DELETE> request to C<broadcast_messages/:message_id>.

=cut

sub delete_broadcast_message {
    my $self = shift;
    croak 'delete_broadcast_message must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($message_id) to delete_broadcast_message must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'broadcast_messages/:message_id', [@_], $options );
    return;
}

=back

=head2 Project-level Variables

See L<https://docs.gitlab.com/ce/api/project_level_variables.html>.

=over

=item project_variables

    my $variables = $api->project_variables(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/variables> and returns the decoded response content.

=cut

sub project_variables {
    my $self = shift;
    croak 'project_variables must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_variables must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_variables must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/variables', [@_], $options );
}

=item project_variable

    my $variable = $api->project_variable(
        $project_id,
        $variable_key,
    );

Sends a C<GET> request to C<projects/:project_id/variables/:variable_key> and returns the decoded response content.

=cut

sub project_variable {
    my $self = shift;
    croak 'project_variable must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($variable_key) to project_variable must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/variables/:variable_key', [@_], $options );
}

=item create_project_variable

    my $variable = $api->create_project_variable(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/variables> and returns the decoded response content.

=cut

sub create_project_variable {
    my $self = shift;
    croak 'create_project_variable must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_project_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_project_variable must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/variables', [@_], $options );
}

=item edit_project_variable

    my $variable = $api->edit_project_variable(
        $project_id,
        $variable_key,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/variables/:variable_key> and returns the decoded response content.

=cut

sub edit_project_variable {
    my $self = shift;
    croak 'edit_project_variable must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_project_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($variable_key) to edit_project_variable must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_project_variable must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/variables/:variable_key', [@_], $options );
}

=item delete_project_variable

    $api->delete_project_variable(
        $project_id,
        $variable_key,
    );

Sends a C<DELETE> request to C<projects/:project_id/variables/:variable_key>.

=cut

sub delete_project_variable {
    my $self = shift;
    croak 'delete_project_variable must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_project_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($variable_key) to delete_project_variable must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/variables/:variable_key', [@_], $options );
    return;
}

=back

=head2 Group-level Variables

See L<https://docs.gitlab.com/ce/api/group_level_variables.html>.

=over

=item group_variables

    my $variables = $api->group_variables(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/variables> and returns the decoded response content.

=cut

sub group_variables {
    my $self = shift;
    croak 'group_variables must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to group_variables must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to group_variables must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/variables', [@_], $options );
}

=item group_variable

    my $variable = $api->group_variable(
        $group_id,
        $variable_key,
    );

Sends a C<GET> request to C<groups/:group_id/variables/:variable_key> and returns the decoded response content.

=cut

sub group_variable {
    my $self = shift;
    croak 'group_variable must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to group_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($variable_key) to group_variable must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/variables/:variable_key', [@_], $options );
}

=item create_group_variable

    my $variable = $api->create_group_variable(
        $group_id,
        \%params,
    );

Sends a C<POST> request to C<groups/:group_id/variables> and returns the decoded response content.

=cut

sub create_group_variable {
    my $self = shift;
    croak 'create_group_variable must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to create_group_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_group_variable must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'groups/:group_id/variables', [@_], $options );
}

=item edit_group_variable

    my $variable = $api->edit_group_variable(
        $group_id,
        $variable_key,
        \%params,
    );

Sends a C<PUT> request to C<groups/:group_id/variables/:variable_key> and returns the decoded response content.

=cut

sub edit_group_variable {
    my $self = shift;
    croak 'edit_group_variable must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($group_id) to edit_group_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($variable_key) to edit_group_variable must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_group_variable must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'groups/:group_id/variables/:variable_key', [@_], $options );
}

=item delete_group_variable

    $api->delete_group_variable(
        $group_id,
        $variable_key,
    );

Sends a C<DELETE> request to C<groups/:group_id/variables/:variable_key>.

=cut

sub delete_group_variable {
    my $self = shift;
    croak 'delete_group_variable must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to delete_group_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($variable_key) to delete_group_variable must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'groups/:group_id/variables/:variable_key', [@_], $options );
    return;
}

=back

=head2 Snippets

See L<https://docs.gitlab.com/ce/api/snippets.html>.

=over

=item snippets

    my $snippets = $api->snippets();

Sends a C<GET> request to C<snippets> and returns the decoded response content.

=cut

sub snippets {
    my $self = shift;
    croak "The snippets method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'snippets', [@_], $options );
}

=item snippet

    my $snippet = $api->snippet(
        $snippet_id,
    );

Sends a C<GET> request to C<snippets/:snippet_id> and returns the decoded response content.

=cut

sub snippet {
    my $self = shift;
    croak 'snippet must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($snippet_id) to snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'snippets/:snippet_id', [@_], $options );
}

=item create_snippet

    my $snippet = $api->create_snippet(
        \%params,
    );

Sends a C<POST> request to C<snippets> and returns the decoded response content.

=cut

sub create_snippet {
    my $self = shift;
    croak 'create_snippet must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_snippet must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'snippets', [@_], $options );
}

=item edit_snippet

    my $snippet = $api->edit_snippet(
        $snippet_id,
        \%params,
    );

Sends a C<PUT> request to C<snippets/:snippet_id> and returns the decoded response content.

=cut

sub edit_snippet {
    my $self = shift;
    croak 'edit_snippet must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($snippet_id) to edit_snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to edit_snippet must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'snippets/:snippet_id', [@_], $options );
}

=item delete_snippet

    $api->delete_snippet(
        $snippet_id,
    );

Sends a C<DELETE> request to C<snippets/:snippet_id>.

=cut

sub delete_snippet {
    my $self = shift;
    croak 'delete_snippet must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($snippet_id) to delete_snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'snippets/:snippet_id', [@_], $options );
    return;
}

=item public_snippets

    my $snippets = $api->public_snippets(
        \%params,
    );

Sends a C<GET> request to C<snippets/public> and returns the decoded response content.

=cut

sub public_snippets {
    my $self = shift;
    croak 'public_snippets must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to public_snippets must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'snippets/public', [@_], $options );
}

=item snippet_user_agent_detail

    my $user_agent = $api->snippet_user_agent_detail(
        $snippet_id,
    );

Sends a C<GET> request to C<snippets/:snippet_id/user_agent_detail> and returns the decoded response content.

=cut

sub snippet_user_agent_detail {
    my $self = shift;
    croak 'snippet_user_agent_detail must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($snippet_id) to snippet_user_agent_detail must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'snippets/:snippet_id/user_agent_detail', [@_], $options );
}

=back

=head2 Commits

See L<https://docs.gitlab.com/ce/api/commits.html>.

=over

=item commits

    my $commits = $api->commits(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/commits> and returns the decoded response content.

=cut

sub commits {
    my $self = shift;
    croak 'commits must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to commits must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to commits must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/commits', [@_], $options );
}

=item create_commit

    my $commit = $api->create_commit(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/repository/commits> and returns the decoded response content.

=cut

sub create_commit {
    my $self = shift;
    croak 'create_commit must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_commit must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_commit must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/repository/commits', [@_], $options );
}

=item commit

    my $commit = $api->commit(
        $project_id,
        $commit_sha,
    );

Sends a C<GET> request to C<projects/:project_id/repository/commits/:commit_sha> and returns the decoded response content.

=cut

sub commit {
    my $self = shift;
    croak 'commit must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to commit must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to commit must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/commits/:commit_sha', [@_], $options );
}

=item commit_refs

    my $refs = $api->commit_refs(
        $project_id,
        $commit_sha,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/commits/:commit_sha/refs> and returns the decoded response content.

=cut

sub commit_refs {
    my $self = shift;
    croak 'commit_refs must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to commit_refs must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to commit_refs must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to commit_refs must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/commits/:commit_sha/refs', [@_], $options );
}

=item cherry_pick_commit

    my $commit = $api->cherry_pick_commit(
        $project_id,
        $commit_sha,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/repository/commits/:commit_sha/cherry_pick> and returns the decoded response content.

=cut

sub cherry_pick_commit {
    my $self = shift;
    croak 'cherry_pick_commit must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to cherry_pick_commit must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to cherry_pick_commit must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to cherry_pick_commit must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/repository/commits/:commit_sha/cherry_pick', [@_], $options );
}

=item commit_diff

    my $diff = $api->commit_diff(
        $project_id,
        $commit_sha,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/commits/:commit_sha/diff> and returns the decoded response content.

=cut

sub commit_diff {
    my $self = shift;
    croak 'commit_diff must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to commit_diff must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to commit_diff must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to commit_diff must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/commits/:commit_sha/diff', [@_], $options );
}

=item commit_comments

    my $comments = $api->commit_comments(
        $project_id,
        $commit_sha,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/commits/:commit_sha/comments> and returns the decoded response content.

=cut

sub commit_comments {
    my $self = shift;
    croak 'commit_comments must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to commit_comments must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to commit_comments must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to commit_comments must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/commits/:commit_sha/comments', [@_], $options );
}

=item create_commit_comment

    $api->create_commit_comment(
        $project_id,
        $commit_sha,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/repository/commits/:commit_sha/comments>.

=cut

sub create_commit_comment {
    my $self = shift;
    croak 'create_commit_comment must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_commit_comment must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to create_commit_comment must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_commit_comment must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/:project_id/repository/commits/:commit_sha/comments', [@_], $options );
    return;
}

=item commit_statuses

    my $build_statuses = $api->commit_statuses(
        $project_id,
        $commit_sha,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/commits/:commit_sha/statuses> and returns the decoded response content.

=cut

sub commit_statuses {
    my $self = shift;
    croak 'commit_statuses must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to commit_statuses must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to commit_statuses must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to commit_statuses must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/commits/:commit_sha/statuses', [@_], $options );
}

=item create_commit_status

    my $build_status = $api->create_commit_status(
        $project_id,
        $commit_sha,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/statuses/:commit_sha> and returns the decoded response content.

=cut

sub create_commit_status {
    my $self = shift;
    croak 'create_commit_status must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_commit_status must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_sha) to create_commit_status must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_commit_status must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/statuses/:commit_sha', [@_], $options );
}

=back

=head2 Container Registry

See L<https://docs.gitlab.com/ce/api/container_registry.html>.

=over

=item registry_repositories_in_project

    my $registry_repositories = $api->registry_repositories_in_project(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/registry/repositories> and returns the decoded response content.

=cut

sub registry_repositories_in_project {
    my $self = shift;
    croak 'registry_repositories_in_project must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to registry_repositories_in_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to registry_repositories_in_project must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/registry/repositories', [@_], $options );
}

=item registry_repositories_in_group

    my $registry_repositories = $api->registry_repositories_in_group(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/registry/repositories> and returns the decoded response content.

=cut

sub registry_repositories_in_group {
    my $self = shift;
    croak 'registry_repositories_in_group must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to registry_repositories_in_group must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to registry_repositories_in_group must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/registry/repositories', [@_], $options );
}

=item delete_registry_repository

    $api->delete_registry_repository(
        $project_id,
        $repository_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/registry/repositories/:repository_id>.

=cut

sub delete_registry_repository {
    my $self = shift;
    croak 'delete_registry_repository must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_registry_repository must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($repository_id) to delete_registry_repository must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/registry/repositories/:repository_id', [@_], $options );
    return;
}

=item registry_repository_tags

    my $tags = $api->registry_repository_tags(
        $project_id,
        $repository_id,
    );

Sends a C<GET> request to C<projects/:project_id/registry/repositories/:repository_id/tags> and returns the decoded response content.

=cut

sub registry_repository_tags {
    my $self = shift;
    croak 'registry_repository_tags must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to registry_repository_tags must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($repository_id) to registry_repository_tags must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/registry/repositories/:repository_id/tags', [@_], $options );
}

=item registry_repository_tag

    my $tag = $api->registry_repository_tag(
        $project_id,
        $repository_id,
        $tag_name,
    );

Sends a C<GET> request to C<projects/:project_id/registry/repositories/:repository_id/tags/:tag_name> and returns the decoded response content.

=cut

sub registry_repository_tag {
    my $self = shift;
    croak 'registry_repository_tag must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to registry_repository_tag must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($repository_id) to registry_repository_tag must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($tag_name) to registry_repository_tag must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/registry/repositories/:repository_id/tags/:tag_name', [@_], $options );
}

=item delete_registry_repository_tag

    $api->delete_registry_repository_tag(
        $project_id,
        $repository_id,
        $tag_name,
    );

Sends a C<DELETE> request to C<projects/:project_id/registry/repositories/:repository_id/tags/:tag_name>.

=cut

sub delete_registry_repository_tag {
    my $self = shift;
    croak 'delete_registry_repository_tag must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to delete_registry_repository_tag must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($repository_id) to delete_registry_repository_tag must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($tag_name) to delete_registry_repository_tag must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/registry/repositories/:repository_id/tags/:tag_name', [@_], $options );
    return;
}

=item bulk_delete_registry_repository_tags

    $api->bulk_delete_registry_repository_tags(
        $project_id,
        $repository_id,
        \%params,
    );

Sends a C<DELETE> request to C<projects/:project_id/registry/repositories/:repository_id/tags>.

=cut

sub bulk_delete_registry_repository_tags {
    my $self = shift;
    croak 'bulk_delete_registry_repository_tags must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to bulk_delete_registry_repository_tags must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($repository_id) to bulk_delete_registry_repository_tags must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to bulk_delete_registry_repository_tags must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/registry/repositories/:repository_id/tags', [@_], $options );
    return;
}

=back

=head2 Custom Attributes

See L<https://docs.gitlab.com/ce/api/custom_attributes.html>.

=over

=item custom_user_attributes

    my $attributes = $api->custom_user_attributes(
        $user_id,
    );

Sends a C<GET> request to C<users/:user_id/custom_attributes> and returns the decoded response content.

=cut

sub custom_user_attributes {
    my $self = shift;
    croak 'custom_user_attributes must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($user_id) to custom_user_attributes must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'users/:user_id/custom_attributes', [@_], $options );
}

=item custom_group_attributes

    my $attributes = $api->custom_group_attributes(
        $group_id,
    );

Sends a C<GET> request to C<groups/:group_id/custom_attributes> and returns the decoded response content.

=cut

sub custom_group_attributes {
    my $self = shift;
    croak 'custom_group_attributes must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($group_id) to custom_group_attributes must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/custom_attributes', [@_], $options );
}

=item custom_project_attributes

    my $attributes = $api->custom_project_attributes(
        $project_id,
    );

Sends a C<GET> request to C<projects/:project_id/custom_attributes> and returns the decoded response content.

=cut

sub custom_project_attributes {
    my $self = shift;
    croak 'custom_project_attributes must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to custom_project_attributes must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/custom_attributes', [@_], $options );
}

=item custom_user_attribute

    my $attribute = $api->custom_user_attribute(
        $user_id,
        $attribute_key,
    );

Sends a C<GET> request to C<users/:user_id/custom_attributes/:attribute_key> and returns the decoded response content.

=cut

sub custom_user_attribute {
    my $self = shift;
    croak 'custom_user_attribute must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($user_id) to custom_user_attribute must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($attribute_key) to custom_user_attribute must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'users/:user_id/custom_attributes/:attribute_key', [@_], $options );
}

=item custom_group_attribute

    my $attribute = $api->custom_group_attribute(
        $group_id,
        $attribute_key,
    );

Sends a C<GET> request to C<groups/:group_id/custom_attributes/:attribute_key> and returns the decoded response content.

=cut

sub custom_group_attribute {
    my $self = shift;
    croak 'custom_group_attribute must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to custom_group_attribute must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($attribute_key) to custom_group_attribute must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/custom_attributes/:attribute_key', [@_], $options );
}

=item custom_project_attribute

    my $attribute = $api->custom_project_attribute(
        $project_id,
        $attribute_key,
    );

Sends a C<GET> request to C<projects/:project_id/custom_attributes/:attribute_key> and returns the decoded response content.

=cut

sub custom_project_attribute {
    my $self = shift;
    croak 'custom_project_attribute must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to custom_project_attribute must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($attribute_key) to custom_project_attribute must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/custom_attributes/:attribute_key', [@_], $options );
}

=item set_custom_user_attribute

    my $attribute = $api->set_custom_user_attribute(
        $user_id,
        $attribute_key,
        \%params,
    );

Sends a C<PUT> request to C<users/:user_id/custom_attributes/:attribute_key> and returns the decoded response content.

=cut

sub set_custom_user_attribute {
    my $self = shift;
    croak 'set_custom_user_attribute must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($user_id) to set_custom_user_attribute must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($attribute_key) to set_custom_user_attribute must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to set_custom_user_attribute must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'users/:user_id/custom_attributes/:attribute_key', [@_], $options );
}

=item set_custom_group_attribute

    my $attribute = $api->set_custom_group_attribute(
        $group_id,
        $attribute_key,
        \%params,
    );

Sends a C<PUT> request to C<groups/:group_id/custom_attributes/:attribute_key> and returns the decoded response content.

=cut

sub set_custom_group_attribute {
    my $self = shift;
    croak 'set_custom_group_attribute must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($group_id) to set_custom_group_attribute must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($attribute_key) to set_custom_group_attribute must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to set_custom_group_attribute must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'groups/:group_id/custom_attributes/:attribute_key', [@_], $options );
}

=item set_custom_project_attribute

    my $attribute = $api->set_custom_project_attribute(
        $project_id,
        $attribute_key,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/custom_attributes/:attribute_key> and returns the decoded response content.

=cut

sub set_custom_project_attribute {
    my $self = shift;
    croak 'set_custom_project_attribute must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to set_custom_project_attribute must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($attribute_key) to set_custom_project_attribute must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to set_custom_project_attribute must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/custom_attributes/:attribute_key', [@_], $options );
}

=item delete_custom_user_attribute

    $api->delete_custom_user_attribute(
        $user_id,
        $attribute_key,
    );

Sends a C<DELETE> request to C<users/:user_id/custom_attributes/:attribute_key>.

=cut

sub delete_custom_user_attribute {
    my $self = shift;
    croak 'delete_custom_user_attribute must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($user_id) to delete_custom_user_attribute must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($attribute_key) to delete_custom_user_attribute must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'users/:user_id/custom_attributes/:attribute_key', [@_], $options );
    return;
}

=item delete_custom_group_attribute

    $api->delete_custom_group_attribute(
        $group_id,
        $attribute_key,
    );

Sends a C<DELETE> request to C<groups/:group_id/custom_attributes/:attribute_key>.

=cut

sub delete_custom_group_attribute {
    my $self = shift;
    croak 'delete_custom_group_attribute must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to delete_custom_group_attribute must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($attribute_key) to delete_custom_group_attribute must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'groups/:group_id/custom_attributes/:attribute_key', [@_], $options );
    return;
}

=item delete_custom_project_attribute

    $api->delete_custom_project_attribute(
        $project_id,
        $attribute_key,
    );

Sends a C<DELETE> request to C<projects/:project_id/custom_attributes/:attribute_key>.

=cut

sub delete_custom_project_attribute {
    my $self = shift;
    croak 'delete_custom_project_attribute must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_custom_project_attribute must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($attribute_key) to delete_custom_project_attribute must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/custom_attributes/:attribute_key', [@_], $options );
    return;
}

=back

=head2 Deployments

See L<https://docs.gitlab.com/ce/api/deployments.html>.

=over

=item deployments

    my $deployments = $api->deployments(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/deployments> and returns the decoded response content.

=cut

sub deployments {
    my $self = shift;
    croak 'deployments must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to deployments must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to deployments must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/deployments', [@_], $options );
}

=item deployment

    my $deployment = $api->deployment(
        $project_id,
        $deployment_id,
    );

Sends a C<GET> request to C<projects/:project_id/deployments/:deployment_id> and returns the decoded response content.

=cut

sub deployment {
    my $self = shift;
    croak 'deployment must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to deployment must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($deployment_id) to deployment must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/deployments/:deployment_id', [@_], $options );
}

=back

=head2 Deploy Keys

See L<https://docs.gitlab.com/ce/api/deploy_keys.html>.

=over

=item all_deploy_keys

    my $keys = $api->all_deploy_keys(
        \%params,
    );

Sends a C<GET> request to C<deploy_keys> and returns the decoded response content.

=cut

sub all_deploy_keys {
    my $self = shift;
    croak 'all_deploy_keys must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to all_deploy_keys must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'deploy_keys', [@_], $options );
}

=item deploy_keys

    my $keys = $api->deploy_keys(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/deploy_keys> and returns the decoded response content.

=cut

sub deploy_keys {
    my $self = shift;
    croak 'deploy_keys must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to deploy_keys must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to deploy_keys must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/deploy_keys', [@_], $options );
}

=item deploy_key

    my $key = $api->deploy_key(
        $project_id,
        $key_id,
    );

Sends a C<GET> request to C<projects/:project_id/deploy_keys/:key_id> and returns the decoded response content.

=cut

sub deploy_key {
    my $self = shift;
    croak 'deploy_key must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to deploy_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($key_id) to deploy_key must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/deploy_keys/:key_id', [@_], $options );
}

=item create_deploy_key

    my $key = $api->create_deploy_key(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/deploy_keys> and returns the decoded response content.

=cut

sub create_deploy_key {
    my $self = shift;
    croak 'create_deploy_key must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_deploy_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_deploy_key must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/deploy_keys', [@_], $options );
}

=item delete_deploy_key

    $api->delete_deploy_key(
        $project_id,
        $key_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/deploy_keys/:key_id>.

=cut

sub delete_deploy_key {
    my $self = shift;
    croak 'delete_deploy_key must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_deploy_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($key_id) to delete_deploy_key must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/deploy_keys/:key_id', [@_], $options );
    return;
}

=item enable_deploy_key

    my $key = $api->enable_deploy_key(
        $project_id,
        $key_id,
    );

Sends a C<POST> request to C<projects/:project_id/deploy_keys/:key_id/enable> and returns the decoded response content.

=cut

sub enable_deploy_key {
    my $self = shift;
    croak 'enable_deploy_key must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to enable_deploy_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($key_id) to enable_deploy_key must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/deploy_keys/:key_id/enable', [@_], $options );
}

=back

=head2 Environments

See L<https://docs.gitlab.com/ce/api/environments.html>.

=over

=item environments

    my $environments = $api->environments(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/environments> and returns the decoded response content.

=cut

sub environments {
    my $self = shift;
    croak 'environments must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to environments must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to environments must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/environments', [@_], $options );
}

=item create_environment

    my $environment = $api->create_environment(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/environments> and returns the decoded response content.

=cut

sub create_environment {
    my $self = shift;
    croak 'create_environment must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_environment must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_environment must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/environments', [@_], $options );
}

=item edit_environment

    my $environment = $api->edit_environment(
        $project_id,
        $environments_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/environments/:environments_id> and returns the decoded response content.

=cut

sub edit_environment {
    my $self = shift;
    croak 'edit_environment must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_environment must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($environments_id) to edit_environment must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_environment must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/environments/:environments_id', [@_], $options );
}

=item delete_environment

    $api->delete_environment(
        $project_id,
        $environment_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/environments/:environment_id>.

=cut

sub delete_environment {
    my $self = shift;
    croak 'delete_environment must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_environment must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($environment_id) to delete_environment must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/environments/:environment_id', [@_], $options );
    return;
}

=item stop_environment

    my $environment = $api->stop_environment(
        $project_id,
        $environment_id,
    );

Sends a C<POST> request to C<projects/:project_id/environments/:environment_id/stop> and returns the decoded response content.

=cut

sub stop_environment {
    my $self = shift;
    croak 'stop_environment must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to stop_environment must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($environment_id) to stop_environment must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/environments/:environment_id/stop', [@_], $options );
}

=back

=head2 Events

See L<https://docs.gitlab.com/ce/api/events.html>.

=over

=item all_events

    my $events = $api->all_events(
        \%params,
    );

Sends a C<GET> request to C<events> and returns the decoded response content.

=cut

sub all_events {
    my $self = shift;
    croak 'all_events must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to all_events must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'events', [@_], $options );
}

=item user_events

    my $events = $api->user_events(
        $user_id,
        \%params,
    );

Sends a C<GET> request to C<users/:user_id/events> and returns the decoded response content.

=cut

sub user_events {
    my $self = shift;
    croak 'user_events must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to user_events must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to user_events must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'users/:user_id/events', [@_], $options );
}

=item project_events

    my $events = $api->project_events(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/events> and returns the decoded response content.

=cut

sub project_events {
    my $self = shift;
    croak 'project_events must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_events must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_events must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/events', [@_], $options );
}

=back

=head2 Feature flags

See L<https://docs.gitlab.com/ce/api/features.html>.

=over

=item features

    my $features = $api->features();

Sends a C<GET> request to C<features> and returns the decoded response content.

=cut

sub features {
    my $self = shift;
    croak "The features method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'features', [@_], $options );
}

=item set_feature

    my $feature = $api->set_feature(
        $name,
        \%params,
    );

Sends a C<POST> request to C<features/:name> and returns the decoded response content.

=cut

sub set_feature {
    my $self = shift;
    croak 'set_feature must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($name) to set_feature must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to set_feature must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'features/:name', [@_], $options );
}

=back

=head2 Gitignores

See L<https://docs.gitlab.com/ce/api/templates/gitignores.html>.

=over

=item gitignores_templates

    my $templates = $api->gitignores_templates(
        \%params,
    );

Sends a C<GET> request to C<templates/gitignores> and returns the decoded response content.

=cut

sub gitignores_templates {
    my $self = shift;
    croak 'gitignores_templates must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to gitignores_templates must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'templates/gitignores', [@_], $options );
}

=item gitignores_template

    my $template = $api->gitignores_template(
        $template_key,
    );

Sends a C<GET> request to C<templates/gitignores/:template_key> and returns the decoded response content.

=cut

sub gitignores_template {
    my $self = shift;
    croak 'gitignores_template must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($template_key) to gitignores_template must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'templates/gitignores/:template_key', [@_], $options );
}

=back

=head2 GitLab CI YMLs

See L<https://docs.gitlab.com/ce/api/templates/gitlab_ci_ymls.html>.

=over

=item gitlab_ci_ymls_templates

    my $templates = $api->gitlab_ci_ymls_templates(
        \%params,
    );

Sends a C<GET> request to C<templates/gitlab_ci_ymls> and returns the decoded response content.

=cut

sub gitlab_ci_ymls_templates {
    my $self = shift;
    croak 'gitlab_ci_ymls_templates must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to gitlab_ci_ymls_templates must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'templates/gitlab_ci_ymls', [@_], $options );
}

=item gitlab_ci_ymls_template

    my $template = $api->gitlab_ci_ymls_template(
        $template_key,
    );

Sends a C<GET> request to C<templates/gitlab_ci_ymls/:template_key> and returns the decoded response content.

=cut

sub gitlab_ci_ymls_template {
    my $self = shift;
    croak 'gitlab_ci_ymls_template must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($template_key) to gitlab_ci_ymls_template must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'templates/gitlab_ci_ymls/:template_key', [@_], $options );
}

=back

=head2 Groups

See L<https://docs.gitlab.com/ce/api/groups.html>.

=over

=item groups

    my $groups = $api->groups(
        \%params,
    );

Sends a C<GET> request to C<groups> and returns the decoded response content.

=cut

sub groups {
    my $self = shift;
    croak 'groups must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to groups must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups', [@_], $options );
}

=item group_subgroups

    my $subgroups = $api->group_subgroups(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/subgroups> and returns the decoded response content.

=cut

sub group_subgroups {
    my $self = shift;
    croak 'group_subgroups must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to group_subgroups must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to group_subgroups must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/subgroups', [@_], $options );
}

=item group_projects

    my $projects = $api->group_projects(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/projects> and returns the decoded response content.

=cut

sub group_projects {
    my $self = shift;
    croak 'group_projects must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to group_projects must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to group_projects must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/projects', [@_], $options );
}

=item group

    my $group = $api->group(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id> and returns the decoded response content.

=cut

sub group {
    my $self = shift;
    croak 'group must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to group must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to group must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id', [@_], $options );
}

=item create_group

    $api->create_group(
        \%params,
    );

Sends a C<POST> request to C<groups>.

=cut

sub create_group {
    my $self = shift;
    croak 'create_group must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_group must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'groups', [@_], $options );
    return;
}

=item transfer_project_to_group

    $api->transfer_project_to_group(
        $group_id,
        $project_id,
    );

Sends a C<POST> request to C<groups/:group_id/projects/:project_id>.

=cut

sub transfer_project_to_group {
    my $self = shift;
    croak 'transfer_project_to_group must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to transfer_project_to_group must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($project_id) to transfer_project_to_group must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'POST', 'groups/:group_id/projects/:project_id', [@_], $options );
    return;
}

=item edit_group

    my $group = $api->edit_group(
        $group_id,
        \%params,
    );

Sends a C<PUT> request to C<groups/:group_id> and returns the decoded response content.

=cut

sub edit_group {
    my $self = shift;
    croak 'edit_group must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to edit_group must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to edit_group must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'groups/:group_id', [@_], $options );
}

=item delete_group

    $api->delete_group(
        $group_id,
    );

Sends a C<DELETE> request to C<groups/:group_id>.

=cut

sub delete_group {
    my $self = shift;
    croak 'delete_group must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($group_id) to delete_group must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'groups/:group_id', [@_], $options );
    return;
}

=item sync_group_with_ldap

    $api->sync_group_with_ldap(
        $group_id,
    );

Sends a C<POST> request to C<groups/:group_id/ldap_sync>.

=cut

sub sync_group_with_ldap {
    my $self = shift;
    croak 'sync_group_with_ldap must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($group_id) to sync_group_with_ldap must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'POST', 'groups/:group_id/ldap_sync', [@_], $options );
    return;
}

=item create_ldap_group_link

    $api->create_ldap_group_link(
        $group_id,
        \%params,
    );

Sends a C<POST> request to C<groups/:group_id/ldap_group_links>.

=cut

sub create_ldap_group_link {
    my $self = shift;
    croak 'create_ldap_group_link must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to create_ldap_group_link must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_ldap_group_link must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'groups/:group_id/ldap_group_links', [@_], $options );
    return;
}

=item delete_ldap_group_link

    $api->delete_ldap_group_link(
        $group_id,
        $cn,
    );

Sends a C<DELETE> request to C<groups/:group_id/ldap_group_links/:cn>.

=cut

sub delete_ldap_group_link {
    my $self = shift;
    croak 'delete_ldap_group_link must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to delete_ldap_group_link must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($cn) to delete_ldap_group_link must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'groups/:group_id/ldap_group_links/:cn', [@_], $options );
    return;
}

=item delete_ldap_provider_group_link

    $api->delete_ldap_provider_group_link(
        $group_id,
        $provider,
        $cn,
    );

Sends a C<DELETE> request to C<groups/:group_id/ldap_group_links/:provider/:cn>.

=cut

sub delete_ldap_provider_group_link {
    my $self = shift;
    croak 'delete_ldap_provider_group_link must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($group_id) to delete_ldap_provider_group_link must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($provider) to delete_ldap_provider_group_link must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($cn) to delete_ldap_provider_group_link must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'groups/:group_id/ldap_group_links/:provider/:cn', [@_], $options );
    return;
}

=back

=head2 Group access requests

See L<https://docs.gitlab.com/ce/api/access_requests.html>.

=over

=item group_access_requests

    my $requests = $api->group_access_requests(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/access_requests> and returns the decoded response content.

=cut

sub group_access_requests {
    my $self = shift;
    croak 'group_access_requests must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to group_access_requests must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to group_access_requests must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/access_requests', [@_], $options );
}

=item request_group_access

    my $request = $api->request_group_access(
        $group_id,
    );

Sends a C<POST> request to C<groups/:group_id/access_requests> and returns the decoded response content.

=cut

sub request_group_access {
    my $self = shift;
    croak 'request_group_access must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($group_id) to request_group_access must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'groups/:group_id/access_requests', [@_], $options );
}

=item approve_group_access

    my $request = $api->approve_group_access(
        $group_id,
        $user_id,
    );

Sends a C<PUT> request to C<groups/:group_id/access_requests/:user_id/approve> and returns the decoded response content.

=cut

sub approve_group_access {
    my $self = shift;
    croak 'approve_group_access must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to approve_group_access must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to approve_group_access must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'PUT', 'groups/:group_id/access_requests/:user_id/approve', [@_], $options );
}

=item deny_group_access

    $api->deny_group_access(
        $group_id,
        $user_id,
    );

Sends a C<DELETE> request to C<groups/:group_id/access_requests/:user_id>.

=cut

sub deny_group_access {
    my $self = shift;
    croak 'deny_group_access must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to deny_group_access must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to deny_group_access must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'groups/:group_id/access_requests/:user_id', [@_], $options );
    return;
}

=back

=head2 Group badges

See L<https://docs.gitlab.com/ce/api/group_badges.html>.

=over

=item group_badges

    my $badges = $api->group_badges(
        $group_id,
    );

Sends a C<GET> request to C<groups/:group_id/badges> and returns the decoded response content.

=cut

sub group_badges {
    my $self = shift;
    croak 'group_badges must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($group_id) to group_badges must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/badges', [@_], $options );
}

=item group_badge

    my $badge = $api->group_badge(
        $group_id,
        $badge_id,
    );

Sends a C<GET> request to C<groups/:group_id/badges/:badge_id> and returns the decoded response content.

=cut

sub group_badge {
    my $self = shift;
    croak 'group_badge must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to group_badge must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($badge_id) to group_badge must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/badges/:badge_id', [@_], $options );
}

=item create_group_badge

    my $badge = $api->create_group_badge(
        $group_id,
        \%params,
    );

Sends a C<POST> request to C<groups/:group_id/badges> and returns the decoded response content.

=cut

sub create_group_badge {
    my $self = shift;
    croak 'create_group_badge must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to create_group_badge must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_group_badge must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'groups/:group_id/badges', [@_], $options );
}

=item edit_group_badge

    my $badge = $api->edit_group_badge(
        $group_id,
        $badge_id,
        \%params,
    );

Sends a C<PUT> request to C<groups/:group_id/badges/:badge_id> and returns the decoded response content.

=cut

sub edit_group_badge {
    my $self = shift;
    croak 'edit_group_badge must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($group_id) to edit_group_badge must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($badge_id) to edit_group_badge must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_group_badge must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'groups/:group_id/badges/:badge_id', [@_], $options );
}

=item delete_group_badge

    $api->delete_group_badge(
        $group_id,
        $badge_id,
    );

Sends a C<DELETE> request to C<groups/:group_id/badges/:badge_id>.

=cut

sub delete_group_badge {
    my $self = shift;
    croak 'delete_group_badge must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to delete_group_badge must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($badge_id) to delete_group_badge must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'groups/:group_id/badges/:badge_id', [@_], $options );
    return;
}

=item preview_group_badge

    my $preview = $api->preview_group_badge(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/badges/render> and returns the decoded response content.

=cut

sub preview_group_badge {
    my $self = shift;
    croak 'preview_group_badge must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to preview_group_badge must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to preview_group_badge must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/badges/render', [@_], $options );
}

=back

=head2 Group members

See L<https://docs.gitlab.com/ce/api/members.html>.

=over

=item group_members

    my $members = $api->group_members(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/members> and returns the decoded response content.

=cut

sub group_members {
    my $self = shift;
    croak 'group_members must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to group_members must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to group_members must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/members', [@_], $options );
}

=item all_group_members

    my $members = $api->all_group_members(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/members/all> and returns the decoded response content.

=cut

sub all_group_members {
    my $self = shift;
    croak 'all_group_members must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to all_group_members must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to all_group_members must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/members/all', [@_], $options );
}

=item group_member

    my $member = $api->group_member(
        $project_id,
        $user_id,
    );

Sends a C<GET> request to C<groups/:project_id/members/:user_id> and returns the decoded response content.

=cut

sub group_member {
    my $self = shift;
    croak 'group_member must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to group_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to group_member must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:project_id/members/:user_id', [@_], $options );
}

=item add_group_member

    my $member = $api->add_group_member(
        $group_id,
        \%params,
    );

Sends a C<POST> request to C<groups/:group_id/members> and returns the decoded response content.

=cut

sub add_group_member {
    my $self = shift;
    croak 'add_group_member must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to add_group_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to add_group_member must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'groups/:group_id/members', [@_], $options );
}

=item update_group_member

    my $member = $api->update_group_member(
        $group_id,
        $user_id,
        \%params,
    );

Sends a C<PUT> request to C<groups/:group_id/members/:user_id> and returns the decoded response content.

=cut

sub update_group_member {
    my $self = shift;
    croak 'update_group_member must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($group_id) to update_group_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to update_group_member must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to update_group_member must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'groups/:group_id/members/:user_id', [@_], $options );
}

=item remove_group_member

    $api->remove_group_member(
        $group_id,
        $user_id,
    );

Sends a C<DELETE> request to C<groups/:group_id/members/:user_id>.

=cut

sub remove_group_member {
    my $self = shift;
    croak 'remove_group_member must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to remove_group_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to remove_group_member must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'groups/:group_id/members/:user_id', [@_], $options );
    return;
}

=back

=head2 Issues

See L<https://docs.gitlab.com/ce/api/issues.html>.

=over

=item global_issues

    my $issues = $api->global_issues(
        \%params,
    );

Sends a C<GET> request to C<issues> and returns the decoded response content.

=cut

sub global_issues {
    my $self = shift;
    croak 'global_issues must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to global_issues must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'issues', [@_], $options );
}

=item group_issues

    my $issues = $api->group_issues(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/issues> and returns the decoded response content.

=cut

sub group_issues {
    my $self = shift;
    croak 'group_issues must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to group_issues must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to group_issues must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/issues', [@_], $options );
}

=item issues

    my $issues = $api->issues(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/issues> and returns the decoded response content.

=cut

sub issues {
    my $self = shift;
    croak 'issues must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to issues must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to issues must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues', [@_], $options );
}

=item issue

    my $issue = $api->issue(
        $project_id,
        $issue_iid,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid> and returns the decoded response content.

=cut

sub issue {
    my $self = shift;
    croak 'issue must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to issue must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid', [@_], $options );
}

=item create_issue

    my $issue = $api->create_issue(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/issues> and returns the decoded response content.

=cut

sub create_issue {
    my $self = shift;
    croak 'create_issue must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_issue must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_issue must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues', [@_], $options );
}

=item edit_issue

    my $issue = $api->edit_issue(
        $project_id,
        $issue_iid,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/issues/:issue_iid> and returns the decoded response content.

=cut

sub edit_issue {
    my $self = shift;
    croak 'edit_issue must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_issue must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to edit_issue must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_issue must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/issues/:issue_iid', [@_], $options );
}

=item delete_issue

    $api->delete_issue(
        $project_id,
        $issue_iid,
    );

Sends a C<DELETE> request to C<projects/:project_id/issues/:issue_iid>.

=cut

sub delete_issue {
    my $self = shift;
    croak 'delete_issue must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_issue must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to delete_issue must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/issues/:issue_iid', [@_], $options );
    return;
}

=item move_issue

    my $issue = $api->move_issue(
        $project_id,
        $issue_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/move> and returns the decoded response content.

=cut

sub move_issue {
    my $self = shift;
    croak 'move_issue must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to move_issue must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to move_issue must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to move_issue must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/move', [@_], $options );
}

=item subscribe_to_issue

    my $issue = $api->subscribe_to_issue(
        $project_id,
        $issue_iid,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/subscribe> and returns the decoded response content.

=cut

sub subscribe_to_issue {
    my $self = shift;
    croak 'subscribe_to_issue must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to subscribe_to_issue must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to subscribe_to_issue must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/subscribe', [@_], $options );
}

=item unsubscribe_from_issue

    my $issue = $api->unsubscribe_from_issue(
        $project_id,
        $issue_iid,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/unsubscribe> and returns the decoded response content.

=cut

sub unsubscribe_from_issue {
    my $self = shift;
    croak 'unsubscribe_from_issue must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to unsubscribe_from_issue must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to unsubscribe_from_issue must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/unsubscribe', [@_], $options );
}

=item create_issue_todo

    my $todo = $api->create_issue_todo(
        $project_id,
        $issue_iid,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/todo> and returns the decoded response content.

=cut

sub create_issue_todo {
    my $self = shift;
    croak 'create_issue_todo must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to create_issue_todo must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to create_issue_todo must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/todo', [@_], $options );
}

=item set_issue_time_estimate

    my $tracking = $api->set_issue_time_estimate(
        $project_id,
        $issue_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/time_estimate> and returns the decoded response content.

=cut

sub set_issue_time_estimate {
    my $self = shift;
    croak 'set_issue_time_estimate must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to set_issue_time_estimate must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to set_issue_time_estimate must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to set_issue_time_estimate must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/time_estimate', [@_], $options );
}

=item reset_issue_time_estimate

    my $tracking = $api->reset_issue_time_estimate(
        $project_id,
        $issue_iid,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/reset_time_estimate> and returns the decoded response content.

=cut

sub reset_issue_time_estimate {
    my $self = shift;
    croak 'reset_issue_time_estimate must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to reset_issue_time_estimate must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to reset_issue_time_estimate must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/reset_time_estimate', [@_], $options );
}

=item add_issue_spent_time

    my $tracking = $api->add_issue_spent_time(
        $project_id,
        $issue_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/add_spent_time> and returns the decoded response content.

=cut

sub add_issue_spent_time {
    my $self = shift;
    croak 'add_issue_spent_time must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to add_issue_spent_time must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to add_issue_spent_time must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to add_issue_spent_time must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/add_spent_time', [@_], $options );
}

=item reset_issue_spent_time

    my $tracking = $api->reset_issue_spent_time(
        $project_id,
        $issue_iid,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/reset_spent_time> and returns the decoded response content.

=cut

sub reset_issue_spent_time {
    my $self = shift;
    croak 'reset_issue_spent_time must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to reset_issue_spent_time must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to reset_issue_spent_time must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/reset_spent_time', [@_], $options );
}

=item issue_time_stats

    my $tracking = $api->issue_time_stats(
        $project_id,
        $issue_iid,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/time_stats> and returns the decoded response content.

=cut

sub issue_time_stats {
    my $self = shift;
    croak 'issue_time_stats must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to issue_time_stats must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_time_stats must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/time_stats', [@_], $options );
}

=item issue_closed_by

    my $merge_requests = $api->issue_closed_by(
        $project_id,
        $issue_iid,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/closed_by> and returns the decoded response content.

=cut

sub issue_closed_by {
    my $self = shift;
    croak 'issue_closed_by must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to issue_closed_by must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_closed_by must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/closed_by', [@_], $options );
}

=item issue_user_agent_detail

    my $user_agent = $api->issue_user_agent_detail(
        $project_id,
        $issue_iid,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/user_agent_detail> and returns the decoded response content.

=cut

sub issue_user_agent_detail {
    my $self = shift;
    croak 'issue_user_agent_detail must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to issue_user_agent_detail must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_user_agent_detail must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/user_agent_detail', [@_], $options );
}

=back

=head2 Issue Boards

See L<https://docs.gitlab.com/ce/api/boards.html>.

=over

=item project_boards

    my $boards = $api->project_boards(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/boards> and returns the decoded response content.

=cut

sub project_boards {
    my $self = shift;
    croak 'project_boards must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_boards must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_boards must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/boards', [@_], $options );
}

=item project_board_lists

    my $lists = $api->project_board_lists(
        $project_id,
        $board_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/boards/:board_id/lists> and returns the decoded response content.

=cut

sub project_board_lists {
    my $self = shift;
    croak 'project_board_lists must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to project_board_lists must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to project_board_lists must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to project_board_lists must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/boards/:board_id/lists', [@_], $options );
}

=item project_board_list

    my $list = $api->project_board_list(
        $project_id,
        $board_id,
        $list_id,
    );

Sends a C<GET> request to C<projects/:project_id/boards/:board_id/lists/:list_id> and returns the decoded response content.

=cut

sub project_board_list {
    my $self = shift;
    croak 'project_board_list must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to project_board_list must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to project_board_list must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($list_id) to project_board_list must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/boards/:board_id/lists/:list_id', [@_], $options );
}

=item create_project_board_list

    my $list = $api->create_project_board_list(
        $project_id,
        $board_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/boards/:board_id/lists> and returns the decoded response content.

=cut

sub create_project_board_list {
    my $self = shift;
    croak 'create_project_board_list must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_project_board_list must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to create_project_board_list must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_project_board_list must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/boards/:board_id/lists', [@_], $options );
}

=item edit_project_board_list

    my $list = $api->edit_project_board_list(
        $project_id,
        $board_id,
        $list_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/boards/:board_id/lists/:list_id> and returns the decoded response content.

=cut

sub edit_project_board_list {
    my $self = shift;
    croak 'edit_project_board_list must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to edit_project_board_list must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to edit_project_board_list must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($list_id) to edit_project_board_list must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to edit_project_board_list must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/boards/:board_id/lists/:list_id', [@_], $options );
}

=item delete_project_board_list

    $api->delete_project_board_list(
        $project_id,
        $board_id,
        $list_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/boards/:board_id/lists/:list_id>.

=cut

sub delete_project_board_list {
    my $self = shift;
    croak 'delete_project_board_list must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to delete_project_board_list must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to delete_project_board_list must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($list_id) to delete_project_board_list must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/boards/:board_id/lists/:list_id', [@_], $options );
    return;
}

=back

=head2 Group Issue Boards

See L<https://docs.gitlab.com/ce/api/group_boards.html>.

=over

=item group_boards

    my $boards = $api->group_boards(
        $group_id,
    );

Sends a C<GET> request to C<groups/:group_id/boards> and returns the decoded response content.

=cut

sub group_boards {
    my $self = shift;
    croak 'group_boards must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($group_id) to group_boards must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/boards', [@_], $options );
}

=item group_board

    my $board = $api->group_board(
        $group_id,
        $board_id,
    );

Sends a C<GET> request to C<groups/:group_id/boards/:board_id> and returns the decoded response content.

=cut

sub group_board {
    my $self = shift;
    croak 'group_board must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to group_board must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to group_board must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/boards/:board_id', [@_], $options );
}

=item group_board_lists

    my $lists = $api->group_board_lists(
        $group_id,
        $board_id,
    );

Sends a C<GET> request to C<groups/:group_id/boards/:board_id/lists> and returns the decoded response content.

=cut

sub group_board_lists {
    my $self = shift;
    croak 'group_board_lists must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to group_board_lists must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to group_board_lists must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/boards/:board_id/lists', [@_], $options );
}

=item group_board_list

    my $list = $api->group_board_list(
        $group_id,
        $board_id,
        $list_id,
    );

Sends a C<GET> request to C<groups/:group_id/boards/:board_id/lists/:list_id> and returns the decoded response content.

=cut

sub group_board_list {
    my $self = shift;
    croak 'group_board_list must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($group_id) to group_board_list must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to group_board_list must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($list_id) to group_board_list must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/boards/:board_id/lists/:list_id', [@_], $options );
}

=item create_group_board_list

    my $list = $api->create_group_board_list(
        $group_id,
        $board_id,
        \%params,
    );

Sends a C<POST> request to C<groups/:group_id/boards/:board_id/lists> and returns the decoded response content.

=cut

sub create_group_board_list {
    my $self = shift;
    croak 'create_group_board_list must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($group_id) to create_group_board_list must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to create_group_board_list must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_group_board_list must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'groups/:group_id/boards/:board_id/lists', [@_], $options );
}

=item edit_group_board_list

    my $list = $api->edit_group_board_list(
        $group_id,
        $board_id,
        $list_id,
        \%params,
    );

Sends a C<PUT> request to C<groups/:group_id/boards/:board_id/lists/:list_id> and returns the decoded response content.

=cut

sub edit_group_board_list {
    my $self = shift;
    croak 'edit_group_board_list must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($group_id) to edit_group_board_list must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to edit_group_board_list must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($list_id) to edit_group_board_list must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to edit_group_board_list must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'groups/:group_id/boards/:board_id/lists/:list_id', [@_], $options );
}

=item delete_group_board_list

    $api->delete_group_board_list(
        $group_id,
        $board_id,
        $list_id,
    );

Sends a C<DELETE> request to C<groups/:group_id/boards/:board_id/lists/:list_id>.

=cut

sub delete_group_board_list {
    my $self = shift;
    croak 'delete_group_board_list must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($group_id) to delete_group_board_list must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($board_id) to delete_group_board_list must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($list_id) to delete_group_board_list must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'groups/:group_id/boards/:board_id/lists/:list_id', [@_], $options );
    return;
}

=back

=head2 Jobs

See L<https://docs.gitlab.com/ce/api/jobs.html>.

=over

=item jobs

    my $jobs = $api->jobs(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/jobs> and returns the decoded response content.

=cut

sub jobs {
    my $self = shift;
    croak 'jobs must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to jobs must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to jobs must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/jobs', [@_], $options );
}

=item pipeline_jobs

    my $jobs = $api->pipeline_jobs(
        $project_id,
        $pipeline_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/pipelines/:pipeline_id/jobs> and returns the decoded response content.

=cut

sub pipeline_jobs {
    my $self = shift;
    croak 'pipeline_jobs must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to pipeline_jobs must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_id) to pipeline_jobs must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to pipeline_jobs must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/pipelines/:pipeline_id/jobs', [@_], $options );
}

=item job

    my $job = $api->job(
        $project_id,
        $job_id,
    );

Sends a C<GET> request to C<projects/:project_id/jobs/:job_id> and returns the decoded response content.

=cut

sub job {
    my $self = shift;
    croak 'job must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to job must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($job_id) to job must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/jobs/:job_id', [@_], $options );
}

=item job_artifacts

    my $artifacts = $api->job_artifacts(
        $project_id,
        $job_id,
    );

Sends a C<GET> request to C<projects/:project_id/jobs/:job_id/artifacts> and returns the decoded response content.

=cut

sub job_artifacts {
    my $self = shift;
    croak 'job_artifacts must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to job_artifacts must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($job_id) to job_artifacts must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/jobs/:job_id/artifacts', [@_], $options );
}

=item job_artifacts_archive

    my $archive = $api->job_artifacts_archive(
        $project_id,
        $ref_name,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/jobs/artifacts/:ref_name/download> and returns the decoded response content.

=cut

sub job_artifacts_archive {
    my $self = shift;
    croak 'job_artifacts_archive must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to job_artifacts_archive must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($ref_name) to job_artifacts_archive must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to job_artifacts_archive must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/jobs/artifacts/:ref_name/download', [@_], $options );
}

=item job_artifacts_file

    my $file = $api->job_artifacts_file(
        $project_id,
        $job_id,
        $artifact_path,
    );

Sends a C<GET> request to C<projects/:project_id/jobs/:job_id/artifacts/:artifact_path> and returns the decoded response content.

=cut

sub job_artifacts_file {
    my $self = shift;
    croak 'job_artifacts_file must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to job_artifacts_file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($job_id) to job_artifacts_file must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($artifact_path) to job_artifacts_file must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/jobs/:job_id/artifacts/:artifact_path', [@_], $options );
}

=item job_trace_file

    my $file = $api->job_trace_file(
        $project_id,
        $job_id,
    );

Sends a C<GET> request to C<projects/:project_id/jobs/:job_id/trace> and returns the decoded response content.

=cut

sub job_trace_file {
    my $self = shift;
    croak 'job_trace_file must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to job_trace_file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($job_id) to job_trace_file must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/jobs/:job_id/trace', [@_], $options );
}

=item cancel_job

    my $job = $api->cancel_job(
        $project_id,
        $job_id,
    );

Sends a C<POST> request to C<projects/:project_id/jobs/:job_id/cancel> and returns the decoded response content.

=cut

sub cancel_job {
    my $self = shift;
    croak 'cancel_job must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to cancel_job must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($job_id) to cancel_job must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/jobs/:job_id/cancel', [@_], $options );
}

=item retry_job

    my $job = $api->retry_job(
        $project_id,
        $job_id,
    );

Sends a C<POST> request to C<projects/:project_id/jobs/:job_id/retry> and returns the decoded response content.

=cut

sub retry_job {
    my $self = shift;
    croak 'retry_job must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to retry_job must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($job_id) to retry_job must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/jobs/:job_id/retry', [@_], $options );
}

=item erase_job

    my $job = $api->erase_job(
        $project_id,
        $job_id,
    );

Sends a C<POST> request to C<projects/:project_id/jobs/:job_id/erase> and returns the decoded response content.

=cut

sub erase_job {
    my $self = shift;
    croak 'erase_job must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to erase_job must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($job_id) to erase_job must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/jobs/:job_id/erase', [@_], $options );
}

=item keep_job_artifacts

    my $job = $api->keep_job_artifacts(
        $project_id,
        $job_id,
    );

Sends a C<POST> request to C<projects/:project_id/jobs/:job_id/artifacts/keep> and returns the decoded response content.

=cut

sub keep_job_artifacts {
    my $self = shift;
    croak 'keep_job_artifacts must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to keep_job_artifacts must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($job_id) to keep_job_artifacts must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/jobs/:job_id/artifacts/keep', [@_], $options );
}

=item play_job

    my $job = $api->play_job(
        $project_id,
        $job_id,
    );

Sends a C<POST> request to C<projects/:project_id/jobs/:job_id/play> and returns the decoded response content.

=cut

sub play_job {
    my $self = shift;
    croak 'play_job must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to play_job must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($job_id) to play_job must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/jobs/:job_id/play', [@_], $options );
}

=back

=head2 Keys

See L<https://docs.gitlab.com/ce/api/keys.html>.

=over

=item key

    my $key = $api->key(
        $key_id,
    );

Sends a C<GET> request to C<keys/:key_id> and returns the decoded response content.

=cut

sub key {
    my $self = shift;
    croak 'key must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($key_id) to key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'keys/:key_id', [@_], $options );
}

=back

=head2 Labels

See L<https://docs.gitlab.com/ce/api/labels.html>.

=over

=item labels

    my $labels = $api->labels(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/labels> and returns the decoded response content.

=cut

sub labels {
    my $self = shift;
    croak 'labels must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to labels must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to labels must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/labels', [@_], $options );
}

=item create_label

    my $label = $api->create_label(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/labels> and returns the decoded response content.

=cut

sub create_label {
    my $self = shift;
    croak 'create_label must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_label must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_label must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/labels', [@_], $options );
}

=item delete_label

    $api->delete_label(
        $project_id,
        \%params,
    );

Sends a C<DELETE> request to C<projects/:project_id/labels>.

=cut

sub delete_label {
    my $self = shift;
    croak 'delete_label must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to delete_label must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to delete_label must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/labels', [@_], $options );
    return;
}

=item edit_label

    my $label = $api->edit_label(
        $project_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/labels> and returns the decoded response content.

=cut

sub edit_label {
    my $self = shift;
    croak 'edit_label must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to edit_label must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to edit_label must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/labels', [@_], $options );
}

=item subscribe_to_label

    my $label = $api->subscribe_to_label(
        $project_id,
        $label_id,
    );

Sends a C<POST> request to C<projects/:project_id/labels/:label_id/subscribe> and returns the decoded response content.

=cut

sub subscribe_to_label {
    my $self = shift;
    croak 'subscribe_to_label must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to subscribe_to_label must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($label_id) to subscribe_to_label must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/labels/:label_id/subscribe', [@_], $options );
}

=item unsubscribe_from_label

    $api->unsubscribe_from_label(
        $project_id,
        $label_id,
    );

Sends a C<POST> request to C<projects/:project_id/labels/:label_id/unsubscribe>.

=cut

sub unsubscribe_from_label {
    my $self = shift;
    croak 'unsubscribe_from_label must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to unsubscribe_from_label must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($label_id) to unsubscribe_from_label must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'POST', 'projects/:project_id/labels/:label_id/unsubscribe', [@_], $options );
    return;
}

=back

=head2 Markdown

See L<https://docs.gitlab.com/ce/api/markdown.html>.

=over

=item markdown

    my $html = $api->markdown(
        \%params,
    );

Sends a C<POST> request to C<markdown> and returns the decoded response content.

=cut

sub markdown {
    my $self = shift;
    croak 'markdown must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to markdown must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'markdown', [@_], $options );
}

=back

=head2 Merge requests

See L<https://docs.gitlab.com/ce/api/merge_requests.html>.

=over

=item global_merge_requests

    my $merge_requests = $api->global_merge_requests(
        \%params,
    );

Sends a C<GET> request to C<merge_requests> and returns the decoded response content.

=cut

sub global_merge_requests {
    my $self = shift;
    croak 'global_merge_requests must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to global_merge_requests must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'merge_requests', [@_], $options );
}

=item merge_requests

    my $merge_requests = $api->merge_requests(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests> and returns the decoded response content.

=cut

sub merge_requests {
    my $self = shift;
    croak 'merge_requests must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to merge_requests must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to merge_requests must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests', [@_], $options );
}

=item merge_request

    my $merge_request = $api->merge_request(
        $project_id,
        $merge_request_iid,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid> and returns the decoded response content.

=cut

sub merge_request {
    my $self = shift;
    croak 'merge_request must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid', [@_], $options );
}

=item merge_request_commits

    my $commits = $api->merge_request_commits(
        $project_id,
        $merge_request_iid,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/commits> and returns the decoded response content.

=cut

sub merge_request_commits {
    my $self = shift;
    croak 'merge_request_commits must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to merge_request_commits must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_commits must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/commits', [@_], $options );
}

=item merge_request_with_changes

    my $merge_request = $api->merge_request_with_changes(
        $project_id,
        $merge_request_iid,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/changes> and returns the decoded response content.

=cut

sub merge_request_with_changes {
    my $self = shift;
    croak 'merge_request_with_changes must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to merge_request_with_changes must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_with_changes must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/changes', [@_], $options );
}

=item create_merge_request

    my $merge_request = $api->create_merge_request(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests> and returns the decoded response content.

=cut

sub create_merge_request {
    my $self = shift;
    croak 'create_merge_request must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_merge_request must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests', [@_], $options );
}

=item edit_merge_request

    my $merge_request = $api->edit_merge_request(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/merge_requests/:merge_request_iid> and returns the decoded response content.

=cut

sub edit_merge_request {
    my $self = shift;
    croak 'edit_merge_request must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to edit_merge_request must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_merge_request must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/merge_requests/:merge_request_iid', [@_], $options );
}

=item delete_merge_request

    $api->delete_merge_request(
        $project_id,
        $merge_request_iid,
    );

Sends a C<DELETE> request to C<projects/:project_id/merge_requests/:merge_request_iid>.

=cut

sub delete_merge_request {
    my $self = shift;
    croak 'delete_merge_request must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to delete_merge_request must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/merge_requests/:merge_request_iid', [@_], $options );
    return;
}

=item accept_merge_request

    my $merge_request = $api->accept_merge_request(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/merge_requests/:merge_request_iid/merge> and returns the decoded response content.

=cut

sub accept_merge_request {
    my $self = shift;
    croak 'accept_merge_request must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to accept_merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to accept_merge_request must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to accept_merge_request must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/merge_requests/:merge_request_iid/merge', [@_], $options );
}

=item cancel_merge_when_pipeline_succeeds

    my $merge_request = $api->cancel_merge_when_pipeline_succeeds(
        $project_id,
        $merge_request_iid,
    );

Sends a C<PUT> request to C<projects/:project_id/merge_requests/:merge_request_iid/cancel_merge_when_pipeline_succeeds> and returns the decoded response content.

=cut

sub cancel_merge_when_pipeline_succeeds {
    my $self = shift;
    croak 'cancel_merge_when_pipeline_succeeds must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to cancel_merge_when_pipeline_succeeds must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to cancel_merge_when_pipeline_succeeds must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/merge_requests/:merge_request_iid/cancel_merge_when_pipeline_succeeds', [@_], $options );
}

=item merge_request_closes_issues

    my $issues = $api->merge_request_closes_issues(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/closes_issues> and returns the decoded response content.

=cut

sub merge_request_closes_issues {
    my $self = shift;
    croak 'merge_request_closes_issues must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to merge_request_closes_issues must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_closes_issues must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to merge_request_closes_issues must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/closes_issues', [@_], $options );
}

=item subscribe_to_merge_request

    my $merge_request = $api->subscribe_to_merge_request(
        $project_id,
        $merge_request_iid,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/subscribe> and returns the decoded response content.

=cut

sub subscribe_to_merge_request {
    my $self = shift;
    croak 'subscribe_to_merge_request must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to subscribe_to_merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to subscribe_to_merge_request must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/subscribe', [@_], $options );
}

=item unsubscribe_from_merge_request

    my $merge_request = $api->unsubscribe_from_merge_request(
        $project_id,
        $merge_request_iid,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/unsubscribe> and returns the decoded response content.

=cut

sub unsubscribe_from_merge_request {
    my $self = shift;
    croak 'unsubscribe_from_merge_request must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to unsubscribe_from_merge_request must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to unsubscribe_from_merge_request must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/unsubscribe', [@_], $options );
}

=item create_merge_request_todo

    my $todo = $api->create_merge_request_todo(
        $project_id,
        $merge_request_iid,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/todo> and returns the decoded response content.

=cut

sub create_merge_request_todo {
    my $self = shift;
    croak 'create_merge_request_todo must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to create_merge_request_todo must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to create_merge_request_todo must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/todo', [@_], $options );
}

=item merge_request_diff_versions

    my $versions = $api->merge_request_diff_versions(
        $project_id,
        $merge_request_iid,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/versions> and returns the decoded response content.

=cut

sub merge_request_diff_versions {
    my $self = shift;
    croak 'merge_request_diff_versions must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to merge_request_diff_versions must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_diff_versions must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/versions', [@_], $options );
}

=item merge_request_diff_version

    my $version = $api->merge_request_diff_version(
        $project_id,
        $merge_request_iid,
        $version_id,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/versions/:version_id> and returns the decoded response content.

=cut

sub merge_request_diff_version {
    my $self = shift;
    croak 'merge_request_diff_version must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to merge_request_diff_version must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_diff_version must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($version_id) to merge_request_diff_version must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/versions/:version_id', [@_], $options );
}

=item set_merge_request_time_estimate

    my $tracking = $api->set_merge_request_time_estimate(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/time_estimate> and returns the decoded response content.

=cut

sub set_merge_request_time_estimate {
    my $self = shift;
    croak 'set_merge_request_time_estimate must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to set_merge_request_time_estimate must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to set_merge_request_time_estimate must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to set_merge_request_time_estimate must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/time_estimate', [@_], $options );
}

=item reset_merge_request_time_estimate

    my $tracking = $api->reset_merge_request_time_estimate(
        $project_id,
        $merge_request_iid,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/reset_time_estimate> and returns the decoded response content.

=cut

sub reset_merge_request_time_estimate {
    my $self = shift;
    croak 'reset_merge_request_time_estimate must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to reset_merge_request_time_estimate must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to reset_merge_request_time_estimate must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/reset_time_estimate', [@_], $options );
}

=item add_merge_request_spent_time

    my $tracking = $api->add_merge_request_spent_time(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/add_spent_time> and returns the decoded response content.

=cut

sub add_merge_request_spent_time {
    my $self = shift;
    croak 'add_merge_request_spent_time must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to add_merge_request_spent_time must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to add_merge_request_spent_time must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to add_merge_request_spent_time must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/add_spent_time', [@_], $options );
}

=item reset_merge_request_spent_time

    my $tracking = $api->reset_merge_request_spent_time(
        $project_id,
        $merge_request_iid,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/reset_spent_time> and returns the decoded response content.

=cut

sub reset_merge_request_spent_time {
    my $self = shift;
    croak 'reset_merge_request_spent_time must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to reset_merge_request_spent_time must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to reset_merge_request_spent_time must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/reset_spent_time', [@_], $options );
}

=item merge_request_time_stats

    my $tracking = $api->merge_request_time_stats(
        $project_id,
        $merge_request_iid,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/time_stats> and returns the decoded response content.

=cut

sub merge_request_time_stats {
    my $self = shift;
    croak 'merge_request_time_stats must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to merge_request_time_stats must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_time_stats must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/time_stats', [@_], $options );
}

=back

=head2 Milestones

See L<https://docs.gitlab.com/ce/api/milestones.html>.

=over

=item project_milestones

    my $milestones = $api->project_milestones(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/milestones> and returns the decoded response content.

=cut

sub project_milestones {
    my $self = shift;
    croak 'project_milestones must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_milestones must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_milestones must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/milestones', [@_], $options );
}

=item project_milestone

    my $milestone = $api->project_milestone(
        $project_id,
        $milestone_id,
    );

Sends a C<GET> request to C<projects/:project_id/milestones/:milestone_id> and returns the decoded response content.

=cut

sub project_milestone {
    my $self = shift;
    croak 'project_milestone must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_milestone must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($milestone_id) to project_milestone must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/milestones/:milestone_id', [@_], $options );
}

=item create_project_milestone

    my $milestone = $api->create_project_milestone(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/milestones> and returns the decoded response content.

=cut

sub create_project_milestone {
    my $self = shift;
    croak 'create_project_milestone must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_project_milestone must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_project_milestone must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/milestones', [@_], $options );
}

=item edit_project_milestone

    my $milestone = $api->edit_project_milestone(
        $project_id,
        $milestone_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/milestones/:milestone_id> and returns the decoded response content.

=cut

sub edit_project_milestone {
    my $self = shift;
    croak 'edit_project_milestone must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_project_milestone must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($milestone_id) to edit_project_milestone must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_project_milestone must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/milestones/:milestone_id', [@_], $options );
}

=item project_milestone_issues

    my $issues = $api->project_milestone_issues(
        $project_id,
        $milestone_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/milestones/:milestone_id/issues> and returns the decoded response content.

=cut

sub project_milestone_issues {
    my $self = shift;
    croak 'project_milestone_issues must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to project_milestone_issues must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($milestone_id) to project_milestone_issues must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to project_milestone_issues must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/milestones/:milestone_id/issues', [@_], $options );
}

=item project_milestone_merge_requests

    my $merge_requests = $api->project_milestone_merge_requests(
        $project_id,
        $milestone_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/milestones/:milestone_id/merge_requests> and returns the decoded response content.

=cut

sub project_milestone_merge_requests {
    my $self = shift;
    croak 'project_milestone_merge_requests must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to project_milestone_merge_requests must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($milestone_id) to project_milestone_merge_requests must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to project_milestone_merge_requests must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/milestones/:milestone_id/merge_requests', [@_], $options );
}

=back

=head2 Group milestones

See L<https://docs.gitlab.com/ce/api/group_milestones.html>.

=over

=item group_milestones

    my $milestones = $api->group_milestones(
        $group_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/milestones> and returns the decoded response content.

=cut

sub group_milestones {
    my $self = shift;
    croak 'group_milestones must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to group_milestones must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to group_milestones must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/milestones', [@_], $options );
}

=item group_milestone

    my $milestone = $api->group_milestone(
        $group_id,
        $milestone_id,
    );

Sends a C<GET> request to C<groups/:group_id/milestones/:milestone_id> and returns the decoded response content.

=cut

sub group_milestone {
    my $self = shift;
    croak 'group_milestone must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($group_id) to group_milestone must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($milestone_id) to group_milestone must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/milestones/:milestone_id', [@_], $options );
}

=item create_group_milestone

    my $milestone = $api->create_group_milestone(
        $group_id,
        \%params,
    );

Sends a C<POST> request to C<groups/:group_id/milestones> and returns the decoded response content.

=cut

sub create_group_milestone {
    my $self = shift;
    croak 'create_group_milestone must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to create_group_milestone must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_group_milestone must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'groups/:group_id/milestones', [@_], $options );
}

=item edit_group_milestone

    my $milestone = $api->edit_group_milestone(
        $group_id,
        $milestone_id,
        \%params,
    );

Sends a C<PUT> request to C<groups/:group_id/milestones/:milestone_id> and returns the decoded response content.

=cut

sub edit_group_milestone {
    my $self = shift;
    croak 'edit_group_milestone must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($group_id) to edit_group_milestone must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($milestone_id) to edit_group_milestone must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_group_milestone must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'groups/:group_id/milestones/:milestone_id', [@_], $options );
}

=item group_milestone_issues

    my $issues = $api->group_milestone_issues(
        $group_id,
        $milestone_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/milestones/:milestone_id/issues> and returns the decoded response content.

=cut

sub group_milestone_issues {
    my $self = shift;
    croak 'group_milestone_issues must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($group_id) to group_milestone_issues must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($milestone_id) to group_milestone_issues must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to group_milestone_issues must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/milestones/:milestone_id/issues', [@_], $options );
}

=item group_milestone_merge_requests

    my $merge_requests = $api->group_milestone_merge_requests(
        $group_id,
        $milestone_id,
        \%params,
    );

Sends a C<GET> request to C<groups/:group_id/milestones/:milestone_id/merge_requests> and returns the decoded response content.

=cut

sub group_milestone_merge_requests {
    my $self = shift;
    croak 'group_milestone_merge_requests must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($group_id) to group_milestone_merge_requests must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($milestone_id) to group_milestone_merge_requests must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to group_milestone_merge_requests must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'groups/:group_id/milestones/:milestone_id/merge_requests', [@_], $options );
}

=back

=head2 Namespaces

See L<https://docs.gitlab.com/ce/api/namespaces.html>.

=over

=item namespaces

    my $namespaces = $api->namespaces(
        \%params,
    );

Sends a C<GET> request to C<namespaces> and returns the decoded response content.

=cut

sub namespaces {
    my $self = shift;
    croak 'namespaces must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to namespaces must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'namespaces', [@_], $options );
}

=item namespace

    my $namespace = $api->namespace(
        $namespace_id,
    );

Sends a C<GET> request to C<namespaces/:namespace_id> and returns the decoded response content.

=cut

sub namespace {
    my $self = shift;
    croak 'namespace must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($namespace_id) to namespace must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'namespaces/:namespace_id', [@_], $options );
}

=back

=head2 Notes

See L<https://docs.gitlab.com/ce/api/notes.html>.

=over

=item issue_notes

    my $notes = $api->issue_notes(
        $project_id,
        $issue_iid,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/notes> and returns the decoded response content.

=cut

sub issue_notes {
    my $self = shift;
    croak 'issue_notes must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to issue_notes must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_notes must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to issue_notes must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/notes', [@_], $options );
}

=item issue_note

    my $note = $api->issue_note(
        $project_id,
        $issue_iid,
        $note_id,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/notes/:note_id> and returns the decoded response content.

=cut

sub issue_note {
    my $self = shift;
    croak 'issue_note must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to issue_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to issue_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/notes/:note_id', [@_], $options );
}

=item create_issue_note

    my $note = $api->create_issue_note(
        $project_id,
        $issue_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/notes> and returns the decoded response content.

=cut

sub create_issue_note {
    my $self = shift;
    croak 'create_issue_note must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_issue_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to create_issue_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_issue_note must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/notes', [@_], $options );
}

=item edit_issue_note

    $api->edit_issue_note(
        $project_id,
        $issue_iid,
        $note_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/issues/:issue_iid/notes/:note_id>.

=cut

sub edit_issue_note {
    my $self = shift;
    croak 'edit_issue_note must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to edit_issue_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to edit_issue_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to edit_issue_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to edit_issue_note must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/issues/:issue_iid/notes/:note_id', [@_], $options );
    return;
}

=item delete_issue_note

    $api->delete_issue_note(
        $project_id,
        $issue_iid,
        $note_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/issues/:issue_iid/notes/:note_id>.

=cut

sub delete_issue_note {
    my $self = shift;
    croak 'delete_issue_note must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to delete_issue_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to delete_issue_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to delete_issue_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/issues/:issue_iid/notes/:note_id', [@_], $options );
    return;
}

=item snippet_notes

    my $notes = $api->snippet_notes(
        $project_id,
        $snippet_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/snippets/:snippet_id/notes> and returns the decoded response content.

=cut

sub snippet_notes {
    my $self = shift;
    croak 'snippet_notes must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to snippet_notes must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to snippet_notes must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to snippet_notes must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/snippets/:snippet_id/notes', [@_], $options );
}

=item snippet_note

    my $note = $api->snippet_note(
        $project_id,
        $snippet_id,
        $note_id,
    );

Sends a C<GET> request to C<projects/:project_id/snippets/:snippet_id/notes/:note_id> and returns the decoded response content.

=cut

sub snippet_note {
    my $self = shift;
    croak 'snippet_note must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to snippet_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to snippet_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to snippet_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/snippets/:snippet_id/notes/:note_id', [@_], $options );
}

=item create_snippet_note

    my $note = $api->create_snippet_note(
        $project_id,
        $snippet_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/snippets/:snippet_id/notes> and returns the decoded response content.

=cut

sub create_snippet_note {
    my $self = shift;
    croak 'create_snippet_note must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_snippet_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to create_snippet_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_snippet_note must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/snippets/:snippet_id/notes', [@_], $options );
}

=item edit_snippet_note

    $api->edit_snippet_note(
        $project_id,
        $snippet_id,
        $note_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/snippets/:snippet_id/notes/:note_id>.

=cut

sub edit_snippet_note {
    my $self = shift;
    croak 'edit_snippet_note must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to edit_snippet_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to edit_snippet_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to edit_snippet_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to edit_snippet_note must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/snippets/:snippet_id/notes/:note_id', [@_], $options );
    return;
}

=item delete_snippet_note

    $api->delete_snippet_note(
        $project_id,
        $snippet_id,
        $note_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/snippets/:snippet_id/notes/:note_id>.

=cut

sub delete_snippet_note {
    my $self = shift;
    croak 'delete_snippet_note must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to delete_snippet_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to delete_snippet_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to delete_snippet_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/snippets/:snippet_id/notes/:note_id', [@_], $options );
    return;
}

=item merge_request_notes

    my $notes = $api->merge_request_notes(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/notes> and returns the decoded response content.

=cut

sub merge_request_notes {
    my $self = shift;
    croak 'merge_request_notes must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to merge_request_notes must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_notes must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to merge_request_notes must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/notes', [@_], $options );
}

=item merge_request_note

    my $note = $api->merge_request_note(
        $project_id,
        $merge_request_iid,
        $note_id,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id> and returns the decoded response content.

=cut

sub merge_request_note {
    my $self = shift;
    croak 'merge_request_note must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to merge_request_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to merge_request_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id', [@_], $options );
}

=item create_merge_request_note

    my $note = $api->create_merge_request_note(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/notes> and returns the decoded response content.

=cut

sub create_merge_request_note {
    my $self = shift;
    croak 'create_merge_request_note must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_merge_request_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to create_merge_request_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_merge_request_note must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/notes', [@_], $options );
}

=item edit_merge_request_note

    $api->edit_merge_request_note(
        $project_id,
        $merge_request_iid,
        $note_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id>.

=cut

sub edit_merge_request_note {
    my $self = shift;
    croak 'edit_merge_request_note must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to edit_merge_request_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to edit_merge_request_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to edit_merge_request_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to edit_merge_request_note must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id', [@_], $options );
    return;
}

=item delete_merge_request_note

    $api->delete_merge_request_note(
        $project_id,
        $merge_request_iid,
        $note_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id>.

=cut

sub delete_merge_request_note {
    my $self = shift;
    croak 'delete_merge_request_note must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to delete_merge_request_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to delete_merge_request_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($note_id) to delete_merge_request_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/merge_requests/:merge_request_iid/notes/:note_id', [@_], $options );
    return;
}

=back

=head2 Discussions

See L<https://docs.gitlab.com/ce/api/discussions.html>.

=over

=item issue_discussions

    my $discussions = $api->issue_discussions(
        $project_id,
        $issue_iid,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/discussions> and returns the decoded response content.

=cut

sub issue_discussions {
    my $self = shift;
    croak 'issue_discussions must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to issue_discussions must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_discussions must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to issue_discussions must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/discussions', [@_], $options );
}

=item issue_discussion

    my $discussion = $api->issue_discussion(
        $project_id,
        $issue_iid,
        $discussion_id,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/discussions/:discussion_id> and returns the decoded response content.

=cut

sub issue_discussion {
    my $self = shift;
    croak 'issue_discussion must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to issue_discussion must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_discussion must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to issue_discussion must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/discussions/:discussion_id', [@_], $options );
}

=item create_issue_discussion

    my $discussion = $api->create_issue_discussion(
        $project_id,
        $issue_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/discussions> and returns the decoded response content.

=cut

sub create_issue_discussion {
    my $self = shift;
    croak 'create_issue_discussion must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_issue_discussion must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to create_issue_discussion must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_issue_discussion must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/discussions', [@_], $options );
}

=item create_issue_discussion_note

    $api->create_issue_discussion_note(
        $project_id,
        $issue_iid,
        $discussion_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/issues/:issue_iid/discussions/:discussion_id/notes>.

=cut

sub create_issue_discussion_note {
    my $self = shift;
    croak 'create_issue_discussion_note must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to create_issue_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to create_issue_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to create_issue_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to create_issue_discussion_note must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/:project_id/issues/:issue_iid/discussions/:discussion_id/notes', [@_], $options );
    return;
}

=item edit_issue_discussion_note

    $api->edit_issue_discussion_note(
        $project_id,
        $issue_iid,
        $discussion_id,
        $note_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/issues/:issue_iid/discussions/:discussion_id/notes/:note_id>.

=cut

sub edit_issue_discussion_note {
    my $self = shift;
    croak 'edit_issue_discussion_note must be called with 4 to 5 arguments' if @_ < 4 or @_ > 5;
    croak 'The #1 argument ($project_id) to edit_issue_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to edit_issue_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to edit_issue_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($note_id) to edit_issue_discussion_note must be a scalar' if ref($_[3]) or (!defined $_[3]);
    croak 'The last argument (\%params) to edit_issue_discussion_note must be a hash ref' if defined($_[4]) and ref($_[4]) ne 'HASH';
    my $params = (@_ == 5) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/issues/:issue_iid/discussions/:discussion_id/notes/:note_id', [@_], $options );
    return;
}

=item delete_issue_discussion_note

    $api->delete_issue_discussion_note(
        $project_id,
        $issue_iid,
        $discussion_id,
        $note_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/issues/:issue_iid/discussions/:discussion_id/notes/:note_id>.

=cut

sub delete_issue_discussion_note {
    my $self = shift;
    croak 'delete_issue_discussion_note must be called with 4 arguments' if @_ != 4;
    croak 'The #1 argument ($project_id) to delete_issue_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to delete_issue_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to delete_issue_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($note_id) to delete_issue_discussion_note must be a scalar' if ref($_[3]) or (!defined $_[3]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/issues/:issue_iid/discussions/:discussion_id/notes/:note_id', [@_], $options );
    return;
}

=item project_snippet_discussions

    my $discussions = $api->project_snippet_discussions(
        $project_id,
        $snippet_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/snippets/:snippet_id/discussions> and returns the decoded response content.

=cut

sub project_snippet_discussions {
    my $self = shift;
    croak 'project_snippet_discussions must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to project_snippet_discussions must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to project_snippet_discussions must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to project_snippet_discussions must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/snippets/:snippet_id/discussions', [@_], $options );
}

=item project_snippet_discussion

    my $discussion = $api->project_snippet_discussion(
        $project_id,
        $snippet_id,
        $discussion_id,
    );

Sends a C<GET> request to C<projects/:project_id/snippets/:snippet_id/discussions/:discussion_id> and returns the decoded response content.

=cut

sub project_snippet_discussion {
    my $self = shift;
    croak 'project_snippet_discussion must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to project_snippet_discussion must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to project_snippet_discussion must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to project_snippet_discussion must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/snippets/:snippet_id/discussions/:discussion_id', [@_], $options );
}

=item create_project_snippet_discussion

    my $discussion = $api->create_project_snippet_discussion(
        $project_id,
        $snippet_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/snippets/:snippet_id/discussions> and returns the decoded response content.

=cut

sub create_project_snippet_discussion {
    my $self = shift;
    croak 'create_project_snippet_discussion must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_project_snippet_discussion must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to create_project_snippet_discussion must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_project_snippet_discussion must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/snippets/:snippet_id/discussions', [@_], $options );
}

=item create_project_snippet_discussion_note

    $api->create_project_snippet_discussion_note(
        $project_id,
        $snippet_id,
        $discussion_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/snippets/:snippet_id/discussions/:discussion_id/notes>.

=cut

sub create_project_snippet_discussion_note {
    my $self = shift;
    croak 'create_project_snippet_discussion_note must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to create_project_snippet_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to create_project_snippet_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to create_project_snippet_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to create_project_snippet_discussion_note must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/:project_id/snippets/:snippet_id/discussions/:discussion_id/notes', [@_], $options );
    return;
}

=item edit_project_snippet_discussion_note

    $api->edit_project_snippet_discussion_note(
        $project_id,
        $snippet_id,
        $discussion_id,
        $note_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/snippets/:snippet_id/discussions/:discussion_id/notes/:note_id>.

=cut

sub edit_project_snippet_discussion_note {
    my $self = shift;
    croak 'edit_project_snippet_discussion_note must be called with 4 to 5 arguments' if @_ < 4 or @_ > 5;
    croak 'The #1 argument ($project_id) to edit_project_snippet_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to edit_project_snippet_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to edit_project_snippet_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($note_id) to edit_project_snippet_discussion_note must be a scalar' if ref($_[3]) or (!defined $_[3]);
    croak 'The last argument (\%params) to edit_project_snippet_discussion_note must be a hash ref' if defined($_[4]) and ref($_[4]) ne 'HASH';
    my $params = (@_ == 5) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/snippets/:snippet_id/discussions/:discussion_id/notes/:note_id', [@_], $options );
    return;
}

=item delete_project_snippet_discussion_note

    $api->delete_project_snippet_discussion_note(
        $project_id,
        $snippet_id,
        $discussion_id,
        $note_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/snippets/:snippet_id/discussions/:discussion_id/notes/:note_id>.

=cut

sub delete_project_snippet_discussion_note {
    my $self = shift;
    croak 'delete_project_snippet_discussion_note must be called with 4 arguments' if @_ != 4;
    croak 'The #1 argument ($project_id) to delete_project_snippet_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to delete_project_snippet_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to delete_project_snippet_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($note_id) to delete_project_snippet_discussion_note must be a scalar' if ref($_[3]) or (!defined $_[3]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/snippets/:snippet_id/discussions/:discussion_id/notes/:note_id', [@_], $options );
    return;
}

=item merge_request_discussions

    my $discussions = $api->merge_request_discussions(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/discussions> and returns the decoded response content.

=cut

sub merge_request_discussions {
    my $self = shift;
    croak 'merge_request_discussions must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to merge_request_discussions must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_discussions must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to merge_request_discussions must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/discussions', [@_], $options );
}

=item merge_request_discussion

    my $discussion = $api->merge_request_discussion(
        $project_id,
        $merge_request_iid,
        $discussion_id,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/discussions/:discussion_id> and returns the decoded response content.

=cut

sub merge_request_discussion {
    my $self = shift;
    croak 'merge_request_discussion must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to merge_request_discussion must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_discussion must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to merge_request_discussion must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/discussions/:discussion_id', [@_], $options );
}

=item create_merge_request_discussion

    my $discussion = $api->create_merge_request_discussion(
        $project_id,
        $merge_request_iid,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/discussions> and returns the decoded response content.

=cut

sub create_merge_request_discussion {
    my $self = shift;
    croak 'create_merge_request_discussion must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_merge_request_discussion must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to create_merge_request_discussion must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_merge_request_discussion must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/discussions', [@_], $options );
}

=item resolve_merge_request_discussion

    $api->resolve_merge_request_discussion(
        $project_id,
        $merge_request_iid,
        $discussion_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/merge_requests/:merge_request_iid/discussions/:discussion_id>.

=cut

sub resolve_merge_request_discussion {
    my $self = shift;
    croak 'resolve_merge_request_discussion must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to resolve_merge_request_discussion must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to resolve_merge_request_discussion must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to resolve_merge_request_discussion must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to resolve_merge_request_discussion must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/merge_requests/:merge_request_iid/discussions/:discussion_id', [@_], $options );
    return;
}

=item create_merge_request_discussion_note

    $api->create_merge_request_discussion_note(
        $project_id,
        $merge_request_iid,
        $discussion_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/merge_requests/:merge_request_iid/discussions/:discussion_id/notes>.

=cut

sub create_merge_request_discussion_note {
    my $self = shift;
    croak 'create_merge_request_discussion_note must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to create_merge_request_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to create_merge_request_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to create_merge_request_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to create_merge_request_discussion_note must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/:project_id/merge_requests/:merge_request_iid/discussions/:discussion_id/notes', [@_], $options );
    return;
}

=item edit_merge_request_discussion_note

    $api->edit_merge_request_discussion_note(
        $project_id,
        $merge_request_iid,
        $discussion_id,
        $note_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/merge_requests/:merge_request_iid/discussions/:discussion_id/notes/:note_id>.

=cut

sub edit_merge_request_discussion_note {
    my $self = shift;
    croak 'edit_merge_request_discussion_note must be called with 4 to 5 arguments' if @_ < 4 or @_ > 5;
    croak 'The #1 argument ($project_id) to edit_merge_request_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to edit_merge_request_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to edit_merge_request_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($note_id) to edit_merge_request_discussion_note must be a scalar' if ref($_[3]) or (!defined $_[3]);
    croak 'The last argument (\%params) to edit_merge_request_discussion_note must be a hash ref' if defined($_[4]) and ref($_[4]) ne 'HASH';
    my $params = (@_ == 5) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/merge_requests/:merge_request_iid/discussions/:discussion_id/notes/:note_id', [@_], $options );
    return;
}

=item delete_merge_request_discussion_note

    $api->delete_merge_request_discussion_note(
        $project_id,
        $merge_request_iid,
        $discussion_id,
        $note_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/merge_requests/:merge_request_iid/discussions/:discussion_id/notes/:note_id>.

=cut

sub delete_merge_request_discussion_note {
    my $self = shift;
    croak 'delete_merge_request_discussion_note must be called with 4 arguments' if @_ != 4;
    croak 'The #1 argument ($project_id) to delete_merge_request_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to delete_merge_request_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to delete_merge_request_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($note_id) to delete_merge_request_discussion_note must be a scalar' if ref($_[3]) or (!defined $_[3]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/merge_requests/:merge_request_iid/discussions/:discussion_id/notes/:note_id', [@_], $options );
    return;
}

=item commit_discussions

    my $discussions = $api->commit_discussions(
        $project_id,
        $commit_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/commits/:commit_id/discussions> and returns the decoded response content.

=cut

sub commit_discussions {
    my $self = shift;
    croak 'commit_discussions must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to commit_discussions must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_id) to commit_discussions must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to commit_discussions must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/commits/:commit_id/discussions', [@_], $options );
}

=item commit_discussion

    my $discussion = $api->commit_discussion(
        $project_id,
        $commit_id,
        $discussion_id,
    );

Sends a C<GET> request to C<projects/:project_id/commits/:commit_id/discussions/:discussion_id> and returns the decoded response content.

=cut

sub commit_discussion {
    my $self = shift;
    croak 'commit_discussion must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to commit_discussion must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_id) to commit_discussion must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to commit_discussion must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/commits/:commit_id/discussions/:discussion_id', [@_], $options );
}

=item create_commit_discussion

    my $discussion = $api->create_commit_discussion(
        $project_id,
        $commit_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/commits/:commit_id/discussions> and returns the decoded response content.

=cut

sub create_commit_discussion {
    my $self = shift;
    croak 'create_commit_discussion must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_commit_discussion must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_id) to create_commit_discussion must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_commit_discussion must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/commits/:commit_id/discussions', [@_], $options );
}

=item create_commit_discussion_note

    $api->create_commit_discussion_note(
        $project_id,
        $commit_id,
        $discussion_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/commits/:commit_id/discussions/:discussion_id/notes>.

=cut

sub create_commit_discussion_note {
    my $self = shift;
    croak 'create_commit_discussion_note must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to create_commit_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_id) to create_commit_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to create_commit_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to create_commit_discussion_note must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/:project_id/commits/:commit_id/discussions/:discussion_id/notes', [@_], $options );
    return;
}

=item edit_commit_discussion_note

    $api->edit_commit_discussion_note(
        $project_id,
        $commit_id,
        $discussion_id,
        $note_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/commits/:commit_id/discussions/:discussion_id/notes/:note_id>.

=cut

sub edit_commit_discussion_note {
    my $self = shift;
    croak 'edit_commit_discussion_note must be called with 4 to 5 arguments' if @_ < 4 or @_ > 5;
    croak 'The #1 argument ($project_id) to edit_commit_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_id) to edit_commit_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to edit_commit_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($note_id) to edit_commit_discussion_note must be a scalar' if ref($_[3]) or (!defined $_[3]);
    croak 'The last argument (\%params) to edit_commit_discussion_note must be a hash ref' if defined($_[4]) and ref($_[4]) ne 'HASH';
    my $params = (@_ == 5) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/commits/:commit_id/discussions/:discussion_id/notes/:note_id', [@_], $options );
    return;
}

=item delete_commit_discussion_note

    $api->delete_commit_discussion_note(
        $project_id,
        $commit_id,
        $discussion_id,
        $note_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/commits/:commit_id/discussions/:discussion_id/notes/:note_id>.

=cut

sub delete_commit_discussion_note {
    my $self = shift;
    croak 'delete_commit_discussion_note must be called with 4 arguments' if @_ != 4;
    croak 'The #1 argument ($project_id) to delete_commit_discussion_note must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($commit_id) to delete_commit_discussion_note must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($discussion_id) to delete_commit_discussion_note must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The #4 argument ($note_id) to delete_commit_discussion_note must be a scalar' if ref($_[3]) or (!defined $_[3]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/commits/:commit_id/discussions/:discussion_id/notes/:note_id', [@_], $options );
    return;
}

=back

=head2 Resource label events

See L<https://docs.gitlab.com/ce/api/resource_label_events.html>.

=over

=item issue_resource_label_events

    my $events = $api->issue_resource_label_events(
        $project_id,
        $issue_iid,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/resource_label_events> and returns the decoded response content.

=cut

sub issue_resource_label_events {
    my $self = shift;
    croak 'issue_resource_label_events must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to issue_resource_label_events must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_resource_label_events must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/resource_label_events', [@_], $options );
}

=item issue_resource_label_event

    my $event = $api->issue_resource_label_event(
        $project_id,
        $issue_iid,
        $resource_label_event_id,
    );

Sends a C<GET> request to C<projects/:project_id/issues/:issue_iid/resource_label_events/:resource_label_event_id> and returns the decoded response content.

=cut

sub issue_resource_label_event {
    my $self = shift;
    croak 'issue_resource_label_event must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to issue_resource_label_event must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($issue_iid) to issue_resource_label_event must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($resource_label_event_id) to issue_resource_label_event must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/issues/:issue_iid/resource_label_events/:resource_label_event_id', [@_], $options );
}

=item merge_request_resource_label_events

    my $events = $api->merge_request_resource_label_events(
        $project_id,
        $merge_request_iid,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/resource_label_events> and returns the decoded response content.

=cut

sub merge_request_resource_label_events {
    my $self = shift;
    croak 'merge_request_resource_label_events must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to merge_request_resource_label_events must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_resource_label_events must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/resource_label_events', [@_], $options );
}

=item merge_request_resource_label_event

    my $event = $api->merge_request_resource_label_event(
        $project_id,
        $merge_request_iid,
        $resource_label_event_id,
    );

Sends a C<GET> request to C<projects/:project_id/merge_requests/:merge_request_iid/resource_label_events/:resource_label_event_id> and returns the decoded response content.

=cut

sub merge_request_resource_label_event {
    my $self = shift;
    croak 'merge_request_resource_label_event must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to merge_request_resource_label_event must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($merge_request_iid) to merge_request_resource_label_event must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($resource_label_event_id) to merge_request_resource_label_event must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/merge_requests/:merge_request_iid/resource_label_events/:resource_label_event_id', [@_], $options );
}

=back

=head2 Notification settings

See L<https://docs.gitlab.com/ce/api/notification_settings.html>.

=over

=item global_notification_settings

    my $settings = $api->global_notification_settings();

Sends a C<GET> request to C<notification_settings> and returns the decoded response content.

=cut

sub global_notification_settings {
    my $self = shift;
    croak "The global_notification_settings method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'notification_settings', [@_], $options );
}

=item set_global_notification_settings

    my $settings = $api->set_global_notification_settings(
        \%params,
    );

Sends a C<PUT> request to C<notification_settings> and returns the decoded response content.

=cut

sub set_global_notification_settings {
    my $self = shift;
    croak 'set_global_notification_settings must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to set_global_notification_settings must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'notification_settings', [@_], $options );
}

=item group_notification_settings

    my $settings = $api->group_notification_settings(
        $group_id,
    );

Sends a C<GET> request to C<groups/:group_id/notification_settings> and returns the decoded response content.

=cut

sub group_notification_settings {
    my $self = shift;
    croak 'group_notification_settings must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($group_id) to group_notification_settings must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'groups/:group_id/notification_settings', [@_], $options );
}

=item project_notification_settings

    my $settings = $api->project_notification_settings(
        $project_id,
    );

Sends a C<GET> request to C<projects/:project_id/notification_settings> and returns the decoded response content.

=cut

sub project_notification_settings {
    my $self = shift;
    croak 'project_notification_settings must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to project_notification_settings must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/notification_settings', [@_], $options );
}

=item set_group_notification_settings

    my $settings = $api->set_group_notification_settings(
        $group_id,
        \%params,
    );

Sends a C<PUT> request to C<groups/:group_id/notification_settings> and returns the decoded response content.

=cut

sub set_group_notification_settings {
    my $self = shift;
    croak 'set_group_notification_settings must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($group_id) to set_group_notification_settings must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to set_group_notification_settings must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'groups/:group_id/notification_settings', [@_], $options );
}

=item set_project_notification_settings

    my $settings = $api->set_project_notification_settings(
        $project_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/notification_settings> and returns the decoded response content.

=cut

sub set_project_notification_settings {
    my $self = shift;
    croak 'set_project_notification_settings must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to set_project_notification_settings must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to set_project_notification_settings must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/notification_settings', [@_], $options );
}

=back

=head2 Licenses

See L<https://docs.gitlab.com/ce/api/templates/licenses.html>.

=over

=item license_templates

    my $templates = $api->license_templates(
        \%params,
    );

Sends a C<GET> request to C<templates/licenses> and returns the decoded response content.

=cut

sub license_templates {
    my $self = shift;
    croak 'license_templates must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to license_templates must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'templates/licenses', [@_], $options );
}

=item license_template

    my $template = $api->license_template(
        $template_key,
        \%params,
    );

Sends a C<GET> request to C<templates/licenses/:template_key> and returns the decoded response content.

=cut

sub license_template {
    my $self = shift;
    croak 'license_template must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($template_key) to license_template must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to license_template must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'templates/licenses/:template_key', [@_], $options );
}

=back

=head2 Pages domains

See L<https://docs.gitlab.com/ce/api/pages_domains.html>.

=over

=item global_pages_domains

    my $domains = $api->global_pages_domains(
        \%params,
    );

Sends a C<GET> request to C<pages/domains> and returns the decoded response content.

=cut

sub global_pages_domains {
    my $self = shift;
    croak 'global_pages_domains must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to global_pages_domains must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'pages/domains', [@_], $options );
}

=item pages_domains

    my $domains = $api->pages_domains(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/pages/domains> and returns the decoded response content.

=cut

sub pages_domains {
    my $self = shift;
    croak 'pages_domains must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to pages_domains must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to pages_domains must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/pages/domains', [@_], $options );
}

=item pages_domain

    my $domain = $api->pages_domain(
        $project_id,
        $domain,
    );

Sends a C<GET> request to C<projects/:project_id/pages/domains/:domain> and returns the decoded response content.

=cut

sub pages_domain {
    my $self = shift;
    croak 'pages_domain must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to pages_domain must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($domain) to pages_domain must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/pages/domains/:domain', [@_], $options );
}

=item create_pages_domain

    my $domain = $api->create_pages_domain(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/pages/domains> and returns the decoded response content.

=cut

sub create_pages_domain {
    my $self = shift;
    croak 'create_pages_domain must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_pages_domain must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_pages_domain must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/pages/domains', [@_], $options );
}

=item edit_pages_domain

    my $domain = $api->edit_pages_domain(
        $project_id,
        $domain,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/pages/domains/:domain> and returns the decoded response content.

=cut

sub edit_pages_domain {
    my $self = shift;
    croak 'edit_pages_domain must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_pages_domain must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($domain) to edit_pages_domain must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_pages_domain must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/pages/domains/:domain', [@_], $options );
}

=item delete_pages_domain

    $api->delete_pages_domain(
        $project_id,
        $domain,
    );

Sends a C<DELETE> request to C<projects/:project_id/pages/domains/:domain>.

=cut

sub delete_pages_domain {
    my $self = shift;
    croak 'delete_pages_domain must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_pages_domain must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($domain) to delete_pages_domain must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/pages/domains/:domain', [@_], $options );
    return;
}

=back

=head2 Pipelines

See L<https://docs.gitlab.com/ce/api/pipelines.html>.

=over

=item pipelines

    my $pipelines = $api->pipelines(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/pipelines> and returns the decoded response content.

=cut

sub pipelines {
    my $self = shift;
    croak 'pipelines must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to pipelines must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to pipelines must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/pipelines', [@_], $options );
}

=item pipeline

    my $pipeline = $api->pipeline(
        $project_id,
        $pipeline_id,
    );

Sends a C<GET> request to C<projects/:project_id/pipelines/:pipeline_id> and returns the decoded response content.

=cut

sub pipeline {
    my $self = shift;
    croak 'pipeline must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to pipeline must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_id) to pipeline must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/pipelines/:pipeline_id', [@_], $options );
}

=item create_pipeline

    my $pipeline = $api->create_pipeline(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/pipeline> and returns the decoded response content.

Git ref (branch or tag) name must be specified in the C<ref> field of the
C<%params> hash. It's also possible to pass variables to a pipeline in
the C<variables> field like in the following example:

    my $pipeline = $api->create_pipeline(
        $project_id,
        {
            'ref'     => 'master',
            variables => [
                { 'key' => 'VARIABLE1', 'value' => 'VALUE1' },
                { 'key' => 'VARIABLE2', 'value' => 'VALUE2' },
            ],
        },
    );

=cut

sub create_pipeline {
    my $self = shift;
    croak 'create_pipeline must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_pipeline must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_pipeline must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/pipeline', [@_], $options );
}

=item retry_pipeline_jobs

    my $pipeline = $api->retry_pipeline_jobs(
        $project_id,
        $pipeline_id,
    );

Sends a C<POST> request to C<projects/:project_id/pipelines/:pipeline_id/retry> and returns the decoded response content.

=cut

sub retry_pipeline_jobs {
    my $self = shift;
    croak 'retry_pipeline_jobs must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to retry_pipeline_jobs must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_id) to retry_pipeline_jobs must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/pipelines/:pipeline_id/retry', [@_], $options );
}

=item cancel_pipeline_jobs

    my $pipeline = $api->cancel_pipeline_jobs(
        $project_id,
        $pipeline_id,
    );

Sends a C<POST> request to C<projects/:project_id/pipelines/:pipeline_id/cancel> and returns the decoded response content.

=cut

sub cancel_pipeline_jobs {
    my $self = shift;
    croak 'cancel_pipeline_jobs must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to cancel_pipeline_jobs must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_id) to cancel_pipeline_jobs must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/pipelines/:pipeline_id/cancel', [@_], $options );
}

=item delete_pipeline

    $api->delete_pipeline(
        $project_id,
        $pipeline_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/pipelines/:pipeline_id>.

=cut

sub delete_pipeline {
    my $self = shift;
    croak 'delete_pipeline must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_pipeline must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_id) to delete_pipeline must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/pipelines/:pipeline_id', [@_], $options );
    return;
}

=back

=head2 Pipeline triggers

See L<https://docs.gitlab.com/ce/api/pipeline_triggers.html>.

=over

=item triggers

    my $triggers = $api->triggers(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/triggers> and returns the decoded response content.

=cut

sub triggers {
    my $self = shift;
    croak 'triggers must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to triggers must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to triggers must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/triggers', [@_], $options );
}

=item trigger

    my $trigger = $api->trigger(
        $project_id,
        $trigger_id,
    );

Sends a C<GET> request to C<projects/:project_id/triggers/:trigger_id> and returns the decoded response content.

=cut

sub trigger {
    my $self = shift;
    croak 'trigger must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to trigger must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($trigger_id) to trigger must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/triggers/:trigger_id', [@_], $options );
}

=item create_trigger

    my $trigger = $api->create_trigger(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/triggers> and returns the decoded response content.

=cut

sub create_trigger {
    my $self = shift;
    croak 'create_trigger must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_trigger must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_trigger must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/triggers', [@_], $options );
}

=item edit_trigger

    my $trigger = $api->edit_trigger(
        $project_id,
        $trigger_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/triggers/:trigger_id> and returns the decoded response content.

=cut

sub edit_trigger {
    my $self = shift;
    croak 'edit_trigger must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_trigger must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($trigger_id) to edit_trigger must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_trigger must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/triggers/:trigger_id', [@_], $options );
}

=item take_ownership_of_trigger

    my $trigger = $api->take_ownership_of_trigger(
        $project_id,
        $trigger_id,
    );

Sends a C<POST> request to C<projects/:project_id/triggers/:trigger_id/take_ownership> and returns the decoded response content.

=cut

sub take_ownership_of_trigger {
    my $self = shift;
    croak 'take_ownership_of_trigger must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to take_ownership_of_trigger must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($trigger_id) to take_ownership_of_trigger must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/triggers/:trigger_id/take_ownership', [@_], $options );
}

=item delete_trigger

    $api->delete_trigger(
        $project_id,
        $trigger_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/triggers/:trigger_id>.

=cut

sub delete_trigger {
    my $self = shift;
    croak 'delete_trigger must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_trigger must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($trigger_id) to delete_trigger must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/triggers/:trigger_id', [@_], $options );
    return;
}

=item trigger_pipeline

    my $pipeline = $api->trigger_pipeline(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/trigger/pipeline> and returns the decoded response content.

The API authentication token (L</private_token> or L</access_token>
parameters in a constructor) is not needed when using this method, however
You must pass trigger token (generated at the trigger creation) as C<token>
field and git ref name as C<ref> field in the C<%params> hash. You can also
pass variables to be set in a pipeline in the C<variables> field. Example:

    my $pipeline = $api->trigger_pipeline(
        $project_id,
        {
            token => 'd69dba9162ab6ac72fa0993496286ada',
            'ref' => 'master',
            variables => {
                variable1 => 'value1',
                variable2 => 'value2',
            },
        },
    );

Read more at L<https://docs.gitlab.com/ce/ci/triggers/#triggering-a-pipeline>.

=cut

sub trigger_pipeline {
    my $self = shift;
    croak 'trigger_pipeline must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to trigger_pipeline must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to trigger_pipeline must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/trigger/pipeline', [@_], $options );
}

=back

=head2 Pipeline schedules

See L<https://docs.gitlab.com/ce/api/pipeline_schedules.html>.

=over

=item pipeline_schedules

    my $schedules = $api->pipeline_schedules(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/pipeline_schedules> and returns the decoded response content.

=cut

sub pipeline_schedules {
    my $self = shift;
    croak 'pipeline_schedules must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to pipeline_schedules must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to pipeline_schedules must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/pipeline_schedules', [@_], $options );
}

=item pipeline_schedule

    my $schedule = $api->pipeline_schedule(
        $project_id,
        $pipeline_schedule_id,
    );

Sends a C<GET> request to C<projects/:project_id/pipeline_schedules/:pipeline_schedule_id> and returns the decoded response content.

=cut

sub pipeline_schedule {
    my $self = shift;
    croak 'pipeline_schedule must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to pipeline_schedule must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_schedule_id) to pipeline_schedule must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/pipeline_schedules/:pipeline_schedule_id', [@_], $options );
}

=item create_pipeline_schedule

    my $schedule = $api->create_pipeline_schedule(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/pipeline_schedules> and returns the decoded response content.

=cut

sub create_pipeline_schedule {
    my $self = shift;
    croak 'create_pipeline_schedule must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_pipeline_schedule must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_pipeline_schedule must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/pipeline_schedules', [@_], $options );
}

=item edit_pipeline_schedule

    my $schedule = $api->edit_pipeline_schedule(
        $project_id,
        $pipeline_schedule_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/pipeline_schedules/:pipeline_schedule_id> and returns the decoded response content.

=cut

sub edit_pipeline_schedule {
    my $self = shift;
    croak 'edit_pipeline_schedule must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_pipeline_schedule must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_schedule_id) to edit_pipeline_schedule must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_pipeline_schedule must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/pipeline_schedules/:pipeline_schedule_id', [@_], $options );
}

=item take_ownership_of_pipeline_schedule

    my $schedule = $api->take_ownership_of_pipeline_schedule(
        $project_id,
        $pipeline_schedule_id,
    );

Sends a C<POST> request to C<projects/:project_id/pipeline_schedules/:pipeline_schedule_id/take_ownership> and returns the decoded response content.

=cut

sub take_ownership_of_pipeline_schedule {
    my $self = shift;
    croak 'take_ownership_of_pipeline_schedule must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to take_ownership_of_pipeline_schedule must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_schedule_id) to take_ownership_of_pipeline_schedule must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/pipeline_schedules/:pipeline_schedule_id/take_ownership', [@_], $options );
}

=item delete_pipeline_schedule

    my $schedule = $api->delete_pipeline_schedule(
        $project_id,
        $pipeline_schedule_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/pipeline_schedules/:pipeline_schedule_id> and returns the decoded response content.

=cut

sub delete_pipeline_schedule {
    my $self = shift;
    croak 'delete_pipeline_schedule must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_pipeline_schedule must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_schedule_id) to delete_pipeline_schedule must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'DELETE', 'projects/:project_id/pipeline_schedules/:pipeline_schedule_id', [@_], $options );
}

=item create_pipeline_schedule_variable

    my $variable = $api->create_pipeline_schedule_variable(
        $project_id,
        $pipeline_schedule_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/pipeline_schedules/:pipeline_schedule_id/variables> and returns the decoded response content.

=cut

sub create_pipeline_schedule_variable {
    my $self = shift;
    croak 'create_pipeline_schedule_variable must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_pipeline_schedule_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_schedule_id) to create_pipeline_schedule_variable must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_pipeline_schedule_variable must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/pipeline_schedules/:pipeline_schedule_id/variables', [@_], $options );
}

=item edit_pipeline_schedule_variable

    my $variable = $api->edit_pipeline_schedule_variable(
        $project_id,
        $pipeline_schedule_id,
        $variable_key,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/pipeline_schedules/:pipeline_schedule_id/variables/:variable_key> and returns the decoded response content.

=cut

sub edit_pipeline_schedule_variable {
    my $self = shift;
    croak 'edit_pipeline_schedule_variable must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to edit_pipeline_schedule_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_schedule_id) to edit_pipeline_schedule_variable must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($variable_key) to edit_pipeline_schedule_variable must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to edit_pipeline_schedule_variable must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/pipeline_schedules/:pipeline_schedule_id/variables/:variable_key', [@_], $options );
}

=item delete_pipeline_schedule_variable

    my $variable = $api->delete_pipeline_schedule_variable(
        $project_id,
        $pipeline_schedule_id,
        $variable_key,
    );

Sends a C<DELETE> request to C<projects/:project_id/pipeline_schedules/:pipeline_schedule_id/variables/:variable_key> and returns the decoded response content.

=cut

sub delete_pipeline_schedule_variable {
    my $self = shift;
    croak 'delete_pipeline_schedule_variable must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to delete_pipeline_schedule_variable must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($pipeline_schedule_id) to delete_pipeline_schedule_variable must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($variable_key) to delete_pipeline_schedule_variable must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'DELETE', 'projects/:project_id/pipeline_schedules/:pipeline_schedule_id/variables/:variable_key', [@_], $options );
}

=back

=head2 Projects

See L<https://docs.gitlab.com/ce/api/projects.html>.

=over

=item projects

    my $projects = $api->projects(
        \%params,
    );

Sends a C<GET> request to C<projects> and returns the decoded response content.

=cut

sub projects {
    my $self = shift;
    croak 'projects must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to projects must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects', [@_], $options );
}

=item user_projects

    my $projects = $api->user_projects(
        $user_id,
        \%params,
    );

Sends a C<GET> request to C<users/:user_id/projects> and returns the decoded response content.

=cut

sub user_projects {
    my $self = shift;
    croak 'user_projects must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to user_projects must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to user_projects must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'users/:user_id/projects', [@_], $options );
}

=item project

    my $project = $api->project(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id> and returns the decoded response content.

=cut

sub project {
    my $self = shift;
    croak 'project must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id', [@_], $options );
}

=item project_users

    my $users = $api->project_users(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/users> and returns the decoded response content.

=cut

sub project_users {
    my $self = shift;
    croak 'project_users must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_users must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_users must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/users', [@_], $options );
}

=item create_project

    my $project = $api->create_project(
        \%params,
    );

Sends a C<POST> request to C<projects> and returns the decoded response content.

=cut

sub create_project {
    my $self = shift;
    croak 'create_project must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_project must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects', [@_], $options );
}

=item create_project_for_user

    $api->create_project_for_user(
        $user_id,
        \%params,
    );

Sends a C<POST> request to C<projects/user/:user_id>.

=cut

sub create_project_for_user {
    my $self = shift;
    croak 'create_project_for_user must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to create_project_for_user must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_project_for_user must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/user/:user_id', [@_], $options );
    return;
}

=item edit_project

    $api->edit_project(
        $project_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id>.

=cut

sub edit_project {
    my $self = shift;
    croak 'edit_project must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to edit_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to edit_project must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id', [@_], $options );
    return;
}

=item fork_project

    $api->fork_project(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/fork>.

=cut

sub fork_project {
    my $self = shift;
    croak 'fork_project must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to fork_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to fork_project must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/:project_id/fork', [@_], $options );
    return;
}

=item project_forks

    my $forks = $api->project_forks(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/forks> and returns the decoded response content.

=cut

sub project_forks {
    my $self = shift;
    croak 'project_forks must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_forks must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_forks must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/forks', [@_], $options );
}

=item start_project

    my $project = $api->start_project(
        $project_id,
    );

Sends a C<POST> request to C<projects/:project_id/star> and returns the decoded response content.

=cut

sub start_project {
    my $self = shift;
    croak 'start_project must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to start_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/star', [@_], $options );
}

=item unstar_project

    my $project = $api->unstar_project(
        $project_id,
    );

Sends a C<POST> request to C<projects/:project_id/unstar> and returns the decoded response content.

=cut

sub unstar_project {
    my $self = shift;
    croak 'unstar_project must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to unstar_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/unstar', [@_], $options );
}

=item project_languages

    my $languages = $api->project_languages(
        $project_id,
    );

Sends a C<GET> request to C<projects/:project_id/languages> and returns the decoded response content.

=cut

sub project_languages {
    my $self = shift;
    croak 'project_languages must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to project_languages must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/languages', [@_], $options );
}

=item archive_project

    my $project = $api->archive_project(
        $project_id,
    );

Sends a C<POST> request to C<projects/:project_id/archive> and returns the decoded response content.

=cut

sub archive_project {
    my $self = shift;
    croak 'archive_project must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to archive_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/archive', [@_], $options );
}

=item unarchive_project

    my $project = $api->unarchive_project(
        $project_id,
    );

Sends a C<POST> request to C<projects/:project_id/unarchive> and returns the decoded response content.

=cut

sub unarchive_project {
    my $self = shift;
    croak 'unarchive_project must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to unarchive_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/unarchive', [@_], $options );
}

=item delete_project

    $api->delete_project(
        $project_id,
    );

Sends a C<DELETE> request to C<projects/:project_id>.

=cut

sub delete_project {
    my $self = shift;
    croak 'delete_project must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to delete_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id', [@_], $options );
    return;
}

=item upload_file_to_project

    my $upload = $api->upload_file_to_project(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/uploads> and returns the decoded response content.

The C<file> parameter must point to a readable file on the local filesystem.
=cut

sub upload_file_to_project {
    my $self = shift;
    croak 'upload_file_to_project must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to upload_file_to_project must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to upload_file_to_project must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/uploads', [@_], $options );
}

=item share_project_with_group

    $api->share_project_with_group(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/share>.

=cut

sub share_project_with_group {
    my $self = shift;
    croak 'share_project_with_group must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to share_project_with_group must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to share_project_with_group must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/:project_id/share', [@_], $options );
    return;
}

=item unshare_project_with_group

    $api->unshare_project_with_group(
        $project_id,
        $group_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/share/:group_id>.

=cut

sub unshare_project_with_group {
    my $self = shift;
    croak 'unshare_project_with_group must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to unshare_project_with_group must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($group_id) to unshare_project_with_group must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/share/:group_id', [@_], $options );
    return;
}

=item project_hooks

    my $hooks = $api->project_hooks(
        $project_id,
    );

Sends a C<GET> request to C<projects/:project_id/hooks> and returns the decoded response content.

=cut

sub project_hooks {
    my $self = shift;
    croak 'project_hooks must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to project_hooks must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/hooks', [@_], $options );
}

=item project_hook

    my $hook = $api->project_hook(
        $project_id,
        $hook_id,
    );

Sends a C<GET> request to C<projects/:project_id/hooks/:hook_id> and returns the decoded response content.

=cut

sub project_hook {
    my $self = shift;
    croak 'project_hook must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($hook_id) to project_hook must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/hooks/:hook_id', [@_], $options );
}

=item create_project_hook

    my $hook = $api->create_project_hook(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/hooks> and returns the decoded response content.

=cut

sub create_project_hook {
    my $self = shift;
    croak 'create_project_hook must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_project_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_project_hook must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/hooks', [@_], $options );
}

=item edit_project_hook

    my $hook = $api->edit_project_hook(
        $project_id,
        $hook_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/hooks/:hook_id> and returns the decoded response content.

=cut

sub edit_project_hook {
    my $self = shift;
    croak 'edit_project_hook must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_project_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($hook_id) to edit_project_hook must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_project_hook must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/hooks/:hook_id', [@_], $options );
}

=item delete_project_hook

    $api->delete_project_hook(
        $project_id,
        $hook_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/hooks/:hook_id>.

=cut

sub delete_project_hook {
    my $self = shift;
    croak 'delete_project_hook must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_project_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($hook_id) to delete_project_hook must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/hooks/:hook_id', [@_], $options );
    return;
}

=item set_project_fork

    $api->set_project_fork(
        $project_id,
        $from_project_id,
    );

Sends a C<POST> request to C<projects/:project_id/fork/:from_project_id>.

=cut

sub set_project_fork {
    my $self = shift;
    croak 'set_project_fork must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to set_project_fork must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($from_project_id) to set_project_fork must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'POST', 'projects/:project_id/fork/:from_project_id', [@_], $options );
    return;
}

=item clear_project_fork

    $api->clear_project_fork(
        $project_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/fork>.

=cut

sub clear_project_fork {
    my $self = shift;
    croak 'clear_project_fork must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to clear_project_fork must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/fork', [@_], $options );
    return;
}

=item start_housekeeping

    $api->start_housekeeping(
        $project_id,
    );

Sends a C<POST> request to C<projects/:project_id/housekeeping>.

=cut

sub start_housekeeping {
    my $self = shift;
    croak 'start_housekeeping must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to start_housekeeping must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'POST', 'projects/:project_id/housekeeping', [@_], $options );
    return;
}

=item transfer_project_to_namespace

    $api->transfer_project_to_namespace(
        $project_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/transfer>.

=cut

sub transfer_project_to_namespace {
    my $self = shift;
    croak 'transfer_project_to_namespace must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to transfer_project_to_namespace must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to transfer_project_to_namespace must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/transfer', [@_], $options );
    return;
}

=back

=head2 Project access requests

See L<https://docs.gitlab.com/ce/api/access_requests.html>.

=over

=item project_access_requests

    my $requests = $api->project_access_requests(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/access_requests> and returns the decoded response content.

=cut

sub project_access_requests {
    my $self = shift;
    croak 'project_access_requests must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_access_requests must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_access_requests must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/access_requests', [@_], $options );
}

=item request_project_access

    my $request = $api->request_project_access(
        $project_id,
    );

Sends a C<POST> request to C<projects/:project_id/access_requests> and returns the decoded response content.

=cut

sub request_project_access {
    my $self = shift;
    croak 'request_project_access must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to request_project_access must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'projects/:project_id/access_requests', [@_], $options );
}

=item approve_project_access

    my $request = $api->approve_project_access(
        $project_id,
        $user_id,
    );

Sends a C<PUT> request to C<projects/:project_id/access_requests/:user_id/approve> and returns the decoded response content.

=cut

sub approve_project_access {
    my $self = shift;
    croak 'approve_project_access must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to approve_project_access must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to approve_project_access must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/access_requests/:user_id/approve', [@_], $options );
}

=item deny_project_access

    $api->deny_project_access(
        $project_id,
        $user_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/access_requests/:user_id>.

=cut

sub deny_project_access {
    my $self = shift;
    croak 'deny_project_access must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to deny_project_access must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to deny_project_access must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/access_requests/:user_id', [@_], $options );
    return;
}

=back

=head2 Project badges

See L<https://docs.gitlab.com/ce/api/project_badges.html>.

=over

=item project_badges

    my $badges = $api->project_badges(
        $project_id,
    );

Sends a C<GET> request to C<projects/:project_id/badges> and returns the decoded response content.

=cut

sub project_badges {
    my $self = shift;
    croak 'project_badges must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to project_badges must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/badges', [@_], $options );
}

=item project_badge

    my $badge = $api->project_badge(
        $project_id,
        $badge_id,
    );

Sends a C<GET> request to C<projects/:project_id/badges/:badge_id> and returns the decoded response content.

=cut

sub project_badge {
    my $self = shift;
    croak 'project_badge must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_badge must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($badge_id) to project_badge must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/badges/:badge_id', [@_], $options );
}

=item create_project_badge

    my $badge = $api->create_project_badge(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/badges> and returns the decoded response content.

=cut

sub create_project_badge {
    my $self = shift;
    croak 'create_project_badge must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_project_badge must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_project_badge must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/badges', [@_], $options );
}

=item edit_project_badge

    my $badge = $api->edit_project_badge(
        $project_id,
        $badge_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/badges/:badge_id> and returns the decoded response content.

=cut

sub edit_project_badge {
    my $self = shift;
    croak 'edit_project_badge must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_project_badge must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($badge_id) to edit_project_badge must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_project_badge must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/badges/:badge_id', [@_], $options );
}

=item delete_project_badge

    $api->delete_project_badge(
        $project_id,
        $badge_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/badges/:badge_id>.

=cut

sub delete_project_badge {
    my $self = shift;
    croak 'delete_project_badge must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_project_badge must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($badge_id) to delete_project_badge must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/badges/:badge_id', [@_], $options );
    return;
}

=item preview_project_badge

    my $preview = $api->preview_project_badge(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/badges/render> and returns the decoded response content.

=cut

sub preview_project_badge {
    my $self = shift;
    croak 'preview_project_badge must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to preview_project_badge must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to preview_project_badge must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/badges/render', [@_], $options );
}

=back

=head2 Project import/export

See L<https://docs.gitlab.com/ce/api/project_import_export.html>.

=over

=item schedule_project_export

    $api->schedule_project_export(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/export>.

=cut

sub schedule_project_export {
    my $self = shift;
    croak 'schedule_project_export must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to schedule_project_export must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to schedule_project_export must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/:project_id/export', [@_], $options );
    return;
}

=item project_export_status

    my $status = $api->project_export_status(
        $project_id,
    );

Sends a C<GET> request to C<projects/:project_id/export> and returns the decoded response content.

=cut

sub project_export_status {
    my $self = shift;
    croak 'project_export_status must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to project_export_status must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/export', [@_], $options );
}

=item download_project_export

    my $download = $api->download_project_export(
        $project_id,
    );

Sends a C<GET> request to C<projects/:project_id/export/download> and returns the decoded response content.

=cut

sub download_project_export {
    my $self = shift;
    croak 'download_project_export must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to download_project_export must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/export/download', [@_], $options );
}

=item schedule_project_import

    $api->schedule_project_import(
        \%params,
    );

Sends a C<POST> request to C<projects/import>.

=cut

sub schedule_project_import {
    my $self = shift;
    croak 'schedule_project_import must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to schedule_project_import must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/import', [@_], $options );
    return;
}

=item project_import_status

    my $status = $api->project_import_status(
        $project_id,
    );

Sends a C<GET> request to C<projects/:project_id/import> and returns the decoded response content.

=cut

sub project_import_status {
    my $self = shift;
    croak 'project_import_status must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($project_id) to project_import_status must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/import', [@_], $options );
}

=back

=head2 Project members

See L<https://docs.gitlab.com/ce/api/members.html>.

=over

=item project_members

    my $members = $api->project_members(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/members> and returns the decoded response content.

=cut

sub project_members {
    my $self = shift;
    croak 'project_members must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_members must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_members must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/members', [@_], $options );
}

=item all_project_members

    my $members = $api->all_project_members(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/members/all> and returns the decoded response content.

=cut

sub all_project_members {
    my $self = shift;
    croak 'all_project_members must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to all_project_members must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to all_project_members must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/members/all', [@_], $options );
}

=item project_member

    my $member = $api->project_member(
        $project_id,
        $user_id,
    );

Sends a C<GET> request to C<projects/:project_id/members/:user_id> and returns the decoded response content.

=cut

sub project_member {
    my $self = shift;
    croak 'project_member must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to project_member must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/members/:user_id', [@_], $options );
}

=item add_project_member

    my $member = $api->add_project_member(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/members> and returns the decoded response content.

=cut

sub add_project_member {
    my $self = shift;
    croak 'add_project_member must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to add_project_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to add_project_member must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/members', [@_], $options );
}

=item update_project_member

    my $member = $api->update_project_member(
        $project_id,
        $user_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/members/:user_id> and returns the decoded response content.

=cut

sub update_project_member {
    my $self = shift;
    croak 'update_project_member must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to update_project_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to update_project_member must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to update_project_member must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/members/:user_id', [@_], $options );
}

=item remove_project_member

    $api->remove_project_member(
        $project_id,
        $user_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/members/:user_id>.

=cut

sub remove_project_member {
    my $self = shift;
    croak 'remove_project_member must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to remove_project_member must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($user_id) to remove_project_member must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/members/:user_id', [@_], $options );
    return;
}

=back

=head2 Project snippets

See L<https://docs.gitlab.com/ce/api/project_snippets.html>.

=over

=item project_snippets

    my $snippets = $api->project_snippets(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/snippets> and returns the decoded response content.

=cut

sub project_snippets {
    my $self = shift;
    croak 'project_snippets must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_snippets must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_snippets must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/snippets', [@_], $options );
}

=item project_snippet

    my $snippet = $api->project_snippet(
        $project_id,
        $snippet_id,
    );

Sends a C<GET> request to C<projects/:project_id/snippets/:snippet_id> and returns the decoded response content.

=cut

sub project_snippet {
    my $self = shift;
    croak 'project_snippet must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to project_snippet must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/snippets/:snippet_id', [@_], $options );
}

=item create_project_snippet

    $api->create_project_snippet(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/snippets>.

=cut

sub create_project_snippet {
    my $self = shift;
    croak 'create_project_snippet must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_project_snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_project_snippet must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/:project_id/snippets', [@_], $options );
    return;
}

=item edit_project_snippet

    $api->edit_project_snippet(
        $project_id,
        $snippet_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/snippets/:snippet_id>.

=cut

sub edit_project_snippet {
    my $self = shift;
    croak 'edit_project_snippet must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_project_snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to edit_project_snippet must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_project_snippet must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/snippets/:snippet_id', [@_], $options );
    return;
}

=item delete_project_snippet

    $api->delete_project_snippet(
        $project_id,
        $snippet_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/snippets/:snippet_id>.

=cut

sub delete_project_snippet {
    my $self = shift;
    croak 'delete_project_snippet must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_project_snippet must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to delete_project_snippet must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/snippets/:snippet_id', [@_], $options );
    return;
}

=item project_snippet_content

    my $content = $api->project_snippet_content(
        $project_id,
        $snippet_id,
    );

Sends a C<GET> request to C<projects/:project_id/snippets/:snippet_id/raw> and returns the decoded response content.

=cut

sub project_snippet_content {
    my $self = shift;
    croak 'project_snippet_content must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_snippet_content must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to project_snippet_content must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/snippets/:snippet_id/raw', [@_], $options );
}

=item project_snippet_user_agent_detail

    my $user_agent = $api->project_snippet_user_agent_detail(
        $project_id,
        $snippet_id,
    );

Sends a C<GET> request to C<projects/:project_id/snippets/:snippet_id/user_agent_detail> and returns the decoded response content.

=cut

sub project_snippet_user_agent_detail {
    my $self = shift;
    croak 'project_snippet_user_agent_detail must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_snippet_user_agent_detail must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($snippet_id) to project_snippet_user_agent_detail must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/snippets/:snippet_id/user_agent_detail', [@_], $options );
}

=back

=head2 Protected branches

See L<https://docs.gitlab.com/ce/api/protected_branches.html>.

=over

=item protected_branches

    my $branches = $api->protected_branches(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/protected_branches> and returns the decoded response content.

=cut

sub protected_branches {
    my $self = shift;
    croak 'protected_branches must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to protected_branches must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to protected_branches must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/protected_branches', [@_], $options );
}

=item protected_branch

    my $branch = $api->protected_branch(
        $project_id,
        $branch_name,
    );

Sends a C<GET> request to C<projects/:project_id/protected_branches/:branch_name> and returns the decoded response content.

=cut

sub protected_branch {
    my $self = shift;
    croak 'protected_branch must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to protected_branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($branch_name) to protected_branch must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/protected_branches/:branch_name', [@_], $options );
}

=item protect_branch

    my $branch = $api->protect_branch(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/protected_branches> and returns the decoded response content.

=cut

sub protect_branch {
    my $self = shift;
    croak 'protect_branch must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to protect_branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to protect_branch must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/protected_branches', [@_], $options );
}

=item unprotect_branch

    $api->unprotect_branch(
        $project_id,
        $branch_name,
    );

Sends a C<DELETE> request to C<projects/:project_id/protected_branches/:branch_name>.

=cut

sub unprotect_branch {
    my $self = shift;
    croak 'unprotect_branch must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to unprotect_branch must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($branch_name) to unprotect_branch must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/protected_branches/:branch_name', [@_], $options );
    return;
}

=back

=head2 Protected tags

See L<https://docs.gitlab.com/ce/api/protected_tags.html>.

=over

=item protected_tags

    my $tags = $api->protected_tags(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/protected_tags> and returns the decoded response content.

=cut

sub protected_tags {
    my $self = shift;
    croak 'protected_tags must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to protected_tags must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to protected_tags must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/protected_tags', [@_], $options );
}

=item protected_tag

    my $tag = $api->protected_tag(
        $project_id,
        $tag_name,
    );

Sends a C<GET> request to C<projects/:project_id/protected_tags/:tag_name> and returns the decoded response content.

=cut

sub protected_tag {
    my $self = shift;
    croak 'protected_tag must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to protected_tag must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to protected_tag must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/protected_tags/:tag_name', [@_], $options );
}

=item protect_tag

    my $tag = $api->protect_tag(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/protected_tags> and returns the decoded response content.

=cut

sub protect_tag {
    my $self = shift;
    croak 'protect_tag must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to protect_tag must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to protect_tag must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/protected_tags', [@_], $options );
}

=item unprotect_tag

    $api->unprotect_tag(
        $project_id,
        $tag_name,
    );

Sends a C<DELETE> request to C<projects/:project_id/protected_tags/:tag_name>.

=cut

sub unprotect_tag {
    my $self = shift;
    croak 'unprotect_tag must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to unprotect_tag must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to unprotect_tag must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/protected_tags/:tag_name', [@_], $options );
    return;
}

=back

=head2 Releases

See L<https://docs.gitlab.com/ce/api/releases/index.html>.

=over

=item releases

    my $releases = $api->releases(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/releases> and returns the decoded response content.

=cut

sub releases {
    my $self = shift;
    croak 'releases must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to releases must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to releases must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/releases', [@_], $options );
}

=item release

    my $release = $api->release(
        $project_id,
        $tag_name,
    );

Sends a C<GET> request to C<projects/:project_id/releases/:tag_name> and returns the decoded response content.

=cut

sub release {
    my $self = shift;
    croak 'release must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to release must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to release must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/releases/:tag_name', [@_], $options );
}

=item create_release

    my $release = $api->create_release(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/releases> and returns the decoded response content.

=cut

sub create_release {
    my $self = shift;
    croak 'create_release must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_release must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_release must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/releases', [@_], $options );
}

=item update_release

    my $release = $api->update_release(
        $project_id,
        $tag_name,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/releases/:tag_name> and returns the decoded response content.

=cut

sub update_release {
    my $self = shift;
    croak 'update_release must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to update_release must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to update_release must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to update_release must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/releases/:tag_name', [@_], $options );
}

=item delete_release

    my $release = $api->delete_release(
        $project_id,
        $tag_name,
    );

Sends a C<DELETE> request to C<projects/:project_id/releases/:tag_name> and returns the decoded response content.

=cut

sub delete_release {
    my $self = shift;
    croak 'delete_release must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_release must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to delete_release must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'DELETE', 'projects/:project_id/releases/:tag_name', [@_], $options );
}

=back

=head2 Release Links

See L<https://docs.gitlab.com/ce/api/releases/links.html>.

=over

=item release_links

    my $links = $api->release_links(
        $project_id,
        $tag_name,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/releases/:tag_name/assets/links> and returns the decoded response content.

=cut

sub release_links {
    my $self = shift;
    croak 'release_links must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to release_links must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to release_links must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to release_links must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/releases/:tag_name/assets/links', [@_], $options );
}

=item release_link

    my $link = $api->release_link(
        $project_id,
        $tag_name,
        $link_id,
    );

Sends a C<GET> request to C<projects/:project_id/releases/:tag_name/assets/links/:link_id> and returns the decoded response content.

=cut

sub release_link {
    my $self = shift;
    croak 'release_link must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to release_link must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to release_link must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($link_id) to release_link must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/releases/:tag_name/assets/links/:link_id', [@_], $options );
}

=item create_release_link

    my $link = $api->create_release_link(
        $project_id,
        $tag_name,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/releases/:tag_name/assets/links> and returns the decoded response content.

=cut

sub create_release_link {
    my $self = shift;
    croak 'create_release_link must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_release_link must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to create_release_link must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_release_link must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/releases/:tag_name/assets/links', [@_], $options );
}

=item update_release_link

    my $link = $api->update_release_link(
        $project_id,
        $tag_name,
        $link_id,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/releases/:tag_name/assets/links/:link_id> and returns the decoded response content.

=cut

sub update_release_link {
    my $self = shift;
    croak 'update_release_link must be called with 3 to 4 arguments' if @_ < 3 or @_ > 4;
    croak 'The #1 argument ($project_id) to update_release_link must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to update_release_link must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($link_id) to update_release_link must be a scalar' if ref($_[2]) or (!defined $_[2]);
    croak 'The last argument (\%params) to update_release_link must be a hash ref' if defined($_[3]) and ref($_[3]) ne 'HASH';
    my $params = (@_ == 4) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/releases/:tag_name/assets/links/:link_id', [@_], $options );
}

=item delete_release_link

    my $link = $api->delete_release_link(
        $project_id,
        $tag_name,
        $link_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/releases/:tag_name/assets/links/:link_id> and returns the decoded response content.

=cut

sub delete_release_link {
    my $self = shift;
    croak 'delete_release_link must be called with 3 arguments' if @_ != 3;
    croak 'The #1 argument ($project_id) to delete_release_link must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to delete_release_link must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The #3 argument ($link_id) to delete_release_link must be a scalar' if ref($_[2]) or (!defined $_[2]);
    my $options = {};
    return $self->_call_rest_client( 'DELETE', 'projects/:project_id/releases/:tag_name/assets/links/:link_id', [@_], $options );
}

=back

=head2 Repositories

See L<https://docs.gitlab.com/ce/api/repositories.html>.

=over

=item tree

    my $tree = $api->tree(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/tree> and returns the decoded response content.

=cut

sub tree {
    my $self = shift;
    croak 'tree must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to tree must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to tree must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/tree', [@_], $options );
}

=item blob

    my $blob = $api->blob(
        $project_id,
        $sha,
    );

Sends a C<GET> request to C<projects/:project_id/repository/blobs/:sha> and returns the decoded response content.

=cut

sub blob {
    my $self = shift;
    croak 'blob must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to blob must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($sha) to blob must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/blobs/:sha', [@_], $options );
}

=item raw_blob

    my $raw_blob = $api->raw_blob(
        $project_id,
        $sha,
    );

Sends a C<GET> request to C<projects/:project_id/repository/blobs/:sha/raw> and returns the decoded response content.

=cut

sub raw_blob {
    my $self = shift;
    croak 'raw_blob must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to raw_blob must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($sha) to raw_blob must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/blobs/:sha/raw', [@_], $options );
}

=item archive

    my $archive = $api->archive(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/archive> and returns the raw response content.

=cut

sub archive {
    my $self = shift;
    croak 'archive must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to archive must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to archive must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/archive', [@_], $options );
}

=item compare

    my $comparison = $api->compare(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/compare> and returns the decoded response content.

=cut

sub compare {
    my $self = shift;
    croak 'compare must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to compare must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to compare must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/compare', [@_], $options );
}

=item contributors

    my $contributors = $api->contributors(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/contributors> and returns the decoded response content.

=cut

sub contributors {
    my $self = shift;
    croak 'contributors must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to contributors must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to contributors must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/contributors', [@_], $options );
}

=back

=head2 Repository files

See L<https://docs.gitlab.com/ce/api/repository_files.html>.

=over

=item file

    my $file = $api->file(
        $project_id,
        $file_path,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/files/:file_path> and returns the decoded response content.

=cut

sub file {
    my $self = shift;
    croak 'file must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($file_path) to file must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to file must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/files/:file_path', [@_], $options );
}

=item raw_file

    my $content = $api->raw_file(
        $project_id,
        $file_path,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/files/:file_path/raw> and returns the raw response content.

=cut

sub raw_file {
    my $self = shift;
    croak 'raw_file must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to raw_file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($file_path) to raw_file must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to raw_file must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/files/:file_path/raw', [@_], $options );
}

=item create_file

    $api->create_file(
        $project_id,
        $file_path,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/repository/files/:file_path>.

=cut

sub create_file {
    my $self = shift;
    croak 'create_file must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($file_path) to create_file must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_file must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'projects/:project_id/repository/files/:file_path', [@_], $options );
    return;
}

=item edit_file

    $api->edit_file(
        $project_id,
        $file_path,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/repository/files/:file_path>.

=cut

sub edit_file {
    my $self = shift;
    croak 'edit_file must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($file_path) to edit_file must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_file must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/repository/files/:file_path', [@_], $options );
    return;
}

=item delete_file

    $api->delete_file(
        $project_id,
        $file_path,
        \%params,
    );

Sends a C<DELETE> request to C<projects/:project_id/repository/files/:file_path>.

=cut

sub delete_file {
    my $self = shift;
    croak 'delete_file must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to delete_file must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($file_path) to delete_file must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to delete_file must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/repository/files/:file_path', [@_], $options );
    return;
}

=back

=head2 Runners

See L<https://docs.gitlab.com/ce/api/runners.html>.

=over

=item runners

    my $runners = $api->runners(
        \%params,
    );

Sends a C<GET> request to C<runners> and returns the decoded response content.

=cut

sub runners {
    my $self = shift;
    croak 'runners must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to runners must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'runners', [@_], $options );
}

=item all_runners

    my $runners = $api->all_runners(
        \%params,
    );

Sends a C<GET> request to C<runners/all> and returns the decoded response content.

=cut

sub all_runners {
    my $self = shift;
    croak 'all_runners must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to all_runners must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'runners/all', [@_], $options );
}

=item runner

    my $runner = $api->runner(
        $runner_id,
    );

Sends a C<GET> request to C<runners/:runner_id> and returns the decoded response content.

=cut

sub runner {
    my $self = shift;
    croak 'runner must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($runner_id) to runner must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'runners/:runner_id', [@_], $options );
}

=item update_runner

    my $runner = $api->update_runner(
        $runner_id,
        \%params,
    );

Sends a C<PUT> request to C<runners/:runner_id> and returns the decoded response content.

=cut

sub update_runner {
    my $self = shift;
    croak 'update_runner must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($runner_id) to update_runner must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to update_runner must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'runners/:runner_id', [@_], $options );
}

=item delete_runner

    $api->delete_runner(
        $runner_id,
    );

Sends a C<DELETE> request to C<runners/:runner_id>.

=cut

sub delete_runner {
    my $self = shift;
    croak 'delete_runner must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($runner_id) to delete_runner must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'runners/:runner_id', [@_], $options );
    return;
}

=item runner_jobs

    my $jobs = $api->runner_jobs(
        $runner_id,
        \%params,
    );

Sends a C<GET> request to C<runners/:runner_id/jobs> and returns the decoded response content.

=cut

sub runner_jobs {
    my $self = shift;
    croak 'runner_jobs must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($runner_id) to runner_jobs must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to runner_jobs must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'runners/:runner_id/jobs', [@_], $options );
}

=item project_runners

    my $runners = $api->project_runners(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/runners> and returns the decoded response content.

=cut

sub project_runners {
    my $self = shift;
    croak 'project_runners must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to project_runners must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to project_runners must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/runners', [@_], $options );
}

=item enable_project_runner

    my $runner = $api->enable_project_runner(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/runners> and returns the decoded response content.

=cut

sub enable_project_runner {
    my $self = shift;
    croak 'enable_project_runner must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to enable_project_runner must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to enable_project_runner must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/runners', [@_], $options );
}

=item disable_project_runner

    my $runner = $api->disable_project_runner(
        $project_id,
        $runner_id,
    );

Sends a C<DELETE> request to C<projects/:project_id/runners/:runner_id> and returns the decoded response content.

=cut

sub disable_project_runner {
    my $self = shift;
    croak 'disable_project_runner must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to disable_project_runner must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($runner_id) to disable_project_runner must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'DELETE', 'projects/:project_id/runners/:runner_id', [@_], $options );
}

=back

=head2 Search

See L<https://docs.gitlab.com/ce/api/search.html>.

=over

=item search

    my $results = $api->search(
        \%params,
    );

Sends a C<GET> request to C<search> and returns the decoded response content.

=cut

sub search {
    my $self = shift;
    croak 'search must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to search must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'search', [@_], $options );
}

=back

=head2 Services

See L<https://docs.gitlab.com/ce/api/services.html>.

=over

=item project_service

    my $service = $api->project_service(
        $project_id,
        $service_name,
    );

Sends a C<GET> request to C<projects/:project_id/services/:service_name> and returns the decoded response content.

=cut

sub project_service {
    my $self = shift;
    croak 'project_service must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to project_service must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($service_name) to project_service must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/services/:service_name', [@_], $options );
}

=item edit_project_service

    $api->edit_project_service(
        $project_id,
        $service_name,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/services/:service_name>.

=cut

sub edit_project_service {
    my $self = shift;
    croak 'edit_project_service must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_project_service must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($service_name) to edit_project_service must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_project_service must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'projects/:project_id/services/:service_name', [@_], $options );
    return;
}

=item delete_project_service

    $api->delete_project_service(
        $project_id,
        $service_name,
    );

Sends a C<DELETE> request to C<projects/:project_id/services/:service_name>.

=cut

sub delete_project_service {
    my $self = shift;
    croak 'delete_project_service must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_project_service must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($service_name) to delete_project_service must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/services/:service_name', [@_], $options );
    return;
}

=back

=head2 Application settings

See L<https://docs.gitlab.com/ce/api/settings.html>.

=over

=item settings

    my $settings = $api->settings();

Sends a C<GET> request to C<application/settings> and returns the decoded response content.

=cut

sub settings {
    my $self = shift;
    croak "The settings method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'application/settings', [@_], $options );
}

=item update_settings

    my $settings = $api->update_settings(
        \%params,
    );

Sends a C<PUT> request to C<application/settings> and returns the decoded response content.

=cut

sub update_settings {
    my $self = shift;
    croak 'update_settings must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to update_settings must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'application/settings', [@_], $options );
}

=back

=head2 Application statistics

See L<https://docs.gitlab.com/ce/api/statistics.html>.

=over

=item statistics

    my $statistics = $api->statistics();

Sends a C<GET> request to C<application/statistics> and returns the decoded response content.

=cut

sub statistics {
    my $self = shift;
    croak "The statistics method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'application/statistics', [@_], $options );
}

=back

=head2 Sidekiq Metrics

See L<https://docs.gitlab.com/ce/api/sidekiq_metrics.html>.

=over

=item queue_metrics

    my $metrics = $api->queue_metrics();

Sends a C<GET> request to C<sidekiq/queue_metrics> and returns the decoded response content.

=cut

sub queue_metrics {
    my $self = shift;
    croak "The queue_metrics method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'sidekiq/queue_metrics', [@_], $options );
}

=item process_metrics

    my $metrics = $api->process_metrics();

Sends a C<GET> request to C<sidekiq/process_metrics> and returns the decoded response content.

=cut

sub process_metrics {
    my $self = shift;
    croak "The process_metrics method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'sidekiq/process_metrics', [@_], $options );
}

=item job_stats

    my $stats = $api->job_stats();

Sends a C<GET> request to C<sidekiq/job_stats> and returns the decoded response content.

=cut

sub job_stats {
    my $self = shift;
    croak "The job_stats method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'sidekiq/job_stats', [@_], $options );
}

=item compound_metrics

    my $metrics = $api->compound_metrics();

Sends a C<GET> request to C<sidekiq/compound_metrics> and returns the decoded response content.

=cut

sub compound_metrics {
    my $self = shift;
    croak "The compound_metrics method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'sidekiq/compound_metrics', [@_], $options );
}

=back

=head2 System hooks

See L<https://docs.gitlab.com/ce/api/system_hooks.html>.

=over

=item hooks

    my $hooks = $api->hooks(
        \%params,
    );

Sends a C<GET> request to C<hooks> and returns the decoded response content.

=cut

sub hooks {
    my $self = shift;
    croak 'hooks must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to hooks must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'hooks', [@_], $options );
}

=item create_hook

    $api->create_hook(
        \%params,
    );

Sends a C<POST> request to C<hooks>.

=cut

sub create_hook {
    my $self = shift;
    croak 'create_hook must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_hook must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'hooks', [@_], $options );
    return;
}

=item test_hook

    my $hook = $api->test_hook(
        $hook_id,
    );

Sends a C<GET> request to C<hooks/:hook_id> and returns the decoded response content.

=cut

sub test_hook {
    my $self = shift;
    croak 'test_hook must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($hook_id) to test_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'hooks/:hook_id', [@_], $options );
}

=item delete_hook

    $api->delete_hook(
        $hook_id,
    );

Sends a C<DELETE> request to C<hooks/:hook_id>.

=cut

sub delete_hook {
    my $self = shift;
    croak 'delete_hook must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($hook_id) to delete_hook must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'hooks/:hook_id', [@_], $options );
    return;
}

=back

=head2 Tags

See L<https://docs.gitlab.com/ce/api/tags.html>.

=over

=item tags

    my $tags = $api->tags(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/repository/tags> and returns the decoded response content.

=cut

sub tags {
    my $self = shift;
    croak 'tags must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to tags must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to tags must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/tags', [@_], $options );
}

=item tag

    my $tag = $api->tag(
        $project_id,
        $tag_name,
    );

Sends a C<GET> request to C<projects/:project_id/repository/tags/:tag_name> and returns the decoded response content.

=cut

sub tag {
    my $self = shift;
    croak 'tag must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to tag must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to tag must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/repository/tags/:tag_name', [@_], $options );
}

=item create_tag

    my $tag = $api->create_tag(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/repository/tags> and returns the decoded response content.

=cut

sub create_tag {
    my $self = shift;
    croak 'create_tag must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_tag must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_tag must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/repository/tags', [@_], $options );
}

=item delete_tag

    $api->delete_tag(
        $project_id,
        $tag_name,
    );

Sends a C<DELETE> request to C<projects/:project_id/repository/tags/:tag_name>.

=cut

sub delete_tag {
    my $self = shift;
    croak 'delete_tag must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_tag must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to delete_tag must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/repository/tags/:tag_name', [@_], $options );
    return;
}

=item create_tag_release

    my $release = $api->create_tag_release(
        $project_id,
        $tag_name,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/repository/tags/:tag_name/release> and returns the decoded response content.

=cut

sub create_tag_release {
    my $self = shift;
    croak 'create_tag_release must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to create_tag_release must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to create_tag_release must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to create_tag_release must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/repository/tags/:tag_name/release', [@_], $options );
}

=item update_tag_release

    my $release = $api->update_tag_release(
        $project_id,
        $tag_name,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/repository/tags/:tag_name/release> and returns the decoded response content.

=cut

sub update_tag_release {
    my $self = shift;
    croak 'update_tag_release must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to update_tag_release must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($tag_name) to update_tag_release must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to update_tag_release must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/repository/tags/:tag_name/release', [@_], $options );
}

=back

=head2 Todos

See L<https://docs.gitlab.com/ce/api/todos.html>.

=over

=item todos

    my $todos = $api->todos(
        \%params,
    );

Sends a C<GET> request to C<todos> and returns the decoded response content.

=cut

sub todos {
    my $self = shift;
    croak 'todos must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to todos must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'todos', [@_], $options );
}

=item mark_todo_done

    my $todo = $api->mark_todo_done(
        $todo_id,
    );

Sends a C<POST> request to C<todos/:todo_id/mark_as_done> and returns the decoded response content.

=cut

sub mark_todo_done {
    my $self = shift;
    croak 'mark_todo_done must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($todo_id) to mark_todo_done must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'todos/:todo_id/mark_as_done', [@_], $options );
}

=item mark_all_todos_done

    $api->mark_all_todos_done();

Sends a C<POST> request to C<todos/mark_as_done>.

=cut

sub mark_all_todos_done {
    my $self = shift;
    croak "The mark_all_todos_done method does not take any arguments" if @_;
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'POST', 'todos/mark_as_done', [@_], $options );
    return;
}

=back

=head2 Users

See L<https://docs.gitlab.com/ce/api/users.html>.

=over

=item users

    my $users = $api->users(
        \%params,
    );

Sends a C<GET> request to C<users> and returns the decoded response content.

=cut

sub users {
    my $self = shift;
    croak 'users must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to users must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'users', [@_], $options );
}

=item user

    my $user = $api->user(
        $user_id,
    );

Sends a C<GET> request to C<users/:user_id> and returns the decoded response content.

=cut

sub user {
    my $self = shift;
    croak 'user must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($user_id) to user must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'users/:user_id', [@_], $options );
}

=item create_user

    $api->create_user(
        \%params,
    );

Sends a C<POST> request to C<users>.

=cut

sub create_user {
    my $self = shift;
    croak 'create_user must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_user must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'users', [@_], $options );
    return;
}

=item edit_user

    $api->edit_user(
        $user_id,
        \%params,
    );

Sends a C<PUT> request to C<users/:user_id>.

=cut

sub edit_user {
    my $self = shift;
    croak 'edit_user must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to edit_user must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to edit_user must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'PUT', 'users/:user_id', [@_], $options );
    return;
}

=item delete_user

    $api->delete_user(
        $user_id,
        \%params,
    );

Sends a C<DELETE> request to C<users/:user_id>.

=cut

sub delete_user {
    my $self = shift;
    croak 'delete_user must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to delete_user must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to delete_user must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'DELETE', 'users/:user_id', [@_], $options );
    return;
}

=item current_user

    my $user = $api->current_user();

Sends a C<GET> request to C<user> and returns the decoded response content.

=cut

sub current_user {
    my $self = shift;
    croak "The current_user method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'user', [@_], $options );
}

=item current_user_ssh_keys

    my $keys = $api->current_user_ssh_keys(
        \%params,
    );

Sends a C<GET> request to C<user/keys> and returns the decoded response content.

=cut

sub current_user_ssh_keys {
    my $self = shift;
    croak 'current_user_ssh_keys must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to current_user_ssh_keys must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'user/keys', [@_], $options );
}

=item user_ssh_keys

    my $keys = $api->user_ssh_keys(
        $user_id,
        \%params,
    );

Sends a C<GET> request to C<users/:user_id/keys> and returns the decoded response content.

=cut

sub user_ssh_keys {
    my $self = shift;
    croak 'user_ssh_keys must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to user_ssh_keys must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to user_ssh_keys must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'users/:user_id/keys', [@_], $options );
}

=item user_ssh_key

    my $key = $api->user_ssh_key(
        $key_id,
    );

Sends a C<GET> request to C<user/keys/:key_id> and returns the decoded response content.

=cut

sub user_ssh_key {
    my $self = shift;
    croak 'user_ssh_key must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($key_id) to user_ssh_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'user/keys/:key_id', [@_], $options );
}

=item create_current_user_ssh_key

    $api->create_current_user_ssh_key(
        \%params,
    );

Sends a C<POST> request to C<user/keys>.

=cut

sub create_current_user_ssh_key {
    my $self = shift;
    croak 'create_current_user_ssh_key must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_current_user_ssh_key must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'user/keys', [@_], $options );
    return;
}

=item create_user_ssh_key

    $api->create_user_ssh_key(
        $user_id,
        \%params,
    );

Sends a C<POST> request to C<users/:user_id/keys>.

=cut

sub create_user_ssh_key {
    my $self = shift;
    croak 'create_user_ssh_key must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to create_user_ssh_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_user_ssh_key must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'users/:user_id/keys', [@_], $options );
    return;
}

=item delete_current_user_ssh_key

    $api->delete_current_user_ssh_key(
        $key_id,
    );

Sends a C<DELETE> request to C<user/keys/:key_id>.

=cut

sub delete_current_user_ssh_key {
    my $self = shift;
    croak 'delete_current_user_ssh_key must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($key_id) to delete_current_user_ssh_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'user/keys/:key_id', [@_], $options );
    return;
}

=item delete_user_ssh_key

    $api->delete_user_ssh_key(
        $user_id,
        $key_id,
    );

Sends a C<DELETE> request to C<users/:user_id/keys/:key_id>.

=cut

sub delete_user_ssh_key {
    my $self = shift;
    croak 'delete_user_ssh_key must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($user_id) to delete_user_ssh_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($key_id) to delete_user_ssh_key must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'users/:user_id/keys/:key_id', [@_], $options );
    return;
}

=item current_user_gpg_keys

    my $keys = $api->current_user_gpg_keys(
        \%params,
    );

Sends a C<GET> request to C<user/gpg_keys> and returns the decoded response content.

=cut

sub current_user_gpg_keys {
    my $self = shift;
    croak 'current_user_gpg_keys must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to current_user_gpg_keys must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'user/gpg_keys', [@_], $options );
}

=item current_user_gpg_key

    my $key = $api->current_user_gpg_key(
        $key_id,
    );

Sends a C<GET> request to C<user/gpg_keys/:key_id> and returns the decoded response content.

=cut

sub current_user_gpg_key {
    my $self = shift;
    croak 'current_user_gpg_key must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($key_id) to current_user_gpg_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'user/gpg_keys/:key_id', [@_], $options );
}

=item create_current_user_gpg_key

    $api->create_current_user_gpg_key(
        \%params,
    );

Sends a C<POST> request to C<user/gpg_keys>.

=cut

sub create_current_user_gpg_key {
    my $self = shift;
    croak 'create_current_user_gpg_key must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_current_user_gpg_key must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{decode} = 0;
    $options->{content} = $params if defined $params;
    $self->_call_rest_client( 'POST', 'user/gpg_keys', [@_], $options );
    return;
}

=item delete_current_user_gpg_key

    $api->delete_current_user_gpg_key(
        $key_id,
    );

Sends a C<DELETE> request to C<user/gpg_keys/:key_id>.

=cut

sub delete_current_user_gpg_key {
    my $self = shift;
    croak 'delete_current_user_gpg_key must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($key_id) to delete_current_user_gpg_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'user/gpg_keys/:key_id', [@_], $options );
    return;
}

=item user_gpg_keys

    my $keys = $api->user_gpg_keys(
        $user_id,
        \%params,
    );

Sends a C<GET> request to C<users/:user_id/gpg_keys> and returns the decoded response content.

=cut

sub user_gpg_keys {
    my $self = shift;
    croak 'user_gpg_keys must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to user_gpg_keys must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to user_gpg_keys must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'users/:user_id/gpg_keys', [@_], $options );
}

=item user_gpg_key

    my $key = $api->user_gpg_key(
        $user_id,
        $key_id,
    );

Sends a C<GET> request to C<users/:user_id/gpg_keys/:key_id> and returns the decoded response content.

=cut

sub user_gpg_key {
    my $self = shift;
    croak 'user_gpg_key must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($user_id) to user_gpg_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($key_id) to user_gpg_key must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'users/:user_id/gpg_keys/:key_id', [@_], $options );
}

=item create_user_gpg_key

    my $keys = $api->create_user_gpg_key(
        $user_id,
        \%params,
    );

Sends a C<POST> request to C<users/:user_id/gpg_keys> and returns the decoded response content.

=cut

sub create_user_gpg_key {
    my $self = shift;
    croak 'create_user_gpg_key must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to create_user_gpg_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_user_gpg_key must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'users/:user_id/gpg_keys', [@_], $options );
}

=item delete_user_gpg_key

    $api->delete_user_gpg_key(
        $user_id,
        $key_id,
    );

Sends a C<DELETE> request to C<users/:user_id/gpg_keys/:key_id>.

=cut

sub delete_user_gpg_key {
    my $self = shift;
    croak 'delete_user_gpg_key must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($user_id) to delete_user_gpg_key must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($key_id) to delete_user_gpg_key must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'users/:user_id/gpg_keys/:key_id', [@_], $options );
    return;
}

=item current_user_emails

    my $emails = $api->current_user_emails(
        \%params,
    );

Sends a C<GET> request to C<user/emails> and returns the decoded response content.

=cut

sub current_user_emails {
    my $self = shift;
    croak 'current_user_emails must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to current_user_emails must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'user/emails', [@_], $options );
}

=item user_emails

    my $emails = $api->user_emails(
        $user_id,
        \%params,
    );

Sends a C<GET> request to C<users/:user_id/emails> and returns the decoded response content.

=cut

sub user_emails {
    my $self = shift;
    croak 'user_emails must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to user_emails must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to user_emails must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'users/:user_id/emails', [@_], $options );
}

=item current_user_email

    my $email = $api->current_user_email(
        $email_id,
    );

Sends a C<GET> request to C<user/emails/:email_id> and returns the decoded response content.

=cut

sub current_user_email {
    my $self = shift;
    croak 'current_user_email must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($email_id) to current_user_email must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'user/emails/:email_id', [@_], $options );
}

=item create_current_user_email

    my $email = $api->create_current_user_email(
        \%params,
    );

Sends a C<POST> request to C<user/emails> and returns the decoded response content.

=cut

sub create_current_user_email {
    my $self = shift;
    croak 'create_current_user_email must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to create_current_user_email must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'user/emails', [@_], $options );
}

=item create_user_email

    my $email = $api->create_user_email(
        $user_id,
        \%params,
    );

Sends a C<POST> request to C<users/:user_id/emails> and returns the decoded response content.

=cut

sub create_user_email {
    my $self = shift;
    croak 'create_user_email must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to create_user_email must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_user_email must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'users/:user_id/emails', [@_], $options );
}

=item delete_current_user_email

    $api->delete_current_user_email(
        $email_id,
    );

Sends a C<DELETE> request to C<user/emails/:email_id>.

=cut

sub delete_current_user_email {
    my $self = shift;
    croak 'delete_current_user_email must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($email_id) to delete_current_user_email must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'user/emails/:email_id', [@_], $options );
    return;
}

=item delete_user_email

    $api->delete_user_email(
        $user_id,
        $email_id,
    );

Sends a C<DELETE> request to C<users/:user_id/emails/:email_id>.

=cut

sub delete_user_email {
    my $self = shift;
    croak 'delete_user_email must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($user_id) to delete_user_email must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($email_id) to delete_user_email must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'users/:user_id/emails/:email_id', [@_], $options );
    return;
}

=item block_user

    my $success = $api->block_user(
        $user_id,
    );

Sends a C<POST> request to C<users/:user_id/block> and returns the decoded response content.

=cut

sub block_user {
    my $self = shift;
    croak 'block_user must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($user_id) to block_user must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'users/:user_id/block', [@_], $options );
}

=item unblock_user

    my $success = $api->unblock_user(
        $user_id,
    );

Sends a C<POST> request to C<users/:user_id/unblock> and returns the decoded response content.

=cut

sub unblock_user {
    my $self = shift;
    croak 'unblock_user must be called with 1 arguments' if @_ != 1;
    croak 'The #1 argument ($user_id) to unblock_user must be a scalar' if ref($_[0]) or (!defined $_[0]);
    my $options = {};
    return $self->_call_rest_client( 'POST', 'users/:user_id/unblock', [@_], $options );
}

=item user_impersonation_tokens

    my $tokens = $api->user_impersonation_tokens(
        $user_id,
        \%params,
    );

Sends a C<GET> request to C<users/:user_id/impersonation_tokens> and returns the decoded response content.

=cut

sub user_impersonation_tokens {
    my $self = shift;
    croak 'user_impersonation_tokens must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to user_impersonation_tokens must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to user_impersonation_tokens must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'users/:user_id/impersonation_tokens', [@_], $options );
}

=item user_impersonation_token

    my $token = $api->user_impersonation_token(
        $user_id,
        $impersonation_token_id,
    );

Sends a C<GET> request to C<users/:user_id/impersonation_tokens/:impersonation_token_id> and returns the decoded response content.

=cut

sub user_impersonation_token {
    my $self = shift;
    croak 'user_impersonation_token must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($user_id) to user_impersonation_token must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($impersonation_token_id) to user_impersonation_token must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'users/:user_id/impersonation_tokens/:impersonation_token_id', [@_], $options );
}

=item create_user_impersonation_token

    my $token = $api->create_user_impersonation_token(
        $user_id,
        \%params,
    );

Sends a C<POST> request to C<users/:user_id/impersonation_tokens> and returns the decoded response content.

=cut

sub create_user_impersonation_token {
    my $self = shift;
    croak 'create_user_impersonation_token must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to create_user_impersonation_token must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_user_impersonation_token must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'users/:user_id/impersonation_tokens', [@_], $options );
}

=item delete_user_impersonation_token

    $api->delete_user_impersonation_token(
        $user_id,
        $impersonation_token_id,
    );

Sends a C<DELETE> request to C<users/:user_id/impersonation_tokens/:impersonation_token_id>.

=cut

sub delete_user_impersonation_token {
    my $self = shift;
    croak 'delete_user_impersonation_token must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($user_id) to delete_user_impersonation_token must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($impersonation_token_id) to delete_user_impersonation_token must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'users/:user_id/impersonation_tokens/:impersonation_token_id', [@_], $options );
    return;
}

=item all_user_activities

    my $activities = $api->all_user_activities(
        \%params,
    );

Sends a C<GET> request to C<user/activities> and returns the decoded response content.

=cut

sub all_user_activities {
    my $self = shift;
    croak 'all_user_activities must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to all_user_activities must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'user/activities', [@_], $options );
}

=item user_memberships

    my $memberships = $api->user_memberships(
        $user_id,
        \%params,
    );

Sends a C<GET> request to C<users/:user_id/memberships> and returns the decoded response content.

=cut

sub user_memberships {
    my $self = shift;
    croak 'user_memberships must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($user_id) to user_memberships must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to user_memberships must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'users/:user_id/memberships', [@_], $options );
}

=back

=head2 Validate the .gitlab-ci.yml

See L<https://docs.gitlab.com/ce/api/lint.html>.

=over

=item lint

    my $result = $api->lint(
        \%params,
    );

Sends a C<POST> request to C<lint> and returns the decoded response content.

=cut

sub lint {
    my $self = shift;
    croak 'lint must be called with 0 to 1 arguments' if @_ < 0 or @_ > 1;
    croak 'The last argument (\%params) to lint must be a hash ref' if defined($_[0]) and ref($_[0]) ne 'HASH';
    my $params = (@_ == 1) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'lint', [@_], $options );
}

=back

=head2 Version

See L<https://docs.gitlab.com/ce/api/version.html>.

=over

=item version

    my $version = $api->version();

Sends a C<GET> request to C<version> and returns the decoded response content.

=cut

sub version {
    my $self = shift;
    croak "The version method does not take any arguments" if @_;
    my $options = {};
    return $self->_call_rest_client( 'GET', 'version', [@_], $options );
}

=back

=head2 Wikis

See L<https://docs.gitlab.com/ce/api/wikis.html>.

=over

=item wiki_pages

    my $pages = $api->wiki_pages(
        $project_id,
        \%params,
    );

Sends a C<GET> request to C<projects/:project_id/wikis> and returns the decoded response content.

=cut

sub wiki_pages {
    my $self = shift;
    croak 'wiki_pages must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to wiki_pages must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to wiki_pages must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{query} = $params if defined $params;
    return $self->_call_rest_client( 'GET', 'projects/:project_id/wikis', [@_], $options );
}

=item wiki_page

    my $pages = $api->wiki_page(
        $project_id,
        $slug,
    );

Sends a C<GET> request to C<projects/:project_id/wikis/:slug> and returns the decoded response content.

=cut

sub wiki_page {
    my $self = shift;
    croak 'wiki_page must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to wiki_page must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($slug) to wiki_page must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    return $self->_call_rest_client( 'GET', 'projects/:project_id/wikis/:slug', [@_], $options );
}

=item create_wiki_page

    my $page = $api->create_wiki_page(
        $project_id,
        \%params,
    );

Sends a C<POST> request to C<projects/:project_id/wikis> and returns the decoded response content.

=cut

sub create_wiki_page {
    my $self = shift;
    croak 'create_wiki_page must be called with 1 to 2 arguments' if @_ < 1 or @_ > 2;
    croak 'The #1 argument ($project_id) to create_wiki_page must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The last argument (\%params) to create_wiki_page must be a hash ref' if defined($_[1]) and ref($_[1]) ne 'HASH';
    my $params = (@_ == 2) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'POST', 'projects/:project_id/wikis', [@_], $options );
}

=item edit_wiki_page

    my $page = $api->edit_wiki_page(
        $project_id,
        $slug,
        \%params,
    );

Sends a C<PUT> request to C<projects/:project_id/wikis/:slug> and returns the decoded response content.

=cut

sub edit_wiki_page {
    my $self = shift;
    croak 'edit_wiki_page must be called with 2 to 3 arguments' if @_ < 2 or @_ > 3;
    croak 'The #1 argument ($project_id) to edit_wiki_page must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($slug) to edit_wiki_page must be a scalar' if ref($_[1]) or (!defined $_[1]);
    croak 'The last argument (\%params) to edit_wiki_page must be a hash ref' if defined($_[2]) and ref($_[2]) ne 'HASH';
    my $params = (@_ == 3) ? pop() : undef;
    my $options = {};
    $options->{content} = $params if defined $params;
    return $self->_call_rest_client( 'PUT', 'projects/:project_id/wikis/:slug', [@_], $options );
}

=item delete_wiki_page

    $api->delete_wiki_page(
        $project_id,
        $slug,
    );

Sends a C<DELETE> request to C<projects/:project_id/wikis/:slug>.

=cut

sub delete_wiki_page {
    my $self = shift;
    croak 'delete_wiki_page must be called with 2 arguments' if @_ != 2;
    croak 'The #1 argument ($project_id) to delete_wiki_page must be a scalar' if ref($_[0]) or (!defined $_[0]);
    croak 'The #2 argument ($slug) to delete_wiki_page must be a scalar' if ref($_[1]) or (!defined $_[1]);
    my $options = {};
    $options->{decode} = 0;
    $self->_call_rest_client( 'DELETE', 'projects/:project_id/wikis/:slug', [@_], $options );
    return;
}

=back

=cut

1;
__END__

=head1 CONTRIBUTING

This module is auto-generated from a set of YAML files defining the
interface of GitLab's API.  If you'd like to contribute to this module
then please feel free to make a
L<fork on GitHub|https://github.com/bluefeet/GitLab-API-v4>
and submit a pull request, just make sure you edit the files in the
C<authors/> directory instead of C<lib/GitLab/API/v4.pm> directly.

Please see
L<https://github.com/bluefeet/GitLab-API-v4/blob/master/author/README.pod>
for more information.

Alternatively, you can
L<open a ticket|https://github.com/bluefeet/GitLab-API-v4/issues>.

=head1 SUPPORT

Please submit bugs and feature requests to the
GitLab-API-v4 GitHub issue tracker:

L<https://github.com/bluefeet/GitLab-API-v4/issues>

=head1 ACKNOWLEDGEMENTS

Thanks to L<ZipRecruiter|https://www.ziprecruiter.com/>
for encouraging their employees to contribute back to the open
source ecosystem.  Without their dedication to quality software
development this distribution would not exist.

=head1 AUTHORS

    Aran Clary Deltac <bluefeet@gmail.com>
    Dotan Dimet <dotan@corky.net>
    Nigel Gregoire <nigelgregoire@gmail.com>
    trunov-ms <trunov.ms@gmail.com>
    Marek R. Sotola <Marek.R.Sotola@nasa.gov>
    José Joaquín Atria <jjatria@gmail.com>
    Dave Webb <github@d5ve.com>
    Simon Ruderich <simon@ruderich.org>
    royce55 <royce@ecs.vuw.ac.nz>
    gregor herrmann <gregoa@debian.org>
    Luc Didry <luc@didry.org>
    Kieren Diment <kieren.diment@staples.com.au>
    Dmitry Frolov <dmitry.frolov@gmail.com>
    Thomas Klausner <domm@plix.at>
    Graham Knop <haarg@haarg.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 Aran Clary Deltac

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.

=cut

