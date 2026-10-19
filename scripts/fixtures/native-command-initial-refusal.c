/* Actual selected constructor refusal must precede later initializers and main.
 * This counter supplies no complete operational envelope or physical admission. */
#include "../../src/cmd/native_client/stdout_stub.c"

__attribute__((constructor)) static void actql_test_later_initializer(void) {
  static const char marker[] = "later initializer\n";
  (void)write(STDOUT_FILENO, marker, sizeof(marker) - 1);
}

int main(void) {
  static const char marker[] = "main\n";
  (void)write(STDOUT_FILENO, marker, sizeof(marker) - 1);
  return 0;
}
