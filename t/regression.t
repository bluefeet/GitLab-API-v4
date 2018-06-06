#!/usr/bin/env perl
use strictures 2;

use Test2::V0;
use Test2::Require::AuthorTesting;

use Log::Any::Adapter 'TAP';
use Path::Tiny;

use GitLab::API::v4;
use GitLab::API::v4::Config;

my $config = GitLab::API::v4::Config->new();
my $api = GitLab::API::v4->new( $config->args() );

subtest projects => sub{
    my $stamp = time();
    my $project_name = "gitlab-api-v4-test-$stamp";

    my $created_project = $api->create_project(
        { name=>$project_name },
    );
    ok( $created_project, 'project created' );

    my $project_id = $created_project->{id};
    my $project = $api->project( $project_id );
    ok( $project, 'project found' );

    subtest upload_file_to_project => sub{
        my $file = Path::Tiny->tempfile( SUFFIX => '.txt' );
        my $file_content = 'Hello GitLab, this is a test of ' . ref($api) . '.';
        $file->spew( $file_content );

        my $upload = $api->upload_file_to_project(
            $project_id,
            { file=>"$file" },
        );
        ok( $upload->{url}, 'got an upload response' );

        my $download_url = URI->new( $api->url() );
        my $site_path = $download_url->path();
        $site_path =~ s{/api/v4/?$}{};
        my $project_path = $project->{path_with_namespace};
        my $upload_path = $upload->{url};
        $download_url->path( join_paths( $site_path, $project_path, $upload_path ) );

        my $res = HTTP::Tiny->new->get(
            $download_url,
            { headers=>$api->_auth_headers() },
        );
        is( $res->{content}, $file_content, 'upload_file_to_project worked' );
    };

    subtest hooks => sub{
        my $hook = $api->create_project_hook(
            $project->{id},
            { url=>'http://example.com/gitlab-hook-1' },
        );
        ok( $hook, 'create_project_hook returned the hook' );

        $hook = $api->edit_project_hook(
            $project->{id}, $hook->{id},
            { url=>'http://example.com/gitlab-hook-2' },
        );
        ok( $hook, 'edit_project_hook returned the hook' );
        my $hook_id = $hook->{id};

        $hook = $api->project_hook( $project->{id}, $hook_id );
        ok( $hook, 'project_hook returned the hook' );
        is( $hook->{url}, 'http://example.com/gitlab-hook-2', 'hook looks right' );

        $api->delete_project_hook( $project->{id}, $hook_id );
        $hook = $api->project_hook( $project->{id}, $hook_id );
        ok( (!$hook), 'delete_project_hook seems to have worked' );

        like(
            dies { $api->delete_project_hook( $project->{id}, $hook_id ) },
            qr{\b404\b},
            'a subsequent delete_project_hook throws',
        );
    };

    $api->delete_project( $project_id );
    pass 'project deleted';
};

subtest users => sub{
    my $stamp = time();
    my $username = "gitlab-api-v4-test-$stamp";
    $api->create_user({
        username   => $username,
        email      => "$username\@example.com",
        password   => 'd5fzHF7tfgh',
        name       => 'GitLabAPIv4 Test',
    });
    pass 'user created';

    my $users = $api->users({ username => $username });
    is( @$users+0, 1, 'one user found' );

    my $user = shift @$users;
    is( $user->{username}, $username, 'user has correct username' );
    die 'Incorrect user found' if $user->{username} ne $username;

    my $user_id = $user->{id};
    ok( $api->block_user($user_id), 'user blocked' );
    ok( (!$api->block_user($user_id)), 'user cannot be blocked again' );
    ok( $api->unblock_user($user_id), 'user unblocked' );
    ok( (!$api->unblock_user($user_id)), 'user cannot be unblocked again' );

    $api->delete_user($user_id);
    pass 'user deleted';
};

subtest failures => sub{
    is( $api->user( 12345678 ), undef, 'GETing an unknown entity returns undef' );
    my $err_re = qr{^Error PUTing \S+/users/12345678 \(HTTP 404\): Not Found \{"message":"404 User Not Found"\}};
    like( dies{ $api->edit_user( 12345678, {} ) }, $err_re, 'POSTing an unknown entity throws a specific exception' );
};

done_testing;

sub join_paths {
    my @paths = @_;

    return() if !@paths;
    return @paths if @paths==1;

    my $first = shift @paths;
    $first =~ s{/$}{};

    my $last = pop @paths;
    $last =~ s{^/}{};

    @paths = (
        map { $_ =~ s{^/?(.*?)/?$}{$1}; $_ }
        @paths
    );

    return join('/', $first, @paths, $last);
}
