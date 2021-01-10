# Data::Hopen::G::Runnable - parent class for anything runnable in a hopen graph
package Data::Hopen::G::Runnable;
use strict;
use Data::Hopen::Base;

our $VERSION = '0.000020'; # TRIAL

use Data::Hopen;
use Data::Hopen::Scope::Hash;
use Data::Hopen::Util::Data qw(fwdopts);
use Data::Hopen::Util::NameSet;
use Hash::Merge;

# Docs {{{1

=head1 NAME

Data::Hopen::G::Runnable - parent class for runnable things in a hopen graph

=head1 SYNOPSIS

Anything with L</run> inherits from this.  TODO should this be a role?

=head1 ATTRIBUTES

=head2 need

(B<Not currently used>)
Inputs this Runnable requires.
A L<Data::Hopen::Util::NameSet>, with the restriction that C<need> may not
contain regexes.  ("Sorry, I can't run unless you give me every variable
in the world that starts with Q."  I don't think so!)
Or maybe later an arrayref?  TODO.

=head2 scope

If defined, a L<Data::Hopen::Scope> that will have the final say on the
data used by L</run>.  This is the basis of the fine-grained override
mechanism in hopen.

=head2 want

(B<Not currently used>)
Inputs this Runnable accepts but does not require.
A L<Data::Hopen::Util::NameSet>, which may include regexes.
Or maybe later an arrayref?  TODO.

=cut

# }}}1

use parent 'Data::Hopen::G::Entity';
use Class::Tiny {
    # NOTE: want and need are not currently used.
    want => sub { Data::Hopen::Util::NameSet->new },
    need => sub { Data::Hopen::Util::NameSet->new },

    scope => sub { Data::Hopen::Scope::Hash->new },
};

=head1 FUNCTIONS

=head2 run

Run the operation, whatever that means.  Returns a new hashref.
Usage:

    my $hrOutputs = $op->run([options])

Options are:

=over

=item -context

A L<Data::Hopen::Scope> or subclass including the inputs the caller wants to
pass to the Runnable.  The L</scope> of the Runnable itself may override
values in the C<context>.

=item -visitor

If given, a L<Data::Hopen::Visitor> instance.  A L<Data::Hopen::G::DAG>
instance invokes L<Data::Hopen::Visitor/visit> after processing each node.

=item -nocontext

If C<< -nocontext=>1 >> is specified, don't link a context scope into
this one.  May not be specified together with C<-context>.

=item -graph

If given, the L<Data::Hopen::G::DAG> (or subclass) instance in which this
operation is being run.  If DAGs are nested, C<-graph> only provides the
innermost DAG.  This is to preserve encapsulation.

=back

See the source for this function, which contains as an example of setting the
scope.

=cut

sub run {
    my ($self, %args) = getparameters('self', [qw(; context visitor nocontext graph)], @_);
    my $context_scope = $args{context};     # which may be undef - that's OK
    croak "Can't combine -context and -nocontext" if $args{context} && $args{nocontext};

    # Link the outer scope to our scope
    my $saver = $args{nocontext} ? undef : $self->scope->outerize($context_scope);

    hlog { '->', ref($self), $self->name, 'input', Dumper($self->scope->as_hashref) } 3;

    my $retval = $self->_run(fwdopts(%args, [qw(visitor graph)]));
    $retval = {} unless defined $retval;    # a convenience

    die "$self\->_run() did not return a hashref" unless ref $retval eq 'HASH';
        # Prevent errors about `non-hashref 1` or `invalid key`.

    hlog { '<-', ref $self, $self->name, 'output', Dumper($retval) } 3;

    return $retval;
} #run()

=head2 _run

The internal method that implements L</run>.  Must be implemented by
subclasses.  When C<_run> is called, C<< $self->scope >> has been hooked
to the context scope, if any.  Therefore, the inputs to the node are in
C<< $self->scope >>.

The parameters to the function are C<< -visitor => $v >> and
C<< -graph => $g >>, described above with reference to L</run>.  C<$v> and
C<$g> may be C<undef>.  C<_run> is always called in scalar context, and B<must>
return a new hashref, or C<undef> (which is treated as C<{}>).

I recommend starting your C<_run> function with:

    my ($self, %args) = getparameters('self', [qw(; visitor graph)], @_);

and working from there.

=cut

sub _run {
    # uncoverable subroutine
    die('Unimplemented'); # uncoverable statement
}

=head2 passthrough

Returns a new hashref of this Runnable's local values, as defined
by L<Data::Hopen::Scope/local>.  Usage:

    my $hashref = $runnable->passthrough([-context => $outer_scope]);
        # To use $outer_scope as the context
    my $hashref = $runnable->passthrough(-nocontext => 1);
        # To ignore the context

Other valid options include L<-levels|Data::Hopen::Scope/$levels>.

=cut

sub passthrough {
    my ($self, %args) = getparameters('self', ['*'], @_);
    my $outer_scope = $args{context};     # which may be undef - that's OK
    croak "Can't combine -context and -nocontext" if $args{context} && $args{nocontext};

    # Link the outer scope to our scope
    my $saver = $args{nocontext} ? undef : $self->scope->outerize($outer_scope);

    # Copy the names
    my $levels = $args{levels} // 'local';
    my @names = @{$self->scope->names(-levels=>$levels)};
    my $retval = {};
    $retval->{$_} = $self->scope->find($_, -levels=>$levels) foreach @names;

    return $retval;
} #passthrough()

1;
__END__
# vi: set fdm=marker: #
