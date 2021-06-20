# Generating

To generate `x86_64.o`, simply use the command `x86_64-w64-mingw32-windres resource.rc x86_64.o`.
To generate `i386.o`, simply use the command `x86_64-w64-mingw32-windres --target=pe-i386 resource.rc i386.o`.