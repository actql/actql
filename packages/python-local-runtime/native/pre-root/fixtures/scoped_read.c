#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
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
static unsigned activation_mode, activation_failures;
static void *activation_target;
static size_t activation_bytes;
static bool observe_activation, activation_lost_ack;
static unsigned activation_calls, activation_failure_at;
static int observed_mprotect(void *p,size_t n,int prot) {
    if(activation_failures && prot==(PROT_READ|PROT_WRITE)) {
        activation_failures--; activation_target=p; activation_bytes=n;
        if(activation_mode==2) assert(mprotect(p,n,prot)==0);
        if(activation_mode==3) {
            size_t page=(size_t)sysconf(_SC_PAGESIZE);
            assert(n>page && mprotect(p,page,prot)==0);
        }
        errno=EIO; return -1;
    }

    if(observe_activation && prot==(PROT_READ|PROT_WRITE)) {
        activation_calls++;
        if(activation_failure_at && activation_calls==activation_failure_at) {
            if(activation_lost_ack) assert(mprotect(p,n,prot)==0);
            errno=EIO; return -1;
        }
    }
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
/* Test-only projection of this translation unit's same provider/TLS. It does
 * not adopt a Common pair, installed Host, resource profile or worker. */
actql_read_context *actql_bootstrap_current_read_context(void) {
    if(!lock_read_contexts()) return NULL;
    actql_read_context *context=read_current;
    bool current=known_read_context(context) && context->active!=0 &&
        read_depth!=0 && actql_native_owned_current()==context->lease;
    unlock_read_contexts();
    return current ? context : NULL;
}
#include FILESYSTEM_SOURCE
#endif

#ifdef ACTQL_READ_SEARCH_WORK
/* Compiler instrumentation observes actual successor traversals without a
 * clock, provider callback or allocation inside the observation. */
static bool observe_read_search;
static size_t read_search_successors;
static size_t read_search_pages;
void __attribute__((no_instrument_function))
__cyg_profile_func_enter(void *function,void *caller) {
    (void)caller;
    if(observe_read_search && function==(void *)read_heap_next)
        read_search_successors++;
    if(observe_read_search && function==(void *)allocate_read_heap_page_locked)
        read_search_pages++;
}
void __attribute__((no_instrument_function))
__cyg_profile_func_exit(void *function,void *caller) {
    (void)function; (void)caller;
}
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
/* Copied runtime values are not aliases into the explicitly owned Read arena.
 * A real native allocation still keeps that same arena BUSY. */
#if defined(ACTQL_RUNTIME_MANAGED_VALUES)
static bool runtime_managed_values(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    moonbit_bytes_t bytes=moonbit_make_bytes_raw(9);
    memcpy(bytes,"original!",9); moonbit_incref(bytes);
    moonbit_string_t text=moonbit_make_string_raw(3);
    text[0]=0x0041; text[1]=0x03bb; text[2]=0x4e2d;
    void *native=actql_native_file_scoped_allocate(37);
    assert(native && actql_native_owned_contains_live_span(lease,native,37)==0);
    memset(native,42,37);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    uint64_t values[16]={0};
    assert(actql_read_context_cleanup_snapshot(context,values,16)==0);
    assert(values[2]==1 && values[4]==0 && values[5]==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    assert(((unsigned char *)native)[36]==42);
    actql_native_file_scoped_free(native);
    finish(&lease,&context);
    assert(memcmp(bytes,"original!",9)==0 && text[1]==0x03bb && text[2]==0x4e2d);
    // Another actual arena can close while these independent copies remain.
    lease=lease_new(); context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    moonbit_bytes_t second=moonbit_make_bytes_raw(5);
    memcpy(second,"again",5);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context);
    assert(memcmp(second,"again",5)==0 && memcmp(bytes,"original!",9)==0);
    moonbit_decref(second); moonbit_decref(text);
    moonbit_decref(bytes); assert(memcmp(bytes,"original!",9)==0);
    moonbit_decref(bytes);
    return true;
}
#endif

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
/* The same active cleanup frame owns its result even after the final Root
 * user acknowledges close. No new entry or retained user is issued. */
static bool cleanup_result_after_last_user(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(context->users==0 && context->active==1 && !context->closing);
    moonbit_bytes_t result=moonbit_make_bytes_raw(12);
    memcpy(result,"cleanup-done",12);
    assert(actql_native_owned_contains_live_span(lease,result,12)==0);
    /* Retirement cannot overtake this same active scope or its result alias. */
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY && !context->closing);
    context_leave(lease,context);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_enter(context)==ACTQL_OWNED_INVALID);
    assert(actql_native_owned_leave(lease)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY && context->closing);
    assert(memcmp(result,"cleanup-done",12)==0);
    moonbit_decref(result);
    finish(&lease,&context); return true;
}
/* The failed close has already returned the final user. Its diagnostic
 * alias still owns the original context, so cleanup must not create a user. */
static bool alias_only_cleanup(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    moonbit_bytes_t diagnostic=moonbit_make_bytes_raw(9);
    memcpy(diagnostic,"original!",9);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY && context->closing);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_enter(context)==ACTQL_OWNED_INVALID);
#ifdef ACTQL_ALIAS_CLEANUP_ENTRY
    assert(actql_read_context_enter_cleanup(context)==0);
#else
    /* The original ABI used the normal entry for this SAME cleanup request. */
    assert(actql_read_context_enter(context)==0);
#endif
    assert(context->users==0 && context->active==1 && context->closing);
    assert(actql_read_context_retain(context)==ACTQL_OWNED_INVALID);
    assert(actql_read_context_enter(context)==ACTQL_OWNED_INVALID);
    moonbit_decref(diagnostic);
    moonbit_bytes_t result=moonbit_make_bytes_raw(12);
    memcpy(result,"cleanup-done",12);
    assert(actql_native_owned_contains_live_span(lease,result,12)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    context_leave(lease,context);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    moonbit_decref(result);
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
    /* Original Reader::next maps 0 to a chunk and 1 to GenerationMismatch. */
    assert(actql_native_filesystem_scoped_reader_next(reader,32,&physical)==0 && physical==0);
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

static bool real_child_root(const char *directory, bool missing) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    size_t length=strlen(directory);
    moonbit_bytes_t path=moonbit_make_bytes_raw((int32_t)length);
    memcpy(path,directory,length);
    actql_native_filesystem_root *parent=NULL,*child=NULL;
    assert(actql_native_filesystem_scoped_open_root(context,path,(int32_t)length,256,&parent)==0);
    moonbit_decref(path); assert(parent && parent->fd>=0);
    const char *component=missing?"absent":"child";
    int32_t count=(int32_t)strlen(component);
    moonbit_bytes_t name=moonbit_make_bytes_raw(count); memcpy(name,component,(size_t)count);
    assert(actql_native_filesystem_scoped_open_child_root(parent,name,count,&child)==0);
    moonbit_decref(name);
    assert(child && child->read_context==context && child->read_context_user);
    assert(context->users==3 && (missing ? child->fd<0 : child->fd>=0));
    int32_t physical=-99;
    assert(actql_native_filesystem_scoped_root_close(parent,&physical)==0 && physical==0);
    assert(context->users==2); // Parent ACK does not retire its child's use.
    moonbit_decref(parent);
    moonbit_bytes_t retained=NULL;
    if(missing) {
        assert(actql_native_filesystem_scoped_root_error(child,&retained)==0);
        assert(Moonbit_array_length(retained)>0);
    } else {
        struct stat actual; assert(fstatat(child->fd,"sample",&actual,AT_SYMLINK_NOFOLLOW)==0);
        name=moonbit_make_bytes_raw(6); memcpy(name,"sample",6);
        actql_native_filesystem_reader *reader=NULL;
        assert(actql_native_filesystem_scoped_open_reader(child,name,6,actual.st_dev,actual.st_ino,actual.st_size,&reader)==0);
        moonbit_decref(name);
        assert(reader->read_context==context && reader->read_context_user && reader->ready);
        assert(actql_native_filesystem_scoped_reader_next(reader,32,&physical)==0 && physical==0);
        assert(actql_native_filesystem_scoped_reader_chunk(reader,&retained)==0);
        assert(Moonbit_array_length(retained)==11 && memcmp(retained,"alpha\nbeta\n",11)==0);
        assert(actql_native_filesystem_scoped_reader_close(reader,false,&physical)==0 && physical==0);
        moonbit_decref(reader);
    }
    assert(actql_native_filesystem_scoped_root_close(child,&physical)==0 && physical==0);
    assert(context->users==1);
    assert(actql_native_filesystem_scoped_root_close(child,&physical)==0 && physical==0);
    assert(context->users==1); // Repeated ACK does not return another use.
    moonbit_decref(child);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    moonbit_decref(retained); finish(&lease,&context); return true;
}

