include $(top_srcdir)/Makefile.am.common

AM_CPPFLAGS += -DLIBRESSL_CRYPTO_INTERNAL

AM_CPPFLAGS += -I $(top_srcdir)/crypto/asn1
AM_CPPFLAGS += -I $(top_srcdir)/crypto/bio
AM_CPPFLAGS += -I $(top_srcdir)/crypto/bn
AM_CPPFLAGS += -I $(top_srcdir)/crypto/evp
AM_CPPFLAGS += -I $(top_srcdir)/crypto/modes
AM_CPPFLAGS += -I $(top_srcdir)/crypto/x509
AM_CPPFLAGS += -I $(top_srcdir)/ssl
AM_CPPFLAGS += -I $(top_srcdir)/apps/openssl
AM_CPPFLAGS += -I $(top_srcdir)/apps/openssl/compat
AM_CPPFLAGS += -D_PATH_SSL_CA_FILE=\"$(top_srcdir)/cert.pem\"

LDADD = $(abs_top_builddir)/tls/.libs/libtls.a
LDADD += $(abs_top_builddir)/ssl/.libs/libssl.a
LDADD += $(abs_top_builddir)/crypto/.libs/libcrypto.a
LDADD += $(PLATFORM_LDADD) $(PROG_LDADD)
if HOST_ASM_MACOSX_X86_64
LDADD += $(abs_top_builddir)/crypto/.libs/libcrypto_la-cpuid-macosx-x86_64.o
endif

TEST_LOG_DRIVER = env AM_TAP_AWK='$(AWK)' $(SHELL) $(top_srcdir)/tap-driver.sh

TESTS =
check_PROGRAMS =
EXTRA_DIST = CMakeLists.txt
DISTCLEANFILES = pidwraptest.txt

# aeadtest
TESTS += aeadtest.sh
check_PROGRAMS += aeadtest
aeadtest_SOURCES = aeadtest.c
EXTRA_DIST += aeadtest.sh
EXTRA_DIST += aeadtests.txt
EXTRA_DIST += aes_128_gcm_tests.txt
EXTRA_DIST += aes_192_gcm_tests.txt
EXTRA_DIST += aes_256_gcm_tests.txt
EXTRA_DIST += chacha20_poly1305_tests.txt
EXTRA_DIST += xchacha20_poly1305_tests.txt

# aes_wrap
TESTS += aes_wrap
check_PROGRAMS += aes_wrap
aes_wrap_SOURCES = aes_wrap.c

# arc4randomforktest
# Windows/mingw does not have fork, but Cygwin does.
if !HOST_WIN
TESTS += arc4randomforktest.sh
check_PROGRAMS += arc4randomforktest
arc4randomforktest_SOURCES = arc4randomforktest.c
endif
EXTRA_DIST += arc4randomforktest.sh

# asn1_string_to_utf8
TESTS += asn1_string_to_utf8
check_PROGRAMS += asn1_string_to_utf8
asn1_string_to_utf8_SOURCES = asn1_string_to_utf8.c

# asn1api
TESTS += asn1api
check_PROGRAMS += asn1api
asn1api_SOURCES = asn1api.c

# asn1basic
TESTS += asn1basic
check_PROGRAMS += asn1basic
asn1basic_SOURCES = asn1basic.c

# asn1complex
TESTS += asn1complex
check_PROGRAMS += asn1complex
asn1complex_SOURCES = asn1complex.c

# asn1evp
TESTS += asn1evp
check_PROGRAMS += asn1evp
asn1evp_SOURCES = asn1evp.c

# asn1object
TESTS += asn1object
check_PROGRAMS += asn1object
asn1object_SOURCES = asn1object.c

# asn1string_copy
TESTS += asn1string_copy
check_PROGRAMS += asn1string_copy
asn1string_copy_SOURCES = asn1string_copy.c

# asn1test
TESTS += asn1test
check_PROGRAMS += asn1test
asn1test_SOURCES = asn1test.c

# asn1time
TESTS += asn1time
check_PROGRAMS += asn1time
asn1time_SOURCES = asn1time.c

