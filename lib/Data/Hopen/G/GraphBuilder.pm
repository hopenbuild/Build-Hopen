# Data::Hopen::G::GraphBuilder - fluent interface for building graphs
package Data::Hopen::G::GraphBuilder;
use Data::Hopen;
use strict;
use Data::Hopen::Base;
use Exporter 'import';

our @EXPORT; BEGIN { @EXPORT=qw(make_GraphBuilder); }

our $VERSION = '0.000020';

use Class::Tiny {
    name => 'ANON',     # Name is optional; it's here so the
                        #   constructor won't croak if you use one.
    dag => undef,       # The current G::DAG instance
    nodes => sub { [] },    # The last node(s) added.  Always an arrayref.
};

use Class::Method::Modifiers qw(install_modifier);
use Data::Dumper;
use Getargs::Mixed;
use Scalar::Util qw(refaddr);

# Docs {{{1

=head1 NAME

Data::Hopen::G::GraphBuilder - fluent interface for building graphs

=head1 SYNOPSIS

A GraphBuilder wraps a L<Data::Hopen::G::DAG> and a current
L<Data::Hopen::G::Node>.  It permits building chains of nodes in a
fluent way.  For example, in an L<App::hopen> hopen file:

    # $Build is a Data::Hopen::G::DAG created by App::hopen
    use language 'C';

    my $builder = $Build->C::compile(file => 'foo.c');
        # Now $builder holds $Build (the DAG) and a node created by
        # C::compile().

=head1 ATTRIBUTES

=head2 name

An optional name, in case you want to identify your Builder instances.

=head2 dag

The current L<Data::Hopen::G::DAG> instance, if any.

=head2 nodes

The current L<Data::Hopen::G::Node> instance(s), if any.  Always an arrayref.

=head1 INSTANCE FUNCTIONS

=cut

# }}}1

=head2 add

Adds a node to the graph.  Returns the node.  Note that this B<does not>
change the builder's current node (L</nodes>).

=cut

sub add {
    my ($self, %args) = getparameters('self', ['node'], @_);
    $self->dag->add($args{node});
    return $args{node};
} #add()

=head2 default_goal

Links the most recent node(s) in the chain to the default goal in the DAG.
If the DAG does not have a default goal, adds one called "all".

As a side effect, calling this function clears the builder's record of the
current node(s) and returns C<undef>.  The idea is that this function
will be used at the end of a chain of calls.  Clearing state in this way
reduces the chance of unintentionally connecting nodes.

=cut

sub default_goal {
    my $self = shift or croak 'Need an instance';

    my $goal = $self->dag->default_goal // $self->dag->goal('all');
    return $self->goal($goal);
} #default_goal()

=head2 goal

Links the most recent node(s) in the chain to the given goal in the DAG.
Clears the builder's record of the current node and returns undef.  Usage:

    $builder->goal(<goal instance or string goal name>);

If you pass a goal instance, you are responsible for making sure it came from
L<Data::Hopen::G::DAG/goal> or L<Data::Hopen::G::DAG/default_goal>.

=cut

sub goal {
    my $self = shift or croak 'Need an instance';
    my $goal_or_name = shift or croak 'Need a goal or goal name';
    croak "Need a node to link to the goal" unless @{$self->nodes};

    my $goal = ref($goal_or_name) ? $goal_or_name : $self->dag->goal($goal_or_name);
    foreach my $node (@{$self->nodes}) {
        $self->dag->add($node);     # no harm in it - DAG::add() is idempotent
        $self->dag->connect($node, $goal);
    }

    $self->nodes([]);       # Less likely to leak state between goals.

    return undef;
        # Also, if this is the last thing in an App::hopen hopen file,
        # whatever it returns gets recorded in MY.hopen.pl.  Therefore,
        # return $self would cause a copy of the whole graph to be dropped into
        # MY.hopen.pl, which would be a Bad Thing.
} #goal()

=head2 to

Connect one set of node(s) to another, where both sets are wrapped in
C<GraphBuilder>s.  Each source node is connected to each destination node
(the same as L</complete>, below).

Usage:

    $builder_1->to($builder_2);
        # Now each node in @{$builder_1->nodes} has an edge to each
        # node in @{$builder_2->nodes}

Returns C<undef>, because chaining would be ambiguous.  For example,
in the snippet above, would the chain continue from C<$builder_1> or
C<$builder_2>?

Does not change the state of either GraphBuilder.

=cut

sub to {
    my ($self, %args) = parameters('self', [qw(dest)], @_);
    croak 'Destination is not a ' . __PACKAGE__
        unless $args{dest}->DOES(__PACKAGE__);
    croak 'Cannot connect nodes from different graphs'
        if refaddr($self->dag) != refaddr($args{dest}->dag);

    for my $srcnode (@{$self->nodes}) {
        for my $destnode (@{$args{dest}->nodes}) {
            $self->dag->connect($srcnode, $destnode);
        }
    }

    return undef;
} #to()

=head1 STATIC FUNCTIONS

=head2 make_GraphBuilder

