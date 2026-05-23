local util = require "luci.util"
local func_nodes_builder = require "applogic.util.func_nodes_builder"
local sys  = require "luci.sys"
local pretty = require "applogic.util.prettyjson"

local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

local function ui_update(rule, nodename, op_name, op_body)
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
        local command = string.format("echo '%s' > %s", ui_data, pipein_file)
        result = sys.process.exec({"/bin/sh", "-c", command }, true, true, false)
        if result.stdout then
            result.stdout = result.stdout:gsub("%c", "") .. "\n"
        end

        noerror = (not result.stderr)
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

return ui_update