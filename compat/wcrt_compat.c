/**
 * @file wcrt_compat.c
 * @brief Supplies the small Win32/POSIX bridge needed by GNU Bison.
 */

#include <config.h>

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <windows.h>

#include "progname.h"

#define BISON_DESCRIPTOR_COUNT 64
#define BISON_O_WRONLY 0x0001
#define BISON_O_RDWR 0x0002
#define BISON_O_APPEND 0x0008
#define BISON_O_CREAT 0x0100
#define BISON_O_TRUNC 0x0200
#define BISON_O_EXCL 0x0400

static HANDLE descriptors[BISON_DESCRIPTOR_COUNT];
static char *empty_environment[] = {NULL};
char **environ = empty_environment;

static HANDLE
descriptor_handle(int descriptor)
{
    if (descriptor == 0)
        return GetStdHandle(STD_INPUT_HANDLE);
    if (descriptor == 1)
        return GetStdHandle(STD_OUTPUT_HANDLE);
    if (descriptor == 2)
        return GetStdHandle(STD_ERROR_HANDLE);
    if (descriptor < 0 || descriptor >= BISON_DESCRIPTOR_COUNT)
        return INVALID_HANDLE_VALUE;
    return descriptors[descriptor] ? descriptors[descriptor] : INVALID_HANDLE_VALUE;
}

static int
register_handle(HANDLE handle)
{
    int descriptor;
    for (descriptor = 3; descriptor < BISON_DESCRIPTOR_COUNT; ++descriptor)
        if (!descriptors[descriptor])
        {
            descriptors[descriptor] = handle;
            return descriptor;
        }
    errno = EMFILE;
    return -1;
}

/** Return the name initialized by gnulib's set_program_name. */
const char *
getprogname(void)
{
    return program_name ? program_name : "bison";
}

/** Create a directory using the Win32 filesystem API. */
int
_mkdir(const char *path)
{
    if (CreateDirectoryA(path, NULL))
        return 0;
    errno = EACCES;
    return -1;
}

/** Change the process working directory. */
int
_chdir(const char *path)
{
    if (SetCurrentDirectoryA(path))
        return 0;
    errno = ENOENT;
    return -1;
}

/** Return the process working directory. */
char *
_getcwd(char *buffer, int size)
{
    unsigned long length;
    if (!buffer || size <= 0)
    {
        errno = EINVAL;
        return NULL;
    }
    length = GetCurrentDirectoryA((unsigned long)size, buffer);
    if (length == 0 || length >= (unsigned long)size)
    {
        errno = ERANGE;
        return NULL;
    }
    return buffer;
}

/** Remove an empty directory. */
int
_rmdir(const char *path)
{
    if (RemoveDirectoryA(path))
        return 0;
    errno = EACCES;
    return -1;
}

/** Test whether a path exists and optionally whether it is writable. */
int
_access(const char *path, int mode)
{
    unsigned long attributes = GetFileAttributesA(path);
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        errno = ENOENT;
        return -1;
    }
    if ((mode & 2) && (attributes & FILE_ATTRIBUTE_READONLY))
    {
        errno = EACCES;
        return -1;
    }
    return 0;
}

/** Set the portable writable bit represented by Microsoft chmod. */
int
_chmod(const char *path, int mode)
{
    unsigned long attributes = GetFileAttributesA(path);
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        errno = ENOENT;
        return -1;
    }
    if (mode & 0200)
        attributes &= ~FILE_ATTRIBUTE_READONLY;
    else
        attributes |= FILE_ATTRIBUTE_READONLY;
    if (!SetFileAttributesA(path, attributes))
    {
        errno = EACCES;
        return -1;
    }
    return 0;
}

/** Remove a regular file. */
int
_unlink(const char *path)
{
    if (DeleteFileA(path))
        return 0;
    errno = EACCES;
    return -1;
}

