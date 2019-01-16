sinclude .config

# Toolchain path
CROSS   := ../../build/tools/armv5-eabi--glibc--stable/bin/armv5-glibc-linux-

BIN     := bin
TARGET  := xboot
CFLAGS   = -Os -march=armv5te -Wall -g -nostdlib -fno-builtin -Iinclude
CFLAGS  += -ffunction-sections -fdata-sections
CFLAGS  += -mthumb -mthumb-interwork
LD_SRC   = boot.ldi
LD_GEN   = boot.ld
LDFLAGS  = -L $(shell dirname `$(CROSS)gcc -print-libgcc-file-name`) -lgcc
#LDFLAGS += -Wl,--gc-sections,--print-gc-sections
LDFLAGS += -Wl,--gc-sections

.PHONY: release debug

# default target
release debug: all

all: $(TARGET)
ifeq ($(CONFIG_SECURE_BOOT_SIGN), y)
	@# 64-byte signature
	@-rm -f $(BIN)/$(TARGET).sig
	@bash ./gen_signature.sh $(BIN)/$(TARGET).bin $(BIN)/$(TARGET).sig
	@echo "Append signature for secure boot"
	@cat  $(BIN)/$(TARGET).sig >> $(BIN)/$(TARGET).bin
	@bash ./add_xhdr.sh $(BIN)/$(TARGET).bin $(BIN)/$(TARGET).img 1
else
	@# 32-byte xboot header
	@bash ./add_xhdr.sh $(BIN)/$(TARGET).bin $(BIN)/$(TARGET).img 0
endif

ifeq ($(CONFIG_STANDALONE_DRAMINIT), y)
	@# print draminit.img size
	@sz=`du -sb $(DRAMINIT_IMG) | cut -f1` ; \
	    printf "$(DRAMINIT_IMG) size = %d (hex %x)\n" $$sz $$sz
	@echo "Append $(DRAMINIT_IMG)"
	@# xboot.img = xboot.img.orig + draminit.img
	@mv  $(BIN)/$(TARGET).img  $(BIN)/$(TARGET).img.orig
	@cat $(BIN)/$(TARGET).img.orig $(DRAMINIT_IMG) > $(BIN)/$(TARGET).img
else
	@echo "Linked with $(DRAMINIT_OBJ)"
endif
	@# print xboot size
	@sz=`du -sb bin/$(TARGET).img | cut -f1` ; \
	    printf "xboot.img size = %d (hex %x)\n" $$sz $$sz

###################
# draminit

# If CONFIG_STANDALONE_DRAMINIT=y, use draminit.img.
ifeq ($(CONFIG_STANDALONE_DRAMINIT), y)
DRAMINIT_IMG := ../draminit/bin/draminit.img
else
# Otherwise, link xboot with plf_dram.o
DRAMINIT_OBJ := ../draminit/plf_dram.o
# Use prebuilt obj if provided
CONFIG_PREBUILT_DRAMINIT_OBJ := $(shell echo $(CONFIG_PREBUILT_DRAMINIT_OBJ))
ifneq ($(CONFIG_PREBUILT_DRAMINIT_OBJ),)
DRAMINIT_OBJ := $(CONFIG_PREBUILT_DRAMINIT_OBJ)
endif
endif # CONFIG_STANDALONE_DRAMINIT

# build target
debug: DRAMINIT_TARGET:=debug

build_draminit:
	@echo ">>>>>>>>>>> Build draminit"
	make -C ../draminit $(DRAMINIT_TARGET) CROSS=$(CROSS)
	@echo ">>>>>>>>>>> Build draminit (done)"
	@echo ""

# Boot up
ASOURCES_V5 := start.S
#ASOURCES_V7 := v7_start.S
ASOURCES = $(ASOURCES_V5) $(ASOURCES_V7)
CSOURCES += xboot.c

CSOURCES += common/diag.c

# MON shell
ifeq ($(CONFIG_DEBUG_WITH_2ND_UART), y)
CSOURCES += romshare/regRW.c
endif
ifeq ($(MON), 1)
CFLAGS += -DMON=1
endif

# Common
CSOURCES += common/common.c common/bootmain.c common/stc.c
CSOURCES += common/string.c lib/image.c

