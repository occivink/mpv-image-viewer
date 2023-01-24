local std = {} -- stdlib

-- escape magic chars ^$()%.[]*+-? https://www.lua.org/manual/5.1/manual.html#5.4.1
string.escmagic  	= function(self, str)	return self:gsub("([^%w])", "%%%1")                  	end
string.startswith	= function(self, str)	return self:find('^' .. str:escmagic()       ) ~= nil	end
string.endswith  	= function(self, str)	return self:find(       str:escmagic() .. '$') ~= nil	end
string.trim      	= function(self     )	return self:match("^%s*(.-)%s*$")                    	end

function std.getScriptFullPath()
  local source = debug.getinfo(2,"S").source
  if source:sub(1,1) == "@" then
    local path_arg = source:sub(2)
    -- ↓ os-dependent resolution of relative paths, but we pass absolute paths
    -- local fullpath = io.popen("realpath '"..path_arg.."'",'r'):read('a')
    -- fullpath = fullpath:gsub('[\n\r]*$','')
    return path_arg
  else error("Caller was not defined in a file", 2) end
end
function std.dir_filename(fullpath)
  if type(fullpath) ~= "string" then return nil end
  local dirname, filename = fullpath:match('^(.*[/\\])([^/\\]-)$')
  dirname 	= dirname  or ''
  filename	= filename or fullpath
  return dirname, filename
end
function std.dir(        fullpath)
  if type(fullpath) ~= "string" then return nil end
  local dirname, filename = fullpath:match('^(.*[/\\])([^/\\]-)$')
  return dirname  or ''
end
function std.filename(   fullpath)
  if type(fullpath) ~= "string" then return nil end
  local dirname, filename = fullpath:match('^(.*[/\\])([^/\\]-)$')
  return filename or fullpath
end
function std.delua(filename) -- strip script's extension
  if type(filename) ~= "string" then return nil end
  return filename:gsub("(.*)(.lua)"    ,"%1") -- (file)(.lua)  → (file)
end

function std.basename(path) -- get filename from path
  if type(path) ~= "string" then return nil end
  return path:gsub("(.*[/\\])(.*)"    ,"%2")  -- (path/)(file) → (file)
end

-- Print contents of `tbl`, with indentation `indent` gist.github.com/ripter/4270799
function std.tprint(tbl, indent)
  if not indent then indent = 0 end
  for k, v in pairs(tbl) do
    formatting = string.rep("  ", indent) .. k .. ": "
    if     type(v) == "table"   then	print(formatting               ); std.tprint(v,indent+1)
    elseif type(v) == 'boolean' then	print(formatting .. tostring(v))
    else                            	print(formatting ..          v ) end
  end
end

function std.tlen(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

-- Math
-- Round @ https://stackoverflow.com/a/58411671
function std.round(num)
  -- if Lua uses double precision IEC-559 (aka IEEE-754) floats (most do)
  -- if -2⁵¹ < num < 2⁵¹
  -- rounding using your FPU's current rounding mode, which is usually round to nearest, ties to even
  return num + (2^52 + 2^51) - (2^52 + 2^51)
end
function std.roundp(num) -- less efficient, performs the same FPU rounding but works for all numbers
  -- doesn't seem to differ, still fails at 0.5=0
  local ofs = 2^52
  if math.abs(num) > ofs then
    return num
  end
  return num < 0 and num - ofs + ofs or num + ofs - ofs
end

-- MPV-specific functions
local options	= require 'mp.options'
local msg    	= require 'mp.msg'

function std.getDimOSD() -- get OSD dimensions only if they exist and wid/height positive
  local dim = mp.get_property_native("osd-dimensions")
  if not dim          then return nil, nil, nil end
  local ww, wh = dim.w, dim.h
  if not (ww > 0 and
          wh > 0    ) then return nil, nil, nil end
  return dim, ww, wh
end

function std.observe_print(propname)  -- notify on changes, use example ↓
  -- local prop_list = {'prop1', 'prop2'}
  -- for k, v in pairs(prop_list) do std.observe_print(v) end
  mp.observe_property(propname, "string", function(_, val)
    msg.info(tostring(val).." \t ←Δ "..propname)
  end)
end

return {
  std = std,
}
