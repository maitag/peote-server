# peote-server
perl tcp-server just with joint-protocol  

This TCP IP Socket Server together with [PeoteNet](https://github.com/maitag/peote-net) API helps me in
network-coding more abstract and platform-independent with haxe.  

It is based on a simple Protocol called "joints" that did fast redirection of of Data
between many clients (only <=2 Bytes overhead each tcp-packet).

(Todo: scheme picture hier)  



Up to 128 joints will be handled
with max. 255 users per joint.

use with care ;)  




###TODO:
- more tests and samples
- damonizing for linux
- hardening against flooding test
- blacklisting via iptables
- standalone for win32 users

