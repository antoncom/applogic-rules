-- Модуль служебных функций

local uci = require "luci.model.uci".cursor()
local util = require "luci.util"


if_debug = function(title, msg, ...)
   local is_debug = (uci:get("applogic", "debug_mode", "enable") == "1")
   local val = ""

   local colors = {
    reset = "\27[0m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    white = "\27[37m",
    bright_red = "\27[91m",
    bright_green = "\27[92m",
    bright_yellow = "\27[93m",
    bright_blue = "\27[94m",
    bright_magenta = "\27[95m",
    bright_cyan = "\27[96m",
    bright_white = "\27[97m"
   }

   local color = {...}

   if (is_debug) then
      if (msg and type(msg) == "table") then
         val = util.serialize_json(msg)
      elseif (msg and type(msg) == "string") then
         val = msg:gsub("%c", " ")
      else
         val = msg
      end
      local dt = os.date("*t")  
      local ms = string.match(tostring(os.clock()), "%d%.(%d+)")  
      local d = string.format("%d:%d:%d", dt.hour, dt.min, dt.sec)  

      local socket = require 'socket'  
      local now = socket.gettime()  
      local millis = math.floor((now % 1) * 100)  
      if(#color > 0 and #color[1] > 0) then
         print(tostring(colors[color[1]]) .. string.format('%s.%02d', d, millis) .. " [applogic]: " .. tostring(title) .. " " .. tostring(val))
         util.perror(tostring(colors[color[1]]) .. string.format('%s.%02d', d, millis) .. " [applogic]: " .. tostring(title) .. " " .. tostring(val))
      else
         print(colors["white"] .. string.format('%s.%02d', d, millis) .. " [applogic]: " .. tostring(title) .. tostring(val))
         util.perror(colors["white"] .. string.format('%s.%02d', d, millis) .. " [applogic]: " .. tostring(title) .. tostring(val))
      end
      print(colors["white"] .. "\n")
   end
end