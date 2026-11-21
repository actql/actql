interface ResponseLimits {
    maxBytes: number;
    maxChunkBytes: number;
    maxChunks: number;
    observedHeaders?: readonly string[];
    maxHeaderBytes: number;
}
interface ReaderPort {
    read(): {
        done?: unknown;
        value?: unknown;
    } | PromiseLike<{
        done?: unknown;
        value?: unknown;
    }>;
    cancel?(): unknown;
    releaseLock(): void;
}
interface PhysicalResponse {
    status: number;
    headers: {
        get(name: string): unknown;
    };
    body: null | {
        getReader(): ReaderPort;
    };
}
export declare function fixedInferResponseLimits({ maxBytes, maxChunkBytes, maxChunks, observedHeaders, maxHeaderBytes, }: ResponseLimits): Readonly<ResponseLimits> & {
    observedHeaders: readonly string[];
};
export declare function readBoundedInferResponse(response: PhysicalResponse, inputLimits: ResponseLimits, signal?: AbortSignal): Promise<Readonly<{
    status: number;
    headers: readonly (readonly [string, string])[];
    body: Uint8Array<ArrayBuffer>;
    observedBytes: number | undefined;
    transportComplete: true;
    issue: undefined;
    readerRetirement: Promise<boolean>;
    retryReaderRetirement: () => Promise<boolean>;
}> | Readonly<{
    status: number;
    headers: readonly (readonly [string, string])[];
    body: Uint8Array<ArrayBuffer>;
    observedBytes: number | undefined;
    transportComplete: false;
    issue: string;
    readerRetirement: Promise<boolean>;
    retryReaderRetirement: () => Promise<boolean>;
}>>;
export {};
