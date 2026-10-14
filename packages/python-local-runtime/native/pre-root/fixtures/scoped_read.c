#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include "moonbit.h"
#include "moonbit_runtime.h"

extern void *mi_malloc(size_t);
extern void mi_free(void *);
static size_t stock_mi_allocations, stock_file_allocations, stock_mi_frees, stock_file_frees;
static void *observed_mi_malloc(size_t n) { stock_mi_allocations++; return mi_malloc(n); }
static void observed_mi_free(void *p) { stock_mi_frees++; mi_free(p); }
static void *observed_malloc(size_t n) { stock_file_allocations++; return malloc(n); }
static void *observed_calloc(size_t n,size_t z) { stock_file_allocations++; return calloc(n,z); }
static void observed_free(void *p) { stock_file_frees++; free(p); }
static void *retirement_target;
static unsigned retirement_failures, retirement_calls;
static int observed_mprotect(void *p,size_t n,int prot) {
    if(p==retirement_target && prot==PROT_NONE) {
        retirement_calls++;
        if(retirement_failures) { retirement_failures--; errno=EIO; return -1; }
    }
    return mprotect(p,n,prot);
}
#define mi_malloc observed_mi_malloc
#define mi_free observed_mi_free
#define malloc observed_malloc
#define calloc observed_calloc
#define free observed_free
#define mprotect observed_mprotect
#include OWNED_SOURCE
#undef mi_malloc
#undef mi_free
#undef malloc
#undef calloc
#undef free
#undef mprotect
#ifdef ACTQL_F_CALLER_CASES
#include FILESYSTEM_SOURCE
#endif

