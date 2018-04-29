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

Extra care has been taken to hide the token arguments behind closures.  This way,
if you dump your api object, your tokens won't accidentally leak into places you
don't want them to.

=head2 CONSTANTS

The GitLab API, in rare cases, uses a numeric value to represent a state.
To make life easier the L<GitLab::API::v4::Constants> module exposes
these states as named variables.

=head2 EXCEPTIONS

The API methods will all throw a useful exception if
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
specified as a numeric project C<ID> or, in many cases, maybe all cases,
as a C<NAMESPACE_PATH/PROJECT_PATH> string.  The GitLab documentation on
this point is vague.

=cut

use GitLab::API::v4::Paginator;

use Types::Standard -types;
use Types::Common::String -types;
use Types::Common::Numeric -types;
use URI::Escape;
use Carp qw( croak confess );
use Log::Any qw( $log );
use Try::Tiny;
use URI;
use HTTP::Tiny;
use JSON;

use Moo;
use strictures 2;
use namespace::clean;

my $http_tiny = HTTP::Tiny->new();
my $json = JSON->new->utf8->allow_nonref();

sub BUILD {
    my ($self) = @_;

    # Ensure any token arguments get moved into their closure before we return
    # the built object.
    $self->access_token();
    $self->private_token();

    $log->debugf( "An instance of %s has been created.", ref($self) );

    return;
}

has _prepared_url => (
    is       => 'lazy',
    init_arg => undef,
    builder  => '_build_prepared_url',
);
sub _build_prepared_url {
    my ($self) = @_;
    my $url = $self->url();
    $url =~ s{/+$}{};
    return URI->new( $url )->canonical();
}

sub _call_rest_method {
    my ($self, $method, $path, $path_vars, $params, $return_content) = @_;

    $log->tracef( 'Making %s request against %s', $method, $path );

    $method = uc( $method );

    $path =~ s{:[^/]+}{%s}g;
    $path =~ s{^/}{};
    $path = sprintf($path, (map { uri_escape($_) } @$path_vars)) if @$path_vars;

    my $url = $self->_prepared_url->clone();
    $url->path( $url->path() . '/' . $path );

    my $headers = {};
    $headers->{'authorization'} = 'Bearer ' . $self->access_token()
        if defined $self->access_token();
    $headers->{'private-token'} = $self->private_token()
        if defined $self->private_token();
    $headers->{'sudo'} = $self->sudo_user()
        if defined $self->sudo_user();

    my $req_content = '';
    if ($params) {
        if ($method eq 'GET' or $method eq 'HEAD') {
            $url->query_form( $params );
        }
        else {
            $req_content = $json->encode( $params );
            $headers->{'content-type'} = 'application/json';
            $headers->{'content-length'} = length( $req_content );
        }
    }

    $url = "$url"; # no need to stringify on every retry

    my $res;
    my $tries_left = $self->retries();
    do {
        $res = $http_tiny->request(
            $method, $url,
            {
                headers => $headers,
                content => $req_content,
            },
        );
        if ($res->{status} =~ m{^5}) {
            $tries_left--;
            $log->warn('Request failed; retrying...') if $tries_left > 0;
        }
        else {
            $tries_left = 0
        }
    } while $tries_left > 0;

    if ($res->{status} eq '404' and $method eq 'GET' and $return_content) {
        return undef;
    }

    if ($res->{success}) {
        return if !$return_content;
        my $type = $res->{headers}->{'content-type'} || '';
        return $res->{content} if $type ne 'application/json';
        return $json->decode( $res->{content} );
    }

    local $Carp::Internal{ 'GitLab::API::v4' } = 1;
    my $one_line_res_content = $res->{content};
    $one_line_res_content =~ s{\s+}{ }g;
    confess sprintf(
        'Error %sing %s (HTTP %s): %s %s',
        $method, $url, $res->{status}, $res->{reason}, $one_line_res_content,
    );
}

sub _clone_args {
    my ($self) = @_;

    return {
        url         => $self->url(),
        retries     => $self->retries(),
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

=head2 sudo_user

The user to execute API calls as.  You may find it more useful to use the
L</sudo> method instead.

See L<https://docs.gitlab.com/ce/api/#sudo>.

=cut

has sudo_user => (
    is  => 'ro',
    isa => NonEmptySimpleStr,
);

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

