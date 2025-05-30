local func_debug = {}

function func_debug.generate_output_info(func)
    local func_debug_info = debug.getinfo(func)

    local path_to_func = tostring(func_debug_info.source):match(".*applogic/(.*)")
    local ouput_info = "path: " .. tostring(path_to_func) .. ":" .. tostring(func_debug_info.linedefined) .. "\n"
    ouput_info = ouput_info .. "lines: " .. tostring(func_debug_info.linedefined) .. "-" .. tostring(func_debug_info.lastlinedefined) .. "\n"

    return ouput_info
end

return func_debug