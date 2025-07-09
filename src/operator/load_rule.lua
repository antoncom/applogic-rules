-- operator: load-rule
-- ["load-rule"] = {
--      rulename = "rule name",
--      nodename = "var name",
-- }
local function load_rule(rule, nodename, op_name, op_body)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.node.debug" end

    local result
    local noerror = true
    local err = ""

    local RULE_EXISTS = (rule.all_rules[op_body.rulename] ~= nil)
    local VAR_EXISTS = RULE_EXISTS and (rule.all_rules[op_body.rulename].setting[op_body.nodename] ~= nil)

    if not RULE_EXISTS then
        noerror = false
        err = string.format("There is no [%s] in the active rules list. Try 'ubus call applogic list' shell command!", op_body.rulename)
    elseif not VAR_EXISTS then
        noerror = false
        err = string.format("There is no [%s] variable in [%s]. Try ubus call applogic vars '{\"rule\":\"%s\"}'!", op_body.nodename, op_body.rulename, op_body.rulename)
    else
        result = rule.all_rules[op_body.rulename].setting[op_body.nodename].output or ""
    end

    if rule.debug_mode.enabled then
        if (noerror) then
            debug(nodename, rule):operator_rule(op_body.rulename, op_body.nodename, result, noerror)
        else
            debug(nodename, rule):operator_rule(op_body.rulename, op_body.nodename, err, noerror)
        end
    end

    return result
end

return load_rule