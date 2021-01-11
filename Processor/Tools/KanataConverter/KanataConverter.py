# -*- coding: utf-8 -*-

#
# This script converts a RSD log to a Kanata log.
#
# Source log data is processed in 3 phases:
#   1: RSD_Parser parses source log data, and then,
#      its results are stored to 'events' and 'ops'.
#   2: KanataGenerator scans all 'ops' and generates 'sid' and 'rid'.
#   3: KanataGenerator generates Kanata log data from 'events'.
#
# There are several IDs in this script:
#
#   gid: An unique id for each micro-op in this script.
#       This is calculated in a RSD_Parser.
#   cid: An unique id for each 'committed' micro op in a Kanata log.
#       This is calculated in a RSD_Parser.
#
#   sid: An unique id for each 'fetched' micro op in a Kanata log.
#       This is calculated from gid when output.
#   rid: An unique id for each 'retired' micro op in a Kanata log.
#       This is calculated from gid when output.
#

import sys
import pprint

from RSD_Parser import RSD_Parser, RSD_ParserError
from KanataGenerator import KanataGenerator
import RISCV_Disassembler


class KanataConverter( object ):

    def Main( self, inputFileName, outputFileName ):
        """ The entry point of this class. """

        parser = RSD_Parser()
        generator = KanataGenerator()

        try:
            parser.Open( inputFileName )
            generator.Open( outputFileName )

            parser.Parse(generator)
            #generator.Generate( parser )
            #pprint.pprint( parser.events );

        except IOError as err:
            print("I/O error: %s" % err)

        except RSD_ParserError as err:
            print(err)

        finally:
            parser.Close()
            generator.Close()


#
# The entry point of this program.
#
if __name__ == '__main__':
    if ( len(sys.argv) < 3 ):
        print( "usage: %(exe)s inputFileName outputFileName" % { 'exe': sys.argv[0] } )
        exit(1)

    kanataConverter = KanataConverter()
    kanataConverter.Main( sys.argv[1], sys.argv[2] )
