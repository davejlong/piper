# Piper

[![Build Status](https://travis-ci.org/operable/piper.svg?branch=master)](https://travis-ci.org/operable/piper)
[![Coverage Status](https://coveralls.io/repos/github/operable/piper/badge.svg?branch=master)](https://coveralls.io/github/operable/piper?branch=master)
[![Ebert](https://ebertapp.io/github/operable/piper.svg)](https://ebertapp.io/github/operable/piper)

Piper contains parsers for [Cog's](https://github.com/operable/cog) access control rule and ChatOps command languages. Piper has minimal
dependencies and can be used wherever parsing either of these languages would be useful.

## Getting piper

Add `piper` to the `deps` section of `mix.exs`:

`{:piper, github: "operable/piper"}`

## Using piper

Until we have proper docs `Piper.Permissions.Parser` (access control rules parser) and `Piper.Command.Parser` (ChatOps command parser) are good
places to start.

## Filing issues

Piper issues are tracked centrally in [Cog's](https://github.com/operable/cog/issues) issue tracker.
