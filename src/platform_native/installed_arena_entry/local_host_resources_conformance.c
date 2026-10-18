/* Actual same-provider Root/SQLite custody. The complete existing private
 * Runtime declaration is diagnostic only, not a normal Host/Run supplier. */
#include "local_host_resources_shim.h"
#include "sqlite_database_shim.h"
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
extern int actql_original_control_initialize(int, char **);
extern int64_t actql_bootstrap_page_bytes(void);
extern void *actql_native_filesystem_acquire_current_root(moonbit_bytes_t, int32_t, int32_t);
extern int32_t actql_native_filesystem_acquisition_status(void *);
extern int32_t actql_native_filesystem_acquisition_has_original(void *);
extern void *actql_native_filesystem_acquisition_root(void *);
extern int32_t actql_native_filesystem_root_close_dispatch(void *);
#define REQUIRE(c) do { if (!(c)) { fprintf(stderr,"assertion line %d: %s\n",__LINE__,#c); exit(1); } } while(0)
static unsigned count;
static void step(const char *name) { printf("case:%u:%s\n",++count,name); fflush(stdout); }
static uint16_t *text(const char *s, int32_t *units) {
    size_t n=strlen(s); REQUIRE(n>0 && n<=4096);
    uint16_t *out=calloc(n,sizeof(*out)); REQUIRE(out);
    for(size_t i=0;i<n;i++) { REQUIRE((unsigned char)s[i]<128);out[i]=(unsigned char)s[i]; }
    *units=(int32_t)n;return out;
}
static void drop_domain(actql_domain_reply **r, actql_control_host *h, actql_domain *d) {
    REQUIRE(*r && actql_domain_issue_family(*r)==0);
    REQUIRE(actql_domain_drop_reply(r,h,d)==0 && !*r);
}
static void drop_backing(actql_backing_reply **r, actql_control_host *h, actql_backing_loan *b) {
    REQUIRE(*r && actql_backing_issue_family(*r)==0);
    REQUIRE(actql_backing_drop_reply(r,h,b)==0 && !*r);
}
static actql_domain *domain(actql_control_host *h,actql_backing_loan *loan,int fd,
    int64_t bytes,int attempts,int64_t retained,int64_t execution,actql_control_host **alias) {
    actql_domain_reply *r=NULL;actql_domain *d=NULL;
    REQUIRE(actql_domain_prepare_into(h,loan,fd,bytes,2,attempts,1,3,retained,execution,&r)==0);
    REQUIRE(actql_domain_issue_family(r)==0);
    REQUIRE(actql_domain_originals_into(r,alias,&d)==0 && *alias==h && d);
    drop_domain(&r,h,d);
    REQUIRE(actql_domain_transfer_into(h,d,&r)==0);drop_domain(&r,h,d);return d;
}
static void phase(actql_control_host *h,actql_control_host *sh,actql_parent_read *r,
    actql_sqlite_original *s,actql_local_host_resources *p,int op,int expected_origin) {
    actql_local_host_resources_reply *reply=NULL;
    REQUIRE(actql_host_resources_operate_into(h,p,op,&reply)==0);
    REQUIRE(actql_host_resources_operation(reply)==op);
    REQUIRE(actql_host_resources_issue_origin(reply)==expected_origin);
    REQUIRE(actql_host_resources_drop_reply(&reply,h,sh,r,s,p)==0);
}
static void db_drop(actql_sqlite_database_reply **r,actql_control_host *h,
    actql_sqlite_original *s,actql_sqlite_database *d) {
    REQUIRE(*r && actql_sqlite_database_issue_family(*r)==0 && actql_sqlite_database_after_issue_family(*r)==0);
    REQUIRE(actql_sqlite_database_drop_reply(r,h,s,d)==0);
}
int main(int argc,char **argv) {
    REQUIRE(argc==6); /* original source, selected component, fresh backing, Root, DB */
    REQUIRE(strlen(argv[1])==40);
    REQUIRE(actql_original_control_initialize(argc,argv)==0);
    int fd=open(argv[3],O_RDWR|O_NOFOLLOW);REQUIRE(fd>=0);
    int64_t page=actql_bootstrap_page_bytes(),total=8192*page;
    struct stat backing;REQUIRE(fstat(fd,&backing)==0 && backing.st_size==total);
    int32_t n;uint16_t *source=text(argv[1],&n);unsigned char recipe[32];memset(recipe,17,32);
    actql_control_reply *cr=NULL;actql_control_host *h=NULL,*h2=NULL;
    REQUIRE(actql_control_prepare_utf16_into(source,n,recipe,32,1,total,20,8,4,30,0,total,65536,&cr)==0);free(source);
    REQUIRE(actql_control_issue_family(cr)==0);
    REQUIRE(actql_control_originals_into(cr,&h,&h2)==0 && h && h==h2);
    REQUIRE(actql_control_drop_reply(&cr,h)==0);
    REQUIRE(actql_control_acquire_fd_into(h,fd,&cr)==0 && actql_control_issue_family(cr)==0);
    REQUIRE(actql_control_drop_reply(&cr,h)==0);
    int64_t initial=actql_host_resources_capacity_scalar(h,1);
    REQUIRE(actql_host_resources_capacity_scalar(h,0)==total && initial>0 && initial<total);
    printf("capacity:total=%"PRId64":actual_control=%"PRId64":page=%"PRId64"\n",total,initial,page);
    step("same original Host acquires exclusive backing and reports actual control usage");
    actql_backing_reply *br=NULL;actql_control_host *bh=NULL;actql_backing_loan *loan=NULL;
    REQUIRE(actql_backing_borrow_into(h,&br)==0);
    REQUIRE(actql_backing_originals_into(br,&bh,&loan)==0 && bh==h && loan);drop_backing(&br,h,loan);
    REQUIRE(actql_backing_enter_scope_into(h,loan,&br)==0);drop_backing(&br,h,loan);
    actql_control_host *rh=NULL,*sqh=NULL;
    actql_domain *rd=domain(h,loan,fd,7168*page,2,32*page,6144*page,&rh);
    int64_t after_read=actql_host_resources_capacity_scalar(h,1);
    REQUIRE(after_read>=initial+7168*page && total-after_read>=48*page);
    actql_domain *sd=domain(h,loan,fd,48*page,1,0,48*page,&sqh);
    int64_t after_sql=actql_host_resources_capacity_scalar(h,1);
    REQUIRE(after_sql>=after_read+48*page && after_sql<=total);
    REQUIRE(actql_backing_leave_scope_into(h,loan,&br)==0);drop_backing(&br,h,loan);
    printf("capacity:read_allocated=%"PRId64":both_allocated=%"PRId64"\n",after_read,after_sql);
    step("disjoint original read and SQLite extents fit actual residual without a second reservation");
    actql_domain_reply *dr=NULL;
    REQUIRE(actql_domain_read_prepare_into(h,rd,&dr)==0);drop_domain(&dr,h,rd);
    REQUIRE(actql_domain_read_prepare_into(h,sd,&dr)==0);drop_domain(&dr,h,sd);
    actql_parent_read_reply *pr=NULL;actql_control_host *prh=NULL;actql_domain *prd=NULL;actql_parent_read *read=NULL;
    REQUIRE(actql_parent_read_prepare_into(h,rd,16*page,16*page,4096*page,16*page,1024*page,&pr)==0);
    REQUIRE(actql_parent_read_issue_family(pr)==0);
    REQUIRE(actql_parent_read_originals_into(pr,&prh,&prd,&read)==0 && prh==h && prd==rd && read);
    REQUIRE(actql_parent_read_drop_reply(&pr,h,rd,read)==0);
    actql_sqlite_reply *sr=NULL;actql_control_host *srh=NULL;actql_domain *srd=NULL;actql_sqlite_original *sql=NULL;
    uint16_t *library=text(argv[2],&n);
    REQUIRE(actql_sqlite_prepare_utf16_into(h,sd,library,n,32*page,128,&sr)==0);free(library);
    REQUIRE(actql_sqlite_issue_family(sr)==0);
    REQUIRE(actql_sqlite_originals_into(sr,&srh,&srd,&sql)==0 && srh==h && srd==sd && sql);
    REQUIRE(actql_sqlite_drop_reply(&sr,h,sd,sql)==0);
    step("original imported Read and first-init private SQLite retain the same provider and distinct domains");
    /* A typed foreign-target refusal retains the true input roles but no pair.
     * Its data retirement cannot close either independently owned original. */
    source=text(argv[1],&n);
    actql_control_host *foreign=NULL,*foreign_alias=NULL;
    REQUIRE(actql_control_prepare_utf16_into(source,n,recipe,32,1,total,20,8,4,30,0,total,65536,&cr)==0);
    free(source);REQUIRE(actql_control_issue_family(cr)==0);
    REQUIRE(actql_control_originals_into(cr,&foreign,&foreign_alias)==0 && foreign==foreign_alias);
    REQUIRE(actql_control_drop_reply(&cr,foreign)==0);
    actql_local_host_resources_reply *refused=NULL;
    actql_control_host *refused_host=NULL,*refused_sqlite_host=NULL;
    actql_parent_read *refused_read=NULL;actql_sqlite_original *refused_sqlite=NULL;
    actql_local_host_resources *absent_pair=NULL;
    REQUIRE(actql_host_resources_bind_into(foreign,read,sql,&refused)==0);
    REQUIRE(actql_host_resources_issue_origin(refused)==2 && actql_host_resources_issue_family(refused)==2);
    REQUIRE(actql_host_resources_originals_into(refused,&refused_host,&refused_sqlite_host,
        &refused_read,&refused_sqlite,&absent_pair)==0);
    REQUIRE(refused_host==h && refused_sqlite_host==h && refused_read==read && refused_sqlite==sql && !absent_pair);
    actql_control_host *wrong_role=foreign;
    REQUIRE(actql_host_resources_finish_refused_bind_data(&wrong_role,&refused_sqlite_host,
        &refused_read,&refused_sqlite,&absent_pair,&refused)==ACTQL_CONTROL_INVALID_SLOT);
    REQUIRE(wrong_role==foreign && refused && refused_read==read && refused_sqlite==sql);
    REQUIRE(actql_host_resources_finish_refused_bind_data(&refused_host,&refused_sqlite_host,
        &refused_read,&refused_sqlite,&absent_pair,&refused)==0);
    REQUIRE(!refused_host && !refused_sqlite_host && !refused_read && !refused_sqlite && !absent_pair && !refused);
    moonbit_decref(foreign_alias);
    REQUIRE(actql_control_try_close_and_drop(&foreign,&cr)==0 && !foreign && !cr);
    step("refused bind data retirement preserves original inputs and rejects foreign role substitution");
    actql_local_host_resources_reply *pair_reply=NULL;actql_control_host *ph=NULL,*psh=NULL;
    actql_parent_read *pair_read=NULL;actql_sqlite_original *pair_sql=NULL;actql_local_host_resources *pair=NULL;
    REQUIRE(actql_host_resources_bind_into(h,read,sql,&pair_reply)==0);
    REQUIRE(actql_host_resources_issue_origin(pair_reply)==0);
    REQUIRE(actql_host_resources_originals_into(pair_reply,&ph,&psh,&pair_read,&pair_sql,&pair)==0);
    REQUIRE(ph==h && psh==h && pair_read==read && pair_sql==sql && pair);
    REQUIRE(actql_host_resources_drop_reply(&pair_reply,ph,psh,pair_read,pair_sql,pair)==0);
    phase(ph,psh,pair_read,pair_sql,pair,3,0);
    phase(ph,psh,pair_read,pair_sql,pair,4,1);
    moonbit_bytes_t root_path=moonbit_make_bytes((int32_t)strlen(argv[4]),0);
    memcpy(root_path,argv[4],strlen(argv[4]));
    void *acquisition=actql_native_filesystem_acquire_current_root(root_path,(int32_t)strlen(argv[4]),128);
    moonbit_decref(root_path);
    REQUIRE(acquisition && actql_native_filesystem_acquisition_status(acquisition)==0 && actql_native_filesystem_acquisition_has_original(acquisition)==1);
    void *root=actql_native_filesystem_acquisition_root(acquisition);REQUIRE(root);
    moonbit_decref(acquisition);
    phase(ph,psh,pair_read,pair_sql,pair,5,0);
    step("real Root is allocated under original Read and nested SQLite phase is refused");
    struct stat dbstat;REQUIRE(stat(argv[5],&dbstat)==0);
    actql_sqlite_database_reply *dbreply=NULL;actql_control_host *dbh=NULL;actql_sqlite_original *dblib=NULL;actql_sqlite_database *db=NULL;
    uint16_t *path=text(argv[5],&n);
    REQUIRE(actql_sqlite_database_initialize_utf16_into(h,sql,path,n,4096,(uint64_t)dbstat.st_dev,(uint64_t)dbstat.st_ino,&dbreply)==0);free(path);
    REQUIRE(actql_sqlite_database_issue_family(dbreply)==0 && actql_sqlite_database_after_issue_family(dbreply)==0);
    REQUIRE(actql_sqlite_database_originals_into(dbreply,&dbh,&dblib,&db)==0 && dbh==h && dblib==sql && db);
    db_drop(&dbreply,h,sql,db);
    step("same Library opens exactly one owned SQLite Database");
    phase(ph,psh,pair_read,pair_sql,pair,4,0);
    REQUIRE(actql_sqlite_database_transaction_into(h,db,7,&dbreply)==0);db_drop(&dbreply,h,sql,db);
    int32_t su,ku;uint16_t *scope=text("pair",&su),*key=text("one",&ku);const unsigned char body[]={0,65,255};
    REQUIRE(actql_sqlite_database_insert_utf16_into(h,db,scope,su,key,ku,body,3,&dbreply)==0);db_drop(&dbreply,h,sql,db);
    REQUIRE(actql_sqlite_database_transaction_into(h,db,8,&dbreply)==0);db_drop(&dbreply,h,sql,db);
    REQUIRE(actql_sqlite_database_read_utf16_into(h,db,scope,su,key,ku,4096,&dbreply)==0);
    REQUIRE(actql_sqlite_database_has_row(dbreply)==1);
    unsigned char copy[4]={9,9,9,9};int64_t copied=-1;
    REQUIRE(actql_sqlite_database_copy_row(dbreply,h,sql,db,copy,4,&copied)==0 && copied==3 && memcmp(copy,body,3)==0 && copy[3]==9);
    db_drop(&dbreply,h,sql,db);free(scope);free(key);
    phase(ph,psh,pair_read,pair_sql,pair,5,0);
    step("actual transaction insert commit and bounded result read use the same SQLite context");
    /* A real Database retains the Library; local close is not its ACK. */
    phase(ph,psh,pair_read,pair_sql,pair,8,3);
    phase(ph,psh,pair_read,pair_sql,pair,2,1);
    REQUIRE(actql_sqlite_database_close_into(h,db,&dbreply)==0);
    REQUIRE(actql_sqlite_database_issue_family(dbreply)==0 && actql_sqlite_database_after_issue_family(dbreply)==0);
    REQUIRE(actql_sqlite_database_finish_closed_data(&dbh,&dblib,&db,&dbreply)==0);
    step("live Database blocks pair cleanup and closing fences new work until its actual close ACK");
    /* SQLite ACK may complete, while a separate real Root still keeps Read. */
    REQUIRE(actql_host_resources_operate_into(ph,pair,8,&pair_reply)==0);
    REQUIRE(actql_host_resources_issue_origin(pair_reply)==2 && actql_host_resources_close_confirmed(pair_reply)==0);
    REQUIRE(actql_host_resources_finish_closed_data(&ph,&psh,&pair_read,&pair_sql,&pair,&pair_reply)==ACTQL_CONTROL_INVALID_SLOT);
    REQUIRE(actql_host_resources_drop_reply(&pair_reply,ph,psh,pair_read,pair_sql,pair)==0);
    step("Root alias keeps original Read pending after independent SQLite retirement");
    phase(ph,psh,pair_read,pair_sql,pair,6,0);
    REQUIRE(actql_native_filesystem_root_close_dispatch(root)==0);
    phase(ph,psh,pair_read,pair_sql,pair,5,0);
    REQUIRE(actql_host_resources_operate_into(ph,pair,8,&pair_reply)==0);
    REQUIRE(actql_host_resources_issue_origin(pair_reply)==2 && actql_host_resources_close_confirmed(pair_reply)==0);
    REQUIRE(actql_host_resources_drop_reply(&pair_reply,ph,psh,pair_read,pair_sql,pair)==0);
    moonbit_decref(root);root=NULL;
    step("physical Root close does not retire its outstanding managed alias");
    REQUIRE(actql_host_resources_operate_into(ph,pair,8,&pair_reply)==0);
    REQUIRE(actql_host_resources_close_confirmed(pair_reply)==1);
    REQUIRE(actql_host_resources_finish_closed_data(&ph,&psh,&pair_read,&pair_sql,&pair,&pair_reply)==0);
    REQUIRE(!ph && !psh && !pair_read && !pair_sql && !pair && !pair_reply);
    step("last original aliases permit separate context ACKs and data-only pair release");
    moonbit_decref(read);moonbit_decref(prd);moonbit_decref(prh);
    moonbit_decref(sql);moonbit_decref(srd);moonbit_decref(srh);
    REQUIRE(actql_backing_return_into(h,loan,&br)==0);
    REQUIRE(actql_backing_finish_returned_data(&bh,&loan,&br)==0);
    REQUIRE(actql_domain_close_into(h,rd,&dr)==0 && actql_domain_issue_family(dr)==0);
    REQUIRE(actql_domain_finish_closed_data(&rh,&rd,&dr)==0);
    REQUIRE(actql_domain_close_into(h,sd,&dr)==0 && actql_domain_issue_family(dr)==0);
    REQUIRE(actql_domain_finish_closed_data(&sqh,&sd,&dr)==0);
    REQUIRE(actql_host_resources_capacity_scalar(h,1)==initial);
    moonbit_decref(h2);
    REQUIRE(actql_control_try_close_and_drop(&h,&cr)==0 && !h && !cr);
    REQUIRE(close(fd)==0);
    step("same original domains mappings loan Host and borrowed descriptor all retire after their own ACKs");
    printf("{\"discovered\":%u,\"executed\":%u,\"passed\":%u,\"failed\":0,\"initializer\":1,\"all_originals_closed\":true,\"normal_profile\":null,\"public_e2e\":0}\n",count,count,count);
    return 0;
}
