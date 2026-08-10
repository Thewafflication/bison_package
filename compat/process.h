/* Minimal native-Windows process constants used by gnulib's spawn code.
   WCRT intentionally does not expose the Microsoft CRT process API.  */
#ifndef BISON_PACKAGE_PROCESS_H
#define BISON_PACKAGE_PROCESS_H

#include <stdint.h>

#define _P_WAIT 0
#define _P_NOWAIT 1
#define _P_OVERLAY 2
#define _P_NOWAITO 3
#define _P_DETACH 4

#define P_WAIT _P_WAIT
#define P_NOWAIT _P_NOWAIT
#define P_OVERLAY _P_OVERLAY
#define P_NOWAITO _P_NOWAITO
#define P_DETACH _P_DETACH

#define _WAIT_CHILD 0
#define WAIT_CHILD _WAIT_CHILD

intptr_t _cwait(int *status, intptr_t process_handle, int action);

#endif
