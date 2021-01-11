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

#from RSD_Parser import RSD_Parser, RSD_ParserError
import RISCV_Disassembler
from RSD_Event import RSD_Event

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

        def __init__( self, sid, rid, commit ):
            self.sid = sid
            self.rid = rid
            self.commit = commit

    def __init__( self ):
        self.outputFileName = ""
        self.outputFile = None

        self.genOps = {}    # gid -> op information
        self.sidMap = {}    # gid -> sid
        self.disassembler = RISCV_Disassembler.RISCV_Disassembler()

        self.nextSID = 0
        self.lastGID = 0
        self.nextRID = 0

        self.currentCycle = KANATA_CONVERTER_INITIAL_CYCLE

    #
    # File open/close
    #

    def Open( self, fileName ):
        self.outputFileName = fileName
        self.outputFile = open( self.outputFileName, "w" )
        self.OutputHeader()


    def Close( self ):
        if self.outputFile is not None :
            self.outputFile.close()


    def OnCycleEnd(self, cycleFinished):

        # Write a cycle updating command.
        if cycleFinished > self.currentCycle:
            self.Write("%s\t%s\n" % (self.KNT_CMD_CYCLE, cycleFinished - self.currentCycle))
        self.currentCycle = cycleFinished


    def OnEvent(self, event):
        #if e.gid in self.genOps:
        if event.gid in self.sidMap or event.type == RSD_Event.INIT:
            self.OutputEvent(event)
        else:
            print("Unknown gid:%d in an event" % event.gid)

    def AddNewGID_(self, gid):

        if gid in self.sidMap:
            print("gid:%d is re-defined." % (gid))
        else:
            self.sidMap[gid] = self.nextSID
            genOp = KanataGenerator.Op(self.nextSID, 0, False)
            self.genOps[gid] = genOp
            self.nextSID += 1

        if self.lastGID > gid:
            print("lastGID:%d is greater than added gid:%d in AddNewGID" % (self.lastGID, gid))
        self.lastGID = gid 

    def AddRetiredEvent_(self, event):
        """ Add a retired op to the generator """
        op = self.genOps[event.gid]
        op.commit = True
        op.rid = self.nextRID
        self.nextRID += 1

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
        if( type == RSD_Event.INIT ):
            self.OnKNT_Initialize( event )
        elif( type == RSD_Event.STAGE_BEGIN ):
            self.OnKNT_StageBegin( event )
        elif( type == RSD_Event.STAGE_END ):
            self.OnKNT_StageEnd( event )
        elif( type == RSD_Event.STALL_BEGIN ):
            self.OnKNT_StallBegin( event )
        elif( type == RSD_Event.STALL_END ):
            self.OnKNT_StallEnd( event )
        elif( type == RSD_Event.RETIRE ):
            self.OnKNT_Retire( event )
        elif( type == RSD_Event.FLUSH ):
            self.OnKNT_Flush( event )
        elif( type == RSD_Event.LABEL ):
            self.OnKNT_Label( event )


    def GetStageName( self, id ):
        return KANATA_CONVERTER_STAGE_NAME_TABLE[ id ]

    def GetSID( self, gid ):
        return self.sidMap[gid]

    def GetRID( self, gid ):
        return self.genOps[gid].rid

    def OnKNT_Initialize( self, event ):
        """ Output an initializing event. """
        gid = event.gid
        self.AddNewGID_(gid) # sid is created in this method

        sid = self.GetSID(gid)
        self.Write(
            "%s\t%s\t%s\t%s\n" %
            (self.KNT_CMD_INIT, sid, gid, self.KNT_THREAD_ID)
        )
        self.Write(
            "%s\t%s\t%s\t%s\\n\n" % (
                self.KNT_CMD_LABEL,
                sid,
                self.KNT_CMD_ARG_LABEL_TYPE_DETAIL,
                "(g:%d,c0)" % (gid)
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
        self.AddRetiredEvent_(event)
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

    def OnKNT_Label( self, event ):
        """ Output a label event using a label command. """
        self.Write(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_LABEL,
                self.GetSID(event.gid),
                self.KNT_CMD_ARG_LABEL_TYPE_ABSTRACT,
                event.comment
            )
        )