static bool refused_child_root(const char *directory) {
    actql_owned_capacity *lease=lease_new(),*foreign=lease_new();
    actql_read_context *context=context_new(lease),*other=context_new(foreign);
    assert(actql_read_context_retain(context)==0);
    assert(actql_read_context_retain(other)==0);
    context_enter(lease,context);
    size_t length=strlen(directory);
    moonbit_bytes_t path=moonbit_make_bytes_raw((int32_t)length); memcpy(path,directory,length);
    moonbit_bytes_t name=moonbit_make_bytes_raw(5); memcpy(name,"child",5);
    actql_native_filesystem_root *parent=NULL,*output=NULL;
    assert(actql_native_filesystem_scoped_open_root(context,path,(int32_t)length,256,&parent)==0);
    moonbit_decref(path);
    context_leave(lease,context);
    context_enter(foreign,other);
    assert(actql_native_filesystem_scoped_open_child_root(parent,name,5,&output)==ACTQL_OWNED_INVALID);
    assert(output==NULL && context->users==2 && other->users==1);
    context_leave(foreign,other);
    context_enter(lease,context);
    int32_t physical=-99;
    assert(actql_native_filesystem_scoped_root_close(parent,&physical)==0 && physical==0);
    assert(actql_native_filesystem_scoped_open_child_root(parent,name,5,&output)==ACTQL_OWNED_INVALID);
    assert(output==NULL && context->users==1);
    moonbit_decref(name); moonbit_decref(parent);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_release_after_owner_ack(other)==0);
    finish(&lease,&context); finish(&foreign,&other); return true;
}

static bool real_private_root(const char *directory, const char *suffix, bool ready) {
    char selected[4096];
    int length=snprintf(selected,sizeof(selected),"%s%s",directory,suffix);
    assert(length>0 && (size_t)length<sizeof(selected));
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    moonbit_bytes_t path=moonbit_make_bytes_raw(length);
    memcpy(path,selected,(size_t)length);
    actql_filesystem_scoped_acquisition *result=
        actql_native_filesystem_acquire_current_private_root(path,length,256);
    moonbit_decref(path);
    assert(actql_native_filesystem_acquisition_status(result)==0);
    assert(actql_native_filesystem_acquisition_has_original(result));
    actql_native_filesystem_root *root=actql_native_filesystem_acquisition_root(result);
    moonbit_decref(result);
    assert(root->read_context==context && root->read_context_user);
    assert(context->users==2);
    assert(ready ? root->fd>=0 && root->error==NULL : root->fd<0 && root->error!=NULL);
    moonbit_bytes_t diagnostic=NULL;
    if(!ready) {
        assert(actql_native_filesystem_scoped_root_error(root,&diagnostic)==0);
        assert(Moonbit_array_length(diagnostic)>0);
    }
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(context->users==1);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    assert(actql_native_owned_enter(lease)==0);
    int32_t physical=-99;
    assert(actql_native_filesystem_scoped_root_close(root,&physical)==0 && physical==0);
    assert(context->users==0);
    assert(actql_native_filesystem_scoped_root_close(root,&physical)==0 && physical==0);
    assert(actql_native_owned_leave(lease)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    moonbit_decref(root);
    if(diagnostic!=NULL) {
        assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
        moonbit_decref(diagnostic);
    }
    finish(&lease,&context);
    return true;
}

static bool private_root_without_current(const char *directory) {
    size_t before_moon=stock_mi_allocations,before_file=stock_file_allocations;
    actql_native_filesystem_root *root=NULL;
    assert(actql_native_filesystem_scoped_open_current_private_root(
        (moonbit_bytes_t)directory,(int32_t)strlen(directory),256,&root)==ACTQL_OWNED_INVALID);
    assert(root==NULL && before_moon==stock_mi_allocations && before_file==stock_file_allocations);
    return true;
}
#endif
static bool allocation_failure_observation(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    size_t mi=stock_mi_allocations,file=stock_file_allocations;
    assert(actql_native_file_scoped_allocate(lease->length)==NULL);
    assert(read_allocation_observation.requested==lease->length);
    assert(read_allocation_observation.known==1 && read_allocation_observation.depth==1);
    assert(read_allocation_observation.active==1 && read_allocation_observation.current==1);
    assert(read_allocation_observation.status==ACTQL_OWNED_EXHAUSTED);
    assert(read_allocation_observation.occupied==lease->occupied_pages);
    assert(read_allocation_observation.control==lease->control_pages);
    assert(read_allocation_observation.pages==lease->page_count);
    assert(read_allocation_observation.page_bytes==lease->page_size);
    assert(read_allocation_observation.extent_domain==0);
    assert(read_allocation_observation.managed_prepared==0);
    assert(read_allocation_observation.managed_preparing==0);
    assert(read_allocation_observation.managed_remaining==0);
    assert(read_allocation_observation.managed_maximum==0);
    report_read_allocation_failure();
    assert(stock_mi_allocations==mi && stock_file_allocations==file);
    void *small=actql_native_file_scoped_allocate(3); assert(small);
    actql_native_file_scoped_free(small);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context);
    return true;
}

/* Same real cohort, distinct refusals before allocator invocation. Observing
 * either failure must neither consume an oversized request nor refill debt. */
static bool allocation_prepared_failure_observation(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_prepare_managed(context,64,1)==0);
    assert(actql_native_owned_leave(lease)==0);
    context_enter(lease,context);
    size_t occupied=lease->occupied_pages, stock=stock_mi_allocations;
    assert(allocate_read_bytes(65,READ_MANAGED)==NULL);
    assert(read_allocation_observation.status==ACTQL_OWNED_INVALID);
    assert(read_allocation_observation.extent_domain==0);
    assert(read_allocation_observation.managed_prepared==1);
    assert(read_allocation_observation.managed_preparing==0);
    assert(read_allocation_observation.managed_remaining==1);
    assert(read_allocation_observation.managed_maximum==64);
    report_read_allocation_failure();
    void *original=actql_native_moon_scoped_allocate(64);assert(original);
    assert(allocate_read_bytes(24,READ_MANAGED)==NULL);
    assert(read_allocation_observation.status==ACTQL_OWNED_INVALID);
    assert(read_allocation_observation.managed_prepared==1);
    assert(read_allocation_observation.managed_preparing==0);
    assert(read_allocation_observation.managed_remaining==0);
    assert(read_allocation_observation.managed_maximum==64);
    report_read_allocation_failure();
    assert(lease->occupied_pages==occupied && stock_mi_allocations==stock);
    actql_native_moon_scoped_free(original);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context);
    return true;
}

/* Domain/root roles are observed from actual distinct provider originals,
 * rather than guessed from equal page counts or forged context fields. */
static bool allocation_domain_failure_observation(void) {
    actql_owned_capacity *parent=lease_new(), *domain=NULL;
    size_t bytes=16*(size_t)sysconf(_SC_PAGESIZE);
    void *storage=NULL;
    actql_owned_extent_loan loan={0};actql_owned_extent_view view={0};
    assert(actql_native_owned_enter(parent)==0);
    assert(actql_native_owned_allocate_in_process_domain(parent,bytes,&storage)==0);
    assert(actql_native_owned_lend_in_process_domain(parent,storage,bytes,&loan)==0);
    assert(actql_native_owned_view_in_process_domain(&loan,&view)==0);
    assert(actql_native_owned_acquire_extent_domain(&view,&domain)==0);
    assert(actql_native_owned_transfer_original_domain(domain)==0);
    assert(actql_native_owned_leave(parent)==0);
    actql_read_context *context=context_new(domain);
    assert(actql_read_context_retain(context)==0);
    context_enter(domain,context);
    assert(actql_native_file_scoped_allocate(domain->length)==NULL);
    assert(read_allocation_observation.extent_domain==1);
    assert(read_allocation_observation.managed_prepared==0);
    assert(read_allocation_observation.managed_preparing==0);
    assert(read_allocation_observation.managed_remaining==0);
    assert(read_allocation_observation.managed_maximum==0);
    assert(read_allocation_observation.status==ACTQL_OWNED_EXHAUSTED);
    report_read_allocation_failure();
    context_leave(domain,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==0 && context==NULL);
    assert(actql_native_owned_close_extent_domain(&view,&domain)==0 && domain==NULL);
    assert(actql_native_owned_close_extent_view(&view)==0);
    assert(actql_native_owned_return_extent(&loan)==0);
    assert(actql_native_owned_retire(parent,storage)==0);
    assert(actql_native_owned_try_close(&parent)==0 && parent==NULL);
    return true;
}

