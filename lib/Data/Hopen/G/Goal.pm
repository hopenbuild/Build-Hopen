# Data::Hopen::G::Goal - A named build goal
package Data::Hopen::G::Goal;
use strict;
use Data::Hopen::Base;

our $VERSION = '0.000020';

use parent 'Data::Hopen::G::Node';
use Class::Tiny {
    should_output => true,      # if true, forward the goal's inputs as
};

use Data::Hopen;
use Data::Hopen::Util::Data qw(fwdopts);

# Docs {{{1

=head1 NAME

Data::Hopen::G::Goal - a named target in a dataflow graph

=head1 SYNOPSIS

A C<Goal> is a named target, e.g., C<doc>, C<dist>, or C<all>.  Goals usually
appear at the end of a dataflow path in a L<Data::Hopen::G::DAG>, but this is
not required --- Goal nodes can appear anywhere in the graph.

=head1 ATTRIBUTES

=head2 should_output

Boolean, default true.  If false, the goal's outputs are always C<{}> (empty).
If true, the goal's inputs are passed through as outputs.

=head1 FUNCTIONS

=head2 _run

Passes through the inputs if L</should_output> is set.

=cut

# }}}1

sub _run {
    my ($self, %args) = getparameters('self', [qw(; visitor graph)], @_);
    hlog { Goal => $self->name, ($self->should_output ? 'with' : 'without'),
            'outputs' };

    return {} unless $self->should_output;

    return $self->passthrough(-nocontext=>1, -levels => 'local',
            fwdopts(%args, [qw[visitor]]));
} #_run()

=head2 BUILD

Enforce the requirement for a user-specified name.

=cut

sub BUILD {
    my ($self, $args) = @_;
    croak 'Goals must have names' unless $self->has_custom_name;
} #BUILD()

1;
__END__
# vi: set fdm=marker: #
