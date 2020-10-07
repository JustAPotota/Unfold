local M = {}

-- Modules
local protoc = require("pb.protoc")
local sio = require("sio")
local utils = require("utils")

-- Set up protoc
protoc.unknown_module = ""
protoc.unknown_type = ""
protoc.include_imports = true
protoc:load(sys.load_resource("/proto/liveupdate_ddf.proto"))

-- Helper functions
function M.read_int(f)
	local char = f:read(4)
	local total = ""
	for i=1,4 do
		total = total ..string.format("%02X", char:sub(i,i):byte())
	end
	return tonumber(total, 16)
	--return (string.unpack(">i", f:read(4)))
end

function M.build_int(n)
	local h = bit.tohex(n)
	local s = ""
	for i=1,7,2 do
		s = s .. string.char(tonumber(h:sub(i,i+1), 16))
	end
	return s
end

function M.build_long(n)
	return M.build_int(bit.rshift(n, 32)) .. M.build_int(n)
end

function M.read_hash(f, length)
	return string.format(string.rep("%02x", length), string.byte(f:read(length), 1, -1))
end

function M.hex_string(h)
	return string.format(string.rep("%02x", #h), string.byte(h, 1, -1))
end

-- Run function for each file in directory
function M.dir_iter(path, for_each)
	for file in lfs.dir(path) do
		if file ~= "." and file ~= ".." then
			local f = path .. "/" .. file
			local attr = lfs.attributes(f)
			if attr.mode == "directory" then
				M.dir_iter(f, for_each)
			else
				for_each(f)
			end
		end
	end
end


-- Main functions
function M.read_index(filename)
	local arc_index = assert(io.open(filename, "rb"))
	local index = {}

	index.version = M.read_int(arc_index)
	arc_index:read(12) -- Padding
	index.entry_count = M.read_int(arc_index)
	index.entry_offset = M.read_int(arc_index)
	index.hash_offset = M.read_int(arc_index)
	index.hash_length = M.read_int(arc_index)

	index.entries = {}

	arc_index:seek("set", index.entry_offset)
	for i=0,index.entry_count-1 do
		local entry = {}
		entry.resource_offset = M.read_int(arc_index)
		entry.size = M.read_int(arc_index)
		entry.compressed_size = M.read_int(arc_index)
		entry.flags = M.read_int(arc_index)

		if entry.compressed_size == 0xFFFFFFFF then
			entry.compressed_size = entry.size
			entry.compressed = false
		else
			entry.compressed = true
		end

		-- Read hash
		local prev_index = arc_index:seek()
		arc_index:seek("set", (index.hash_offset + i * 64))
		entry.hash = M.read_hash(arc_index, index.hash_length)
		arc_index:seek("set", prev_index)

		table.insert(index.entries, entry)
	end

	return index
end

function M.write(bundle_dir, index, manifest, entries)
	local arcd = io.open(bundle_dir .. "/game.arcd", "wb")
	local arci = io.open(bundle_dir .. "/game.arci", "wb")
	local dman = io.open(bundle_dir .. "/game.dmanifest", "wb")

	arci:write(M.build_int(0)) -- Version
	arci:write(M.build_int(0)) -- Padding
	arci:write(M.build_long(0))
	arci:write(M.build_int(0)) -- Entry count
	arci:write(M.build_int(0)) -- Entry offset
	arci:write(M.build_int(0)) -- Hash length
	arci:write(M.build_int(index.hash_length))

	for i=#entries-1,0,-1 do
		entry = entries[i]
		if entry.compressed then
		end
	end
end

function M.read_compiled_files(path)
	local entries = {}

	M.dir_iter(path .. "/compiled", function(f)
		local e = {} -- New entry

		e.data = sio.read(utils.to_platform(f))
		e.size = #e.data
		e.url = f:gsub(path .. "/compiled", "") -- Convert from system path to project path

		table.insert(entries, e)
	end)
end

function M.read_manifest(filename)
	return pb.decode(".dmLiveUpdateDDF.ManifestFile", sio.read(filename))
end

function M.build_manifest(manifest)
	return pb.encode(".dmLiveUpdateDDF.ManifestFile", sio.read(filename))
end

function M.convert_hashes(manifest)
	for i,v in ipairs(manifest.data.resources) do
		v.hash.data = M.hex_string(v.hash.data)
		v.url_hash = string.format("%x", v.url_hash)
	end
	for i,v in ipairs(manifest.data.engine_versions) do
		v.data = M.hex_string(v.data)
	end
	return manifest
end

function M.get_entries(archive_data, index, manifest)
	local entries = {}

	for _,v in ipairs(index.entries) do
		local entry = v

		-- Get the URL from the manifest
		for _,w in ipairs(manifest.data.resources) do
			if entry.hash == w.hash.data then
				entry.url = w.url
				break
			end
		end

		-- Get the file data from the archive
		entry.data = archive_data:sub(entry.resource_offset + 1, entry.resource_offset + entry.compressed_size)

		table.insert(entries, entry)
	end

	return entries
end

return M