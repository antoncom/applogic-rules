local sys = require "luci.sys"

-- operator: bash
-- ["bash"] = [[ <bash code> ]]
local function bash(rule, node_name, op_name, op_body, op_index)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

    local node_table = rule.setting[node_name] or {}
    local command = op_body and op_body:gsub("^%s+", ""):gsub("%s$", "") or ""

    local result = {}
    local noerror = true

    local from_input = (not node_table.source) and (op_index == 1)
    command = substitute(node_name, rule, command, from_input, true)

    -- Because we already probably have initial value (or from previous modifier)
    -- we need to prepend "echo ... | " before new bash command

    local command_extra = ""
    if (node_table.subtotal:len() > 0 and node_table.subtotal ~= "\"\"" and node_table.subtotal ~= "''") then
        -- Remove "'" from bash command to prevent errors
        rule.setting[node_name].subtotal = rule.setting[node_name].subtotal:gsub("'", "")
        command_extra = string.format("echo '%s' | %s", rule.setting[node_name].subtotal, command)

        command_extra = command_extra:gsub("%c", "")
        --if varname == "ussd_command" then print("COMMAND_EXTRA=", command_extra) end
        result = sys.process.exec({"/bin/sh", "-c", command_extra }, true, true, true)

        if result.stdout then
            result.stdout = result.stdout:gsub("%c", "")
        end
    end

    noerror = (not result.stderr)
    if rule.debug_mode.enabled then
        debug(node_name, rule):modifier_bash(op_name, command_extra, result, noerror)
    end

    return result.stdout or ""
end

return bash