/* Keep the original 64-page fixture. A real generic File prefix places the
 * managed page after other original extents, as in command preparation. LLVM
 * coverage observes the actual search work; no provider hook changes routing. */
static bool managed_search_workload(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    size_t stock=stock_mi_allocations;
    void *prefix=actql_native_file_scoped_allocate(12*lease->page_size);
    assert(prefix);
    void *values[128],*replacement[64];
    for(size_t i=0;i<128;i++) {
        values[i]=actql_native_moon_scoped_allocate(32);assert(values[i]);
        memset(values[i],(int)(i+1),32);
    }
    for(size_t i=0;i<128;i+=2) actql_native_moon_scoped_free(values[i]);
    for(size_t i=0;i<64;i++) {
        replacement[i]=actql_native_moon_scoped_allocate(32);assert(replacement[i]);
        for(size_t j=1;j<128;j+=2) assert(replacement[i]!=values[j]);
        memset(replacement[i],0x5a,32);
    }
    for(size_t i=1;i<128;i+=2) {
        assert(((unsigned char *)values[i])[31]==(unsigned char)(i+1));
        actql_native_moon_scoped_free(values[i]);
    }
    for(size_t i=0;i<64;i++) {
        assert(((unsigned char *)replacement[i])[31]==0x5a);
        actql_native_moon_scoped_free(replacement[i]);
    }
    /* A physically retired cached page must not become an allocation grant. */
    void *last=actql_native_moon_scoped_allocate(32);assert(last);
    assert(stock_mi_allocations==stock);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    actql_native_moon_scoped_free(last);
    actql_native_file_scoped_free(prefix);
    finish(&lease,&context);
    return true;
}

#ifdef ACTQL_READ_SEARCH_WORK
static bool managed_successor_search(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    void *values[128];
    size_t stock=stock_mi_allocations;
    read_search_successors=0; observe_read_search=true;
    for(size_t i=0;i<128;i++) {
        values[i]=actql_native_moon_scoped_allocate(32);assert(values[i]);
        memset(values[i],(int)(i+1),32);
    }
    observe_read_search=false;
    printf("{\"allocationCalls\":128,\"successorTraversals\":%zu}\n",read_search_successors);
    /* A retained live prefix must not be walked again for every allocation.
     * At a page boundary the full fallback remains admissible. */
    assert(read_search_successors<=2*128);
    for(size_t i=0;i<128;i++) {
        assert(((unsigned char *)values[i])[31]==(unsigned char)(i+1));
        actql_native_moon_scoped_free(values[i]);
    }
    assert(stock_mi_allocations==stock);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context);
    return true;
}

/* Retain a real multi-page prepared cohort, then naturally miss each full
 * page hint. Counts observe the original allocator, never a replacement. */
static bool managed_cohort_page_search(void) {
    const size_t calls=192;
    size_t page=(size_t)sysconf(_SC_PAGESIZE),bytes=page/8;
    actql_owned_capacity *lease=NULL;
    assert(actql_native_owned_acquire(256*page,1,recipe,&lease)==0);
    assert(actql_native_owned_transfer(lease,1,recipe)==0);
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_prepare_managed(context,bytes,calls)==0);
    uint64_t generation=context->managed_generation;
    assert(actql_native_owned_leave(lease)==0);
    context_enter(lease,context);
    void *values[192];
    size_t stock=stock_mi_allocations;
    size_t occupied=lease->occupied_pages;
    read_search_successors=0;read_search_pages=0;observe_read_search=true;
    for(size_t i=0;i<calls;i++) {
        values[i]=actql_native_moon_scoped_allocate(bytes);assert(values[i]);
        memset(values[i],(int)(i+1),bytes);
    }
    observe_read_search=false;
    printf("{\"allocationCalls\":%zu,\"pageProbes\":%zu,\"successorTraversals\":%zu}\n",
        calls,read_search_pages,read_search_successors);
    assert(context->managed_remaining==0 && lease->occupied_pages==occupied);
    assert(read_search_successors<=4*calls && read_search_pages<=4*calls);
    for(size_t i=0;i<calls;i++) {
        assert(((unsigned char *)values[i])[bytes-1]==(unsigned char)(i+1));
        actql_native_moon_scoped_free(values[i]);
    }
    assert(stock_mi_allocations==stock);
    context_leave(lease,context);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_finish_managed(context,generation)==0);
    assert(actql_native_owned_leave(lease)==0);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context);
    return true;
}

/* The circular fallback must still wrap to an earlier fitting original slab,
 * without acquiring a new one or hiding another context's live allocation. */
static bool managed_page_wrap_fallback(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    size_t bytes=lease->page_size/8;
    size_t slots=(lease->page_size-read_heap_round(sizeof(struct read_heap_page)))/
        (read_heap_round(bytes)+read_heap_header());
    size_t calls=8*slots;
    assert(slots>=3 && calls<=64);
    void *values[64];
    for(size_t i=0;i<calls;i++) {
        values[i]=actql_native_moon_scoped_allocate(bytes);assert(values[i]);
        memset(values[i],(int)(i+1),bytes);
    }
    size_t occupied=lease->occupied_pages,stock=stock_mi_allocations;
    actql_native_moon_scoped_free(values[0]);
    actql_native_moon_scoped_free(values[1]);
    actql_native_moon_scoped_free(values[calls-1]);
    void *merged=actql_native_moon_scoped_allocate(2*bytes);
    assert(merged==values[0] && lease->occupied_pages==occupied);
    memset(merged,0x6b,2*bytes);
    for(size_t i=2;i<calls-1;i++) {
        assert(((unsigned char *)values[i])[bytes-1]==(unsigned char)(i+1));
        actql_native_moon_scoped_free(values[i]);
    }
    assert(((unsigned char *)merged)[2*bytes-1]==0x6b);
    actql_native_moon_scoped_free(merged);
    assert(stock_mi_allocations==stock);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context);
    return true;
}
#endif

/* A too-small hinted free block must not hide a coalesced fitting original
 * block elsewhere on the same page. Fill the actual remaining tail first. */
static bool managed_block_fallback(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    void *values[8];
    for(size_t i=0;i<8;i++) {
        values[i]=actql_native_moon_scoped_allocate(32);assert(values[i]);
        memset(values[i],(int)(i+1),32);
    }
    size_t index=context->managed_page_hint;
    void *page=owned_page_address(lease,index);
    size_t page_bytes=owned_extent(lease,index)->pages*lease->page_size;
    struct read_heap_block *tail=read_heap_first(page),*next;
    while((next=read_heap_next(page,page_bytes,tail))) tail=next;
    assert(tail->requested==0);
    size_t tail_bytes=tail->capacity;
    void *fill=actql_native_private_scoped_allocate(tail_bytes);assert(fill);
    memset(fill,0x7a,tail_bytes);
    actql_native_moon_scoped_free(values[1]);
    actql_native_moon_scoped_free(values[2]);
    actql_native_moon_scoped_free(values[5]);
    void *merged=actql_native_moon_scoped_allocate(64);assert(merged==values[1]);
    memset(merged,0x6b,64);
    for(size_t i=0;i<8;i++) {
        if(i==1 || i==2 || i==5) continue;
        assert(((unsigned char *)values[i])[31]==(unsigned char)(i+1));
        actql_native_moon_scoped_free(values[i]);
    }
    assert(((unsigned char *)merged)[63]==0x6b);
    assert(((unsigned char *)fill)[tail_bytes-1]==0x7a);
    actql_native_moon_scoped_free(merged);
    assert(actql_native_private_scoped_free(fill)==0);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    finish(&lease,&context);
    return true;
}

