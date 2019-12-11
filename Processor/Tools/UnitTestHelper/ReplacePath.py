import os, sys

TARGET_STR_FIRST = '$sdf_annotate("'
TARGET_STR_LAST = 'netgen/'

USAGE_STR = "Usage: ReplacePath.py {Path to ISE Project} {Target File}"

# check argument
if ( len(sys.argv) < 3 ):
    print USAGE_STR
    sys.exit(0)

# read file
f = open( sys.argv[2], 'r' )
str = f.read()
f.close()

# replace string
str = str.replace( TARGET_STR_FIRST + TARGET_STR_LAST, TARGET_STR_FIRST + sys.argv[1] + TARGET_STR_LAST )

# write to file
f = open( sys.argv[2], 'w' )
f.write( str )
f.close()
