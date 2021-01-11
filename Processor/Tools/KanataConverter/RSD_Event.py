# -*- coding: utf-8 -*-

class RSD_Label( object ):
    """ Label information of an op """
    def __init__( self ):
        self.iid = 0
        self.mid = 0
        self.pc = 0
        self.code = ""

    def __repr__( self ):
        return "{iid:%d, mid:%d, pc: %s, code: %s}" % ( self.iid, self.mid, self.pc, self.code )

class RSD_Event(object):
    """ Parser event types """

    INIT = 0
    STAGE_BEGIN = 1
    STAGE_END = 2
    STALL_BEGIN = 3
    STALL_END = 4
    RETIRE = 5
    FLUSH = 6
    LABEL = 7
