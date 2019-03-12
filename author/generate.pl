#!/usr/bin/env perl
use strictures 1;

use YAML::XS qw();
use Data::Dumper;
use Path::Tiny;

my $dir = path('sections');
my $header = path('header.pm')->slurp();
my $footer = path('footer.pm')->slurp();
my $config = YAML::XS::Load( path('config.yml')->slurp() );

print $header;

print "=head1 API METHODS\n\n";

foreach my $section_pack (@{ $config->{sections} }) {
foreach my $section_name (keys %$section_pack) {
    my $section = $section_pack->{$section_name};

    my $file = $dir->child("$section_name.yml");
    my $endpoints = YAML::XS::Load( $file->slurp() );

    print "=head2 $section->{head}\n\n";
    print "See L<$section->{doc_url}>.\n\n";
    print "=over\n\n";

    foreach my $endpoint (@$endpoints) {
        if (keys(%$endpoint) == 1) {
            my ($method) = keys %$endpoint;
            $endpoint = {
                method => $method,
                spec   => $endpoint->{$method},
            };
        }

        my $method = $endpoint->{method};
        my $spec = $endpoint->{spec};

        my ($return, $verb, $path, $params_ok);
        if ($spec =~ m{^(?:(\S+) = |)(GET|POST|PUT|DELETE) ([^/\s]\S*?[^/\s]?)(\??)$}) {
            ($return, $verb, $path, $params_ok) = ($1, $2, $3, $4);
        }
        else {
            die "Invalid spec ($method): $spec";
        }

        my $no_decode = 0;
        $no_decode = 1 if !$return;
        $no_decode = 1 if $endpoint->{no_decode};

        print "=item $method\n\n";
        print '    ';

        print "my \$$return = " if $return;

        print "\$api->$method(";

        my @args = (
            map { ($_ =~ m{^:(.+)$}) ? "\$$1" : () }
            split(m{/}, $path)
        );

        push @args, '\%params' if $params_ok;

        if (@args) {
            print "\n" . join('',
                map { "        $_,\n" }
                @args
            );
            print '    ';
        }

        print ");\n\n";

        print "Sends a C<$verb> request to C<$path>";
        print ' and returns the ' . ($no_decode ? 'raw' : 'decoded') . ' response content' if $return;
        print ".\n\n";
        print "$endpoint->{note}\n" if $endpoint->{note};
        print "=cut\n\n";

        print "sub $method {\n";
        print "    my \$self = shift;\n";

        if (@args) {
            my $min_args = @args;
            my $max_args = @args;
            $min_args-- if $params_ok;

            if ($min_args == $max_args) {
                print "    croak '$method must be called with $min_args arguments' if \@_ != $min_args;\n";
            }
            else {
                print "    croak '$method must be called with $min_args to $max_args arguments' if \@_ < $min_args or \@_ > $max_args;\n";
            }

            my $i = 0;
            foreach my $arg (@args) {
                my $is_params = ($params_ok and $i==$#args) ? 1 : 0;
                if ($is_params) {
                    print "    croak 'The last argument ($arg) to $method must be a hash ref' if defined(\$_[$i]) and ref(\$_[$i]) ne 'HASH';\n";
                }
                else {
                    my $number = $i + 1;
                    print "    croak 'The #$number argument ($arg) to $method must be a scalar' if ref(\$_[$i]) or (!defined \$_[$i]);\n";
                }
                $i ++;
            }

            print "    my \$params = (\@_ == $max_args) ? pop() : undef;\n" if $params_ok;
        }
        else {
            print "    croak \"The $method method does not take any arguments\" if \@_;\n";
        }

        print "    my \$options = {};\n";
        print "    \$options->{decode} = 0;\n" if $no_decode;

        if ($params_ok) {
            my $params_key = ($verb eq 'GET' or $verb eq 'HEAD') ? 'query' : 'content';
            print "    \$options->{$params_key} = \$params if defined \$params;\n";
        }

        print '    ';
        print 'return ' if $return;
        print "\$self->_call_rest_client( '$verb', '$path', [\@_], \$options );\n";
        print "    return;\n" if !$return;
        print "}\n\n";
    }

    print "=back\n\n";
}}

print "=cut\n\n";

print $footer;
