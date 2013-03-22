.PHONY: all clean-quilt-patches clean-dlfcn-win32 clean

MINGW_HOST  := i686-w64-mingw32
DLFCN_DIR   := dlfcn-win32
OCAML_DIR   := ocaml
FINDLIB_DIR := findlib 
OTHER_LIBS  := win32unix str num dynlink bigarray systhreads win32graph

all: tmp stamp-quilt-patches  stamp-build-dlfcn-win32

tmp:
	mkdir -p tmp

stamp-quilt-patches:
	quilt push -a
	touch stamp-quilt-patches

clean-quilt-patches:
	quilt pop -a
	rm -f stamp-quilt-patches

stamp-build-dlfcn-win32:
	cd $(DLFCN_DIR) && ./configure --prefix=tmp/ --cross-prefix=$(MINGW_HOST)- --enable-static
	cd $(DLFCN_DIR) && $(MAKE)
	touch stamp-build-dlfcn-win32

clean-dlfcn-win32:
	cd $(DLFCN_DIR) && $(MAKE) clean || true
	cd $(DLFCN_DIR) && rm -rf config.mak
	rm -f stamp-build-dlfcn-win32

clean: clean-dlfcn-win32 clean-quilt-patches
	rm -rf tmp
