
local last_mdfr_name = require "applogic.util.last_mdfr_name"

function frozen(varname, rule, mdf_name) --[[
    To froze variable value once it calculated first time.
    Should return number of seconds to froze.
    ----------------------------------------]]
    local debug
    if rule.debug then debug = require "applogic.var.debug".init(rule) end
    local varlink = rule.setting[varname]
    local max_seconds = 31536000
    local noerror = true
    local frozen_value = ""
    local result = ""

    local body = varlink.modifier[mdf_name]

    if not varlink.frozen then
        local delay = body and tonumber(body)
        if delay and delay > 0 and delay < max_seconds then
            varlink.frozen = {
                seconds = delay,
                cancel_time = os.time() + delay,
                value = string.format("%s", varlink.subtotal),
            }
            frozen_value = varlink.frozen.value
        else
            noerror = false
        end
    end

    if varlink.frozen and varlink.frozen.cancel_time then
        -- Update Frozen modifier result (for debug)
        frozen_value = tostring(varlink.frozen.value)
        local now = os.time()
        if (now > varlink.frozen.cancel_time) then
            varlink.frozen = nil
            if rule.debug then debug(varname):modifier(mdf_name, "Frozen until:", "Unfrozen", noerror) end
        else
            local time = os.date("%X", varlink.frozen.cancel_time)
            local remains = varlink.frozen.cancel_time - now
            result = string.format("%s, remains: %s sec.", time, remains)

            if rule.debug then debug(varname):modifier(mdf_name, "Frozen until:", result, noerror) end
        end
    end

    return frozen_value
end
return frozen
