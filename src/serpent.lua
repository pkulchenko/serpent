local n, v = "serpent", 0.20 -- (C) 2012 Paul Kulchenko; MIT License
local c, d = "Paul Kulchenko", "Serializer and pretty printer of Lua data types"
local snum = {[tostring(1/0)]='1/0 --[[math.huge]]',[tostring(-1/0)]='-1/0 --[[-math.huge]]',[tostring(0/0)]='0/0'}
local badtype = {thread = true, userdata = true}
local keyword, globals, G = {}, {}, (_G or _ENV)
for _,k in ipairs({'and', 'break', 'do', 'else', 'elseif', 'end', 'false',
  'for', 'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat',
  'return', 'then', 'true', 'until', 'while'}) do keyword[k] = true end
for k,v in pairs(G) do globals[v] = k end -- build func to name mapping
for _,g in ipairs({'coroutine', 'debug', 'io', 'math', 'string', 'table', 'os'}) do
  for k,v in pairs(G[g]) do globals[v] = g..'.'..k end end

local function s(t, opts)
  local name, indent, fatal = opts.name, opts.indent, opts.fatal
  local sparse, custom, huge = opts.sparse, opts.custom, not opts.nohuge
  local space, maxl = (opts.compact and '' or ' '), (opts.maxlevel or math.huge)
  local comm = opts.comment and (tonumber(opts.comment) or math.huge)
  local seen, sref, syms, symn = {}, {}, {}, 0
  local function gensym(val) return (tostring(val):gsub("[^%w]",""):gsub("(%d%w+)",
    function(s) if not syms[s] then symn = symn+1; syms[s] = symn end return syms[s] end)) end
  local function safestr(s) return type(s) == "number" and (huge and snum[tostring(s)] or s)
    or type(s) ~= "string" and tostring(s) -- escape NEWLINE/010 and EOF/026
    or ("%q"):format(s):gsub("\010","n"):gsub("\026","\\026") end
  local function comment(s,l) return comm and (l or 0) < comm and ' --[['..tostring(s)..']]' or '' end
  local function globerr(s,l) return globals[s] and globals[s]..comment(s,l) or not fatal
    and safestr(select(2, pcall(tostring, s))) or error("Can't serialize "..tostring(s)) end
  local function safename(path, name) -- generates foo.bar, foo[3], or foo['b a r']
    local n = name == nil and '' or name
    local plain = type(n) == "string" and n:match("^[%l%u_][%w_]*$") and not keyword[n]
    local safe = plain and n or '['..safestr(n)..']'
    return (path or '')..(plain and path and '.' or '')..safe, safe end
  local alphanumsort = type(opts.sortkeys) == 'function' and opts.sortkeys or function(o, n)
    local maxn, to = tonumber(n) or 12, {number = 'a', string = 'b'}
    local function padnum(d) return ("%0"..maxn.."d"):format(d) end
    table.sort(o, function(a,b)
      return (o[a] and 0 or to[type(a)] or 'z')..(tostring(a):gsub("%d+",padnum))
           < (o[b] and 0 or to[type(b)] or 'z')..(tostring(b):gsub("%d+",padnum)) end) end
  local function val2str(t, name, indent, insref, path, plainindex, level)
    local ttype, level = type(t), (level or 0)
    local spath, sname = safename(path, name)
    local tag = plainindex and
      ((type(name) == "number") and '' or name..space..'='..space) or
      (name ~= nil and sname..space..'='..space or '')
    if seen[t] then -- if already seen and in sref processing,
      if insref then return tag..seen[t] end -- then emit right away
      table.insert(sref, spath..space..'='..space..seen[t])
      return tag..'nil'..comment('ref', level)
    elseif badtype[ttype] then
      seen[t] = spath
      return tag..globerr(t, level)
    elseif ttype == 'function' then
      seen[t] = insref or spath
      local ok, res = pcall(string.dump, t)
      local func = ok and ((opts.nocode and "function() --[[..skipped..]] end" or
        "loadstring("..safestr(res)..",'@serialized')")..comment(t, level))
      return tag..(func or globerr(t, level))
    elseif ttype == "table" then
      if level >= maxl then return tag..'{}'..comment('max', level) end
      seen[t] = insref or spath -- set path to use as reference
      if getmetatable(t) and getmetatable(t).__tostring
        then return tag..safestr(tostring(t))..comment("meta", level) end
      if next(t) == nil then return tag..'{}'..comment(t, level) end -- table empty
      local maxn, o, out = #t, {}, {}
      for key = 1, maxn do table.insert(o, key) end
      for key in pairs(t) do if not o[key] then table.insert(o, key) end end
      if opts.sortkeys then alphanumsort(o, opts.sortkeys) end
      for n, key in ipairs(o) do
        local value, ktype, plainindex = t[key], type(key), n <= maxn and not sparse
        if opts.ignore and opts.ignore[value] -- skip ignored values; do nothing
        or opts.keyallow and not opts.keyallow[key]
        or sparse and value == nil then -- skipping nils; do nothing
        elseif ktype == 'table' or ktype == 'function' or badtype[ktype] then
          if not seen[key] and not globals[key] then
            table.insert(sref, 'placeholder')
            sref[#sref] = 'local '..val2str(key,gensym(key),indent,gensym(key)) end
          table.insert(sref, 'placeholder')
          local path = seen[t]..'['..(seen[key] or globals[key] or gensym(key))..']'
          sref[#sref] = path..space..'='..space..(seen[value] or val2str(value,nil,indent,path))
        else
          table.insert(out,val2str(value,key,indent,insref,seen[t],plainindex,level+1))
        end
      end
      local prefix = string.rep(indent or '', level)
      local head = indent and '{\n'..prefix..indent or '{'
      local body = table.concat(out, ','..(indent and '\n'..prefix..indent or space))
      local tail = indent and "\n"..prefix..'}' or '}'
      return (custom and custom(tag,head,body,tail) or tag..head..body..tail)..comment(t, level)
    else return tag..safestr(t) end -- handle all other types
  end
  local sepr = indent and "\n" or ";"..space
  local body = val2str(t, name, indent) -- this call also populates sref
  local tail = #sref>0 and table.concat(sref, sepr)..sepr or ''
  return not name and body or "do local "..body..sepr..tail.."return "..name..sepr.."end"
end

local function merge(a, b) if b then for k,v in pairs(b) do a[k] = v end end; return a; end
return { _NAME = n, _COPYRIGHT = c, _DESCRIPTION = d, _VERSION = v, serialize = s,
  dump = function(a, opts) return s(a, merge({name = '_', compact = true, sparse = true}, opts)) end,
  line = function(a, opts) return s(a, merge({sortkeys = true, comment = true}, opts)) end,
  block = function(a, opts) return s(a, merge({indent = '  ', sortkeys = true, comment = true}, opts)) end }
