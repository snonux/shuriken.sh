# Publishing

To publish generated output, configure destinations and run `shuriken --sync`.

## `SYNC_DESTINATIONS`

`SYNC_DESTINATIONS` must be a Bash array, even for a single destination:

```sh
SYNC_DESTINATIONS=(
    admin@fishfinger.buetow.org:/var/www/htdocs/example.org/
    admin@blowfish.buetow.org:/var/www/htdocs/example.org/
)
```

A scalar string is rejected with an error, since word-splitting would break
destinations that contain spaces (for example
`SYNC_DESTINATIONS=( '/path/with spaces/' )` is the correct spelling).

`--sync` validates that `SYNC_DESTINATIONS` contains at least one destination and
that rsync is installed.

## Overriding destinations per run

Pass `--sync-destination DEST` one or more times with `--sync` to override the
configured destinations for that run only:

```sh
shuriken --sync --sync-destination user@host:/var/www/htdocs/example.org/
```

## The rsync command

`--sync` runs, for each destination:

```sh
rsync -av --delete "$DIST_DIR/" "$destination"
```

The trailing slash on `DIST_DIR/` means the generated **contents** are copied
into the target directory. Set `SYNC_DELETE=no` or pass `--no-sync-delete` to
omit `--delete`.

`--sync` reads `./shuriken.conf` by default; pass `--config PATH` to select a
different config file.