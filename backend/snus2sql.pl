#!/usr/bin/perl -w
use strict;
use LWP::Simple;
use JSON::XS qw( decode_json);
use Data::Dumper;
use DBI();
use POSIX qw(setsid);
use Sys::Syslog qw(:DEFAULT setlogsock);

# References
# http://stackoverflow.com/questions/5210523/simple-json-parsing-perl
# http://xmodulo.com/2013/04/how-to-parse-json-string-in-perl.html

my %Options=(
  db_host     =>"localhost",
  db_database =>"spacenearer",
  db_user     =>"spacenearer",
  db_pass     =>"",
  data_url    =>"http://spacenear.us/tracker/data.php",
  max_records =>100,
  sleep_time  =>3,
  lock_file   =>$ENV{"HOME"} . "/run/snus2sql.pid"
);

if  ( -f $Options{'lock_file'}){
	print "A process is already running\n";
	exit -1;
}
open (_LOCK, ">".$Options{'lock_file'}) or die "Unable to create lockfile\n";
&daemonize;
print _LOCK "$$";
close _LOCK;

my $lastpos=0;
my $loop=1;
my $entries=0;

# Syslog
setlogsock('unix');
openlog('snus2sql', 'cons,pid', 'local1');

$SIG{HUP}= \&catch_hup;
$SIG{INT}= \&catch_hup;

syslog('info', 'Starting');
while ($loop){
	$entries=0;	# Reset Counter
	my $dbh = DBI->connect("DBI:mysql:host=$Options{'db_host'};database=$Options{'db_database'}", $Options{'db_user'},$Options{'db_pass'});

	# Check we're connected to the DB
	if ($dbh){

		# Prep SQL Statements
		my $addPosition=$dbh->prepare("insert into positions values (?,?,?,?,MICROSECOND(?)/1e6,?,MICROSECOND(?)/1e6,?,?,?,?,?,?,?,?)");
		my $addCall=$dbh->prepare("insert into positions_call values (?,?)");
		my $addData=$dbh->prepare("insert into positions_data values (?,?,?)");

		# If lastpos is 0 get the largest position_id from the db
		if ($lastpos==0){
			my $getMaxPos=$dbh->prepare("select max(position_id) as lastPosID from positions");
			$getMaxPos->execute();
			if ($getMaxPos->rows() ==1 ){
				my $row=$getMaxPos->fetchrow_hashref;
				if (defined($row->{'lastPosID'})){
					$lastpos=$row->{'lastPosID'};
				}
			}
			$getMaxPos->finish();
		}

		# Get data.php json data
		my $json = get($Options{'data_url'}."?format=json&position_id=".$lastpos."&max_positions=".$Options{'max_records'});
		if ($json){
			my $json_out=decode_json($json);
			my @positions=@{$json_out->{'positions'}{'position'}};
			foreach my $pos (@positions){
				$entries++;
				my $logmsg=$pos->{'vehicle'}."(".$pos->{'position_id'}."),\t";
				$addPosition->execute(
					$pos->{'position_id'},
					$pos->{'mission_id'},
					$pos->{'vehicle'},
					$pos->{'server_time'},
					$pos->{'server_time'},
					$pos->{'gps_time'},
					$pos->{'gps_time'},
					$pos->{'gps_lat'},
					$pos->{'gps_lon'},
					$pos->{'gps_alt'},
					$pos->{'gps_heading'},
					$pos->{'gps_speed'},
					$pos->{'picture'},
					$pos->{'temp_inside'},
					$pos->{'sequence'});

				# Process Habitat data
				if ($pos->{'data'} ne ""){
					my %data=%{decode_json($pos->{'data'})};
					for (keys %data){
						$addData->execute($pos->{'position_id'},$_,$data{$_});
					}
				}

				# Process Callsign data
				foreach (split(",",$pos->{'callsign'})){
					$logmsg .= $_."\t";
					$addCall->execute($pos->{'position_id'},$_);
				}
	
				$lastpos=$pos->{'position_id'} if ($lastpos < $pos->{'position_id'});
				syslog('info',$logmsg);
			} # foreach
		} else { # if($json)
			sleep(60) if $loop;
		}
		$addPosition->finish();
		$addCall->finish();
		$addData->finish();
		$dbh->disconnect();
	} else { #if ($dbh)
		sleep(60) if $loop;
	}

	sleep($Options{'sleep_time'}) if ($entries<$Options{'max_records'});
} #while($loop)

unlink $Options{'lock_file'};

