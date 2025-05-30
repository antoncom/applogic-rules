local func_vars_builder = require "applogic.util.func_vars_builder"
local last_mdfr_name = require "applogic.util.last_mdfr_name"
local util = require "luci.util"

function frozen_func(varname, rule, mdf_name) --[[
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
    local seconds_to_froze = 0
    local value_after_unfroze = nil

    -- local body = varlink.modifier[mdf_name]
    local func = varlink.modifier[mdf_name]

    -- Keep value of variable wile first time modifier applied
    if not varlink.frozen then

        -- local luacode = substitute(varname, rule, body, false, true)
        local vars = func_vars_builder.make_vars(varname, rule, false)

        -- noerror, res = pcallchunk(luacode)
        if(type(func) == "function") then
            local tmp_res
            noerror, tmp_res = pcall(func, vars)

            if (type(tmp_res) == "table") then
                seconds_to_froze = tmp_res[1] or 0
                value_after_unfroze = tmp_res[2] or nil
            else
                seconds_to_froze = tmp_res or 0
            end
        else
            seconds_to_froze = 0
            noerror = false
        end

        if (tonumber(seconds_to_froze) and (noerror == true)) then
            local delay = seconds_to_froze and tonumber(seconds_to_froze)
            if delay and delay > 0 and delay < max_seconds then
                if (type(varlink.subtotal) == "table") then
                    varlink.subtotal = util.serialize_json(varlink.subtotal)
                elseif (type(varlink.subtotal) == "number" or type(varlink.subtotal) == "string") then
                    varlink.subtotal = tostring(varlink.subtotal)
                end
                varlink.frozen = {
                    seconds = delay,
                    cancel_time = os.time() + delay,
                    value = tostring(varlink.subtotal),
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

    -- Check delay and unfroze variable's value if time is up
    if (noerror == true) then
        if varlink.frozen and varlink.frozen.cancel_time then
            -- Update Frozen modifier seconds_to_froze (for debug)
            --frozen_value = tostring(varlink.frozen.value)
            frozen_value = varlink.frozen.value
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
                    seconds_to_froze = string.format("%s", seconds)
                    debug(varname, rule):modifier(mdf_name, "Frozen duration:", seconds_to_froze, noerror)
                end
            end
        end
    else
        if rule.debug_mode.enabled then debug(varname, rule):modifier(mdf_name, "Frozen duration:", "Wrong frozen value. Check rule!", noerror) end
    end

    return frozen_value
end
return frozen_func
