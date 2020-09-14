local M = {}

M.is_windows = sys.get_sys_info().platform == "Windows"

function M.mkdir(filename)
	-- Very hack-y workaround, will make a better solution
	local path = (filename:sub(1,1) == "/" and "/" or "")
	for i in filename:gmatch("([^/]+)/?") do
		path = path .. i .. "/"

		lfs.mkdir(path)
	end
end

function M.enclosing_folder(filename)
	return filename:match("(.+)/[^/]+$")
end

function M.file_exists(filename)
	local exists = io.open(filename, "rb")
	if exists then io.close(exists) end
	return exists ~= nil
end

function M.to_unix(path)
	if M.is_windows then
		path = path:gsub("\\", "/")
	end
	return path
end

function M.to_platform(path)
	if M.is_windows then
		path = path:gsub("/", "\\")
	end
	return path
end

return M