# asn1x509
TESTS += asn1x509
check_PROGRAMS += asn1x509
asn1x509_SOURCES = asn1x509.c

# base64test
TESTS += base64test
check_PROGRAMS += base64test
base64test_SOURCES = base64test.c

# bftest
TESTS += bftest
check_PROGRAMS += bftest
bftest_SOURCES = bftest.c

# biotest
# the BIO tests rely on resolver results that are OS and environment-specific
if ENABLE_EXTRATESTS
TESTS += biotest
check_PROGRAMS += biotest
biotest_SOURCES = biotest.c
endif

# bnaddsub
TESTS += bnaddsub
check_PROGRAMS += bnaddsub
bnaddsub_SOURCES = bnaddsub.c

# bn_isqrt
TESTS += bn_isqrt
check_PROGRAMS += bn_isqrt
bn_isqrt_SOURCES = bn_isqrt.c

# bn_mod_exp2_mont
TESTS += bn_mod_exp2_mont
check_PROGRAMS += bn_mod_exp2_mont
bn_mod_exp2_mont_SOURCES = bn_mod_exp2_mont.c

# bn_mod_sqrt
TESTS += bn_mod_sqrt
check_PROGRAMS += bn_mod_sqrt
bn_mod_sqrt_SOURCES = bn_mod_sqrt.c

# bn_primes
TESTS += bn_primes
check_PROGRAMS += bn_primes
bn_primes_SOURCES = bn_primes.c

# bn_rand_interval
TESTS += bn_rand_interval
check_PROGRAMS += bn_rand_interval
bn_rand_interval_SOURCES = bn_rand_interval.c

# bntest
TESTS += bntest
bntest_CPPFLAGS = $(AM_CPPFLAGS) -ULIBRESSL_INTERNAL
check_PROGRAMS += bntest
bntest_SOURCES = bntest.c

# bn_to_string
TESTS += bn_to_string
check_PROGRAMS += bn_to_string
bn_to_string_SOURCES = bn_to_string.c

# buffertest
TESTS += buffertest
check_PROGRAMS += buffertest
buffertest_SOURCES = buffertest.c

# bytestringtest
TESTS += bytestringtest
check_PROGRAMS += bytestringtest
bytestringtest_SOURCES = bytestringtest.c

# casttest
TESTS += casttest
check_PROGRAMS += casttest
casttest_SOURCES = casttest.c

# chachatest
TESTS += chachatest
check_PROGRAMS += chachatest
chachatest_SOURCES = chachatest.c

# cipher_list
TESTS += cipher_list
check_PROGRAMS += cipher_list
cipher_list_SOURCES = cipher_list.c
noinst_HEADERS = tests.h

# cipherstest
TESTS += cipherstest
check_PROGRAMS += cipherstest
cipherstest_SOURCES = cipherstest.c

# clienttest
TESTS += clienttest
check_PROGRAMS += clienttest
clienttest_SOURCES = clienttest.c

# cmstest
TESTS += cmstest
check_PROGRAMS += cmstest
cmstest_SOURCES = cmstest.c

# configtest
TESTS += configtest
check_PROGRAMS += configtest
configtest_SOURCES = configtest.c

# constraints
TESTS += constraints
check_PROGRAMS += constraints
constraints_SOURCES = constraints.c

# cts128test
TESTS += cts128test
check_PROGRAMS += cts128test
cts128test_SOURCES = cts128test.c

# destest
TESTS += destest
check_PROGRAMS += destest
destest_SOURCES = destest.c

# dhtest
TESTS += dhtest
check_PROGRAMS += dhtest
dhtest_SOURCES = dhtest.c

# dsatest
TESTS += dsatest
check_PROGRAMS += dsatest
dsatest_SOURCES = dsatest.c

# dtlstest
if !HOST_WIN
TESTS += dtlstest.sh
check_PROGRAMS += dtlstest
dtlstest_SOURCES = dtlstest.c
endif
EXTRA_DIST += dtlstest.sh

# ec_asn1_test
TESTS += ec_asn1_test
check_PROGRAMS += ec_asn1_test
ec_asn1_test_SOURCES = ec_asn1_test.c

