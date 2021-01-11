# -*- coding: utf-8 -*-

#
# Parse a RSD log file.
#
# This class is used by KanataConverter.
#
# There are several IDs in this script:
#
#   iid: An unique id for each instruction in a RSD log file. 
#       This is outputted from SystemVerilog code.
#   mid: The index of a micro-op in each instruction.
#       This is outputted from SystemVerilog code.
#
#   gid: An unique id for each micro-op in this script. 
#       This is calculated from iid and mid for internal use.
#   cid: An unique id for each 'committed' micro op in a Kanata log. 
#       This is calculated from gid.
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

class RSD_ParserError( Exception ):
    """ An exception class for RSD_Parser """
    pass


class RSD_Parser( object ):
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
    def CreateGID( self, iid, mid ):
        """ Create unique 'gid' from 'iid' and 'mid'. """
        if mid >= RSD_Parser.MAX_MICRO_OPS_PER_INSN:
            raise RSD_ParserError( "'mid' exceeds MAX_MICRO_OPS_PER_INSN at iid(%d)" % iid  )
        
        # A           B
        # |<----W---->|<----W---->|
        # |----r---g--|-----------|: n = A
        # |----g---r--|-----------|: n = A
        # |--------r--|--g--------|: n = B
        # |--------g--|--r--------|: n = A
        g = mid + iid * RSD_Parser.MAX_MICRO_OPS_PER_INSN
        W = RSD_Parser.GID_WRAP_AROUND
        M = W / 4
        r = self.maxRetiredOp % W
        n = self.maxRetiredOp - r

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

    class Op( object ):
        """ Op class. """
        def __init__( self, iid, mid, gid, stall, clear, stageID, updatedCycle ):
            self.iid = iid
            self.mid = mid
            self.gid = gid
            self.cid = RSD_PARSER_CID_DEFAULT
            self.stageID = stageID
            self.stall = stall
            self.clear = clear
            self.updatedCycle = updatedCycle
            self.commit = False

        def __repr__( self ):
            return (
                "{gid:%s, cid: %s, stall:%s, clear:%s, stageID:%s, updatedCycle: %s}" % 
                ( self.gid, self.cid, self.stall, self.clear, self.stageID, self.updatedCycle )
            )


    class Event( object ):
        """ Event class """
        def __init__( self, gid, type, stageID, comment, op):
            self.gid = gid
            self.type = type
            self.stageID = stageID
            self.comment = comment
            self.op = op

        def __repr__( self ):
            return (
                "{gid:%s, type:%s, stageID:%s, comment:%s}" % 
                ( self.gid, self.type, self.stageID, self.comment )
            )

    def __init__( self ):
        """ Initializer """

        self.inputFileName = ""
        self.inputFile = None

        # A current processor cycle.
        self.currentCycle = RSD_PARSER_INITIAL_CYCLE

        self.ops = {}       # gid -> Op map
        self.events = {}    # cycle -> Event map
        self.retired = set( [] )    # retired gids
        self.maxRetiredOp = 0      # The maximum number in retired ops.
        self.committedOpNum = 0    # Num of committed ops.

        self.generator = None
        self.nextCycleForGenerator = 0
        self.lineNum = 1

        self.disassembler = RISCV_Disassembler()


    def Open( self, inputFileName ):
        self.inputFileName = inputFileName
        self.inputFile  = open( inputFileName, "r" )

    def Close( self ):
        if self.inputFile is not None :
            self.inputFile.close()

    #
    # Parsing file
    #

    def ProcessHeader( self, line ):
        """ Process a file header """

        words = re.split( r"[\t\n\r]", line )

        header = words[0]
        if header != self.RSD_HEADER :
            raise RSD_ParserError( 
                "An unknown file format."
            )

        # Check a file version
        version = int( words[1] )
        if version != self.RSD_VERSION :
            raise RSD_ParserError( 
                "An unknown file version: %d" % ( version ) 
            )

    
    def ProcessLine( self, line ):
        """ Process a line. """

        words = re.split( r"[\t\n\r]", line )
        cmd = words[0]

        if cmd == self.RSD_CMD_STAGE :
            self.OnRSD_Stage( words )
        elif cmd == self.RSD_CMD_LABEL :
            self.OnRSD_Label( words )
        elif cmd == self.RSD_CMD_CYCLE :
            self.OnRSD_Cycle( words )
        elif cmd == self.RSD_CMD_COMMENT :
            pass    # A comment is not processed.
        elif cmd == "":
            pass    # A blank line is skipped
        else:
            raise RSD_ParserError("Unknown command:'%s'" % cmd)
       

    def OnRSD_Stage( self, words ):
        """ Dump a stage state.
        Format:
           'S', stage, valid, stall, flush, iid, mid, comment
        """

        # Check whether an op on this stage is valid or not.
        if words[2] == 'x':
            valid = False
        else:
            valid = int( words[2] )
        if( not valid ):
            return

        op = self.CreateOpFromString( words )

        # if both stall and clear signals are asserted, it means send bubble and
        # it is not pipeline flush.
        flush = op.clear and not op.stall

        if (op.gid in self.retired):
            if flush:
                # Ops in a backend may be flush more than once, because there
                # are ops in pipeline stages and an active list.
                return
            else:
                print("A retired op is dumped. op: (%s)" % op.__repr__())

        comment = words[7]
        current = self.currentCycle
        gid = op.gid
        retire = op.stageID == RSD_PARSER_RETIREMENT_STAGE_ID

        # Check whether an event occurs or not.
        if gid in self.ops:
            prevOp = self.ops[ gid ]

            # End stalling
            if prevOp.stall and not op.stall:
                self.AddEvent( current, gid, RSD_Event.STALL_END, prevOp.stageID, "", op)
                # End and begin a current stage For output comment.
                self.AddEvent( current, gid, RSD_Event.STAGE_END, prevOp.stageID, "", op)
                self.AddEvent( current, gid, RSD_Event.STAGE_BEGIN, op.stageID, comment, op)
            
            # Begin stalling
            if not prevOp.stall and op.stall:
                self.AddEvent( current, gid, RSD_Event.STALL_BEGIN, op.stageID, comment, op)
            
            # End/Begin a stage
            if prevOp.stageID != op.stageID:
                self.AddEvent( current, gid, RSD_Event.STAGE_END, prevOp.stageID, "", op)
                self.AddEvent( current, gid, RSD_Event.STAGE_BEGIN, op.stageID, comment, op)
                if retire:
                    # Count num of committed ops.
                    op.commit = True
                    op.cid = self.committedOpNum
                    self.AddRetiredGID(gid, op)
                    self.committedOpNum += 1
                    # Close a last stage
                    self.AddEvent( current + 1, gid, RSD_Event.STAGE_END, op.stageID, "", op)
                    self.AddEvent( current + 1, gid, RSD_Event.RETIRE, op.stageID, "", op)
        else:
            # Initialize/Begin a stage
            self.AddEvent( current, gid, RSD_Event.INIT, op.stageID, "", op)
            self.AddEvent( current, gid, RSD_Event.STAGE_BEGIN, op.stageID, comment, op)
            if ( op.stall ):
                self.AddEvent( current, gid, RSD_Event.STALL_BEGIN, op.stageID, "", op)

        # if both stall and clear signals are asserted, it means send bubble and
        # it is not pipeline flush.
        if flush:
            prevOp = self.ops[ gid ]
            if prevOp.stageID == 0:
                # When an instruction was flushed in NextPCStage,
                # delete the op from self.ops so that the instruction is not dumped
                del self.ops[ gid ]
                return
            else:
                # Add events about flush
                self.AddEvent( current, gid, RSD_Event.STAGE_END, op.stageID, "", op)
                self.AddEvent( current, gid, RSD_Event.FLUSH, op.stageID, comment, op)
            self.AddRetiredGID(gid, op)

        self.ops[ gid ] = op


    def CreateOpFromString( self, words ):
        """ Create an op from strings split from a source line text. 
        Format:
           'S', stage, stall, valid, clear, iid, mid
        """
        stageID = int( words[1] )
        stall = int( words[3] ) != 0
        clear = int( words[4] ) != 0
        iid = int( words[5] )
        mid = int( words[6] )
        gid = self.CreateGID( iid, mid )
        return self.Op( iid, mid, gid, stall, clear, stageID, self.currentCycle )


    def AddEvent( self, cycle, gid, type, stageID, comment, op):
        """ Add an event to an event list.  """
        event = self.Event( gid, type, stageID, comment, op)
        if cycle not in self.events:
            self.events[ cycle ] = []
        self.events[ cycle ].append( event )


    def OnRSD_Label( self, words ):
        """ Dump information about an op 
        Format:
            'L', iid, mid, pc, code
        """
        iid = int( words[1] )
        mid = int( words[2] )
        pc = words[3]
        code = words[4]
        gid = self.CreateGID( iid, mid )

        pcStr = pc
        asmStr = self.disassembler.Disassemble(code)
        comment = "%s: %s" % (pcStr, asmStr)
        self.AddEvent(self.currentCycle, gid, RSD_Event.LABEL, -1, comment, None)


    def OnRSD_Cycle(self, words):
        """ Update a processor cycle.
        Format:
           'C', 'incremented value'
        """
        self.currentCycle += int(words[1])
        self.ProcessEvents(dispose=False)
    
    def ProcessEvents(self, dispose):
        events = self.events
        for cycle in sorted(events.keys()):
            if not dispose and cycle >  self.currentCycle - 100:
                break
            self.generator.OnCycleEnd(cycle)
            # Extract and process events at a current cycle.
            for e in events[cycle]:
                if e.gid in self.ops:
                    self.generator.OnEvent(e)
            del events[cycle]


    def AddRetiredGID(self, gid, op):
        """ Add a gid to a retired op list. """
        self.retired.add(gid)
        self.maxRetiredOp = max(self.maxRetiredOp, gid)


    def Parse(self, generator):
        """ Parse an input file. 
        This method includes a main loop that parses a file.
        """
        self.generator = generator
        file = self.inputFile
        
        # Process a file header.
        headerLine = file.readline()
        self.ProcessHeader( headerLine )
        
        # Parse lines.
        while True:
            line = file.readline()
            if line == "" :
                break
            self.ProcessLine( line )
            self.lineNum = self.lineNum + 1

        self.ProcessEvents(dispose=True)

