CM-Yacc: A parser generator for Standard ML and Haskell
=======================================================

This is RedPRL's fork of [CM-Yacc](https://github.com/standardml/cmyacc). The
only difference is that we do not build with Smackage; Smackage can be a nice
tool for local and non-collaborative development, but we are principally
concerned with having build environments that do not require complicated setup
processes, and which can easily be reproduced on remote continuous integration
servers like Travis.

By keeping all code in-repository (using submodules), it is possible to achieve
a simple and reproducible build that requires no extra tools except those which
come with the two principal Standard ML distributions (SML/NJ and MLton).


Installing
----------

First, ensure that CM-Yacc's submodules are up to date:

    $ git submodule update --init --recursive

To install CM-Yacc (for Standard ML)

    $ make mlton (or smlnj or win+smlnj)
    $ make install DESTDIR=/usr/local/ # for example

To install CM-Yacc-HS (for Haskell)

    $ make mlton+hs (or smlnj+hs or win+smlnj+hs)
    $ make install+hs DESTDIR=/usr/local/ # for example

