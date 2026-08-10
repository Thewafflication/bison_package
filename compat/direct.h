/* Microsoft-compatible directory declarations implemented by this port.  */
#ifndef BISON_PACKAGE_DIRECT_H
#define BISON_PACKAGE_DIRECT_H

int _chdir(const char *path);
char *_getcwd(char *buffer, int size);
int _mkdir(const char *path);
int _rmdir(const char *path);

#endif
