package GitLab::API::v4::RESTClient;
our $VERSION = '0.27';

=encoding utf8

=head1 NAME

GitLab::API::v4::RESTClient - The HTTP client that does the heavy lifting.

=head1 DESCRIPTION

Currently this class uses L<HTTP::Tiny> and L<JSON::MaybeXS> to do its job.
This may change, and the interface may change, so documentation is lacking in
order to not mislead people.

If you do want to customize how this class works then take a look at the
source.

=head1 ATTRIBUTES

=head1 http_tiny_request

    my $req = $api->rest_client->http_tiny_request();

The most recent request arrayref as passed to L<HTTP::Tiny>.

If this is C<undef> then no request has been made.

=head1 http_tiny_response

    my $res = $api->rest_client->http_tiny_response();

The most recent response hashref as passed back from L<HTTP::Tiny>.

If this is C<undef> and L</request> is defined then no response was received
and you will have encountered an error when making the request

=cut

use Carp qw();
use HTTP::Tiny::Multipart;
use HTTP::Tiny;
use JSON::MaybeXS;
use Log::Any qw( $log );
use Path::Tiny;
use Try::Tiny;
use Types::Common::Numeric -types;
use Types::Common::String -types;
use Types::Standard -types;
use URI::Escape;
use URI;

use Moo;
use strictures 2;
use namespace::clean;

sub croak {
    local $Carp::Internal{ 'GitLab::API::v4' } = 1;
    local $Carp::Internal{ 'GitLab::API::v4::RESTClient' } = 1;

    return Carp::croak( @_ );
}

sub croakf {
    my $msg = shift;
    $msg = sprintf( $msg, @_ );
    return croak( $msg );
}

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

has retry_wait => (
    is      => 'ro',
    isa     => PositiveOrZeroInt,
    default => 10,
);

has http_tiny => (
    is  => 'lazy',
    isa => InstanceOf[ 'HTTP::Tiny' ],
);
sub _build_http_tiny {
    return HTTP::Tiny->new( verify_SSL => 1 );
}

has json => (
    is  => 'lazy',
    isa => HasMethods[ 'encode', 'decode' ],
);
sub _build_json {
    return JSON::MaybeXS->new(utf8 => 1, allow_nonref => 1);
}

has http_tiny_request => (
    is       => 'ro',
    writer   => '_set_request',
    clearer  => '_clear_request',
    init_arg => undef,
);

has http_tiny_response => (
    is       => 'ro',
    writer   => '_set_response',
    clearer  => '_clear_response',
    init_arg => undef,
);

# The purpose of this method is for tests to have a place to inject themselves.
sub _http_tiny_request {
    my ($self, $req_method, $req) = @_;

    return $self->http_tiny->$req_method( @$req );
}

