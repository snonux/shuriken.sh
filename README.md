# photoalbum

photoalbum is a minimal Bash script for Unix like operating systems (such as Linux) to generate static web photo albums.
The resulting static photo album is pure HTML+CSS (without any JavaScript!).

## Installation

Run the following commands to install it:

```
make
sudo make install
```

Also, as a requirement, ImageMagick needs to be installed. The script prefers the
modern `magick` command and falls back to `convert` when needed.

## Usage

```
    photoalbum --generate [--config PATH] [OPTIONS]
    photoalbum --clean [--config PATH] [OPTIONS]
    photoalbum --version
    photoalbum --init
```

* `--generate`: Generates the static photo album
* `--clean`: Cleans up the workspace
* `--config PATH`: Selects the config file for `--generate` or `--clean`
* `--version`: Prints out the version
* `--init`: Creates a `photoalbum.conf` in the current working directory

The following long options can be used with `--generate` or `--clean` to
override values loaded from `photoalbum.conf`:

* `--incoming PATH`: Overrides `INCOMING_DIR`
* `--dist PATH`: Overrides `DIST_DIR`
* `--template PATH`: Overrides `TEMPLATE_DIR`
* `--title TEXT`: Overrides `TITLE`
* `--height VALUE`: Overrides `HEIGHT`
* `--thumbheight VALUE`: Overrides `THUMBHEIGHT`
* `--maxpreviews N`: Overrides `MAXPREVIEWS`
* `--shuffle`: Sets `SHUFFLE=yes`
* `--no-shuffle`: Sets `SHUFFLE=no`
* `--tarball`: Sets `TARBALL_INCLUDE=yes`
* `--no-tarball`: Sets `TARBALL_INCLUDE=no`

## Example usage

1. Run `photoalbum --init`, which creates a `photoalbum.conf` file in the current directory from the installed/default config template.
2. Adjust the `INCOMING_DIR` path in `photoalbum.conf`. Point it to a directory with all the pictures in it.
3. Run `photoalbum --generate` to generate it.
4. Distribute the `./dist` directory to a static web server.
5. Clean the mess up with `photoalbum --clean`

## HTML templates

Poke around in this source directory. You will find a bunch of Bash-HTML template files. You could tweak them to your likings. 
