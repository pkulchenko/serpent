local serpent = require("serpent")
local serialize = serpent.dump

--[[ Penlight
local serialize = require("pl.pretty").write --]]
--[[ metalua
require("serialize") -- this creates global serialize() function --]]
--[[ lua-nucleo
import = require("lua-nucleo.import_as_require").import
local serialize = require("lua-nucleo.tserialize").tserialize --]]

local b = {text="ha'ns", ['co\nl or']='bl"ue', str="\"\n'\\\000"}
local c = function() return 1 end
local d = {'sometable'}
local a = {
  x=1, [true] = {b}, [not true]=2, -- boolean as key
  ['true'] = 'some value', -- keyword as a key
  z = c, -- function as value
  list={'a',nil,nil, -- embedded nils
        [9]='i','f',[5]='g',[7]={}, -- empty table
        ['3'] = 33, [-1] = -1, [1.2] = 1.2}, -- numeric and negative index
  [c] = print, -- function as key, global as value
  [io.stdin] = 3, -- global userdata as key
  ['label 2'] = b, -- shared reference
  [b] = 0/0, -- table as key, undefined value as value
  [math.huge] = -math.huge, -- huge as number value
  ignore = d -- table to ignore
}
a.c = a -- self-reference
a[a] = a -- self-reference with table as key

print("pretty: " .. serpent.block(a, {ignore = {[d] = true}}) .. "\n")
print("line: " .. serpent.line(a, {ignore = {[d] = true}}) .. "\n")
local str = serpent.dump(a, {ignore = {[d] = true}})
print("full: " .. str .. "\n")

local fun, err = assert(loadstring(str))

assert(loadstring(serpent.line(a, {name = '_'})), "line() method produces deserializable output: failed")
assert(loadstring(serpent.block(a, {name = '_'})), "block() method produces deserializable output: failed")

local _a = fun()
local _b = _a['label 2'] -- shared reference
local _c = _a.z -- function

assert(_a[not true] == 2, "boolean value as key: failed")
assert(_a[true][1] == _b, "shared reference stays shared: failed")
assert(_c() == 1, "serialized user function returns value: failed")
assert(tostring(_a[_b]) == tostring(0/0), "table as key and undefined value: failed")
assert(_a[math.huge] == -math.huge, "math.huge as key and value: failed")
assert(_a[io.stdin] == 3, "io.stdin as key: failed")
assert(_a[_c] == print, "shared function as key and global function as value: failed")
assert(#(_a.list[7]) == 0, "empty table stays empty: failed")
assert(_a.list[-1] == -1, "negative index is in the right place: failed")
assert(_a.list['3'] == 33, "string that looks like number as index: failed")
assert(_a.list[4] == 'f', "specific table element preserves its value: failed")
assert(_a.ignore == nil, "ignored table not serialized: failed")

-- test without sparsness to check the number of elements in the list with nil
_a = loadstring(serpent.dump(a, {sparse = false}))()
assert(#(_a.list) == #(a.list), "size of array part stays the same: failed")

local diffable = {sortkeys = true, comment = false, nocode = true, indent = ' '}
assert(serpent.block(a, diffable) == serpent.block(_a, diffable),
 "block(a) == block(copy_of_a): failed")

-- test maxlevel
_a = loadstring(serpent.dump(a, {sparse = false, nocode = true, maxlevel = 1}))()
assert(#(_a.list) == 0, "nested table 1 is empty with maxlevel=1: failed")
assert(#(_a[true]) == 0, "nested table 2 is empty with maxlevel=1: failed")

-- test comment level
local dump = serpent.block(a, {comment = 1, nocode = true})
assert(dump:find(tostring(a)), "first level comment is present with comment=1: failed")
assert(not dump:find(tostring(a.list)), "second level comment is not present with comment=1: failed")
assert(dump:find("function() --[[..skipped..]] end", 1, true),
  "nocode replaces functions with an empty body: failed")

assert(serpent.line(nil) == 'nil', "nil value serialized as 'nil': failed")
assert(serpent.line(123) == '123', "numeric value serialized as number: failed")
assert(serpent.line("123") == '"123"', "string value serialized as string: failed")
