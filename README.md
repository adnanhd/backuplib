# backuplib

Shared shell library of [archivectl](https://github.com/adnanhd/archivectl) (Borg archives) and [snapshotctl](https://github.com/adnanhd/snapshotctl) (rsync hard-link snapshots), used as their `lib` submodule:

```sh
git submodule add git@github.com:adnanhd/backuplib.git lib
```

A tool's dispatcher sets `PROG`, `CONFIG` and `SCRIPT_PATH`, defines `usage`, and sources `lib/common.sh`.

## common.sh

- `die`, `say`: a message on stderr; `say` also appends it to the log `open_log` opened under `$XDG_STATE_HOME/PROG/`, mode 600 in a 700 directory
- `enter_repo`: change into the nearest directory holding `CONFIG` and read it (`find_repo_root`, `require_config`)
- `write_config`: write a configuration with every value quoted for the shell (`printf %q`)
- `parse_dry_run`, `parse_select_options`, `reject_options`: option parsing for `-n`, the `list` filters and commands without arguments
- `select_records`: keep the records `id<TAB>date...` older or newer than N days, then the first or last N
- `read_ids`, `require_known`: the ids `delete` reads on stdin, and the check that each names something
- `rsync_records`, `compare_trees`: one record `path<TAB>added|removed|modified` per path an rsync dry run would change, or whose content or type differs between two trees; a backslash, tab or newline in a path is written `\\`, `\t` or `\n` (`AWK_ESCAPE`)
- `create_in_parent`: run `create` in the repository above this one, if any, and return its status
- `build_exclude_params`: `--exclude` flags for borg or rsync
- `safe_name`, `storage_for`: a path as one file name, `%` written `%25`, `/` `%2F` and a newline `%0A`, so that two paths never share one; `storage_for` refuses when storage exists under the name hlinkctl and dedupctl used (`old_safe_name`), which two paths can share
