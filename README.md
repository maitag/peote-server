# peote-server
perl5 tcp-server just with joint-protocol  

This [TCP](https://en.wikipedia.org/wiki/Transmission_Control_Protocol) [Socket](https://upload.wikimedia.org/wikipedia/commons/thumb/3/3e/BLW_Pair_of_socks.jpg/320px-BLW_Pair_of_socks.jpg) Server together with [PeoteNet](https://github.com/maitag/peote-net) helps me  
to do crossplatform networkcoding with haxe.  

It is based on a simple Protocol called "joints" that did fast redirection of of Data
between many clients (only <=2 Bytes overhead each tcp-packet).  

(Todo: scheme picture hier)  

Up to 128 joints (open channels per user) will be handled with max. 255 users per joint.  


## Perl 5 Environment

On Linux everything should run out of the box (`apt install perl5 libpoe-perl && cpan Protocol::WebSocket`),
for Windows i recommend to use [strawberryperl](http://strawberryperl.com/).  

### Perlmodule dependencies
- [POE](http://search.cpan.org/~rcaputo/POE-1.367/lib/POE.pm) - ( http://poe.perl.org/ )
- [Protocol::WebSocket](http://search.cpan.org/~vti/Protocol-WebSocket/lib/Protocol/WebSocket.pm)  

### Start the Server
- configure ports, max connections per ip and logging inside `peote-server.conf`
- run the server `perl -I. peote-server.pl`


## TODO:
- more test-clients & debugging
- damonizing (linux)
- hardening (iptables)
- standalone packages (par)
