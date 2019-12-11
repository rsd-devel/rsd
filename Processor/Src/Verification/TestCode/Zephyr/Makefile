#
# Do "make" on the lower directory
#

# If RSD_ENV is defined, copy from there additionally
ifdef RSD_ENV

SRC_TESTS =    \
	HelloWorld \
	Philosophers \
	Synchronization \
	Dhrystone \

SRC_DIR = $(RSD_ENV)/Tools/Testbench/Zephyr/
.DEFAULT: all
all: 
	cd $(SRC_DIR); $(MAKE)

env-clean: clean
	cd $(SRC_DIR); $(MAKE) env-clean


# By making $(SRC_DIRS) a pseudo target with PHONY,
# run every time regardless of timestamp
.PHONY: $(SRC_TESTS)
$(SRC_TESTS):
	cp $(SRC_DIR)/$@ ./ -r -a

copy: $(SRC_TESTS)

clean: 
	rm $(SRC_TESTS) -r -f


else	# ifdef RSD_ENV

# Do nothing

all: 
env-clean:
copy:
clean: 

endif	# ifdef RSD_ENV

