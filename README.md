# Serpent

Lua serializer and pretty printer.

## Features

* Human readable:
    * Provides single-line and multi-line output.
    * Nested tables are properly indented in the multi-line output.
    * Numerical keys are listed first.
    * Array part skips keys (`{'a', 'b'}` instead of `{[1] = 'a', [2] = 'b'}`).
    * `nil` values are included when expected (`{1, nil, 3}` instead of `{1, [3]=3}`).
    * Keys use short notation (`{foo = 'foo'}` instead of `{['foo'] = 'foo'}`).
    * Shared and self-references are marked in the output.
* Machine readable: provides reliable deserialization using `loadstring()`.
* Supports deeply nested tables.
* Supports tables with self-references.
* Shared tables and functions stay shared after de/serialization.
* Supports function serialization using `string.dump()`.
* Supports serialization of global functions.
* Escapes new-line `\010` and end-of-file control `\026` characters in strings.

## Usage

```lua
local serpent = require("serpent")
local a = {1, nil, 3, x=1, ['true'] = 2, [not true]=3}
a[a] = a -- self-reference with a table as key and value

print(serpent.serialize(a)) -- full serialization
print(serpent.printsing(a)) -- single line, no self-ref section
print(serpent.printmult(a)) -- multi-line indented, no self-ref section

local fun, err = loadstring(serpent.serialize(a))
if err then error(err) end
local copy = fun()

```

## Limitations

* Doesn't handle userdata (except filehandles in `io.*` table).
* Threads, function upvalues/environments, and metatables are not serialized.

## Performance

A simple performance test against `serialize.lua` from metalua, `pretty.write`
from Penlight, and `tserialize.lua` from lua-nucleo is included in `t/bench.lua`.

These are the results from one of the runs:

* nucleo (1000): 0.256s
* metalua (1000): 0.177s
* serpent (1000): 0.22s
* serpent (1000): 0.161s -- no comments, no string escapes, no math.huge check
* penlight (1000): 0.132s

Serpent does additional processing to escape `\010` and `\026` characters in
strings (to address http://lua-users.org/lists/lua-l/2007-07/msg00362.html,
which is already fixed in Lua 5.2) and to check all numbers for `math.huge`.
The seconds number excludes this processing to put it on an equal footing
with other modules that skip these checks (`nucleo` still checks for `math.huge`).
There is no switch to disable this processing though as without it there is 
no guarantee that the generated string is deserializable.

## Author

Paul Kulchenko (paul@kulchenko.com)

## License

See LICENSE file.
