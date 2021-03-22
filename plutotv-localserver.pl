#!/usr/bin/perl

package server;

$| = 1;

use strict;
use warnings;

use HTTP::Daemon;
use HTTP::Status;
use HTTP::Request::Params;
use HTTP::Request::Common;
use HTTP::Cookies;
use DateTime;
use DateTime::Format::Strptime qw(strptime);
use JSON;
use JSON::Parse ':all';
use HTTP::Request ();
use LWP::UserAgent;
use URI::Escape;
use UUID::Tiny ':std';
use File::Which;

my $hostip = "127.0.0.1";
my $port   = "9000";
my $apiurl = "http://api.pluto.tv/v2/channels?start={from}Z&stop={to}Z";
#channel-id: 5ddbf866b1862a0009a0648e

my $deviceid = uuid_to_string(create_uuid(UUID_V1));
my $ffmpeg = which 'ffmpeg';

sub get_channel_json {
    my $request = HTTP::Request->new(GET => $apiurl);
    my $useragent = LWP::UserAgent->new;
    my $response = $useragent->request($request);
    if ($response->is_success) {
        return @{parse_json($response->decoded_content)};
    }
    else{
        return ();
    }
}

sub get_from_url {
    my $request = HTTP::Request->new(GET => @_);
    my $useragent = LWP::UserAgent->new;
    my $response = $useragent->request($request);
    if ($response->is_success) {
        return $response->content;
    }
    else{
        return ();
    }
}

sub buildM3U {
    my @senderliste = @_;
    my $m3u = "#EXTM3U\n";
    my $i = 0;
    for my $sender( @senderliste ) {
        if($sender->{number} > 0) {
            my $logo = $sender->{logo}->{path};
            if(defined $logo) {
                $m3u = $m3u . "#EXTINF:-1 tvg-chno=\"" . $sender->{number} . "\" tvg-id=\"" . uri_escape($sender->{name}) . "\" tvg-name=\"" . $sender->{name} . "\" tvg-logo=\"" . $logo . "\" group-title=\"PlutoTV\"," . $sender->{name} . "\n";
                $m3u = $m3u . "pipe://" . $ffmpeg . " -loglevel fatal -threads 2 -re -fflags +genpts+ignidx+igndts -user-agent \"Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:76.0) Gecko/20100101 Firefox/76.0\" -i \"http://" . $hostip . ":" . $port . "/channel?id=" . $sender->{_id} . "\" -vcodec copy -acodec copy -f mpegts -tune zerolatency -metadata service_name=\"" . $sender->{name} . "\" pipe:1\n";
            }
        }
    }
    return $m3u;
}

sub send_m3ufile {
    my $client = $_[0];
    my @senderListe = get_channel_json;
    if(scalar @senderListe <= 0) {
        $client->send_error(RC_INTERNAL_SERVER_ERROR, "Unable to fetch channel-list from pluto.tv-api.");
        return;
    }
    my $m3uContent = buildM3U(@senderListe);
    my $response = HTTP::Response->new();
    $response->header("content-disposition", "filename=\"plutotv.m3u\"");
    $response->code(200);
    $response->message("OK");
    $response->content($m3uContent);

    $client->send_response($response);
}

sub getPlaylistsFromMaster {
    my ($master, $baseurl) = @_;
    my $lines = () = $master =~ m/\n/g;

    my $linebreakpos = 0;
    my $readnextline = 0;
    my $m3u8 = "";
    for (my $linenum=0; $linenum<$lines; $linenum++) {
        my $line = substr($master, $linebreakpos+1, index($master, "\n", $linebreakpos+1)-$linebreakpos);
        if($readnextline == 1) {
            $m3u8 .= $baseurl.$line;
        }
        if(index($line, "#EXT-X-STREAM-INF:PROGRAM-ID=") >=0) {
            $readnextline = 1;
        }
        else {
            $readnextline = 0;
        }
        $linebreakpos = index($master, "\n", $linebreakpos+1);
    }
    return $m3u8;
}

