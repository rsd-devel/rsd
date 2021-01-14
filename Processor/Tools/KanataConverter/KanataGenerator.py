# -*- coding: utf-8 -*-

#
# This script converts a RSD log to a Kanata log.
#
# Source log data is processed as follows:
#   1: RSD_Parser parses source log data, and call 
#      OnCycle/OnEvent of KanataGenerator.
#   2: KanataGenerator generates Kanata log data.
#
# There are several IDs in this script:
#
#   gid: An unique id for each micro-op in this script.
#        This id is gerated in a RSD_Parser.
#
#   sid: An unique id for each 'fetched' micro op in a Kanata log.
#        This id is generated from gid when output.
#   rid: An unique id for each 'retired' micro op in a Kanata log.
#        This id is generated from gid when output.
#

import sys
import pprint

from RSD_Event import RSD_Event

#
# Global constants
#
KANATA_CONVERTER_STAGE_NAME_TABLE = [
    "Np", "F", "Pd", "Dc", "Rn", "Ds", "Sc", "Is", "Rr", "X", "Ma", "Mt", "Rw", "Wc", "Cm"
]
KANATA_CONVERTER_INITIAL_CYCLE = -1
KANATA_CONVERTER_RETIREMENT_STAGE_ID = 14   # See constants in RSD_Parser.py



