requires 'perl' => '5.010001';

# Common modules.
requires 'Moo' => '2.003000';
requires 'strictures' => '2.000003';
requires 'namespace::clean' => '0.27';
requires 'Types::Standard' => '1.002001';
requires 'Types::Common::String' => '1.002001';
requires 'Types::Common::Numeric' => '1.002001';
requires 'Log::Any' => '1.703';
requires 'Carp' => 0;
requires 'JSON' => '2.59';

# Used by GitLab::API::v4::RESTClient.
requires 'HTTP::Tiny' => '0.059';
requires 'HTTP::Tiny::Multipart' => '0.05';
requires 'URI' => '1.62';
requires 'URI::Escape' => '1.72';

# Used by GitLab::API::v4::Constants.
requires 'Const::Fast' => '0.014';
requires 'Exporter' => 0;

# Used by gitlab-api-v4 and/or GitLab::API::v4::Config.
requires 'Try::Tiny' => '0.28';
requires 'Getopt::Long' => 0;
requires 'Pod::Usage' => 0;
requires 'Log::Any::Adapter' => '1.703';
requires 'Log::Any::Adapter::Screen' => '0.13';
requires 'Path::Tiny' => '0.079';
requires 'IO::Prompter' => '0.004014';

on test => sub {
    requires 'Test2::V0' => '0.000094';
    requires 'Log::Any::Adapter::TAP' => '0.003003';
    requires 'MIME::Base64' => '3.15';
};
