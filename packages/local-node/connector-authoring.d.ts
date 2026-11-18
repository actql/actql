/** Validate bounded nonsecret GET declaration JSON using this package's shipped
 * Common codec. Returns the unchanged admitted JSON wire. This creates no Host,
 * Source, session, Account permission, execution or physical cleanup receipt.
 * A matching installed validator is required; no source/compiler fallback.
 */
export declare function validateRestReadDeclaration(readWire: string, cursorParameter?: string): string;