# ec_point_conversion
TESTS += ec_point_conversion
check_PROGRAMS += ec_point_conversion
ec_point_conversion_SOURCES = ec_point_conversion.c

# ecdhtest
TESTS += ecdhtest
check_PROGRAMS += ecdhtest
ecdhtest_SOURCES = ecdhtest.c

# ecdsatest
TESTS += ecdsatest
check_PROGRAMS += ecdsatest
ecdsatest_SOURCES = ecdsatest.c

# ectest
TESTS += ectest
check_PROGRAMS += ectest
ectest_SOURCES = ectest.c

# enginetest
TESTS += enginetest
check_PROGRAMS += enginetest
enginetest_SOURCES = enginetest.c

# evp_pkey_check
TESTS += evp_pkey_check
check_PROGRAMS += evp_pkey_check
evp_pkey_check_SOURCES = evp_pkey_check.c

# evp_pkey_cleanup
TESTS += evp_pkey_cleanup
check_PROGRAMS += evp_pkey_cleanup
evp_pkey_cleanup_SOURCES = evp_pkey_cleanup.c

# evptest
TESTS += evptest.sh
check_PROGRAMS += evptest
evptest_SOURCES = evptest.c
EXTRA_DIST += evptest.sh
EXTRA_DIST += evptests.txt

# explicit_bzero
# explicit_bzero relies on SA_ONSTACK, which is unavailable on Windows
if !HOST_WIN
if !HOST_CYGWIN
TESTS += explicit_bzero
check_PROGRAMS += explicit_bzero
explicit_bzero_SOURCES = explicit_bzero.c
if !HAVE_MEMMEM
explicit_bzero_SOURCES += compat/memmem.c
endif
endif
endif

# exptest
TESTS += exptest
check_PROGRAMS += exptest
exptest_CPPFLAGS = $(AM_CPPFLAGS) -ULIBRESSL_INTERNAL
exptest_SOURCES = exptest.c

# freenull
TESTS += freenull
check_PROGRAMS += freenull
freenull_SOURCES = freenull.c

# gcm128test
TESTS += gcm128test
check_PROGRAMS += gcm128test
gcm128test_SOURCES = gcm128test.c

# gost2814789t
TESTS += gost2814789t
check_PROGRAMS += gost2814789t
gost2814789t_SOURCES = gost2814789t.c

# handshake_table
TESTS += handshake_table
check_PROGRAMS += handshake_table
handshake_table_SOURCES = handshake_table.c

# hkdf_test
TESTS += hkdftest
check_PROGRAMS += hkdftest
hkdftest_SOURCES = hkdf_test.c

# hmactest
TESTS += hmactest
check_PROGRAMS += hmactest
hmactest_SOURCES = hmactest.c

# ideatest
TESTS += ideatest
check_PROGRAMS += ideatest
ideatest_SOURCES = ideatest.c

# igetest
TESTS += igetest
check_PROGRAMS += igetest
igetest_SOURCES = igetest.c

# key_schedule
TESTS += key_schedule
check_PROGRAMS += key_schedule
key_schedule_SOURCES = key_schedule.c

# keypairtest
TESTS += keypairtest.sh
keypairtest_CPPFLAGS = -I $(top_srcdir)/tls $(AM_CPPFLAGS)
check_PROGRAMS += keypairtest
keypairtest_SOURCES = keypairtest.c
EXTRA_DIST += keypairtest.sh

# md_test
TESTS += md_test
check_PROGRAMS += md_test
md_test_SOURCES = md_test.c

# mont
TESTS += mont
check_PROGRAMS += mont
mont_SOURCES = mont.c

# objectstest
TESTS += objectstest
check_PROGRAMS += objectstest
objectstest_SOURCES = objectstest.c

# ocsp_test
if ENABLE_EXTRATESTS
TESTS += ocsptest.sh
check_PROGRAMS += ocsp_test
ocsp_test_SOURCES = ocsp_test.c
endif
EXTRA_DIST += ocsptest.sh ocsptest.bat

# optionstest
TESTS += optionstest
check_PROGRAMS += optionstest
optionstest_SOURCES = optionstest.c

