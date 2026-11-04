-- boshiamy_processor.lua
-- 嘸蝦米指令與中英連打的按鍵處理（放在 recognizer 與 key_binder 之前）
--
-- 1. 組字以 ,, 開頭時接受大寫字母（,,T ,,CT ,,C ,,E）
-- 2. 空白鍵：
--    - 目前選中的是指令提示 → 執行指令並清掉組字（指令本身不上屏）
--    - 目前選中的是英文候選（代表沒有任何中文候選，即錯碼）→ 清掉組字，不送出英文
--      （英文候選要用點選或數字鍵選）
-- 3. 數字鍵選到指令提示 → 執行指令
-- 4. F35：App 點選指令提示時送來的鍵 → 執行目前組字對應的指令

local cmds = require("boshiamy_commands")

local kRejected, kAccepted, kNoop = 0, 1, 2
local XK_space, XK_F35 = 0x20, 0xffe0
local PAGE_SIZE = 10

local function selected_candidate(ctx)
  local ok, cand = pcall(function() return ctx:get_selected_candidate() end)
  if ok then return cand end
  return nil
end

local function candidate_at(ctx, index)
  local seg = ctx.composition:back()
  if not seg then return nil end
  local ok, cand = pcall(function() return seg:get_candidate_at(index) end)
  if ok then return cand end
  return nil
end

local function run_and_clear(ctx)
  local input = ctx.input
  ctx:clear()
  cmds.run(ctx, input)
end

local function processor(key, env)
  if key:release() or key:ctrl() or key:alt() or key:super() then return kNoop end
  local ctx = env.engine.context
  local kc = key.keycode

  -- 不在組字中：只處理 F35（保險起見，避免殘留）
  if not ctx:is_composing() then
    if kc == XK_F35 then return kAccepted end
    return kNoop
  end

  local input = ctx.input

  -- 1) ,, 開頭時收下大寫字母（不論是否帶 Shift 修飾）
  if input:sub(1, 2) == ",," and kc >= 0x41 and kc <= 0x5a then
    ctx:push_input(string.char(kc))
    return kAccepted
  end

  -- 4) App 點選指令提示
  if kc == XK_F35 then
    if cmds.lookup(input) then run_and_clear(ctx) end
    return kAccepted
  end

  -- 2) 空白鍵
  if kc == XK_space then
    local cand = selected_candidate(ctx)
    if cand and cand.type == cmds.CANDIDATE_TYPE then
      run_and_clear(ctx)
      return kAccepted
    end
    if cand and cand.type == "boshiamy_en" then
      ctx:clear()
      return kAccepted
    end
    return kNoop
  end

  -- 3) 數字鍵選字（alternative_select_keys: 0123456789，0 是第一個）
  if kc >= 0x30 and kc <= 0x39 then
    local seg = ctx.composition:back()
    if seg then
      local page_start = math.floor((seg.selected_index or 0) / PAGE_SIZE) * PAGE_SIZE
      local cand = candidate_at(ctx, page_start + (kc - 0x30))
      if cand and cand.type == cmds.CANDIDATE_TYPE then
        run_and_clear(ctx)
        return kAccepted
      end
    end
    return kNoop
  end

  return kNoop
end

return processor
