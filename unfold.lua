local M = {}

-- Modules
local Array = require("array")
local sio = require("sio")
local utils = require("utils")
local ddf = require("ddf.ddf")
local protoc = require("pb.protoc")

-- Set up protoc -----------------
protoc.unknown_module = ""
protoc.unknown_type = ""
protoc.include_imports = true
function protoc:unknown_import(module_name)
	return protoc:parsefile("/proto/" .. M.current_engine_hash .. "/" .. module_name)
end
protoc:load(sys.load_resource("/ddf/proto/ddf.proto"))
protoc:load(sys.load_resource("/proto/resource/liveupdate_ddf.proto"))
protoc:load(sys.load_resource("/proto/gamesys/texture_set_ddf.proto"))
----------------------------------


-- Helper functions --------------
local ENGINE_VERSIONS = Array(json.decode(sys.load_resource("/defold_versions.json")))
function M.get_engine_version(exe_path)
	local bytes = sio.read(exe_path)
	return ENGINE_VERSIONS:find(function(version) return bytes:find(version.sha) end)
end

function M.latest_engine_version()
	return ENGINE_VERSIONS[1]
end

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

-- Convert hashes to human-readable format
function M.convert_hashes(manifest)
	for i,v in ipairs(manifest.data.resources) do
		v.hash.data = M.hex_string(v.hash.data)
		v.url_hash = string.format("%x", v.url_hash)
	end
	for i,v in ipairs(manifest.data.engine_versions) do
		v.data = M.hex_string(v.data)
	end
	manifest.data.header.project_identifier = M.hex_string(manifest.data.header.project_identifier.data)
	return manifest
end
----------------------------------


-- Main functions ----------------
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

-- WIP import functions, needs LZ4 NE -----------
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

	utils.dir_iter(path .. "/compiled", function(f)
		local e = {} -- New entry

		e.data = sio.read(utils.to_platform(f))
		e.size = #e.data
		e.url = f:gsub(path .. "/compiled", "") -- Convert from system path to project path

		table.insert(entries, e)
	end)
end
---------------------------------

function M.read_manifest(filename)
	return pb.decode(".dmLiveUpdateDDF.ManifestFile", sio.read(filename))
end

function M.build_manifest(manifest)
	return pb.encode(".dmLiveUpdateDDF.ManifestFile", sio.read(filename))
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
		if entry.compressed and entry.flags % 2 == 0 then -- Don't try to decompress encrypted files
			entry.data = lz4.block_decompress_safe(entry.data, entry.size)
		end

		table.insert(entries, entry)
	end

	return entries
end

local function safe_decode(ddf_type, data)
	local success, v = pcall(pb.decode, ddf_type, data)
	if success then
		return json.encode(v)
	else
		print("Error decoding file of type " .. ddf_type .. ":\n" .. v)
	end
end

local function fix_collection(collection)
	if collection.instances then
		for i,instance in ipairs(collection.instances) do
			if instance.component_properties then
				for _,property in ipairs(instance.component_properties) do
					property.property_decls = nil
				end
			end

			-- Remove leading /
			instance.id = instance.id:sub(2)
		end
	end
	return collection
end

local function fix_go(go)
	if go.components then
		for _,component in ipairs(go.components) do
			component.property_decls = nil

			if component.component:sub(-6) == "script" and component.properties then
				local properties = {}
				for _,property in ipairs(component.properties) do
					properties[property.id] = property
				end
			end
		end
	end
	return go
end

local ddf_types = {
	animationset = "dmRigDDF.AnimationSet",
	camera = "dmGamesysDDF.CameraDesc",
	collection = function(collection)
		return ddf.encode_collection(fix_collection(pb.decode("dmGameObjectDDF.CollectionDesc", collection)))
	end,
	collectionfactory = "dmGameSystemDDF.CollectionFactoryDesc",
	collectionproxy = "dmGameSystemDDF.CollectionProxyDesc",
	collisionobject = "dmPhysicsDDF.CollisionObjectDesc",
	cubemap = "dmGraphics.Cubemap",
	display_profiles = "dmRenderDDF.DisplayProfiles",
	factory = "dmGameSystemDDF.FactoryDesc",
	--font = "dmRenderDDF.FontDesc",
	go = "dmGameObjectDDF.PrototypeDesc",
	gui = "dmGuiDDF.SceneDesc",
	input_binding = "dmInputDDF.InputBinding",
	label = "dmGameSystemDDF.LabelDesc",
	light = "dmGameSystemDDF.LightDesc",
	material = "dmRenderDDF.MaterialDesc",
	particlefx = "dmParticleDDF.ParticleFX",
	render = "dmRenderDDF.RenderPrototypeDesc",
	sound = "dmSoundDDF.SoundDesc",
	spinemodel = "dmGameSystemDDF.SpineModelDesc",
	spinescene = "dmGameSystemDDF.SpineSceneDesc",
	sprite = "dmGameSystemDDF.SpriteDesc",
	texture_profiles = "dmGraphics.TextureProfiles",
	tilemap = "dmGameSystemDDF.TileGrid",
}

local function fix_dependency_paths(contents)
	return contents:gsub(': "/.-c"', function(s)
		return s:sub(1,-3) .. '"'
	end)
end

local function decode_file(contents, file_extension)
	local file_type = ddf_types[file_extension]
	local type_type = type(file_type)

	local decoded
	if type_type == "string" then
		decoded = ddf["encode_" .. file_extension](pb.decode(file_type, contents))
	elseif type_type == "function" then
		decoded = file_type(contents)
	end

	if decoded then
		return fix_dependency_paths(decoded)
	end
end

function M.decompile_files(entries, out_path)
	for _,e in ipairs(entries) do
		local ext = utils.get_extension(e.url):sub(1,-2)
		local output = decode_file(e.data, ext) or e.data

		if output then
			local path = out_path .. "/decompiled" .. e.url:sub(1,-2)
			utils.mkdir(utils.enclosing_folder(path))
			sio.write(path, output)
		end
	end

	sio.write(out_path .. "/decompiled/game.project", sio.read(out_path .. "/compiled/game.projectc"))
end

return M
