#include "stdlib.h"

signed char Link_C_get8 (void* p) { return * (signed char*) p; }
signed short Link_C_get16 (void* p) { return * (signed short*) p; }
signed long Link_C_get32 (void* p) { return * (signed long*) p; }

void* Link_C_malloc (int size) {
	return malloc(size);
}
void Link_C_free (void* p) {
	free(p);
}

