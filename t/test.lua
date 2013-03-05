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

-- this weirdness is needed to force not just shared reference,
-- but something that generates local variable.
a[1] = {}
a[1].more = {[a[1]] = "more"}
a[1].moreyet = {[{__more = a[1]}] = "moreyet"}

-- this weirdness is needed to use a table as key multiple times.
a[2] = {}
a[a[2]] = {more = a[2]}

print("pretty: " .. serpent.block(a, {valignore = {[d] = true}}) .. "\n")
print("line: " .. serpent.line(a, {valignore = {[d] = true}}) .. "\n")
local str = serpent.dump(a, {valignore = {[d] = true}})
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

-- test allowing keys
_a = assert(loadstring(serpent.dump(a, {keyallow = {["list"] = true, ["x"] = true}})))()
assert(_a.x == 1, "allowing key 'x': failed")
assert(_a.list ~= nil, "allowing key 'list': failed")
assert(_a[_c] == nil, "not allowing key '_c': failed")

-- test ignore value types
_a = assert(loadstring(serpent.dump(a, {valtypeignore = {["function"] = true, ["table"] = true}})))()
assert(_a.z == nil, "ignoring value type 'function': failed")
assert(_a[c] == nil, "ignoring value type 'function': failed")
assert(_a.list == nil, "ignoring value type 'table': failed")
assert(_a['true'] ~= nil, "not ignoring value type 'string': failed")
assert(_a.x ~= nil, "not ignoring value type 'number': failed")

-- test without sparsness to check the number of elements in the list with nil
_a = assert(loadstring(serpent.dump(a, {sparse = false})))()
assert(#(_a.list) == #(a.list), "size of array part stays the same: failed")

local diffable = {sortkeys = true, comment = false, nocode = true, indent = ' '}
assert(serpent.block(a, diffable) == serpent.block(_a, diffable),
 "block(a) == block(copy_of_a): failed")

-- test maxlevel
_a = assert(loadstring(serpent.dump(a, {sparse = false, nocode = true, maxlevel = 1})))()
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

-- test shared references serialized from shared reference section
do
  local a = {}
  local tbl = {'tbl'}
  a[3] = {[{}] = {happy = tbl}, sad = tbl}

  assert(loadstring(serpent.dump(a, {sparse = false, nocode = true})),
    "table as key with circular/shared reference: failed")
end

-- test shared functions
do
  local a = {a={}}
  local function1 = function() end
  a.a[function1] = function() end
  a.b = a.a[function1]

  assert(loadstring(serpent.dump(a, {sparse = false, nocode = true})),
    "functions as shared references while processing shared refs: failed")
end

-- test serialization of metatable with __tostring
do
  local mt = {}
  mt.__tostring = function(t) return 'table with ' .. #t .. ' entries' end
  local a = {'a', 'b'}
  setmetatable(a, mt)

  assert(loadstring(serpent.dump(a, {sparse = false, nocode = true, comment = true})),
    "metatable with __tostring serialized with a comment: failed")

  local shadow = {x = 11, y = 12}
  mt.__index = function(t, f) return shadow[f] end
  mt.__tostring = function(t) return {t[1], x = 1, y=t.y} end
  local _a = assert(loadstring(serpent.dump(a, {sparse = false, nocode = true, comment = 1})))()
  assert(_a.y == 12, "metatable with __tostring and __index 1: failed")
  assert(_a[1] == 'a', "metatable with __tostring and __index 2: failed")
  assert(_a.x == 1, "metatable with __tostring and __index 3: failed")
end

-- test circular reference in self-reference section
do
  local a = {}
  local table1 = {}
  a[table1]={}
  a[table1].rec1=a[table1]

  local _a = assert(loadstring(serpent.dump(a, {sparse = false, nocode = true})))()
  local t1 = next(_a)
  assert(_a[t1].rec1, "circular reference in self-reference section 1: failed")
  assert(_a[t1].rec1 == _a[t1], "circular reference in self-reference section 2: failed")
end

-- test userdata with __tostring method that returns type starting with digits
do
  local userdata = newproxy(true)
  getmetatable(userdata).__tostring = function() return "1234 <Userdata>" end
  local a = {hi = "there", [{}] = 123, [userdata] = 23}

  assert(loadstring(serpent.dump(a, {sparse = false, nocode = true})),
    "userdata with type starting with digits: failed")
end

-- test userdata with __tostring method that returns a table
do
  local userdata = newproxy(true)
  getmetatable(userdata).__tostring = function() return {3,4,5} end
  local a = {hi = "there", [{}] = 123, [userdata] = 23, ud = userdata}

  local f = assert(loadstring(serpent.dump(a, {sparse = false, nocode = true})),
    "userdata with __tostring that returns a table 1: failed")
  local _a = f()
  assert(_a.ud, "userdata with __tostring that returns a table 2: failed")
  assert(_a[_a.ud] == 23, "userdata with __tostring that returns a table 3: failed")
end

-- test userdata with __tostring method that includes another userdata
do
  local userdata1 = newproxy(true)
  local userdata2 = newproxy(true)
  getmetatable(userdata1).__tostring = function() return {1,2,ud = userdata2} end
  getmetatable(userdata2).__tostring = function() return {3,4,ud = userdata2} end
  local a = {hi = "there", [{}] = 123, [userdata1] = 23, ud = userdata1}

  local f = assert(loadstring(serpent.dump(a, {sparse = false, nocode = true})),
    "userdata with __tostring that returns userdata 1: failed")
  local _a = f()
  assert(_a.ud, "userdata with __tostring that returns userdata 2: failed")
  assert(_a[_a.ud] == 23, "userdata with __tostring that returns userdata 3: failed")
  assert(_a.ud.ud == _a.ud.ud.ud, "userdata with __tostring that returns userdata 4: failed")
end

-- test userdata with __serialize method that includes another userdata
do
  local userdata1 = newproxy(true)
  local userdata2 = newproxy(true)
  getmetatable(userdata1).__serialize = function() return {1,2,ud = userdata2} end
  getmetatable(userdata2).__serialize = function() return {3,4,ud = userdata2} end
  local a = {hi = "there", [{}] = 123, [userdata1] = 23, ud = userdata1}

  local f = assert(loadstring(serpent.dump(a, {sparse = false, nocode = true})),
    "userdata with __serialize that returns userdata 1: failed")
  local _a = f()
  assert(_a.ud, "userdata with __serialize that returns userdata 2: failed")
  assert(_a[_a.ud] == 23, "userdata with __serialize that returns userdata 3: failed")
  assert(_a[_a.ud] == 23, "userdata with __serialize that returns userdata 3: failed")
  assert(_a.ud.ud == _a.ud.ud.ud, "userdata with __serialize that returns userdata 4: failed")
end

print("All tests passed.")
