#include "../lib.c"

int main(void)
{
    const char *message = "Hello,World!\n";
    while (*message) {
        serial_out_char(*message++);
    }
    return 0;
}
