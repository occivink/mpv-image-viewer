local std	= require "lib/std".std

local color = {} -- color helper functions

-- functions adapted from
-- https://github.com/EmmanuelOga/columns/blob/master/utils/color.lua
-- https://github.com/bottosson/bottosson.github.io/blob/master/misc/colorpicker/colorconversion.js
local function toe_inv(x)
  local k_1 = 0.206
  local k_2 = 0.03
  local k_3 = (1+k_1)/(1+k_2)
  return (x*x + k_1*x)/(k_3*(x+k_2))
end
local function srgb_transfer_function(a)
  if .0031308 >= a then return 12.92 * a
  else                  return 1.055 * a^(.4166666666666667) - .055 end
end
local function oklab2linear_srgb(L,a,b)
  local l_ = L + 0.3963377774 * a + 0.2158037573 * b
  local m_ = L - 0.1055613458 * a - 0.0638541728 * b
  local s_ = L - 0.0894841775 * a - 1.2914855480 * b

  local l = l_*l_*l_
  local m = m_*m_*m_
  local s = s_*s_*s_

  return ( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
         (-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
         (-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
end
local function compute_max_saturation(a, b) -- Finds the maximum saturation possible for a given hue that fits in sRGB Saturation here is defined as S = C/L a and b must be normalized so a^2 + b^2 == 1
  -- Max saturation will be when one of r, g or b goes below zero
  -- Select different coefficients depending on which component goes below zero first
  local k0, k1, k2, k3, k4, wl, wm, ws

  if     (-1.88170328 * a - 0.80936493 * b > 1) then -- Red component
    k0 = 1.19086277   ; k1 =  1.76576728  ; k2 =  0.59662641  ; k3 =  0.75515197; k4 = 0.56771245
    wl = 4.0767416621 ; wm = -3.3077115913; ws =  0.2309699292
  elseif ( 1.81444104 * a - 1.19445276 * b > 1) then -- Green component
    k0 =  0.73956515  ; k1 = -0.45954404  ; k2 =  0.08285427  ; k3 =  0.12541070; k4 = 0.14503204
    wl = -1.2684380046; wm =  2.6097574011; ws = -0.3413193965
  else                                               -- Blue component
    k0 =  1.35733652  ; k1 = -0.00915799  ; k2 = -1.15130210  ; k3 = -0.50559606; k4 = 0.00692167
    wl = -0.0041960863; wm = -0.7034186147; ws =  1.7076147010
  end

  local S = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b -- Approximate max saturation using a polynomial

  -- 1 step Halley's method to get closer; error < 10e6, except for some blue hues where the dS/dh ≈ ∞
  -- should be sufficient for most applications, otherwise do two/three steps
  local k_l =  0.3963377774 * a + 0.2158037573 * b
  local k_m = -0.1055613458 * a - 0.0638541728 * b
  local k_s = -0.0894841775 * a - 1.2914855480 * b

  local l_   	= 1 + S * k_l
  local m_   	= 1 + S * k_m
  local s_   	= 1 + S * k_s
  --         	--
  local l    	= l_ * l_ * l_
  local m    	= m_ * m_ * m_
  local s    	= s_ * s_ * s_
  --         	--
  local l_dS 	= 3 * k_l * l_ * l_
  local m_dS 	= 3 * k_m * m_ * m_
  local s_dS 	= 3 * k_s * s_ * s_
  --         	--
  local l_dS2	= 6 * k_l * k_l * l_
  local m_dS2	= 6 * k_m * k_m * m_
  local s_dS2	= 6 * k_s * k_s * s_
  --         	--
  local f    	= wl * l     + wm * m     + ws * s
  local f1   	= wl * l_dS  + wm * m_dS  + ws * s_dS
  local f2   	= wl * l_dS2 + wm * m_dS2 + ws * s_dS2

  S = S - f * f1 / (f1*f1 - 0.5 * f * f2)

  return S
end
local function find_cusp(a, b)
  local S_cusp = compute_max_saturation(a, b) -- find the maximum saturation (saturation S = C/L)

  -- Convert to linear sRGB to find the first point where at least one of r,g or b >= 1
  local r, g, b	= oklab2linear_srgb(1, S_cusp * a, S_cusp * b) -- rgb@max
  local L_cusp 	= (1 / math.max(math.max(r,g), b))^(1/3)
  local C_cusp 	= L_cusp * S_cusp

  return {L_cusp , C_cusp}
end
function find_gamut_intersection(a, b, L1, C1, L0, cusp) -- Finds intersection of the line defined by
  -- L = L0 * (1 - t) + t * L1;
  -- C = t * C1;
  -- a and b must be normalized so a^2 + b^2 == 1
  if not cusp then cusp = find_cusp(a,b) end -- Find the cusp of the gamut triangle

  -- Find the intersection for upper and lower half seprately
  local t
  if ((L1 - L0) * cusp[2] - (cusp[1] - L0) * C1) <= 0 then -- Lower half
    t = cusp[2] * L0 / (C1 * cusp[1] + cusp[2] * (L0 - L1));
  else                                                       -- Upper half
    -- First intersect with triangle
    t = cusp[2] * (L0 - 1) / (C1 * (cusp[1] - 1) + cusp[2] * (L0 - L1));

    -- Then one step Halley's method
    local dL  	= L1 - L0;
    local dC  	= C1;
    --        	--
    local k_l 	=  0.3963377774 * a + 0.2158037573 * b;
    local k_m 	= -0.1055613458 * a - 0.0638541728 * b;
    local k_s 	= -0.0894841775 * a - 1.2914855480 * b;
    --        	--
    local l_dt	= dL + dC * k_l;
    local m_dt	= dL + dC * k_m;
    local s_dt	= dL + dC * k_s;

    -- For higher accuracy do 2 or 3 iterations of the following
    local L   	= L0 * (1 - t) + t * L1;
    local C   	= t * C1;
    --        	--
    local l_  	= L + C * k_l;
    local m_  	= L + C * k_m;
    local s_  	= L + C * k_s;
    --        	--
    local l   	= l_ * l_ * l_;
    local m   	= m_ * m_ * m_;
    local s   	= s_ * s_ * s_;
    --        	--
    local ldt 	= 3 * l_dt * l_ * l_;
    local mdt 	= 3 * m_dt * m_ * m_;
    local sdt 	= 3 * s_dt * s_ * s_;
    --        	--
    local ldt2	= 6 * l_dt * l_dt * l_;
    local mdt2	= 6 * m_dt * m_dt * m_;
    local sdt2	= 6 * s_dt * s_dt * s_;
    --        	--
    local r   	= 4.0767416621 * l    - 3.3077115913 * m    + 0.2309699292 * s - 1;
    local r1  	= 4.0767416621 * ldt  - 3.3077115913 * mdt  + 0.2309699292 * sdt;
    local r2  	= 4.0767416621 * ldt2 - 3.3077115913 * mdt2 + 0.2309699292 * sdt2;
    --        	--
    local u_r 	= r1 / (r1 * r1 - 0.5 * r * r2);
    local t_r 	= -r * u_r;
    --        	--
    local g   	= -1.2684380046 * l    + 2.6097574011 * m    - 0.3413193965 * s - 1;
    local g1  	= -1.2684380046 * ldt  + 2.6097574011 * mdt  - 0.3413193965 * sdt;
    local g2  	= -1.2684380046 * ldt2 + 2.6097574011 * mdt2 - 0.3413193965 * sdt2;
    --        	--
    local u_g 	= g1 / (g1 * g1 - 0.5 * g * g2);
    local t_g 	= -g * u_g;
    --        	--
    local b   	= -0.0041960863 * l    - 0.7034186147 * m    + 1.7076147010 * s - 1;
    local b1  	= -0.0041960863 * ldt  - 0.7034186147 * mdt  + 1.7076147010 * sdt;
    local b2  	= -0.0041960863 * ldt2 - 0.7034186147 * mdt2 + 1.7076147010 * sdt2;
    --        	--
    local u_b 	= b1 / (b1 * b1 - 0.5 * b * b2);
    local t_b 	= -b * u_b;

    if u_r < 0 then t_r	= 10e5 end
    if u_g < 0 then t_g	= 10e5 end
    if u_b < 0 then t_b	= 10e5 end

    t = t + math.min(t_r, math.min(t_g,t_b))
  end

  return t
end

function get_ST_max(a_,b_, cusp)
  if not cusp then cusp = find_cusp(a_, b_) end

  local L = cusp[1]
  local C = cusp[2]
  return {C/L, C/(1-L)}
end

local function get_ST_mid(a_,b_)
  local S = 0.11516993 + 1/(
   0+ 7.44778970 + 4.15901240*b_
    + a_*(-2.19557347 + 1.75198401*b_
    + a_*(-2.13704948 -10.02301043*b_
    + a_*(-4.24894561 + 5.38770819*b_ + 4.69891013*a_ )))
    )

  local T = 0.11239642 + 1/(
   0+ 1.61320320 - 0.68124379*b_
    + a_*( 0.40370612 + 0.90148123*b_
    + a_*(-0.27087943 + 0.61223990*b_
    + a_*( 0.00299215 - 0.45399568*b_ - 0.14661872*a_ )))
    )

  return {S, T}
end
local function get_Cs(L, a_, b_)
  local cusp  	= find_cusp(a_, b_)
  local C_max 	= find_gamut_intersection(a_,b_,L,1,L,cusp)
  local ST_max	= get_ST_max(a_, b_, cusp)

  local S_mid = 0.11516993 + 1/(0
    +      7.44778970 + 4.15901240*b_
    + a_*(-2.19557347 + 1.75198401*b_
    + a_*(-2.13704948 -10.02301043*b_
    + a_*(-4.24894561 + 5.38770819*b_ + 4.69891013*a_ )))
    )

  local T_mid = 0.11239642 + 1/(0
    +      1.61320320 - 0.68124379*b_
    + a_*( 0.40370612 + 0.90148123*b_
    + a_*(-0.27087943 + 0.61223990*b_
    + a_*( 0.00299215 - 0.45399568*b_ - 0.14661872*a_ )))
    )

  local k = C_max/math.min((L*ST_max[1]), (1-L)*ST_max[2])

  local C_mid
  local C_a = L*S_mid
  local C_b = (1-L)*T_mid
  C_mid = 0.9*k*math.sqrt(math.sqrt(1/(1/(C_a*C_a*C_a*C_a) + 1/(C_b*C_b*C_b*C_b))))

  local C_0
  local C_a = L*0.4
  local C_b = (1-L)*0.8
  C_0 = math.sqrt(1/(1/(C_a*C_a) + 1/(C_b*C_b)))

  return {C_0, C_mid, C_max}
end

function color.hsl2rgb(h, s, l)
  if type(h) == 'string' then h = tonumber(h)      end  -- normalize str→num
  if type(s) == 'string' then s = tonumber(s)      end
  if type(l) == 'string' then l = tonumber(l)      end
  if      h   > 1        then h =          h / 360 end  -- normalize
  if      s   > 1        then s =          s / 100 end
  if      l   > 1        then l =          l / 100 end
  local r,g,b

  if (s == 0) then r,g,b = l,l,l  -- achromatic
  else
    local function hue2rgb(p, q, t)
      if     (t < 0  ) then t = t + 1
      elseif (t > 1  ) then t = t - 1 end
      if     (t < 1/6) then return p + (q - p) *        t  * 6
      elseif (t < 3/6) then return      q
      elseif (t < 4/6) then return p + (q - p) * (2/3 - t) * 6
      else                  return p end
    end

    local q
    if (l < 1/2) then q = l * (1 + s)
    else              q = l * (1 - s) + s end
    local p = 2 * l - q
    r = hue2rgb(p, q, h + 1/3)
    g = hue2rgb(p, q, h      )
    b = hue2rgb(p, q, h - 1/3)
  end
  return -- min to avoid returning values > 255; also round
    std.round(255*math.min(r,1)),
    std.round(255*math.min(g,1)),
    std.round(255*math.min(b,1))
end

function color.okhsl2srgb(h,s,l)
  if type(h) == 'string' then h = tonumber(h)      end  -- normalize str→num
  if type(s) == 'string' then s = tonumber(s)      end
  if type(l) == 'string' then l = tonumber(l)      end
  if      h   > 1        then h =          h / 360 end  -- normalize
  if      s   > 1        then s =          s / 100 end
  if      l   > 1        then l =          l / 100 end
  local r,g,b

  if     (l == 1) then return 255,255,255
  elseif (l == 0) then return   0,  0,  0 end

  local a_	= math.cos(2*math.pi * h)
  local b_	= math.sin(2*math.pi * h)
  local L 	= toe_inv(l)

  local Cs   	= get_Cs(L, a_, b_)
  local C_0  	= Cs[1]
  local C_mid	= Cs[2]
  local C_max	= Cs[3]

  local C, t, k_0, k_1, k_2
  if (s < 0.8) then
    t  	= 1.25*s
    k_0	= 0
    k_1	= 0.8*C_0
    k_2	= (1 - k_1/C_mid)
  else
    t  	= 5*(s-0.8)
    k_0	=     C_mid
    k_1	= 0.2*C_mid*C_mid*1.25*1.25/C_0
    k_2	= (1 - k_1/(C_max - C_mid))
  end

  C = k_0 + t*k_1/(1-k_2*t)

  -- If we would only use one of the Cs:
  -- C = s*C_0
  -- C = s*1.25*C_mid
  -- C = s*C_max

  r,g,b = oklab2linear_srgb(L, C*a_, C*b_)
  return -- min to avoid returning values > 255; also round
    std.round(255*math.min(srgb_transfer_function(r),1)),
    std.round(255*math.min(srgb_transfer_function(g),1)),
    std.round(255*math.min(srgb_transfer_function(b),1))
end


function color.hex2rgb(hex) -- also converts short rgbs
  -- https://gist.github.com/fernandohenriques/12661bf250c8c2d8047188222cab7e28
  local hex = hex:gsub("#","")
  local len = hex:len()
  if     len == 2 then return  tonumber("0x"..hex:sub(1,2))    /255,  -- short #CC
                               tonumber("0x"..hex:sub(1,2))    /255,
                               tonumber("0x"..hex:sub(1,2))    /255
  elseif len == 3 then return (tonumber("0x"..hex:sub(1,1))*17)/255,  -- short #RGB
                              (tonumber("0x"..hex:sub(2,2))*17)/255,
                              (tonumber("0x"..hex:sub(3,3))*17)/255
  elseif len == 6 then return  tonumber("0x"..hex:sub(1,2))    /255,  -- regular #RRGGBB
                               tonumber("0x"..hex:sub(3,4))    /255,
                               tonumber("0x"..hex:sub(5,6))    /255
  else   print("wrong input length ("..len.."), should be 2, 3, or 6 symbols without #: "..hex) end
end
function color.hex2a(hex)
  local hex = hex:gsub("#","")
  local len = hex:len()
  if     len == 2 then return  tonumber("0x"..hex:sub(1,2))    /255   -- short #AA
  else   print("wrong input length ("..len.."), should be 2 symbols without #: "..hex) end
end
function color.hex2rev(hex)
  local hex = hex:gsub("#","")
  local len = hex:len()
  local hexbgr
  if     len == 2 then hexbgr = hex:sub(1,2)..hex:sub(1,2)..hex:sub(1,2)
  elseif len == 3 then hexbgr = hex:sub(3,3)..hex:sub(2,2)..hex:sub(1,1)
  elseif len == 6 then hexbgr = hex:sub(5,6)..hex:sub(3,4)..hex:sub(1,2)
  else   print("wrong input length ("..len.."), should be 2, 3, or 6 symbols without #: "..hex) end
  return hexbgr, "#"..tostring(hexbgr)
end
function color.rgb2hex(r,g,b)
  if type(r) == 'string' then r = tonumber(r)      end  -- normalize str→num
  if type(g) == 'string' then g = tonumber(g)      end
  if type(b) == 'string' then b = tonumber(b)      end
  if r>255 or g>255 or b>255 then print("error: r,g,b > 255"); return end
  if r<  0 or g<  0 or b<  0 then print("error: r,g,b < 0"  ); return end
  local hex = string.format("%02X%02X%02X",r,g,b)
  return hex   , "#"..tostring(hex)
end
function color.rgb2hexbgr(r,g,b)
  if type(r) == 'string' then r = tonumber(r)      end  -- normalize str→num
  if type(g) == 'string' then g = tonumber(g)      end
  if type(b) == 'string' then b = tonumber(b)      end
  if r>255 or g>255 or b>255 then print("error: r,g,b > 255"); return end
  if r<  0 or g<  0 or b<  0 then print("error: r,g,b < 0"  ); return end
  return color.rgb2hex(b,g,r)
end
function color.a2hex(a)
  if type(a) == 'string' then a = tonumber(a)      end  -- normalize str→num
  if a>255 then print("error: a > 255"); return end
  if a<  0 then print("error: a < 0"  ); return end
  local hex = string.format("%02X",a)
  return hex   , "#"..tostring(hex)
end

function color.convert2mpv(color_space, col_in, sep)
  if sep == nil then sep = ' ' end
  if col_in:startswith("#") then
    if not color_space == "hex" then
      print("color type mismatch: passed hex color ("..col_in.."), but non-hex color space ("..color_space..")")
      color_space = "hex" end end
  local col_conv
  if     color_space:lower() == "okhsl" then
    local hsl  	= col_in:splitflex(sep)
    local r,g,b	= color.okhsl2srgb(hsl[1],hsl[2],hsl[3])
    col_conv   	= color.rgb2hexbgr(r,g,b)
  elseif color_space:lower() == "hsl"   then
    local hsl  	= col_in:splitflex(sep)
    local r,g,b	= color.hsl2rgb(hsl[1],hsl[2],hsl[3])
    col_conv   	= color.rgb2hexbgr(r,g,b)
  elseif color_space:lower() == "hex"   then
    col_conv	= color.hex2rev(col_in)
  end
  return col_conv
end

return {
  color = color,
}