static bool managed_search_fallback(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *a=context_new(lease),*b=context_new(lease);
    assert(actql_read_context_retain(a)==0 && actql_read_context_retain(b)==0);
    context_enter(lease,a);
    size_t stock=stock_mi_allocations,half=lease->page_size/2;
    void *large=actql_native_moon_scoped_allocate(half);assert(large);
    void *small=actql_native_moon_scoped_allocate(32);assert(small);
    memset(large,0x61,half);memset(small,0x62,32);
    /* The current page cannot satisfy another half-page block. It must keep
     * both live slots and acquire another original page rather than overlap. */
    void *other=actql_native_moon_scoped_allocate(half);assert(other);
    assert(other!=large && other!=small);memset(other,0x63,half);
    actql_native_moon_scoped_free(large);
    void *reused=actql_native_moon_scoped_allocate(half);assert(reused);
    memset(reused,0x64,half);
    assert(((unsigned char *)small)[31]==0x62);
    assert(((unsigned char *)other)[half-1]==0x63);
    context_leave(lease,a);
    context_enter(lease,b);
    void *foreign=actql_native_moon_scoped_allocate(32);assert(foreign);
    memset(foreign,0x65,32);
    /* Free follows a's original even while b is entered; b's allocations
     * cannot inherit a's remaining live slots or its page hint. */
    actql_native_moon_scoped_free(reused);
    void *second=actql_native_moon_scoped_allocate(half);assert(second);
    assert(second!=small && second!=other && second!=foreign);
    memset(second,0x66,half);
    assert(((unsigned char *)small)[31]==0x62 &&
        ((unsigned char *)other)[half-1]==0x63 &&
        ((unsigned char *)foreign)[31]==0x65);
    assert(actql_native_owned_contains_live_span(lease,small,32)==0);
    assert(actql_native_owned_contains_live_span(lease,foreign,33)==ACTQL_OWNED_INVALID);
    context_leave(lease,b);
    assert(actql_read_context_release_after_owner_ack(a)==0);
    assert(actql_read_context_release_after_owner_ack(b)==0);
    assert(actql_read_context_try_close(&a)==ACTQL_OWNED_BUSY);
    assert(actql_read_context_try_close(&b)==ACTQL_OWNED_BUSY);
    actql_native_moon_scoped_free(small);actql_native_moon_scoped_free(other);
    assert(actql_read_context_try_close(&a)==0 && a==NULL);
    assert(((unsigned char *)foreign)[31]==0x65 &&
        ((unsigned char *)second)[half-1]==0x66);
    actql_native_moon_scoped_free(foreign);actql_native_moon_scoped_free(second);
    assert(stock_mi_allocations==stock);
    finish(&lease,&b);
    return true;
}

static bool managed_subpages(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    size_t stock=stock_mi_allocations;
    void *values[1024];
    for(size_t i=0;i<1024;i++) {
        values[i]=actql_native_moon_scoped_allocate(32);
        assert(values[i] && (uintptr_t)values[i]%_Alignof(max_align_t)==0);
        memset(values[i],(int)(i%251),32);
        assert(actql_native_owned_contains_live_span(lease,values[i],32)==0);
        assert(actql_native_owned_contains_live_span(lease,values[i],33)==ACTQL_OWNED_INVALID);
    }
    size_t overhead=read_heap_round(sizeof(struct read_heap_page));
    size_t per_page=(lease->page_size-overhead)/(read_heap_header()+read_heap_round(32));
    assert(per_page>0);
    size_t expected_pages=(1024+per_page-1)/per_page;
    assert(stock==stock_mi_allocations &&
        lease->occupied_pages==lease->control_pages+1+expected_pages);
    void *page=(void *)((uintptr_t)values[0] & ~(lease->page_size-1));
    assert(actql_native_owned_protect(lease,page,0,lease->page_size,PROT_READ)==ACTQL_OWNED_INVALID);
    assert(actql_native_owned_retire(lease,page)==ACTQL_OWNED_INVALID);
    actql_owned_extent_loan loan={0};
    assert(actql_native_owned_lend_extent(lease,page,false,&loan)==ACTQL_OWNED_INVALID);
    actql_native_moon_scoped_free(values[0]);
    assert(actql_native_owned_contains_live_span(lease,values[0],1)==ACTQL_OWNED_INVALID);
    assert(release_read_bytes(values[0],true)==ACTQL_OWNED_INVALID);
    assert(release_read_bytes(values[1],false)==ACTQL_OWNED_INVALID);
    assert(release_read_bytes((unsigned char *)values[1]+1,true)==ACTQL_OWNED_INVALID);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    for(size_t i=1;i<1024;i++) {
        assert(((unsigned char *)values[i])[0]==i%251);
        actql_native_moon_scoped_free(values[i]);
    }
    finish(&lease,&context);return true;
}
static bool managed_page_retirement(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    void *value=actql_native_moon_scoped_allocate(31);
    retirement_target=(void *)((uintptr_t)value & ~(lease->page_size-1));
    retirement_failures=2; retirement_calls=0;
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    actql_native_moon_scoped_free(value);
    assert(retirement_calls==1 && retirement_failures==1);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_PHYSICAL_FAILURE && context);
    assert(retirement_calls==2 && retirement_failures==0);
    finish(&lease,&context); retirement_target=NULL;return true;
}
static bool managed_page_exhaustion(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    void *values[32769];size_t count=0,stock=stock_mi_allocations;
    while(count<32769 && (values[count]=allocate_read_bytes(32,true))!=NULL) count++;
    fprintf(stderr,"managed-exhaustion count=%zu occupied=%zu pages=%zu status=%d\n",count,lease->occupied_pages,lease->page_count,read_allocation_observation.status);
    assert(count>1024 && count<32769);
    assert(read_allocation_observation.status==ACTQL_OWNED_EXHAUSTED);
    assert(stock_mi_allocations==stock && lease->occupied_pages==lease->page_count);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    for(size_t i=0;i<count;i++) actql_native_moon_scoped_free(values[i]);
    finish(&lease,&context);return true;
}

static bool managed_original_provenance(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *a=context_new(lease),*b=context_new(lease);
    assert(actql_read_context_retain(a)==0 && actql_read_context_retain(b)==0);
    context_enter(lease,a);
    const size_t sizes[]={0,31,8192,8193};void *values[4];
    for(size_t i=0;i<4;i++) {
        values[i]=actql_native_moon_scoped_allocate(sizes[i]);
        assert(values[i] && actql_native_owned_contains_live_span(lease,values[i],sizes[i]?sizes[i]:1)==0);
    }
    context_leave(lease,a);
    assert(actql_read_context_release_after_owner_ack(a)==0);
    assert(actql_read_context_try_close(&a)==ACTQL_OWNED_BUSY);
    context_enter(lease,b);
    for(size_t i=0;i<4;i++) actql_native_moon_scoped_free(values[i]);
    assert(read_current==b && read_depth==1 && b->active==1);
    assert(actql_read_context_try_close(&a)==0 && a==NULL);
    /* The finite serial space cannot wrap or fall back into a generic page. */
    b->managed_serial=UINT64_MAX;
    size_t stock=stock_mi_allocations,occupied=lease->occupied_pages;
    assert(allocate_read_bytes(1,true)==NULL);
    assert(read_allocation_observation.status==ACTQL_OWNED_EXHAUSTED);
    assert(stock_mi_allocations==stock && lease->occupied_pages==occupied);
    context_leave(lease,b);
    assert(actql_read_context_release_after_owner_ack(b)==0);
    finish(&lease,&b);return true;
}

