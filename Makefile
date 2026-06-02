NAME=photoalbum
#DESTDIR=/
all: version build
version:
	cut -d' ' -f2 changelog | head -n 1 | sed 's/(//;s/)//' > .version
build:
	test ! -d ./bin && mkdir ./bin || exit 0
	sed "s/PHOTOALBUMVERSION/$$(cat .version)/" src/$(NAME).sh > ./bin/$(NAME)
	chmod 0755 ./bin/$(NAME)
install:
	test ! -d $(DESTDIR)/usr/bin && mkdir -p $(DESTDIR)/usr/bin || exit 0
	cp ./bin/* $(DESTDIR)/usr/bin
	test ! -d $(DESTDIR)/usr/share/photoalbum/templates && mkdir -p $(DESTDIR)/usr/share/photoalbum/templates || exit 0
	cp -R ./share/templates $(DESTDIR)/usr/share/photoalbum/
	test ! -d $(DESTDIR)/etc/default && mkdir -p $(DESTDIR)/etc/default || exit 0
	cp ./src/photoalbum.default.conf $(DESTDIR)/etc/default/photoalbum
deinstall:
	test ! -z "$(DESTDIR)" && test -f $(DESTDIR)/usr/bin/$(NAME) && rm $(DESTDIR)/usr/bin/$(NAME) || exit 0
	test ! -z "$(DESTDIR)" && test -d $(DESTDIR)/usr/share/$(NAME) && rm -r $(DESTDIR)/usr/share/$(NAME) || exit 0
	test ! -z "$(DESTDIR)" && test -f $(DESTDIR)/etc/default/photoalbum && rm $(DESTDIR)/etc/default/photoalbum || exit 0
clean:
	test -d ./bin && rm -Rf ./bin || exit 0
shellcheck:
	# SC1090: ShellCheck can't follow non-constant source. Use a directive to specify location.
	# SC2001: See if you can use ${variable//search/replace} instead.
	# SC2010: Don't use ls | grep. Use a glob or a for loop with a condition to allow non-alphanumeric filenames.
	# SC2012: Use find instead of ls to better handle non-alphanumeric filenames.
	# SC2103: Use a ( subshell ) to avoid having to cd back.
	# SC2155: Declare and assign separately to avoid masking return values.
	# SC2164: Use 'cd ... || exit' or 'cd ... || return' in case cd fails.
	# SC2207: Prefer mapfile or read -a to split command output (or quote to avoid splitting).
	shellcheck \
		--exclude SC1090 \
		--exclude SC2001 \
		--exclude SC2010 \
		--exclude SC2012 \
		--exclude SC2103 \
		--exclude SC2155 \
		--exclude SC2164 \
		--exclude SC2207 \
		./src/photoalbum.sh
