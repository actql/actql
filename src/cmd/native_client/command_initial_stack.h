#ifndef ACTQL_NATIVE_COMMAND_INITIAL_STACK_H
#define ACTQL_NATIVE_COMMAND_INITIAL_STACK_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <pthread.h>
#include <unistd.h>

/* Subordinate to the trusted command entry. The OS-created original main
 * thread already owns this stack; neither its address nor its size supplies
 * another allocator, a Read domain or a new thread. Retain the whole extent,
 * rather than an observed high-water mark. There is no close/refill operation.
 */
typedef struct {
  pid_t process;
  pthread_t thread;
  uintptr_t lower, upper;
  size_t bytes;
  bool attempted, captured;
} actql_bootstrap_command_stack;

static bool actql_bootstrap_capture_command_stack(
    actql_bootstrap_command_stack *original) {
  if (!original || original->attempted) return false;
  original->attempted = true;
#if defined(__APPLE__)
  original->process = getpid();
  original->thread = pthread_self();
  if (!pthread_main_np()) return false;
  uintptr_t upper = (uintptr_t)pthread_get_stackaddr_np(original->thread);
  size_t bytes = pthread_get_stacksize_np(original->thread);
  volatile unsigned char marker = 0;
  uintptr_t current = (uintptr_t)&marker;
  if (!upper || !bytes || bytes > upper ||
      current < upper - bytes || current >= upper) return false;
  original->upper = upper;
  original->lower = upper - bytes;
  original->bytes = bytes;
  original->captured = true;
  return true;
#else
  return false;
#endif
}

/* The enclosing entry checks nominal membership before this private check.
 * A fork, another thread or changed OS extent cannot reuse the captured stack.
 * This is original-stack correspondence, not complete initial admission or a
 * proof that every possible call chain fits the supplied stack capacity. */
static bool actql_bootstrap_command_stack_current(
    const actql_bootstrap_command_stack *original) {
#if defined(__APPLE__)
  if (!original || !original->attempted || !original->captured ||
      original->process != getpid() ||
      !pthread_equal(original->thread, pthread_self()) || !pthread_main_np() ||
      !original->bytes || original->bytes > original->upper ||
      original->lower != original->upper - original->bytes) return false;
  volatile unsigned char marker = 0;
  uintptr_t current = (uintptr_t)&marker;
  return (uintptr_t)pthread_get_stackaddr_np(original->thread) == original->upper &&
    pthread_get_stacksize_np(original->thread) == original->bytes &&
    current >= original->lower && current < original->upper;
#else
  (void)original;
  return false;
#endif
}

#endif
