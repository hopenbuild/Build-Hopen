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

# TODO merge visit_goal and visit_node into visit(node|goal => $node)
#Process a L<Data::Hopen::G::Node> or L<Data::Hopen::G::Goal>.

=head1 FUNCTIONS

=head2 visit_goal

Process a L<Data::Hopen::G::Goal>.

Called after the node runs.  Invoked as:

    $visitor->visit_goal($goal, \@predecessors);

where C<$goal> is the goal node and C<@predecessors> is a list of that node's
predecessors in the DAG.

Before this is called, C<< $goal->outputs >> (L<Data::Hopen::G::Node/outputs>)
is set to the hashref of outputs produced by running that node.

Any return value of C<visit_goal()> is ignored.

=cut

sub visit_goal { ... }

=head2 visit_node

Process a graph node that is not a C<Data::Hopen::G::Goal>.  All other details
are the same as

=cut

sub visit_node { ... }

1;
__END__
# vi: set fdm=marker: #
