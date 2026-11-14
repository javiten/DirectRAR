#include "Extractor.h"
#include <archive.h>
#include <archive_entry.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

static int safe_name(const char *p) {
    if (!p || !*p || *p=='/' || strchr(p,'\\')) return 0;
    const char *s=p;
    do {
        const char *e=strchr(s,'/'); size_t n=e?(size_t)(e-s):strlen(s);
        if ((n==2 && s[0]=='.' && s[1]=='.') || memchr(s,':',n)) return 0;
        if (!e) break;
        s=e+1;
    } while (*s);
    return 1;
}
// Walk beneath an opened root with O_NOFOLLOW; never traverse archive links.
static int parent_fd(int root, char *path, char **leaf) {
    int fd=dup(root); if(fd<0) return -1;
    char *p=path, *slash;
    while((slash=strchr(p,'/'))) {
        *slash=0;
        if (*p && strcmp(p,".")) {
            if(mkdirat(fd,p,0700)<0 && errno!=EEXIST) {close(fd);return -1;}
            int next=openat(fd,p,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
            close(fd); if(next<0)return -1; fd=next;
        }
        p=slash+1;
    }
    *leaf=p; return fd;
}
int dr_extract(const char *source,const char *destination,dr_progress cb,void *ctx,char *err,size_t cap) {
    int result=1, root=-1, out=-1; int64_t written=0;
    struct archive *a=archive_read_new(); struct archive_entry *entry=NULL;
    if(cap)err[0]=0;
    if(!a){snprintf(err,cap,"No se pudo iniciar el extractor.");return 1;}
    archive_read_support_filter_all(a);
    archive_read_support_format_rar(a); archive_read_support_format_rar5(a);
    archive_read_support_format_zip(a); archive_read_support_format_7zip(a);
    root=open(destination,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if(root<0)goto system_error;
    if(archive_read_open_filename(a,source,128*1024)!=ARCHIVE_OK)goto archive_error;
    for (;;) {
        if(cb && cb(ctx,archive_filter_bytes(a,-1),written,"")){result=2;goto done;}
        int status=archive_read_next_header(a,&entry);
        if(status==ARCHIVE_EOF){result=0;goto done;}
        if(status!=ARCHIVE_OK)goto archive_error;
        const char *name=archive_entry_pathname_utf8(entry);
        if(!name)name=archive_entry_pathname(entry);
        if(!safe_name(name) || archive_entry_symlink(entry) || archive_entry_hardlink(entry)) {
            snprintf(err,cap,"Ruta o enlace no permitido en el archivo.");goto done;
        }
        mode_t type=archive_entry_filetype(entry);
        if(type!=AE_IFREG && type!=AE_IFDIR){snprintf(err,cap,"Tipo de entrada no compatible.");goto done;}
        char *path=strdup(name); if(!path)goto system_error;
        size_t len=strlen(path); while(len && path[len-1]=='/')path[--len]=0;
        char *leaf=NULL; int parent=parent_fd(root,path,&leaf);
        if(parent<0){free(path);goto system_error;}
        if(type==AE_IFDIR) {
            int ok=mkdirat(parent,leaf,0700);
            if(ok<0 && errno==EEXIST){int d=openat(parent,leaf,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);ok=d<0?-1:0;if(d>=0)close(d);}
            close(parent);free(path);if(ok<0)goto system_error;continue;
        }
        out=openat(parent,leaf,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
        close(parent);free(path);if(out<0)goto system_error;
        char buffer[128*1024];
        for (;;) {
            if(cb && cb(ctx,archive_filter_bytes(a,-1),written,name)){result=2;goto done;}
            la_ssize_t n=archive_read_data(a,buffer,sizeof(buffer));
            if(n<0)goto archive_error;
            if(n==0)break;
            la_ssize_t pos=0;
            while(pos<n){ssize_t count=write(out,buffer+pos,(size_t)(n-pos));if(count<0 && errno==EINTR)continue;if(count<=0)goto system_error;pos+=count;}
            written+=n;
        }
        if(close(out)<0){out=-1;goto system_error;}out=-1;
    }
archive_error:
    snprintf(err,cap,"%s",archive_error_string(a)?archive_error_string(a):"Error de lectura del archivo.");goto done;
system_error:
    snprintf(err,cap,"%s",strerror(errno));
done:
    if(out>=0)close(out);
    if(root>=0)close(root);
    archive_read_free(a);
    return result;
}
