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
cmp_ok($oldrefaddr, '!=', $newrefaddr, 'make_GraphBuilder changed next()');

# A no-op builder
sub nopbuild { return undef }
make_GraphBuilder 'nopbuild';

# A would-be builder that does not return a blessed reference
sub plainrefbuild { [] }
make_GraphBuilder 'plainrefbuild';

# A would-be builder that does not return a node
package Foo {
    use Class::Tiny;
}
sub nonnodebuild { return Foo->new; }

sub get_only_node {
    my $builder = shift;
    is(ref $builder->nodes, 'ARRAY', 'builder->nodes is an arrayref');
    cmp_ok(@{$builder->nodes}, '==', 1, 'nodes has one element');
    return $builder->nodes->[0];
}

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
    my $op2 = get_only_node($builder);

    $builder->main::nopbuild;
    my $op3 = get_only_node($builder);
    cmp_ok(refaddr $op3, '==', refaddr $op2, 'NOP builder leaves node the same');

    like( exception { $builder->main::plainrefbuild },
        qr/Invalid return value/, 'arrayref rejected' );

    $builder->main::nonnodebuild;
    my $op5 = get_only_node($builder);
    cmp_ok(refaddr $op5, '==', refaddr $op2, 'non-node builder leaves node the same');

    my $n3 = newnode('node3');
    $builder->add($n3);
    my $op6 = get_only_node($builder);
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

    $builder->nodes([$n3]);
    $builder->default_goal;
    ok($dag->_graph->has_edge($n3, $goal), 'edge node3->goal exists');

    my $n4 = newnode('node4');
    $builder->nodes([$n4]);
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

# Test different return values of builder functions
package Builders {
    use Test::More;
    use Test::Fatal;
    use Data::Hopen qw(hnew);
    use Data::Hopen::Base;
    use Data::Hopen::G::DAG;
    use Data::Hopen::G::GraphBuilder;

    sub retundef { return undef }
    sub retfalsy { return 0 }
    sub rettruthy { return 42 }
    sub retarray { return [] }
    sub retnode { shift; goto &main::newnode }

    sub retparallel {
        my $builder = shift;
        return +{ parallel => [map { main::newnode() } 0..$#{$builder->nodes}]};
    }

    sub retcomplete {
        my $builder = shift;
        return +{ complete => [map { main::newnode() } 0..3]};
    }

    sub retunknownrel { return +{ unsupported_relationship => [1] } }
    sub retnonodes { return +{ parallel => [] } }

    sub retwrongparallel {
        my $builder = shift;
        return +{ parallel => [map { main::newnode() } 0..$#{$builder->nodes}+1]};
    }

    sub retmultiple {
        return +{ parallel => [1], complete => [1]};
    }

    sub retcomplete1 {
        my $builder = shift;
        return +{ complete => [main::newnode()]};
    }

    make_GraphBuilder foreach qw(retundef retfalsy rettruthy retarray
                                    retnode retparallel retcomplete
                                    retunknownrel retnonodes retwrongparallel
                                    retmultiple retcomplete1);

    sub run {
        my $dag1 = hnew DAG => 'dag1';
        my $builder = hnew GraphBuilder => 'builder1', dag => $dag1;
        cmp_ok(@{$builder->nodes}, '==', 0, 'No current nodes in new builder');
        $builder->Builders::retundef;
        cmp_ok(@{$builder->nodes}, '==', 0, 'No current nodes after retundef');
        $builder->Builders::retfalsy;
        cmp_ok(@{$builder->nodes}, '==', 0, 'No current nodes after retfalsy');

        like( exception { $builder->Builders::rettruthy },
            qr/did not return a reference/, 'truthy non-reference rejected' );

        like( exception { $builder->Builders::retarray },
            qr/Invalid return value/, 'arrayref rejected' );

        like( exception { $builder->Builders::retunknownrel },
            qr/requested relationship.+unsupported_relationship/,
            'unsupported relationship rejected' );

        like( exception { $builder->Builders::retnonodes },
            qr/provided no nodes/, 'empty set of new nodes rejected' );

        my $name = 'retnode1';
        $builder->Builders::retnode($name);
        cmp_ok(@{$builder->nodes}, '==', 1, 'One current node after retnode');
        $builder->Builders::retcomplete;
        cmp_ok(@{$builder->nodes}, '==', 4, 'Four current nodes after retcomplete');
        my @node1succ = $builder->dag->_graph->successors(
            $builder->dag->node_by_name($name));
        cmp_ok(@node1succ, '==', 4, 'Four successors after retcomplete');

        $builder->Builders::retparallel;
        cmp_ok(@{$builder->nodes}, '==', 4, 'Four current nodes after retparallel');
        foreach (@node1succ) {
            cmp_ok($builder->dag->_graph->successors($_), '==', 1,
                "Node @{[$_->name]} has one successor");
        }

        like( exception { $builder->Builders::retwrongparallel },
            qr/parallel.+must match.+nodes/, '"parallel" rejects mismatched node count' );

        like( exception { $builder->Builders::retmultiple },
            qr/one type of return/, 'multiple-key hashref rejected' );

        $builder->Builders::retcomplete1;
        cmp_ok(@{$builder->nodes}, '==', 1, 'One current node after retcomplete1');
        my @preds = $builder->dag->_graph->predecessors($builder->nodes->[0]);
        cmp_ok(@preds, '==', 4, 'current node after retcomplete1 has four predecessors');


    } #Builders::run
}

# === Run ===

main;
failures;
Builders::run;

done_testing;
