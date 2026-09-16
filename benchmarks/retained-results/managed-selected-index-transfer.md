# Selected measurement index transfer

The new bounded selection preparation copies the exact occurrence metadata for
unchanged/copied output columns into an independent output index. Row-map input
is defensively copied before any liveness callback; duplicate/out-of-range
occurrences and incompatible all-row/permutation shapes remain rejected.
Metadata copy/traversal work and output cell count have explicit limits.

An adopted Host verifier must still establish actual execution, demanded
expressions, order/failure preservation and the selected output generation.
Preparing this metadata never certifies that selection executed. New computed
columns remain unsupported by this copy-only issuer and require their own
validation/measurement path, not fabricated inherited facts.

The issuance opportunity is consumed before callbacks, including installation
failure. Successful verification attaches the independent index to the ordinary
managed output receipt; failed verification, cancellation or lost input cannot
publish it. Logical output charges are enforced by the existing issuer. The
resulting receipt stores neither the original plan nor the source index array.
Temporary preparation handles still belong to the Host and must be released;
this is not a claim that all production ownership cleanup is finished.

The through-Core fixture completes a take/projection output, retains it
independently, invalidates the original input and binds another checked
consumer. That consumer obtains selected measurements twice from the new
receipt. This establishes repeated metadata reuse across completion, not
native execution of a new multirow selection pipeline.

Native producer/selection wiring, computed-column index merging, Host physical
metadata memory reservation and the full large-case performance gates remain
outstanding. No old identity preimage, contract pin, baseline or acceptance
threshold changed.

Verification: execution_relation passed 438 tests on each of JS, Wasm and
Native; native Compute/manifest tests passed six cases. Strict JS checking also
passed after making two fixture assertions explicit without changing their
exported Result ABI. These results do not establish large-case performance.
