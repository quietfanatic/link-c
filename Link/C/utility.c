#include "stdlib.h"

signed char Link_C_get8 (void* p) { return * (signed char*) p; }
void Link_C_set8 (void* p, signed char value) { * (signed char*) p = value; }
signed short Link_C_get16 (void* p) { return * (signed short*) p; }
void Link_C_set16 (void* p, signed short value) { * (signed short*) p = value; }
signed long Link_C_get32 (void* p) { return * (signed long*) p; }
void Link_C_set32 (void* p, signed long value) { * (signed long*) p = value; }

void* Link_C_malloc (int size) {
	return malloc(size);
}
void Link_C_free (void* p) {
	free(p);
}

