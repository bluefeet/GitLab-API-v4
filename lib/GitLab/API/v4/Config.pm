package GitLab::API::v4::Config;
our $VERSION = '0.26';

=encoding utf8

=head1 NAME

GitLab::API::v4::Config - Load configuration from a file, environment,
and/or CLI options.

=head1 SYNOPSIS

    use GitLab::API::v4;
    use GitLab::API::v4::Config;
    
    my $config = GitLab::API::v4::Config->new();
    my $api = GitLab::API::v4->new( $config->args() );

=head1 DESCRIPTION

This module is used by L<gitlab-api-v4> to load configuration.

If you are using L<GitLab::API::v4> directly then this module will not be
automatically used, but you are welcome to explicitly use it as shown in the
L</SYNOPSIS>.

=cut

use Getopt::Long;
use IO::Prompter;
use JSON;
use Log::Any qw( $log );
use Path::Tiny;
use Types::Common::String -types;
use Types::Standard -types;

use Moo;
use strictures 2;
use namespace::clean;

sub _filter_args {
    my ($self, $args) = @_;

    return {
        map { $_ => $args->{$_} }
        grep { $args->{$_} }
        keys %$args
    };
}

=head1 ARGUMENTS

=head2 file

The file to load configuration from.  The file should hold valid JSON.

By default this will be set to C<.gitlab-api-v4-config> in the current
user's home directory.

This can be overridden with the C<GITLAB_API_V4_CONFIG_FILE> environment
variable or the C<--config-file=...> command line argument.

=cut

has file => (
    is  => 'lazy',
    isa => NonEmptySimpleStr,
);
sub _build_file {
    my ($self) = @_;

    my $file = $self->opt_args->{config_file}
            || $self->env_args->{config_file};
    return $file if $file;

    my ($home) = ( getpwuid($<) )[7];
    return '' . path( $home )->child('.gitlab-api-v4-config');
}

=head1 ATTRIBUTES

=head2 opt_args

Returns a hashref of arguments derived from command line options.

Supported options are:

    --config_file=...
    --url=...
    --private-token=...
    --access-token=...
    --retries=...

Note that the options are read from, and removed from, C<@ARGV>.  Due
to this the arguments are saved internally and re-used for all instances
of this class so that there are no weird race conditions.

=cut

has opt_args => (
    is      => 'rwp',
    isa     => HashRef,
    default => sub{ {} },
);

=head2 env_args

Returns a hashref of arguments derived from environment variables.

Supported environment variables are:

    GITLAB_API_V4_CONFIG_FILE
    GITLAB_API_V4_URL
    GITLAB_API_V4_PRIVATE_TOKEN
    GITLAB_API_V4_ACCESS_TOKEN
    GITLAB_API_V4_RETRIES

=cut

has env_args => (
    is  => 'lazy',
    isa => HashRef,
);
sub _build_env_args {
    my ($self) = @_;

    return $self->_filter_args({
        config_file   => $ENV{GITLAB_API_V4_CONFIG_FILE},
        url           => $ENV{GITLAB_API_V4_URL},
        private_token => $ENV{GITLAB_API_V4_PRIVATE_TOKEN},
        access_token  => $ENV{GITLAB_API_V4_ACCESS_TOKEN},
        retries       => $ENV{GITLAB_API_V4_RETRIES},
    });
}

=head2 file_args

Returns a hashref of arguments gotten by decoding the JSON in the L</file>.

=cut

has file_args => (
    is  => 'lazy',
    isa => HashRef,
);
sub _build_file_args {
    my ($self) = @_;

    my $file = $self->file();
    return {} if !-r $file;

    $file = path( $file );
    $log->debugf( 'Loading configuration for GitLab::API::v4 from: %s', $file->absolute() );
    my $json = $file->slurp();
    my $data = decode_json( $json );

    return $self->_filter_args( $data );
}

=head2 args

Returns a final, combined, hashref of arguments containing everything in
L</opt_args>, L</env_args>, and L</file_args>.  If there are any duplicate
arguments then L</opt_args> has highest precedence, L</env_args> is next, and
at the bottom is L</file_args>.

=cut

sub args {
    my ($self) = @_;

    return {
        %{ $self->file_args() },
        %{ $self->env_args() },
        %{ $self->opt_args() },
    };
}

=head1 METHODS

=head2 get_options

=cut

sub get_options {
    my ($self, @extra) = @_;

    Getopt::Long::Configure(qw(
        gnu_getopt no_ignore_case
    ));

    my $opt_args = {};

    GetOptions(
        'config-file=s'   => \$opt_args->{config_file},
        'url=s'           => \$opt_args->{url},
        'private-token=s' => \$opt_args->{private_token},
        'access-token=s'  => \$opt_args->{access_token},
        'retries=i'       => \$opt_args->{retries},
        @extra,
    ) or die('Unable to process options!');

    $opt_args = $self->_filter_args( $opt_args );

    $self->_set_opt_args( $opt_args );

    return;
}

=head2 configure

When called this method interactively prompts the user for argument values
and then encodes them as JSON and stores them in L</file>.  The file will
be chmod'ed C<0600> so that only the current user may read or write to the
file.

=cut

sub configure {
    my ($self) = @_;

    my $url = prompt(
        'Full URL to a v4 GitLab API:',
        '-stdio', '-verbatim',
    );

    my $private_token = prompt(
        'Private Token:',
        -echo=>'',
        '-stdio', '-verbatim',
    );

    my $access_token = prompt(
        'Access Token:',
        -echo=>'',
        '-stdio', '-verbatim',
    );

    my $json = JSON->new
        ->pretty
        ->canonical
    ->encode({
        $url           ? (url=>$url) : (),
        $private_token ? (private_token=>$private_token) : (),
        $access_token  ? (access_token=>$access_token) : (),
    });

    my $file = path( $self->file() );
    $file->touch();
    $file->chmod( 0600 );
    $file->append( {truncate=>1}, $json );

    $log->infof( 'Configuration for GitLab::API::v4 saved to: %s', $file->absolute() );

    return;
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

