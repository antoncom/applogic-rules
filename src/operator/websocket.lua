local util = require "luci.util"
local nixio = require "nixio"
local func_nodes_builder = require "applogic.util.func_nodes_builder"
local pretty = require "applogic.util.prettyjson"

-- Открываем FIFO без блокировки: если Gwsocket не запущен (нет читателя),
-- open() сразу вернёт ошибку ENXIO, и applogic не зависнет.
local FIFO_FLAGS = nixio.open_flags("wronly", "nonblock")

local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

local function websocket(rule, nodename, op_name, op_body)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.node.debug" end
    local pipein_file = "/tmp/wspipein.fifo" -- Gwsocket creates it
    local nodelink = rule.setting[nodename] or {}
    local result = {}
    local noerror = true
    local vars = func_nodes_builder:make_nodes(rule)

    local noerror = true
    local tmp_res

    if type(op_body) == "function" then
        noerror, tmp_res = pcall(op_body, vars)

        if noerror == false then
            print("Error: " .. tostring(tmp_res))
            tmp_res = nil
        end
    else
        tmp_res = nil
        noerror = false
    end

    if (file_exists(pipein_file)) then -- Check if pipein file exists
        local params = tmp_res or {}
        params["ruleid"] = rule.ruleid

        local ui_data = util.serialize_json(params)

        -- Пишем в FIFO напрямую, без запуска /bin/sh на каждое сообщение.
        -- Раньше здесь был sys.process.exec({"/bin/sh", "-c", "echo '...' > fifo"}):
        -- fork+exec shell-а ~10 раз за итерацию (каждые 0.8 сек) заметно грузил CPU.
        -- Заодно больше не ломается JSON, содержащий одинарную кавычку.
        local fifo, err_no, err_msg = nixio.open(pipein_file, FIFO_FLAGS)
        if fifo then
            local written = fifo:write(ui_data .. "\n")
            fifo:close()
            noerror = (written ~= nil)
            result = { stdout = "", stderr = (written == nil) and "write to fifo failed" or nil }
        else
            noerror = false
            result = { stdout = "", stderr = tostring(err_msg) }
        end
        if rule.debug_mode.enabled then
            result.stdout = pretty(params):gsub("\t", "  ")
            debug(nodename, rule):operator(op_name, pretty(param_list):gsub("\t", "  "), result.stdout, noerror)
        end
    else -- if no pipein file (or Gwsocket is not started)
        noerror = false
        if rule.debug_mode.enabled then
            local result_str = "No pipe file existed: " .. pipein_file .. "\nCheck Gwsocket started properly."
            debug(nodename, rule):operator(op_name, pretty(param_list):gsub("\t", "  "), result_str, noerror)
        end
    end
end

return websocket