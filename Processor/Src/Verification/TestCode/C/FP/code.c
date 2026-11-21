#include "../lib.c"
union fi {
    float f;
    int i;
};

int bitcast(float x){
    union fi tmp;
    tmp.f = x;
    return tmp.i;
}

int main(void){
    volatile float s = 0;
    for(int i=1;i<=100;++i){
        s = (s - i) * 3.0f / i + 1.5f;
        serial_out_hex(bitcast(s));
        serial_out_char('\n');
    }
    return 0;
}
