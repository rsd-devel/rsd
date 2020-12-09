#
# Do "make" on the lower directory
#

# Target subcommand
TARGETS = all clean

# Copy files only if RSD_ENV is defined
ifdef RSD_ENV
COPIED_SRC_DIRS = \
	Dhrystone \

COPY:
	cp $(RSD_ENV)/Tools/Testbench/Dhrystone ./ -r -a
else
COPIED_SRC_DIRS =
COPY:
endif


.DEFAULT_GOAL =	# Disable default target

# Directory where make is done
SRC_DIRS = \
	$(COPIED_SRC_DIRS) \


# If any of TARGETS is applicable, SRC_DIRS becomes the dependency source
$(TARGETS): COPY $(SRC_DIRS)

copy: COPY


# Do make for each element in SRC_DIRS
# $(MAKE): The parent make argument is passed to the child as is.
#            (-j etc. is also passed to the child)
# $(MAKECMDGOALS): Subcommand of parent make
$(SRC_DIRS):
	$(MAKE) -C $@ $(MAKECMDGOALS)


# By making $(SRC_DIRS) a pseudo target with PHONY,
# run every time regardless of timestamp
.PHONY: $(TARGETS) $(SRC_DIRS) copy
