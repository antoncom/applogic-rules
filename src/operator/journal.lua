local util = require "luci.util"
local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

-- Define the LevelDB database path
-- local inmemory_db_path = uci:get("tsmjournal", "database", "inmemory")
-- local ondisk_db_path = uci:get("tsmjournal", "database", "ondisk")


-- Function to store data in the database using db_utils
local function journal(rule, nodename, op_name, op_body)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.node.debug" end

    local vars = func_vars_builder.make_vars(rule)

    local result = ""
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

    result = tmp_res or nil

    local jour_record = {}
    jour_record["journal"] = result or {}
    jour_record["ruleid"] = rule.ruleid

    util.ubus("tsmodem.journal", "send", jour_record)
    --print("[JOURNAL] OPERATOR RUN ......[" .. rule.ruleid .. "]..........[" .. nodename .. "]................................. at: "  .. os.date("%Y-%m-%d %H:%M:%S"))

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        var_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end
end

return journal