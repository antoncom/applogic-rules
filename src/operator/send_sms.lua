local util = require 'luci.util'

-- operator: send-sms
-- ["send-sms"] = {
--      phone = "recipient phone number",
--      text = "sms text",
-- }
local function send_sms(rule, nodename, op_name, op_body)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.node.debug" end

    local params = {
        phone = substitute(rule, op_body["phone"], false),
        text = substitute(rule, op_body["text"], false),
    }

    local result = util.ubus("tsmodem.sms", "send_sms", params) -- todo: check result status

    if rule.debug_mode.enabled then
        local params_str = util.serialize_json(params)
        var_debug(nodename, rule):operator_send_sms(op_name, params_str, result, result ~= nil)
    end

    return result
end

return send_sms