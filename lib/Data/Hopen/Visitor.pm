# Data::Hopen::Visitor - abstract interface for a visitor.
package Data::Hopen::Visitor;
use strict;
use Data::Hopen::Base;

our $VERSION = '0.000020';

use Class::Tiny;

# Docs {{{1

=head1 NAME

Data::Hopen::Visitor - Abstract base class for DAG visitors

=head1 SYNOPSIS

This is an abstract base class for visitors provided to
L<Data::Hopen::G::Dag/run>.

=cut

# }}}1

=head1 FUNCTIONS

=head2 visit

Process a L<Data::Hopen::G::Node> or L<Data::Hopen::G::Goal>.

Called after the node runs.  Invoked as:

    $visitor->visit($node, $type, $node_inputs, \@predecessors);

Any return value of C<visit()> is ignored.  Before this function is called,
C<< $goal->outputs >> (L<Data::Hopen::G::Node/outputs>) is set to the hashref
of outputs produced by running that node.

Input parameters are:

=over

=item C<$node>

The goal node

=item C<$type>

Either C<'goal'> for goals or C<'node'> for non-goals

=item C<$node_inputs>

A L<Data::Hopen::Scope> of the inputs given to C<< $node->run >> just before
the visitor was called.  (Note that the node's outputs are cached in
C<< $node->outputs >>, which the visitor is allowed to change.)

=item C<\@predecessors>

An arrayref of C<$node>'s predecessors in the DAG.

=back

(If you need to use C<$node_inputs> or C<@predecessors>, open an issue so we
can consider adding a cleaner API for your use case.)

=cut

sub visit { ... }

1;
__END__
# vi: set fdm=marker: #
