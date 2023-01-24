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
-- MPV-specific functions
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
    mp.msg.info(tostring(val).." \t ←Δ "..propname)
  end)
end

return {
  std = std,
}
