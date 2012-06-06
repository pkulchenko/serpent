local n, v, c, d = "serpent", 0.1, -- (C) 2012 Paul Kulchenko; MIT License
  "Paul Kulchenko", "Serialization and pretty printing of Lua data types"
local snum = {[tostring(1/0)]="math.huge",[tostring(-1/0)]="-math.huge",[tostring(0/0)]="0/0"}
local badtype = {thread = true, userdata = true}
local keyword, globals, G = {}, {}, (_G or _ENV)
for _,k in ipairs({'and', 'break', 'do', 'else', 'elseif', 'end', 'false',
  'for', 'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat',
  'return', 'then', 'true', 'until', 'while'}) do keyword[k] = true end
for k,v in pairs(G) do globals[v] = k end -- build func to name mapping
for _,g in ipairs({'coroutine', 'debug', 'io', 'math', 'string', 'table', 'os'}) do
  for k,v in pairs(G[g]) do globals[v] = g..'.'..k end end

local function serialize(t, name, indent, fatal)
  local seen, sref = {}, {}
  local function gensym(val) return tostring(val):gsub("[^%w]","") end
  local function safestr(s) return type(s) == "number" and (snum[tostring(s)] or s)
    or type(s) ~= "string" and tostring(s) -- escape NEWLINE/010 and EOF/026
    or ("%q"):format(s):gsub("\010","010"):gsub("\026","\\026") end
  local function comment(s) return ' --[['..tostring(s)..']]' end
  local function globerr(s) return globals[s] and globals[s]..comment(s) or not fatal
    and safestr(tostring(s))..' --[[err]]' or error("Can't serialize "..tostring(s)) end
  local function safename(path, name) -- generates foo.bar, foo[3], or foo['b a r']
    local n = name == nil and '' or name
    local plain = type(n) == "string" and n:match("^[%l%u_][%w_]*$") and not keyword[n]
    local safe = plain and n or '['..safestr(n)..']'
    return (path or '')..(plain and path and '.' or '')..safe, safe
  end
  local function val2str(t, name, indent, path, plainindex, level)
    local ttype, level = type(t), (level or 0)
    local spath, sname = safename(path, name)
    local tag = plainindex and ((type(name) == "number") and '' or name..' = ')
                           or (name ~= nil and sname..' = ' or '')
    if seen[t] then
      table.insert(sref, spath..' = '..seen[t])
      return tag..'nil --[[ref]]'
    elseif badtype[ttype] then return tag..globerr(t)
    elseif ttype == 'function' then
      seen[t] = spath
      local ok, res = pcall(string.dump, t)
      local func = ok and "loadstring("..safestr(res)..",'@serialized')"..comment(t)
      return tag..(func or globerr(t))
    elseif ttype == "table" then
      seen[t] = spath
      if next(t) == nil then return tag..'{}'..comment(t) end -- table empty
      local maxn, o, out = #t, {}, {}
      for key = 1, maxn do table.insert(o, key) end -- first array part
      for key in pairs(t) do -- then hash part (skip array keys up to maxn)
        if type(key) ~= "number" or key > maxn then
          table.insert(o, key) end end
      for n, key in ipairs(o) do
        local value, ktype, plainindex = t[key], type(key), n <= maxn
        if badtype[ktype] then plainindex, key = true, '['..globerr(key)..']' end
        if ktype == 'table' or ktype == 'function' then
          if not seen[key] and not globals[key] then
            table.insert(sref, 'local '..val2str(key,gensym(key),indent)) end
          table.insert(sref, seen[t]..'['..(seen[key] or globals[key] or gensym(key))
            ..'] = '..(seen[value] or val2str(value,nil,indent)))
        else table.insert(out,val2str(value,key,indent,spath,plainindex,level+1)) end
      end
      local prefix = string.rep(indent or '', level)
      return tag..(indent and '{\n'..prefix..indent or '{')..
        table.concat(out, indent and ',\n'..prefix..indent or ', ')..
        (indent and "\n"..prefix..'}' or '}')..comment(t)
    else return tag..safestr(t) end -- handle all other types
  end
  local sepr = indent and "\n" or "; "
  local body = val2str(t, name, indent) -- this call also populates sref
  local tail = #sref>0 and table.concat(sref, sepr)..sepr or ''
  return not name and body or "do local "..body..sepr..tail.."return "..name..sepr.."end"
end

return { _NAME = n, _COPYRIGHT = c, _DESCRIPTION = d, _VERSION = v,
  serialize = function(t,n,i,f) return serialize(t,n or '_',i,f) end,
  printmult = function(t,i) return serialize(t,nil,i or '  ') end,
  printsing = function(t) return serialize(t) end }