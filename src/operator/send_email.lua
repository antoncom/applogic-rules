local uci = require "luci.model.uci".cursor()
local util = require 'luci.util'

-- operator: send-email
-- ["send-email"] = {
--      to = "recipient",
--      from = "sender",
--      subj = "email title",
--      body = "email message",
-- }
local function send_email(rule, nodename, op_name, op_body)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.node.debug" end

    local params = {
        from = uci:get("tsmail", "general", "auth_user"),
        to = substitute(rule, op_body["to"], false),
        subj = substitute(rule, op_body["subj"], false),
        body = substitute(rule, op_body["body"], false),
    }

    local result = util.ubus("tsmail", "send", params) -- todo: check result status

    if rule.debug_mode.enabled then
        local params_str = util.serialize_json(params)
        var_debug(nodename, rule):operator_send_email(op_name, params_str, result, result ~= nil)
    end

    return result
end

return send_email