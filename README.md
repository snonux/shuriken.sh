# photoalbum

photoalbum is a minimal Bash script for Unix like operating systems (such as Linux) to generate static web photo albums.
The resulting static photo album is pure HTML+CSS (without any JavaScript!).

## Installation

Build and install the command, templates, and default config from a source
checkout with:

```
make
sudo make install
```

ImageMagick must also be installed. The script prefers the
modern `magick` command and falls back to `convert` when needed.

## Usage

```
photoalbum --init
photoalbum --generate [--config PATH] [OPTIONS]
photoalbum --clean [--config PATH] [OPTIONS]
photoalbum --version
```

* `--init` creates `./photoalbum.conf` in the current working directory from the
  default config. It refuses to overwrite an existing file.
* `--generate` builds the static album.
* `--clean` removes the configured output directory.
* `--version` prints the program version.
* `--config PATH` selects the config file for `--generate` or `--clean`.

When `--config PATH` is not provided, `--generate` and `--clean` read
`./photoalbum.conf`. If the file is missing, run `photoalbum --init` first.

The config file is a Bash file with assignments such as `INCOMING_DIR`,
`DIST_DIR`, `TEMPLATE_DIR`, `TITLE`, `HEIGHT`, `THUMBHEIGHT`, `MAXPREVIEWS`,
`SHUFFLE`, and `TARBALL_INCLUDE`.

Before generating, `photoalbum` validates the loaded config and command-line
overrides. It checks required values, positive integer settings, `yes`/`no`
settings, readable input and template directories, a writable output location,
and ImageMagick availability. Generation stops before writing album output when
validation fails.

The following long options override config values:

| Option | Config value |
| --- | --- |
| `--incoming PATH` | `INCOMING_DIR` |
| `--dist PATH` | `DIST_DIR` |
| `--template PATH` | `TEMPLATE_DIR` |
| `--title TEXT` | `TITLE` |
| `--height VALUE` | `HEIGHT` |
| `--thumbheight VALUE` | `THUMBHEIGHT` |
| `--maxpreviews N` | `MAXPREVIEWS` |
| `--shuffle` | `SHUFFLE=yes` |
| `--no-shuffle` | `SHUFFLE=no` |
| `--tarball` | `TARBALL_INCLUDE=yes` |
| `--no-tarball` | `TARBALL_INCLUDE=no` |

`--clean` accepts the same override options, but only `--dist` changes what it
removes.

## Example usage

1. Run `photoalbum --init`.
2. Edit `photoalbum.conf`. Set `INCOMING_DIR` to the directory containing the
   pictures and adjust `DIST_DIR`, `TITLE`, or template settings as needed.
3. Run `photoalbum --generate` to generate the album.
4. Distribute the `./dist` directory to a static web server.
5. Run `photoalbum --clean` to remove the generated output.

## HTML templates

Templates live under `share/templates/default` in the source tree and under the
installed template directory after installation. Copy and edit them, then point
`TEMPLATE_DIR` or `--template PATH` at the customized directory.
