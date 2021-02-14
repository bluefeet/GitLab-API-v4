package GitLab::API::v4::Paginator;
our $VERSION = '0.26';

=encoding utf8

=head1 NAME

GitLab::API::v4::Paginator - Iterate through paginated GitLab v4 API records.

=head1 DESCRIPTION

There should be no need to create objects of this type
directly, instead use L<GitLab::API::v4/paginator> which
simplifies things a bit.

=cut

use Carp qw( croak );
use Types::Common::String -types;
use Types::Standard -types;

use Moo;
use strictures 2;
use namespace::clean;

=head1 REQUIRED ARGUMENTS

=head2 method

The name of the method subroutine to call on the L</api> object
to get records from.

This method must accept a hash ref of parameters as the last
argument, adhere to the C<page> and C<per_page> parameters, and
return an array ref.

=cut

has method => (
    is       => 'ro',
    isa      => NonEmptySimpleStr,
    required => 1,
);

=head2 api

The L<GitLab::API::v4> object.

=cut

has api => (
    is       => 'ro',
    isa      => InstanceOf[ 'GitLab::API::v4' ],
    required => 1,
);

=head1 OPTIONAL ARGUMENTS

=head2 args

The arguments to use when calling the L</method>, the same arguments
you would use when you call the method yourself on the L</api>
object, minus the C<\%params> hash ref.

=cut

has args => (
    is      => 'ro',
    isa     => ArrayRef,
    default => sub{ [] },
);

=head2 params

The C<\%params> hash ref argument.

=cut

has params => (
    is      => 'ro',
    isa     => HashRef,
    default => sub{ {} },
);

=head1 METHODS

=cut

has _records => (
    is       => 'rw',
    init_arg => undef,
    default  => sub{ [] },
);

has _page => (
    is       => 'rw',
    init_arg => undef,
    default  => 0,
);

has _last_page => (
    is       => 'rw',
    init_arg => undef,
    default  => 0,
);

=head2 next_page

    while (my $records = $paginator->next_page()) { ... }

Returns an array ref of records for the next page.

=cut

sub next_page {
    my ($self) = @_;

    return if $self->_last_page();

    my $page     = $self->_page() + 1;
    my $params   = $self->params();
    my $per_page = $params->{per_page} || 20;

    $params = {
        %$params,
        page     => $page,
        per_page => $per_page,
    };

    my $method = $self->method();
    my $records = $self->api->$method(
        @{ $self->args() },
        $params,
    );

    croak("The $method method returned a non array ref value")
        if ref($records) ne 'ARRAY';

    $self->_page( $page );
    $self->_last_page( 1 ) if @$records < $per_page;
    $self->_records( [ @$records ] );

    return if !@$records;

    return $records;
}

=head2 next

    while (my $record = $paginator->next()) { ... }

Returns the next record in the current page.  If all records have
been exhausted then L</next_page> will automatically be called.
This way if you want to ignore pagination you can just call C<next>
over and over again to walk through all the records.

=cut

sub next {
    my ($self) = @_;

    my $records = $self->_records();
    return shift(@$records) if @$records;

    return if $self->_last_page();

    $self->next_page();

    $records = $self->_records();
    return shift(@$records) if @$records;

    return;
}

=head2 all

    my $records = $paginator->all();

This is just an alias for calling L</next_page> over and over
again to build an array ref of all records.

=cut

sub all {
    my ($self) = @_;

    $self->reset();

    my @records;
    while (my $page = $self->next_page()) {
        push @records, @$page;
    }

    return \@records;
}

=head2 reset

    $paginator->reset();

Reset the paginator back to its original state on the first page
with no records retrieved yet.

=cut

sub reset {
    my ($self) = @_;
    $self->_records( [] );
    $self->_page( 0 );
    $self->_last_page( 0 );
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

