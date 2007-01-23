use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile (
    'NAME'		      => 'Finance::Bank::HSBC',
    'VERSION_FROM'	=> 'lib/Finance/Bank/HSBC.pm', # finds $VERSION
    'EXE_FILES'     => [ 'scripts/makeextract.pl' ],
    'PREREQ_PM'		  => {
        WWW::Mechanize    => 0,
        HTML::TokeParser  => 0,
    }
);
