// Public-only RFC 8032 vectors exercise the actual selected Library.
// Injected callbacks cover getter refusal; no private key or signature is used.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
static int deny_getter;
static void *expected_handle;
static void *fixture_dlsym(void *handle, const char *name) {
  if (deny_getter && strcmp(name, "EVP_PKEY_get_raw_public_key") == 0) {
    assert(handle == expected_handle); return NULL;
  }
  return dlsym(handle, name);
}
#define dlsym fixture_dlsym
#define ACTQL_SIGNATURE_RAW_DIAGNOSTIC
#include "../../src/platform_native/signature/signature_stub.c"
#undef dlsym
static const char *key_a = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=\n-----END PUBLIC KEY-----\n";
static const char *key_b = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAPUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw=\n-----END PUBLIC KEY-----\n";
static const char *x25519 = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VuAyEA11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=\n-----END PUBLIC KEY-----\n";
static const unsigned char expected_a[32] = {0xd7,0x5a,0x98,0x01,0x82,0xb1,0x0a,0xb7,0xd5,0x4b,0xfe,0xd3,0xc9,0x64,0x07,0x3a,0x0e,0xe1,0x72,0xf3,0xda,0xa6,0x23,0x25,0xaf,0x02,0x1a,0x68,0xf7,0x07,0x51,0x1a};
static int supplied_code=1;
static size_t supplied_length=32;
static int injected_getter(const EVP_PKEY *key, unsigned char *pub, size_t *len) {
  assert(key != NULL && pub != NULL && *len == 32);
  memset(pub, 0x7f, 32); *len=supplied_length; return supplied_code;
}
static BIO *failed_bio(const void *bytes, int len) {
  assert(bytes != NULL && len > 0); return NULL;
}
static int project(actql_native_signature_library *library, const char *pem,
                   unsigned char out[32]) {
  return actql_native_signature_ed25519_public_key_raw32(
    library, (moonbit_bytes_t)pem, (int32_t)strlen(pem), out, 32);
}
static void cleared(const unsigned char out[32]) {
  for (int i=0;i<32;i++) assert(out[i]==0);
}
int main(int argc,char **argv) {
  assert(argc==2);
  actql_native_signature_library *library=actql_native_signature_load_library(
    (moonbit_bytes_t)argv[1], (int32_t)strlen(argv[1]), 64);
  assert(actql_native_signature_library_ready(library));
  unsigned char a[32],b[32];
  assert(project(library,key_a,a)==0 && memcmp(a,expected_a,32)==0);
  puts("independent raw32 vector: PASS");
  char crlf[256]; size_t j=0;
  for(size_t i=0;i<strlen(key_a);i++) {
    if(key_a[i]=='\n') crlf[j++]='\r'; crlf[j++]=key_a[i];
  }
  crlf[j]=0;
  assert(project(library,crlf,b)==0 && memcmp(a,b,32)==0);
  puts("different PEM same actual key: PASS");
  assert(project(library,key_b,b)==0 && memcmp(a,b,32)!=0);
  puts("distinct actual public key: PASS");
  assert(project(library,x25519,b)==4);
  puts("non Ed25519 refusal: PASS");
  assert(project(library,"not a public PEM",b)==3);
  assert(project(library,"-----BEGIN PRIVATE KEY-----\ninvalid\n-----END PRIVATE KEY-----",b)==3);
  puts("invalid and private-only PEM refusal: PASS");
  char nul[256];strcpy(nul,key_a);nul[30]=0;
  assert(actql_native_signature_ed25519_public_key_raw32(library,
    (moonbit_bytes_t)nul,(int32_t)strlen(key_a),b,32)==2);
  puts("embedded NUL refusal: PASS");
  assert(actql_native_signature_ed25519_public_key_raw32(library,
    (moonbit_bytes_t)key_a,0,b,32)==2);
  assert(actql_native_signature_ed25519_public_key_raw32(library,
    (moonbit_bytes_t)key_a,16385,b,32)==2);
  assert(actql_native_signature_ed25519_public_key_raw32(library,
    (moonbit_bytes_t)key_a,(int32_t)strlen(key_a),b,31)==2);
  assert(actql_native_signature_ed25519_public_key_raw32(library,
    (moonbit_bytes_t)key_a,(int32_t)strlen(key_a),NULL,32)==2);
  puts("closed input and output bounds: PASS");
  int32_t ceiling=library->diagnostic_ceiling;library->diagnostic_ceiling=0;
  assert(project(library,key_a,b)==2);library->diagnostic_ceiling=ceiling;
  puts("explicit bounded diagnostic required: PASS");
  actql_evp_pkey_get_raw_public_key_fn actual=library->evp_pkey_get_raw_public_key;
  library->evp_pkey_get_raw_public_key=injected_getter;
  supplied_code=0;assert(project(library,key_a,b)==5);cleared(b);
  supplied_code=2;assert(project(library,key_a,b)==5);cleared(b);
  puts("exact getter success code required: PASS");
  supplied_code=1;supplied_length=31;assert(project(library,key_a,b)==5);cleared(b);
  supplied_length=33;assert(project(library,key_a,b)==5);cleared(b);
  puts("exact returned 32 bytes required: PASS");
  library->evp_pkey_get_raw_public_key=NULL;deny_getter=1;
  expected_handle=library->dynamic_library;
  assert(project(library,key_a,b)==5);cleared(b);
  deny_getter=0;library->evp_pkey_get_raw_public_key=actual;
  assert(project(library,key_a,b)==0);
  puts("missing same Library symbol refusal: PASS");
  actql_bio_new_mem_buf_fn bio=library->bio_new_mem_buf;
  library->bio_new_mem_buf=failed_bio;
  assert(project(library,key_a,b)==3);cleared(b);
  library->bio_new_mem_buf=bio;
  puts("public decode allocation refusal: PASS");
  printf("Library bytes=%zu addedGetterBytes=%zu pairPayloadBytes=64\n",
    sizeof(*library),sizeof(library->evp_pkey_get_raw_public_key));
  moonbit_decref(library);
  puts("Public key comparison cases: 12/12");
  return 0;
}
