# backuplib

Shared shell library of [archivectl](https://github.com/adnanhd/archivectl) (Borg archives) and [snapshotctl](https://github.com/adnanhd/snapshotctl) (rsync hard-link snapshots), used as their `lib` submodule:

```sh
git submodule add git@github.com:adnanhd/backuplib.git lib
```

A tool's dispatcher sets `PROG`, `CONFIG` and `SCRIPT_PATH`, defines `usage`, and sources `lib/common.sh`; each command's module defines `show_help`, which `-h` prints.

## common.sh

- `die`, `say`: a message on stderr; `say` also appends it to the log `open_log` opened under `$XDG_STATE_HOME/PROG/`, mode 600 in a 700 directory
- `enter_repo`: change into the nearest directory holding `CONFIG` and read it (`find_repo_root`, `require_config`)
- `write_config`: write a configuration with every value quoted for the shell (`printf %q`)
- `parse_select_options`, `reject_options`: option parsing for the `list` filters and `--human-readable` (`HUMAN=true`), and for commands without arguments
- `size` (`AWK_HUMAN`): an awk function that writes a byte count as a record shows it, in K, M, G, T as `du -h` does when `HUMAN=true`
- `select_records`: keep the records `id<TAB>date...`, the date `YYYY-MM-DD HH:MM:SS`, older or newer than N days, then the first or last N
- `read_ids`: the ids `delete` is given, or else reads on stdin; both at once, or neither with a terminal on stdin, end the run with status 2
- `escaped`, `rsync_records`, `compare_trees`: one record `path<TAB>added|removed|modified` per path an rsync dry run would change, or whose content or type differs between two trees; a backslash, tab or newline in a path is written `\\`, `\t` or `\n` (`AWK_ESCAPE`)
- `create_in_parent`: run `create` in the repository above this one, if any, and return its status
- `build_exclude_params`: the patterns to leave out (`EXCLUDE_PATTERNS`) and their `--exclude` flags for borg or rsync
- `safe_name`, `storage_for`, `default_root`: a path as one readable file name, the leading `/` dropped and every other `/` written `__` (`/home/adhd/test` is `home__adhd__test`), with `%`, a newline, an `_` at either end of a part or next to another `_`, and a leading `!` written `%25`, `%0A`, `%5F` and `%21`, so that two paths never share one; a name over 199 bytes is cut to 135 bytes, `~` and the SHA-256 of the path. `storage_for` is the storage path under a root named by `safe_name`. `default_root` is `/data/backup/<kind>` when `/data` is a mount point.
