# Data::Hopen::Util::MergeWithoutCloneBlessed - Hash::Merge, but without
# cloning blessed references.
package Data::Hopen::Util::MergeWithoutCloneBlessed;
use strict;
use warnings;
use 5.014;
use Carp qw(croak);

our $VERSION = '0.000015';

use base 'Hash::Merge';     # since `base` is what Hash::Merge uses
use Clone::Choose 0.008;    # also from Hash::Merge

use Scalar::Util qw(blessed);

# Docs {{{1

=head1 NAME

Data::Hopen::Util::MergeWithoutCloneBlessed - Hash::Merge without cloning blessed references

=head1 SYNOPSIS

This is L<Hash::Merge>, but modified so that, under the default behaviour,
blessed references will not be cloned.  Non-blessed references, e.g.,
hashrefs or arrayrefs, will be cloned.

=head1 FUNCTIONS

=cut

# }}}1

=head2 merge

Do the merge.  Copied and modified from L<Hash::Merge/merge>.

=cut

sub merge {
    my $self = shift or croak 'Need an instance';

    my ($left, $right) = @_;
    print "Merging:\n<<<\n$left\n>>>\n$right\n---\n" =~ s/^/# /gmr;

    # For the general use of this module, we want to create duplicates
    # of all data that is merged.  This behavior can be shut off, but
    # can create havoc if references are used heavily.

    my $lefttype = ref($left);
    $lefttype = "SCALAR" unless defined $lefttype and defined $self->{'matrix'}->{$lefttype};

    my $righttype = ref($right);
    $righttype = "SCALAR" unless defined $righttype and defined $self->{'matrix'}->{$righttype};

    if ($self->{'clone'})
    {
        # TODO this clone() call will clone blessed references inside
        # $left or $right, so this module doesn't work yet.
        $left  = (ref($left) && !blessed($left))   ? clone($left)  : $left;
        $right = (ref($right) && !blessed($right)) ? clone($right) : $right;
    }

    local $Hash::Merge::CONTEXT = $self;
    return $self->{'matrix'}->{$lefttype}{$righttype}->($left, $right);
} #merge()

1;
# Rest of the docs {{{1
__END__

=head1 AUTHOR

Modifications made by Christopher White C<< <cxwembedded@gmail.com> >>.

=head1 LICENSE

Modifications copyright (c) 2019 Christopher White.

This library is free software.  You can redistribute it and/or modify it
under the same terms as Perl itself.

This code is modified from the original version of L<Hash::Merge> by
adding checks to not clone blessed references.

=cut

# }}}1
# vi: set fdm=marker: #
