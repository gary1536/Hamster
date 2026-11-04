-- boshiamy_translator.lua
-- 1. 指令提示候選：組字是 ,,T ,,CT ,,C ,,E 時，顯示「進入打繁出簡模式」等提示
--    （type = boshiamy_cmd，comment = 〔指令〕，選它會執行指令而不是上屏）
-- 2. 中英連打：選項 boshiamy_en_off 為 false（預設）、組字全是英文字母時，附上英文原文候選
--    （type = boshiamy_en），品質設得很低，永遠排在所有中文候選之後

local cmds = require("boshiamy_commands")

local function translator(input, seg, env)
  local ctx = env.engine.context

  local cmd = cmds.lookup(input)
  if cmd then
    local cand = Candidate(cmds.CANDIDATE_TYPE, seg.start, seg._end, cmd.label(ctx), cmds.CANDIDATE_COMMENT)
    -- 大寫指令（真正的嘸蝦米寫法）排第一；小寫 ,,c 會和「《」同碼，排在後面
    cand.quality = cmds.is_explicit(input) and 1000 or -1000
    yield(cand)
    return
  end

  if not ctx:get_option(cmds.OPTION_ENGLISH_OFF) and input:match("^[a-z]+$") then
    local cand = Candidate("boshiamy_en", seg.start, seg._end, input, "")
    cand.quality = -10000
    cand.preedit = input
    yield(cand)
  end
end

return translator