Given the name of a subroutine, wrap the given subroutine for use in a
GraphBuilder chain such as that shown in the L</SYNOPSIS>.  Usage:

    sub worker {
        my $graphbuilder = shift;
        ...
        return $node;   # Will automatically be linked into the chain
    }

    make_GraphBuilder 'worker';
        # now worker can take a DAG or GraphBuilder, and the
        # return value will be the GraphBuilder.

    # then later...

    my $dag = Data::Hopen::G::DAG->new;
    my $builder = Data::Hopen::G::GraphBuilder->new(dag => $dag);
    $builder->main::worker(@args);
        # calls worker($builder, @args)

If no parameter is given to C<make_GraphBuilder()>, C<$_> is used.

=head3 Worker function

The worker function (C<worker()> in the example above) is called in scalar
context.  It receives the graph-builder instance as its first parameter.
Any other parameters are those given in the calling code.and an arrayref of the current
node(s) (L</nodes>).

Depending on what the worker function returns, the builder will create different
connections between nodes.  The worker function may not return a truthy
non-reference.  The return-value options and corresponding behaviours are:

=over

=item something falsy

The bulder does not add nodes or create links.  This is not an error.

=item a single node

Each of the current node(s) (L</nodes>) will be linked to the node returned
by the worker function (1-1 or many-1 connection)

=item a hashref

A single C<< mapping => [new node(s)] >> entry.  At present, multiple
mapping+arrayref pairs are no supported.  Possible C<mapping> values are:

=over

=item parallel

Each of the current node(s) is linked to the corresponding one of the
new node(s).  The graph gets parallel edges added, whence the name.

This is only valid if the number of current nodes matches the number of
new nodes, or if the number of current nodes is zero.

=item complete

Each of the current node(s) is linked to B<all> of the new node(s).  For
a single current node, this is 1-to-many fanout; for a single new node, this
is many-to-1 fan-in.

This is valid regardless of the number of current nodes.  For example, the
number of current nodes may be zero.

=back

=back

=cut

sub _wrapper;

sub make_GraphBuilder {
    my $target = caller;
    my $funcname = shift // $_ or croak 'Need the name of the sub to wrap';   # yum

    install_modifier $target, 'around', $funcname, \&_wrapper;
} #make_GraphBuilder()

# The "around" modifier
sub _wrapper {
    my $orig = shift or die 'Need a function to wrap';
    croak "Need a parameter" unless @_;

    # Create the GraphBuilder if we don't have one already.
    my $self = shift;
    $self = __PACKAGE__->new(dag=>$self)
        unless eval { $self->DOES(__PACKAGE__) };
    croak "Parameter must be a DAG or Builder"
        unless eval { $self->dag->DOES('Data::Hopen::G::DAG') };

    unshift @_, $self;     # Put the builder on the arg list

    # Call the worker
    my $worker_retval = &{$orig};   # @_ passed to code

    hlog { 'Worker returned', Dumper($worker_retval) } 4;

    return $self unless $worker_retval;
    die "Builder $orig did not return a reference" unless ref $worker_retval;

    # Make links
    if(eval { $worker_retval->DOES('Data::Hopen::G::Node') } ) {    # many-to-1
        $self->dag->add($worker_retval);    # Link it into the graph
        $self->dag->connect($_, $worker_retval) foreach @{$self->nodes};

        $self->nodes([$worker_retval]);        # It's now our current node

    } elsif(ref $worker_retval eq 'HASH') {
        my @keys = keys %$worker_retval;
        if(@keys != 1) {
            die "At this time, I can only handle one type of return.  Sorry!  (got @keys)";
        }

        my @newnodes = @{$worker_retval->{$keys[0]}};
        die "Worker provided no nodes" unless @newnodes;
        my $ncurrnodes = @{$self->nodes};

        if($keys[0] eq 'parallel') {                                # 1-to-1 x N
            if($ncurrnodes != 0 && $ncurrnodes != @newnodes) {
                die "For parallel, number @{[scalar @newnodes]} of new nodes" .
                    " must match number $ncurrnodes of existing nodes.";
            }
            for my $idx (0..$#newnodes) {
                my $destnode = $self->dag->add($newnodes[$idx]);
                $self->dag->connect($self->nodes->[$idx], $destnode);
            }

            $self->nodes(\@newnodes);

        } elsif($keys[0] eq 'complete') {                           # many-to-many
            my @srces = @{$self->nodes};    # for convenience

            for my $destidx (0..$#newnodes) {
                my $destnode = $self->dag->add($newnodes[$destidx]);
                for my $srcidx (0..$#srces) {
                    # srces must be the inner loop because there may not be
                    # any srces.
                    $self->dag->connect($srces[$srcidx], $destnode);
                }
            }

            $self->nodes(\@newnodes);

        } else {
            die "I don't understand requested relationship ``$keys[0]''";
        }
    } else {
        croak "Invalid return value $worker_retval from worker function $orig";
    }

    return $self;
}; #_wrapper()

1;
__END__
# vi: set fdm=marker: #
