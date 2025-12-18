ifneq ("$(wildcard config.mk)","")
include config.mk
endif

ARCH       ?= aarch64-none-elf-
ifeq "$(origin CC)" "default"
CC         := $(ARCH)gcc
endif
ifeq "$(origin CXX)" "default"
CXX        := $(ARCH)g++
endif
LD         := $(ARCH)ld
DUMP	   := $(ARCH)objdump

CFLAGS ?= -std=c99 -g -O0
EXEC_NAME ?= $(notdir $(CURDIR))
PKG ?= $(EXEC_NAME).red
OUT ?= $(PKG)/$(EXEC_NAME).elf

SHOULD_RUN ?= true

SYSNAME := $(shell uname -s)

ifeq ($(ARCH), aarch64-none-elf-)
	SYSTEM := redacted
	CFLAGS += -nostdlib -ffreestanding
	LDFLAGS += -Wl,-emain 
else
    DEPS += \
	local:../redxlib:../redxlib/redxlib.a \
	local:../raylib/src/:../raylib/src/libraylib.a
	
	ifeq ($(shell uname),Darwin)
		SYSTEM := macos
	    DEPS += \
			fw:Cocoa \
			fw:IOKit \
			fw:CoreVideo \
			fw:CoreFoundation \
			sys:m \
			sys:c
    else ifeq($(shell uname), Linux)
    	SYSTEM := linux
    	LDFLAGS := -Wl,--start-group
        DEPS += sys:m \
        		sys:c
	else ifeq($(OS),Windows_NT)
		SYSTEM := windows
        # Windows dependencies
        DEPS += sys:opengl32 \
        		sys:gdi32 \
          		sys:winmm \
            	sys:shell32 \
                sys:User32
        LDFLAGS := -fuse-ld=lld 
        CC := clang
        CCX := clang
        AR := llvm-ar
    endif
endif

get_type = $(word 1,$(subst :, ,$1))
get_a1   = $(word 2,$(subst :, ,$1))
get_a2   = $(word 3,$(subst :, ,$1))

expand_dep = $(call expand_$(call get_type,$1),$1)

expand_sys = -l$(call get_a1,$1)
expand_fw = -framework $(call get_a1,$1)
expand_local = -I$(call get_a1,$1) $(call expand_local_lib,$1)

expand_local_lib = $(call get_a2,$1)

INCLUDES  += $(foreach d,$(DEPS),$(filter -I%,$(call expand_dep,$(d))))
LINKS     += $(foreach d,$(DEPS),$(filter-out -I%,$(call expand_dep,$(d))))

.PHONY: dump

all: prepare compile
	echo "Finished build"

prepare:
	mkdir -p $(PKG)
	mkdir -p resources
	cp -r resources $(PKG)
	cp package.info $(EXEC_NAME).red

compile:
	# echo "$(SYSTEM)" > buildreport
	$(CC) $(LDFLAGS) $(CFLAGS) -I. $(INCLUDES) $(shell find . -name "*.c") $(LINKS) -o $(OUT)
	chmod +x $(OUT)

run: all
ifeq ($(ARCH), aarch64-none-elf-)
	rm -rf $(FS_PATH)
	cp -rf $(PKG) $(FS_PATH)
	$(MAKE) -C $(OS_DIR) run
else
	$(OUT)
endif

clean:
	rm $(OUT)
	rm -r $(FS_PATH)
	rm -r $(EXEC_NAME).red

cross:
	$(MAKE) -f $(REDBUILD)/Makefile -C $(shell pwd) ARCH=""
	@if [ "$(SHOULD_RUN)" = true ]; then\
	    if [ "$(DEBUG)" = true ]; then\
			gdb -ex run $(OUT);\
		else\
	        $(OUT);\
		fi;\
	fi

dump:
	$(DUMP) -D $(OUT) > dump
