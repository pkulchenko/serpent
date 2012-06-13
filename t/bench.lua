local ITERS = 1000
local TESTS = {
  serpent = function() return require("serpent").dump end,
  penlight = function() return require("pl.pretty").write end,
  metalua = function() require("serialize"); return (_G or _ENV).serialize end,
  nucleo = function()
    import = require("lua-nucleo.import_as_require").import
    return require("lua-nucleo.tserialize").tserialize end
}

-- test data
local b = {text="ha'ns", ['co\nl or']='bl"ue', str="\"\n'\\\001"}
local a = {
  x=1, y=2, z=3,
  ['function'] = b, -- keyword as a key
  list={'a',nil,nil, -- shared reference, embedded nils
        [9]='i','f',[5]='g',[7]={}}, -- empty table
  ['label 2'] = b, -- shared reference
  [math.huge] = -math.huge, -- huge as number value
}
a.c = a -- self-reference
-- test data

for test, func in pairs(TESTS) do
  local start, str = os.clock()
  local serializer = func()
  for _ = 1, ITERS do str = serializer(a) end
  print(("%s (%d): %ss"):format(test, ITERS, os.clock() - start))
end
