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

local loadstring = loadstring or load
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
if _VERSION == 'Lua 5.1' then
  local userdata = newproxy(true)
  getmetatable(userdata).__tostring = function() return "1234 <Userdata>" end
  local a = {hi = "there", [{}] = 123, [userdata] = 23}

  assert(loadstring(serpent.dump(a, {sparse = false, nocode = true})),
    "userdata with type starting with digits: failed")
end

-- test userdata with __tostring method that returns a table
if _VERSION == 'Lua 5.1' then
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
if _VERSION == 'Lua 5.1' then
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
if _VERSION == 'Lua 5.1' then
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

-- test that numerical keys are all present in the serialized table
do
  local a = {[4]=1,[5]=1,[6]=1,[7]=1,[8]=1,[9]=1,[10]=1}
  local f = assert(loadstring(serpent.dump(a)),
    "serializing table with numerical keys: failed")
  local _a = f()
  for k,v in pairs(a) do
    assert(_a[k] == v, "numerical keys are all present: failed")
  end
end

-- test maxnum limit
do
  local a = {a = {7,6,5,4,3,2,1}, b = {1,2}}
  local f = assert(loadstring(serpent.dump(a, {maxnum = 3})),
    "serializing table with numerical keys: failed")
  local _a = f()
  assert(#_a.a == 3, "table with maxnum=3 has no more than 3 elements 1/3: failed")
  assert(_a.a[3] == 5, "table with maxnum=3 has no more than 3 elements 2/3: failed")
  assert(#_a.b == 2, "table with maxnum=3 has no more than 3 elements 3/3: failed")
end

-- test serialization of mixed tables
do
  local a = {a='a', b='b', c='c', [3]=3, [2]=2,[1]=1}
  local diffable = {sortkeys = true, comment = false, nocode = true, indent = ' '}
  local _a = assert(loadstring(serpent.dump(a, diffable)))()

  for k,v in pairs(a) do
    assert(v == _a[k],
      ("mixed table with sorted keys (key = '%s'): failed"):format(k))
  end
end

-- test sorting is not called on numeric-only tables
do
  local a = {1,2,3,4,5}
  local called = false
  local sortfunc = function() called = true end

  serpent.dump(a, {sortkeys = sortfunc, sparse = false})
  assert(called == false, "sorting is not called on numeric-only tables: failed")

  called = false
  serpent.dump(a, {sortkeys = sortfunc, sparse = false, maxnum = 3})
  assert(called == false, "sorting is not called on numeric-only tables with maxnum: failed")
end

do
  local ok, res = serpent.load(serpent.line(10))
  assert(ok and res == 10, "deserialization of simple number values: failed")

  local ok, res = serpent.load(serpent.line(true))
  assert(ok and res == true, "deserialization of simple boolean values: failed")

  local ok, res = serpent.load(serpent.line({3,4}))
  assert(ok and #res == 2 and res[1] == 3 and res[2] == 4,
    "deserialization of pretty-printed tables: failed")

  local ok, res = serpent.load(serpent.dump({3,4}))
  assert(ok and #res == 2 and res[1] == 3 and res[2] == 4,
    "deserialization of serialized tables: failed")

  local ok, res = serpent.load('{a = math.random()}')
  assert(not ok and res:find("cannot call functions"),
    "deserialization of unsafe values: failed")

  local ok, res = serpent.load('{a = math.random()}', {safe = false})
  assert(ok and res and res.a > 0,
    "deserialization of unsafe values disabled: failed")
end

do
  local a = {1, 2, 3, 4, [false] = 0, [true] = 0}
  local f = assert(loadstring('return '..serpent.line(a)),
    "serializing table with numerical and boolean keys: failed")
  local _a = f()
  assert(#_a == #a, "table with array and hash parts has the right number of elements: failed")
  assert(_a[3] == a[3], "table with array and hash parts has the right order of elements 1/4: failed")
  assert(_a[4] == a[4], "table with array and hash parts has the right order of elements 2/4: failed")

  a = {1, [0] = 0}
  f = assert(loadstring('return '..serpent.line(a)),
    "serializing table with two numerical keys: failed")
  local _a = f()
  assert(_a[1] == 1, "table with array and hash parts has the right order of elements 3/4: failed")
  assert(_a[0] == 0, "table with array and hash parts has the right order of elements 4/4: failed")
end

-- based on https://gist.github.com/mpeterv/8360307
local function random_var(is_key, deep)
  local key = math.random(1000)

  if key <= 100 then
    return is_key and 0 or nil
  elseif key <= 200 then
    return false
  elseif key <= 500 then
    return math.random(-1e6, 1e6)
  elseif key <= 900 then
    local len = math.random(0, 100)
    local res = {}

    for i=1, len do
      table.insert(res, string.char(math.random(65, 90)))
    end

    return table.concat(res)
  else
    if deep > 3 or is_key then
      return 0
    else
      local len = math.random(0, 10)
      local res = {}

      for i=1, len do
        if math.random(0, 1) == 0 then
          table.insert(res, random_var(false, deep+1))
        else
          res[random_var(true, deep+1)] = random_var(false, deep+1)
        end
      end
      return res
    end
  end
end

local function deepsame(a1, a2)
  if type(a1) == type(a2) and type(a1) == 'table' then
    local e1, e2
    while true do
      e1, e2 = next(a1, e1), next(a2, e2)
      -- looped through all the elements and they are the same
      if e1 == nil and e2 == nil then return true end
      local res
      if e1 == e2 then
        res = deepsame(a1[e1], a2[e2])
      else
        res = deepsame(a1[e1], a2[e1]) and deepsame(a1[e2], a2[e2])
      end
      -- found two different elements
      if not res then return false end
    end
  end
  return type(a1) == type(a2) and a1 == a2
end

do
  local seed = os.time()
  math.randomseed(seed)

  local max = 100
  for i = 1, max do
    local x = random_var(false, 0)
    local s = serpent.block(x)
    local ok, x2 = serpent.load(s)
    assert(ok, ("deserialization of randomly generated values %d/%d (seed=%d): failed"):format(i, max, seed))
    assert(deepsame(x, x2),
      ("randomly generated values are the same after deserialization %d/%d (seed=%d): failed"):format(i, max, seed))
  end
end

do -- test for Lua 5.2 compiled without loadstring
  local a = {function() return 1 end}

  local load, loadstring = _G.load, _G.loadstring
  local f = assert((loadstring or load)('load = loadstring or load; loadstring = nil; return '..serpent.line(a)),
    "serializing table with function as a value (1/2): failed")
  local _a = f()
  assert(_a[1]() == a[1](), "deserialization of function value without loadstring (1/2): failed")
  _G.load, _G.loadstring = load, loadstring

  local f = assert((loadstring or load)('return '..serpent.line(a)),
    "serializing table with function as a value (2/2): failed")
  local _a = f()
  assert(_a[1]() == a[1](), "deserialization of function value without loadstring (2/2): failed")
end

do
  local ok, res = serpent.load("do error('not allowed') end")
  assert(not ok and res:find("cannot call functions"),
    "not allowing calling functions from serialized content: failed")

  local print = _G.print
  local ok, res = serpent.load("do print = error end")
  assert(ok and _G.print == print and print ~= error,
    "not allowing resetting `print` from serialized content (1/4): failed")

  local ok, res = serpent.load("do _G.print = error end")
  assert(ok and _G.print == print and _G.print ~= error,
    "not allowing resetting `print` from serialized content (2/4): failed")

  local ok, res = serpent.load("do _G._G.print = error end")
  assert(ok and _G.print == print and print ~= error,
    "not allowing resetting `print` from serialized content (3/4): failed")

  local ok, res = serpent.load("do _G = nil _G.print = error end")
  assert(ok and _G.print == print and print ~= error,
    "not allowing resetting `print` from serialized content (4/4): failed")
end

print("All tests passed.")

if arg[1] == 'perf' then
  print("\nSerializing large numeric-only tables:")

  local a, str = {}
  for i = 1, 100000 do a[i] = i end

  local start = os.clock()
  str = serpent.dump(a)
  print("dump: "..(os.clock() - start), #str)

  start = os.clock()
  str = serpent.dump(a, {maxnum = 400})
  print("dump/maxnum: "..(os.clock() - start), #str)

  start = os.clock()
  str = serpent.dump(a, {sparse = false})
  print("dump/sparse=false: "..(os.clock() - start), #str)
end
