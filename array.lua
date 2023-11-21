local Array = {}

function Array.new(array)
	return setmetatable(array, { __index = Array })
end

function Array:find(predicate)
	for _, value in ipairs(self) do
		if predicate(value) then return value end
	end
end

return setmetatable(Array, { __call = function(_, array) return Array.new(array) end })