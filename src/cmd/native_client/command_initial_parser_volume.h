#ifndef ACTQL_NATIVE_COMMAND_INITIAL_PARSER_VOLUME_H
#define ACTQL_NATIVE_COMMAND_INITIAL_PARSER_VOLUME_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

/* Source-bound managed terms for the immutable selected Command graph:
 * 28 commands, 135 arguments, depth two, one local Append and no multiple
 * positional. These select the existing finite initial facility; they are
 * neither an all-input demand-fit guarantee nor complete physical coverage.
 * Pages, allocator controls, SIMDUTF/stack, platform and later command holdings
 * remain separate. The four argv classes come from this SAME entry.
 * No free, default restoration or child close is credited here. */
#if defined(__APPLE__)
static bool actql_command_volume_add(size_t *total, size_t value) {
  if (value > SIZE_MAX - *total) return false;
  *total += value;
  return true;
}

static bool actql_command_reference_growth(size_t elements, size_t *out) {
  size_t capacity = 8, total = 0;
  for (;;) {
    if (capacity > (SIZE_MAX - 8) / 8) return false;
    size_t request = 8 + 8 * capacity;
    size_t actual_class = mi_good_size(request);
    if (actual_class < request ||
        !actql_command_volume_add(&total, actual_class)) return false;
    if (capacity >= elements) break;
    if (capacity > SIZE_MAX / 2) return false;
    capacity *= 2;
  }
  *out = total;
  return true;
}

static size_t actql_command_builder_volume(size_t length) {
  size_t capacity = 1, logarithm = 0;
  while (capacity < length) { capacity *= 2; logarithm++; }
  return 15 * length + 32 * (logarithm + 4);
}

static bool actql_command_initial_parser_volume(size_t arguments,
    size_t storage, const int64_t argv_classes[4], size_t *out) {
  if (!out || !argv_classes || sizeof(size_t) != 8 || arguments == 0 ||
      arguments > 1048576 || storage < arguments || storage > 1048576)
    return false;
  size_t one, subcommands, singleton_growth, fixed_growth, input_growth;
  one = mi_good_size(8 + 8);
  subcommands = mi_good_size(8 + 8 * 27);
  if (one < 16 || subcommands < 224 ||
      subcommands > (SIZE_MAX - 121616) / 2 ||
      !actql_command_reference_growth(1, &singleton_growth) ||
      !actql_command_reference_growth(137, &fixed_growth) ||
      !actql_command_reference_growth(arguments, &input_growth)) return false;
  /* Input bounds make the fixed coefficients safe before their checked sum.
   * MEMSYS5/Read/platform quantities are not operands in this managed volume. */
  size_t error_length = storage + 2 * 95609 + 131747 + 21;
  size_t terms[] = {
    765952 + 16,                /* retained startup plus check-verdict Ref */
    121616 + 2 * subcommands,   /* constructor without tuple/capture overlap */
    32 * (1080 + 2 * arguments), /* reference Array objects, once */
    607 * fixed_growth,
    (arguments + 6) * one,
    (54 + 268) * singleton_growth,
    6 * input_growth,
    474288,                    /* parser Map/Set and all backing generations */
    142080 + 320 * arguments,   /* tuples, including constructor tuples */
    975424 + 768 * arguments,   /* captures/iterators/MutLocal */
    2563488 + 192 * arguments,  /* other records, including argv Array/owner */
    12 * storage + 128 * arguments,
    21267034,                   /* help text and original builders */
    99360,                      /* suggestion rows and original StrPair */
    8 * actql_command_builder_volume(error_length) +
      2 * actql_command_builder_volume(11),
    6 * error_length + 32,       /* terminal UTF8 buffer */
    3 * 131747 + 32              /* help newline-trim copy */
  };
  size_t total = 0;
  for (size_t i = 0; i < sizeof(terms)/sizeof(terms[0]); i++)
    if (!actql_command_volume_add(&total, terms[i])) return false;
  for (size_t i = 0; i < 4; i++) {
    if (argv_classes[i] <= 0 ||
        !actql_command_volume_add(&total, (size_t)argv_classes[i])) return false;
  }
  *out = total;
  return true;
}
#endif
#endif
