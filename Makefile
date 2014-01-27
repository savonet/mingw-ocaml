.PHONY: all dist clean patch flexdll mingw-ocaml findlib binary install

MINGW_HOST     := i686-w64-mingw32
FLEXDLL_DIR    := flexdll
OCAML_DIR      := ocaml
FINDLIB_DIR    := findlib
OTHER_LIBS     := win32unix str num dynlink bigarray systhreads win32graph
BUILD_DIR      := build
BINARY_DIR     := $(CURDIR)/binary
INSTALL_DIR    := # install at root
INSTALL_PREFIX := /usr
PATH           := $(PATH):$(CURDIR)/$(BUILD_DIR)/$(FLEXDLL_DIR)

ifeq ($(MINGW_HOST),i686-w64-mingw32)
BUILD_CC       := gcc -m32
ARCH           := i386
MINGW_SYSTEM   := mingw
else
BUILD_CC       := gcc
ARCH           := amd64
MINGW_SYSTEM   := mingw64
endif

DISTFILES := LICENSE Makefile README files findlib flexdll ocaml patches.in

all: binary

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)
	cp -rf $(FLEXDLL_DIR)  $(OCAML_DIR) $(FINDLIB_DIR) $(BUILD_DIR)

patches:
	mkdir -p patches
	find patches.in | grep '.patch' | while read i; do \
	  sed -e 's#@mingw_host@#$(MINGW_HOST)#g' < $$i > \
	  `echo $$i | sed -e 's#patches.in#patches#'`; \
	done
	cp patches.in/series patches

patch: stamp-quilt-patches

stamp-quilt-patches: patches $(BUILD_DIR)
	quilt push -a
	touch stamp-quilt-patches

flexdll: stamp-build-flexdll

stamp-build-flexdll: stamp-quilt-patches
	cd $(BUILD_DIR)/$(FLEXDLL_DIR) && make flexlink.exe build_mingw build_mingw64
	rm -f $(BUILD_DIR)/$(FLEXDLL_DIR)/flexlink
	ln -s flexlink.exe $(BUILD_DIR)/$(FLEXDLL_DIR)/flexlink
	touch stamp-build-flexdll

mingw-ocaml: stamp-binary-mingw-ocaml

