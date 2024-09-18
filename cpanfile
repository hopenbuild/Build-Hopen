# cpanfile for Data-Hopen
requires 'Carp';
requires 'Class::Method::Modifiers', '2.10';
requires 'Class::Tiny', '1.001';
requires 'Config';
requires 'Data::Dumper';
requires 'Exporter';
requires 'File::Spec';
requires 'Getargs::Mixed', '1.04';
requires 'Getopt::Long', '2.5';
requires 'Graph', '0.9704';
requires 'Hash::Merge', '0.299';
requires 'Import::Into';
requires 'Path::Class', '0.37';
requires 'Regexp::Assemble', '0.38';
requires 'Scalar::Util';
requires 'Set::Scalar', '1.27';
requires 'Storable', '3.06';
requires 'Sub::ScopeFinalizer', '0.02';
requires 'constant';
requires 'experimental', '0.009';
requires 'feature';
requires 'overload';
requires 'perl', '5.014';
requires 'strict';
requires 'vars::i', '2.000000';
requires 'warnings';

on configure => sub {
    requires 'Module::Build::Tiny';
};

on build => sub {
    requires 'Getopt::Long';
    requires 'Path::Class', '0.37';
    requires 'Pod::Markdown';
    requires 'Pod::Text';
};

on test => sub {
    requires 'Capture::Tiny';
    requires 'List::AutoNumbered', '0.000009';
    requires 'Quote::Code', '1.0102';
    requires 'Sub::Identify', '0.14';
    requires 'Test::Deep', '0.098';
    requires 'Test::Fatal', '0.014';
    requires 'Test::More';
    requires 'Test::UseAllModules', '0.17';
    requires 'Test::Warn', '0.35';
    requires 'rlib';
};

on develop => sub {
    requires 'App::RewriteVersion';
    requires 'CPAN::Meta';
    requires 'File::Slurp', '9999.26';
    requires 'Module::CPANfile', '0.9020';
    requires 'Module::Metadata', '1.000016';
    requires 'Test::Kwalitee';
};
