package GitLab::API::v4::RESTClient;

=encoding utf8

=head1 NAME

GitLab::API::v4::RESTClient - The HTTP client that does the heavy lifting.

=head1 DESCRIPTION

Currently this class uses L<HTTP::Tiny> and L<JSON> to do its job.  This may
change, and the interface may change, so documentation is lacking in order
to not mislead people.

If you do want to customize how this class works then take a look at the
source.

=cut

use Types::Standard -types;
use Types::Common::String -types;
use Types::Common::Numeric -types;
use Log::Any qw( $log );
use URI::Escape;
use HTTP::Tiny;
use JSON;
use URI;
use Carp qw( confess );
use Try::Tiny;

use Moo;
use strictures 2;
use namespace::clean;

has _clean_base_url => (
    is       => 'lazy',
    init_arg => undef,
    builder  => '_build_clean_base_url',
);
sub _build_clean_base_url {
    my ($self) = @_;
    my $url = $self->base_url();

    # Remove any leading slash so that request() does not build URLs
    # with double slashes when joining the base_url with the path.
    # If double slashes were allowed then extra unecessary redirects
    # could happen.
    $url =~ s{/+$}{};

    return URI->new( $url )->canonical();
}

has base_url => (
    is       => 'ro',
    isa      => NonEmptySimpleStr,
    required => 1,
);

has retries => (
    is      => 'ro',
    isa     => PositiveOrZeroInt,
    default => 0,
);

has http_tiny => (
    is  => 'lazy',
    isa => InstanceOf[ 'HTTP::Tiny' ],
);
sub _build_http_tiny {
    return HTTP::Tiny->new();
}

has json => (
    is  => 'lazy',
    isa => HasMethods[ 'encode', 'decode' ],
);
sub _build_json {
    return JSON->new->utf8->allow_nonref();
}

sub request {
    my ($self, $method, $path, $path_vars, $options) = @_;

    # Convert foo/:bar/baz into foo/%s/baz.
    $path =~ s{:[^/]+}{%s}g;
    # sprintf will throw if the number of %s doesn't match the size of @$path_vars.
    # Might be nice to catch that and provide a better error message, but that should
    # never happen as the API methods verify the argument size before we get here.
    $path = sprintf($path, (map { uri_escape($_) } @$path_vars)) if @$path_vars;

    $log->tracef( 'Making %s request against %s', $method, $path );

    my $url = $self->_clean_base_url->clone();
    $url->path( $url->path() . '/' . $path );
    $url->query_form( $options->{query} ) if defined $options->{query};
    $url = "$url"; # No more changes to the url from this point forward.

    my $headers = $options->{headers};
    $headers = { %{ $headers || {} } }; # Clone headers since we may be modifying them.

    my $content = $options->{content};
    if (ref $content) {
        $content = $self->json->encode( $content );
        $headers->{'content-type'} = 'application/json';
        $headers->{'content-length'} = length( $content );
    }

    my $req = [
        $method, $url,
        {
            headers => $headers,
            defined($content) ? (content => $content) : (),
        },
    ];

    my $res;
    my $tries_left = $self->retries();
    do {
        $res = $self->http_tiny->request( @$req );
        if ($res->{status} =~ m{^5}) {
            $tries_left--;
            $log->warn('Request failed; retrying...') if $tries_left > 0;
        }
        else {
            $tries_left = 0
        }
    } while $tries_left > 0;


    if ($res->{status} eq '404' and $method eq 'GET') {
        return undef;
    }

    if ($res->{success}) {
        my $decode = $options->{decode};
        $decode = 1 if !defined $decode;

        return $res if !$decode;

        # JSON decoding may fail. Catch it and provide a more contextually rich
        # error message?
        return $self->json->decode( $res->{content} );
    }

    local $Carp::Internal{ 'GitLab::API::v4' } = 1;
    local $Carp::Internal{ 'GitLab::API::v4::RESTClient' } = 1;

    my $one_line_res_content = $res->{content};
    $one_line_res_content =~ s{\s+}{ }g;
    confess sprintf(
        'Error %sing %s (HTTP %s): %s %s',
        $method, $url, $res->{status}, $res->{reason}, $one_line_res_content,
    );
}

1;
__END__

=head1 AUTHORS

See L<GitLab::API::v4/AUTHOR> and L<GitLab::API::v4/CONTRIBUTORS>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

