
local last_mdfr_name = require "applogic.util.last_mdfr_name"

function frozen(varname, rule, mdf_name) --[[
    To froze variable value once it calculated first time.
    Should return number of seconds to froze.
    Or it may return table like this {seconds, "value after unfroze"}.
    ----------------------------------------]]
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

    local varlink = rule.setting[varname]
    local max_seconds = 31536000
    local noerror = true
    local frozen_value = ""
    local result = 0
    local value_after_unfroze = nil

    local body = varlink.modifier[mdf_name]

    if not varlink.frozen then

        local luacode = substitute(varname, rule, body, false, true)

        noerror, res = pcallchunk(luacode)

        if (type(res) == "table") then
            result = res[1] or 0
            value_after_unfroze = res[2] or nil
        else
            result = res or 0
        end

        if (tonumber(result) and (noerror == true)) then
            local delay = result and tonumber(result)
            if delay and delay > 0 and delay < max_seconds then
                varlink.frozen = {
                    seconds = delay,
                    cancel_time = os.time() + delay,
                    value = string.format("%s", varlink.subtotal),
                    value_after = value_after_unfroze
                }
                frozen_value = varlink.frozen.value

                -- ADDON TMPL
                if (noerror) then
                    varlink["frozee"] = varlink.subtotal
                end

            elseif delay == 0 then
                noerror = true
                varlink["frozee"] = nil
            else
                noerror = false
            end
        end
    end

    if (noerror == true) then
        if varlink.frozen and varlink.frozen.cancel_time then
            -- Update Frozen modifier result (for debug)
            frozen_value = tostring(varlink.frozen.value)
            local now = os.time()
            if (now > varlink.frozen.cancel_time) then
                -- After unfroze put predefined value to the var output
                if (varlink.frozen.value_after) then
                    varlink.subtotal = tostring(varlink.frozen.value_after)
                    varlink.input = tostring(varlink.frozen.value_after)
                end
                varlink.frozen = nil

                -- ADDON TMPL
                varlink["frozee"] = nil

                if rule.debug_mode.enabled then debug(varname, rule):modifier(mdf_name, "Frozen until:", "", noerror) end
            else
                if rule.debug_mode.enabled then
                    local remains = varlink.frozen.cancel_time - now
                    local seconds = varlink.frozen.seconds
                    result = string.format("%s", seconds)
                    debug(varname, rule):modifier(mdf_name, "Frozen duration:", result, noerror)
                end
            end
        end
    else
        if rule.debug_mode.enabled then debug(varname, rule):modifier(mdf_name, "Frozen duration:", "Wrong frozen value. Check rule!", noerror) end
    end

    return frozen_value
end
return frozen