sub request {
    my ($self, $verb, $raw_path, $path_vars, $options) = @_;

    $self->_clear_request();
    $self->_clear_response();

    $options = { %{ $options || {} } };
    my $query = delete $options->{query};
    my $content = delete $options->{content};
    my $headers = $options->{headers} = { %{ $options->{headers} || {} } };

    # Convert foo/:bar/baz into foo/%s/baz.
    my $path = $raw_path;
    $path =~ s{:[^/]+}{%s}g;
    # sprintf will throw if the number of %s doesn't match the size of @$path_vars.
    # Might be nice to catch that and provide a better error message, but that should
    # never happen as the API methods verify the argument size before we get here.
    $path = sprintf($path, (map { uri_escape($_) } @$path_vars)) if @$path_vars;

    $log->tracef( 'Making %s request against %s', $verb, $path );

    my $url = $self->_clean_base_url->clone();
    $url->path( $url->path() . '/' . $path );
    $url->query_form( $query ) if defined $query;
    $url = "$url"; # No more changes to the url from this point forward.

    my $req_method = 'request';
    my $req = [ $verb, $url, $options ];
    my $boundary;

    if (($verb eq 'POST' or $verb eq 'PUT' ) and ref($content) eq 'HASH' and $content->{file}) {
        $content = { %$content };
        my $file = delete $content->{file};

        my $key = (keys %$file)[0]
            if (ref $file);

        $file = (ref $file)
            ? path( $file->{$key} )
            : path( $file );

        unless (-f $file and -r $file) {
            local $Carp::Internal{ 'GitLab::API::v4' } = 1;
            local $Carp::Internal{ 'GitLab::API::v4::RESTClient' } = 1;
            croak "File $file is not readable";
        }

        # Might as well mask the filename, but leave the extension.
        my $filename = $file->basename(); # foo/bar.txt => bar.txt

        my $data = {
            file => {
                filename => $filename,
                content  => $file->slurp(),
            },
        };

        if ($verb eq 'POST') {
            $req->[0] = $req->[1]; # Replace method with url.
            $req->[1] = $data; # Put data where url was.
            # So, req went from [$verb,$url,$options] to [$url,$data,$options],
            # per the post_multipart interface.

            $req_method = 'post_multipart';
            $content = undef if ! %$content;
        } elsif ($verb eq 'PUT') {
            $boundary .= sprintf("%x", rand 16) for 1..16;
            $content = <<"EOL";
--------------------------$boundary
Content-Disposition: form-data; name="$key"; filename="$data->{file}->{filename}"

$data->{file}->{content}
--------------------------$boundary--
EOL
        }
    }

    if (defined $boundary or ref $content) {
        $content = $self->json->encode( $content )
          if (ref $content);

      $headers->{'content-type'} = (defined $boundary)
          ? "multipart/form-data; boundary=------------------------$boundary"
          : 'application/json';

        $headers->{'content-length'} = length( $content );
    }

    $options->{content} = $content if defined $content;

    $self->_set_request( $req );

    my $res;
    my $tries_left = $self->retries + 1;
    while ($tries_left) {
        $res = $self->_http_tiny_request( $req_method, $req );
        $tries_left--;
        last unless $tries_left;

        # Retry if we get a 5xx (error) or 429 (rate limited)
        my $status = $res->{status};
        last unless $status =~ m{^5} or $status == 429;
        my $wait = $self->retry_wait;
        $log->warn("Request failed with a $status status; retrying in $wait seconds...");
        sleep $wait if $wait;
    }

    $self->_set_response( $res );

    if ($res->{status} eq '404' and $verb eq 'GET') {
        return undef;
    }

    # Special case for:
    # https://github.com/bluefeet/GitLab-API-v4/issues/35#issuecomment-515533017
    if ($res->{status} eq '403' and $verb eq 'GET' and $raw_path eq 'projects/:project_id/releases/:tag_name') {
        return undef;
    }

    if ($res->{success}) {
        return undef if $res->{status} eq '204';

        my $decode = $options->{decode};
        $decode = 1 if !defined $decode;
        return $res->{content} if !$decode;

        return try{
            $self->json->decode( $res->{content} );
        }
        catch {
            croakf(
                'Error decoding JSON (%s %s %s): ',
                $verb, $url, $res->{status}, $_,
            );
        };
    }

    my $glimpse = $res->{content} || '';
    $glimpse =~ s{\s+}{ }g;
    if ( length($glimpse) > 50 ) {
        $glimpse = substr( $glimpse, 0, 50 );
        $glimpse .= '...';
    }

    croakf(
        'Error %sing %s (HTTP %s): %s %s',
        $verb, $url,
        $res->{status}, ($res->{reason} || 'Unknown'),
        $glimpse,
    );
}

1;
__END__

=head1 SUPPORT

See L<GitLab::API::v4/SUPPORT>.

=head1 AUTHORS

See L<GitLab::API::v4/AUTHORS>.

=head1 LICENSE

See L<GitLab::API::v4/LICENSE>.

=cut

