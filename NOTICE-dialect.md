# Third-party notices

Dialect's watch app is built on software written by other people. This file credits every piece of
it that ships in the app, with its licence, and is what the app's acknowledgements screen shows.

It covers the watch app only. The iOS companion does not run LispKit, and needs its own list if it
links anything.

The Apache License 2.0, under which LispKit and several packages below are licensed, is reproduced
in full in [`LICENSE`](LICENSE); the acknowledgements screen shows it alongside this file. None of
the Apache-licensed packages below has a `NOTICE` file of its own to reproduce.

## LispKit

**[LispKit](https://github.com/objecthub/swift-lispkit)**, Copyright © 2015-2026 ObjectHub and
Matthias Zenger. Licensed under the Apache License 2.0.

Dialect uses LispKit through a fork of 2.6.2 (upstream `b234663`) that adds watchOS support. Every
file the fork changes carries a `DIALECT:` note saying so. The fork also bundles LispKit's Scheme
libraries, listed [below](#bundled-scheme-libraries).

## Swift packages

Compiled into the watch app. MarkdownKit and CLFormat are Dialect's forks of them, modified to build
for watchOS; the rest are used unmodified, at the versions pinned in LispKit's `Package.resolved`.

| Package                                                              | Version                            | Copyright                                                                                                                        | Licence                                   |
| -------------------------------------------------------------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| [MarkdownKit](https://github.com/objecthub/swift-markdownkit)        | fork of 1.4.1 (upstream `876a944`) | © 2019-2025 Google LLC; © 2026 Matthias Zenger                                                                                   | Apache 2.0                                |
| [CLFormat](https://github.com/objecthub/swift-clformat)              | fork of 1.2.1                      | © 2023-2026 Matthias Zenger                                                                                                      | Apache 2.0                                |
| [CommandLineKit](https://github.com/objecthub/swift-commandlinekit)  | 1.1.1                              | © 2018-2025 Google LLC; © 2026 Matthias Zenger; © 2017 Andy Best; © 2010-2014 Salvatore Sanfilippo; © 2010-2013 Pieter Noordhuis | BSD 3-Clause                              |
| [DynamicJSON](https://github.com/objecthub/swift-dynamicjson)        | `main` at `6b932fd`                | © 2024 Matthias Zenger                                                                                                           | Apache 2.0                                |
| [NanoHTTP](https://github.com/objecthub/swift-nanohttp)              | 1.0.1                              | © 2024 Matthias Zenger; © 2014 Damian Kołakowski                                                                                 | BSD 3-Clause                              |
| [NumberKit](https://github.com/objecthub/swift-numberkit)            | 2.6.1                              | © 2015-2024 Matthias Zenger                                                                                                      | Apache 2.0                                |
| [SQLiteExpress](https://github.com/objecthub/swift-sqliteexpress)    | 1.0.3                              | © 2020 Google LLC                                                                                                                | Apache 2.0                                |
| [Swift Atomics](https://github.com/apple/swift-atomics)              | 1.3.0                              | © 2020-2025 Apple Inc. and the Swift project authors                                                                             | Apache 2.0 with Runtime Library Exception |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)           | 0.9.20                             | © 2017-2025 Thomas Zoechling                                                                                                     | MIT                                       |
| [SWCompression](https://github.com/tsolomko/SWCompression)           | 4.8.6                              | © 2024 Timofey Solomko                                                                                                           | MIT                                       |
| [BitByteData](https://github.com/tsolomko/BitByteData)               | 2.0.3                              | © 2023 Timofey Solomko                                                                                                           | MIT                                       |
| [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) | `master` at `e0c7eeb`              | © 2014 kishikawa katsumi                                                                                                         | MIT                                       |
| [CBORCoding](https://github.com/SomeRandomiOSDev/CBORCoding)         | 1.4.0                              | © 2021 Joe Newton                                                                                                                | MIT                                       |
| [Half](https://github.com/SomeRandomiOSDev/Half)                     | 1.4.2                              | © 2023 Joe Newton                                                                                                                | MIT                                       |

The full texts of the MIT and BSD licences, with their copyright notices, are
[at the end of this file](#licence-texts).

## highlight.js

**[highlight.js](https://highlightjs.org) 11.11.1**, Copyright © 2006-2025 Josh Goebel and other
contributors. Licensed under the BSD 3-Clause License; the full text is
[at the end of this file](#licence-texts).

MarkdownKit bundles it, with 105 of its colour themes, for syntax highlighting. Five of the themes
are base16 schemes whose headers give them as "MIT (or more permissive)": `silk-dark` and
`silk-light` by Gabriel Fontes, `snazzy` by Chawye Hsu (after Sindre Sorhus's Hyper Snazzy),
`vulcan` by Andrey Varfolomeev, and `xcode-dusk` by Elsa Gonsiorowski.

## Bundled Scheme libraries

LispKit's Scheme libraries ship in the app as source, each file carrying its own copyright and
licence notice in full.

The prelude and 82 of the 191 libraries were written for LispKit by Matthias Zenger and are covered
by LispKit's Apache 2.0 licence above. The other 109 are, in whole or in part, the work of the
people below: most are reference implementations of SRFIs, adapted to LispKit by Matthias Zenger.

| Library                             | Copyright                                                                                             | Licence                                           |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| `(lispkit clos)`                    | 1992 Xerox Corporation                                                                                | Xerox licence                                     |
| `(lispkit clos support)`            | 1992 Xerox Corporation                                                                                | Xerox licence                                     |
| `(lispkit combinator)`              | 2002 Sebastian Egner                                                                                  | Apache 2.0; portions public domain (SRFI 26)      |
| `(lispkit comparator)`              | 2015-2019 John Cowan                                                                                  | MIT                                               |
| `(lispkit enum r6rs)`               | 2015 Taylan Ulrich Bayırlı/Kammer                                                                     | Permissive (notice required)                      |
| `(lispkit heap)`                    | 1992, 1993, 1994, 1995, 1997 Aubrey Jaffer                                                            | Apache 2.0; portions SLIB licence                 |
| `(lispkit json deprecated)`         | 2011-2014 Marc Feeley; 2015 Jason K. MacDuffie; 2012-2015 Alvaro Castro-Castilla                      | MIT                                               |
| `(lispkit list set)`                | 1998, 1999 Olin Shivers                                                                               | Apache 2.0; portions permissive (notice required) |
| `(lispkit logic)`                   | 2015 William E. Byrd                                                                                  | MIT                                               |
| `(lispkit match)`                   | Alex Shinn                                                                                            | Public domain                                     |
| `(lispkit pdf legacy)`              | 2002 Marc Battyani                                                                                    | BSD                                               |
| `(lispkit prettify)`                | 1991 Marc Feeley; 1993, 1994 Aubrey Jaffer                                                            | Apache 2.0; portions SLIB licence                 |
| `(lispkit prolog)`                  | 1993-2015 Dorai Sitaram                                                                               | Permissive (notice required)                      |
| `(lispkit stream)`                  | 2007 Philip L. Bewig                                                                                  | MIT                                               |
| `(lispkit sxml)`                    | Alex Shinn                                                                                            | BSD                                               |
| `(lispkit sxml html)`               | 2003-2014 Alex Shinn                                                                                  | BSD                                               |
| `(lispkit sxml xml)`                | 2007 Aubrey Jaffer                                                                                    | SLIB licence                                      |
| `(lispkit test)`                    | 2010-2014 Alex Shinn                                                                                  | Apache 2.0; portions BSD                          |
| `(lispkit thread channel)`          | 2017 Kristian Lein-Mathisen                                                                           | BSD                                               |
| `(lispkit wt-tree)`                 | 2010 Kazu Yamamoto; 1993-1994 Stephen Adams; 1993-94 Massachusetts Institute of Technology            | MIT Scheme licence                                |
| `(scheme division)`                 | Alex Shinn                                                                                            | Public domain                                     |
| `(srfi 1)`                          | 1998, 1999 Olin Shivers; 2013-2014 Yuichi Nishiwaki and other picrin contributors                     | Permissive (notice required)                      |
| `(srfi 6)`                          | 1999 William D Clinger                                                                                | MIT                                               |
| `(srfi 8)`                          | 1999 John David Stone                                                                                 | MIT                                               |
| `(srfi 9)`                          | 1999 Richard Kelsey                                                                                   | MIT                                               |
| `(srfi 14 ascii)`                   | 1988-1995 Massachusetts Institute of Technology                                                       | MIT Scheme licence                                |
| `(srfi 19)`                         | 2000-2003 I/NET, Inc                                                                                  | MIT                                               |
| `(srfi 26)`                         | 2002 Sebastian Egner                                                                                  | Public domain                                     |
| `(srfi 27)`                         | 2002 Sebastian Egner                                                                                  | MIT                                               |
| `(srfi 28)`                         | 2002 Scott G. Miller                                                                                  | MIT                                               |
| `(srfi 35)`                         | 2002 Richard Kelsey, Michael Sperber                                                                  | MIT                                               |
| `(srfi 41)`                         | 2007 Philip L. Bewig                                                                                  | MIT                                               |
| `(srfi 41 derived)`                 | 2007 Philip L. Bewig                                                                                  | MIT                                               |
| `(srfi 41 primitive)`               | 2007 Philip L. Bewig                                                                                  | MIT                                               |
| `(srfi 48)`                         | 2003 Kenneth A Dickey; 2014 Taylan Ulrich Bayırlı/Kammer                                              | MIT                                               |
| `(srfi 51)`                         | 2004 Joo ChurlSoo; 2014 Taylan Ulrich Bayırlı/Kammer                                                  | MIT                                               |
| `(srfi 54)`                         | 2004 Joo ChurlSoo                                                                                     | MIT                                               |
| `(srfi 63)`                         | 2001, 2003 Aubrey Jaffer                                                                              | SLIB licence                                      |
| `(srfi 64)`                         | 2005-2013 Per Bothner; 2005 Alex Shinn; 2012 Álvaro Castro-Castilla; 2014 Mark H Weaver               | MIT                                               |
| `(srfi 69)`                         | 2005 Panu Kalliokoski                                                                                 | Apache 2.0 (specification by its author)          |
| `(srfi 95)`                         | 2006 Aubrey Jaffer; 2014 Taylan Ulrich Bayırlı/Kammer                                                 | MIT                                               |
| `(srfi 101)`                        | 2009 David Van Horn                                                                                   | MIT                                               |
| `(srfi 111)`                        | 2013 John Cowan                                                                                       | MIT                                               |
| `(srfi 112)`                        | 2013 John Cowan                                                                                       | MIT                                               |
| `(srfi 113)`                        | 2013 John Cowan                                                                                       | MIT                                               |
| `(srfi 118)`                        | 2015 Per Bothner                                                                                      | MIT                                               |
| `(srfi 121)`                        | 2015 Shiro Kawai, John Cowan, Thomas Gilray                                                           | MIT                                               |
| `(srfi 125)`                        | 2016 John Cowan, Will Clinger                                                                         | Apache 2.0 (specification by its authors)         |
| `(srfi 128)`                        | 2015 John Cowan                                                                                       | MIT                                               |
| `(srfi 129)`                        | 2015 John Cowan                                                                                       | MIT                                               |
| `(srfi 132)`                        | 1998-1999 Olin Shivers                                                                                | MIT; portions permissive (notice required)        |
| `(srfi 133)`                        | 2016 John Cowan                                                                                       | MIT; implementation public domain                 |
| `(srfi 134)`                        | 2015 John Cowan, Kevin Wortman; 2015 Shiro Kawai                                                      | MIT; portions BSD                                 |
| `(srfi 135)`                        | 2016 William D Clinger                                                                                | MIT                                               |
| `(srfi 135 kernel0)`                | 2016 William D Clinger                                                                                | MIT                                               |
| `(srfi 141)`                        | 2010-2011 Taylor R. Campbell; 2015 William D Clinger                                                  | BSD; portions permissive                          |
| `(srfi 142)`                        | 2016, 2017 John Cowan; 1991, 1993, 2001, 2003, 2005 Aubrey Jaffer                                     | MIT; portions SLIB licence                        |
| `(srfi 144)`                        | 2016 William D Clinger                                                                                | MIT                                               |
| `(srfi 146)`                        | 2016, 2017 Marc Nieper-Wißkirchen                                                                     | MIT                                               |
| `(srfi 146 rbtree)`                 | 2016 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 151)`                        | 2016, 2017 John Cowan; 1991, 1993, 2001, 2003, 2005 Aubrey Jaffer                                     | MIT; portions SLIB licence                        |
| `(srfi 152)`                        | 2016, 2017 John Cowan; 1988-1994 Massachusetts Institute of Technology; 1998, 1999, 2000 Olin Shivers | MIT; portions BSD (scsh) and MIT Scheme licence   |
| `(srfi 154)`                        | 2017 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 155)`                        | 2017 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 158)`                        | 2015 Shiro Kawai, John Cowan, Thomas Gilray                                                           | MIT                                               |
| `(srfi 161)`                        | 2018 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 162)`                        | 2018 John Cowan                                                                                       | MIT                                               |
| `(srfi 165)`                        | 2019 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 166)`                        | 2020 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 166 base)`                   | 2020 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 166 color)`                  | 2020 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 166 columnar)`               | 2020 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 166 pretty)`                 | 2020 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 166 unicode)`                | 2020 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 167 engine)`                 | 2019 Amirouche Boubekki                                                                               | MIT                                               |
| `(srfi 167 memory)`                 | 2019 Amirouche Boubekki                                                                               | MIT                                               |
| `(srfi 167 pack)`                   | 2019 Amirouche Boubekki                                                                               | MIT                                               |
| `(srfi 175)`                        | 2019 Lassi Kortela                                                                                    | MIT                                               |
| `(srfi 177)`                        | 2019 Lassi Kortela                                                                                    | MIT                                               |
| `(srfi 180)`                        | 2020 Amirouche Boubekki                                                                               | MIT                                               |
| `(srfi 189)`                        | 2020 John Cowan, Wolfgang Corcoran-Mathe                                                              | MIT                                               |
| `(srfi 194)`                        | 2020 Shiro Kawai, Arvydas Silanskas, Linas Vepštas, John Cowan                                        | MIT                                               |
| `(srfi 195)`                        | 2020 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 196)`                        | 2020 Wolfgang Corcoran-Mathe                                                                          | MIT                                               |
| `(srfi 204)`                        | 2020 Felix Thibault                                                                                   | MIT                                               |
| `(srfi 209)`                        | 2020 Wolfgang Corcoran-Mathe                                                                          | MIT                                               |
| `(srfi 210)`                        | 2020 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 214)`                        | 2020-2021 Adam Nelson                                                                                 | MIT                                               |
| `(srfi 215)`                        | 2020 Göran Weinholt                                                                                   | MIT                                               |
| `(srfi 216)`                        | 2020 Vladimir Nikishkin                                                                               | MIT                                               |
| `(srfi 217)`                        | 2020 Wolfgang Corcoran-Mathe                                                                          | MIT                                               |
| `(srfi 219)`                        | 2021 Lassi Kortela                                                                                    | MIT                                               |
| `(srfi 221)`                        | 2020 John Cowan (text), Arvydas Silanskas (implementation)                                            | MIT                                               |
| `(srfi 222)`                        | 2021 John Cowan (text), Arvydas Silanskas (implementation)                                            | MIT                                               |
| `(srfi 223)`                        | 2021 Daphne Preston-Kendal                                                                            | MIT                                               |
| `(srfi 224)`                        | 2021 Wolfgang Corcoran-Mathe                                                                          | MIT                                               |
| `(srfi 228)`                        | 2021 Daphne Preston-Kendal                                                                            | MIT                                               |
| `(srfi 230)`                        | 2021 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 232)`                        | 2022 Wolfgang Corcoran-Mathe                                                                          | MIT                                               |
| `(srfi 233)`                        | 2022 Arvydas Silanskas                                                                                | MIT                                               |
| `(srfi 235)`                        | 2023 Arvydas Silanskas                                                                                | MIT                                               |
| `(srfi 236)`                        | 2022 Marc Nieper-Wißkirchen                                                                           | MIT                                               |
| `(srfi 239)`                        | 2023 Robby Zambito; 2022 Marc Nieper-Wißkirchen                                                       | MIT                                               |
| `(srfi 258)`                        | 2025 Matthias Zenger                                                                                  | MIT                                               |
| `(srfi sicp)`                       | 2020 Vladimir Nikishkin                                                                               | MIT                                               |
| `(third-party adapton memoization)` | 2016-2017 Dakota Fisher and William Byrd                                                              | MIT                                               |
| `(third-party adapton micro)`       | 2016-2017 Dakota Fisher and William Byrd                                                              | MIT                                               |
| `(third-party adapton mini)`        | 2016-2017 Dakota Fisher and William Byrd                                                              | MIT                                               |
| `(third-party adapton set)`         | 2016-2017 Dakota Fisher and William Byrd                                                              | MIT                                               |

## Licence texts

Reproduced verbatim from each package.

### BitByteData

```text
MIT License

Copyright (c) 2023 Timofey Solomko

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### CBORCoding

```text
Copyright (c) 2021 Joe Newton <somerandomiosdev@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### CommandLineKit

```text
Copyright © 2018-2025 Google LLC
Copyright © 2026 Matthias Zenger
Copyright © 2017 Andy Best <andybest.net at gmail dot com>
Copyright © 2010-2014 Salvatore Sanfilippo <antirez at gmail dot com>
Copyright © 2010-2013 Pieter Noordhuis <pcnoordhuis at gmail dot com>

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its contributors
  may be used to endorse or promote products derived from this software without
  specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### Half

```text
Copyright (c) 2023 Joe Newton <somerandomiosdev@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### highlight.js

```text
BSD 3-Clause License

Copyright (c) 2006-2025 Josh Goebel <hello@joshgoebel.com> and other contributors.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### KeychainAccess

```text
The MIT License (MIT)

Copyright (c) 2014 kishikawa katsumi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### NanoHTTP

```text
Copyright © 2024 Matthias Zenger
Copyright © 2014 Damian Kołakowski

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### SWCompression

```text
MIT License

Copyright (c) 2024 Timofey Solomko

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### ZIPFoundation

```text
MIT License

Copyright (c) 2017-2025 Thomas Zoechling (https://www.peakstep.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
