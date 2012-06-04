local serpent = require("serpent")
local serialize = serpent.serialize

--[[ Penlight
local serialize = require("pl.pretty").write --]]
--[[ metalua
require("serialize") -- this creates global serialize() function --]]
--[[ lua-nucleo
import = require("lua-nucleo.import_as_require").import
local serialize = require("lua-nucleo.tserialize").tserialize --]]

local b = {text="ha'ns", ['co\nl or']='bl"ue', str="\"\n'\\\000"}
local c = function() return 1 end
local a = {
  x=1, [true] = {b}, [not true]=2, -- boolean as key
  ['true'] = 'some value', -- keyword as a key
  z = c, -- function as value
  list={'a',nil,nil, -- shared reference, embedded nils
        [9]='i','f',[5]='g',[7]={}}, -- empty table
  [c] = print, -- function as key, global as value
  [io.stdin] = 3, -- global userdata as key
  ['label 2'] = b, -- shared reference
  [b] = 0/0, -- table as key, undefined value as value
  [math.huge] = -math.huge, -- huge as number value
}
a.c = a -- self-reference
a[a] = a -- self-reference with table as key

print("pretty: " .. serpent.printmult(a) .. "\n") -- serialize(a, nil, '  ')
print("line: " .. serpent.printsing(a) .. "\n") -- serialize(a)
local str = serpent.serialize(a, 'a')
print("full: " .. str .. "\n")

local fun, err = loadstring(str)
if err then error(err) end

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
assert(#(_a.list) == #(a.list), "size of array part stays the same: failed")
assert(#(_a.list[7]) == 0, "empty table stays empty: failed")
