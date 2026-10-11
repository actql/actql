// SPDX-License-Identifier: Apache-2.0
// ActQL reference-verification harness for GoogleSQL's Apache-2.0 sources.
// Upstream numerical implementation: Copyright 2019 Google LLC.
// The supplied, hash-verified numerical source is included without modification.
#include <cassert>
#include <cfenv>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <type_traits>
#include <utility>
// Standard headers are loaded before selecting the portable upstream branch.
// This also prevents an ARM compiler's architecture macro from silently choosing
// FMA in the variant explicitly labeled Dekker. Numerical source stays unchanged.
#ifdef ACTQL_REFERENCE_DEKKER
#pragma push_macro("FP_FAST_FMA")
#pragma push_macro("__FMA__")
#pragma push_macro("__aarch64__")
#pragma push_macro("__CUDA_ARCH__")
#undef FP_FAST_FMA
#undef __FMA__
#undef __aarch64__
#undef __CUDA_ARCH__
#endif
#include "googlesql/common/round_decimal.cc"
#ifdef ACTQL_REFERENCE_DEKKER
#pragma pop_macro("__CUDA_ARCH__")
#pragma pop_macro("__aarch64__")
#pragma pop_macro("__FMA__")
#pragma pop_macro("FP_FAST_FMA")
#endif

static_assert(sizeof(double) == sizeof(std::uint64_t));
static_assert(std::numeric_limits<double>::is_iec559);
static_assert(std::numeric_limits<double>::digits == 53);

namespace {
std::uint64_t Bits(double value) {
  std::uint64_t out;
  std::memcpy(&out, &value, sizeof(out));
  return out;
}
double Value(std::uint64_t bits) {
  double out;
  std::memcpy(&out, &bits, sizeof(out));
  return out;
}
}

extern "C" std::uint64_t actql_reference_round(std::uint64_t bits, std::int64_t digits) {
  return Bits(googlesql::util_math::RoundDecimal(Value(bits), digits));
}
extern "C" std::uint64_t actql_reference_trunc(std::uint64_t bits, std::int64_t digits) {
  return Bits(googlesql::util_math::TruncDecimal(Value(bits), digits));
}
// Inclusion above keeps the original table in this translation unit. These
// accessors observe it without rewriting or independently calculating entries.
extern "C" std::uint64_t actql_reference_power_hi(std::int64_t digits) {
  return Bits(googlesql::util_math::kPowFiveDouble[digits + 323].hi());
}
extern "C" std::uint64_t actql_reference_power_lo(std::int64_t digits) {
  return Bits(googlesql::util_math::kPowFiveDouble[digits + 323].lo());
}
extern "C" int actql_reference_rounding_mode() { return std::fegetround(); }
extern "C" int actql_reference_nearest_mode() { return FE_TONEAREST; }
