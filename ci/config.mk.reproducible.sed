# Add link-time optimization for even better performance
/^CFLAGS[[:blank:]]*=/s/$/ -fdebug-prefix-map=`pwd`=./
/^LDFLAGS[[:blank:]]*=/s/$/ -Wl,-reproducible -Wl,-oso_prefix,. -Wl,-object_path_lto,lto.o/
