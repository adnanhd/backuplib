# backuplib

Shared shell library of [archivectl](https://github.com/adnanhd/archivectl) (Borg archives) and [snapshotctl](https://github.com/adnanhd/snapshotctl) (rsync hard-link snapshots), used as their `lib` submodule:

```sh
git submodule add git@github.com:adnanhd/backuplib.git lib
```

A tool's dispatcher sets `PROG` (its name), `CONFIG` (its configuration file), `IGNORE` (its ignore file) and `SCRIPT_PATH`, defines `usage`, and sources `lib/common.sh`; each command's module defines `show_help`, which `-h` prints. The library has no tests of its own: the pytest suites of archivectl and snapshotctl run it through the tools.

## common.sh

- `die`, `say`: a message on stderr; `say` also appends it to the log `open_log` opened, `$XDG_STATE_HOME/PROG/<repository root as safe_name>.log`, mode 600 in a 700 directory
- `enter_repo`: change into the nearest directory holding `CONFIG` and read it (`find_repo_root`, `require_config`)
- `write_config`: write a configuration with every value quoted for the shell (`printf %q`)
- `parse_select_options`, `reject_options`: option parsing for the `list` filters and `--human-readable` (`HUMAN=true`), and for commands without arguments
- `size` (`AWK_HUMAN`): an awk function that writes a byte count as a record shows it, in K, M, G, T as `du -h` does when `HUMAN=true`
- `select_records`: keep the records `id<TAB>date...`, the date `YYYY-MM-DD HH:MM:SS`, older or newer than N days, then the first or last N
- `read_ids`: the ids `delete` is given, or else reads on stdin; both at once, or neither with a terminal on stdin, end the run with status 2
- `escaped`, `rsync_records`, `compare_trees`: one record `path<TAB>added|removed|modified` per path an rsync dry run would change, or whose content or type differs between two trees; a backslash, tab or newline in a path is written `\\`, `\t` or `\n` (`AWK_ESCAPE`)
- `create_in_parent`: run `create` in the repository above this one, if any, and return its status
- `build_exclude_params`: the patterns to leave out (`EXCLUDE_PATTERNS`) and their `--exclude` flags (`EXCLUDE_PARAMS`) for borg or rsync, from the lines of the `IGNORE` file in the repository root (`ignore_lines`), or `.cache`, `tmp` and `__pycache__` without one; `ignore_pattern` reads a line as `.gitignore` does: no `/` matches at any depth, a `/` at the start or inside matches from the top, a trailing `/` is dropped for borg, and a borg line with a style prefix (`sh:`, `fm:`, `re:`, `pp:`, `pf:`) is passed as it is
- `safe_name`, `storage_for`, `default_root`: a path as one readable file name, the leading `/` dropped and every other `/` written `__` (`/home/adhd/test` is `home__adhd__test`), with `%`, a newline, an `_` at either end of a part or next to another `_`, and a leading `!` written `%25`, `%0A`, `%5F` and `%21`, and `/` itself `%2F`, so that two paths never share one; a name over 199 bytes is cut to 135 bytes, `~` and the SHA-256 of the path. `storage_for` is the storage path under a root named by `safe_name`. `default_root KIND OLD` is `/data/backup/KIND` when `/data` is a mount point, else `OLD`.

## On this machine

The checkout is `~/src/personal/backuplib`; `~/src/personal/dedupctl/lib` (archivectl) and `~/src/personal/hlinkctl/lib` (snapshotctl) are its submodule copies, and `make install` of each tool copies `common.sh` into `~/.local/lib/<tool>/`.
