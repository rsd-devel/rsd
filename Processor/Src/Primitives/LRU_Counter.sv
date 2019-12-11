// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import BasicTypes::*;

module LRU_Counter #( parameter WAY_NUM = 2, INDEX_BIT_WIDTH = 1, PORT_WIDTH = 1 )
(
input
    logic clk, rst,
    logic [ INDEX_BIT_WIDTH-1:0 ] index [ PORT_WIDTH ],
    logic access [ PORT_WIDTH ],
    logic [ $clog2(WAY_NUM)-1:0 ] accessWay [ PORT_WIDTH ],
output
    logic [ $clog2(WAY_NUM)-1:0 ] leastRecentlyAccessedWay [ PORT_WIDTH ]
);
    localparam ENTRY_NUM = 1 << INDEX_BIT_WIDTH;

    typedef logic unsigned [ $clog2(WAY_NUM)-1:0 ] LRU_Rank;
    typedef logic unsigned [ $clog2(PORT_WIDTH)-1:0 ] LRU_PortNum;
    typedef struct packed {
        LRU_Rank [ WAY_NUM-1:0 ] rank; // larger value means more recently accessd
    } LRU_Entry;

    LRU_Entry body [ ENTRY_NUM ];
    LRU_Entry readEntry [ PORT_WIDTH ];
    LRU_Entry writeEntry [ PORT_WIDTH ];
    
    logic we [ PORT_WIDTH ];
    
    always_comb begin
        for ( int i = 0; i < PORT_WIDTH; i++ ) begin
            // we, readEntry
            readEntry[i] = body[ index[i] ];
            we[i] = access[i];
            for ( int j = 0; j < i; j++ ) begin
                // Prevent write-conflict
                if ( we[j] == TRUE && index[i] == index[j] ) begin
                    we[i] = FALSE;
                end
            end
            
            // writeEntry
            if ( readEntry[i].rank[ accessWay[i] ] == WAY_NUM - 1 ) begin
                // It happened to access the way accessd most recently.
                for ( int j = 0; j < WAY_NUM; j++ ) begin
                    writeEntry[i].rank[j] = readEntry[i].rank[j];
                end
            end
            else begin
                for ( int j = 0; j < WAY_NUM; j++ ) begin
                    if ( j == accessWay[i] ) begin
                        writeEntry[i].rank[j] = WAY_NUM - 1;
                    end
                    else begin
                        writeEntry[i].rank[j] = ( readEntry[i].rank[j] == 0 ? 0 : readEntry[i].rank[j] - 1 );
                    end
                end
            end
        end

        // leastRecentlyAccessedWay
        for ( int i = 0; i < PORT_WIDTH; i++ ) begin
            leastRecentlyAccessedWay[i] = 0;
            for ( int j = 0; j < WAY_NUM; j++ ) begin
                if ( readEntry[i].rank[j] == 0 )
                    leastRecentlyAccessedWay[i] = j;
            end
        end
    end

    always_ff @ ( posedge clk ) begin
        if ( rst ) begin
            for ( int i = 0; i < ENTRY_NUM; i++ )
                for ( int j = 0; j < WAY_NUM; j++ )
                    body[i].rank[j] <= 0;
        end
        else begin
            for ( int i = 0; i < PORT_WIDTH; i++ )
                if ( we[i] )
                    body[ index[i] ] <= writeEntry[i];
        end
    end

endmodule
