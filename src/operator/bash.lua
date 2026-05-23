local sys = require "luci.sys"

-- operator: bash
-- ["bash"] = [[ <bash code> ]]

-- Оператор [bash] позволяет выполнить произвольную shell-команду.
-- Результат выпонения возвращается в узел.

local function bash(rule, nodename, op_name, op_body)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.node.debug" end

    local nodelink = rule.setting[nodename] or {}
    local command = op_body and op_body:gsub("^%s+", ""):gsub("%s$", "") or ""

    local result = {}
    local noerror = true

    command = substitute(rule, command, true)

    -- Because we already probably have initial value (or from previous operator)
    -- we need to prepend "echo ... | " before new bash command

    local command_extra = ""
    if (nodelink.output:len() > 0 and nodelink.output ~= "\"\"" and nodelink.output ~= "''") then
        -- Remove "'" from bash command to prevent errors
        rule.setting[nodename].output = rule.setting[nodename].output:gsub("'", "")
        command_extra = string.format("echo '%s' | %s", rule.setting[nodename].output, command)
        command_extra = command_extra:gsub("%c", "")

        result = sys.process.exec({"/bin/sh", "-c", command_extra }, true, true, true)

        if result.stdout then
            result.stdout = result.stdout:gsub("%c", "")
        end
    end

    noerror = (not result.stderr)
    if rule.debug_mode.enabled then
        debug(nodename, rule):operator_bash(op_name, command_extra, result, noerror)
    end

    return result.stdout or ""
end

return bash