#if defined(__linux__) && defined(ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN)
static void linux_stock_originals(void) {
    void *plain=actql_native_file_scoped_allocate(37);
    unsigned char *zero=actql_native_file_scoped_callocate(7,9);
    assert(plain && zero && known_stock_file(plain) && known_stock_file(zero));
    assert((uintptr_t)plain % _Alignof(max_align_t)==0);
    assert((uintptr_t)zero % _Alignof(max_align_t)==0);
    for(size_t i=0;i<63;i++) assert(zero[i]==0);
    assert(actql_native_file_scoped_callocate(SIZE_MAX,2)==NULL);
    assert(!known_stock_file((unsigned char *)plain+1));
    int foreign=0;
    assert(release_stock_file(&foreign)==ACTQL_OWNED_INVALID);
    assert(release_stock_file((unsigned char *)plain+1)==ACTQL_OWNED_INVALID);
    actql_native_file_scoped_free(zero);
    assert(!known_stock_file(zero));
    assert(release_stock_file(zero)==ACTQL_OWNED_INVALID);
    pid_t child=fork(); assert(child>=0);
    if(child==0) { actql_native_file_scoped_free((unsigned char *)plain+1); _exit(94); }
    assert(child_status(child,SIGABRT) && known_stock_file(plain));
    actql_native_file_scoped_free(plain);
}
static void linux_stock_finite_slots(void) {
    void *held[ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS]={0};
    for(size_t i=0;i<ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS;i++) {
        held[i]=actql_native_file_scoped_allocate(1);
        assert(held[i]!=NULL);
    }
    size_t calls=stock_file_allocations;
    assert(actql_native_file_scoped_allocate(1)==NULL);
    assert(stock_file_allocations==calls); /* no extra allocation or fallback */
    for(size_t i=0;i<ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS;i++)
        actql_native_file_scoped_free(held[i]);
    void *again=actql_native_file_scoped_allocate(1);assert(again);
    actql_native_file_scoped_free(again);
}
struct linux_stock_competitor {
    void *original;
    void *allocated;
    int released;
    bool known;
};
static void *linux_stock_competing_call(void *raw) {
    struct linux_stock_competitor *result=raw;
    result->allocated=actql_native_file_scoped_allocate(7);
    result->released=release_stock_file(result->original);
    result->known=known_stock_file(result->original);
    return NULL;
}
static void linux_stock_concurrent_entry(void) {
    void *original=actql_native_file_scoped_allocate(29);assert(original);
    memset(original,71,29);
    struct linux_stock_competitor result={original,NULL,99,true};
    size_t allocations=stock_file_allocations,frees=stock_file_frees;
    assert(enter_stock_files());
    pthread_t thread;
    assert(pthread_create(&thread,NULL,linux_stock_competing_call,&result)==0);
    assert(pthread_join(thread,NULL)==0);
    assert(result.allocated==NULL && result.released==ACTQL_OWNED_BUSY && !result.known);
    assert(stock_file_allocations==allocations && stock_file_frees==frees);
    for(size_t i=0;i<29;i++) assert(((unsigned char *)original)[i]==71);
    leave_stock_files();
    assert(known_stock_file(original));
    actql_native_file_scoped_free(original);
    assert(!known_stock_file(original));
}
static void linux_stock_entry_snapshot(void) {
    void *plain=actql_native_file_scoped_allocate(19);assert(plain);
    assert(enter_stock_files());
    assert(actql_native_file_scoped_allocate(1)==NULL);
    assert(release_stock_file(plain)==ACTQL_OWNED_BUSY);
    /* A fork during this entry is unsupported; it must refuse immediately,
     * never acquire an inherited lock or traverse a changing metadata table. */
    pid_t child=fork();assert(child>=0);
    if(child==0) {
        assert(!known_stock_file(plain));
        assert(actql_native_file_scoped_allocate(1)==NULL);
        assert(release_stock_file(plain)==ACTQL_OWNED_BUSY);
        _exit(0);
    }
    assert(child_status(child,0));
    leave_stock_files();
    assert(known_stock_file(plain));
    actql_native_file_scoped_free(plain);
}
#endif

struct cleanup_snapshot_thread_case {
    actql_read_context *context;
    int status;
    uint64_t output[16];
};
static void *foreign_cleanup_snapshot(void *opaque) {
    struct cleanup_snapshot_thread_case *value=opaque;
    value->status=actql_read_context_cleanup_snapshot(value->context,value->output,16);
    return NULL;
}
static bool cleanup_snapshot_original(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    uint64_t values[16]={0};
    assert(actql_read_context_cleanup_snapshot((actql_read_context *)(uintptr_t)1,values,16)==ACTQL_OWNED_INVALID);
    assert(actql_read_context_cleanup_snapshot(context,values,15)==ACTQL_OWNED_INVALID);
    values[4]=1;
    assert(actql_read_context_cleanup_snapshot(context,values,16)==ACTQL_OWNED_INVALID && values[4]==1);
    memset(values,0,sizeof(values));
    struct cleanup_snapshot_thread_case foreign={.context=context};
    pthread_t thread;
    assert(pthread_create(&thread,NULL,foreign_cleanup_snapshot,&foreign)==0);
    assert(pthread_join(thread,NULL)==0 && foreign.status==ACTQL_OWNED_INVALID);
    for(size_t i=0;i<16;i++) assert(foreign.output[i]==0);
    pid_t child=fork(); assert(child>=0);
    if(child==0) {
        uint64_t inherited[16]={0};
        _exit(actql_read_context_cleanup_snapshot(context,inherited,16)==ACTQL_OWNED_INVALID ? 0 : 1);
    }
    assert(child_status(child,0));
    context_enter(lease,context);
    void *generic=actql_native_file_scoped_allocate(9);
    unsigned char *small=actql_native_moon_scoped_allocate(17);
    unsigned char *large=actql_native_moon_scoped_allocate(83);
    assert(generic && small && large);
    memset(small,41,17); memset(large,42,83);
    assert(actql_read_context_cleanup_snapshot(context,values,16)==0);
    assert(values[0]==1 && values[1]==1 && values[2]==1 && values[3]==1);
    assert(values[4]==1 && values[5]==2 && values[6]==100 && values[7]>=100);
    assert(values[10]==17 && values[11]==83 && values[13]==1 && values[14]==1);
    assert(values[15]==sizeof(actql_read_context) && small[16]==41 && large[82]==42);
    context_leave(lease,context);
    memset(values,0,sizeof(values));
    assert(actql_read_context_cleanup_snapshot(context,values,16)==0);
    assert(values[0]==1 && values[1]==0 && values[12]==0 && values[13]==0 && values[14]==0);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    actql_native_file_scoped_free(generic);
    actql_native_moon_scoped_free(small);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    memset(values,0,sizeof(values));
    assert(actql_read_context_cleanup_snapshot(context,values,16)==0);
    assert(values[0]==0 && values[1]==0 && values[2]==0 && values[5]==1 && values[6]==83);
    assert(values[10]==83 && values[11]==83 && values[12]==1 && large[82]==42);
    size_t page=((uintptr_t)large-(uintptr_t)lease)/lease->page_size;
    retirement_target=(unsigned char *)lease+page*lease->page_size;
    retirement_failures=1;
    actql_native_moon_scoped_free(large);
    memset(values,0,sizeof(values));
    assert(actql_read_context_cleanup_snapshot(context,values,16)==0);
    assert(values[4]==0 && values[5]==0 && values[6]==0 && values[8]>=1 && values[9]>=1);
    // Empty live counts/pending metadata still acknowledge no parent close.
    assert(context!=NULL && actql_native_owned_try_close(&lease)==ACTQL_OWNED_BUSY);
    retirement_target=NULL; retirement_failures=0;
    actql_read_context *stale=context;
    assert(actql_read_context_try_close(&context)==0 && context==NULL);
    memset(values,0,sizeof(values));
    assert(actql_read_context_cleanup_snapshot(stale,values,16)==ACTQL_OWNED_INVALID);
    assert(actql_native_owned_try_close(&lease)==0 && lease==NULL);
    return true;
}

/* Real page activation and retirement failures, not a simulated Common ACK.
 * This closed C constructor cohort uses the same allocator and extent table. */
static void managed_prepared_cohort(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    size_t occupied=lease->occupied_pages;
    assert(actql_read_context_prepare_managed(context,400,3)==ACTQL_OWNED_INVALID);
    assert(lease->occupied_pages==occupied && !context->managed_prepared);
    assert(actql_native_owned_enter(lease)==0);
    observe_activation=true; activation_calls=activation_failure_at=0;
    assert(actql_read_context_prepare_managed(context,400,3)==0);
    assert(activation_calls==3 && lease->occupied_pages==occupied+3);
    assert(context->managed_remaining==3 && !context->managed_preparing);
    assert(actql_native_owned_leave(lease)==0);
    size_t stock=stock_mi_allocations;
    context_enter(lease,context);
    assert(actql_read_context_prepare_managed(context,400,1)==ACTQL_OWNED_INVALID);
    assert(context->managed_remaining==3);
    void *old=actql_native_moon_scoped_allocate(400); assert(old);
    size_t logical; assert(owned_pointer_offset(lease,old,&logical));
    retirement_target=owned_page_address(lease,logical/lease->page_size);
    retirement_failures=1; retirement_calls=0;
    actql_native_moon_scoped_free(old);
    // Empty prepared slabs stay owned and reusable until scalar cohort finish.
    assert(retirement_calls==0 && retirement_failures==1);
    void *a=actql_native_moon_scoped_allocate(400); assert(a==old);
    void *b=actql_native_moon_scoped_allocate(64); assert(b);
    assert(context->managed_remaining==0 && activation_calls==3);
    /* Probe the fallible internal port only: a certificate violation must not
     * activate another page or silently allocate from the stock runtime. */
    assert(allocate_read_bytes(1,READ_MANAGED)==NULL);
    assert(activation_calls==3 && stock_mi_allocations==stock);
    context_leave(lease,context);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_prepare_managed(context,400,1)==0);
    assert(activation_calls==4 && context->managed_remaining==1);
    assert(actql_native_owned_leave(lease)==0);
    context_enter(lease,context);
    void *c=actql_native_moon_scoped_allocate(400); assert(c);
    memset(a,11,400); memset(b,12,64); memset(c,13,400);
    assert(activation_calls==4);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    assert(((unsigned char *)a)[0]==11 && ((unsigned char *)c)[0]==13);
    actql_native_moon_scoped_free(a); actql_native_moon_scoped_free(b);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    actql_native_moon_scoped_free(c);
    retirement_target=NULL; observe_activation=false;
    finish(&lease,&context);
}

