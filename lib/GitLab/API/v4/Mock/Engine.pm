package GitLab::API::v4::Mock::Engine;
our $VERSION = '0.26';

=encoding utf8

=head1 NAME

GitLab::API::v4::Mock::Engine - Mocking the internals of a GitLab server.

=head1 SYNOPSIS

    use GitLab::API::v4::Mock::Engine;
    
    my $engine = GitLab::API::v4::Mock::Engine->new();
    
    my $user = $engine->create_user({
        email    => $email,
        username => $username,
        name     => $name,
        ...,
    });
    
    print "User created with ID: $user->{id}\n";

=head1 DESCRIPTION

This module provides the tooling to run a mock of the internal state
of a GitLab server.

At this time very little is validated.  For example, when you
create a user with L</create_user> there is no logic which double
checks that you specify the required C<email> field or that you
don't put in fields that are unexpected.

=cut

use Moo;
use strictures 2;
use namespace::clean;

=head1 ATTRIBUTES

=head2 next_ids

    my $ids = $engine->next_ids();

A hash reference containing object types to the next ID.

Used by L</next_id_for>.

=cut

has next_ids => (
    is       => 'ro',
    init_arg => undef,
    default  => sub{ {} },
);

=head2 users

    my $users = $engine->users();
    foreach my $user (@$users) { ... }

Returns the full array reference of all users hash references.

=cut

has users => (
    is       => 'ro',
    init_arg => undef,
    default  => sub{ [] },
);

=head1 METHODS

=head2 next_id_for

    my $id = $engine->next_id_for( 'user' );

Given an object type this will return the next unused ID.

=cut

sub next_id_for {
    my ($self, $for) = @_;

    my $next_id = $self->next_ids->{$for} || 1;
    $self->next_ids->{$for} = $next_id + 1;

    return $next_id;
}

=head1 USER METHODS

=head2 user

    my $user = $engine->user( $id );

Returns a user hash reference for the given ID.

If no user is found with the ID then C<undef> is returned.

=cut

sub user {
    my ($self, $id) = @_;

    foreach my $user (@{ $self->users() }) {
        return $user if $user->{id} == $id;
    }

    return undef;
}

=head2 create_user

    my $user = $engine->create_user( $user );
    my $id = $user->{id};

Takes a user hash reference, sets the C<id> field, and stores it in
L</users>.

Returns the updated user hash reference.

=cut

sub create_user {
    my ($self, $user) = @_;

    $user->{id} = $self->next_id_for( 'user' );
    push @{ $self->users() }, $user;

    return $user;
}

=head2 update_user

    my $user = $engine->update_user( $id, $new_user_data );

Takes the ID of the user to update and a hash reference of fields
to update.

Returns the updated user hash reference.

=cut

sub update_user {
    my ($self, $id, $data) = @_;

    my $user = $self->user( $id );
    return undef if !$user;

    %$user = (
        %$user,
        %$data,
    );

    return $user;
}

=head2 delete_user

    my $user = $engine->delete_user( $id );

Deletes the user with the specified ID from L</users>.

If no user is found with the ID then C<undef> is returned.
Otherwise the user hash reference is returned.

=cut

sub delete_user {
    my ($self, $id) = @_;

    my $users = $self->users();

    my @new;
    my $found_user;
    foreach my $user (@$users) {
        if ($user->{id} == $id and !$found_user) {
            $found_user = $user;
            next;
        }
        push @new, $user;
    }

    return undef if !$found_user;

    @$users = @new;

    return $found_user;
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

