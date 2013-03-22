.PHONY: all clean patch dlfcn-win32 mingw-ocaml

MINGW_HOST  := i686-w64-mingw32
DLFCN_DIR   := dlfcn-win32
OCAML_DIR   := ocaml
FINDLIB_DIR := findlib 
OTHER_LIBS  := win32unix str num dynlink bigarray systhreads win32graph
BUILD_DIR   := build

all: patch dlfcn-win32 mingw-ocaml

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)
	cp -rf $(DLFCN_DIR)  $(OCAML_DIR) $(FINDLIB_DIR) $(BUILD_DIR)

patch: stamp-quilt-patches

stamp-quilt-patches: $(BUILD_DIR)
	quilt push -a
	touch stamp-quilt-patches

dlfcn-win32: stamp-build-dlfcn-win32

stamp-build-dlfcn-win32: $(BUILD_DIR)
	cd $(BUILD_DIR)/$(DLFCN_DIR) && ./configure --prefix=tmp/ --cross-prefix=$(MINGW_HOST)- --enable-static
	cd $(BUILD_DIR)/$(DLFCN_DIR) && $(MAKE)
	touch stamp-build-dlfcn-win32

mingw-ocaml: stamp-build-ocamlcore

stamp-build-ocamlcore: $(BUILD_DIR)
	# Build native ocamlrun and ocamlc which contain the
	# filename-win32-dirsep patch.
	#
	# Note that we must build a 32 bit compiler, even on 64 bit build
	# architectures, because this compiler will try to do strength
	# reduction optimizations using its internal int type, and that must
	# match Windows' int type.  (That's what -cc and -host are for).
	cd $(BUILD_DIR)/$(OCAML_DIR) && ./configure \
	  -prefix /usr/$(MINGW_HOST) \
	  -bindir /usr/$(MINGW_HOST)/bin \
	  -libdir /usr/$(MINGW_HOST)/lib/ocaml \
	  -no-tk \
	  -cc "gcc -m32" -host $(MINGW_HOST) -x11lib /usr/lib -verbose
	cd $(BUILD_DIR)/$(OCAML_DIR) && make world
	# Now move the working ocamlrun, ocamlc into the boot/ directory,
	# overwriting the binary versions which ship with the compiler with
	# ones that contain the filename-win32-dirsep patch.
	cd $(BUILD_DIR)/$(OCAML_DIR) && make coreboot
	touch stamp-build-ocamlcore

clean:
	rm -rf $(BUILD_DIR) .pc/ stamp-*
