use strictures 1;

use YAML::XS qw();
use Data::Dumper;
use Path::Tiny;

my $dir = path('data');
my $header = path('header.pm')->slurp();
my $footer = path('footer.pm')->slurp();

print $header;

foreach my $file (sort $dir->children()) {
    next if $file !~ m{\.yml$};

    my $data = YAML::XS::Load( $file->slurp() );

    my $header = $file->basename();
    $header =~ s{\.yml$}{};
    $header =~ s{_}{ }g;
    $header = uc( $header );
    print "=head1 $header METHODS\n\n";

    foreach my $endpoint (@$data) {
        my ($sub) = keys( %$endpoint );
        my $spec = $endpoint->{$sub};

        my ($return, $method, $path, $params_ok);
        if ($spec =~ m{^(?:(\S+) = |)(GET|POST|PUT|DELETE) (\S+?)(\??)$}) {
            ($return, $method, $path, $params_ok) = ($1, $2, $3, $4);
        }
        else {
            die "Invalid spec ($sub): $spec";
        }

        print "=head2 $sub\n\n";
        print '    ';

        print "my \$$return = " if $return;

        print "\$api->$sub(";

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

        print "Sends a C<$method> request to C<$path>";
        print " and returns the decoded/deserialized response body" if $return;
        print ".\n\n=cut\n\n";

        print "sub $sub {\n";
        print "    my \$self = shift;\n";

        if (@args) {
            my $min_args = @args;
            my $max_args = @args;
            $min_args-- if $params_ok;

            if ($min_args == $max_args) {
                print "    croak '$sub must be called with $min_args arguments' if \@_ != $min_args;\n";
            }
            else {
                print "    croak '$sub must be called with $min_args to $max_args arguments' if \@_ < $min_args or \@_ > $max_args;\n";
            }

            my $i = 0;
            foreach my $arg (@args) {
                my $is_params = ($params_ok and $i==$#args) ? 1 : 0;
                if ($is_params) {
                    print "    croak 'The last argument ($arg) to $sub must be a hash ref' if defined(\$_[$i]) and ref(\$_[$i]) ne 'HASH';\n";
                }
                else {
                    my $number = $i + 1;
                    print "    croak 'The #$number argument ($arg) to $sub must be a scalar' if ref(\$_[$i]) or (!defined \$_[$i]);\n";
                }
                $i ++;
            }
        }
        else {
            print "    croak \"The $sub method does not take any arguments\" if \@_;\n";
        }

        print "    my \$params = pop;\n" if $params_ok;

        my $sprintf_path = $path;
        $sprintf_path =~ s{:[^/]+}{%s}g;
        print "    my \$path = sprintf('$sprintf_path', (map { uri_escape(\$_) } \@_));\n";

        my $method_sub = lc( $method );
        print '    ';
        print 'return ' if $return;
        print "\$self->$method_sub( \$path";
        print ", ( defined(\$params) ? \$params : () )" if $params_ok;
        print " );\n";
        print "    return;\n" if !$return;
        print "}\n\n";
    }
}

print $footer;
