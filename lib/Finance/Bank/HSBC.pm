package Finance::Bank::HSBC;

use vars qw($VERSION);

$VERSION = '1.05';

use strict;
use warnings;

use WWW::Mechanize;
use HTML::TokeParser;

sub generate_qif
{
    shift if $_ [ 0 ] eq __PACKAGE__ || ref $_ [ 0 ] eq __PACKAGE__;

    my $account = shift;

    die ( "Could not find statements" ) unless exists $account->{statements};

    my $statements = $account->{statements};

    # find out the statement dates, earliest first
    my @dates = sort { $b cmp $a } keys %$statements;

    my $qif = "!Type:Oth L\n";

    foreach my $d ( @dates )
    {
        my @transactions = reverse @{ $statements->{$d} };

        foreach my $t ( @transactions )
        {
            my $tdate = $t->{date};

            # the date /should/ match this, which we can do something with,
            # hopefully
            if ( $tdate =~ m/(\d+)\s*(\w+)/ )
            {
                my ( $date, $month ) = ( $1, $2 );
                my %months = (
                    jan => 1,
                    feb => 2,
                    mar => 3,
                    apr => 4,
                    may => 5,
                    jun => 6,
                    jul => 7,
                    aug => 8,
                    sep => 9,
                    oct => 10,
                    nov => 11,
                    dec => 12,
                );
                my $mon_num = $months { lc $month };

                # we need to guess the year, based on the statement date
                my $year = $d;
                $year =~ m/(\d+)\-(\d+)-\d+$/;
                my ( $syear, $smonth ) = ( $1, $2 );

                # if the month number on the statement, is less than the month
                # number of the transaction, then it must have been last year
                # (if my logic holds, that is)
                --$syear if $mon_num > $smonth;

                $tdate = sprintf ( "%02d/%02d/%04d", $date, $mon_num, $syear );
            }

            $qif .= "D" . $tdate . "\nT";

            if ( $t->{paidout} )
            {
                $qif .= '-' . $t->{paidout};
            }
            elsif ( $t->{paidin} )
            {
                $qif .= $t->{paidin};
            }
            else
            {
                $qif .= '0';
            }

            my $d = $t->{desc};
            $d =~ s/[\r\n]/ /g;
            $qif .= "\nP" . $d . "\n^\n";
        }
    }

    return $qif;
}

# extract_details was listed as the new method name, but for historical
# reasons it's left as check_balance
sub extract_details
{
    &check_balance;
}

sub check_balance
{
    # we don't care about a class
    shift if $_ [ 0 ] eq __PACKAGE__ || ref $_ [ 0 ] eq __PACKAGE__;

    my ( %opts ) = @_;

    my @accounts;

    die "Must provide a security code" unless defined $opts{seccode};
    die "Must provide a banking id" unless defined $opts{bankingid};
    die "Must provide a date of birth" unless defined $opts{dateofbirth};

    $opts{accounts} = [ $opts{accounts} ]
        if defined $opts{accounts} && ref $opts{accounts} ne 'ARRAY';

    my $agent = WWW::Mechanize->new ();
    $agent->get ( "http://hsbc.co.uk/1/2/personal/pib-home" );

    # Filling in the login form. 
    $agent->submit_form (
        form_name => 'navbarLogon',
        fields    => {
            internetBankingID => $opts{bankingid},
        },
    );

    # We're given a redirect, and then need to navigate a frameset.
    $agent->follow_link ( url => 'https://www.ebank.hsbc.co.uk/main/IBLogon.jsp' );

    # The login page.
    my ( $digit1, $digit2, $digit3 ) =
        $agent->content =~ /Please enter the ([A-Z]+), ([A-Z]+) and ([A-Z]+) digits of your security number/
        or die ( "Was expecting request for security code digits" );

    my @digitnames = qw(FIRST SECOND THIRD FOURTH FIFTH SIXTH SEVENTH EIGHTH NINTH);
    my $t = 0;
    my %digitnames = map { $_ => $t++ } @digitnames;

    # it's possible they used "LAST"
    $digit3 = $digitnames [ length ( $opts{seccode} ) - 2 ]
        if $digit3 eq 'LAST';

    my $seccodedigits = '';
    my @seccode = split //, $opts{seccode};

    foreach ( $digit1, $digit2, $digit3 )
    {
        $seccodedigits .= $seccode [ $digitnames { $_ } ];
    }

    $agent->submit_form (
        form_name => 'IBLogon',
        fields    => {
            dateOfBirth => $opts{dateofbirth},
            tsn         => $seccodedigits,
        },
    );

    # More frameset navigation.
    $agent->follow_link ( url => 'https://www.ebank.hsbc.co.uk/welcomebackindex.jsp' );
    $agent->follow_link ( url => 'https://www.ebank.hsbc.co.uk/main/portmain.jsp' );

    # Now we have the data, we need to parse it - use a RE, which'll work
    # until they update their markup
    
    my $content = $agent->{content};

    ACCOUNT: while ( $content =~ m!<td height="25">\s*(.*?)\s*</td>.*?<td>\s*(.*?)\s*</td>.*?<td><a href='([^']*)'.*?>\s*(.*?)\s*</a>.*?<td align="right" nowrap="nowrap">\s*(.*?)\s*([DC])\s*</td>!sg )
    {
        my ( $name, $type, $details_link, $number, $balance, $balance_neg ) = ( $1, $2, $3, $4, $5, $6 );

        # check to see whether we should be parsing thing
        if ( defined $opts{accounts} )
        {
            my $n = $number;
            $n =~ s/[^0-9]//g;
            my %t = map { $_ => 1 } @{ $opts{accounts} };
            next ACCOUNT unless exists $t { $n };
        }

        # a "D" denotes negative!
        $balance = "-" . $balance if $balance_neg eq 'D';

        my $account = {
            balance         => $balance,
            name            => $name,
            type            => $type,
            account         => $number,
        };

        foreach ( qw(balance name type account) )
        {
            $account->{$_} =~ s/&#160;/ /g;
            $account->{$_} =~ s/<[^>]*>//g;
            $account->{$_} =~ s/(^\s*)|(\s*$)//g;
        }

        $account->{transactions} = _get_transactions ( $agent, $account )
            if $opts{get_transactions};

        $account->{statements} = _get_statements ( $agent, $account,
                $opts{earliest_statement_date} )
            if $opts{get_statements};

        push @accounts, $account;
    }

    return @accounts;
}

