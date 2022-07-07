function string:split(sep)
   local sep, fields = sep or ":", {}
   local pattern = string.format("([^%s]+)", sep)
   self:gsub(pattern, function(c) fields[#fields+1] = c end)
   return fields
end

function string:quoted()
    local res = ""
    if (tonumber(self) == nil) then
        res = '"'..self..'"'
    else
        res = self
    end
    return res
end
