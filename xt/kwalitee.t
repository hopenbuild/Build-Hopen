use Test::More;
use strict;
use warnings;
BEGIN {
    plan skip_all => 'these tests are for release candidate testing'
        unless $ENV{RELEASE_TESTING};
}

use Test::Kwalitee 'kwalitee_ok';
kwalitee_ok();
done_testing;
# NOTE: we fail has_meta_yml when run from a source checkout, but META.yml
# is in the dist.