stamp-build-ocamlcore: stamp-quilt-patches
	# Build native ocamlrun and ocamlc which contain the
	# filename-win32-dirsep patch.
	#
	# Note that we must build a 32 bit compiler, even on 64 bit build
	# architectures, because this compiler will try to do strength
	# reduction optimizations using its internal int type, and that must
	# match Windows' int type.  (That's what -cc and -host are for).
	cd $(BUILD_DIR)/$(OCAML_DIR) && ./configure \
	  -prefix $(INSTALL_PREFIX)/$(MINGW_HOST) \
	  -bindir $(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	  -libdir $(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	  -no-tk \
	  -cc "$(BUILD_CC)" -host $(MINGW_HOST) -verbose
	cd $(BUILD_DIR)/$(OCAML_DIR) && make world
	# Now move the working ocamlrun, ocamlc into the boot/ directory,
	# overwriting the binary versions which ship with the compiler with
	# ones that contain the filename-win32-dirsep patch.
	cd $(BUILD_DIR)/$(OCAML_DIR) && make coreboot
	touch stamp-build-ocamlcore

stamp-patch-mingw-include: stamp-build-ocamlcore
	# Now patch utils/clflags.ml to hardcode mingw-specific include.
	patch -p1 < patches/ocaml-hardcode_mingw_include.patch
	touch stamp-patch-mingw-include

stamp-prepare-cross-build: stamp-patch-mingw-include
	# Replace the compiler configuration (config/{s.h,m.h,Makefile})
	# with ones as they would be on a 32 bit Windows system.
	cp -f $(BUILD_DIR)/$(OCAML_DIR)/config/m-nt.h $(BUILD_DIR)/$(OCAML_DIR)/config/m.h
	cp -f $(BUILD_DIR)/$(OCAML_DIR)/config/s-nt.h $(BUILD_DIR)/$(OCAML_DIR)/config/s.h
	# config/Makefile is a custom one which we supply.
	rm -f $(BUILD_DIR)/$(OCAML_DIR)/config/Makefile
	sed \
	  -e "s,@prefix@,/usr/$(MINGW_HOST),g" \
	  -e "s,@bindir@,/usr/$(MINGW_HOST)/bin,g" \
	  -e "s,@libdir@,/usr/$(MINGW_HOST)/lib/ocaml,g" \
	  -e "s,@otherlibraries@,$(OTHER_LIBS),g" \
	  -e "s,@arch@,$(ARCH),g" \
	  -e "s,@mingw_system@,$(MINGW_SYSTEM),g" \
	  -e "s,@flexdir@,$(CURDIR)/$(BUILD_DIR)/$(FLEXDLL_DIR),g" \
	  -e "s,@flexlink_mingw_chain@,$(MINGW_SYSTEM),g" \
	  -e "s,@mingw_host@,$(MINGW_HOST),g" \
	  < files/ocaml//Makefile-mingw.in > $(BUILD_DIR)/$(OCAML_DIR)/config/Makefile
	# We're going to build in otherlibs/win32unix and otherlibs/win32graph
	# directories, but since they would normally only be built under
	# Windows, they only have the Makefile.nt files.  Just symlink
	# Makefile -> Makefile.nt for these cases.
	for d in $(BUILD_DIR)/$(OCAML_DIR)/otherlibs/win32unix \
	         $(BUILD_DIR)/$(OCAML_DIR)/otherlibs/win32graph \
	         $(BUILD_DIR)/$(OCAML_DIR)/otherlibs/bigarray \
	         $(BUILD_DIR)/$(OCAML_DIR)/otherlibs/systhreads; do \
	  ln -sf Makefile.nt $$d/Makefile; \
	done
	# Now clean the temporary files from the previous build.  This
	# will also cause asmcomp/arch.ml (etc) to be linked to the 32 bit
	# i386 versions, essentially causing ocamlopt to use the Win/i386 code
	# generator.
	cd $(BUILD_DIR)/$(OCAML_DIR) && make partialclean
	# We need to remove any .o object for make sure they are
	# recompiled later..
	cd $(BUILD_DIR)/$(OCAML_DIR) && rm byterun/*.o
	# Finally, make a stamp file to tell myocamlbuild to
	# build for win32
	touch $(BUILD_DIR)/$(OCAML_DIR)/stamp-build-mingw-win32
	touch stamp-prepare-cross-build

stamp-build-mingw-ocaml: stamp-build-flexdll stamp-prepare-cross-build
	# Just rebuild some small bits that we need for the following
	# 'make opt' to work.  Note that 'make all' fails here.
	cd $(BUILD_DIR)/$(OCAML_DIR) && make -C byterun libcamlrun.a
	cd $(BUILD_DIR)/$(OCAML_DIR) && make ocaml ocamlc
	cd $(BUILD_DIR)/$(OCAML_DIR) && make -C stdlib
	cd $(BUILD_DIR)/$(OCAML_DIR) && make -C tools ocamlmklib
	cd $(BUILD_DIR)/$(OCAML_DIR) && make opt
	# Now build otherlibs for ocamlopt
	cd $(BUILD_DIR)/$(OCAML_DIR) && \
	for i in $(OTHER_LIBS); do \
	  make -C otherlibs/$$i clean; \
	  PATH=$(CURDIR)/$(BUILD_DIR)/$(FLEXDLL_DIR):$(PATH) \
	    make -C otherlibs/$$i all; \
	  PATH=$(CURDIR)/$(BUILD_DIR)/$(FLEXDLL_DIR):$(PATH) \
	    make -C otherlibs/$$i allopt; \
	done
	# Finally build all tools
	cd $(BUILD_DIR)/$(OCAML_DIR) && make -C tools
	touch stamp-build-mingw-ocaml

stamp-binary-mingw-ocaml: stamp-build-mingw-ocaml
	mkdir -p $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/threads
	mkdir -p $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/stublibs
	mkdir -p $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin
	mkdir -p $(BINARY_DIR)$(INSTALL_PREFIX)/bin
	mkdir -p $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/compiler-libs
	cd $(BUILD_DIR)/$(OCAML_DIR) && make BINDIR=$(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	                                        LIBDIR=$(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	                                        -C byterun install
	cd $(BUILD_DIR)/$(OCAML_DIR) && make BINDIR=$(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	                                        LIBDIR=$(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	                                        -C stdlib install
	cd $(BUILD_DIR)/$(OCAML_DIR) && \
	for i in $(OTHER_LIBS); do \
	  make BINDIR=$(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	       LIBDIR=$(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	       -C otherlibs/$$i install; \
	done
	cd $(BUILD_DIR)/$(OCAML_DIR) && make BINDIR=$(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	                                        LIBDIR=$(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	                                        -C tools install
	cd $(BUILD_DIR)/$(OCAML_DIR) && make BINDIR=$(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	                                        LIBDIR=$(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	                        installopt
	cd $(BUILD_DIR)/$(OCAML_DIR) && install -m 0755 ocamlc $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin
	cd $(BUILD_DIR)/$(OCAML_DIR) && cp \
	  toplevel/topstart.cmo \
	  typing/outcometree.cmi typing/outcometree.mli \
	  toplevel/toploop.cmi toplevel/toploop.mli \
	  toplevel/topdirs.cmi toplevel/topdirs.mli \
 	  toplevel/topmain.cmi toplevel/topmain.mli \
	  $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml
	# Rename all the binaries to target-binary
	for f in ocamlc ocamlcp ocamlrun ocamldep ocamlmklib ocamlmktop ocamlopt ocamlprof; do \
	  mv $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin/$$f $(BINARY_DIR)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-$$f; \
	done
	# We do not need this.
	rm -rf $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/compiler-libs
	touch stamp-binary-mingw-ocaml

findlib: stamp-build-findlib

stamp-build-findlib: stamp-binary-mingw-ocaml
	cd $(BUILD_DIR)/$(FINDLIB_DIR)/tools/extract_args && make
	$(BUILD_DIR)/$(FINDLIB_DIR)/tools/extract_args/extract_args \
	  -o $(BUILD_DIR)/$(FINDLIB_DIR)/src/findlib/ocaml_args.ml \
	  $(BINARY_DIR)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-ocamlc \
	  $(BINARY_DIR)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-ocamlcp \
	  $(BINARY_DIR)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-ocamlmktop \
	  $(BINARY_DIR)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-ocamlopt \
	  $(BINARY_DIR)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-ocamldep
	cd $(BUILD_DIR)/$(FINDLIB_DIR) && ./configure \
	  -config /etc/$(MINGW_HOST)-ocamlfind.conf \
	  -bindir  $(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	  -sitelib $(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	  -mandir $(INSTALL_PREFIX)/share/man \
	  -with-toolbox
	cd $(BUILD_DIR)/$(FINDLIB_DIR) && make all
	cd $(BUILD_DIR)/$(FINDLIB_DIR) && make opt
	touch stamp-build-findlib

binary: stamp-binary-all

stamp-binary-all: stamp-build-findlib
	# Install findlib
	# Create this dir to please install..
	mkdir -p $(BINARY_DIR)$(INSTALL_PREFIX)/lib/ocaml
	cd $(BUILD_DIR)/$(FINDLIB_DIR) && make install \
						prefix=$(BINARY_DIR)
	# Remove ocamlfind binary - we will use the native version.
	rm $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin/ocamlfind
	# Remove findlib & num-top libs: if anything uses these we can
	# add them back later.
	rm -r $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/findlib
	rm -r $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/num-top
	# XXX topfind gets installed as %{_libdir}/ocaml - not sure why
	# but delete it anyway.
	rm -rf $(BINARY_DIR)$(INSTALL_PREFIX)/lib/ocaml
	# Override /etc/%{_mingw_target}-ocamlfind.conf with our
	# own version.
	rm $(BINARY_DIR)/etc/$(MINGW_HOST)-ocamlfind.conf
	sed \
	  -e "s,@libdir@,$(INSTALL_PREFIX)/$(MINGW_HOST)/lib,g" \
	  -e 's,@target@,$(MINGW_HOST),g' \
	  < files/findlib/ocamlfind.conf.in \
	  > $(BINARY_DIR)/etc/$(MINGW_HOST)-ocamlfind.conf
	# Install flexlink binary
	mkdir -p $(BINARY_DIR)$(INSTALL_PREFIX)/lib/flexdll
	cd $(BUILD_DIR)/$(FLEXDLL_DIR) && install -m 0755 flexlink.exe flexdll_mingw.o flexdll_initer_mingw.o \
	                                                               flexdll_mingw64.o flexdll_initer_mingw64.o \
	                                                     $(BINARY_DIR)$(INSTALL_PREFIX)/lib/flexdll
	# Nothing in /usr/$(MINGW_HOST)/lib/ocaml should 'a priori' be executable except flexlink.exe..
	find $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml -type f -executable | grep -v flexlink.exe | while read i; do \
	    chmod -x $$i; done
	# Now make all script with #!/usr/bin/ocamlrun executables
	grep -r -l '#!/usr/$(MINGW_HOST)/bin/ocamlrun' $(BINARY_DIR)$(INSTALL_PREFIX)/bin | while read i; do \
	  sed -e 's|#!/usr/$(MINGW_HOST)/bin/ocamlrun|#!/usr/bin/$(MINGW_HOST)-ocamlrun|' -i $$i; \
	  chmod +x $$i; done
	# Remove rm -rf $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin: all binaries should be prefixed and living in /usr/bin..
	rm -rf $(BINARY_DIR)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin
	touch stamp-binary-all

install: stamp-binary-all
	find $(BINARY_DIR) -type f | sed -e s'#$(BINARY_DIR)##g' | while read i; do \
	  [ -d $(INSTALL_DIR)`dirname $$i` ] || mkdir -p $(INSTALL_DIR)`dirname $$i`; \
	  cp -f $(BINARY_DIR)/$$i $(INSTALL_DIR)`dirname $$i`; \
	done
	# Symlink flexlink to flexlink.exe
	rm -f $(INSTALL_DIR)$(INSTALL_PREFIX)/bin/flexlink
	ln -s ../lib/flexdll/flexlink.exe $(INSTALL_DIR)$(INSTALL_PREFIX)/bin/flexlink

clean:
	rm -rf $(BUILD_DIR) $(BINARY_DIR) $(INSTALL_DIR) patches .pc/ stamp-*

dist: clean
	rm -rf mingw-ocaml
	mkdir mingw-ocaml
	cp -rf $(DISTFILES) mingw-ocaml
	find mingw-ocaml -name .git | xargs rm -rf
	tar cvzf mingw-ocaml.tar.gz mingw-ocaml
	rm -rf mingw-ocaml 
