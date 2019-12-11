# -*- coding: utf-8 -*-

#
# This script converts a RSD log to an architecture state log.
#
# Source log data is processed in 3 phases:
#   1: RSD_Parser parses source log data, and then, its results are stored to 'ops'.
#   2: ArchitectureStateGenerator scans committed 'ops' and generates 'opList'.
#   3: ArchitectureStateGenerator generates architecuturestate log data from 'opList'.
#      Now, the log consists of only PCs of committed ops.
#

import sys
from RSD_Parser import RSD_Parser, RSD_ParserError

class ArchitectureStateGenerator( object ):
    """ Generate architecture state log data from parsed results. """

    ARCHITECTURE_STATE_HEADER = "# PC \n"

    class Op( object ):
        """ It has information about an op. """

        def __init__( self, pc ):
            self.pc = pc

    def __init__( self ):
        self.outputFileName = ""
        self.outputFile = None

        self.opList = []   # List of committed ops.

    #
    # File open/close
    #

    def Open( self, fileName ):
        self.outputFileName = fileName;
        self.outputFile = open( self.outputFileName, "w" )


    def Close( self ):
        if self.outputFile is not None :
            self.outputFile.close()
    

    #
    # Make and output log data to a file.
    #
    def Generate( self, parser ):
        """ Output Kanata log data to a output file. """
        
        # Extract parsed results.
        parserOps = parser.ops

        # gid, pc are extracted.
        for gid in sorted( parserOps.keys() ):
            parserOp = parserOps[ gid ]
            if parserOp.commit:
                op = ArchitectureStateGenerator.Op( parserOp.label.pc )
                self.opList.append( op )
        
        # Emit architecture state file header.            
        self.OutputHeader()

        # Emit architecture state log data.
        for op in self.opList:
            self.OutputArchitectureState( op )

    def Write( self, str ):
        self.outputFile.write( str )

    def OutputHeader( self ):
        """ Output Kanata log header. """
        self.Write( self.ARCHITECTURE_STATE_HEADER )
    
    def OutputArchitectureState( self, op ):
        self.Write( "%s\n" % op.pc )

class ArchitectureStateConverter( object ):

    def Main( self, inputFileName, outputFileName ):
        """ The entry point of this class. """

        parser = RSD_Parser()
        generator = ArchitectureStateGenerator()

        try:
            parser.Open( inputFileName )
            generator.Open( outputFileName )

            parser.Parse()
            generator.Generate( parser )

        except IOError, (errno, strerror):
            print( "I/O error(%s): %s" % ( errno, strerror ) )

        except RSD_ParserError, ( strerror ):
            print( strerror )

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
    
    architectureStateConverter = ArchitectureStateConverter()
    architectureStateConverter.Main( sys.argv[1], sys.argv[2] )

