
# flay

A script for playing .flac files on OpenBSD. A stupid console music player.

```sh
$ ruby flay.rb file.flac
$ ruby flay.rb dir/
$ ruby flay.rb dir1/ dir2/
```

in `bin/flay`:
```sh
#!/bin/sh

/usr/local/bin/ruby25 ~/w/flay/lib/flay.rb "$@"
```


## license

MIT (See [LICENSE.txt](LICENSE.txt)).

