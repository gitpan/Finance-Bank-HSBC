#!/usr/local/bin/perl

use Finance::Bank::HSBC;

my @accounts = Finance::Bank::HSBC->check_balance (
    bankingid               => "IBnnnnnnnnnn",
    seccode                 => "nnnnnn",
    dateofbirth             => "DDMMYY",
    #get_statements          => 0, # or 1
    #get_transactions        => 0, # or 1
    # YYYY-MM-DD
    #earliest_statement_date => '2006-08-31',
    # sortcodeACCOUNTNUMBER e.g. 987654012345678
    # can be an array of several, a single value, or none at all
    #accounts => [ 'nnnnnnnnnnnnnn' ],
);

foreach ( @accounts )
{
  my $ac = $_->{account};
  $ac =~ s/[^0-9]+//g;

  open FD, ">" . $ac . ".qif" || die ( "Can't write .qif - ". $@ );
  print FD Finance::Bank::HSBC->generate_qif ( $_ );
  close FD;
}

