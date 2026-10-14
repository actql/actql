#if !defined(__APPLE__) || !defined(__aarch64__)
#error "This unadopted image candidate targets Darwin arm64 only"
#endif

#include "owned_capacity.h"
#include <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <stdbool.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static bool same_file(const struct stat *before, const struct stat *after) {
    return before->st_dev == after->st_dev && before->st_ino == after->st_ino &&
           before->st_size == after->st_size &&
           before->st_mtimespec.tv_sec == after->st_mtimespec.tv_sec &&
           before->st_mtimespec.tv_nsec == after->st_mtimespec.tv_nsec &&
           before->st_ctimespec.tv_sec == after->st_ctimespec.tv_sec &&
           before->st_ctimespec.tv_nsec == after->st_ctimespec.tv_nsec;
}

int actql_native_owned_capture_image_fd(actql_owned_capacity *lease, int fd,
                                        size_t expected_bytes, size_t maximum_bytes,
                                        const unsigned char digest[32], void **out) {
    if (lease == NULL || actql_native_owned_current() != lease || fd < 0 ||
        digest == NULL || out == NULL || *out != NULL || expected_bytes == 0 ||
        expected_bytes > maximum_bytes || expected_bytes > PTRDIFF_MAX)
        return ACTQL_OWNED_INVALID;
    int flags = fcntl(fd, F_GETFL);
    if (flags < 0 || (flags & O_ACCMODE) != O_RDONLY)
        return ACTQL_OWNED_INVALID;
    struct stat before;
    if (fstat(fd, &before) != 0) return ACTQL_OWNED_PHYSICAL_FAILURE;
    if (!S_ISREG(before.st_mode) || before.st_size <= 0 ||
        (uint64_t)before.st_size != (uint64_t)expected_bytes)
        return ACTQL_OWNED_IMAGE_MISMATCH;

    int status = actql_native_owned_allocate(lease, expected_bytes, 1, out);
    if (status != ACTQL_OWNED_OK) return status;
    /* Publish the cleanup pointer before another physical operation can fail.
     * Its caller must not deserialize unless the final status is OK. */
    void *scratch = NULL;
    status = actql_native_owned_allocate(lease, sizeof(CC_SHA256_CTX),
                                         _Alignof(CC_SHA256_CTX), &scratch);
    if (status != ACTQL_OWNED_OK) return status;
    CC_SHA256_CTX *checksum = scratch;
    if (CC_SHA256_Init(checksum) != 1) {
        status = ACTQL_OWNED_PHYSICAL_FAILURE;
        goto cleanup;
    }
    size_t offset = 0;
    while (offset < expected_bytes) {
        /* Preserve the existing SDK's 65536-byte read quantum. No whole-file
         * Python bytes, ctypes copy, new input limit or JIT fallback. */
        size_t remaining = expected_bytes - offset;
        size_t count = remaining < 65536 ? remaining : 65536;
        unsigned char *target = (unsigned char *)*out + offset;
        ssize_t read_bytes = pread(fd, target, count, (off_t)offset);
        /* Interrupted/failed reads fail explicitly. Do not add an unbounded
         * retry loop or silently accept a truncated image. */
        if (read_bytes <= 0 || (size_t)read_bytes > count ||
            CC_SHA256_Update(checksum, target, (CC_LONG)read_bytes) != 1) {
            status = ACTQL_OWNED_PHYSICAL_FAILURE;
            goto cleanup;
        }
        offset += (size_t)read_bytes;
    }
    unsigned char extra;
    ssize_t tail = pread(fd, &extra, 1, (off_t)expected_bytes);
    struct stat after;
    if (tail < 0 || fstat(fd, &after) != 0) {
        status = ACTQL_OWNED_PHYSICAL_FAILURE;
        goto cleanup;
    }
    unsigned char actual[CC_SHA256_DIGEST_LENGTH];
    if (CC_SHA256_Final(actual, checksum) != 1) {
        status = ACTQL_OWNED_PHYSICAL_FAILURE;
        goto cleanup;
    }
    if (tail != 0 || !same_file(&before, &after) ||
        memcmp(actual, digest, CC_SHA256_DIGEST_LENGTH) != 0) {
        status = ACTQL_OWNED_IMAGE_MISMATCH;
        goto cleanup;
    }
    status = actql_native_owned_seal_readonly(lease, *out);

cleanup:
    /* A failed retirement stays in the same holding's pending extent. The
     * original LocalCore/lease cleanup must retry it, not report success. */
    if (actql_native_owned_retire(lease, scratch) != ACTQL_OWNED_OK)
        status = ACTQL_OWNED_PHYSICAL_FAILURE;
    return status;
}
