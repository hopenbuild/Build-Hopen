# Data::Hopen::G::Node - base class for hopen nodes
package Data::Hopen::G::Node;
use Data::Hopen qw(:default explainvar);
use strict;
use Data::Hopen::Base;

our $VERSION = '0.000020'; # TRIAL

use parent 'Data::Hopen::G::Runnable';

use Class::Tiny::ConstrainedAccessor outputs => [
    sub { ref $_[0] eq 'HASH' },
    sub { "Need hashref, not @{[explainvar $_[0]]}" },
];

use Class::Tiny {
    outputs => sub { +{} },
};

=head1 NAME

Data::Hopen::G::Node - A graph node

=head1 DESCRIPTION

A graph node is runnable and stores its outputs.

=head1 VARIABLES

=head2 outputs

Hashref of the outputs from the last time this node was run.  Default C<{}>.

=cut

1;
__END__
# vi: set fdm=marker: #
