-- 九宫格：把分段选过的词告诉键盘（写在 context 的属性里，键盘用 get_property 读）。
-- enclave_selected：每个选定的段一行「结束位置<Tab>文字」，位置是原始输入里的字节下标。
-- 键盘靠它知道拼音栏该从哪里接着选，选拼音重输后把选过的词再选回来。
local function selected(context)
  local lines = {}
  local composition = context.composition
  if composition:empty() then return "" end
  local segmentation = composition:toSegmentation()
  for i = 0, segmentation.size - 1 do
    local segment = segmentation:get_at(i)
    if segment.status == "kSelected" or segment.status == "kConfirmed" then
      local cand = segment:get_selected_candidate()
      if cand == nil then break end
      lines[#lines + 1] = tostring(segment._end) .. "\t" .. cand.text
    else
      break
    end
  end
  return table.concat(lines, "\n")
end

return {
  init = function(env)
    local function update(ctx)
      local value = selected(ctx)
      if ctx:get_property("enclave_selected") ~= value then
        ctx:set_property("enclave_selected", value)
      end
    end
    local context = env.engine.context
    -- 打字、删除时发 update，选词只发 select。
    env.connections = {
      context.update_notifier:connect(update),
      context.select_notifier:connect(update),
    }
  end,
  func = function(key, env)
    return 2 -- kNoop：不处理按键
  end,
  fini = function(env)
    for _, connection in ipairs(env.connections or {}) do connection:disconnect() end
  end,
}