# ARM code
CSOURCES += cpu/cpu.c lib/eabi_compat.c
space :=
space +=
cpu/cpu.o: CFLAGS:=$(subst -mthumb$(space),,$(CFLAGS))

# Generic Boot Device
ifeq ($(CONFIG_HAVE_NAND_COMMON), y)
CSOURCES += nand/nandop.c nand/bch.c
endif

# Parallel NAND
ifeq ($(CONFIG_HAVE_PARA_NAND), y)
CSOURCES += nand/nfdriver.c
endif

# SPI NAND
ifeq ($(CONFIG_HAVE_SPI_NAND), y)
CSOURCES += nand/spi_nand.c
endif

# FAT
ifeq ($(CONFIG_HAVE_FS_FAT),y)
CSOURCES += fat/fat_boot.c
endif

# USB
ifeq ($(CONFIG_HAVE_USB_DISK), y)
CSOURCES += usb/ehci_usb.c
endif

# MMC
ifeq ($(CONFIG_HAVE_MMC), y)
CSOURCES += sdmmc/drv_sd_mmc.c  sdmmc/hal_sd_mmc.c sdmmc/hw_sd.c
endif

# OTP
ifeq ($(CONFIG_HAVE_OTP), y)
CSOURCES += otp/sp_otp.c
endif

CSOURCES += draminit/dram_test.c

OBJS = $(ASOURCES:.S=.o) $(CSOURCES:.c=.o)

$(OBJS): prepare

$(TARGET): $(OBJS)
	@echo ">>>>> Link $@"
	@$(CROSS)cpp -P $(CFLAGS) $(LD_SRC) $(LD_GEN)
	$(CROSS)gcc $(CFLAGS) $(OBJS) $(DRAMINIT_OBJ) -T $(LD_GEN) $(LDFLAGS) -o $(BIN)/$(TARGET) -Wl,-Map,$(BIN)/$(TARGET).map
	@$(CROSS)objcopy -O binary -S $(BIN)/$(TARGET) $(BIN)/$(TARGET).bin
	@$(CROSS)objdump -d -S $(BIN)/$(TARGET) > $(BIN)/$(TARGET).dis

%.o: %.S
	$(CROSS)gcc $(CFLAGS) -c -o $@ $<

%.o: %.c
	$(CROSS)gcc $(CFLAGS) -c -o $@ $<


#################
# dependency
.depend: $(ASOURCES) $(CSOURCES)
	@rm -f .depend >/dev/null
	@$(CROSS)gcc $(CFLAGS) -MM $^ >> ./.depend
sinclude .depend

#################
# clean
.PHONY:clean
clean:
	@rm -rf .depend $(LD_GEN) $(OBJS) *.o >/dev/null
	@if [ -d $(BIN) ];then \
		cd $(BIN) && rm -rf $(TARGET) $(TARGET).bin $(TARGET).map $(TARGET).dis \
			$(TARGET).img $(TARGET).img.orig $(TARGET).sig >/dev/null ;\
	 fi;
	@echo "$@: done"

distclean: clean
	@rm -rf .config .config.old $(BIN)/v7
	@rm -f GPATH GTAGS GRTAGS
	@-rmdir $(BIN)
	@echo "$@: done"

#################
# configurations
.PHONY: prepare
prepare: auto_config build_draminit
	@mkdir -p $(BIN)

AUTOCONFH=tools/auto_config_h
MCONF=tools/mconf

config_list=$(subst configs/,,$(shell find configs/ -maxdepth 1 -mindepth 1 -type f|sort))
$(config_list):
	@if [ ! -f configs/$@ ];then \
		echo "Not found config file for $@" ; \
		exit 1 ; \
	fi
	@make clean >/dev/null
	@echo "Configure to $@ ..."
	@cp configs/$@ .config

list:
	@echo "$(config_list)" | sed 's/ /\n/g'

auto_config: chkconfig
	@echo "  [KCFG] $@.h"
	$(AUTOCONFH) .config include/$@.h

chkconfig:
	@if [ ! -f .config ];then \
		echo "Please make XXX to generate .config. Find configs by: make list" ; \
		exit 1; \
	fi

config menuconfig:
	@$(MCONF) Kconfig

#################
# misc
r: clean all
pack:
	@make -C ../../ipack
