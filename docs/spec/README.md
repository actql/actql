# ActQL specification family

Adopted specifications. These documents define the design; implementation conformance is established separately. Edit the owner documents listed below.

- [language](language.md): source, types, expressions, operations, nest, effect-intents, canonical-semantics, observable-boundaries.
- [execution](execution.md): capture, admission, run-identity-model, checkpoint-invariants, replay, effect-outcomes, reconciliation.
- [contracts](protocols/contracts.md): catalog, sourceview, mapping, command, model-task, check-environment, lock, static-plan-artifacts, diagnostics.
- [artifacts](protocols/artifacts.md): result-artifact, result-manifest, result-delivery, store-admission, availability-leases.
- [run](protocols/run.md): run-wire, checkpoint-wire, resolution-wire, preview-wire, apply-receipt, reconciliation-receipt.
- [discovery](protocols/discovery.md): publication-snapshot, describe, list, read, cursor, disclosure.
- [collection](protocols/collection.md): collection-definition, collection-execution, accounting, collection-evidence, coverage, integration-binding.
- [http](protocols/http.md): typed-http-binding, origins, redirects, ssrf, bounded-transfer.
- [run-graph](protocols/run-graph.md): finite-process-graph, typed-activation, attempt-lifecycle, cross-run-bindings.
- [conformance](conformance.md): claims, profile-dependencies, corpora, evidence, release-combinations.

Document versions, semantic contract CIDs, and release combinations are separate identities. Requirements are maintained in owner-local registries; the aggregate inventory is generated. Evidence is attached only to the exact requirement it verifies.

[Reference Host design](../design/reference-host.md) is informative.

The normative dependency list in each document specifies imported owner
requirements. Other cross-owner links navigate to protocol bindings or evidence;
they do not require implementing that entire protocol. Narrow schema/law
references are individually pinned in each owner's machine-contract section.
Conformance consumes the owners required by the claimed profiles, not vice versa.

Normative document imports are explicitly marked and versioned in the family
descriptor; machine imports pin individual artifact CIDs. The family checker
reports both separately from informative references.
