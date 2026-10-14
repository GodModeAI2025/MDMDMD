#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <sandbox.h>
int main(void) { char *err=0; int rc=sandbox_init("(version 1)(allow default)(deny file-read-data (literal \"/\"))",0,&err); if(rc){fprintf(stderr,"sandbox unavailable: %s\n",err);return 2;} int a=open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC); printf("root_read=%d errno=%d\n",a,errno); if(a>=0)close(a); errno=0; int b=open("/",O_SEARCH|O_CLOEXEC); printf("root_search=%d errno=%d\n",b,errno); if(b>=0)close(b); return 0; }
