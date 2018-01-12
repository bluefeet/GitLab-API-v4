requires 'strictures' => '2.000003';
requires 'namespace::clean' => '0.27';

requires 'Moo' => '2.003000';
requires 'Types::Standard' => '1.002001';
requires 'Types::Common::String' => '1.002001';
requires 'Types::Common::Numeric' => '1.002001';

requires 'Role::REST::Client' => '0.22';
requires 'Const::Fast' => '0.014';
requires 'URI::Escape' => '1.72';
requires 'Log::Any' => '1.703';
requires 'Try::Tiny' => '0.28';

requires 'Carp' => 0;
requires 'Exporter' => 0;
requires 'Data::Dumper' => 0;

# Used exclusively by gitlab-api-v4 and/or GitLab::API::v4::Config.
requires 'Getopt::Long' => 0;
requires 'Pod::Usage' => 0;
requires 'Log::Any::Adapter' => '1.703';
requires 'Log::Any::Adapter::Screen' => '0.13';
requires 'JSON' => '2.92';
requires 'Path::Tiny' => '0.079';
requires 'IO::Prompter' => '0.004014';

on test => sub {
    requires 'Test2::V0' => '0.000094';
    requires 'Log::Any::Adapter::TAP' => '0.003003';
};
