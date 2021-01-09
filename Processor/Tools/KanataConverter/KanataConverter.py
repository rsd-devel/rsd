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
import RISCV_Disassembler

#
# Global constants
#
KANATA_CONVERTER_STAGE_NAME_TABLE = [
    "Np", "F", "Pd", "Dc", "Rn", "Ds", "Sc", "Is", "Rr", "X", "Ma", "Mt", "Rw", "Wc", "Cm"
]
KANATA_CONVERTER_INITIAL_CYCLE = -1
KANATA_CONVERTER_RETIREMENT_STAGE_ID = 14   # See constants in RSD_Parser.py



class KanataGenerator( object ):
    """ Generate Kanata log data from parsed results. """

    #
    # Constants
    #

    # Whether to output flushed ops.
    KNT_OUTPUT_FLUSHED_OPS = True

    # Kanata constans related to a file header.
    KNT_HEADER = "Kanata\t0004\n"
    KNT_THREAD_ID = 0

    # Kanata lanes
    KNT_LANE_DEFAULT = 0
    KNT_LANE_STALL = 1

    # Kanata command strings.
    KNT_CMD_INIT = "I"
    KNT_CMD_LABEL = "L"
    KNT_CMD_CYCLE = "C"
    KNT_CMD_STAGE_BEGIN = "S"
    KNT_CMD_STAGE_END = "E"
    KNT_CMD_RETIRE = "R"

    # Kanata retirement types.
    KNT_CMD_ARG_RETIRE = 0
    KNT_CMD_ARG_FLUSH = 1

    # Label type
    KNT_CMD_ARG_LABEL_TYPE_ABSTRACT = 0 # Shown in a left pane.
    KNT_CMD_ARG_LABEL_TYPE_DETAIL = 1   # Shown in a tool-tip on a left pane.
    KNT_CMD_ARG_LABEL_TYPE_STAGE = 2    # Shown in a tool-tip on each stage.

    KNT_CMD_ARG_STALL = "stl"

    class Op( object ):
        """ It has information about an op. """

        def __init__( self, sid, rid, cid, commit, label ):
            self.sid = sid
            self.rid = rid
            self.cid = cid
            self.commit = commit
            self.label = label

    def __init__( self ):
        self.outputFileName = ""
        self.outputFile = None

        self.ops = {}    # gid -> op information
        self.disassembler = RISCV_Disassembler.RISCV_Disassembler()

    #
    # File open/close
    #

    def Open( self, fileName ):
        self.outputFileName = fileName
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

        # sid, rid, label are extracted.
        rid = 0
        for sid, gid in enumerate( sorted( parserOps.keys() ) ):
            parserOp = parserOps[ gid ]

            if self.KNT_OUTPUT_FLUSHED_OPS:
                # Output flushed ops
                genOp = KanataGenerator.Op( sid, rid, parserOp.cid, parserOp.commit, parserOp.label )
                self.ops[ gid ] = genOp
                if not parserOp.clear:
                    rid += 1
            else:
                # Don't output flushed ops
                genOp = KanataGenerator.Op( rid, rid, parserOp.cid, parserOp.commit, parserOp.label )
                if not parserOp.clear:
                    self.ops[ gid ] = genOp
                    rid += 1

        # Emit Kanata file header.
        current = KANATA_CONVERTER_INITIAL_CYCLE
        self.OutputHeader()

        # Emit Kanata log data.
        events = parser.events
        for cycle in sorted( events.keys() ):
            # Write a cycle updating command.
            if cycle > current:
                self.Write( "%s\t%s\n" % ( self.KNT_CMD_CYCLE, cycle - current ) )
            current = cycle

            # Extract and process events at a current cycle.
            for e in events[ cycle ]:
                if e.gid in self.ops:
                    self.OutputEvent( e )

    def Write( self, str ):
        self.outputFile.write( str )

    def OutputHeader( self ):
        """ Output Kanata log header. """
        self.Write( self.KNT_HEADER )
        self.Write( "C=\t%s\n" % KANATA_CONVERTER_INITIAL_CYCLE )

    def OutputEvent( self, event ):
        """ Output an event to an output file.
        This method dispatches events to corresponding handlers.
        """
        type = event.type
        if( type == RSD_Parser.EVENT_INIT ):
            self.OnKNT_Initialize( event )
        elif( type == RSD_Parser.EVENT_STAGE_BEGIN ):
            self.OnKNT_StageBegin( event )
        elif( type == RSD_Parser.EVENT_STAGE_END ):
            self.OnKNT_StageEnd( event )
        elif( type == RSD_Parser.EVENT_STALL_BEGIN ):
            self.OnKNT_StallBegin( event )
        elif( type == RSD_Parser.EVENT_STALL_END ):
            self.OnKNT_StallEnd( event )
        elif( type == RSD_Parser.EVENT_RETIRE ):
            self.OnKNT_Retire( event )
        elif( type == RSD_Parser.EVENT_FLUSH ):
            self.OnKNT_Flush( event )


    def GetStageName( self, id ):
        return KANATA_CONVERTER_STAGE_NAME_TABLE[ id ]

    def GetSID( self, gid ):
        return self.ops[ gid ].sid

    def GetRID( self, gid ):
        return self.ops[ gid ].rid

    def GetLabel( self, gid ):
        #commit = self.ops[ gid ].commit
        #cid = self.ops[ gid ].cid
        label = self.ops[ gid ].label
        pcStr = label.pc
        asmStr = self.disassembler.Disassemble( label.code )
        return "%s: %s" % (pcStr, asmStr)

    def OnKNT_Initialize( self, event ):
        """ Output an initializing event. """
        gid = event.gid
        sid = self.GetSID(gid)
        self.Write(
            "%s\t%s\t%s\t%s\n" %
            (self.KNT_CMD_INIT, sid, gid, self.KNT_THREAD_ID)
        )
        self.Write(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_LABEL,
                sid,
                self.KNT_CMD_ARG_LABEL_TYPE_ABSTRACT,
                self.GetLabel( gid )
            )
        )
        self.Write(
            "%s\t%s\t%s\t%s\\n\n" % (
                self.KNT_CMD_LABEL,
                sid,
                self.KNT_CMD_ARG_LABEL_TYPE_DETAIL,
                "(g:%d,c%d)" % (gid, self.ops[gid].cid)
            )
        )

    def OnKNT_StageBegin( self, event ):
        """ Output an stage begin event. """
        self.Write(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_STAGE_BEGIN,
                self.GetSID( event.gid ),
                self.KNT_LANE_DEFAULT,
                self.GetStageName( event.stageID )
            )
        )
        if event.comment != "":
            self.OnKNT_Comment( event )

    def OnKNT_StageEnd( self, event ):
        """ Output an stage end event. """
        self.Write(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_STAGE_END,
                self.GetSID( event.gid ),
                self.KNT_LANE_DEFAULT,
                self.GetStageName( event.stageID )
            )
        )

    def OnKNT_StallBegin( self, event ):
        """ Output an stall begin event. """
        self.Write(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_STAGE_BEGIN,
                self.GetSID( event.gid ),
                self.KNT_LANE_STALL,
                self.KNT_CMD_ARG_STALL
            )
        )

    def OnKNT_StallEnd( self, event ):
        """ Output an stall end event. """
        self.Write(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_STAGE_END,
                self.GetSID( event.gid ),
                self.KNT_LANE_STALL,
                self.KNT_CMD_ARG_STALL
            )
        )

    def OnKNT_Retire( self, event ):
        """ Output a retirement event. """
        self.Write(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_RETIRE,
                self.GetSID( event.gid ),
                self.GetRID( event.gid ),
                self.KNT_CMD_ARG_RETIRE
            )
        )

    def OnKNT_Flush( self, event ):
        """ Output a flush event. """
        self.Write(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_RETIRE,
                self.GetSID( event.gid ),
                self.GetRID( event.gid ),
                self.KNT_CMD_ARG_FLUSH
            )
        )

    def OnKNT_Comment( self, event ):
        """ Output a comment event using a label command. """
        self.Write(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_LABEL,
                self.GetSID( event.gid ),
                self.KNT_CMD_ARG_LABEL_TYPE_DETAIL,
                event.comment
            )
        )
        self.Write(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_LABEL,
                self.GetSID( event.gid ),
                self.KNT_CMD_ARG_LABEL_TYPE_STAGE,
                event.comment
            )
        )


class KanataConverter( object ):

    def Main( self, inputFileName, outputFileName ):
        """ The entry point of this class. """

        parser = RSD_Parser()
        generator = KanataGenerator()

        try:
            parser.Open( inputFileName )
            generator.Open( outputFileName )

            parser.Parse()
            generator.Generate( parser )

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
