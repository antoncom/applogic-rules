function pcallchunk(chunk)
    local noerror = true
    local result = nil

    local finalcode = chunk and loadstring(chunk)
    if finalcode then
        noerror, result = pcall(finalcode)
        if noerror == false then
            result = nil
        end
    else
        result = nil
        noerror = false
    end

    return noerror, result
end
return pcallchunk