sub fixPlaylistUrlsInMaster {
    my ($master, $baseurl) = @_;
    my $lines = () = $master =~ m/\n/g;

    my $linebreakpos = 0;
    my $readnextline = 0;
    my $m3u8 = "";
    for (my $linenum=0; $linenum<$lines; $linenum++) {
        my $line = substr($master, $linebreakpos+1, index($master, "\n", $linebreakpos+1)-$linebreakpos);
        if($readnextline == 1) {
            $m3u8 .= $baseurl.$line;
            $readnextline = 0;
            $linebreakpos = index($master, "\n", $linebreakpos+1);
            next;
        }
        if(index($line, "#EXT-X-STREAM-INF:PROGRAM-ID=") >=0) {
            $m3u8 .= $line;
            $readnextline = 1;
        }
        else {
          $m3u8 .= $line;
        }
        $linebreakpos = index($master, "\n", $linebreakpos+1);
    }
    return $m3u8;
}

sub send_masterm3u8file {
    my ($client, $request) = @_;
    my $parse_params = HTTP::Request::Params->new({
        req => $request,
    });
    my $params = $parse_params->params;
    my $channelid = $params->{'id'};

    my @senderListe = get_channel_json;
    if(scalar @senderListe <= 0) {
        $client->send_error(RC_INTERNAL_SERVER_ERROR, "Unable to fetch channel-list from pluto.tv-api.");
        return;
    }
    my @sender = grep($_->{_id} =~ /$channelid/ , @senderListe);
    my $url = $sender[0]->{stitched}->{urls}[0]->{url};

    my $sessionuuid = uuid_to_string(create_uuid(UUID_V1));
    $url =~ s/&deviceMake=/&deviceMake=Firefox/ig;
    $url =~ s/&deviceType=/&deviceType=web/ig;
    $url =~ s/&deviceId=unknown/&deviceId=$deviceid/ig;
    $url =~ s/&deviceModel=/&deviceModel=web/ig;
    $url =~ s/&deviceVersion=unknown/&deviceVersion=82\.0/ig;
    $url =~ s/&appName=&/&appName=web&/ig;
    $url =~ s/&appVersion=&/&appVersion=5.9.1-e0b37ef76504d23c6bdc8157813d13333dfa33a3/ig;
    $url =~ s/&sid=/&sid=$sessionuuid&sessionID=$sessionuuid/ig;
    $url =~ s/&deviceDNT=0/&deviceDNT=false/ig;
    $url = $url."&serverSideAds=false&clientDeviceType=0&clientModelNumber=na&clientID=".$deviceid;

    printf("Request for Channel ".$sender[0]->{name}." received");
    my $master = get_from_url($url);
    my $baseurl = substr($url, 0, index($url, $channelid)+length($channelid)+1);

    $master =~ s/terminate=true/terminate=false/ig;
    $master = fixPlaylistUrlsInMaster($master, $baseurl);
    #$playlists =~ s/terminate=true/terminate=false/ig;


    my $response = HTTP::Response->new();
    $response->header("content-disposition", "filename=\"master.m3u8\"");
    $response->code(200);
    $response->message("OK");
    $response->content($master);

    $client->send_response($response);
    printf(" and served.\n");
}

sub process_request {
    my $from = DateTime->now();
    my $to = $from->add(hours => 6);

    $apiurl =~ s/{from}/$from/ig;
    $apiurl =~ s/{to}/$to/ig;

    my $deamon = shift;
    my $client = $deamon->accept or die("could not get any Client");
    my $request = $client->get_request() or die("could not get Client-Request.");
    $client->autoflush(1);

    #http://localhost:9000/playlist <-- liefert m3u aus
    #http://localhost:9000/channel?id=xxxx <-- liefert Stream des angefragten Senders

    if($request->uri->path eq "/playlist") {
        send_m3ufile($client);
    }
    elsif($request->uri->path eq "/channel") {
        send_masterm3u8file($client, $request);
    }
    else {
        $client->send_error(RC_NOT_FOUND, "No such path available: ".$request->uri->path);
    }
}

# START DAEMON
my $deamon = HTTP::Daemon->new(
    LocalAddr => $hostip,
    LocalPort => $port,
    Reuse => 1,
    ReuseAddr => 1,
    ReusePort => $port,
) or die "Server could not be started.\n\n";

printf("Server started on port ".$port."\n");
while (1) {
    process_request($deamon);
}
printf("Server stopped\n");