package Finance::Bank::HSBC;
use strict;
use Carp;
our $VERSION = '1.00';

use WWW::Mechanize;
use HTML::TokeParser;

sub check_balance {
    my ($class, %opts) = @_;
    my @accounts;
    croak "Must provide a security code" unless exists $opts{seccode};
    croak "Must provide a banking id" unless exists $opts{bankingid};

    my $self = bless { %opts }, $class;
    
    my $agent = WWW::Mechanize->new();
    $agent->get("https://www.ebank.hsbc.co.uk/main/loginmain.jsp");

    # Filling in the login form. 
    $agent->form(0);
    $agent->field("internetBankingID", $opts{bankingid});
    $agent->field("telephoneSecurityNumber", $opts{seccode}); 
    $agent->click("ok");

    # We're given a redirect, and then need to navigate a frameset.
    $agent->follow(0);
    $agent->follow("master");
    $agent->follow("main");

    # We need to perform a new GET request on the portfolio page.
    my @links = @{$agent->{links}};
    my $bal   = $links[2];
    $agent->get(@{$bal});

    # More frameset navigation.
    $agent->follow(0);
    $agent->follow("main");

    # Now we have the data, we need to parse it.  This is fragile.
    my $content = $agent->{content};

    my ($split1, $split2)  = split /<!-- bgcolor="#9D0710" -->/, $content;
    my ($content, $split2) = split /portform/, $split2;

    my $stream = HTML::TokeParser->new(\$content) or die "$!";
    
    while (my $token = $stream->get_tag("tr")) {
        $token = $stream->get_tag("td");
        
        if ($token->[1]{height} eq "25") {
            # We have an account!
            my $accountname = $stream->get_trimmed_text("/td");
            $stream->get_tag("td");

            my $accounttype = $stream->get_trimmed_text("/td");
            $stream->get_tag("td");

            my $accountnumber = $stream->get_trimmed_text("/td");
            $stream->get_tag("td");
            $stream->get_tag("td");

            my $accountbalance = $stream->get_trimmed_text("/td");

            # Convert / [CD]$/ to a positive or negative float.
            $accountbalance =~ s/ C$//;
            $accountbalance = "-$accountbalance" if $accountbalance =~ s/ D$//;
                   
            push @accounts, {
                balance    => $accountbalance,
                name       => $accountname,
                type       => $accounttype,
                account    => $accountnumber
            };
        }
    }
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
      bankingid => "IBxxxxxxxxxx",
      seccode   => "xxxxxx"
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
C<WWW::Mechanize> and C<HTML::TokeParser> for screen-scraping.

=head1 CLASS METHODS

    check_balance(bankingid => $u, seccode => $p)

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
is based, Andy Lester (and Skud, by continuation) for WWW::Mechanize, Gisle
Aas for HTML::TokeParser.

=head1 AUTHOR

Chris Ball C<chris@cpan.org>

=cut

