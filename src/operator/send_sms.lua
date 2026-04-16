-- local util = require 'luci.util'

-- -- operator: send-sms
-- -- ["send-sms"] = {
-- --      phone = "recipient phone number",
-- --      text = "sms text",
-- -- }
-- local function send_sms(rule, nodename, op_name, op_body)
--     local var_debug
--     if rule.debug_mode.enabled then var_debug = require "applogic.node.debug" end

--     local params = {
--         phone = substitute(rule, op_body["phone"], false),
--         text = substitute(rule, op_body["text"], false),
--     }

--     local result = util.ubus("tsmodem.sms", "send_sms", params) -- todo: check result status

--     if rule.debug_mode.enabled then
--         local params_str = util.serialize_json(params)
--         var_debug(nodename, rule):operator_send_sms(op_name, params_str, result, result ~= nil)
--     end

--     return result
-- end

-- return send_sms


local util = require 'luci.util'
local func_vars_builder = require "applogic.util.func_vars_builder"


-- operator: send_sms
-- ["send_sms"] = function(nodes)
--      return({
--         phone = "recipient phone number",
--         text = "sms text",
--      })
-- end
local function send_sms(rule, nodename, op_name, op_body)
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

    if tmp_res ~= nil then
        local phone = string.format("%s", (tmp_res.phone or ""))
        local text = string.format("%s", (tmp_res.text or ""))

        local params = {
            phone = phone,
            text = text,
        }

        result = util.ubus("tsmodem.sms", "send_sms", params) -- todo: check result status
    end

    if rule.debug_mode.enabled then
        local params_str = util.serialize_json(params)
        var_debug(nodename, rule):operator_send_sms(op_name, params_str, result, result ~= nil)
    end

    return result
end

return send_sms