static void managed_prepared_partial(bool lost_ack) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    assert(actql_native_owned_enter(lease)==0);
    size_t occupied=lease->occupied_pages;
    observe_activation=true; activation_calls=0; activation_failure_at=2;
    activation_lost_ack=lost_ack;
    assert(actql_read_context_prepare_managed(context,400,3)==ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(activation_calls==2 && lease->occupied_pages==occupied+2);
    assert(context->managed_preparing && context->managed_remaining==0);
    assert(actql_read_context_enter(context)==ACTQL_OWNED_INVALID);
    assert(actql_read_context_prepare_managed(context,400,3)==ACTQL_OWNED_INVALID);
    assert(activation_calls==2);
    assert(actql_native_owned_leave(lease)==0);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    for(size_t i=lease->control_pages;i<lease->page_count;i++) {
        if(owned_extent(lease,i)->read_context==context && owned_extent(lease,i)->retired) {
            assert(owned_extent(lease,i)->read_heap && owned_extent(lease,i)->read_released);
            retirement_target=owned_page_address(lease,i);
        }
    }
    assert(retirement_target);
    retirement_failures=1; retirement_calls=0;
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(context && retirement_calls==1 && lease->occupied_pages==occupied+1);
    assert(actql_native_owned_try_close(&lease)==ACTQL_OWNED_BUSY);
    retirement_target=NULL; observe_activation=false; activation_failure_at=0;
    activation_lost_ack=false;
    finish(&lease,&context);
}

static void managed_prepared_failed_extension(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_prepare_managed(context,400,1)==0);
    assert(actql_native_owned_leave(lease)==0);
    context_enter(lease,context);
    unsigned char *old=actql_native_moon_scoped_allocate(400); assert(old);
    memset(old,47,400);
    context_leave(lease,context);
    uint64_t serial=context->managed_serial;
    assert(actql_native_owned_enter(lease)==0);
    observe_activation=true; activation_calls=0; activation_failure_at=2;
    activation_lost_ack=true;
    assert(actql_read_context_prepare_managed(context,400,2)==ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(context->managed_preparing && context->managed_remaining==0);
    assert(context->managed_serial==serial && old[399]==47);
    assert(actql_read_context_enter(context)==ACTQL_OWNED_INVALID);
    assert(actql_native_owned_leave(lease)==0);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    // Original-provenance release remains available without re-entry or TLS swap.
    actql_native_moon_scoped_free(old);
    observe_activation=false; activation_failure_at=0; activation_lost_ack=false;
    finish(&lease,&context);
}

static void managed_prepared_unused(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    assert(actql_native_owned_enter(lease)==0);
    size_t occupied=lease->occupied_pages;
    assert(actql_read_context_prepare_managed(context,lease->page_size/2+1,1)==ACTQL_OWNED_INVALID);
    assert(lease->occupied_pages==occupied && !context->managed_prepared);
    assert(actql_read_context_prepare_managed(context,400,3)==0);
    assert(lease->occupied_pages==occupied+3);
    assert(actql_native_owned_leave(lease)==0);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    /* Cancellation before any constructor still retires every prepared page. */
    finish(&lease,&context);
}

/* Repeated exact transitions reuse the same owner, while every older live
 * alias and any failed retirement remain charged. No count is a lifetime cap. */
static void managed_cohort_finish_repeats(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    assert(actql_read_context_finish_managed(context,context->managed_generation)==ACTQL_OWNED_INVALID);
    assert(actql_native_owned_enter(lease)==0);
    size_t baseline=lease->occupied_pages, request=lease->page_size/2;
    assert(actql_read_context_prepare_managed(context,request,2)==0);
    assert(actql_native_owned_leave(lease)==0);
    context_enter(lease,context);
    unsigned char *old=actql_native_moon_scoped_allocate(request); assert(old);
    memset(old,71,request);
    void *fresh=actql_native_moon_scoped_allocate(request); assert(fresh);
    size_t offset; assert(owned_pointer_offset(lease,fresh,&offset));
    retirement_target=owned_page_address(lease,offset/lease->page_size);
    retirement_failures=1; retirement_calls=0;
    actql_native_moon_scoped_free(fresh);
    assert(retirement_calls==0 && lease->occupied_pages==baseline+2);
    assert(actql_read_context_finish_managed(context,context->managed_generation)==ACTQL_OWNED_INVALID);
    assert(context->managed_cohort && !context->managed_finishing);
    context_leave(lease,context);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_finish_managed(context,context->managed_generation)==ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(context->managed_finishing && !context->managed_cohort);
    assert(context->managed_remaining==0 && context->managed_serial==2);
    assert(old[request-1]==71 && lease->occupied_pages==baseline+2);
    assert(actql_read_context_prepare_managed(context,request,1)==ACTQL_OWNED_INVALID);
    assert(actql_read_context_enter(context)==ACTQL_OWNED_INVALID);
    assert(actql_read_context_finish_managed(context,context->managed_generation)==0);
    assert(!context->managed_finishing && lease->occupied_pages==baseline+1);
    assert(actql_read_context_finish_managed(context,context->managed_generation)==0);
    assert(actql_read_context_enter(context)==ACTQL_OWNED_INVALID);
    retirement_target=NULL;
    for(unsigned round=0;round<6;round++) {
        uint64_t previous=context->managed_generation;
        assert(actql_read_context_prepare_managed(context,request,1)==0);
        assert(context->managed_generation==previous+1);
        assert(actql_read_context_finish_managed(context,previous)==ACTQL_OWNED_INVALID);
        assert(context->managed_cohort && context->managed_remaining==1);
        assert(actql_native_owned_leave(lease)==0);
        context_enter(lease,context);
        void *next=actql_native_moon_scoped_allocate(request); assert(next && next!=old);
        assert(lease->occupied_pages==baseline+2 && old[request-1]==71);
        actql_native_moon_scoped_free(next);
        context_leave(lease,context);
        assert(actql_native_owned_enter(lease)==0);
        assert(actql_read_context_finish_managed(context,context->managed_generation)==0);
        assert(lease->occupied_pages==baseline+1 && context->managed_serial==3+round);
    }
    assert(actql_native_owned_leave(lease)==0);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    actql_native_moon_scoped_free(old);
    finish(&lease,&context);
}

static void managed_cohort_finish_partial(void) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    assert(actql_native_owned_enter(lease)==0);
    size_t baseline=lease->occupied_pages;
    assert(actql_read_context_prepare_managed(context,400,1)==0);
    assert(actql_native_owned_leave(lease)==0);
    context_enter(lease,context);
    unsigned char *old=actql_native_moon_scoped_allocate(400); assert(old);
    memset(old,83,400);
    context_leave(lease,context);
    assert(actql_native_owned_enter(lease)==0);
    observe_activation=true; activation_calls=0; activation_failure_at=2;
    activation_lost_ack=true;
    assert(actql_read_context_prepare_managed(context,400,2)==ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(context->managed_preparing && context->managed_serial==1);
    for(size_t i=lease->control_pages;i<lease->page_count;i++) {
        if(owned_extent(lease,i)->read_context==context && owned_extent(lease,i)->retired)
            retirement_target=owned_page_address(lease,i);
    }
    assert(retirement_target);
    retirement_failures=1; retirement_calls=0;
    assert(actql_read_context_finish_managed(context,context->managed_generation)==ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(context->managed_preparing && context->managed_finishing);
    assert(context->managed_remaining==0 && old[399]==83);
    assert(actql_read_context_prepare_managed(context,400,1)==ACTQL_OWNED_INVALID);
    assert(actql_read_context_finish_managed(context,context->managed_generation)==0);
    assert(lease->occupied_pages==baseline+1 && old[399]==83);
    retirement_target=NULL; observe_activation=false;
    activation_failure_at=0; activation_lost_ack=false;
    assert(actql_read_context_prepare_managed(context,400,1)==0);
    assert(actql_native_owned_leave(lease)==0);
    context_enter(lease,context);
    void *next=actql_native_moon_scoped_allocate(400); assert(next);
    actql_native_moon_scoped_free(next);
    context_leave(lease,context);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_finish_managed(context,context->managed_generation)==0);
    assert(lease->occupied_pages==baseline+1 && context->managed_serial==2);
    assert(actql_native_owned_leave(lease)==0);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    actql_native_moon_scoped_free(old);
    finish(&lease,&context);
}