class KanataGenerator(object):
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

    class Op(object):
        """ It has information about an op. """
        def __init__(self, sid):
            self.sid = sid


    def __init__(self):
        self.outputFileName_ = ""
        self.outputFile_ = None

        self.opMap_ = {}    # gid -> op information

        self.nextSID_ = 0
        self.lastGID_ = 0
        self.nextRID_ = 0

        self.currentCycle_ = KANATA_CONVERTER_INITIAL_CYCLE

    #
    # File open/close
    #
    def Open(self, fileName):
        self.outputFileName_ = fileName
        self.outputFile_ = open(self.outputFileName_, "w")
        self.OutputHeader_()

    def Close(self):
        if self.outputFile_ is not None :
            self.outputFile_.close()

    def Write_(self, str):
        self.outputFile_.write(str)


    def OutputHeader_(self):
        """ Output Kanata log header. """
        self.Write_(self.KNT_HEADER)
        self.Write_("C=\t%s\n" % KANATA_CONVERTER_INITIAL_CYCLE)

    def OutputEvent_(self, event):
        """ Output an event to an output file.
        This method dispatches an event to a corresponding handler.
        """
        type = event.type
        if(type == RSD_Event.INIT):
            self.OnKNT_Initialize_(event)
        elif(type == RSD_Event.STAGE_BEGIN):
            self.OnKNT_StageBegin_(event)
        elif(type == RSD_Event.STAGE_END):
            self.OnKNT_StageEnd_(event)
        elif(type == RSD_Event.STALL_BEGIN):
            self.OnKNT_StallBegin_(event)
        elif(type == RSD_Event.STALL_END):
            self.OnKNT_StallEnd_(event)
        elif(type == RSD_Event.RETIRE):
            self.OnKNT_Retire_(event)
        elif(type == RSD_Event.FLUSH):
            self.OnKNT_Flush_(event)
        elif(type == RSD_Event.LABEL):
            self.OnKNT_Label_(event)


    def OnCycle(self, cycle):
        """ This method is called from RSD_Parser """
        # Write a cycle-update command.
        if cycle > self.currentCycle_:
            self.Write_("%s\t%s\n" % (self.KNT_CMD_CYCLE, cycle - self.currentCycle_))
        self.currentCycle_ = cycle

    def OnEvent(self, event):
        """ This method is called from RSD_Parser """
        if event.gid in self.opMap_ or event.type == RSD_Event.INIT:
            self.OutputEvent_(event)
        else:
            print("Unknown gid:%d is in an event" % event.gid)


    def GetStageName_(self, id):
        return KANATA_CONVERTER_STAGE_NAME_TABLE[id]

    def GetSID_(self, gid):
        return self.opMap_[gid].sid


    def AddNewGID_(self, gid):
        """ Register a specified gid and generates a new sid """
        if gid in self.opMap_:
            print("gid:%d is re-defined." % (gid))
        else:
            genOp = KanataGenerator.Op(self.nextSID_)
            self.opMap_[gid] = genOp
            self.nextSID_ += 1

        if self.lastGID_ > gid:
            print("lastGID:%d is greater than added gid:%d in AddNewGID" % (self.lastGID_, gid))
        self.lastGID_ = gid 


    def OnKNT_Initialize_(self, event):
        """ Output an initializing event. """
        gid = event.gid
        self.AddNewGID_(gid) # sid is created in this method
        sid = self.GetSID_(gid)

        self.Write_(
            "%s\t%s\t%s\t%s\n" %
            (self.KNT_CMD_INIT, sid, gid, self.KNT_THREAD_ID)
        )
        self.Write_(
            "%s\t%s\t%s\t%s\\n\n" % (
                self.KNT_CMD_LABEL,
                sid,
                self.KNT_CMD_ARG_LABEL_TYPE_DETAIL,
                "(g:%d,c0)" % (gid)
            )
        )

    def OnKNT_StageBegin_(self, event):
        """ Output a stage begin event. """
        self.Write_(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_STAGE_BEGIN,
                self.GetSID_(event.gid),
                self.KNT_LANE_DEFAULT,
                self.GetStageName_(event.stageID )
            )
        )
        if event.comment != "":
            self.OnKNT_Comment(event )

    def OnKNT_StageEnd_(self, event):
        """ Output a stage end event. """
        self.Write_(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_STAGE_END,
                self.GetSID_(event.gid),
                self.KNT_LANE_DEFAULT,
                self.GetStageName_(event.stageID )
            )
        )

    def OnKNT_StallBegin_(self, event):
        """ Output a stall begin event. """
        self.Write_(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_STAGE_BEGIN,
                self.GetSID_(event.gid),
                self.KNT_LANE_STALL,
                self.KNT_CMD_ARG_STALL
            )
        )

    def OnKNT_StallEnd_(self, event):
        """ Output a stall end event. """
        self.Write_(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_STAGE_END,
                self.GetSID_(event.gid),
                self.KNT_LANE_STALL,
                self.KNT_CMD_ARG_STALL
            )
        )

    def OnKNT_Retire_(self, event):
        """ Output a retirement event. """
        self.Write_(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_RETIRE,
                self.GetSID_(event.gid),
                self.nextRID_,
                self.KNT_CMD_ARG_RETIRE
            )
        )

        self.nextRID_ += 1
        del self.opMap_[event.gid]
        
        # GC
        if event.gid % 64 == 0:
            for gid in list(self.opMap_.keys()):
                if gid < event.gid:
                    del self.opMap_[gid]

    def OnKNT_Flush_(self, event):
        """ Output a flush event. """
        self.Write_(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_RETIRE,
                self.GetSID_(event.gid),
                0,
                self.KNT_CMD_ARG_FLUSH
            )
        )

    def OnKNT_Comment(self, event):
        """ Output a comment event using a label command. """
        self.Write_(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_LABEL,
                self.GetSID_(event.gid),
                self.KNT_CMD_ARG_LABEL_TYPE_DETAIL,
                event.comment
            )
        )
        self.Write_(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_LABEL,
                self.GetSID_(event.gid),
                self.KNT_CMD_ARG_LABEL_TYPE_STAGE,
                event.comment
            )
        )

    def OnKNT_Label_(self, event):
        """ Output a label event using a label command. """
        self.Write_(
            "%s\t%s\t%s\t%s\n" % (
                self.KNT_CMD_LABEL,
                self.GetSID_(event.gid),
                self.KNT_CMD_ARG_LABEL_TYPE_ABSTRACT,
                event.comment
            )
        )
