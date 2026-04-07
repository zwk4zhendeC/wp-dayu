local function new_lru(capacity)
  local cache = {}
  local prev = {}
  local next = {}
  local head = nil
  local tail = nil
  local size = 0

  local function detach(key)
    local prev_key = prev[key]
    local next_key = next[key]

    if prev_key ~= nil then
      next[prev_key] = next_key
    else
      head = next_key
    end

    if next_key ~= nil then
      prev[next_key] = prev_key
    else
      tail = prev_key
    end

    prev[key] = nil
    next[key] = nil
  end

  local function attach_front(key)
    prev[key] = nil
    next[key] = head

    if head ~= nil then
      prev[head] = key
    end

    head = key

    if tail == nil then
      tail = key
    end
  end

  local function get(key)
    local value = cache[key]
    if value == nil then
      return nil
    end

    -- 每次命中都提升到链表头部，尾部始终表示最近最少使用的键。
    if head ~= key then
      detach(key)
      attach_front(key)
    end

    return value
  end

  local function put(key, value)
    if cache[key] ~= nil then
      cache[key] = value
      if head ~= key then
        detach(key)
        attach_front(key)
      end
      return
    end

    cache[key] = value
    attach_front(key)
    size = size + 1

    if size <= capacity then
      return
    end

    -- 超过容量后，淘汰链表尾部那个最近最少使用的键。
    local evict = tail
    if evict ~= nil then
      detach(evict)
      cache[evict] = nil
      size = size - 1
    end
  end

  return {
    get = get,
    put = put,
  }
end

return new_lru
