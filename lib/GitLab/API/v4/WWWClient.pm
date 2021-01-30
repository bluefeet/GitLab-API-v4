package GitLab::API::v4::WWWClient;
our $VERSION = '0.26';

=encoding utf8

=head1 NAME

GitLab::API::v4::WWWClient - A client that works against the GitLab web site.

=head1 SYNOPSIS

    use GitLab::API::v4::WWWClient;
    
    my $client = GitLab::API::v4::WWWClient->new(
        url => 'https://git.example.com/',
    );
    
    $client->sign_in( $username, $password );
    
    my $res = $client->get( $path );

=head1 DESCRIPTION

This class makes it possible to interact with the GitLab web site.

=cut

use Carp qw( croak );
use HTTP::Tiny;
use Types::Common::String qw( NonEmptySimpleStr );

use Moo;
use strictures 2;
use namespace::clean;

has _session => (
    is       => 'rw',
    init_arg => undef,
);

sub _croak_res {
    my ($verb, $url, $res) = @_;
    
    return if $res->{status} !~ m{^5};

    local $Carp::Internal{ 'GitLab::API::v4::WWWClient' } = 1;

    croak sprintf(
        'Error %sing %s (HTTP %s): %s',
        uc($verb), $url,
        $res->{status}, ($res->{reason} || 'Unknown'),
    );
}

=head1 REQUIRED ARGUMENTS

=head2 url

This is the base URL to your GitLab web site.

=cut

has url => (
    is       => 'ro',
    isa      => NonEmptySimpleStr,
    required => 1,
);

=head1 METHODS

=head2 sign_in

    $client->sign_in( $username, $password );

Signs in the client given the username and password.

=cut

sub sign_in {
    my ($self, $username, $password) = @_;

    my $tiny = HTTP::Tiny->new(
        max_redirect => 0,
    );

    my $base_url = $self->url();
    $base_url =~ s{/$}{};
    my $sign_in_url = "$base_url/users/sign_in";

    my $load_res = $tiny->get( $sign_in_url );

    _croak_res( 'get', $sign_in_url, $load_res );

    my $token = (
        $load_res->{content} =~
        m{name="authenticity_token" value="(.+?)"}
    )[0];

    my $first_session = (
        $load_res->{headers}->{'set-cookie'} =~
        m{_gitlab_session=(.+?);}
    )[0];

    my $submit_res = $tiny->post_form(
        $sign_in_url,
        {
            'utf8'               => '✓',
            'authenticity_token' => $token,
            'user[login]'        => $username,
            'user[password]'     => $password,
            'user[remember_me]'  => 0,
        },
        {
            headers => {
                'Referer' => $sign_in_url,
                'Cookie'  => "_gitlab_session=$first_session",
                'Cookie2' => '$Version="1"',
            },
        },
    );

    _croak_res( 'post', $sign_in_url, $submit_res );

    my $second_session = (
        $submit_res->{headers}->{'set-cookie'} =~
        m{_gitlab_session=(.+?);}
    )[0];

    my $home_res = $tiny->get(
        $base_url,
        {
            headers => {
                'Referer' => $sign_in_url,
                'Cookie'  => "_gitlab_session=$second_session",
                'Cookie2' => '$Version="1"',
            },
        },
    );

    _croak_res( 'get', $base_url, $home_res );

    my $ok = ( $home_res->{content} =~ m{sign-out-link} ) ? 1 : 0;
    croak 'Failed to sign in' if !$ok;

    $self->_session( $second_session );

    return;
}

=head2 get

    my $res = $client->get( $path );

Gets the path and returns the L<HTTP::Tiny> response hash.

=cut

sub get {
    my ($self, $path) = @_;

    my $tiny = HTTP::Tiny->new(
        max_redirect => 0,
    );

    my $base_url = $self->url();
    $base_url =~ s{/$}{};
    $path =~ s{^/}{};
    my $url = "$base_url/$path";

    my $session = $self->_session();
    my $headers = $session ? {
        'Cookie'  => "_gitlab_session=$session",
        'Cookie2' => '$Version="1"',
    } : {};

    my $res = $tiny->get(
        $url,
        { headers=>$headers },
    );

    _croak_res( 'get', $url, $res );

    return $res;
}

1;
__END__

=head1 SUPPORT

See L<GitLab::API::v4/SUPPORT>.

=head1 AUTHORS

See L<GitLab::API::v4/AUTHORS>.

=head1 COPYRIGHT AND LICENSE

See L<GitLab::API::v4/COPYRIGHT AND LICENSE>.

=cut

