#ifndef ACTQL_SQLITE_FIXTURE_RETIREMENT_FAULT_H
#define ACTQL_SQLITE_FIXTURE_RETIREMENT_FAULT_H
/* Fixture-only dylib. Fault state and interpose live together in that image,
 * not in a main executable whose interpose section dyld may not apply. */
void actql_fixture_retirement_arm(void);
unsigned actql_fixture_retirement_calls(void);
int actql_fixture_retirement_armed(void);
#endif