sub daemonize {
	chdir '/'                 or die "Can't chdir to /: $!";
	defined(my $pid = fork)   or die "Can't fork: $!";
	exit if $pid;
	setsid                    or die "Can't start a new session: $!";
	umask 0;
}

sub catch_hup {
	$loop=0;
	syslog('warning', 'Got HUP');
}

__END__
-- SQL Schema used for this script
-- Should work on 5.1 upwards
-- 7dp for lat/lon allows 11mm preceision

CREATE TABLE positions (
	`position_id`    INT unsigned NOT Null,
	`mission_id`     INT unsigned,
	`vehicle`        CHAR(30) not null,
	`server_time`    DATETIME,
	`server_time_ms` DECIMAL(7,6),
	`gps_time`       DATETIME,
	`gps_time_ms`    DECIMAL(7,6),
	`gps_lat`        DECIMAL(11,7) not null,
	`gps_lon`        DECIMAL(11,7) not NULL,
	`gps_alt`        DECIMAL(8,2) not NULL,
	`gps_heading`    DECIMAL(8,3),
	`gps_speed`      DECIMAL(8,3),
	`picture`        CHAR(100),
	`temp_inside`    DECIMAL(7,2),
	`sequence`       int unsigned,
	PRIMARY KEY      (`position_id`),
	KEY `vehicle`    (`vehicle`),
	KEY `sequence`   (`sequence`)
) ENGINE=InnoDB;

-- callsign => 'ASTRA',
CREATE TABLE positions_call (
	`position_id` INT UNSIGNED NOT NULL,
	`callsign`    CHAR(20),
	KEY `position_id` (`position_id`)
) ENGINE=InnoDB;

-- data => '{"uv": "-0.002", "temperature_external": "7.29", "light": 0, "temperature_external_ds": "6.3", "humidity": 9289, "pressure": "101600.0", "battery_raw": "4.93", "ir": 0}',
CREATE TABLE positions_data (
	`position_id` INT UNSIGNED NOT NULL,
	`key`         CHAR(30),
	`val`         CHAR(30),
	KEY `position_id` (`position_id`)
) ENGINE=InnoDB;

==== End of Schema ====




ONSTRAINT `acl_ibfk_2` FOREIGN KEY (`userid`) REFERENCES `passwd` (`id_passwd`) ON DELETE CASCADE

http://spacenear.us/tracker/data.php
{"positions": {"position": [
{"position_id":"3944630","mission_id":"0","vehicle":"VK4HIA_chase","server_time":"2013-12-07 05:15:06.497451","gps_time":"2013-12-07 05:15:05","gps_lat":"-26.7692583427","gps_lon":"153.112194808","gps_alt":"0.0751953125","gps_heading":"","gps_speed":"0","picture":"","temp_inside":"","data":"","callsign":"","sequence":""}
{"position_id":"3939504","mission_id":"0","vehicle":"POP1","server_time":"2013-12-06 23:22:25.365001","gps_time":"2013-12-06 23:22:22","gps_lat":"50.931785","gps_lon":"-1.3857067","gps_alt":"12","gps_heading":"","gps_speed":"","picture":"","temp_inside":"13.2","data":"{\"uv\": \"-0.002\", \"temperature_external\": \"7.29\", \"light\": 0, \"temperature_external_ds\": \"6.3\", \"humidity\": 9289, \"pressure\": \"101600.0\", \"battery_raw\": \"4.93\", \"ir\": 0}","callsign":"ASTRA","sequence":"185"}
]}} 

http://spacenear.us/tracker/receivers.php
[
{"lat": 51.247592, "alt": 117.0, "lon": -1.177061, "name": "M0CJM", "description": "\n<font size=\"-2\"><BR>\n<B>Radio: </B>Kenwood TS2000 &amp; Signalink USB<BR>\n<B>Antenna: </B>Triband Vertical<BR>\n<B>Last Contact: </B>7 hours ago<BR>\n</font>\n"},
{"lat": 50.935265, "alt": 0.0, "lon": -1.393789, "name": "ASTRA", "description": "\n<font size=\"-2\"><BR>\n<B>Radio: </B>FT-817<BR>\n<B>Antenna: </B>2m/70cms Colinear<BR>\n<B>Last Contact: </B>4 hours ago<BR>\n</font>\n"} 
{"lat": 45.380844, "alt": 236.0, "lon": 4.820123, "name": "F4UGF", "description": "\n<font size=\"-2\"><BR>\n<B>Radio: </B>FT-817<BR>\n<B>Antenna: </B>QUAGI UHF V<BR>\n<B>Last Contact: </B>13 hours ago<BR>\n</font>\n"}
]

http://spacenear.us/tracker/get_predictions.php

