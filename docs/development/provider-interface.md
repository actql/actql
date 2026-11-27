# Provider compiler interface references

The private compiler representation belongs to the single template and generator
in `scripts/templates/js-compiler-binding.mts` and
`scripts/generate-js-compiler-bindings.mjs`. Independently installed Providers use
byte-identical local copies. Their original-materials generator checks those
copies before checking its own generated consumers. No opaque value is rebuilt
by serialization, and no public wire field is interpreted by these helpers.

The Provider consumers retain their own error codes, failure causes and original
cleanup handles. A pair constructor replaces one existing pair object with one
pair object; this unit adds no sparse-field temporary record. Reference Option
and Unit Option are not generalized to diagnostic enum tags.

| Attribute | Existing authority and executable reference |
| --- | --- |
| Responsibility | `src/model_execution/physical_call_request.mbt`; Provider `_internal/model-port.mjs`: `start`, `poll`, `cleanup` |
| Inputs/outputs | `adapters/host-common/model-original-materials.mts.in`: `admitHTTPOriginalMaterials`; HTTP `original-chat-request.mjs`: `prepareOriginalHttpChatRequest`; registered SDK `model-port.mts`: `createAdmittedRegisteredSdkPreflight` |
| Identity | `packages/provider-http/original-materials.test.mjs`: `actual HTTP Common readers`; `adapters/host-node/infer-original-http-common.test.mjs`: separate equal profile refusal |
| Ownership | `src/model_execution/raw_capture_save.mbt`; `adapters/host-node/infer-original-multi-call-store.test.mjs`; Provider `_internal/model-port.mjs`: `rawCaptureBinder`, `cleanupRaw` |
| Synchronization | `packages/provider-http/model-port.test.mjs`; `packages/provider-ai-sdk/model-port.test.mjs`; SDK `_internal/native-decision-preflight.mjs`: `advance` |
| Failure | Provider `_internal/model-port.mjs`: `failure`, `reconcileRaw`; `packages/provider-ai-sdk/model-port-retirement.test.mjs`: `failed save` |
| Cancellation | Provider `_internal/model-port.mjs`: `abort`, `cleanup`; `packages/provider-http/model-port.test.mjs`: `cancellation` |
| Resources | Provider `_internal/model-port.mjs`: `requestLimits`, `responseLimits`; SDK `_internal/model-port.mts`: `projectionLimits`; SDK `model-port-retirement.test.mjs` |
| Extension | `scripts/generate-js-compiler-bindings.mjs`: `generateCompilerBindings`; `scripts/generate-model-original-materials.mjs`; `scripts/provider-entrypoints.test.mjs` |
| Verification | `scripts/js-compiler-binding-runtime.test.mjs`; `scripts/model-original-materials.test.mjs`; HTTP `original-materials.test.mts`, `model-port.test.mts`; SDK `admitted-native-decision.test.mjs` |

These references are review/discovery inputs, not a second operation contract or
an execution receipt. Actual Common/Host tests, controlled SDK/HTTP fixtures,
compiler probes and public Provider execution have separate qualifications.
No new capability, authority, numerical profile or public Provider acceptance is
established by moving compiler access into the generated binding.
