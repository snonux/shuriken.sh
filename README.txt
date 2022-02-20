NAME
    photoalbum - photoalbum is a minimal bash script for linux to generate
    static web photo albums.

SYNOPSIS
    photoalbum clean|generate|version [rcfile] photoalbum
    photoalbum makemake

    clean
        Cleans up the working space

    generate
        Generates the static photoalbum

    version
        Prints out the version

    makemake
        Creates a Makefile and photoalbumrc in the current working
        directory.

  RCFILE
  TUTORIAL
    * See if /etc/default/photoalbum fits your needs. If not, copy
    /etc/default/photoalbum to ~/.photoalbumrc in order to customize it.

    * Copy all images wanted to the incoming folder (see config file)

    * Run 'photoalbum generate'

    * Distribute the ./dist directory

    * Clean the mess up with 'photoalbum clean'

    It is possible to specify a custom rcfile path too.

   HTML TEMPLATES
    Go to the templates directory and edit them as wished.

LICENSE
    See package description or project website.

AUTHOR
    Paul Buetow - <https://codeberg.org/foozone/photoalbum>

