-- operator: load-rule
-- ["load-rule"] = {
--      rulename = "rule name",
--      varname = "var name",
-- }
local function load_rule(rule, node_name, op_name, op_body, op_index)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

    local result
    local noerror = true
    local err = ""

    local RULE_EXISTS = (rule.all_rules[op_body.rulename] ~= nil)
    local VAR_EXISTS = RULE_EXISTS and (rule.all_rules[op_body.rulename].setting[op_body.varname] ~= nil)

    if not RULE_EXISTS then
        noerror = false
        err = string.format("There is no [%s] in the active rules list. Try 'ubus call applogic list' shell command!", op_body.rulename)
    elseif not VAR_EXISTS then
        noerror = false
        err = string.format("There is no [%s] variable in [%s]. Try ubus call applogic vars '{\"rule\":\"%s\"}'!", op_body.varname, op_body.rulename, op_body.rulename)
    else
        result = rule.all_rules[op_body.rulename].setting[op_body.varname].output or ""
    end

    if rule.debug_mode.enabled then
        if (noerror) then
            debug(node_name, rule):source_rule(op_body.rulename, op_body.varname, result, noerror)
        else
            debug(node_name, rule):source_rule(op_body.rulename, op_body.varname, err, noerror)
        end
    end

    return result
end

return load_rule