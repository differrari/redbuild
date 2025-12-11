ifneq ("$(wildcard config.mk)","")
include config.mk
endif

ARCH       ?= aarch64-none-elf-
CC         := $(ARCH)gcc
CXX        := $(ARCH)g++
LD         := $(ARCH)ld
DUMP	   := $(ARCH)objdump

CFLAGS ?= -std=c99 -g -O0
EXEC_NAME ?= $(notdir $(CURDIR))
PKG ?= $(EXEC_NAME).red
OUT ?= $(PKG)/$(EXEC_NAME).elf

SYSNAME := $(shell uname -s)

LDFLAGS := -Wl,--start-group

ifeq ($(ARCH), aarch64-none-elf-)
	SYSTEM := redacted
	CFLAGS += -nostdlib -ffreestanding
	LDFLAGS += -Wl,-emain 
else
	SYSTEM := native
    DEPS += \
    sys:c \
	local:../redxlib:../redxlib/redxlib.a \
	sys:m \
	local:../raylib/src/:../raylib/src/libraylib.a
	
	ifeq ($(SYSNAME),Darwin)
	    DEPS += \
			fw:Cocoa \
			fw:IOKit \
			fw:CoreVideo \
			fw:CoreFoundation 
    else
        # Windows & linux dependencies
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
	$(CC) $(LDFLAGS) $(CFLAGS) -I. $(INCLUDES) $(shell find . -name '*.c') $(LINKS) -o $(OUT)
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
	$(MAKE) -f $(REDBUILD)/Makefile -C $(shell pwd) ARCH=''
# 	gdb -ex run $(OUT)
	$(OUT)

dump:
	$(DUMP) -D $(OUT) > dump
