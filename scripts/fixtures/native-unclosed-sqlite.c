#define _POSIX_C_SOURCE 200809L
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>
#include <unistd.h>

// Independent version-3 fixture. Execute in a fresh process, commit the old
// Coordinator wire, and exit without SQLite close so the WAL stays present.
int main(int argc, char **argv) {
  if (argc != 5 || (strcmp(argv[4], "0") && strcmp(argv[4], "1"))) return 10;
  uint32_t lengths[2];
  FILE *input = fopen(argv[3], "rb");
  if (!input || fread(lengths, sizeof(lengths), 1, input) != 1 ||
      !lengths[0] || lengths[0] > 65536 || lengths[1] > 1048576) return 11;
  unsigned char *key = malloc(lengths[0]), *body = malloc(lengths[1] ? lengths[1] : 1);
  if (!key || !body || fread(key, 1, lengths[0], input) != lengths[0] ||
      fread(body, 1, lengths[1], input) != lengths[1] || fgetc(input) != EOF ||
      fclose(input)) return 12;
  void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) { fprintf(stderr, "WAL fixture library: %s\n", dlerror()); return 13; }
  int (*open_db)(const char *, sqlite3 **, int, const char *);
  int (*exec_sql)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
  int (*prepare)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
  int (*bind_text)(sqlite3_stmt *, int, const char *, int, void (*)(void *));
  int (*bind_blob)(sqlite3_stmt *, int, const void *, int, void (*)(void *));
  int (*step)(sqlite3_stmt *), (*finalize)(sqlite3_stmt *);
  const char *(*error)(sqlite3 *);
#define LOAD(field, symbol) do { *(void **)(&(field)) = dlsym(library, symbol); if (!(field)) return 14; } while (0)
  LOAD(open_db, "sqlite3_open_v2"); LOAD(exec_sql, "sqlite3_exec");
  LOAD(prepare, "sqlite3_prepare_v2"); LOAD(bind_text, "sqlite3_bind_text");
  LOAD(bind_blob, "sqlite3_bind_blob"); LOAD(step, "sqlite3_step");
  LOAD(finalize, "sqlite3_finalize"); LOAD(error, "sqlite3_errmsg");
  sqlite3 *database = NULL;
  if (open_db(argv[2], &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL) != SQLITE_OK) return 15;
  const char *schema =
    "PRAGMA journal_mode=WAL;PRAGMA synchronous=FULL;PRAGMA foreign_keys=ON;"
    "BEGIN IMMEDIATE;"
    "CREATE TABLE actql_records(namespace TEXT NOT NULL,record_key TEXT NOT NULL,"
    "revision INTEGER NOT NULL CHECK(revision >= 0),body BLOB NOT NULL,PRIMARY KEY(namespace, record_key)) STRICT;"
    "CREATE TABLE actql_capacity(namespace TEXT NOT NULL,reservation_key TEXT NOT NULL,"
    "reserved_bytes INTEGER NOT NULL CHECK(reserved_bytes >= 0),reserved_objects INTEGER NOT NULL CHECK(reserved_objects >= 0),"
    "PRIMARY KEY(namespace, reservation_key)) STRICT;"
    "CREATE TABLE actql_claims(namespace TEXT NOT NULL,claim_key TEXT NOT NULL,"
    "ordinal INTEGER NOT NULL CHECK(ordinal > 0),PRIMARY KEY(namespace, claim_key),UNIQUE(namespace, ordinal)) STRICT;"
    "PRAGMA user_version=3;COMMIT;PRAGMA wal_autocheckpoint=0;";
  if (exec_sql(database, schema, NULL, NULL, NULL) != SQLITE_OK) {
    fprintf(stderr, "WAL fixture schema: %s\n", error(database)); return 16;
  }
  sqlite3_stmt *statement = NULL;
  int code = prepare(database, "INSERT INTO actql_records VALUES('coordinator_dispatch',?1,0,?2)", -1, &statement, NULL);
  if (code == SQLITE_OK) code = bind_text(statement, 1, (const char *)key, (int)lengths[0], SQLITE_TRANSIENT);
  if (code == SQLITE_OK) code = bind_blob(statement, 2, body, (int)lengths[1], SQLITE_TRANSIENT);
  if (code == SQLITE_OK) code = step(statement);
  if (code != SQLITE_DONE || finalize(statement) != SQLITE_OK) return 17;
  if (!strcmp(argv[4], "1") && exec_sql(database, "DROP TABLE actql_capacity", NULL, NULL, NULL) != SQLITE_OK) return 18;
  // Deliberately no close, checkpoint, finalizer or atexit handler.
  _exit(0);
}
