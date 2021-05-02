#include <stdio.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: mksparsedmg dmgpath\n");
        return 1;
    }
    FILE *f = fopen(argv[1], "wb");
#include "sparsedmg_data.c"
    fclose(f);
}