#!perl
# 050-runnable.t: Tests of D::H::G::Runnable functions not covered elsewhere
use rlib 'lib';
use HopenTest;
use Test::Fatal;

use Data::Hopen qw(hnew);
use Data::Hopen::Scope::Hash;

{
    package DummyRunnable;
    use strict; use warnings;
    use Data::Hopen;
    use parent 'Data::Hopen::G::Node';  # Node so it can be added into graph;
                                        # Node IS-A Runnable.
    use constant {  # what to return
        NORMAL => 0,
        ARRAYREF => 1,
        UNDEF => 2,
    };
    use Class::Tiny { ret => NORMAL };
    our $dag;
    sub _run {
        my ($self, %args) = getparameters('self', [qw(; graph *)], @_);
        $dag = $args{graph};
        if($self->ret == ARRAYREF) {
            return [];
        } elsif($self->ret == UNDEF) {
            return undef;
        } else {
            # Copied from Data::Hopen::G::CollectOp
            return $self->passthrough(-nocontext => 1, -levels => 1)
                # -nocontext because Runnable::run() already hooked in the context
        }
    }
}

{
    my $dut = DummyRunnable->new;

    like(exception { $dut->run(-context => 1, -nocontext => 1) },
        qr{Can't combine}, 'run: -context and -nocontext are mutually exclusive');
    like(exception { $dut->passthrough(-context => 1, -nocontext => 1) },
        qr{Can't combine}, 'passthrough: -context and -nocontext are mutually exclusive');

    my $scope = Data::Hopen::Scope::Hash->new;
    $scope->put(foo => 42);

    is_deeply($dut->passthrough(-context => $scope), {foo=>42}, 'passthrough');
}

{
    my $dut = DummyRunnable->new(ret => DummyRunnable::ARRAYREF);
    like(exception { $dut->run(-nocontext => 1) }, qr{did not return a hashref},
        "run() checks _run()'s return type");
}

{
    my $dut = DummyRunnable->new(ret => DummyRunnable::UNDEF);
    my $retval = $dut->run(-nocontext => 1);
    is_deeply($retval, {}, 'undef return translated to hashref');
}
{
    my $dut = DummyRunnable->new;

    # Test -graph argument to run/_run
    $DummyRunnable::dag = 'a defined value, so we can make sure _run() clears it';
    $dut->run(-nocontext => 1);
    ok(!defined $DummyRunnable::dag, 'run() without -graph did not pass graph to _run()');

    my $dag = hnew DAG => 'dag';
    my $n = $dag->add($dut);
    $dag->connect($n, $dag->goal('all'));
    $DummyRunnable::dag = undef;
    $dag->run;
    is($DummyRunnable::dag, $dag, 'DAG passed itself to op via -graph');
}

done_testing();
