/* Real C transport and managed-reference counters only. These callbacks are
 * fixture DATA, never a Native Session, Host admission or physical cleanup. */
#include "local_adoption_shim.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

typedef struct { int value; } Token;
typedef struct {
    actql_control_host *host;
    actql_local_host_resources *pair;
    actql_parent_read *read;
    actql_adoption_crypto *crypto;
    actql_adoption_session *session;
    actql_adoption_journal *journal;
    int ack;
} Binding;
typedef struct { actql_adoption_binding *original; int op, issue; } Reply;
static int live, prepared, operated, attached, journal_opened, allow_close, cases;
static actql_control_host *expected_host;
static actql_local_host_resources *expected_pair;
static actql_parent_read *expected_read;
static actql_adoption_crypto *expected_crypto;
static void token_drop(void *value) { (void)value; live--; }
static void *token(int value) {
    Token *t = moonbit_make_external_object(token_drop, sizeof(Token));
    t->value = value; live++; return t;
}
static void binding_drop(void *value) {
    Binding *b = value;
    moonbit_decref(b->host); moonbit_decref(b->pair);
    moonbit_decref(b->read); moonbit_decref(b->crypto);
    if (b->session) moonbit_decref(b->session);
    if (b->journal) moonbit_decref(b->journal);
    live--;
}
static void reply_drop(void *value) {
    Reply *r = value; moonbit_decref(r->original); live--;
}
static actql_adoption_reply *reply(actql_adoption_binding *b, int op, int issue) {
    Reply *r = moonbit_make_external_object(reply_drop, sizeof(Reply));
    r->original = b; r->op = op; r->issue = issue;
    moonbit_incref(b); live++; return (actql_adoption_reply *)r;
}
static void exact(moonbit_string_t s, const uint16_t *expected, int32_t units) {
    assert(Moonbit_array_length(s) == units);
    assert(memcmp(s, expected, (size_t)units * 2) == 0);
}
static actql_adoption_binding *prepare(actql_control_host *h, actql_local_host_resources *p,
    actql_parent_read *r, actql_adoption_crypto *c, moonbit_string_t parent,
    moonbit_string_t state, moonbit_string_t source, moonbit_string_t name,
    moonbit_string_t account, moonbit_string_t *files, moonbit_string_t managed,
    int32_t has_managed, int32_t ceiling) {
    const uint16_t unicode[] = {'r', 0xD83D, 0xDE00};
    const uint16_t first[] = {'a', 0xD83D, 0xDE00};
    const uint16_t second[] = {'b'};
    const uint16_t id[] = {' ', 0x2028, 0x2029};
    assert(h == expected_host && p == expected_pair && r == expected_read && c == expected_crypto);
    exact(parent, unicode, 3); exact(state, unicode, 3); exact(source, unicode, 3);
    exact(name, unicode, 3); exact(account, id, 3);
    assert(Moonbit_array_length(files) == 2);
    exact(files[0], first, 3); exact(files[1], second, 1);
    assert(!has_managed && Moonbit_array_length(managed) == 0 && ceiling == 128);
    Binding *b = moonbit_make_external_object(binding_drop, sizeof(Binding));
    memset(b, 0, sizeof(*b)); b->host=h; b->pair=p; b->read=r; b->crypto=c;
    moonbit_incref(h); moonbit_incref(p); moonbit_incref(r); moonbit_incref(c);
    live++; prepared++; return (actql_adoption_binding *)b;
}
static actql_adoption_reply *operate(actql_adoption_binding *value, int32_t op) {
    Binding *b = (Binding *)value; operated++;
    if (op == 1 && !b->session) b->session = token(5);
    if (op == 5) { assert(b->journal && attached == 1); journal_opened++; }
    if (op == 3 && allow_close) b->ack = 1;
    return reply(value, op, op == 3 && !b->ack ? 4 : 0);
}
static actql_adoption_reply *attach(actql_adoption_binding *value, double ttl, int32_t records, int64_t bytes) {
    Binding *b = (Binding *)value; assert(ttl == 100.0 && records == 8 && bytes == 8388608);
    assert(b->session && !b->journal); b->journal = token(6); attached++;
    return reply(value, 4, 0);
}
static actql_adoption_binding *original(actql_adoption_reply *value) {
    actql_adoption_binding *b = ((Reply *)value)->original; moonbit_incref(b); return b;
}
#define GETTER(name, type, field) static type *name(actql_adoption_binding *value) { \
    type *p=((Binding *)value)->field; if (p) moonbit_incref(p); return p; }
