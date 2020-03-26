#!perl
# t/009-scope.t: test Data::Hopen::Scope functions not tested elsewhere.
use rlib 'lib';
use HopenTest 'Data::Hopen::Scope::Hash';
use Data::Hopen::Scope ':all';

ok(is_first_only(FIRST_ONLY), 'is_first_only(FIRST_ONLY)');
ok(!is_first_only({}), '!is_first_only({})');
ok(!is_first_only([]), '!is_first_only([])');
ok(!is_first_only(0), '!is_first_only(0)');
ok(!is_first_only(1), '!is_first_only(1)');

done_testing;
