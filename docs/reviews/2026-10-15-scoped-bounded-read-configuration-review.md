# Exact scoped bounded-read configuration review

Reviewed author Source: `8c0870eb1ab4fdad1ad3e5c436f60dda71c49760`.
The only manifest addition is the Native whitebox predicate
`"scoped_cleanup_native_wbtest.mbt": [ "native" ]`, introduced at
`ea73884358631b4c6de7ef89d8db2515a9db6788` with sole genuine parent `7b602b9152720cb1264a6209b7c130d14f7830eb`.
The Git blob is `e0e7725e473f55c79396eb12aa0f2ea4fbbdcd2c` (mode100644);
its SHA256 is `383a532bbbee2be32d5c4c7ccab853fa392892667451095a7b553c495d5c578d`. The exact Git blob identity is also checked by the
integration record; source bytes, not this prose, determine the digest.
Removing that one literal line restores the entire parent manifest, SHA256
`d3226436c6183cae948253152b6f49c386881ae9f3653c7e970183d7d1b99f57`, also identical to the earlier `f089341cd29c2989c1e462333ca2e382fc9c9e55`
manifest. The test retains this independent historical whole preimage.

This is the existing `literal-native-options-with-bound-source-membership`
rule. Imports, aliases, native stub, link flags, supported targets, hooks and
the two old predicates are unchanged. The new whitebox is an immediate keyed
source member. Its physical close followed by loss of observation is a sticky
Reader uncertainty test, not an observed kernel EIO. It retains the original
parent Root and never closes the consumed integer descriptor again. The scoped
entry uses the existing current read context without creating or granting one.

Only this exact JS configuration digest and its review revision/reference are
refreshed. The other seventeen Native pins, separate foreign-library identity,
toolchain, parser, validator, wrong-path/target/unknown-option refusals and full
source membership remain unchanged. No namespace or general permission grows.

Original Native4 and JS5 are source-qualified finite cases, not whole managed
caller acceptance. The separate active-cleanup allocator finding and #2176
repair remain outside this unit. Normal numeric/profile, managed positive,
Cloud and public acceptance remain unverified. Configuration identity does not
prove Native correctness, allocator accounting, GC or physical retirement.
