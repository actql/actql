// SPDX-License-Identifier: Apache-2.0
// Minimal ActQL test-harness shim; no numerical operations are replaced.
#pragma once
#include <cstring>
namespace absl {
template <typename To, typename From>
To bit_cast(const From& value) {
  static_assert(sizeof(To) == sizeof(From));
  To out;
  std::memcpy(&out, &value, sizeof(out));
  return out;
}
}
