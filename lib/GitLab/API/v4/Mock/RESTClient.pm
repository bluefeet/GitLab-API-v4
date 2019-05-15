package GitLab::API::v4::Mock::RESTClient;

use GitLab::API::v4::Mock::Engine;
use JSON;
use URI;

use Moo;
use strictures 2;
use namespace::clean;

extends 'GitLab::API::v4::RESTClient';

my @ENDPOINTS;

sub has_endpoint {
    my ($method, $path_re, $sub) = @_;

    push @ENDPOINTS, [
        $method, $path_re, $sub,
    ];

    return;
}

sub _http_tiny_request {
    my ($self, $req_method, $req) = @_;

    die "req_method may only be 'request' at this time"
        if $req_method ne 'request';

    my ($http_method, $url, $options) = @$req;

    my $path = URI->new( $url )->path();
    $path =~ s{^.*api/v4/}{};

    foreach my $endpoint (@ENDPOINTS) {
        my ($endpoint_method, $path_re, $sub) = @$endpoint;

        next if $endpoint_method ne $http_method;
        next if $path !~ $path_re;

        my @captures = ($path =~ $path_re);

        my ($status, $content) = $sub->(
            $self,
            [$http_method, $url, $options],
            @captures,
        );

        $content = encode_json( $content ) if ref $content;

        return {
            status => $status,
            success => ($status =~ m{^2\d\d$}) ? 1 : 0,
            defined( $content ) ? (content=>$content) : (),
        };
    }

    die "No endpoint matched the $http_method '$path' endpoint";
}

=head1 ATTRIBUTES

=head2 engine

=cut

has engine => (
    is       => 'lazy',
    init_arg => undef,
);
sub _build_engine {
    return GitLab::API::v4::Mock::Engine->new();
}

=head1 USER ENDPOINTS

=head2 GET users

=cut

has_endpoint GET => qr{^users$}, sub{
    my ($self) = @_;
    return 200, $self->users();
};

=head2 GET user/:id

=cut

has_endpoint GET => qr{^users/(\d+)$}, sub{
    my ($self, $req, $id) = @_;

    my $user = $self->user( $id );
    return 404 if !$user;

    return 200, $user;
};

=head2 POST users

=cut

has_endpoint POST => qr{^users$}, sub{
    my ($self, $req) = @_;

    my $user = decode_json( $req->[2]->{content} );
    $self->create_user( $user );

    return 204;
};

=head2 PUT user/:id

=cut

has_endpoint PUT => qr{^users/(\d+)$}, sub{
    my ($self, $req, $id) = @_;

    my $data = decode_json( $req->[2]->{content} );

    my $user = $self->update_user( $id, $data );
    return 404 if !$user;

    return 204;
};

=head2 DELETE user/:id

=cut

has_endpoint DELETE => qr{^users/(\d+)$}, sub{
    my ($self, $req, $id) = @_;

    my $user = $self->delete_user( $id );
    return 404 if !$user;

    return 204;
};

1;
__END__

=head1 SUPPORT

See L<GitLab::API::v4/SUPPORT>.

=head1 AUTHORS

See L<GitLab::API::v4/AUTHORS>.

=head1 COPYRIGHT AND LICENSE

See L<GitLab::API::v4/COPYRIGHT AND LICENSE>.

=cut