/** Open a file as a Win32 handle and return a small descriptor. */
int
_open(const char *path, int flags, ...)
{
    unsigned long desired_access = GENERIC_READ;
    unsigned long creation = OPEN_EXISTING;
    HANDLE handle;
    int descriptor;

    if ((flags & 3) == BISON_O_WRONLY)
        desired_access = GENERIC_WRITE;
    else if ((flags & 3) == BISON_O_RDWR)
        desired_access = GENERIC_READ | GENERIC_WRITE;

    if ((flags & (BISON_O_CREAT | BISON_O_EXCL)) ==
        (BISON_O_CREAT | BISON_O_EXCL))
        creation = CREATE_NEW;
    else if ((flags & (BISON_O_CREAT | BISON_O_TRUNC)) ==
             (BISON_O_CREAT | BISON_O_TRUNC))
        creation = CREATE_ALWAYS;
    else if (flags & BISON_O_CREAT)
        creation = OPEN_ALWAYS;
    else if (flags & BISON_O_TRUNC)
        creation = TRUNCATE_EXISTING;

    handle = CreateFileA(path, desired_access,
                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                         NULL, creation, FILE_ATTRIBUTE_NORMAL, NULL);
    if (handle == INVALID_HANDLE_VALUE)
    {
        errno = EACCES;
        return -1;
    }
    descriptor = register_handle(handle);
    if (descriptor < 0)
    {
        CloseHandle(handle);
        return -1;
    }
    if (flags & BISON_O_APPEND)
        SetFilePointer(handle, 0, NULL, FILE_END);
    return descriptor;
}

/** Close a compatibility descriptor. */
int
_close(int descriptor)
{
    HANDLE handle = descriptor_handle(descriptor);
    if (descriptor < 3 || handle == INVALID_HANDLE_VALUE)
    {
        if (descriptor >= 0 && descriptor < 3)
            return 0;
        errno = EBADF;
        return -1;
    }
    descriptors[descriptor] = NULL;
    if (!CloseHandle(handle))
    {
        errno = EIO;
        return -1;
    }
    return 0;
}

/** Return the Win32 handle represented by a descriptor. */
intptr_t
_get_osfhandle(int descriptor)
{
    HANDLE handle = descriptor_handle(descriptor);
    if (handle == INVALID_HANDLE_VALUE)
    {
        errno = EBADF;
        return -1;
    }
    return (intptr_t)handle;
}

/** Adopt a Win32 handle into the compatibility descriptor table. */
int
_open_osfhandle(intptr_t handle, int flags)
{
    (void)flags;
    return register_handle((HANDLE)handle);
}

/** Duplicate a compatibility descriptor. */
int
_dup(int descriptor)
{
    HANDLE source = descriptor_handle(descriptor);
    HANDLE duplicate = NULL;
    if (source == INVALID_HANDLE_VALUE ||
        !DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(),
                         &duplicate, 0, TRUE, DUPLICATE_SAME_ACCESS))
    {
        errno = EBADF;
        return -1;
    }
    return register_handle(duplicate);
}

/** Duplicate a compatibility descriptor to a requested slot. */
int
_dup2(int source_descriptor, int destination_descriptor)
{
    HANDLE source = descriptor_handle(source_descriptor);
    HANDLE duplicate = NULL;
    if (source == INVALID_HANDLE_VALUE || destination_descriptor < 0 ||
        destination_descriptor >= BISON_DESCRIPTOR_COUNT ||
        !DuplicateHandle(GetCurrentProcess(), source, GetCurrentProcess(),
                         &duplicate, 0, TRUE, DUPLICATE_SAME_ACCESS))
    {
        errno = EBADF;
        return -1;
    }
    if (destination_descriptor < 3)
        SetStdHandle(destination_descriptor == 0 ? STD_INPUT_HANDLE :
                     destination_descriptor == 1 ? STD_OUTPUT_HANDLE :
                                                   STD_ERROR_HANDLE,
                     duplicate);
    else
    {
        if (descriptors[destination_descriptor])
            CloseHandle(descriptors[destination_descriptor]);
        descriptors[destination_descriptor] = duplicate;
    }
    return 0;
}