# pbkdf2
TESTS += pbkdf2
check_PROGRAMS += pbkdf2
pbkdf2_SOURCES = pbkdf2.c

# pidwraptest
# pidwraptest relies on an OS-specific way to give out pids and is generally
# awkward on systems with slow fork
if ENABLE_EXTRATESTS
TESTS += pidwraptest.sh
check_PROGRAMS += pidwraptest
pidwraptest_SOURCES = pidwraptest.c
endif
EXTRA_DIST += pidwraptest.sh

# pkcs7test
TESTS += pkcs7test
check_PROGRAMS += pkcs7test
pkcs7test_SOURCES = pkcs7test.c

# poly1305test
TESTS += poly1305test
check_PROGRAMS += poly1305test
poly1305test_SOURCES = poly1305test.c

# pq_test
TESTS += pq_test.sh
check_PROGRAMS += pq_test
pq_test_SOURCES = pq_test.c
EXTRA_DIST += pq_test.sh pq_test.bat
EXTRA_DIST += pq_expected.txt

# quictest
TESTS += quictest.sh
check_PROGRAMS += quictest
quictest_SOURCES = quictest.c
EXTRA_DIST += quictest.sh quictest.bat

# randtest
TESTS += randtest
check_PROGRAMS += randtest
randtest_SOURCES = randtest.c

# rc2_test
TESTS += rc2_test
check_PROGRAMS += rc2_test
rc2_test_SOURCES = rc2_test.c

# rc4_test
TESTS += rc4_test
check_PROGRAMS += rc4_test
rc4_test_SOURCES = rc4_test.c

# recordtest
TESTS += recordtest
check_PROGRAMS += recordtest
recordtest_SOURCES = recordtest.c

# record_layer_test
TESTS += record_layer_test
check_PROGRAMS += record_layer_test
record_layer_test_SOURCES = record_layer_test.c

# rfc3779
TESTS += rfc3779
rfc3779_CPPFLAGS = $(AM_CPPFLAGS) -D__unused=
check_PROGRAMS += rfc3779
rfc3779_SOURCES = rfc3779.c

# rfc5280time
check_PROGRAMS += rfc5280time
rfc5280time_SOURCES = rfc5280time.c
if SMALL_TIME_T
TESTS += rfc5280time_small.test
else
TESTS += rfc5280time
endif
EXTRA_DIST += rfc5280time_small.test

# rmd_test
TESTS += rmd_test
check_PROGRAMS += rmd_test
rmd_test_SOURCES = rmd_test.c

# rsa_test
TESTS += rsa_test
check_PROGRAMS += rsa_test
rsa_test_SOURCES = rsa_test.c

# servertest
TESTS += servertest.sh
check_PROGRAMS += servertest
servertest_SOURCES = servertest.c
EXTRA_DIST += servertest.sh servertest.bat

# sha_test
TESTS += sha_test
check_PROGRAMS += sha_test
sha_test_SOURCES = sha_test.c

# sm3test
TESTS += sm3test
check_PROGRAMS += sm3test
sm3test_SOURCES = sm3test.c

# sm4test
TESTS += sm4test
check_PROGRAMS += sm4test
sm4test_SOURCES = sm4test.c

# ssl_get_shared_ciphers
TESTS += ssl_get_shared_ciphers
ssl_get_shared_ciphers_CPPFLAGS = $(AM_CPPFLAGS) -DCERTSDIR=\"$(srcdir)\"
check_PROGRAMS += ssl_get_shared_ciphers
ssl_get_shared_ciphers_SOURCES = ssl_get_shared_ciphers.c

# ssl_methods
TESTS += ssl_methods
check_PROGRAMS += ssl_methods
ssl_methods_SOURCES = ssl_methods.c

# ssl_set_alpn_protos
TESTS += ssl_set_alpn_protos
check_PROGRAMS += ssl_set_alpn_protos
ssl_set_alpn_protos_SOURCES = ssl_set_alpn_protos.c

# ssl_versions
TESTS += ssl_versions
check_PROGRAMS += ssl_versions
ssl_versions_SOURCES = ssl_versions.c