static void managed_cohort_finish_scope_refusal(void) {
    actql_owned_capacity *lease=lease_new(), *foreign=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_prepare_managed(context,400,2)==0);
    uint64_t generation=context->managed_generation;
    size_t occupied=lease->occupied_pages;
    assert(actql_native_owned_leave(lease)==0);
    assert(actql_native_owned_enter(foreign)==0);
    assert(actql_read_context_finish_managed(context,generation)==ACTQL_OWNED_INVALID);
    assert(context->managed_remaining==2 && !context->managed_finishing);
    assert(lease->occupied_pages==occupied);
    assert(actql_native_owned_leave(foreign)==0);
    assert(actql_native_owned_try_close(&foreign)==0);
    context_enter(lease,context);
    void *old=actql_native_moon_scoped_allocate(400); assert(old);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    assert(context->closing && context->managed_remaining==1);
    assert(actql_native_owned_enter(lease)==0);
    assert(actql_read_context_finish_managed(context,generation)==ACTQL_OWNED_INVALID);
    assert(context->managed_remaining==1 && !context->managed_finishing);
    assert(actql_native_owned_leave(lease)==0);
    actql_native_moon_scoped_free(old);
    finish(&lease,&context);
}

/* Fallible private C consumers use the ordinary current Read, not a prepared
 * constructor cohort. Failed, lost and partially completed physical activation
 * all retain the same extent until its actual protection ACK. */
static void read_activation_failure(unsigned mode) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    size_t occupied=lease->occupied_pages, stock=stock_mi_allocations;
    uint64_t serial=context->managed_serial;
    activation_mode=mode; activation_failures=1; activation_target=NULL;
    size_t bytes=mode==3 ? lease->page_size+64 : 64;
    assert(actql_native_private_scoped_allocate(bytes)==NULL);
    assert(activation_target && activation_failures==0);
    size_t pages=mode==3 ? 2 : 1;
    assert(activation_bytes==pages*lease->page_size);
    assert(lease->occupied_pages==occupied+pages && context->managed_serial==serial);
    size_t offset; assert(owned_pointer_offset(lease,activation_target,&offset));
    struct extent *pending=owned_extent(lease,offset/lease->page_size);
    assert(pending->pages==pages && pending->read_context==context);
    assert(pending->retired && pending->read_released && pending->read_heap);
    assert(actql_native_owned_contains_live_span(lease,activation_target,1)==ACTQL_OWNED_INVALID);
    assert(actql_native_private_scoped_contains_allocation(context,lease,
        activation_target,1)==ACTQL_OWNED_INVALID);
    uint64_t snapshot[16]={0};
    assert(actql_read_context_cleanup_snapshot(context,snapshot,16)==0);
    assert(snapshot[8]==1 && snapshot[9]==pages);
    unsigned char *live=actql_native_private_scoped_allocate(64); assert(live);
    size_t live_offset; assert(owned_pointer_offset(lease,live,&live_offset));
    assert(live_offset/lease->page_size!=offset/lease->page_size);
    memset(live,53,64);
    assert(stock_mi_allocations==stock && context->managed_serial==serial+1);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    retirement_target=activation_target; retirement_failures=1; retirement_calls=0;
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(context && retirement_calls==1 && lease->occupied_pages==occupied+pages+1);
    assert(actql_native_owned_try_close(&lease)==ACTQL_OWNED_BUSY);
    retirement_target=NULL;
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    assert(lease->occupied_pages==occupied+1 && live[63]==53);
    assert(actql_native_private_scoped_free(live)==0);
    activation_mode=0; activation_target=NULL;
    finish(&lease,&context);
}

/* Large managed and File values bypass the subpage heap. Their failures
 * still belong to this exact Read before the first protection syscall. */
static void read_raw_activation_failure(unsigned mode, bool managed) {
    actql_owned_capacity *lease=lease_new();
    actql_read_context *context=context_new(lease);
    assert(actql_read_context_retain(context)==0);
    context_enter(lease,context);
    size_t occupied=lease->occupied_pages;
    size_t mi=stock_mi_allocations,file=stock_file_allocations;
    size_t bytes=2*lease->page_size+1, pages=3;
    uint64_t serial=context->managed_serial;
    activation_mode=mode; activation_failures=1; activation_target=NULL;
    /* The managed public wrapper is fail-stop after this same fallible call.
     * Test its NULL outcome here without replacing the allocator or its scope. */
    void *failed=managed ? allocate_read_bytes(bytes,READ_MANAGED)
                         : actql_native_file_scoped_allocate(bytes);
    assert(failed==NULL && activation_target && activation_failures==0);
    assert(read_allocation_observation.status==ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(activation_bytes==pages*lease->page_size);
    assert(lease->occupied_pages==occupied+pages && context->managed_serial==serial);
    size_t offset; assert(owned_pointer_offset(lease,activation_target,&offset));
    struct extent *pending=owned_extent(lease,offset/lease->page_size);
    assert(pending->pages==pages && pending->read_context==context);
    assert(pending->retired && pending->read_released && !pending->read_heap);
    assert(actql_native_owned_contains_live_span(lease,activation_target,1)==ACTQL_OWNED_INVALID);
    uint64_t snapshot[16]={0};
    assert(actql_read_context_cleanup_snapshot(context,snapshot,16)==0);
    assert(snapshot[8]==1 && snapshot[9]==pages && snapshot[2]==0);
    unsigned char *live=managed ? actql_native_moon_scoped_allocate(bytes)
                                : actql_native_file_scoped_allocate(bytes);
    assert(live && live!=activation_target);
    memset(live,67,bytes);
    size_t live_offset; assert(owned_pointer_offset(lease,live,&live_offset));
    struct extent *live_extent=owned_extent(lease,live_offset/lease->page_size);
    assert(live_extent->read_context==context && !live_extent->read_heap &&
        !live_extent->retired && !live_extent->read_released);
    assert(stock_mi_allocations==mi && stock_file_allocations==file);
    context_leave(lease,context);
    assert(actql_read_context_release_after_owner_ack(context)==0);
    retirement_target=activation_target; retirement_failures=1; retirement_calls=0;
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_PHYSICAL_FAILURE);
    assert(context && retirement_calls==1 && lease->occupied_pages==occupied+2*pages);
    assert(pending->read_context==context && pending->retired && pending->read_released);
    assert(actql_native_owned_try_close(&lease)==ACTQL_OWNED_BUSY);
    assert(actql_read_context_try_close(&context)==ACTQL_OWNED_BUSY);
    assert(retirement_calls==2 && lease->occupied_pages==occupied+pages);
    assert(live[bytes-1]==67);
    if(managed) actql_native_moon_scoped_free(live);
    else actql_native_file_scoped_free(live);
    retirement_target=NULL; activation_mode=0; activation_target=NULL;
    finish(&lease,&context);
}

