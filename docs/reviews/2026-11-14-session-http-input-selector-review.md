# Local Host HTTP Request input selector review

This finite successor covers only `src/client_local_host/moon.pkg` at
`45906df586b5439ac03235e3b1a9b8f1576b98ec`: 11019 bytes,
SHA-256 `24a013cbcf540ebf0c47fba54b93516ad0ef498549a669237e6710f2232ce778`.
Those descriptor bytes remain exact at the reviewed integrated source
`bdce424514605b0af786db48b3f9154a06b5a527`.
The complete previous descriptor at
`bad3df76f10ae158ab579b33a4b9d1232eee58cf` remains retained: 10957 bytes,
SHA-256 `73ce0addad1ed0fee070cd0ae738e91dc2e857c877e14e57951f4de4392cdcfb`.

Removing exactly this 62-byte literal selector reconstructs the prior descriptor
byte for byte:

```text
    "preparation_request_http_input_js_wbtest.mbt": [ "js" ],
```

All imports, aliases, supported targets, previous selectors and other options
remain unchanged. The selected whitebox source contains three existing tests:
actual long Text geometry retained on the same Request, foreign/current/policy
and failed-growth cleanup, and a smaller original-parent refusal before native
tree construction. The tests use the existing Request parent fixture, JSON
preparation, original Resource/Ledger and cleanup methods. They do not perform
HTTP, open a Host, resolve secrets, introduce a foreign function or execute a
build hook. This review does not execute the MoonBit tests or certify their
product, resource backing, normal artifact or runtime behavior.

The existing `literal-target-selectors-with-bound-source-membership` rule remains
restricted to JS and the unchanged pinned toolchain. Only the exact successor
digest is current. All earlier descriptor preimages and their original tests
remain retained; none is silently relabelled as this successor. Selector target,
file, import, option, path or toolchain changes still refuse or independently
rekey. The complete immediate source membership, bytes, modes and transitive
imports remain inputs. No general target-selector parser, wildcard review,
proof completeness change or reuse authorization is added.
