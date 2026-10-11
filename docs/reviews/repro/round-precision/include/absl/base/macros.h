// SPDX-License-Identifier: Apache-2.0
// Minimal ActQL test-harness shim; upstream assertions remain enabled.
#pragma once
#include <cassert>
#define ABSL_HARDENING_ASSERT(condition) assert(condition)
