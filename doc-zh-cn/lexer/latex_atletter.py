#!/usr/bin/env python

# Copyright © 2020 E. Zöllner
# Alternatively to the terms of the LPPL, at your choice,
# you can redistribute and/or modify this file under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See http://www.wtfpl.net/about/.

from pygments.lexers.markup import TexLexer

re_cmd = r'\\([a-zA-Z@]+|.)'

tokens_root = TexLexer.tokens['root']
t = next(t for t in tokens_root if 'command' in t)
i = tokens_root.index(t)
t = (re_cmd,) + t[1:]
tokens_root[i] = t
