# photoalbum

photoalbum is a minimal Bash script for Unix like operating systems (such as Linux) to generate static web photo albums.
As a requirement `convert` from ImageMagick needs to be installed.  

The resulting static photo album is pure HTML+CSS (without any JavaScript!). An example album can be surfed here: https://sidewalk.ninja

## Usage

```
    photoalbum clean|generate|version [rcfile] photoalbum
    photoalbum makemake
```

* `clean`: Cleans up the workspace
* `generate`: Generates the static photo album
* `version`: Prints out the version
* `makemake`: Creates a Makefile and photoalbumrc in the current working directory.

## Example usage

1. See if /etc/default/photoalbum fits your needs. If not, run `photoalbum makemake`, which will create a `photoalbumrc` file in the current directory.
2. Adjust the `incoming` path in `photoalbum`. Point to a directory with all the pictures in it. 
3. Run `make` (or `photoalbum generate`) to generate it.
4. Distribute the `./dist` directory to a static web server.
5. Clean the mess up with `make clean` or `photoalbum clean`
