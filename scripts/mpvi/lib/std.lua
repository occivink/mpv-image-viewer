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

local parse_yaml	= require "lib/tinyyaml".parse
function std.read_options_yaml(opts, identifier, on_update)
  if identifier == nil then identifier = mp.get_script_name() end
  msg.debug("reading options for "..identifier)

  -- get, read, and parse YAML config file
  local function read_yaml_config(identifier) -- get YAML config file contet
    local yaml_ext           	= {'yml','yaml'}
    local cfgContent,err,cfgF	= nil,"",nil
    for k, ext in pairs(yaml_ext) do
      local cfgFileName	= identifier.."."..ext
      local cfgFilePath	= "script-opts".."/"..cfgFileName
            cfgF       	= mp.find_config_file(cfgFilePath)
      if    cfgF == nil then err = err.."failed to find '"..cfgFilePath.."'"  ..'\n'
      else
        local  f, e = io.open(cfgF,"r")
        if     f == nil then err = err.."failed to open '"..cfgF.."' error: "..e..'\n'
        else cfgContent = f:read("*all"); io.close(f) end
      end
    end
    if err then msg.debug(err) end
    return cfgContent, cfgF
  end

  local k_prev,k_top = "","" -- defined outside of ↓ to store recursive compound strings of previous keys
  local opt_change = {}
  local function import_opt(cfg_def, cfg_act, cfg_src, change) -- merge old and new configs
    if change and type(change) ~= 'table' then change = nil
      local warn = "[ignore] wrong argument type: expected 'table'"..
        ", got '"..type(change)..
        "\n  in 'import_opt(...change)' function argument"
      msg.warn(warn)
    end
    local i            	= 0
    local k_def,k_first	= nil
    local def_len      	= std.tlen(cfg_def)
    local act_len      	= std.tlen(cfg_act)
    for k, v in pairs(cfg_act) do
      i = i + 1
      if i == 1 then k_first = k end -- store 1st key to read types from cfg_def if it only has 1 key
      if     (def_len >= act_len) then k_def = k
      elseif (def_len > 1       ) then k_def = k
      else                             k_def = k_first end
      if   cfg_def[k_def] == nil       then
        local warn = "[ignore] unknown key '"..k_prev..k.."' = "..tostring(v)
        if cfg_src then warn = warn.."\n  in '"..cfg_src.."'" end
        msg.warn(warn)
      else
        local  type_def = type(cfg_def[k_def])
        local  type_cfg = type(v)
        if     type_def ~= type_cfg then  -- mismatch
          local warn = "[ignore] wrong key type: "..
            "expected '"..type_def..
            "', got '"  ..type_cfg..
            "' in key '"..k_prev..k.."' = "..tostring(v)
          if cfg_src then warn = warn.."\n  in '"  ..cfg_src.."'" end
          msg.warn(warn)
        elseif type_def == 'table'  then -- → recursively check tables
          k_prev = k_prev..k.."'→'"
          if   change then
               change[k] = v                      -- allows setting change status to leaf keys ↓
               import_opt(cfg_def[k], cfg_act[k], cfg_src, change[k])
          else import_opt(cfg_def[k], cfg_act[k], cfg_src           ) end
        else                             -- or replace config value with parsed
          if cfg_def[k] ~= v then -- avoids copying
             cfg_def[k]  = v
            if change then change[k]  = true  end -- set change status to leaf keys
          else
            if change then change[k]  = false end
          end
        end
      end
    end
    k_prev = ""
  end

  -- 1. Import YAML config
  local cfg_yaml, cfg_file = read_yaml_config(identifier)  -- 1a. read yaml config
  local cfg_parsed = nil
  local function try_parse_yaml() cfg_parsed = parse_yaml(cfg_yaml) end -- pcall accepts fn, not fn(arg)
  if    cfg_yaml ~= nil and not pcall(try_parse_yaml) then msg.warn("failed to parse YAML config")
  else import_opt(opts, cfg_parsed, cfg_file) end          -- 1b. merge yaml config

  -- 2. Import CLI config (overrides 1.)
  local cfg_src      	= 'command line'
  local cfg_parsed   	= nil
  local cli_prefix   	= identifier.."-"
  local cli_prefix_re	= cli_prefix:escmagic()
  local cfg_cli_raw  	= mp.get_property_native("options/script-opts")              -- 2a. read cli opt
  local function parse_prefix_cfg(cfg, cfg_src)
    local cfg_cli_parsed	= {}
    for k, v in pairs(cfg) do
      if k:startswith(cli_prefix) then cfg_cli_parsed[k:gsub(cli_prefix_re,'',1)]=v end end
    return cfg_cli_parsed
  end
  if   next(cfg_cli_raw) ~= nil then cfg_parsed = parse_prefix_cfg(cfg_cli_raw, cfg_src)
    if next(cfg_parsed ) ~= nil then import_opt(opts, cfg_parsed, cfg_src) end end -- 2b. merge cli opt

  -- 3. Register auto-update function
  if on_update then mp.observe_property("options/script-opts", "native", function(name, opt_new)
    local cfg_src   	= 'on_update'
    local cfg_parsed	= nil
    local opt_change	= {}
    if   next(opt_new   ) ~= nil then cfg_parsed = parse_prefix_cfg(opt_new,cfg_src) -- 3a. merge new opt
      if next(cfg_parsed) ~= nil then import_opt(opts, cfg_parsed, cfg_src, opt_change) end end
    if next(opt_change) ~= nil then on_update(opt_change) end
    end)
  end
end

return {
  std = std,
}
