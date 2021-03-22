# plutoTV-tvheadend
Perl-Script to generate m3u and xmltv-epg from PlutoTV-API.  
So far, there are still short interruptions when advertising starts or ends.  
      
There are two ways to use these scripts:
* you can generate a static m3u by using the `plutotv-generate.pl`-script with params 
* you can start `plutotv-localserver.pl` as local HTTP-Server and call it via URLs


## install used modules
`sudo cpan install DateTime DateTime::Format::Strptime JSON JSON:Parse HTTP::Request URI::Escape LWP::UserAgent UUID::Tiny File::Which`

when using `--localserver` also:
`sudo cpan install HTTP::Request::Params HTTP::Deamon HTTP::Status HTTP::Requst::Common HTTP::Cookies`


## usage
`perl plutotv-generate.pl [--createm3u] [--usebash] [--useffmpeg | --usestreamlink]

### or
`perl plutotv-localserver.pl` (or start as systemd-daemon)

## how to load xmltv-guide into tvheadend
* Go to menu option "Configuration" > "Channel/EPG" > "EPG Grabber Modules" and enable "External: XMLTV"
* Go to menu option "Configuration" > "Channel/EPG" > "Channel" > "Map services" > "Map all services" and map the services
* Run the following command twice:

`cat plutotv-epg.xml | socat - UNIX-CONNECT:/var/lib/hts/.hts/tvheadend/epggrab/xmltv.sock`


## more
PlutoTV only delivers timelines 6h in future. So epg has to be fetched at least every 6 hours:
crontab:
`15 */6 * * * perl plutotv-generate.pl`

