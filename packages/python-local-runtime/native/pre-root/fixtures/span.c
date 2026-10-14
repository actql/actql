/* Independent native cases prepared for a later explicitly allocated window.
 * This does not execute Wasmtime, choose a product profile or create a Core Root. */
#include <stdio.h>
#include "../owned_capacity.c"

#define CHECK(name, condition) do { \
    discovered++; \
    if (!(condition)) { \
        fprintf(stderr, "native span case failed: %s\n", name); \
        return 1; \
    } \
    passed++; \
} while (0)

int main(void) {
    int discovered = 0, passed = 0;
    long page_value = sysconf(_SC_PAGESIZE);
    if (page_value <= 0) return 2;
    size_t page = (size_t)page_value;
    if (page > SIZE_MAX / 64) return 2;
    /* Independent fixture region, not an adopted runtime/Host limit. */
    size_t fixture_bytes = page * 64;
    unsigned char recipe[32] = {0};
    actql_owned_capacity *original = NULL, *foreign = NULL;
    uint64_t capacity = 0;
    void *first = NULL, *second = NULL, *other = NULL;
    CHECK("acquire original", actql_native_owned_acquire(fixture_bytes, 7, recipe, &original) == 0);
    CHECK("original full capacity", actql_native_owned_capacity_bytes(original, &capacity) == 0 && capacity == fixture_bytes);
    CHECK("untransferred membership denied", actql_native_owned_enter(original) == 0 &&
          actql_native_owned_contains_live_span(original, original, 1) == -1 &&
          actql_native_owned_leave(original) == 0);
    CHECK("original transfer", actql_native_owned_transfer(original, 7, recipe) == 0);
    CHECK("enter original", actql_native_owned_enter(original) == 0);
    CHECK("first extent", actql_native_owned_allocate(original, page * 2, 1, &first) == 0);
    CHECK("second extent", actql_native_owned_allocate(original, page, 1, &second) == 0);
    CHECK("interior exact end", actql_native_owned_contains_live_span(original,
          (unsigned char *)first + page + 17, page - 17) == 0);
    CHECK("adjacent extents cannot be combined", (unsigned char *)second == (unsigned char *)first + page * 2 &&
          actql_native_owned_contains_live_span(original, (unsigned char *)first + page * 2 - 1, 2) == -1);
    CHECK("control region is not a child", actql_native_owned_contains_live_span(original, original, 1) == -1);
    CHECK("foreign allocation", actql_native_owned_acquire(fixture_bytes, 8, recipe, &foreign) == 0 &&
          actql_native_owned_allocate(foreign, page, 1, &other) == 0);
    CHECK("foreign span denied", actql_native_owned_contains_live_span(original, other, page) == -1);
    CHECK("retire exact child", actql_native_owned_retire(original, first) == 0 &&
          actql_native_owned_contains_live_span(original, first, page) == -1);
    capacity = 0;
    CHECK("retirement does not shrink region", actql_native_owned_capacity_bytes(original, &capacity) == 0 && capacity == fixture_bytes);
    CHECK("other live child remains", actql_native_owned_contains_live_span(original, second, page) == 0);
    CHECK("leave and pending close", actql_native_owned_leave(original) == 0 &&
          actql_native_owned_try_close(&original) == -3 && original != NULL);
    capacity = 0;
    CHECK("pending close retains full capacity", actql_native_owned_capacity_bytes(original, &capacity) == 0 && capacity == fixture_bytes);
    CHECK("closing refuses new scope", actql_native_owned_enter(original) == -3);
    CHECK("original physical release", actql_native_owned_retire(original, second) == 0 &&
          actql_native_owned_try_close(&original) == 0 && original == NULL);
    CHECK("foreign physical release", actql_native_owned_retire(foreign, other) == 0 &&
          actql_native_owned_try_close(&foreign) == 0 && foreign == NULL);
    capacity = 0;
    CHECK("null released holding denied", actql_native_owned_capacity_bytes(original, &capacity) == -1 && capacity == 0);
    if (discovered != 21 || passed != 21) return 3;
    printf("{\"native_span_cases\":21,\"passed\":21,\"wasmtime\":0,\"public_e2e\":0}\n");
    return 0;
}
