# -*- coding: utf-8 -*-

#
# Parse a RSD log file.
# Please see the comments in KanataGenerator.py
#


import re
from KanataGenerator import KanataGenerator
from RSD_Event import RSD_Event
from RISCV_Disassembler import RISCV_Disassembler

#
# Global constants
#
RSD_PARSER_INITIAL_CYCLE = -1
RSD_PARSER_RETIREMENT_STAGE_ID = 14
RSD_PARSER_CID_DEFAULT = -1

class RSD_ParserError(Exception):
    """ An exception class for RSD_Parser """
    pass


class RSD_Parser(object):
    """ Parse RSD log data. """

    # Constants

    # RSD log command strings.
    RSD_HEADER = "RSD_Kanata"
    RSD_VERSION = 0

    RSD_CMD_LABEL = "L"
    RSD_CMD_STAGE = "S"
    RSD_CMD_CYCLE = "C"
    RSD_CMD_COMMENT = "#"

    # Bit width of OpSerial in SystemVerilog code.
    # An id stored in OpSerial signal is loaded as "iid" in this python script.
    # See the comments in CreateGID()
    OP_SERIAL_WIDTH = 10

    # Max micro-ops per an instruction.
    MAX_MICRO_OPS_PER_INSN = 4

    # Wrap around of gid caused by wrap around of iid.
    GID_WRAP_AROUND = 2 ** OP_SERIAL_WIDTH * MAX_MICRO_OPS_PER_INSN

    # Create unique 'gid' from 'iid' and 'mid'. 
    # Since 'iid' is stored in a signal with the limited width of OpSerial, 
    # 'iid' causes wrap around. So this script generats an unique id called 'gid' 
    # from 'iid' and current state.
    def CreateGID_(self, iid, mid):
        """ Create unique 'gid' from 'iid' and 'mid'. """
        if mid >= RSD_Parser.MAX_MICRO_OPS_PER_INSN:
            raise RSD_ParserError("'mid' exceeds MAX_MICRO_OPS_PER_INSN at iid(%d)" % iid )
        
        # A           B
        # |<----W---->|<----W---->|
        # |----r---g--|-----------|: n = A
        # |----g---r--|-----------|: n = A
        # |--------r--|--g--------|: n = B
        # |--------g--|--r--------|: n = A
        g = mid + iid * RSD_Parser.MAX_MICRO_OPS_PER_INSN
        W = RSD_Parser.GID_WRAP_AROUND
        M = W / 4
        r = self.maxRetiredOp_ % W
        n = self.maxRetiredOp_ - r

        # The maximum difference between g and r must be less than W/2,
        # so the maximum number if in-flight ops must be less than GID_WRAP_AROUND/2
        # |--------r--|--g--------|: n = B
        if r > M * 3 and g < M:
                n = n + W   
        # |--------g--|--r--------|: n = A
        if g > M * 3 and r < M: 
                n = n - W

        gid = n + g
        return gid

    #
    # Internal classes
    #
    class Op(object):
        """ Op class. """
        def __init__(self, iid, mid, gid, stall, clear, stageID, updatedCycle):
            self.iid = iid
            self.mid = mid
            self.gid = gid
            self.stageID = stageID
            self.stall = stall
            self.clear = clear
            self.updatedCycle = updatedCycle
            self.labelOutputted = False

        def __repr__(self):
            return (
                "{gid:%s, stall:%s, clear:%s, stageID:%s, updatedCycle: %s}" % 
                (self.gid, self.stall, self.clear, self.stageID, self.updatedCycle)
            )


    class Event(object):
        """ Event class """
        def __init__(self, gid, type, stageID, comment):
            self.gid = gid
            self.type = type
            self.stageID = stageID
            self.comment = comment

        def __repr__(self):
            return (
                "{gid:%s, type:%s, stageID:%s, comment:%s}" % 
                (self.gid, self.type, self.stageID, self.comment)
            )

    def __init__(self):
        """ Initializer """

        self.inputFileName_ = ""
        self.inputFile_ = None

        # A current processor cycle.
        self.currentCycle_ = RSD_PARSER_INITIAL_CYCLE

        self.ops_ = {}       # gid -> Op map
        self.events_ = {}    # cycle -> Event map
        self.flushedOpGIDs__ = set([])    # retired gids
        self.maxRetiredOp_ = 0      # The maximum number in retired ops.
        self.committedOpNum_ = 0    # Num of committed ops.

        self.generator = None
        self.lineNum_ = 1

        self.disasm_ = RISCV_Disassembler()
        self.wordRe_ = re.compile(r"[\t\n\r]")


    def Open(self, inputFileName):
        self.inputFileName_ = inputFileName
        self.inputFile_  = open(inputFileName, "r")

    def Close(self):
        if self.inputFile_ is not None :
            self.inputFile_.close()

    #
    # Parsing file
    #

    def ProcessHeader_(self, line):
        """ Process a file header """

        words = self.wordRe_.split(line)

        header = words[0]
        if header != self.RSD_HEADER :
            raise RSD_ParserError("An unknown file format.")

        # Check a file version
        version = int(words[1])
        if version != self.RSD_VERSION :
            raise RSD_ParserError("An unknown file version: %d" % (version))

    
    def ProcessLine_(self, line):
        """ Process a line. """

        words = self.wordRe_.split(line)
        cmd = words[0]

        if cmd == self.RSD_CMD_STAGE :
            self.OnRSD_Stage_(words)
        elif cmd == self.RSD_CMD_LABEL :
            self.OnRSD_Label_(words )
        elif cmd == self.RSD_CMD_CYCLE :
            self.OnRSD_Cycle_(words )
        elif cmd == self.RSD_CMD_COMMENT :
            pass    # A comment is not processed.
        elif cmd == "":
            pass    # A blank line is skipped
        else:
            raise RSD_ParserError("Unknown command:'%s'" % cmd)
       

    def OnRSD_Stage_(self, words):
        """ Dump a stage state.
        Format:
           'S', stage, valid, stall, flush, iid, mid, comment
        """

        # Check whether an op on this stage is valid or not.
        if words[2] == 'x':
            valid = False
        else:
            valid = int(words[2])
        if(not valid):
            return

        op = self.CreateOpFromString_(words)

        # if both stall and clear signals are asserted, it means send bubble and
        # it is not pipeline flush.
        flush = op.clear and not op.stall

        if (op.gid in self.flushedOpGIDs__):
            if flush:
                # Ops in a backend may be flush more than once, because there
                # are ops in pipeline stages and an active list.
                return
            else:
                print("A retired op is dumped. op: (%s)" % op.__repr__())

        comment = words[7]
        current = self.currentCycle_
        gid = op.gid
        retire = op.stageID == RSD_PARSER_RETIREMENT_STAGE_ID

        if gid < self.maxRetiredOp_:
            print("A retired op is dumped. op: (%s)" % op.__repr__())

        # Check whether an event occurs or not.
        if gid in self.ops_:
            prevOp = self.ops_[ gid ]
            op.labelOutputted = prevOp.labelOutputted

            # End stalling
            if prevOp.stall and not op.stall:
                self.AddEvent_(current, gid, RSD_Event.STALL_END, prevOp.stageID, "")
                # End and begin a current stage For output comment.
                self.AddEvent_(current, gid, RSD_Event.STAGE_END, prevOp.stageID, "")
                self.AddEvent_(current, gid, RSD_Event.STAGE_BEGIN, op.stageID, comment)
            
            # Begin stalling
            if not prevOp.stall and op.stall:
                self.AddEvent_(current, gid, RSD_Event.STALL_BEGIN, op.stageID, comment)
            
            # End/Begin a stage
            if prevOp.stageID != op.stageID:
                self.AddEvent_(current, gid, RSD_Event.STAGE_END, prevOp.stageID, "")
                self.AddEvent_(current, gid, RSD_Event.STAGE_BEGIN, op.stageID, comment)
                if retire:
                    # Count num of committed ops.
                    self.RetireOp_(op)
                    self.committedOpNum_ += 1
                    # Close a last stage
                    self.AddEvent_(current + 1, gid, RSD_Event.STAGE_END, op.stageID, "")
                    self.AddEvent_(current + 1, gid, RSD_Event.RETIRE, op.stageID, "")
        else:
            # Initialize/Begin a stage
            self.AddEvent_(current, gid, RSD_Event.INIT, op.stageID, "")
            self.AddEvent_(current, gid, RSD_Event.STAGE_BEGIN, op.stageID, comment)
            if (op.stall):
                self.AddEvent_(current, gid, RSD_Event.STALL_BEGIN, op.stageID, "")

        # if both stall and clear signals are asserted, it means send bubble and
        # it is not pipeline flush.
        if flush:
            prevOp = self.ops_[ gid ]
            if prevOp.stageID == 0:
                # When an instruction was flushed in NextPCStage,
                # delete the op from self.ops_ so that the instruction is not dumped
                del self.ops_[ gid ]
                return
            else:
                # Add events about flush
                self.AddEvent_(current, gid, RSD_Event.STAGE_END, op.stageID, "")
                self.AddEvent_(current, gid, RSD_Event.FLUSH, op.stageID, comment)
            self.FlushOp_(op)
    
        self.ops_[ gid ] = op


    def CreateOpFromString_(self, words):
        """ Create an op from strings split from a source line text. 
        Format:
           'S', stage, stall, valid, clear, iid, mid
        """
        stageID = int(words[1])
        stall = int(words[3]) != 0
        clear = int(words[4]) != 0
        iid = int(words[5])
        mid = int(words[6])
        gid = self.CreateGID_(iid, mid)
        return self.Op(iid, mid, gid, stall, clear, stageID, self.currentCycle_)

    def AddEvent_(self, cycle, gid, type, stageID, comment):
        """ Add an event to an event list.  """
        event = self.Event(gid, type, stageID, comment)
        if cycle not in self.events_:
            self.events_[ cycle ] = []
        self.events_[ cycle ].append(event)


    def OnRSD_Label_(self, words):
        """ Dump information about an op 
        Format:
            'L', iid, mid, pc, code
        """
        iid = int(words[1])
        mid = int(words[2])
        pc = words[3]
        code = words[4]
        gid = self.CreateGID_(iid, mid)

        if gid not in self.ops_:
            print("Label is outputtted with an unknown gid:%d" % gid)
        op = self.ops_[gid]

        if not op.labelOutputted:
            op.labelOutputted = True
            asmStr = self.disasm_.Disassemble(code)
            comment = "%s: %s" % (pc, asmStr)
            self.AddEvent_(self.currentCycle_, gid, RSD_Event.LABEL, -1, comment)

    def OnRSD_Cycle_(self, words):
        """ Update a processor cycle.
        Format:
           'C', 'incremented value'
        """
        self.currentCycle_ += int(words[1])
        self.ProcessEvents_(dispose=False)


    def ProcessEvents_(self, dispose):
        events = self.events_
        for cycle in sorted(events.keys()):
            # イベント投入された後のサイクルで一部取り消されるものがあるためバッファする
            # 基本的に Np ステージでの命令取り消しのみのはず
            if not dispose and cycle > self.currentCycle_ - 3:
                break
            self.generator.OnCycle(cycle)

            # Extract and process events at a current cycle.
            for e in events[cycle]:
                if e.gid in self.ops_:
                    self.generator.OnEvent(e)

                if e.type == RSD_Event.RETIRE:
                    del self.ops_[e.gid]
                    # GC
                    # リタイアした命令より古いものを削除する
                    if e.gid % 64 == 0:
                        for gid in list(self.ops_):
                            if gid < e.gid:
                                del self.ops_[gid]

            del events[cycle]


    def RetireOp_(self, op):
        self.maxRetiredOp_ = max(self.maxRetiredOp_, op.gid)
        # リタイアした命令より前のフラッシュされた命令を削除
        for gid in list(self.flushedOpGIDs__):
            if gid < self.maxRetiredOp_:
                self.flushedOpGIDs__.remove(gid)

    def FlushOp_(self, op):
        self.flushedOpGIDs__.add(op.gid)
        del self.ops_[op.gid]

    def Parse(self, generator):
        """ Parse an input file. 
        This method includes a main loop that parses a file.
        """
        self.generator = generator
        file = self.inputFile_
        
        # Process a file header.
        headerLine = file.readline()
        self.ProcessHeader_(headerLine)
        
        # Parse lines.
        while True:
            line = file.readline()
            if line == "" :
                break
            self.ProcessLine_(line)
            self.lineNum_ = self.lineNum_ + 1

        self.ProcessEvents_(dispose=True)

