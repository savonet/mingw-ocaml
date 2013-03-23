.PHONY: all clean patch flexdll mingw-ocaml install

MINGW_HOST     := i686-w64-mingw32
FLEXDLL_DIR    := flexdll
OCAML_DIR      := ocaml
FINDLIB_DIR    := findlib
OTHER_LIBS     := win32unix str num dynlink bigarray systhreads win32graph
BUILD_DIR      := build
INSTALL_ROOT   := $(CURDIR)/binary
INSTALL_PREFIX := /usr/local

ifeq ($(MINGW_HOST),i686-w64-mingw32)
BUILD_CC       := gcc -m32
FLEXLINK_CHAIN := mingw
else
BUILD_CC       := gcc
FLEXLINK_CHAIN := mingw64
endif

all: install

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
	cd $(BUILD_DIR)/$(FLEXDLL_DIR) && make flexlink.exe build_$(FLEXLINK_CHAIN)
	touch stamp-build-flexdll

mingw-ocaml: stamp-install-mingw-ocaml

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
	  -e "s,@flexdir@,$(CURDIR)/$(BUILD_DIR)/$(FLEXDLL_DIR),g" \
	  -e "s,@flexlink_mingw_chain@,$(FLEXLINK_CHAIN),g" \
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
	# Build ocamlopt
	cd $(BUILD_DIR)/$(OCAML_DIR) && PATH=$(CURDIR)/$(BUILD_DIR)/$(FLEXDLL_DIR):$(PATH) \
	                                   make opt
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

