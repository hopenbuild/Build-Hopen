#!perl
# 130-graphbuilder.t: tests of Data::Hopen::G::GraphBuilder
use rlib 'lib';
use HopenTest;
use Test::Deep::NoTest;     # NoTest since I am using eq_deeply directly
use Test::Fatal;

use Data::Hopen qw(:v hnew);
use Data::Hopen::G::DAG;
use Data::Hopen::G::GraphBuilder;
use Data::Hopen::G::NoOp;
use Scalar::Util qw(refaddr);

diag "Testing Data::Hopen::G::GraphBuilder from $INC{'Data/Hopen/G/GraphBuilder.pm'}";

# For unique node names
my $nodeid = 42;

sub newnode {
    return Data::Hopen::G::NoOp->new(name => $_[0] // ('N' . $nodeid++));
}

# a builder
sub next {
    my $graphbuilder = shift;
    return newnode($_[0]);
}

# Make it a builder
is(ref \&next, 'CODE', 'next() is a sub before wrapping');
my $oldrefaddr = refaddr \&next;

make_GraphBuilder 'next';
my $newrefaddr = refaddr \&next;

is(ref \&next, 'CODE', 'next() is a sub after wrapping');
cmp_ok($oldrefaddr, ne => $newrefaddr, 'make_GraphBuilder changed next()');

# A no-op builder
sub nopbuild { }
make_GraphBuilder 'nopbuild';

# A would-be builder that does not return a blessed reference
sub plainrefbuild { [] }
make_GraphBuilder 'plainrefbuild';

# A would-be builder that does not return a node
package Foo {
    use Class::Tiny;
}

sub nonnodebuild { return Foo->new; }

sub main {
    my $dag = Data::Hopen::G::DAG->new;
    isa_ok($dag, 'Data::Hopen::G::DAG');
    ok($dag->empty, 'DAG is initially empty');
    cmp_ok($dag->_graph->vertices, '==', 1, 'DAG initially has 1 vertex');

    my $builder = $dag->main::next('node1');
    isa_ok($builder, 'Data::Hopen::G::GraphBuilder');
    my $builder2 = $builder->main::next('node2');
    isa_ok($builder2, 'Data::Hopen::G::GraphBuilder');
    cmp_ok(refaddr $builder, '==', refaddr $builder2, 'Same builder instance');
    my $op2 = $builder->node;

    $builder->main::nopbuild;
    my $op3 = $builder->node;
    cmp_ok(refaddr $op3, '==', refaddr $op2, 'NOP builder leaves node the same');

    $builder->main::plainrefbuild;
    my $op4 = $builder->node;
    cmp_ok(refaddr $op4, '==', refaddr $op2, 'plain-ref builder leaves node the same');

    $builder->main::nonnodebuild;
    my $op5 = $builder->node;
    cmp_ok(refaddr $op5, '==', refaddr $op2, 'non-node builder leaves node the same');

    my $n3 = newnode('node3');
    $builder->add($n3);
    my $op6 = $builder->node;
    cmp_ok(refaddr $op6, '==', refaddr $op2, 'builder->add() leaves node the same');

    my $retval = $builder->default_goal;
    ok(!defined $retval, 'default_goal returns undef');
    my $n1 = $dag->node_by_name('node1');
    ok($n1, 'Got node1 by name');
    my $n2 = $dag->node_by_name('node2');
    ok($n2, 'Got node2 by name');
    my $goal = $dag->default_goal;
    ok($dag->_graph->has_edge($n1, $n2), 'edge node1->node2 exists');
    ok($dag->_graph->has_edge($n2, $goal), 'edge node2->goal exists');
    ok(!$dag->_graph->has_edge($n1, $goal), 'edge node1->goal does not exist');

    $builder->node($n3);
    $builder->default_goal;
    ok($dag->_graph->has_edge($n3, $goal), 'edge node3->goal exists');

    my $n4 = newnode('node4');
    $builder->node($n4);
    $builder->goal('all');
    ok($dag->_graph->has_edge($n4, $goal), 'edge node3->goal("all") exists');

    # A graph with a default not named 'all'
    $dag = hnew DAG => 'dag';
    my $defgoalname = 'leetness';
    my $defgoal = $dag->goal($defgoalname);
    cmp_ok(refaddr($dag->default_goal), '==', refaddr($defgoal), 'Default goal does not have to be "all"');

    $builder = $dag->main::next('whatever');
    $builder->default_goal;
    my $node_whatever = $dag->node_by_name('whatever');
    ok($dag->_graph->has_edge($node_whatever, $defgoal), 'edge node->default goal exists');

} #main

sub failures {
    my $dag = Data::Hopen::G::DAG->new;
    my $builder = Data::Hopen::G::GraphBuilder->new(dag => $dag);

    like( exception { make_GraphBuilder; }, qr/Need the name/, 'make_GraphBuilder without name');
    like( exception { Data::Hopen::G::GraphBuilder::_wrapper() }, qr/Need a function/, 'GraphBuilder _wrapper() without function');
    like( exception { Data::Hopen::G::GraphBuilder::_wrapper('foo') }, qr/Need a parameter/, 'GraphBuilder _wrapper() without parameter');
    like( exception { Data::Hopen::G::GraphBuilder::_wrapper('foo', []) }, qr/must be a DAG/, 'GraphBuilder _wrapper() without DAG');


}

# === Run ===

main;
failures;

done_testing;
