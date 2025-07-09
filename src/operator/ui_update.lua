local util = require "luci.util"
local sys  = require "luci.sys"
local pretty = require "applogic.util.prettyjson"

local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

-- operator: ui-update
-- ["ui-update"] = { param_list = { "param1", "param2", etc... } }
local function ui_update(rule, nodename, op_name, op_body)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.node.debug" end

    local pipein_file = "/tmp/wspipein.fifo" -- Gwsocket creates it
    local nodelink = rule.setting[nodename] or {}
    local param_list = op_body.param_list or {}
    local result = {}
    local noerror = true

    if(#param_list > 0) then
        if (file_exists(pipein_file)) then -- Check if pipein file exists
            -- Prepare params to send to UI
            local params, name = {}, ''
            for i=1, #param_list do
                name = param_list[i]
                if name == nodename then
                    if util.contains({ "journal_reg", "journal_usb", "journal_stm" }, name) then
                        name = "journal"
                    end
                    params[name] = nodelink.output or ""
                else
                    params[name] = rule.setting[name] and rule.setting[name].output or ""
                end
            end
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
end

return ui_update