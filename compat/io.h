/* Microsoft low-level I/O declarations consumed by gnulib on Windows. */
#ifndef BISON_PACKAGE_IO_H
#define BISON_PACKAGE_IO_H

#include <stdint.h>

int _access(const char *path, int mode);
int _chmod(const char *path, int mode);
int _close(int descriptor);
int _dup(int descriptor);
int _dup2(int source, int destination);
intptr_t _get_osfhandle(int descriptor);
int _isatty(int descriptor);
long _lseek(int descriptor, long offset, int origin);
int _open(const char *path, int flags, ...);
int _open_osfhandle(intptr_t handle, int flags);
int _pipe(int descriptors[2], unsigned int size, int mode);
int _read(int descriptor, void *buffer, unsigned int size);
int _setmode(int descriptor, int mode);
int _unlink(const char *path);
int _write(int descriptor, const void *buffer, unsigned int size);
int _getmaxstdio(void);
int _setmaxstdio(int count);

#endif