static const unsigned char recipe[32]={17};
static actql_owned_capacity *lease_new(void) {
    actql_owned_capacity *lease=NULL;
    size_t page=(size_t)sysconf(_SC_PAGESIZE);
    assert(actql_native_owned_acquire(64*page,1,recipe,&lease)==0);
    assert(actql_native_owned_transfer(lease,1,recipe)==0);
    return lease;
}
static actql_read_context *context_new(actql_owned_capacity *lease) {
    actql_read_context *context=NULL;
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_create(lease,&context)==0);
    assert(actql_native_owned_leave(lease)==0);
    return context;
}
static void context_enter(actql_owned_capacity *lease,actql_read_context *context) {
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_enter(context)==0);
}
static void context_leave(actql_owned_capacity *lease,actql_read_context *context) {
    assert(actql_read_context_leave(context)==0);
    assert(actql_native_owned_leave(lease)==0);
}
static void finish(actql_owned_capacity **lease,actql_read_context **context) {
    assert(actql_read_context_try_close(context)==0 && *context==NULL);
    assert(actql_native_owned_try_close(lease)==0 && *lease==NULL);
}
static bool child_status(pid_t child,int signal_number) {
    int status=0; assert(waitpid(child,&status,0)==child);
    return signal_number ? WIFSIGNALED(status)&&WTERMSIG(status)==signal_number
                         : WIFEXITED(status)&&WEXITSTATUS(status)==0;
}
static bool fork_stock(void) {
    void *inherited_mi=actql_native_moon_scoped_allocate(31);
    void *inherited_file=actql_native_file_scoped_allocate(31);
    /* This ordinary parent free fixes the old index origin PID. */
    void *probe=actql_native_moon_scoped_allocate(4);
    actql_native_moon_scoped_free(probe);
    pid_t child=fork(); assert(child>=0);
    if(child==0) {
        void *mi=actql_native_moon_scoped_allocate(37);
        void *file=actql_native_file_scoped_allocate(37);
        assert(mi && file);
        memset(mi,42,37); memset(file,43,37);
        actql_native_moon_scoped_free(mi);
        actql_native_file_scoped_free(file);
        actql_native_moon_scoped_free(inherited_mi);
        actql_native_file_scoped_free(inherited_file);
        _exit(0);
    }
    bool ok=child_status(child,0);
    actql_native_moon_scoped_free(inherited_mi);
    actql_native_file_scoped_free(inherited_file);
    return ok;
}
static bool managed_alias(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    moonbit_bytes_t bytes=moonbit_make_bytes_raw(9);
    memcpy(bytes,"original!",9); moonbit_incref(bytes);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    moonbit_decref(bytes);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    assert(memcmp(bytes,"original!",9)==0);
    moonbit_decref(bytes);
    finish(&lease,&context); return true;
}
static bool busy_cleanup(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    assert(!context->closing);
    assert(actql_native_owned_try_close(&lease)==ACTQL_OWNED_BUSY);
    assert(!lease->closing);
    context_enter(lease,context);
    void *diagnostic=actql_native_file_scoped_allocate(17);
    assert(diagnostic && actql_native_owned_contains_live_span(lease,diagnostic,17)==0);
    actql_native_file_scoped_free(diagnostic);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context); return true;
}
static bool nested_foreign_closing(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *a=context_new(lease),*b=context_new(lease);
    assert(actql_read_context_retain(a)==0 && actql_read_context_retain(b)==0);
    context_enter(lease,a);
    assert(actql_read_context_enter(a)==0);
    assert(actql_read_context_enter(b)==ACTQL_OWNED_INVALID);
    assert(read_current==a && read_depth==2);
    assert(actql_read_context_leave(a)==0);
    void *pointer=actql_native_file_scoped_allocate(5); assert(pointer);
    context_leave(lease,a);
    assert(actql_read_context_release_after_owner_ack(a)==0);
    assert(actql_read_context_try_close(&a)==ACTQL_OWNED_BUSY && a->closing);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_enter(a)==ACTQL_OWNED_INVALID);
    assert(actql_read_context_retain(a)==ACTQL_OWNED_INVALID);
    assert(actql_native_owned_leave(lease)==0);
    actql_native_file_scoped_free(pointer);
    assert(actql_read_context_try_close(&a)==0);
    assert(actql_read_context_release_after_owner_ack(b)==0);
    finish(&lease,&b); return true;
}
static bool exhausted_no_fallback(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    size_t mi=stock_mi_allocations,file=stock_file_allocations;
    assert(actql_native_file_scoped_allocate(lease->length)==NULL);
    assert(stock_mi_allocations==mi && stock_file_allocations==file);
    void *small=actql_native_file_scoped_allocate(3); assert(small);
    actql_native_file_scoped_free(small);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context); return true;
}
static bool retire_retry(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    void *pointer=actql_native_file_scoped_allocate(7); assert(pointer);
    retirement_target=pointer; retirement_calls=0; retirement_failures=1;
    actql_native_file_scoped_free(pointer);
    size_t index; assert(allocation_start(lease,pointer,&index));
    assert(lease->extents[index].retired && lease->extents[index].read_released);
    assert(retirement_calls==1);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context);
    assert(retirement_calls==2); retirement_target=NULL; return true;
}
static bool fork_arena(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    void *file=actql_native_file_scoped_allocate(4); assert(file);
    moonbit_bytes_t bytes=moonbit_make_bytes_raw(4); memcpy(bytes,"keep",4);
    context_leave(lease,context);
    pid_t child=fork(); assert(child>=0);
    if(child==0) { actql_native_file_scoped_free(file); _exit(90); }
    assert(child_status(child,SIGABRT));
    child=fork(); assert(child>=0);
    if(child==0) { moonbit_decref(bytes); _exit(91); }
    assert(child_status(child,SIGABRT));
    assert(memcmp(bytes,"keep",4)==0 && lease->read_context_count==1);
    moonbit_decref(bytes); actql_native_file_scoped_free(file);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context); return true;
}
static bool foreign_pid(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    pid_t child=fork(); assert(child>=0);
    if(child==0) {
        actql_read_context *same=context;
        assert(actql_read_context_enter(context)==ACTQL_OWNED_INVALID);
        assert(actql_read_context_release_after_owner_ack(context)==ACTQL_OWNED_INVALID);
        assert(actql_read_context_try_close(&same)==ACTQL_OWNED_INVALID && same==context);
        _exit(0);
    }
    assert(child_status(child,0));
    assert(context->users==1);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context); return true;
}
static bool context_retire_retry(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease),*same=context;
    retirement_target=context; retirement_calls=0; retirement_failures=1;
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(context==same && lease->read_context_count==1);
    assert(actql_native_owned_try_close(&lease)==ACTQL_OWNED_BUSY && !lease->closing);
    finish(&lease,&context);
    assert(retirement_calls==2); retirement_target=NULL; return true;
}
#ifdef ACTQL_F_CALLER_CASES
static bool real_reader(const char *directory) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0); /* Original caller frame use. */
    context_enter(lease,context);
    size_t length=strlen(directory); assert(length<4096);
    moonbit_bytes_t path=moonbit_make_bytes_raw((int32_t)length); memcpy(path,directory,length);
    actql_native_filesystem_root *root=NULL;
    assert(actql_native_filesystem_scoped_open_root(context,path,(int32_t)length,256,&root)==0);
    assert(root && root->fd>=0); moonbit_decref(path);
    moonbit_bytes_t name=moonbit_make_bytes_raw(6); memcpy(name,"sample",6);
    struct stat actual; assert(fstatat(root->fd,"sample",&actual,AT_SYMLINK_NOFOLLOW)==0);
    actql_native_filesystem_reader *reader=NULL;
    assert(actql_native_filesystem_scoped_open_reader(root,name,6,actual.st_dev,actual.st_ino,actual.st_size,&reader)==0);
    moonbit_decref(name); assert(reader && reader->ready);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    assert(actql_native_owned_enter(lease)==0);
    int32_t physical=-99;
    assert(actql_native_filesystem_scoped_reader_next(reader,32,&physical)==0 && physical==1);
    moonbit_bytes_t chunk=NULL;
    assert(actql_native_filesystem_scoped_reader_chunk(reader,&chunk)==0);
    assert(Moonbit_array_length(chunk)==11 && memcmp(chunk,"alpha\nbeta\n",11)==0);
    assert(actql_native_filesystem_scoped_reader_close(reader,false,&physical)==0 && physical==0);
    assert(actql_native_filesystem_scoped_root_close(root,&physical)==0 && physical==0);
    assert(actql_native_owned_leave(lease)==0);
    moonbit_decref(reader); moonbit_decref(root);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    assert(memcmp(chunk,"alpha\nbeta\n",11)==0); moonbit_decref(chunk);
    finish(&lease,&context); return true;
}
static bool real_failed_root(const char *directory) {
    char absent[4096]; assert(snprintf(absent,sizeof(absent),"%s/absent",directory)>0);
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    size_t length=strlen(absent);
    moonbit_bytes_t path=moonbit_make_bytes_raw((int32_t)length); memcpy(path,absent,length);
    actql_native_filesystem_root *root=NULL;
    assert(actql_native_filesystem_scoped_open_root(context,path,(int32_t)length,256,&root)==0);
    moonbit_decref(path); assert(root && root->fd<0);
    moonbit_bytes_t error=NULL;
    assert(actql_native_filesystem_scoped_root_error(root,&error)==0 && Moonbit_array_length(error)>0);
    int32_t physical=-99;
    assert(actql_native_filesystem_scoped_root_close(root,&physical)==0 && physical==0);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    moonbit_decref(root);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    moonbit_decref(error); finish(&lease,&context); return true;
}
#endif
int main(int argc,char **argv) {
    struct rlimit core={0,0}; assert(setrlimit(RLIMIT_CORE,&core)==0);
    setbuf(stdout,NULL);
    if(argc==2 && strcmp(argv[1],"--fork-stock-only")==0) {
        bool ok=fork_stock();
        printf("{\"case\":\"fork-stock\",\"ok\":%s}\n",ok?"true":"false");
        return ok?0:1;
    }
    assert(argc==2);
    bool (*tests[])(void)={fork_stock,managed_alias,busy_cleanup,nested_foreign_closing,
        exhausted_no_fallback,retire_retry,fork_arena,foreign_pid,context_retire_retry};
    const char *names[]={"fork-stock","managed-alias","same-owner-cleanup","nested-foreign-closing",
        "exhaustion-no-fallback","extent-retirement-retry","fork-arena-refusal","foreign-pid-refusal","context-retirement-retry"};
    unsigned executed=0;
    for(size_t i=0;i<sizeof(tests)/sizeof(tests[0]);i++) {
        bool ok=tests[i](); executed++;
        printf("{\"case\":\"%s\",\"ok\":%s}\n",names[i],ok?"true":"false");
        if(!ok) return 1;
    }
#ifdef ACTQL_F_CALLER_CASES
    assert(real_reader(argv[1])); executed++; puts("{\"case\":\"actual-F-reader-alias\",\"ok\":true}");
    assert(real_failed_root(argv[1])); executed++; puts("{\"case\":\"actual-F-failed-root-diagnostic\",\"ok\":true}");
#endif
    printf("{\"success\":true,\"discovered\":%u,\"executed\":%u,\"passed\":%u,\"failed\":0,\"public_e2e\":0}\n",executed,executed,executed);
    return 0;
}
