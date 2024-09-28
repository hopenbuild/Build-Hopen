# Data::Hopen::G::DAG - hopen build graph
package Data::Hopen::G::DAG;
use strict;
use Data::Hopen::Base;

our $VERSION = '0.000021';

use parent 'Data::Hopen::G::Op';
use Class::Tiny {
    goals   => sub { [] },
    default_goal => undef,
    winner => undef,

    # Private attributes with simple defaults
    #_node_by_name => sub { +{} },   # map from node names to nodes in either
    #                                # _init_graph or _graph

    # Private attributes - initialized by BUILD()
    _graph  => undef,   # L<Data::Hopen::OrderedPredecessorGraph> instance
    _final   => undef,  # The graph sink - all goals have edges to this

    #Initialization operations
    _init_graph => undef,   # L<Data::Hopen::OrderedPredecessorGraph>
                            # for initializations
    _init_first => undef,   # Graph node for initialization - the first
                            # init operation to be performed.

    # TODO? also support fini to run operations after _graph runs?
};

use Data::Hopen qw(hlog getparameters *QUIET);
use Data::Hopen::G::Goal;
use Data::Hopen::G::Link;
use Data::Hopen::G::Node;
use Data::Hopen::G::CollectOp;
use Data::Hopen::Util::Data qw(forward_opts);
use Data::Hopen::OrderedPredecessorGraph;
use Getargs::Mixed; # parameters, which doesn't permit undef
use Hash::Merge;
use Regexp::Assemble;
use Scalar::Util qw(refaddr);
use Storable ();

# Class data {{{1

use constant {
    LINKS => 'link_list',    # Graph edge attr: array of DHG::Link instances
};

# A counter used for making unique names
my $_id_counter = 0;    # threads: make shared

# }}}1
# Docs {{{1

=head1 NAME

Data::Hopen::G::DAG - A hopen build graph

=head1 SYNOPSIS

This class encapsulates the DAG for a particular set of one or more goals.
It is itself a L<Data::Hopen::G::Op> so that it can be composed into
other DAGs.

=head1 ATTRIBUTES

=head2 goals

Arrayref of the goals for this DAG.

=head2 default_goal

The default goal for this DAG.

=head2 winner

When a node has multiple predecessors, their outputs are combined using
L<Hash::Merge> to form the input to that node.  This sets the C<Hash::Merge>
precedence.  Valid values (case-insensitive) are:

=over

=item C<undef> or C<'combine'>

(the default): L<Hash::Merge/Retainment Precedence>.  Same-name keys
are merged, so no data is lost.

=item C<'first'> or C<'keep'>

L<Hash::Merge/Left Precedence>.  The first predecessor to add a value
under a particular key will win.

=item C<'last'> or C<'replace'>

L<Hash::Merge/Right Precedence>.  The last predecessor to add a value
under a particular key will win.

=back

=head2 _graph

The actual L<Graph>.  If you find that you have to use it, please open an
issue so we can see about providing a documented API for your use case!

=head2 _final

The node to which all goals are connected.

=head2 _init_graph

A separate L<Graph> of operations that will run before all the operations
in L</_graph>.  This is because I don't want to add an edge to every
single node just to force the topological sort to work out.

=head2 _init_first

The first node to be run in _init_graph.

=head1 FUNCTIONS

=cut

# }}}1

=head2 _run

Traverses the graph.  The DAG is similar to a subroutine in this respect.  The
outputs from all the goals of the DAG are aggregated and provided as the
outputs of the DAG.  The output is a hash keyed by the name of each goal, with
each goal's outputs as the values under that name.  Usage:

    my $hrOutputs = $dag->run([-context=>$scope][, other options])

C<$scope> must be a L<Data::Hopen::Scope> or subclass if provided.
Other options are as L<Data::Hopen::G::Runnable/run>.

When evaluating a node, the edges from its predecessors are traversed in
the order those predecessors were added to the graph.

=cut

