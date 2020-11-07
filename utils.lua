local M = {}

M.is_windows = sys.get_sys_info().platform == "Windows"

-- Run function for each file in directory
function M.dir_iter(path, for_each, for_each_dir)
	for file in lfs.dir(path) do
		if file ~= "." and file ~= ".." then
			local f = path .. "/" .. file
			local attr = lfs.attributes(f)
			if attr.mode == "directory" then
				M.dir_iter(f, for_each, for_each_dir)
				if for_each_dir then
					for_each_dir(f)
				end
			else
				for_each(f)
			end
		end
	end
end

function M.mkdir(filename)
	-- Should make a better solution for this
	local path = (filename:sub(1,1) == "/" and "/" or "")
	for i in filename:gmatch("([^/]+)/?") do
		path = path .. i .. "/"

		lfs.mkdir(path)
	end
end

function M.erase_dir(filename)
	M.dir_iter(filename, function(f)
		os.remove(f)
	end, function(f)
		lfs.rmdir(f)
	end)
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
