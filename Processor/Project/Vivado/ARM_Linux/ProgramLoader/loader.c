// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// Cross-compiled by Buildroot and installed as /usr/bin/rsd-loader.
// Usage: rsd-loader code.hex [decoded-byte-size]

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define RAM_SIZE 0x10000000u
#define CONTROL_SIZE 0x1000u
#define DONE_OFFSET 6
#define L2S_EMPTY_OFFSET 0
#define L2S_DATA_OFFSET 1

// UIO numbering depends on probe order. Use the names in rsd-zed.dts instead.
static volatile uint32_t *map_uio(const char *name, size_t size)
{
    glob_t entries = {0};
    volatile uint32_t *mapping = MAP_FAILED;
    if (glob("/sys/class/uio/uio*/name", 0, NULL, &entries) == 0) {
        for (size_t i = 0; i < entries.gl_pathc; i++) {
            char actual[64];
            FILE *fp = fopen(entries.gl_pathv[i], "r");
            if (!fp)
                continue;
            int match = fgets(actual, sizeof(actual), fp) != NULL;
            fclose(fp);
            if (!match)
                continue;
            actual[strcspn(actual, "\r\n")] = '\0';
            if (strcmp(name, actual) != 0)
                continue;
            // Replace /sys/class/uio/ with /dev/ and remove /name.
            char device[128];
            snprintf(device, sizeof(device), "/dev/%s", entries.gl_pathv[i] + strlen("/sys/class/uio/"));
            *strrchr(device, '/') = '\0';
            int fd = open(device, O_RDWR | O_SYNC);
            if (fd >= 0) {
                mapping = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
                close(fd);
            }
            break;
        }
    }
    globfree(&entries);
    if (mapping == MAP_FAILED)
        fprintf(stderr, "Cannot map UIO device %s\n", name);
    return mapping;
}

// Each HEX line is one 128-bit word, most significant digits first.
// Reverse the four 32-bit groups for the little-endian AXI memory interface.
static int read_word(FILE *fp, uint32_t words[4])
{
    char line[36];
    if (!fgets(line, sizeof(line), fp))
        return ferror(fp) ? -1 : 0;
    if (strcspn(line, "\r\n") != 32)
        return -1;
    for (size_t i = 32; line[i]; i++)
        if (line[i] != '\r' && line[i] != '\n')
            return -1;
    for (size_t i = 0; i < 32; i++)
        if (!isxdigit((unsigned char)line[i]))
            return -1;
    for (size_t i = 0; i < 4; i++) {
        char group[9];
        memcpy(group, line + 8 * i, 8);
        group[8] = '\0';
        words[3 - i] = (uint32_t)strtoul(group, NULL, 16);
    }
    return 1;
}

int main(int argc, char **argv)
{
    if (argc == 2 && (!strcmp(argv[1], "-h") || !strcmp(argv[1], "--help"))) {
        puts("Usage: rsd-loader code.hex [decoded-byte-size]");
        return 0;
    }
    if (argc < 2 || argc > 3) {
        fprintf(stderr, "Usage: rsd-loader code.hex [decoded-byte-size]\n");
        return 1;
    }
    FILE *fp = fopen(argv[1], "r");
    if (!fp) {
        perror(argv[1]);
        return 1;
    }
    // Validate before accessing hardware, without a program-sized stack buffer.
    uint32_t words[4];
    size_t bytes = 0;
    int result;
    while ((result = read_word(fp, words)) == 1) {
        bytes += sizeof(words);
        if (bytes > RAM_SIZE)
            break;
    }
    if (result < 0 || !bytes || bytes > RAM_SIZE) {
        fprintf(stderr, "Invalid HEX: expected 128-bit lines fitting in RSD RAM\n");
        fclose(fp);
        return 1;
    }
    if (argc == 3) {
        char *end;
        errno = 0;
        unsigned long expected = strtoul(argv[2], &end, 0);
        if (errno || end == argv[2] || *end || expected != bytes) {
            fprintf(stderr, "Decoded size mismatch: HEX contains %zu bytes\n", bytes);
            fclose(fp);
            return 1;
        }
    }
    rewind(fp);
    volatile uint32_t *ram = map_uio("rsd-ram", RAM_SIZE);
    volatile uint32_t *pl2ps = map_uio("rsd-pl2ps", CONTROL_SIZE);
    volatile uint32_t *ps2pl = map_uio("rsd-ps2pl", CONTROL_SIZE);
    if (ram == MAP_FAILED || pl2ps == MAP_FAILED || ps2pl == MAP_FAILED)
        goto done;

    ps2pl[DONE_OFFSET] = 0;
    __sync_synchronize();
    for (size_t i = 0; i < RAM_SIZE / sizeof(*ram); i++)
        ram[i] = 0;
    for (size_t i = 0; i < bytes / sizeof(words); i++) {
        if (read_word(fp, words) != 1) {
            fprintf(stderr, "HEX changed while loading\n");
            goto done;
        }
        for (size_t j = 0; j < 4; j++)
            ram[4 * i + j] = words[j];
    }
    // Publish DDR writes before releasing the core from reset.
    __sync_synchronize();
    ps2pl[DONE_OFFSET] = 1;
    setvbuf(stdout, NULL, _IONBF, 0);
    // Output is consumed by reading DATA. Interrupt with Ctrl-C when finished.
    for (;;) {
        if (pl2ps[L2S_EMPTY_OFFSET] != 1)
            putchar((unsigned char)pl2ps[L2S_DATA_OFFSET]);
    }

done:
    fclose(fp);
    if (ram != MAP_FAILED) munmap((void *)ram, RAM_SIZE);
    if (pl2ps != MAP_FAILED) munmap((void *)pl2ps, CONTROL_SIZE);
    if (ps2pl != MAP_FAILED) munmap((void *)ps2pl, CONTROL_SIZE);
    return 1;
}
