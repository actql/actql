// SPDX-License-Identifier: Apache-2.0
// Branch prediction has no numerical effect in this reference-verification shim.
#pragma once
#define ABSL_PREDICT_FALSE(condition) (condition)