GETTER(host, actql_control_host, host)
GETTER(pair, actql_local_host_resources, pair)
GETTER(read_original, actql_parent_read, read)
GETTER(crypto, actql_adoption_crypto, crypto)
GETTER(session, actql_adoption_session, session)
GETTER(journal, actql_adoption_journal, journal)
static int32_t ack(actql_adoption_binding *value) { return ((Binding *)value)->ack; }
static int32_t operation(actql_adoption_reply *value) { return ((Reply *)value)->op; }
static int32_t issue(actql_adoption_reply *value) { return ((Reply *)value)->issue; }
static int make(actql_adoption_binding **out, const uint16_t *text, int32_t units,
                const int32_t *lengths, int32_t count) {
    const uint16_t id[]={' ',0x2028,0x2029}, files[]={'a',0xD83D,0xDE00,'b'};
    return actql_local_adoption_prepare_utf16_into(expected_host, expected_pair, expected_read,
        expected_crypto, text, units, text, units, text, units, text, units, id, 3,
        files, 4, lengths, count, NULL, 0, 0, 128, out);
}
int main(void) {
    expected_host=token(1); expected_pair=token(2); expected_read=token(3); expected_crypto=token(4);
    const uint16_t text[]={'r',0xD83D,0xDE00}, bad[]={0xD800};
    const int32_t lengths[]={3,1}, wrong[]={2,1};
    actql_adoption_binding *b=NULL; actql_adoption_reply *r=NULL;
    assert(make(&b,text,3,lengths,2)==ACTQL_CONTROL_UNAVAILABLE && !b && !prepared); cases++;
    actql_native_control_register_local_adoption_binding_roots(prepare,operate,attach,original,
        host,pair,read_original,crypto,session,journal,ack,operation,issue);
    assert(make(&b,bad,1,lengths,2)==ACTQL_CONTROL_INVALID_SLOT && !prepared); cases++;
    assert(make(&b,text,3,wrong,2)==ACTQL_CONTROL_INVALID_SLOT && !prepared); cases++;
    assert(make(&b,text,3,lengths,9)==ACTQL_CONTROL_INVALID_SLOT && !prepared); cases++;
    assert(make(&b,text,3,lengths,2)==0 && b && prepared==1); cases++;
    assert(make(&b,text,3,lengths,2)==ACTQL_CONTROL_INVALID_SLOT && prepared==1); cases++;
    actql_control_host *h=NULL; actql_local_host_resources *p=NULL; actql_parent_read *rd=NULL;
    actql_adoption_crypto *c=NULL; actql_adoption_session *s=NULL; actql_adoption_journal *j=NULL;
    assert(actql_local_adoption_originals_into(b,&h,&p,&rd,&c,&s,&j)==0);
    assert(h==expected_host && p==expected_pair && rd==expected_read && c==expected_crypto && !s && !j); cases++;
    actql_control_host *saved=h; h=token(7);
    assert(actql_local_adoption_drop_originals(b,&h,&p,&rd,&c,&s,&j)==ACTQL_CONTROL_INVALID_SLOT);
    assert(h!=saved && p==expected_pair && rd==expected_read && c==expected_crypto);
    moonbit_decref(h); h=saved;
    assert(actql_local_adoption_drop_originals(b,&h,&p,&rd,&c,&s,&j)==0); cases++;
    assert(actql_local_adoption_operate_into(b,1,&r)==0 && operation(r)==1 && !issue(r));
    assert(actql_local_adoption_finish_closed_data(&b,&r)==ACTQL_CONTROL_INVALID_SLOT && b && r);
    assert(actql_local_adoption_drop_reply(&r,b)==0 && !r); cases++;
    assert(actql_local_adoption_capture_journal_into(b,100.0,8,8388608,&r)==0);
    assert(operation(r)==4 && !issue(r) && attached==1);
    assert(actql_local_adoption_originals_into(b,&h,&p,&rd,&c,&s,&j)==0 && s && j);
    assert(actql_local_adoption_drop_originals(b,&h,&p,&rd,&c,&s,&j)==0);
    assert(actql_local_adoption_drop_reply(&r,b)==0); cases++;
    assert(actql_local_adoption_operate_into(b,4,&r)==ACTQL_CONTROL_INVALID_SLOT && !r);
    assert(actql_local_adoption_operate_into(b,5,&r)==0 && operation(r)==5 && !issue(r));
    assert(journal_opened==1 && attached==1);
    assert(actql_local_adoption_drop_reply(&r,b)==0); cases++;
    assert(actql_local_adoption_operate_into(b,3,&r)==0 && issue(r)==4);
    assert(actql_local_adoption_finish_closed_data(&b,&r)==ACTQL_CONTROL_INVALID_SLOT && b && r);
    assert(actql_local_adoption_drop_reply(&r,b)==0); cases++;
    allow_close=1; assert(actql_local_adoption_operate_into(b,3,&r)==0 && !issue(r));
    assert(actql_local_adoption_finish_closed_data(&b,&r)==0 && !b && !r);
    assert(actql_local_adoption_finish_closed_data(&b,&r)==0 && operated==4); cases++;
    moonbit_decref(expected_host); moonbit_decref(expected_pair);
    moonbit_decref(expected_read); moonbit_decref(expected_crypto);
    assert(live==0 && cases==13);
    printf("{\"executed\":%d,\"passed\":%d,\"managed_aliases_closed\":true,\"fixture_callbacks\":true,\"physical_session\":false}\n",cases,cases);
    return 0;
}