/** Read bytes through a compatibility descriptor. */
int
_read(int descriptor, void *buffer, unsigned int size)
{
    unsigned long transferred = 0;
    HANDLE handle = descriptor_handle(descriptor);
    if (handle == INVALID_HANDLE_VALUE ||
        !ReadFile(handle, buffer, size, &transferred, NULL))
    {
        errno = EIO;
        return -1;
    }
    return (int)transferred;
}

/** Write bytes through a compatibility descriptor. */
int
_write(int descriptor, const void *buffer, unsigned int size)
{
    unsigned long transferred = 0;
    HANDLE handle = descriptor_handle(descriptor);
    if (handle == INVALID_HANDLE_VALUE ||
        !WriteFile(handle, buffer, size, &transferred, NULL))
    {
        errno = EIO;
        return -1;
    }
    return (int)transferred;
}

/** Seek a compatibility descriptor. */
long
_lseek(int descriptor, long offset, int origin)
{
    unsigned long result;
    HANDLE handle = descriptor_handle(descriptor);
    if (handle == INVALID_HANDLE_VALUE)
    {
        errno = EBADF;
        return -1;
    }
    result = SetFilePointer(handle, offset, NULL, (unsigned long)origin);
    if (result == INVALID_SET_FILE_POINTER && GetLastError() != NO_ERROR)
    {
        errno = EIO;
        return -1;
    }
    return (long)result;
}

/** Report whether a descriptor names a character device. */
int
_isatty(int descriptor)
{
    HANDLE handle = descriptor_handle(descriptor);
    return handle != INVALID_HANDLE_VALUE && GetFileType(handle) == FILE_TYPE_CHAR;
}

/** Report the fixed compatibility descriptor capacity. */
int
_getmaxstdio(void)
{
    return BISON_DESCRIPTOR_COUNT;
}

/** Accept descriptor-limit requests up to the compatibility capacity. */
int
_setmaxstdio(int count)
{
    return count <= BISON_DESCRIPTOR_COUNT ? count : BISON_DESCRIPTOR_COUNT;
}

/** Supply the C99 sign-bit operation missing from WCRT 0.9.5. */
int
signbit(double value)
{
    union
    {
        double real;
        unsigned long long bits;
    } representation;
    representation.real = value;
    return (int)(representation.bits >> 63);
}

/** Terminate without invoking C exit handlers. */
void
_exit(int status)
{
    ExitProcess((unsigned int)status);
}

/** WCRT streams are already binary-safe on Windows. */
int
_setmode(int descriptor, int mode)
{
    (void)descriptor;
    (void)mode;
    return 0;
}

/** Wait for the process handle returned by gnulib's Win32 spawn layer. */
intptr_t
_cwait(int *status, intptr_t process_handle, int action)
{
    unsigned long exit_code = 1;
    void *handle = (void *)process_handle;
    (void)action;
    if (WaitForSingleObject(handle, INFINITE) != WAIT_OBJECT_0 ||
        !GetExitCodeProcess(handle, &exit_code))
    {
        errno = ECHILD;
        return -1;
    }
    CloseHandle(handle);
    if (status)
        *status = (int)(exit_code << 8);
    return process_handle;
}

/** Return the Win32 process identifier. */
int
_getpid(void)
{
    return (int)GetCurrentProcessId();
}

/** Descriptor-backed status is unavailable in WCRT 0.9.5. */
int
_fstati64(int descriptor, struct _stat64 *status)
{
    (void)descriptor;
    (void)status;
    errno = ENOSYS;
    return -1;
}

/**
 * Keep accidental descriptor-to-stream conversion safe.  The WCRT port's
 * M4 path uses temporary files and never calls this compatibility entry.
 */
FILE *
_fdopen(int descriptor, const char *mode)
{
    (void)descriptor;
    (void)mode;
    errno = ENOSYS;
    return NULL;
}
