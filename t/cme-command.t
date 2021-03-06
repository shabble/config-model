use strict ;
use warnings ;
use File::Path ;
use Probe::Perl ;

use Test::Command 0.08 ;
use Test::More;
use Test::File::Contents;

if ( $^O =~ /linux|bsd|solaris|sunos/ ) {
    plan tests => 10;
}
else {
    plan skip_all => "Test with system() in build systems don't work well on this OS ($^O)";
}

## testing exit status

# pseudo root where config files are written by config-model
my $wr_root = 'wr_root';

# cleanup before tests
rmtree($wr_root);

my $test1 = 'popcon1' ;
my $wr_dir = $wr_root.'/'.$test1 ;
my $conf_file = "$wr_dir/etc/popularity-contest.conf" ;

my $path = Probe::Perl->find_perl_interpreter();

my $perl_cmd = $path . ' -Ilib ' .join(' ',map { "-I$_" } Probe::Perl->perl_inc());

my $oops = Test::Command->new( 
  cmd => "$perl_cmd script/cme modify popcon -root_dir $wr_dir PARITICIPATE=yes"
);

exit_cmp_ok($oops, '>',0,'missing config file detected');
stderr_like($oops, qr/cannot find configuration file/, 'check auto_read_error') ;

# put popcon data in place
my @orig = <DATA> ;


mkpath($wr_dir.'/etc', { mode => 0755 }) 
  || die "can't mkpath: $!";
open(CONF,"> $conf_file" ) || die "can't open $conf_file: $!";
print CONF @orig ;
close CONF ;

$oops = Test::Command->new( 
  cmd => "$perl_cmd script/cme modify popcon -root_dir $wr_dir PARITICIPATE=yes");
exit_cmp_ok($oops, '>',0,'wrong parameter detected');
stderr_like($oops, qr/unknown element/, 'check unknown element') ;

# use -force-load to force a file save to update file header
my $ok = Test::Command->new( 
  cmd => "$perl_cmd script/cme modify popcon -force-load -root_dir $wr_dir PARTICIPATE=yes"
);
exit_is_num($ok, 0,'all went well');

file_contents_like $conf_file, qr/cme/, "updated header";
file_contents_unlike $conf_file, qr/removed`/, "double comment is removed";

my $search = Test::Command->new( 
  cmd => "$perl_cmd script/cme search popcon -root_dir $wr_dir -search y -narrow value");
exit_is_num($search, 0,'search went well');
stdout_like($search,qr/PARTICIPATE/,"got PARTICIPATE");
stdout_like($search,qr/USEHTTP/,"got USEHTTP");

__END__
# Config file for Debian's popularity-contest package.
#
# To change this file, use:
#        dpkg-reconfigure popularity-contest

## should be removed

MY_HOSTID="aaaaaaaaaaaaaaaaaaaa"
# we participate
PARTICIPATE="yes"
USEHTTP="yes" # always http
DAY="6"

