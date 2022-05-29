
function substitute(varname, rule, chunk, from_output)
    local body = string.format("%s", (chunk or ""))

    --print("<<ISFIRST>> "..varname, from_output)
    for name, _ in pairs(rule.setting) do
        if name ~= varname then
            body = body:gsub('$'..name, tostring(rule.setting[name].output))
        else
            if from_output then
                body = body:gsub('$'..varname, tostring(rule.setting[varname].output))
            else
                body = body:gsub('$'..varname, tostring(rule.setting[varname].subtotal))
            end
        end
    end
    return body
end
return substitute
