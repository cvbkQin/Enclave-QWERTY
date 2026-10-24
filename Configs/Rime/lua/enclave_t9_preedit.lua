-- 九宫格：拼写栏里显示候选词的拼音，而不是按下的数字。
-- 拼音来自 translator/spelling_hints 写进注释里的编码；常用词没有注释，从键盘写的 enclave_phrase_t9_pinyin.txt 里查。
local function load_phrase_pinyin()
  local map = {}
  local file = io.open(rime_api.get_user_data_dir() .. "/enclave_phrase_t9_pinyin.txt", "r")
  if file == nil then return map end
  for line in file:lines() do
    local text, pinyin = line:match("^(.-)\t(.+)$")
    if text ~= nil then map[text] = pinyin end
  end
  file:close()
  return map
end

return {
  init = function(env)
    env.phrase_pinyin = load_phrase_pinyin()
  end,
  func = function(input, env)
    for cand in input:iter() do
      local pinyin = cand.comment
      if pinyin == nil or pinyin == "" then
        pinyin = env.phrase_pinyin[cand.text]
      end
      if pinyin ~= nil and pinyin ~= "" then
        cand:get_genuine().preedit = pinyin
      end
      yield(cand)
    end
  end,
}
