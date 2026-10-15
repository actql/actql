# Exact scoped filesystem acquisition configuration review

Reviewed author Source: `e66017830a96128dbf1226661533b524baf8652d`.
Two product selectors were introduced at
`4a62dc0cfc30be562405d2fc31bdfa1556bfae9c`, whose sole genuine parent is
`8d93c89d48e5991d9a890648db023a4336ff8979`. Two mandatory refusal-WB
selectors followed at `6db6f2ce88454b80c21dbb3f5fb0bb9e7127d003`, whose sole
parent is `380473dc6794b09bd561946aa8c7d9c2bcd9d1b4`. Each whole preimage is
retained and stripped in that exact order. The final author has the same
manifest bytes as 6db6. Its exact Git blob is
`b8ca1dd7abff97fad56b57cea762d02b06c7725f` (mode100644), SHA256
`98c10419328d72de804dd3e65aea84346db093880edce96cd679e6fbc55a6460`.

This extends only the existing
`literal-native-options-with-bound-source-membership` review. Removing these
four new literal selectors restores the exact parent manifest, including the
previous read-layout selectors and all imports/stub/target settings:

```text
"scoped_read_native.mbt": [ "native" ]
"scoped_read_unsupported.mbt": [ "not", "native" ]
"scoped_read_unselected_native_wbtest.mbt": [ "native" ]
"scoped_read_unsupported_wbtest.mbt": [ "not", "native" ]
```

The parent manifest SHA256 remains historical
`bb816061434a3d23d1446366e137d3e64539cd0ef6ae191bea81f71f93400a86`.
The read-layout and earlier six-selector introductions keep their independent
whole-byte assertions; no historical fixture or old pin is resealed.

The new sources are immediate keyed members. Native uses the existing Root,
Reader and same current read context. The private constructor result preserves
the original failure Root/Reader and close dispatch returns context use only
after the original physical Owner ACK. JS/Wasm explicitly refuse unsupported
physical acquisition. The imports, aliases, supported targets, native stub and
old selectors are unchanged. No hook, external resolver, new Owner, allocation
grant or configuration kind is introduced. Every C/include/interface/member
byte and mode remains independently keyed.

Only this exact JS verification digest is refreshed. The other seventeen
Native digests, separate foreign-library identity, literal parser, rule,
validator, toolchain digest and wrong-target/path/unknown-option rejection are
unchanged. The toolchain.json SHA256 stays
`8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a`.
Source membership/import selection is not Native correctness or public proof.

The author's C3 positive evidence is a physical same-provider fixture, while
Native2 and JS2 are refusal cases. Whole managed positive read/funding,
normal profile and Cloud/public acceptance remain unverified. The separate
RO5KRV combined Core diagnostic omitted ACTQL_SCOPED_READ_ALLOCATOR; its
failure is preserved as a diagnostic recipe defect, not relabeled as a defect
of the already reviewed derived allocator or a positive product result.
