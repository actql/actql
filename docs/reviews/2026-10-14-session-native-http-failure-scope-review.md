# Native HTTP construction custody: target and configuration review

Reviewed implementation Source `aabe52c48759ff41aa3210dda2ff162814c6f089`
preserves original author `5374dfacf4020a892e1f6d4367342e8ed00399b6`
and normally adopts main `e7e618837f80f64a1096c99f063b73433018be4b`.
The existing constructor configuration and Store failure scope reviews remain
historical. Other reviewed manifests keep their exact existing digests.

The original failed Library/Client state and cleanup methods are concrete only
on Native, where their constructors run. Shared error alternatives and public
nominal signatures remain shared. Unsupported targets have opaque failure
types and refusing methods; no object is acquired or cleanup acknowledged there.
No public fields/constructor, warning suppression, authority or alternate Owner
is added. The original Native method and runtime bodies are preserved under the
pinned formatter. The original C stub remains unchanged by this placement fix.

Client metadata cleanup returns the same residual Library. It does not confirm
global libcurl or resolver/runtime retirement. Failed global initialization and
unconfirmed unload remain pending without a replacement load or repeated close
of a consumed handle. The existing normal numeric profile remains None.

| Manifest | Exact reviewed SHA256 | Git blob, mode100644 |
| --- | --- | --- |
| `src/platform_native/http_client/moon.pkg` | `3cdde0301c89f7a3a2c79aca654cfb4c48b49751847561c27a8e88232e099baf` | `80287cd4726c447b3d3dbd3e4d7c207627b27f41` |

The only manifest change is the literal Native predicate
`"construction_custody_native_wbtest.mbt": [ "native" ]`. Removing it restores
the entire previous main manifest. Normal/WB imports and aliases, supported
targets, native stub, linker settings, all other predicates, and absence of
build hooks/external resolvers remain exact. The pinned JS path cannot invoke
the Native stub/linker through this predicate. Every selected source member,
mode and body remains a separately bound input.

Refresh this exact digest and implementation reference under the existing
`literal-native-options-with-bound-source-membership` rule. Keep its target,
toolchain and identifier syntax unchanged. Unknown path/digest/option, other
target/toolchain and full-source fallback refusals remain unchanged. A matching
digest establishes configuration identity, not compiler/OS correctness or
runtime execution. Additive API generation, matching-target tests and consuming
type checks provide their own exact-source evidence when actually executed.

No assembly equivalence, fresh Native execution, installed/public acceptance,
normal funding, resource release or Provider request follows from this review.
