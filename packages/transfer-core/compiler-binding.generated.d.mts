export declare const runtimeTag: (value: unknown) => unknown;
export declare const runtimeIsOk: (value: unknown) => boolean;
export declare const runtimeIsOkRequired: (value: unknown) => boolean;
export declare const runtimeIsError: (value: unknown) => boolean;
export declare const runtimeIsBoxedSome: (value: unknown) => boolean;
export declare const runtimeIsBoxedNone: (value: unknown) => boolean;
export declare const runtimeUnboxedReferenceOption: <T>(value: T) => T;
export declare const runtimeUnboxedUnitOptionPresent: (value: unknown) => boolean;
export declare const runtimeField: (value: unknown, index: number | string) => unknown;
export declare const runtimeOptionalField: (value: unknown, index: number | string) => unknown;
export declare const runtimePair: <A, B>(first: A, second: B) => {
    _0: A;
    _1: B;
};
export declare const runtimeTriple: <A, B, C>(first: A, second: B, third: C) => {
    _0: A;
    _1: B;
    _2: C;
};
export declare const runtimeTupleFromFields: (fields: Record<string, unknown>) => Record<string, unknown>;
export declare const runtimeFailure: <T>(cause: T) => {
    $tag: 0;
    _0: T;
};
