package Finance::Bank::HSBC;
use strict;
use Carp;
our $VERSION = '1.05';

use WWW::Mechanize;
use HTML::TableExtract;

sub check_balance {
    my ($class, %opts) = @_;
    my @accounts;
    croak "Must provide a security code" unless exists $opts{seccode};
    croak "Must provide a banking id" unless exists $opts{bankingid};
    croak "Must provide a date of birth" unless exists $opts{dateofbirth};

    my $self = bless { %opts }, $class;
    
    my $agent = WWW::Mechanize->new();
    #$agent->get("http://www.ukpersonal.hsbc.com/public/ukpersonal/internet_banking/en/logon.jhtml");
    $agent->get("http://www.hsbc.co.uk/1/2/personal/internet-banking");

    # Fill in and submit the login form. (banking id) 
    $agent->form_number(1);
    $agent->field('userid', $opts{bankingid});
    $agent->click("IBlogon");

    # This brings us to the security page,
    # Get the list of the requested security code digits (in words)
    my @seccodedigits_req;
    if ($agent->content(format=>'text') =~ /The ([A-Z]+ and .*) digits of your Security Number/g) {
	# Turn the string reponse from the regex into an array of words
	# by splitting on the 'and' word
        @seccodedigits_req = split(/\s+and\s+/i, $1);
    }
    else {
        croak "Was expecting request for security code digits"; 
    }

    # Hash to convert words to numbers
    my %word2digit = (
		FIRST			=>	1,
		SECOND			=>	2,
		THIRD			=>	3,
		FOURTH			=>	4,
		FIFTH			=>	5,
		SIXTH			=>	6,
		SEVENTH			=>	7,
		EIGHTH			=>	8,
		NINETH			=>	9,
		'NEXT TO LAST'		=>	length($opts{'seccode'}) - 1,
		LAST			=>	length($opts{'seccode'}),
	);

    # Generate response to security code request
    my $seccodedigits;
    foreach my $digit (@seccodedigits_req) {
	# Use digit from %word2digit as the index for the substring. this gives
	# us the required digit to append to the response
        $seccodedigits .= substr($opts{'seccode'}, $word2digit{$digit} - 1, 1);
    }
	
    # Fill in and submit the security questions form
    $agent->field('memorableAnswer', $opts{dateofbirth});
    $agent->field('password', $seccodedigits);
    $agent->submit_form(form_number => 0);

    # Follow Links to Continue (sets up session cookies etc...)
    # we ned to do this twice
    $agent->follow_link( text => 'here' );
    $agent->follow_link( text => 'Click here to continue' );

    # Now we have the data, we need to parse it.
    # we use TabelExtract to extract the table based on the headings
    my $te = HTML::TableExtract->new( headers => ['Account name','Account number','Balance']);
    $te->parse($agent->{content});

    foreach my $row ($te->rows) {
        my $acc_name = @$row[0];
        my $acc_type = @$row[0];
        my $acc_num  = @$row[1];
        my $acc_bal  = @$row[2];

        # Remove gubbins around account name
        # (everything before a . surrounded by whitespace)
        $acc_name =~ s/^\s+.*\s+\.\s+//;

        # Extract Account Type from Javascript
        $acc_type =~ s/\s+.*\>(.*)\<\/a\>\"\)\;\s+\.\s+.*/$1/gi;

        # Remove all leading and trailing spaces
        $acc_name =~ s/^\s+//;
        $acc_name =~ s/\s+$//;
        $acc_num  =~ s/^\s+//;
        $acc_num  =~ s/\s+$//;
        $acc_bal  =~ s/^\s+//;
        $acc_bal  =~ s/\s+$//;

	# Turn balance strings into integers (add '-' if required)
	$acc_bal =~ s/\s(C|D)$//;
	$acc_bal = -$acc_bal if($1 eq 'D');

        # Remove '-' (dash) from acc number
        $acc_num =~ s/\-//g;

        # Skip any empty entries
        next unless($acc_bal && $acc_num && $acc_name);

	# Add to the accounts array
        push @accounts, {
             balance    => $acc_bal,
             name       => $acc_name,
             type       => $acc_type,
             account    => $acc_num,
	};

    }

    # Return the data
    return @accounts;
}

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Finance::Bank::HSBC - Check your HSBC bank accounts from Perl

=head1 SYNOPSIS

  use Finance::Bank::HSBC;
  my @accounts = Finance::Bank::HSBC->check_balance(
      bankingid   => "IBxxxxxxxxxx",
      seccode     => "xxxxxx",
      dateofbirth => "ddmmyy"
  );

  foreach (@accounts) {
      printf "%25s : %13s / %18s : GBP %8.2f\n",
        $_->{name}, $_->{type}, $_->{account}, $_->{balance};
  }

=head1 DESCRIPTION

This module provides a rudimentary interface to the HSBC online
banking system at C<https://www.ebank.hsbc.co.uk/>. 

=head1 DEPENDENCIES

You will need either C<Crypt::SSLeay> or C<IO::Socket::SSL> installed 
for HTTPS support to work with LWP.  This module also depends on 
C<WWW::Mechanize> and C<HTML::TableExtract> for screen-scraping.

=head1 CLASS METHODS

    check_balance(bankingid => $u, seccode => $p, dateofbirth => $d)

Return an array of account hashes, one for each of your bank accounts.

=head1 ACCOUNT HASH KEYS 

    $ac->name
    $ac->type
    $ac->account
    $ac->balance
 
Return the account owner's name, account type (eg. 'STUDENT A/C'), account
number, and balance as a signed floating point value.

=head1 WARNING

This warning is from Simon Cozens' C<Finance::Bank::LloydsTSB>, and seems
just as apt here.

This is code for B<online banking>, and that means B<your money>, and
that means B<BE CAREFUL>. You are encouraged, nay, expected, to audit
the source of this module yourself to reassure yourself that I am not
doing anything untoward with your banking data. This software is useful
to me, but is provided under B<NO GUARANTEE>, explicit or implied.

=head1 THANKS

Simon Cozens for C<Finance::Bank::LloydsTSB>, upon which most of this code
is based, Andy Lester (and Skud, by continuation) for C<WWW::Mechanize> and 
Matt Sisk for C<HTML::TableExtract>

=head1 AUTHOR

Chris Ball C<chris@cpan.org>

=cut