stamp-install-mingw-ocaml: stamp-build-mingw-ocaml
	mkdir -p $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/threads
	mkdir -p $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/stublibs
	mkdir -p $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin
	mkdir -p $(INSTALL_ROOT)$(INSTALL_PREFIX)/bin
	mkdir -p $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/compiler-libs
	cd $(BUILD_DIR)/$(OCAML_DIR) && make BINDIR=$(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	                                        LIBDIR=$(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	                                        -C byterun install
	cd $(BUILD_DIR)/$(OCAML_DIR) && make BINDIR=$(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	                                        LIBDIR=$(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	                                        -C stdlib install
	cd $(BUILD_DIR)/$(OCAML_DIR) && \
	for i in $(OTHER_LIBS); do \
	  make BINDIR=$(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	       LIBDIR=$(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	       -C otherlibs/$$i install; \
	done
	cd $(BUILD_DIR)/$(OCAML_DIR) && make BINDIR=$(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	                                        LIBDIR=$(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	                                        -C tools install
	cd $(BUILD_DIR)/$(OCAML_DIR) && make BINDIR=$(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin \
	                                        LIBDIR=$(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml \
	                        installopt
	cd $(BUILD_DIR)/$(OCAML_DIR) && install -m 0755 ocamlc $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin
	cd $(BUILD_DIR)/$(OCAML_DIR) && cp \
	  toplevel/topstart.cmo \
	  typing/outcometree.cmi typing/outcometree.mli \
	  toplevel/toploop.cmi toplevel/toploop.mli \
	  toplevel/topdirs.cmi toplevel/topdirs.mli \
 	  toplevel/topmain.cmi toplevel/topmain.mli \
	  $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml
	# Rename all the binaries to target-binary
	for f in ocamlc ocamlcp ocamlrun ocamldep ocamlmklib ocamlmktop ocamlopt ocamlprof; do \
	  mv $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin/$$f $(INSTALL_ROOT)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-$$f; \
	done
	# We do not need this.
	rm -rf $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/compiler-libs
	touch stamp-install-mingw-ocaml

findlib: stamp-build-findlib

stamp-build-findlib: stamp-install-mingw-ocaml
	cd $(BUILD_DIR)/$(FINDLIB_DIR)/tools/extract_args && make
	$(BUILD_DIR)/$(FINDLIB_DIR)/tools/extract_args/extract_args \
	  -o $(BUILD_DIR)/$(FINDLIB_DIR)/src/findlib/ocaml_args.ml \
	  $(INSTALL_ROOT)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-ocamlc \
	  $(INSTALL_ROOT)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-ocamlcp \
	  $(INSTALL_ROOT)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-ocamlmktop \
	  $(INSTALL_ROOT)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-ocamlopt \
	  $(INSTALL_ROOT)$(INSTALL_PREFIX)/bin/$(MINGW_HOST)-ocamldep
	cd $(BUILD_DIR)/$(FINDLIB_DIR) && ./configure \
	  -config /etc/$(MINGW_HOST)-ocamlfind.conf \
	  -bindir /usr/$(MINGW_HOST)/bin \
	  -sitelib /usr/$(MINGW_HOST)/lib/ocaml \
	  -mandir /usr/share/man \
	  -with-toolbox
	cd $(BUILD_DIR)/$(FINDLIB_DIR) && make all
	cd $(BUILD_DIR)/$(FINDLIB_DIR) && make opt
	touch stamp-build-findlib

install: stamp-install-all

stamp-install-all: stamp-build-findlib
	# Install findlib
	# Create this dir to please install..
	mkdir -p $(INSTALL_ROOT)$(INSTALL_PREFIX)/lib/ocaml
	cd $(BUILD_DIR)/$(FINDLIB_DIR) && make install \
						prefix=$(INSTALL_ROOT)
	# Remove ocamlfind binary - we will use the native version.
	rm $(INSTALL_ROOT)/usr/$(MINGW_HOST)/bin/ocamlfind
	# Remove findlib & num-top libs: if anything uses these we can
	# add them back later.
	rm -r $(INSTALL_ROOT)/usr/$(MINGW_HOST)/lib/ocaml/findlib
	rm -r $(INSTALL_ROOT)/usr/$(MINGW_HOST)/lib/ocaml/num-top
	# XXX topfind gets installed as %{_libdir}/ocaml - not sure why
	# but delete it anyway.
	rm -rf $(INSTALL_ROOT)/usr/lib/ocaml
	# Override /etc/%{_mingw_target}-ocamlfind.conf with our
	# own version.
	rm $(INSTALL_ROOT)/etc/$(MINGW_HOST)-ocamlfind.conf
	sed \
	  -e "s,@libdir@,/usr/$(MINGW_HOST)/lib,g" \
	  -e 's,@target@,$(MINGW_HOST),g' \
	  < files/findlib/ocamlfind.conf.in \
	  > $(INSTALL_ROOT)/etc/$(MINGW_HOST)-ocamlfind.conf
	# Install flexlink binary
	mkdir -p $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/flexdll
	cd $(BUILD_DIR)/$(FLEXDLL_DIR) && install -m 0755 flexlink.exe flexdll_$(FLEXLINK_CHAIN).o flexdll_initer_$(FLEXLINK_CHAIN).o \
	                                                     $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml/flexdll
	# Symkink flexlink to flexlink.exe
	rm -f $(INSTALL_ROOT)$(INSTALL_PREFIX)/bin/flexlink
	ln -s ../$(MINGW_HOST)/lib/ocaml/flexdll/flexlink.exe $(INSTALL_ROOT)$(INSTALL_PREFIX)/bin/flexlink
	# Nothing in /usr/$(MINGW_HOST)/lib/ocaml should 'a priori' be executable except flexlink.exe..
	find $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/lib/ocaml -type f -executable | grep -v flexlink.exe | while read i; do \
	    chmod -x $$i; done
	# Now make all script with #!/usr/bin/ocamlrun executables
	grep -r -l '#!/usr/$(MINGW_HOST)/bin/ocamlrun' $(INSTALL_ROOT)$(INSTALL_PREFIX)/bin | while read i; do \
	  sed -e 's|#!/usr/$(MINGW_HOST)/bin/ocamlrun|#!/usr/bin/$(MINGW_HOST)-ocamlrun|' -i $$i; \
	  chmod +x $$i; done
	# Remove rm -rf $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin: all binaries should be prefixed and living in /usr/bin..
	rm -rf $(INSTALL_ROOT)$(INSTALL_PREFIX)/$(MINGW_HOST)/bin
	touch stamp-install-all

root_install: # stamp-install-all
	find $(INSTALL_ROOT) -type f | sed -e s'#$(INSTALL_ROOT)##g' | while read i; do \
	  echo mkdir -p `dirname $$i`; \
	  echo cp $$i `dirname $$i`; \
	done

clean:
	rm -rf $(BUILD_DIR) $(INSTALL_ROOT) patches .pc/ stamp-*
