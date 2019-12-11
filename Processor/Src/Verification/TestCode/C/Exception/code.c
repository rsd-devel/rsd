#include "../lib.c"

#define LOOP_NUM 10000

int rand(void) {
  static unsigned int y = 1987534242;
  y = y ^ (y << 13); y = y ^ (y >> 17);
  return y = y ^ (y << 5);
}

void main(){

    volatile int memory[LOOP_NUM];
    volatile int tmp=0;
    volatile int sum = 0;
    //memory = (int*)0x20000;   //stack top

    int i;
    for(i=0;i<LOOP_NUM;i++){
        if( rand()&0x1 ){   //分岐はランダムなので50%でミスが起こる
            *(memory) = 0x1;
        }else{
            *(memory) = 0x0;
        }
        tmp += *(memory);   //メモリ順序違反を起こしうる
        sum += i;

        if(*memory == 0x1){     //メモリ順序違反を起こしうる
            serial_out_char('1');
        }else{
            serial_out_char('0');
        }
    }

    //最後のシリアル出力のためのウェイト
    for(i=0; i<100; i++) sum += i;
}
