require "applogic.util.str_helpers"

function substitute(rule, chunk, put_in_quotes)
    local body = string.format("%s", (chunk or ""))

    for name, _ in pairs(rule.setting) do
        if put_in_quotes then
            body = body:gsub('$'..name, tostring(rule.setting[name].output):quoted())
        else
            body = body:gsub('$'..name, tostring(rule.setting[name].output))
        end
    end

    return body
end

return substitute
