package GitLab::API::v4::Mock;
our $VERSION = '0.26';

=encoding utf8

=head1 NAME

GitLab::API::v4::Mock - Mock API object for testing.

=head1 SYNOPSIS

    use GitLab::API::v4::Mock;
    
    my $api = GitLab::API::v4::Mock->new();

=head1 DESCRIPTION

This module is a subclass of L<GitLab::API::v4>.  It modifies
it to mock the REST client via L<GitLab::API::v4::Mock::RESTClient>.

This module is meant to be used for writing unit tests.

=cut

use GitLab::API::v4::Mock::RESTClient;

use Moo;
use strictures 2;
use namespace::clean;

extends 'GitLab::API::v4';

=head1 ATTRIBUTES

=head2 url

This attribute is altered from L<GitLab::API::v4/url> to default
to C<https://example.com/api/v4> and to not be required.

=cut

has '+url' => (
    required => 0,
    default  => 'https://example.com/api/v4',
);

=head2 rest_client_class

This attribute is altered from L<GitLab::API::v4/rest_client_class>
to default to L<GitLab::API::v4::Mock::RESTClient>.

=cut

sub _build_rest_client_class {
    return 'GitLab::API::v4::Mock::RESTClient';
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

