requires 'Moo' => 1.006000;
requires 'Role::REST::Client' => 0.20;
requires 'Type::Tiny' => 1;
requires 'strictures' => 0;
requires 'namespace::clean' => 0;
requires 'Const::Fast' => 0;
requires 'URI::Escape' => 0;
requires 'Log::Any' => 0.11;
requires 'Log::Any::Adapter' => 0;
requires 'Log::Any::Adapter::Screen' => 0;
requires 'Try::Tiny' => 0;
requires 'Data::Serializer' => 0;
requires 'YAML' => 0;
requires 'Getopt::Long' => 0;
requires 'Pod::Usage' => 0;

on test => sub {
    requires 'Test::Simple' => 0.94;
    requires 'Log::Any::Adapter::TAP' => 0.2.0;
};
