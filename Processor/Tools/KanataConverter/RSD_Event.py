# -*- coding: utf-8 -*-

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
