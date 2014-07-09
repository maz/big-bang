Development
===========
This file contains notes relevant to developers of the projects in this directory.

Before proceeding, developers should read and understand `README-Compiling.md`.


Assertions
----------
The projects related to TinyBang have an assertion mode which is only operational if (1) it is compiled into the binary and (2) it is activated at runtime via command-line arguments.  In order to compile assertions into the binary, the `-fno-ignore-asserts` flag must be passed to GHC.  If building on the command line, this can be accomplished by building with `cabal build --ghc-option=-fno-ignore-asserts`.
