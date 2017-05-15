
sub raw_snippet {
    my $self = shift;
    warn "The raw_snippet method is deprecated, please use the snippet_content method instead";
    return $self->snippet_content( @_ );
}

1;
__END__

=head1 SEE ALSO

L<Net::Gitlab> purports to provide an interface to the GitLab API, but
it is hard to tell due to a complete lack of documentation via either
POD or unit tests.

=head1 CONTRIBUTING

This module is auto-generated from a set of YAML files defining the
interface of GitLab's API.  If you'd like to contribute to this module
then please feel free to make a
L<fork on GitHub|https://github.com/bluefeet/GitLab-API-v3>
and submit a pull request, just make sure you edit the files in the
C<authors/> directory instead of C<lib/GitLab/API/v3.pm> directly.

Please see
L<https://github.com/bluefeet/GitLab-API-v3/blob/master/author/README.pod>
for more information.

Alternatively, you can
L<open a ticket|https://github.com/bluefeet/GitLab-API-v3/issues>.

=head1 AUTHOR

Aran Clary Deltac <bluefeetE<64>gmail.com>

=head2 CONTRIBUTORS

=over

=item *

Dotan Dimet <dotanE<64>corky.net>

=item *

Nigel Gregoire <nigelgregoireE<64>gmail.com>

=item *

trunov-ms <trunov.msE<64>gmail.com>

=item *

Marek R. Sotola <Marek.R.SotolaE<64>nasa.gov>

=item *

José Joaquín Atria <jjatriaE<64>gmail.com>

=item *

Dave Webb <githubE<64>d5ve.com>

=back

=head1 ACKNOWLEDGEMENTS

Thanks to L<ZipRecruiter|https://www.ziprecruiter.com/>
for encouraging their employees to contribute back to the open
source ecosystem.  Without their dedication to quality software
development this distribution would not exist.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