# The implementation of run().  $self->scope has already been linked to the context.
sub _run {
    my ($self, %args) = getparameters('self', [qw(; visitor)], @_);
    my $retval = {};

    # --- Get the initialization ops ---

    my @init_order = eval { $self->_init_graph->toposort };
    die "Initializations contain a cycle!" if $@;
    @init_order = () if $self->_init_graph->vertices == 1;  # no init nodes => skip

    # --- Get the runtime ops ---

    my @order = eval { $self->_graph->toposort };
        # TODO someday support multi-core-friendly topo-sort, so nodes can run
        # in parallel until they block each other.
    die "Graph contains a cycle!" if $@;

    # Remove _final from the order for now - I don't yet know what it means
    # to traverse _final.
    warn "Last item in order isn't _final!  This might indicate a bug in hopen, or that some graph edges are missing."
        unless $QUIET or refaddr $order[$#order] == refaddr $self->_final;

    @order = grep { refaddr $_ != refaddr $self->_final } @order;

    # --- Check for non-connected ops, and goals with no inputs ---

    unless($QUIET) {
        foreach my $node ($self->_graph->isolated_vertices) {
            warn "Node @{[$node->name]} is not connected to any other nodes";
        }

        foreach my $goal (@{$self->goals}) {
            warn "Goal @{[$goal->name]} has no inputs"
                if $self->_graph->is_predecessorless_vertex($goal);
        }
    }

    # --- Set up for the merge ---

    state $STRATEGIES = {   # regex => strategy
        '(<undef>|combine)' => 'combine',
        '(first|keep)' => 'keep',
        '(last|replace)' => 'replace',
    };
    state $STRATEGY_MAP = Regexp::Assemble->new->flags('i')->track(1)
        ->anchor_string_begin->anchor_string_end
        ->add(keys %$STRATEGIES);

    my $merge_strategy_idx = $STRATEGY_MAP->match($self->winner // '<undef>');
    die "Invalid winner value @{[$self->winner]}" unless defined $merge_strategy_idx;
    my $merge_strategy = $STRATEGIES->{$merge_strategy_idx};

    # --- Traverse ---

    # Note: while hacking, please make sure Goal nodes can appear
    # anywhere in the graph.

    hlog { my $x = 'Traversing DAG ' . $self->name; $x, '*' x (76-length($x)) };

    my $graph = $self->_init_graph;
    foreach my $node (@init_order, undef, @order) {

        if(!defined($node)) {   # undef is the marker between init and run
            $graph = $self->_graph;
            next;
        }

        # Inputs to this node.  These are different from the DAG's inputs.
        # The scope stack is (outer to inner) DAG's inputs, DAG's overrides,
        # then $node_inputs, then the individual node's overrides.
        my $node_inputs = Data::Hopen::Scope::Hash->new;
            # TODO make this a DH::Scope::Inputs once it's implemented
        $node_inputs->outer($self->scope);
            # Data specifically being provided to the current node, e.g.,
            # on input edges, beats the scope of the DAG as a whole.
        $node_inputs->local(true);
            # A CollectOp won't reach above the node's inputs by default.
        $node_inputs->merge_strategy($merge_strategy);

        # Iterate over each node's edges and process any Links
        foreach my $pred ($graph->ordered_predecessors($node)) {
            hlog { ('From', $pred->name, 'to', $node->name) };

            # Goals do not feed outputs to other Goals.  This is so you can
            # add edges between Goals to set their order while keeping the
            # data for each Goal separate.
            # TODO add tests for this.  Also TODO decide whether this is
            # actually the Right Thing!
            next if eval { $pred->DOES('Data::Hopen::G::Goal') };

            my $links = $graph->get_edge_attribute($pred, $node, LINKS);

            # Simple case (no links): predecessor's outputs become our inputs
            unless($links) {
                hlog { '  -- no links' };
                $node_inputs->merge(%{$pred->outputs});
                    # TODO specify which set these are.
                    # Use the predecessor's identity as the set.
                next;
            }

            # More complex case: Process all the links

            # Helper function to wrap a hashref in the right scope for a link input
            local *make_link_inputs = sub {
                my $hrIn = shift;
                my $scLinkInputs = Data::Hopen::Scope::Hash->new->put(%$hrIn);
                    # All links get the same outer scope --- they are parallel,
                    # not in series.
                    # TODO? use the predecessor's identity as the set.
                $scLinkInputs->outer($self->scope);
                    # The links run at the same scope level as the node.
                $scLinkInputs->local(true);
                return $scLinkInputs;
            };

            # Make the first link's input scope
            my $hrPredOutputs = $pred->outputs;
                # In one test, outputs was undef if not on its own line.
            my $scLinkInputs = make_link_inputs($hrPredOutputs);

            # Run the links in series - not parallel!
            my $hrLinkOutputs = $scLinkInputs->as_hashref(-levels=>'local');
            foreach my $link (@$links) {
                hlog { ('From', $pred->name, 'via', $link->name, 'to', $node->name) };

                $hrLinkOutputs = $link->run(
                    -context=>$scLinkInputs,
                    # visitor not passed to links.
                );
                $scLinkInputs = make_link_inputs($hrLinkOutputs);
            } #foreach incoming link

            $node_inputs->merge(%$hrLinkOutputs);
                # TODO specify which set these are.

        } #foreach predecessor node

        my $step_output = $node->run(-context=>$node_inputs,
            forward_opts(\%args, {'-'=>1}, 'visitor')
        );
        $node->outputs($step_output);

        # Give the visitor a chance, and stash the results if necessary.
        if(eval { $node->DOES('Data::Hopen::G::Goal') }) {
            $args{visitor}->visit_goal($node, $node_inputs) if $args{visitor};

            # Save the result if there is one.  Don't save {}.
            # use $node->outputs, not $step_output, since the visitor may
            # alter $node->outputs.
            $retval->{$node->name} = $node->outputs if keys %{$node->outputs};
        } else {
            $args{visitor}->visit_node($node, $node_inputs) if $args{visitor};
        }

        hlog { 'Finished node', $node->name, 'with outputs',
            Dumper $node->outputs } 10;

    } #foreach node in topo-sort order

    return $retval;
} #run()

=head1 ADDING DATA

=head2 goal

Creates a goal of the DAG.  Goals are names for sequences of operations,
akin to top-level Makefile targets.  Usage:

    my $goalOp = $dag->goal('name')

Returns the L<Data::Hopen::G::Goal> node that is the goal.  By default, any
inputs passed into a goal are provided as outputs of that goal, and are
saved as outputs of the DAG under the goal's name.

The first call to C<goal()> also sets L</default_goal>.

=cut

sub goal {
    my $self = shift or croak 'Need an instance';
    my $name = shift or croak 'Need a goal name';
    my $goal = Data::Hopen::G::Goal->new(name => $name);
    $self->_graph->add_vertex($goal);
    #$self->_node_by_name->{$name} = $goal;
    $self->_graph->add_edge($goal, $self->_final);
    $self->default_goal($goal) unless $self->default_goal;
    push @{$self->goals}, $goal;
    return $goal;
} #goal()

=head2 connect

=over 4

=item - C<< DAG:connect(<op1>, <out-edge>, <in-edge>, <op2>) >>

B<Not yet implemented>.
Connects output C<out-edge> of operation C<op1> as input C<in-edge> of
operation C<op2>.  No processing is done between output and input.
C<out-edge> and C<in-edge> can be anything usable as a table index, provided
that table index appears in the corresponding operation's descriptor.

=item - C<< DAG:connect(<op1>, <op2>) >>

Creates a dependency edge from C<op1> to C<op2>, indicating that C<op1> must be
run before C<op2>.  Does not transfer any data from C<op1> to C<op2>.

=item - C<< DAG:connect(<op1>, <Link>, <op2>) >>

Connects C<op1> to C<op2> via L<Data::Hopen::G::Link> C<Link>.
C<Link> may be undef, in which case this is treated as the two-parameter form.

If there are already link(s) on the edge from C<op1> to C<op2>, the new link
is added after the last existing link.

=back

TODO return the name of the edge?  The edge instance itself?  Maybe a
fluent interface to the DAG for chaining C<connect> calls?

TODO remove the out-edge and in-edge parameters?

=cut

sub connect {
    my $self = shift or croak 'Need an instance';
    my ($op1, $out_edge, $in_edge, $op2, $link);

    # Unpack args
    #if(@_ == 4) {
    #    ($op2, $out_edge, $in_edge, $op2) = @_;
    #} else the following
    if(@_ == 3) {
        ($op1, $link, $op2) = @_;
    } elsif(@_ == 2) {
        ($op1, $op2) = @_;
    } else {
        die "Invalid arguments";
    }

    #my $out_edge = false;      # No outputs    TODO use these?
    #my $in_edge = false;       # No inputs

    hlog { 'DAG::connect(): Edge from', $op1->name,
            'via', $link ? $link->name : '(no link)',
            'to', $op2->name };

    # Add it to the graph (idempotent)
    $self->_graph->add_edge($op1, $op2);
    # $self->_node_by_name->{$_->name} = $_ foreach ($op1, $op2);

    # Save the DHG::Link as an edge attribute (not idempotent!)
    if($link) {
        my $attrs = $self->_graph->get_edge_attribute($op1, $op2, LINKS) || [];
        push @$attrs, $link;
        $self->_graph->set_edge_attribute($op1, $op2, LINKS, $attrs);
    }

    return undef;   # TODO decide what to return
} #connect()

=head2 add

Add a regular node to the graph.  An attempt to add the same node twice will be
ignored.  Usage:

    my $node = Data::Hopen::G::Op->new(name=>"whatever");
    $dag->add($node);

Returns the node, for the sake of chaining.

=cut

sub add {
    my ($self, undef, $node) = parameters('self', ['node'], @_);
    return if $self->_graph->has_vertex($node);
    hlog { __PACKAGE__, $self->name, 'adding', Dumper($node) } 2;

    $self->_graph->add_vertex($node);
    #$self->_node_by_name->{$node->name} = $node if $node->name;

    return $node;
} #add()

=head2 init

Add an initialization operation to the graph.  Initialization operations run
before all other operations.  An attempt to add the same initialization
operation twice will be ignored.  Usage:

    my $op = Data::Hopen::G::Op->new(name=>"whatever");
    $dag->init($op[, $first]);

If C<$first> is truthy, the op will be run before anything already in the
graph.  However, later calls to C<init()> with C<$first> set will push
operations even before C<$op>.

Returns the node, for the sake of chaining.

=cut

sub init {
    my $self = shift or croak 'Need an instance';
    my $op = shift or croak 'Need an op';
    my $first = shift;
    return if $self->_init_graph->has_vertex($op);

    $self->_init_graph->add_vertex($op);
    #$self->_node_by_name->{$op->name} = $op;

    if($first) {    # $op becomes the new _init_first node
        $self->_init_graph->add_edge($op, $self->_init_first);
        $self->_init_first($op);
    } else {    # Not first, so can happen anytime.  Add it after the
                # current first node.
        $self->_init_graph->add_edge($self->_init_first, $op);
    }

    return $op;
} #init()

=head1 ACCESSORS

=head2 empty

Returns truthy if the only nodes in the graph are internal nodes.
Intended for use by hopen files.

=cut

sub empty {
    my $self = shift or croak 'Need an instance';
    return ($self->_graph->vertices == 1);
        # _final is the node in an empty() graph.
        # We don't check the _init_graph since empty() is intended
        # for use by hopen files, not toolsets.
} #empty()

=head1 OTHER

=head2 BUILD

Initialize the instance.

=cut

sub BUILD {
    #use Data::Dumper;
    #say Dumper(\@_);
    my $self = shift or croak 'Need an instance';
    my $hrArgs = shift;

    # DAGs always have names
    $self->name('__R_DAG_' . $_id_counter++) unless $self->has_custom_name;

    # Graph of normal operations
    my $graph = Data::Hopen::OrderedPredecessorGraph->new( directed => true,
                            refvertexed => true);
    my $final = Data::Hopen::G::Node->new(
                                    name => '__R_DAG_ROOT' . $_id_counter++);
    $graph->add_vertex($final);
    $self->_graph($graph);
    $self->_final($final);

    # Graph of initialization operations
    my $init_graph = Data::Hopen::OrderedPredecessorGraph->new( directed => true,
                            refvertexed => true);
    my $init = Data::Hopen::G::CollectOp->new(
                                    name => '__R_DAG_INIT' . $_id_counter++);
    $init_graph->add_vertex($init);

    $self->_init_graph($init_graph);
    $self->_init_first($init);
} #BUILD()

1;
# Rest of the docs {{{1
__END__

=head1 IMPLEMENTATION

Each DAG has a hidden L</_final> node.  All outputs have edges from the _final
node.  The traversal order is reverse topological from the root node, but is
not constrained beyond that.

The DAG is built backwards from the outputs toward the inputs, although calls
to L</output> and L</connect> can appear in any order as
long as everything is hooked in before the DAG is run.

The following is TODO:

=over 4

=item - C<< DAG::inject(<op1>,<op2>[, after/before]) >>

Returns an operation that
lives on the edge between C<op1> and C<op2>.  If the third parameter is
false, C<'before'>, or omitted, the new operation will be the first
operation on that edge.  If the third parameter is true or C<'after'>,
the new operation will be the last operation on that edge.  Any number
of operations can be injected on any edge.

=back

=cut

# }}}1
# vi: set fdm=marker: #