sub _get_statements
{
    shift if $_ [ 0 ] eq __PACKAGE__ || ref $_ [ 0 ] eq __PACKAGE__;

    my $agent = shift;
    my $account = shift;
    my $earliestDate = shift;

    my $number = $account->{account};
    $number =~ s/\s*//g;
    $agent->follow_link ( url_regex => qr/OnAccountSelectionServlet.*?${number}$/ );
    $agent->follow_link ( url_regex => qr/\/navbar.jsp$/ );

    my %statement;

    # make sure there /is/ a statements link
    if ( $agent->find_link ( url_regex => qr/OnMnuMyStatementsServlet/ ) )
    {
        # we're good
        $agent->follow_link ( url_regex => qr/OnMnuMyStatementsServlet/ );
        $agent->follow_link ( url_regex => qr/\/hs_date_selection.jsp/ );

        STATEMENT: while ( 1 )
        {
            # extract all the statement dates
            my $sdc = $agent->content;
            $sdc =~ m!(<select name="statementDate".*?</select>)!s;
            $sdc = $1;

            while ( $sdc =~ m/<option value="(.*?)"/g )
            {
                my $statementDate = $1;

                # can we give up yet?
                last STATEMENT 
                    if defined $earliestDate &&
                       $statementDate lt $earliestDate;

                $agent->form ( 0 );
                $agent->select ( "statementDate", $statementDate );
                $agent->submit_form;

                # get the page
                my @statement;
                my $content = $agent->content;

                while ( $content =~ m!<tr>(.*?)</tr>!gs )
                {
                    my $c = $1;
                    if ( $c =~ m!<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>.*?</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>.*?</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>.*?</td>\s*<td[^>]*><b>(.*?)</b></td>\s*<td[^>]*><b>(.*?)</b></td>!gs )
                    {
                        my ( $date, $type, $desc, $paidout, $paidin, $balance, $balance_neg ) = ( $1, $2, $3, $4, $5, $6, $7 );

                        my $entry = {
                            date        => $date,
                            type        => $type,
                            desc        => $desc,
                            paidin      => $paidin,
                            paidout     => $paidout,
                            balance     => $balance,
                            balance_neg => $balance_neg,
                        };

                        foreach ( qw(desc paidout paidin date balance_neg type) )
                        {
                            $entry->{$_} =~ s/&#160;/ /g;
                            $entry->{$_} =~ s/<[^>]*>//g;
                            $entry->{$_} =~ s/(^\s*)|(\s*$)//g;
                        }

                        $entry->{balance} = "-" . $entry->{balance}
                            if $entry->{balance_neg} eq 'D';

                        push @statement, $entry;
                    }
                }

                $statement { $statementDate } = \@statement;

                # back to the statement date chooser
                $agent->follow_link ( url_regex => qr/OnBackToStatementDateListServlet/ );
            }

            last STATEMENT unless $agent->find_link ( url_regex => qr/OnListOlderStatementDatesServlet/ );

            $agent->follow_link ( url_regex => qr/OnListOlderStatementDatesServlet/ );
        }
    }
    else
    {
        warn ( "Couldn't find `My statements' link for account #$number" );
    }

    # back to the main accounts page
    $agent->follow_link ( url_regex => qr/OnMyAccountsServlet/ );
    $agent->follow_link ( url_regex => qr/\/portmain.jsp$/ );

    return \%statement;
}

