FILENAME_KEY = FILENAME_KEY or "filename"
OUTPUT_KEY = OUTPUT_KEY or "container_name"
CACHE_SIZE = CACHE_SIZE or 1024

-- 直接使用容器内的绝对路径加载辅助模块，避免依赖工作目录或 debug 库。
local new_lru = dofile("/fluent-bit/etc/script/lru.lua")
local filename_cache = new_lru(CACHE_SIZE)

local function extract_container_id(filename)
  if type(filename) ~= "string" then
    return nil
  end

  return string.match(filename, "/containers/([0-9a-f]+)/")
end

local function build_config_path(filename, container_id)
  if type(filename) ~= "string" or type(container_id) ~= "string" then
    return nil
  end

  local prefix = string.match(filename, "^(.*)/containers/" .. container_id .. "/")
  if prefix == nil then
    return nil
  end

  return prefix .. "/containers/" .. container_id .. "/config.v2.json"
end

local function read_file(path)
  if type(path) ~= "string" then
    return nil
  end

  local file = io.open(path, "r")
  if file == nil then
    return nil
  end

  local content = file:read("*a")
  file:close()

  return content
end

local function parse_container_name_from_config(config_content)
  if type(config_content) ~= "string" then
    return nil
  end

  local name = string.match(config_content, '"Name"%s*:%s*"([^"]+)"')
  if name == nil or name == "" then
    return nil
  end

  return (string.gsub(name, "^/", ""))
end

local function lookup_container_name(filename)
  -- Docker 会把容器元数据和 json 日志放在同级目录下，因此可以直接从
  -- 已采集的日志文件路径定位到对应的 config.v2.json，而不必调用 Docker API。
  local container_id = extract_container_id(filename)
  if container_id == nil then
    return nil
  end

  local config_path = build_config_path(filename, container_id)
  local config_content = read_file(config_path)
  if config_content == nil then
    return nil
  end

  return parse_container_name_from_config(config_content)
end

function extract_container_name(tag, timestamp, record)
  if type(record) ~= "table" then
    return 0, timestamp, record
  end

  local filename = record[FILENAME_KEY]
  if type(filename) ~= "string" or filename == "" then
    return 0, timestamp, record
  end

  -- 以日志文件路径作为缓存键，命中后可以直接 O(1) 返回容器名。
  local container_name = filename_cache.get(filename)
  if container_name == nil then
    container_name = lookup_container_name(filename)
    if container_name ~= nil and container_name ~= "" then
      filename_cache.put(filename, container_name)
    end
  end

  if container_name == nil or container_name == "" then
    return 0, timestamp, record
  end

  record[OUTPUT_KEY] = container_name
  return 2, timestamp, record
end
