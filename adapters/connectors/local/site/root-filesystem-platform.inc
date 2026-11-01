/* The only Local Files OS seams. All custody, bounds, locking, publication
 * ordering and cleanup stay in the shared descriptor implementation. */
static void local_fs_times(const struct stat *value, int64_t *modified_seconds,
    int64_t *modified_nanos, int64_t *changed_seconds, int64_t *changed_nanos) {
#if defined(__APPLE__)
  *modified_seconds = value->st_mtimespec.tv_sec; *modified_nanos = value->st_mtimespec.tv_nsec;
  *changed_seconds = value->st_ctimespec.tv_sec; *changed_nanos = value->st_ctimespec.tv_nsec;
#else
  *modified_seconds = value->st_mtim.tv_sec; *modified_nanos = value->st_mtim.tv_nsec;
  *changed_seconds = value->st_ctim.tv_sec; *changed_nanos = value->st_ctim.tv_nsec;
#endif
}
static int local_fs_rename(int directory, const char *source, const char *destination,
    bool overwrite) {
#if defined(__APPLE__)
  return renameatx_np(directory, source, directory, destination, overwrite ? 0 : RENAME_EXCL);
#elif defined(__linux__)
  /* No check-then-rename or link/unlink fallback: unsupported kernel/filesystem
   * no-replace semantics fail closed with the original errno. */
  return renameat2(directory, source, directory, destination, overwrite ? 0 : RENAME_NOREPLACE);
#else
  (void)directory; (void)source; (void)destination; (void)overwrite;
  errno = ENOTSUP; return -1;
#endif
}