sub _get_transactions
{
    shift if $_ [ 0 ] eq __PACKAGE__ || ref $_ [ 0 ] eq __PACKAGE__;

    my $agent = shift;
    my $account = shift;

    my $number = $account->{account};
    $number =~ s/\s*//g;
    $agent->follow_link ( url_regex => qr/OnAccountSelectionServlet.*?${number}$/ );
    $agent->follow_link ( url_regex => qr/\/statement.jsp$/ );

    # get the page
    my @transactions;
    my $content = $agent->content;

    while ( $content =~ m!<tr>\s*<td valign="top">(.*?)</td>\s*<td valign="top">(.*?)</td>\s*<td height="20" valign="top">\s*(.*?)\s*</td>\s*<td valign="top"></td>\s*<td valign="top" nowrap="nowrap" align="right">(.*?)&\#160;&\#160;</td>\s*<td valign="top"></td>\s*<td valign="top" nowrap="nowrap" align="right">(.*?)&\#160;&\#160;</td>\s*<td valign="top"></td>\s*<td align="right" valign="top" nowrap="nowrap">(.*?)</td>\s*<td align="right" valign="top" nowrap="nowrap">&\#160; (.)</td>\s*</tr>!gs )
    {
        my ( $date, $type, $desc, $paidout, $paidin, $balance, $balance_neg ) = ( $1, $2, $3, $4, $5, $6, $7 );

        my $transaction = {
            date        => $date,
            type        => $type,
            desc        => $desc,
            paidin      => $paidin,
            paidout     => $paidout,
            balance     => $balance,
            balance_neg => $balance_neg,
        };

        foreach ( qw(date type desc paidin paidout balance balance_neg) )
        {
            $transaction->{$_} =~ s/&#160;/ /g;
            $transaction->{$_} =~ s/<[^>]*>//g;
            $transaction->{$_} =~ s/(^\s*)|(\s*$)//g;
        }

        $transaction->{balance} = "-" . $transaction->{balance}
            if $transaction->{balance_neg} eq 'D';

        # cleanup $desc
        $transaction->{desc} =~ s/\s*([\r\n]+)\s*/\n/g;
        $transaction->{desc} =~ s/\n+/\n/g;

        push @transactions, $transaction,
    }

    $agent->follow_link ( url_regex => qr/OnMyAccountsServlet/ );
    $agent->follow_link ( url_regex => qr/\/portmain.jsp$/ );

    return \@transactions;
}

1;

__END__

=head1 NAME

Finance::Bank::HSBC - Extract HSBC online banking data.

=head1 SYNOPSIS

  use Finance::Bank::HSBC;

  my @accounts = Finance::Bank::HSBC->check_balance(
    bankingid               => "IBnnnnnnnnnn",
    seccode                 => "nnnnnn",
    dateofbirth             => "DDMMYY",
    get_statements          => 0, # or 1
    get_transactions        => 0, # or 1

    # YYYY-MM-DD
    earliest_statement_date => '2006-08-31',

    # full account number(s) without spaces, as shown in online banking
    # e.g. sortcodeACCOUNTNUMBER e.g. 987654012345678
    # can be an array of several or a single value
    accounts => [ 'nnnnnnnnnnnnnn' ],
  );

  foreach (@accounts) {
      printf "%25s : %13s / %18s : GBP %8.2f\n",
        $_->{name}, $_->{type}, $_->{account}, $_->{balance};
  }

=head1 DESCRIPTION

This module provides a rudimentary interface to the HSBC online
banking system at C<https://www.ebank.hsbc.co.uk/>. It provides the ability to
extract account information, transaction history and statements.

=head1 DEPENDENCIES

You will need either C<Crypt::SSLeay> or C<IO::Socket::SSL> installed 
for HTTPS support to work with LWP.  This module also depends on 
C<WWW::Mechanize> and C<HTML::TokeParser> for screen-scraping.

=head1 METHODS

=over 2

=item check_balance(%options)

Return an array of account hashes, one for each of your bank accounts. Below
is a list of all the options that this method takes.

=item extract_details(%options)

A synonym for check_balance.

=item generate_qif(\%account)

Generate a very basic QIF file from the account information stored in
\%account. This method requires that the statement information was extracted
for the account data passed in. An example would be:

  my @accounts = Finance::Bank::HSBC->check_balance ( %options );

  foreach ( @accounts )
  {
    my $ac = $_->{account};
    $ac =~ s/[^0-9]+//g;

    open FD, ">" . $ac . ".qif" || die ( "Can't write .qif - ". $@ );
    print FD Finance::Bank::HSBC->generate_qif ( $_ );
    close FD;
  }

=back

=over 2

=item bankingid MANDATORY

Your own personal banking ID number. Along the lines of IBnnnnnnnnnnnn.

=item seccode MANDATORY

The security code assigned to your bank account. Usually a 6 digit number,
though we support upto 9 digits.

=item dateofbirth MANDATORY

Your date of birth, in the format DDMMYY.

=item get_statements OPTIONAL

Defaults to 0. Whether or not the script should extract statement information
for the accounts that are being processed.

=item get_transactions OPTIONAL

Defaults to 0. Whether or not the script should extract recent transaction
information for the accounts that are being processed.

=item earliest_statement_date OPTIONAL

When defined the script will extract data from every statement that has a
"statement date" of at least "earliest_statement_date".

=item accounts OPTIONAL

A single value, or array reference, of account numbers that should be
processed. Only account numbers that are found will be processed, for obvious
reasons. If this option is not present then all accounts that are listed on
the main account overview page will have their details extracted.

=back

=head1 ACCOUNT HASH DATA 

The data returned is an array reference of hashes. Each of these hashes
contains information about a particular account, explained below.

=over 2

=item name

Name of the account, e.g. "MR M WILSON".

=item type

Type of the account, e.g. "STUDENT A/C".

=item account

Account number, as it appears in online banking, i.e. "SORTCODE
ACCOUNT_NUMBER".

=item balance

The current balance of the account, e.g. "123.45" or "-1.23".

=item transactions

The transaction key contains an array reference full of hash references - one
for each transaction in the account's recent history. The transactions are
stored from new to old.

=over 2

=item date

The date of the transaction, e.g. "JAN 02"

=item type

The type of the transaction, e.g. "DD".

=item desc

The description associated with the transaction, e.g. "NSPCC".

=item paidin

The amount paid in during this transaction, which may be "", e.g. "10.00".

=item paidout

The amount paid out during this transaction, which may be "", e.g. "10.00".

=item balance

The account balance after this transaction occured, which may not be present,
e.g. "12.00".

=back

=item statements

The statement key contains a hash reference, where each key is the date which
a statement was issued (YYYY-MM-DD), and each value is an array reference
which contains hash references - one for each statement entry extracted. The
statement entries are stored from new to old.

=over 2

=item date

The date of the transaction, e.g. "JAN 02"

=item type

The type of the transaction, e.g. "DD".

=item desc

The description associated with the transaction, e.g. "NSPCC".

=item paidin

The amount paid in during this transaction, which may be "", e.g. "10.00".

=item paidout

The amount paid out during this transaction, which may be "", e.g. "10.00".

=item balance

The account balance after this transaction occured, which may not be present,
e.g. "12.00".

=back

=back

=head1 SEE ALSO

=over 2

=item L<Finance::Bank::LloydsTSB>

This module was used a base for the original version of this module. See
L</THANKS>, below.

=back

=head1 WARNING

This warning is from Simon Cozens' C<Finance::Bank::LloydsTSB>, and seems
just as apt here.

This is code for B<online banking>, and that means B<your money>, and
that means B<BE CAREFUL>. You are encouraged, nay, expected, to audit
the source of this module yourself to reassure yourself that I am not
doing anything untoward with your banking data. This software is useful
to me, but is provided under B<NO GUARANTEE>, explicit or implied.

=head1 THANKS

Simon Cozens for L<Finance::Bank::LloydsTSB>, upon which most of the original
code was based, Andy Lester (and Skud, by continuation) for L<WWW::Mechanize>,
Gisle Aas for L<HTML::TokeParser>, Leon Cowle for updated login code after HSBC
changed their HTML the first time.

A special thanks to Real Programmers Ltd L<http://realprogrammers.com/> for
sponsoring development of the script in order to bring it up to date
(22/01/2007).

=head1 AUTHOR

Matt Wilson E<lt>matt _at_ mattsscripts _dot_ co _dot_ ukE<gt>.

Original version by Chris Ball C<chris@cpan.org>.

=cut

# vim:ts=4:sw=4:et
