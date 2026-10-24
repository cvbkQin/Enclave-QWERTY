-- 九宫格：拼写栏里显示候选词的拼音，而不是按下的数字。
-- 拼音来自 translator/spelling_hints 写进注释里的编码。
return function(input)
  for cand in input:iter() do
    local pinyin = cand.comment
    if pinyin ~= nil and pinyin ~= "" then
      cand:get_genuine().preedit = pinyin
    end
    yield(cand)
  end
end
