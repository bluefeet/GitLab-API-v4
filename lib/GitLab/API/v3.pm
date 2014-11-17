package GitLab::API::v3;

=head1 NAME

GitLab::API::v3 - GitLab API v3 client.

=head1 SYNOPSIS

    use GitLab::API::v3;
    
    my $api = GitLab::API::v3->new(
        url   => $v3_api_url,
        token => $token,
    );
    
    my $branches = $api->branches( $project_id );

=head1 DESCRIPTION

This module provides a one-to-one interface with the GitLab
API v3.  Little is documented here as it would just be duplicating
GitLab's own L<API Documentation|http://doc.gitlab.com/ce/api/README.html>.

Currently only the branches set of API handlers is supported.  More
are coming shortly (release early, release often).

=cut

use GitLab::API::v3::RESTClient;

use Type::Params qw( compile );
use Types::Standard qw( -types slurpy );
use Types::GitLab -types;
use Types::Git -types;

use Moo;
use strictures 1;
use namespace::clean;

=head1 REQUIRED ARGUMENTS

=head2 url

The URL to your v3 API endpoint.  Typically this will be something
like C<http://git.example.com/api/v3>.

=cut

has url => (
    is       => 'ro',
    isa      => GitLabAPIURI,
    coerce   => 1,
    required => 1,
);

=head2 token

A GitLab API token.

=cut

has token => (
    is       => 'ro',
    isa      => GitLabToken,
    required => 1,
);

=head1 OPTIONAL ARGUMENTS

=head2 rest_client

An instance of C<GitLab::API::v3::RESTClient>.  Typically you will not
be setting this as it defaults to a new instance and customization
should not be necessary.

=cut

has rest_client => (
    is      => 'lazy',
    isa     => InstanceOf[ 'GitLab::API::v3::RESTClient' ],
    handles => [qw( post get head put delete options )],
);
sub _build_rest_client {
    my ($self) = @_;

    my $rest = GitLab::API::v3::RESTClient->new(
        server => '' . $self->url(),
        type   => 'application/json',
    );

    $rest->set_persistent_header(
        'PRIVATE-TOKEN' => $self->token(),
    );

    return $rest;
}

=head1 BRANCH METHODS

=head2 branches

    my $branches = $api->branches( $project_id );

Returns an array ref of branch hash refs.

=cut

{
    my $check = compile(
        Object,
        GitLabProjectID,
    );

    sub branches {
        my ($self, $project_id) = $check->(@_);
        return $self->get("/projects/$project_id/repository/branches");
    }
}

=head2 branch

    my $branch = $api->branch( $project_id, $branch_name );

Returns a branch hash ref.

=cut

{
    my $check = compile(
        Object,
        GitLabProjectID,
        GitLooseRef,
    );

    sub branch {
        my ($self, $project_id, $branch_name) = $check->(@_);
        return $self->get("/projects/$project_id/repository/branches/$branch_name");
    }
}

=head2 protect_branch

    $api->protect_branch( $project_id, $branch_name );

Marks a branch as protected.

=cut

{
    my $check = compile(
        Object,
        GitLabProjectID,
        GitLooseRef,
    );

    sub protect_branch {
        my ($self, $project_id, $branch_name) = $check->(@_);
        return $self->put("/projects/$project_id/repository/branches/$branch_name/protect");
    }
}

=head2 unprotect_branch

    $api->unprotect_branch( $project_id, $branch_name );

Marks a branch as not protected.

=cut

{
    my $check = compile(
        Object,
        GitLabProjectID,
        GitLooseRef,
    );

    sub unprotect_branch {
        my ($self, $project_id, $branch_name) = $check->(@_);
        return $self->put("/projects/$project_id/repository/branches/$branch_name/unprotect");
    }
}

=head2 create_branch

    my $branch = $api->create_branch(
        $project_id,
        branch_name => $branch_name,
        ref         => $ref,
    );

Creates a branch and returns the hash ref for it.

=cut

{
    my $check = compile(
        Object,
        GitLabProjectID,
        slurpy Dict[
            branch_name => GitLooseRef,
            ref         => GitObject,
        ],
    );

    sub create_branch {
        my ($self, $project_id, $params) = $check->(@_);
        return $self->post("/projects/$project_id/repository/branches", $params);
    }
}

=head2 delete_branch

    $api->delete_branch(
        $project_id,
        $branch_name,
    );

Deletes the specified branch.

=cut

{
    my $check = compile(
        Object,
        GitLabProjectID,
        GitLooseRef,
    );
    sub delete_branch {
        my ($self, $project_id, $branch_name) = $check->(@_);
        return $self->delete("/projects/$project_id/repository/branches/$branch_name");
    }
}

1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeet@gmail.com>

=head1 ACKNOWLEDGEMENTS

Thanks to L<ZipRecruiter|https://www.ziprecruiter.com/>
for encouraging their employees to contribute back to the open
source ecosystem.  Without their dedication to quality software
development this distribution would not exist.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

