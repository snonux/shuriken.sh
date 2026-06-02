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
    photoalbum --generate
    photoalbum --clean
    photoalbum --version
    photoalbum --init
```

* `--generate`: Generates the static photo album
* `--clean`: Cleans up the workspace
* `--version`: Prints out the version
* `--init`: Creates a `photoalbumrc` in the current working directory

## Example usage

1. See if `/etc/default/photoalbum` fits your needs. If not, run `photoalbum --init`, which will create a `photoalbumrc` file in the current directory.
2. Adjust the `INCOMING_DIR` path in `photoalbumrc`. Point it to a directory with all the pictures in it.
3. Run `photoalbum --generate` to generate it.
4. Distribute the `./dist` directory to a static web server.
5. Clean the mess up with `photoalbum --clean`

## HTML templates

Poke around in this source directory. You will find a bunch of Bash-HTML template files. You could tweak them to your likings. 