int main(int argc,char **argv) {
    struct rlimit core={0,0}; assert(setrlimit(RLIMIT_CORE,&core)==0);
    setbuf(stdout,NULL);
#ifdef ACTQL_READ_SEARCH_WORK
    if(argc==2 && strcmp(argv[1],"--managed-page-wrap-fallback-only")==0) {
        assert(managed_page_wrap_fallback());
        puts("{\"case\":\"same-original-page-wrap-fallback\",\"passed\":1,\"failed\":0}");
        return 0;
    }
    if(argc==2 && strcmp(argv[1],"--managed-cohort-page-search-only")==0) {
        assert(managed_cohort_page_search());
        puts("{\"case\":\"same-original-cohort-page-search\",\"passed\":1,\"failed\":0}");
        return 0;
    }
    if(argc==2 && strcmp(argv[1],"--managed-successor-search-only")==0) {
        assert(managed_successor_search());
        puts("{\"case\":\"same-original-successor-search\",\"passed\":1,\"failed\":0}");
        return 0;
    }
#endif
    if(argc==2 && strcmp(argv[1],"--read-raw-activation-only")==0) {
        for(unsigned mode=1;mode<=3;mode++) {
            read_raw_activation_failure(mode,false);
            read_raw_activation_failure(mode,true);
        }
        puts("{\"case\":\"raw-read-activation-custody\",\"passed\":6,\"failed\":0}");
        return 0;
    }
    if(argc==2 && strcmp(argv[1],"--read-activation-only")==0) {
        read_activation_failure(1); read_activation_failure(2); read_activation_failure(3);
        puts("{\"case\":\"ordinary-read-activation-custody\",\"passed\":3,\"failed\":0}");
        return 0;
    }

    if(argc==2 && strcmp(argv[1],"--managed-prepared-only")==0) {
        managed_prepared_cohort(); managed_prepared_partial(false);
        managed_prepared_partial(true); managed_prepared_failed_extension();
        managed_prepared_unused();
        managed_cohort_finish_repeats(); managed_cohort_finish_partial();
        managed_cohort_finish_scope_refusal();
        puts("{\"case\":\"same-original-managed-preactivation\",\"passed\":8,\"failed\":0}");
        return 0;
    }
#if defined(ACTQL_RUNTIME_MANAGED_VALUES)
    if(argc==2 && strcmp(argv[1],"--runtime-managed-values-only")==0) {
        assert(runtime_managed_values());
        puts("{\"case\":\"runtime-copies-and-original-native-alias\",\"passed\":1,\"failed\":0}");
        return 0;
    }
#else
    if(argc==2 && strcmp(argv[1],"--scoped-managed-alias-only")==0) {
        assert(managed_alias());
        puts("{\"case\":\"scoped-managed-alias\",\"passed\":1,\"failed\":0}");
        return 0;
    }
#endif
    if(argc==2 && strcmp(argv[1],"--cleanup-snapshot-only")==0) {
        assert(cleanup_snapshot_original());
        printf("{\"case\":\"same-original-cleanup-snapshot\",\"passed\":1,\"failed\":0,"
               "\"contextPayloadBytes\":%zu,\"objectHeaderBytes\":%zu,\"utf16UnitBytes\":%zu,"
               "\"utf16SentinelBytes\":%zu,\"valueArrayHeaderBytes\":%zu,\"pointerBytes\":%zu}\n",
            sizeof(actql_read_context),sizeof(struct moonbit_object),sizeof(uint16_t),
            sizeof(uint16_t),sizeof(struct moonbit_valtype_array_header),sizeof(void *));
        return 0;
    }
#if defined(__linux__) && defined(ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN)
    if(argc==2 && strcmp(argv[1],"--linux-stock-concurrency-only")==0) {
        linux_stock_concurrent_entry();
        puts("{\"case\":\"linux-stock-concurrency\",\"passed\":1,\"failed\":0}");
        return 0;
    }
    if(argc==2 && strcmp(argv[1],"--linux-stock-provenance-only")==0) {
        linux_stock_originals();
        linux_stock_finite_slots();
        linux_stock_entry_snapshot();
        assert(fork_stock());
        puts("{\"case\":\"linux-stock-provenance\",\"passed\":4,\"failed\":0}");
        printf("{\"recordBytes\":%zu,\"recordAlignment\":%zu,\"slots\":%d,"
               "\"tableBytes\":%zu,\"entryBytes\":%zu,\"normalProfile\":null}\n",
            sizeof(struct stock_file_record),_Alignof(struct stock_file_record),
            ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS,sizeof(stock_files),sizeof(stock_file_entry));
        return 0;
    }
#endif
    if(argc==2 && strcmp(argv[1],"--fork-stock-only")==0) {
        bool ok=fork_stock();
        printf("{\"case\":\"fork-stock\",\"ok\":%s}\n",ok?"true":"false");
        return ok?0:1;
    }
    if(argc==2 && strcmp(argv[1],"--allocation-diagnostic-only")==0) {
        bool ok=allocation_failure_observation();
        puts("{\"case\":\"same-original-allocation-failure-observation\",\"passed\":1,\"failed\":0}");
        return ok?0:1;
    }
    if(argc==2 && strcmp(argv[1],"--allocation-context-diagnostic-only")==0) {
        assert(allocation_failure_observation());
        assert(allocation_prepared_failure_observation());
        assert(allocation_domain_failure_observation());
        puts("{\"case\":\"allocation-context-failure-observation\",\"passed\":4,\"failed\":0}");
        return 0;
    }
    if(argc==2 && strcmp(argv[1],"--managed-block-fallback-only")==0) {
        assert(managed_block_fallback());
        puts("{\"case\":\"same-original-block-fallback\",\"passed\":1,\"failed\":0}");
        return 0;
    }
    if(argc==2 && strcmp(argv[1],"--managed-search-fallback-only")==0) {
        assert(managed_search_fallback());
        puts("{\"case\":\"same-original-managed-search-fallback\",\"passed\":1,\"failed\":0}");
        return 0;
    }
    if(argc==2 && strcmp(argv[1],"--managed-search-only")==0) {
        assert(managed_search_workload());
        puts("{\"case\":\"same-original-managed-search-and-cleanup\",\"passed\":1,\"failed\":0}");
        return 0;
    }
    if(argc==2 && strcmp(argv[1],"--managed-subpage-only")==0) {
        assert(managed_subpages());
        assert(managed_page_retirement());
        assert(managed_page_exhaustion());
        assert(managed_original_provenance());
        puts("{\"case\":\"managed-subpages\",\"passed\":4,\"failed\":0}");
        return 0;
    }
    if(argc==2 && strcmp(argv[1],"--managed-layout-only")==0) {
        printf("{\"alignment\":%zu,\"blockStruct\":%zu,\"blockHeader\":%zu,\"pageHeader\":%zu,\"readContext\":%zu,\"extentRecord\":%zu,\"capacityHeader\":%zu}\n",
            _Alignof(max_align_t),sizeof(struct read_heap_block),read_heap_header(),
            read_heap_round(sizeof(struct read_heap_page)),sizeof(actql_read_context),
            sizeof(struct extent),sizeof(actql_owned_capacity));
        return 0;
    }
    assert(argc==2);
    bool (*tests[])(void)={fork_stock,managed_alias,busy_cleanup,cleanup_result_after_last_user,alias_only_cleanup,nested_foreign_closing,
        exhausted_no_fallback,retire_retry,fork_arena,foreign_pid,context_retire_retry};
    const char *names[]={"fork-stock","managed-alias","same-owner-cleanup","cleanup-result-after-last-user","alias-only-cleanup","nested-foreign-closing",
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
    assert(real_child_root(argv[1],false)); executed++; puts("{\"case\":\"child-retains-context-reader-and-alias\",\"ok\":true}");
    assert(real_child_root(argv[1],true)); executed++; puts("{\"case\":\"failed-child-retains-original-custody\",\"ok\":true}");
    assert(refused_child_root(argv[1])); executed++; puts("{\"case\":\"child-refuses-foreign-and-closed-parent\",\"ok\":true}");
    assert(real_private_root(argv[1],"",true)); executed++; puts("{\"case\":\"private-root-original-context-and-alias\",\"ok\":true}");
    assert(real_private_root(argv[1],"/broad",false)); executed++; puts("{\"case\":\"private-root-mode-refusal-keeps-original\",\"ok\":true}");
    assert(real_private_root(argv[1],"/absent",false)); executed++; puts("{\"case\":\"private-root-missing-refusal-keeps-original\",\"ok\":true}");
    assert(real_private_root(argv[1],"/alias",false)); executed++; puts("{\"case\":\"private-root-symlink-refusal-keeps-original\",\"ok\":true}");
    assert(real_private_root(argv[1],"/.",false)); executed++; puts("{\"case\":\"private-root-dot-refusal-keeps-original\",\"ok\":true}");
    assert(private_root_without_current(argv[1])); executed++; puts("{\"case\":\"private-root-missing-context-no-acquisition\",\"ok\":true}");
#endif
    printf("{\"success\":true,\"discovered\":%u,\"executed\":%u,\"passed\":%u,\"failed\":0,\"public_e2e\":0}\n",executed,executed,executed);
    return 0;
}