# ssltest
TESTS += ssltest.sh
check_PROGRAMS += ssltest
ssltest_SOURCES = ssltest.c
EXTRA_DIST += ssltest.sh ssltest.bat
EXTRA_DIST += testssl testssl.bat
EXTRA_DIST += ca-int-ecdsa.crl ca-int-ecdsa.pem ca-int-rsa.crl ca-int-rsa.pem
EXTRA_DIST += ca-root-ecdsa.pem ca-root-rsa.pem ca.pem client.pem
EXTRA_DIST += client1-ecdsa-chain.pem client1-ecdsa.pem client1-rsa-chain.pem
EXTRA_DIST += client1-rsa.pem client2-ecdsa-chain.pem client2-ecdsa.pem
EXTRA_DIST += client2-rsa-chain.pem client2-rsa.pem client3-ecdsa-chain.pem
EXTRA_DIST += client3-ecdsa.pem client3-rsa-chain.pem client3-rsa.pem
EXTRA_DIST += server.pem server1-ecdsa-chain.pem server1-ecdsa.pem
EXTRA_DIST += server1-rsa-chain.pem server1-rsa.pem server2-ecdsa-chain.pem
EXTRA_DIST += server2-ecdsa.pem server2-rsa-chain.pem server2-rsa.pem
EXTRA_DIST += server3-ecdsa-chain.pem server3-ecdsa.pem server3-rsa-chain.pem
EXTRA_DIST += server3-rsa.pem


# string_table
TESTS += string_table
check_PROGRAMS += string_table
string_table_SOURCES = string_table.c

# testdsa
TESTS += testdsa.sh
EXTRA_DIST += testdsa.sh testdsa.bat
EXTRA_DIST += openssl.cnf

# testenc
TESTS += testenc.sh
EXTRA_DIST += testenc.sh testenc.bat

# testrsa
TESTS += testrsa.sh
EXTRA_DIST += testrsa.sh testrsa.bat

# timingsafe
TESTS += timingsafe
check_PROGRAMS += timingsafe
timingsafe_SOURCES = timingsafe.c

# tlsexttest
TESTS += tlsexttest
check_PROGRAMS += tlsexttest
tlsexttest_SOURCES = tlsexttest.c

# tlslegacytest
TESTS += tlslegacytest
check_PROGRAMS += tlslegacytest
tlslegacytest_SOURCES = tlslegacytest.c

# tlstest
TESTS += tlstest.sh
check_PROGRAMS += tlstest
tlstest_SOURCES = tlstest.c
if !HAVE_PIPE2
tlstest_SOURCES += compat/pipe2.c
endif
EXTRA_DIST += tlstest.sh tlstest.bat

# tls_ext_alpn
TESTS += tls_ext_alpn
check_PROGRAMS += tls_ext_alpn
tls_ext_alpn_SOURCES = tls_ext_alpn.c

# tls_prf
TESTS += tls_prf
check_PROGRAMS += tls_prf
tls_prf_SOURCES = tls_prf.c

# utf8test
TESTS += utf8test
check_PROGRAMS += utf8test
utf8test_SOURCES = utf8test.c

# valid_handshakes_terminate
TESTS += valid_handshakes_terminate
check_PROGRAMS += valid_handshakes_terminate
valid_handshakes_terminate_SOURCES = valid_handshakes_terminate.c

# verifytest
TESTS += verifytest
check_PROGRAMS += verifytest
verifytest_SOURCES = verifytest.c

# x25519test
TESTS += x25519test
check_PROGRAMS += x25519test
x25519test_SOURCES = x25519test.c

# x509attribute
TESTS += x509attribute
check_PROGRAMS += x509attribute
x509attribute_SOURCES = x509attribute.c

# x509_info
TESTS += x509_info
check_PROGRAMS += x509_info
x509_info_SOURCES = x509_info.c

# x509name
TESTS += x509name
check_PROGRAMS += x509name
x509name_SOURCES = x509name.c

# x509req_ext
TESTS += x509req_ext
check_PROGRAMS += x509req_ext
x509req_ext_SOURCES = x509req_ext.c
