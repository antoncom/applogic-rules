require "applogic.util.str_helpers"

function substitute(varname, rule, chunk, from_input, put_in_quotes)
    local body = string.format("%s", (chunk or ""))

    for name, _ in pairs(rule.setting) do
        if name ~= varname then
            if put_in_quotes then
                body = body:gsub('$'..name, tostring(rule.setting[name].output):quoted())
            else
                body = body:gsub('$'..name, tostring(rule.setting[name].output))
            end
        else
            if from_input then
                if put_in_quotes then
                    body = body:gsub('$'..varname, tostring(rule.setting[name].input):quoted())
                else
                    body = body:gsub('$'..varname, tostring(rule.setting[name].input))
                end
                --body = body:gsub('$'..varname, tostring(rule.setting[varname].output))
            else
                if put_in_quotes then
                    body = body:gsub('$'..varname, tostring(rule.setting[name].subtotal):quoted())
                else
                    body = body:gsub('$'..varname, tostring(rule.setting[name].subtotal))
                end
                --body = body:gsub('$'..varname, tostring(rule.setting[varname].subtotal))
            end
        end
    end
    return body
end
return substitute
