---
spec_id: actql.protocol.http
status: adopted
version: actql/0.1
normative_dependencies: [actql.protocol.contracts, actql.protocol.artifacts]
---

# ActQL http

[Specification index](../README.md)

<!-- normative-import: actql.protocol.contracts actql/0.1 -->
<!-- normative-import: actql.protocol.artifacts actql/0.1 -->

This document owns typed-http-binding, origins, redirects, ssrf, bounded-transfer. It does not define other owners' wire protocols or a particular Host implementation. Cross-owner links outside the declared dependencies are informative navigation to protocol bindings or conformance evidence; they do not import those documents' requirements. Narrow machine contracts remain authoritative for their explicitly referenced values and envelopes.

<a id="http-transport"></a>

### HTTP Connector transport

`actql-http-transport/0.1` is a companion Connector profile, not ActQL source
syntax. A semantic SourceView or typed Command may declare an HTTP transport
binding that closes method, admitted origin, explicit auth mode, request and
response schema CIDs, typed path/query/header/body mapping, static bounded
GraphQL document identity when used, body media type, disjoint success/error
status sets, response row extraction, pagination termination, redirects,
byte/request/time limits, signed review attestation, and SSRF admission.

<!-- requirement-block: http-transport.a-checked-write-must-be-idempotent-or-provably-reconcilable stage-transport.product-6053b661e961 -->
Program-selected URLs, methods, arbitrary headers, cookies, raw secrets,
and `fetch(url, body)` are forbidden. A checked write MUST be idempotent or
provably reconcilable. A non-idempotent and non-reconcilable HTTP call is an
Opaque Task with visibly weaker guarantees, not a checked ActQL Effect.

<a id="stage-transport"></a>

### Stage acquisition and recovery transport

Typed adapters MUST retain logical request/slot/item correlation independently
of physical requests. Model transient retries and completion polls share finite
attempt, duration, cost and byte envelopes, including failed/lost responses.
Mutation uncertainty requires its declared reconciliation capability, not a
transport retry default. Artifact model transfer validates MIME, exact content,
scope and egress before dispatch and records transport evidence without exposing
raw HTTP or binary payloads as new Program authoring forms. Stamp insertion is
part of the approved request recipe and permission footprint, never a hidden
second write. Late responses cannot replace a sealed adopted model outcome.

<a id="machine-contracts"></a>

## Machine contracts

These exact schema/law references are owned here. Their identities do not include this document or another owner's aggregate contract.

<!-- requirement-block: machine-contracts.exact-artifacts -->
<!-- normative-code: law -->
```text
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/http_review_attestation sha256:78708b99a081b9916f63f36da8d740d4bd76e6b91c64cc834896be0361a12cae
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/http_read_transport sha256:9d1b94d787b76a5e9ef6714bf9d44bc9c5edd42e3f9f60ffa106c9bc4ecb525c
../../../spec/contracts/actql-production-profile-schemas.json#/schemas/http_write_transport sha256:22107bd89a3fe1e3d49637ca16e04056a5a6df3a4893c4447e15e00aff6569bb
```
