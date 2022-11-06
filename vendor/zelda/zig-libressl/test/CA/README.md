
# Happy Bob's Test CA

This implements a dumb CA with a root, intermediate, and ocsp signer using the
openssl command..

While I am OK with you learning from it, please remember:

### Friends do not let friends use the openssl(1) command in production!

It's nasty and horrible. it does not check return values. for the love of Cthulhu don't trust it for anything real and expose it to input that could come from untrusted sources!

I am using it here for *TESTING*, and that's all you should do with it.  You've been warned.

Now having said that. the Makefile in here sets everything up.

- "make" builds the root CA, intermediate, and ocsp signer, along with a server and client certificate, both having a CN for "localhost".
- "make clean" blows away *everything* including the signers and issued certs. Don't do this if you want to keep using the same certs.
-  "makecert.sh" is a little shell script that can be use to make client and server certs with an arbitrary CN and email address.
-  "ocspfetch.sh" Retreives the OCSP response for server.crt using openssl commands.
