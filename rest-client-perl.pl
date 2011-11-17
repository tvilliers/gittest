#!/usr/bin/env perl
use warnings;
use strict;
$|++;

use REST::Client;
use JSON;

use Digest::SHA1 qw(sha1_hex);
use MIME::Base64 qw(encode_base64);

use Data::Dumper;

my $user = '__YOUR__NAME';
my $pass = '__YOUR_SECRET';

sub _auth_digest {
    my $text = shift;
    my $hash = sha1_hex($text);
    my $encode = encode_base64($hash);
    chomp $encode;
    return $encode;
}

sub _auth_header_text {
    my ( $user, $secret ) = ( shift, shift );
    my $nonce = time() . rand();
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);
    $mon++;
    $year += 1900;
    my $omtr_time = sprintf( "%d-%02d-%02d %02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec );
    my $pw_digest = _auth_digest( $nonce . $omtr_time . $secret );
    my $headers = qq{UsernameToken Username="$user", PasswordDigest="$pw_digest", Nonce="$nonce", Created="$omtr_time"};
    return $headers;
}

my $host = "https://api2.omniture.com";
my $path = "/admin/1.2/rest/";

my ( $done, $error ) = ( 0, 0 );

my $client = REST::Client->new();
$client->setHost($host);

## $client->getUseragent->add_handler("request_send",  sub { shift->dump; return });
## $client->getUseragent->add_handler("response_done", sub { shift->dump; return });

##
## Company.GetTokenCount
##

my $method = "Company.GetTokenCount";
my $data = "";

$client->POST("$path?method=$method", $data, {"X-WSSE" => _auth_header_text($user,$pass)});

if ( $client->responseCode() == 200 ) {
    print "available tokens : " . $client->responseContent() . "\n";
} else {
    $error = 1;
    print "something went really wrong!\n";
    print Dumper($client->getInfo());
}

##
## Report.QueueRanked
##

$method="Report.QueueRanked";
$data='{
    "reportDescription":{
        "reportSuiteID":"__YOUR_REPORTSUITE",
        "dateFrom":"2011-11-01",
        "dateTo":"2011-11-11",
        "metrics":[{"id":"pageviews"}],
        "elements":[{"id":"page","top":"20"}]
    }
}';

$client->POST("$path?method=$method", $data, {"X-WSSE" => _auth_header_text($user,$pass)});

my $report_id;

if ( $client->responseCode() == 200 ) {
    my $response = $client->responseContent();
    my $json = from_json($response);
    if ( $json->{"status"} eq "queued" ) {
        $report_id = $json->{"reportID"};
        print "queued reportID : $report_id\n";
    } else {
        $error = 1;
        print "not queued - error!\n";
    }
} else {
    $error = 1;
    print "something went really wrong!\n";
    print Dumper($client->getInfo());
}

##
## Report.GetStatus
##

while ( $done < 1 ) { ##&& $error != 1 ) {
    print "waiting for report ... \n";
    sleep(15);
        
    $method = "Report.GetStatus";
    $data = '{"reportID":"' . $report_id . '"}';

    my ( $response, $json );
    
    $client->POST("$path?method=$method", $data, {"X-WSSE" => _auth_header_text($user,$pass)});
    
    if ( $client->responseCode() == 200 ) {
        $response = $client->responseContent();
        $json = from_json($response);
        if ( $json->{"status"} eq "done" ) {
            $done = 1;
        } elsif ( $json->{"status"} eq "failed" ) { ##or ($json->status, "error")>0) {
            $error = 1;
        } else {
            $done = 1;
            $error = 1;
            print "something went really wrong!\n";
            print Dumper($client->getInfo());
        }
    }

    ##
    ## Report.GetReport
    ##

    if ( $error == 1 ) {
        print "report failed:\n";
        print $response;
    } else {
        $method = "Report.GetReport";
        $data = '{"reportID":"' . $report_id . '"}';
        
        $client->POST("$path?method=$method", $data, {"X-WSSE" => _auth_header_text($user,$pass)});

        if ( $client->responseCode() == 200 ) {
            $response = $client->responseContent();;
            $json = from_json($response);
            ## print Dumper($json);
            print "Page - PageViews\n";
            foreach my $row ( @{ $json->{"report"}{"data"}} ) {
                print $row->{"name"} . " - " . $row->{"counts"}->[0] . "\n";
            }
        } else {
            print "something went really wrong!\n";
            print Dumper($client->getInfo());
        }
    }
}

exit($error);

