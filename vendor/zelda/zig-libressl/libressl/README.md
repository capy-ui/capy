![LibreSSL image](https://www.libressl.org/images/libressl.jpg)
## Official portable version of [LibreSSL](https://www.libressl.org) ##

[![Linux Build Status](https://github.com/libressl-portable/portable/actions/workflows/linux_test.yml/badge.svg)](https://github.com/libressl-portable/portable/actions/workflows/linux_test.yml)
[![macOS Build Status](https://github.com/libressl-portable/portable/actions/workflows/macos_test.yml/badge.svg)](https://github.com/libressl-portable/portable/actions/workflows/macos_test.yml)
[![Android_Build Status](https://github.com/libressl-portable/portable/actions/workflows/android_test.yml/badge.svg)](https://github.com/libressl-portable/portable/actions/workflows/android_test.yml)
[![Cross_Build Status](https://github.com/libressl-portable/portable/actions/workflows/cross_test.yml/badge.svg)](https://github.com/libressl-portable/portable/actions/workflows/cross_test.yml)
[![Fuzzing Status](https://oss-fuzz-build-logs.storage.googleapis.com/badges/libressl.svg)](https://bugs.chromium.org/p/oss-fuzz/issues/list?sort=-opened&can=1&q=proj:libressl)
[![ASan Status](https://github.com/libressl-portable/portable/actions/workflows/linux_test_asan.yml/badge.svg)](https://github.com/libressl-portable/portable/actions/workflows/linux_test_asan.yml)

LibreSSL is a fork of [OpenSSL](https://www.openssl.org) 1.0.1g developed by the
[OpenBSD](https://www.openbsd.org) project.  Our goal is to modernize the codebase,
improve security, and apply best practice development processes from OpenBSD.

## Compatibility with OpenSSL: ##

LibreSSL is API compatible with OpenSSL 1.0.1, but does not yet include all
new APIs from OpenSSL 1.0.2 and later. LibreSSL also includes APIs not yet
present in OpenSSL. The current common API subset is OpenSSL 1.0.1.

LibreSSL is not ABI compatible with any release of OpenSSL, or necessarily
earlier releases of LibreSSL. You will need to relink your programs to
LibreSSL in order to use it, just as in moving between major versions of OpenSSL.
LibreSSL's installed library version numbers are incremented to account for
ABI and API changes.

## Compatibility with other operating systems: ##

While primarily developed on and taking advantage of APIs available on OpenBSD,
the LibreSSL portable project attempts to provide working alternatives for
other operating systems, and assists with improving OS-native implementations
where possible.

At the time of this writing, LibreSSL is known to build and work on:

* Linux (kernel 3.17 or later recommended)
* FreeBSD (tested with 9.2 and later)
* NetBSD (7.0 or later recommended)
* HP-UX (11i)
* Solaris (11 and later preferred)
* Mac OS X (tested with 10.8 and later)
* AIX (5.3 and later)

LibreSSL also supports the following Windows environments:
* Microsoft Windows (Windows 7 / Windows Server 2008r2 or later, x86 and x64)
* Wine (32-bit and 64-bit)
* Mingw-w64, Cygwin, and Visual Studio

Official release tarballs are available at your friendly neighborhood
OpenBSD mirror in directory
[LibreSSL](https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/),
although we suggest that you use a [mirror](https://www.openbsd.org/ftp.html).

The LibreSSL portable build framework is also
[mirrored](https://github.com/libressl-portable/portable) in Github.

Please report bugs either to the public libressl@openbsd.org mailing list,
or to the github
[issue tracker](https://github.com/libressl-portable/portable/issues)

Severe vulnerabilities or bugs requiring coordination with OpenSSL can be
sent to the core team at libressl-security@openbsd.org.

# Building LibreSSL #

## Prerequisites when building from a Git checkout ##

If you have checked this source using Git, or have downloaded a source tarball
from Github, follow these initial steps to prepare the source tree for
building. _Note: Your build will fail if you do not follow these instructions! If you cannot follow these instructions (e.g. Windows system using CMake) or cannot meet these prerequistes, please download an official release distribution from https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/ instead. Using official releases is strongly advised if you are not a developer._

1. Ensure you have the following packages installed:
   automake, autoconf, git, libtool, perl
2. Run `./autogen.sh` to prepare the source tree for building or
   run `./dist.sh` to prepare a tarball.

## Steps that apply to all builds ##

Once you have a source tree, either by downloaded using git and having
run the `autogen.sh` script above, or by downloading a release distribution from
an OpenBSD mirror, run these commands to build and install the package on most
systems:

```sh
./configure   # see ./configure --help for configuration options
make check    # runs builtin unit tests
make install  # set DESTDIR= to install to an alternate location
```

If you wish to use the CMake build system, use these commands:

```sh
mkdir build
cd build
cmake ..
make
make test
```

For faster builds, you can use Ninja as well:

```sh
mkdir build-ninja
cd build-ninja
cmake -G"Ninja" ..
ninja
ninja test
```

### OS specific build information: ###

#### HP-UX (11i) ####

Set the UNIX_STD environment variable to `2003` before running `configure`
in order to build with the HP C/aC++ compiler. See the "standards(5)" man
page for more details.

```sh
export UNIX_STD=2003
./configure
make
```

#### Windows - Mingw-w64 ####

LibreSSL builds against relatively recent versions of Mingw-w64, not to be
confused with the original mingw.org project.  Mingw-w64 3.2 or later
should work. See README.windows for more information

#### Windows - Visual Studio ####

LibreSSL builds using the CMake target "Visual Studio 12 2013" and newer. To
generate a Visual Studio project, install CMake, enter the LibreSSL source
directory and run:

```sh
 mkdir build-vs2013
 cd build-vs2013
 cmake -G"Visual Studio 12 2013" ..
```

Replace "Visual Studio 12 2013" with whatever version of Visual Studio you
have installed. This will generate a LibreSSL.sln file that you can incorporate
into other projects or build by itself.

#### Cmake - Additional Options ####

| Option Name | Default | Description
| ------------ | -----: | ------
|  LIBRESSL_SKIP_INSTALL | OFF | allows skipping install() rules.  Can be specified from command line using <br>```-DLIBRESSL_SKIP_INSTALL=ON``` |
|  LIBRESSL_APPS | ON | allows skipping application builds. Apps are required to run tests |
|  LIBRESSL_TESTS | ON | allows skipping of tests. Tests are only available in static builds |
|  BUILD_SHARED_LIBS | OFF | CMake option for building shared libraries. |
|  ENABLE_ASM | ON | builds assembly optimized rules. |
|  ENABLE_EXTRATESTS | OFF | Enable extra tests that may be unreliable on some platforms |
|  ENABLE_NC | OFF | Enable installing TLS-enabled nc(1) |
|  OPENSSLDIR | Blank | Set the default openssl directory.  Can be specified from command line using <br>```-DOPENSSLDIR=<dirname>``` |

# Using LibreSSL #

## CMake ##

Make a new folder in your project root (where your main CMakeLists.txt file is located) called CMake. Copy the FindLibreSSL.cmake file to that folder, and add the following line to your main CMakeLists.txt:

```cmake
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/CMake;${CMAKE_MODULE_PATH}")
```

After your **add_executable** or **add_library** line in your CMakeLists.txt file add the following:

```cmake
find_package(LibreSSL REQUIRED)
```

It will tell CMake to find LibreSSL and if found will let you use the following 3 interfaces in your CMakeLists.txt file:

* LibreSSL::Crypto
* LibreSSL::SSL
* LibreSSL::TLS

If you for example want to use the LibreSSL TLS library in your test program, include it like so (SSL and Cryto are required by TLS and included automatically too):

```cmake
target_link_libraries(test LibreSSL::TLS)
```

Full example:

```cmake
cmake_minimum_required(VERSION 3.10.0)

set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/CMake;${CMAKE_MODULE_PATH}")

project(test)

add_executable(test Main.cpp)

find_package(LibreSSL REQUIRED)

target_link_libraries(test LibreSSL::TLS)
```

#### Linux ####

Following the guide in the sections above to compile LibreSSL using make and running "sudo make install" will install LibreSSL to the /usr/local/ folder, and will found automatically by find_package. If your system installs it to another location or you have placed them yourself in a different location, you can set the CMake variable LIBRESSL_ROOT_DIR to the correct path, to help CMake find the library.

#### Windows ####

Placing the library files in C:/Program Files/LibreSSL/lib and the include files in C:/Program Files/LibreSSL/include should let CMake find them automatically, but it is recommended that you use CMake-GUI to set the paths. It is more convenient as you can have the files in any folder you choose.
